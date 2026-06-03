import AppKit
import SwiftUI

/// NSViewRepresentable wrapping an NSTextView for pixel-precise teleprompter scrolling.
///
/// Renders the full script as an attributed string, builds a word-to-pixel position
/// lookup table, and scrolls to exact pixel offsets driven by the engine's scroll position.
struct PrompterTextView: NSViewRepresentable {
    let sections: [ScriptSection]
    let scrollPosition: Double
    let totalWords: Int
    let settings: AppSettings
    let viewportHeight: CGFloat

    typealias Coordinator = PrompterTextCoordinator

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = PrompterScrollView()
        scrollView.coordinator = context.coordinator
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = .init(top: 0, left: 0, bottom: 0, right: 0)

        // Build text system with custom layout manager for soft highlights
        let textStorage = NSTextStorage()
        let layoutManager = PrompterLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 32, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.alignment = .center

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator

        // Rebuild attributed string if content changed OR scroll view width changed
        // (first layout pass has width=0; we need to rebuild once the real width arrives)
        let contentKey = sections.map(\.text).joined()
        let currentWidth = scrollView.contentView.bounds.width
        let widthChanged = currentWidth > 0 && abs(currentWidth - coordinator.lastLayoutWidth) > 10
        if coordinator.lastContentKey != contentKey || coordinator.lastFontSize != settings.fontSize
            || widthChanged
        {
            coordinator.lastContentKey = contentKey
            coordinator.lastFontSize = settings.fontSize
            coordinator.lastLayoutWidth = currentWidth
            rebuildContent(coordinator: coordinator)
        }

        // Update viewport height for centering calculation
        coordinator.viewportHeight = viewportHeight

        // Update target position — the display link interpolates smoothly toward it
        coordinator.targetScrollPosition = scrollPosition
        coordinator.targetTotalWords = totalWords
        coordinator.startDisplayLink()
    }

    func makeCoordinator() -> PrompterTextCoordinator {
        PrompterTextCoordinator()
    }

    // MARK: - Content Building

    private func rebuildContent(coordinator: PrompterTextCoordinator) {
        guard let textView = coordinator.textView else { return }

        let fullAttributed = NSMutableAttributedString()
        let baseFont = CueFont.prompterFont(name: settings.fontName, size: settings.fontSize)
        let titleFont: NSFont = {
            let size = settings.fontSize * 1.3
            if settings.fontName == "New York",
                let desc = NSFontDescriptor.preferredFontDescriptor(forTextStyle: .body)
                    .withDesign(.serif)?.withSymbolicTraits(.bold)
            {
                return NSFont(descriptor: desc, size: size)
                    ?? NSFont.systemFont(ofSize: size, weight: .bold)
            }
            return NSFont(name: settings.fontName, size: size)
                ?? NSFont.systemFont(ofSize: size, weight: .bold)
        }()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = settings.lineSpacing * 4

        let sectionSpacing = NSMutableParagraphStyle()
        sectionSpacing.alignment = .center
        sectionSpacing.paragraphSpacingBefore = settings.lineSpacing * 10
        sectionSpacing.lineSpacing = settings.lineSpacing * 4

        // Subtle drop shadow on all text for depth
        let textShadow = NSShadow()
        textShadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        textShadow.shadowOffset = NSSize(width: 0, height: -1)
        textShadow.shadowBlurRadius = 4

        var wordPositions: [Int] = []  // character index of each word start
        var wordLengths: [Int] = []  // character length of each word

        for (sectionIdx, section) in sections.enumerated() {
            let style = sectionIdx == 0 ? paragraphStyle : sectionSpacing

            // Section title
            if let title = section.title, !title.isEmpty {
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: titleFont,
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: style,
                    .shadow: textShadow,
                ]
                let titleStr = NSAttributedString(string: title + "\n", attributes: titleAttrs)
                let titleWords = title.components(separatedBy: .whitespacesAndNewlines).filter {
                    !$0.isEmpty
                }
                var titleSearchStart = title.startIndex
                for word in titleWords {
                    if let range = title.range(of: word, range: titleSearchStart..<title.endIndex) {
                        let charOffset = title.distance(
                            from: title.startIndex, to: range.lowerBound)
                        wordPositions.append(fullAttributed.length + charOffset)
                        wordLengths.append(word.count)
                        titleSearchStart = range.upperBound
                    } else {
                        wordPositions.append(fullAttributed.length)
                        wordLengths.append(word.count)
                    }
                }
                fullAttributed.append(titleStr)
            }

            // Section body — render inline markdown (bold/italic)
            let bodyText = section.text
            let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            let renderedBody = MarkdownRenderer.render(
                bodyText,
                baseFont: baseFont,
                boldFont: boldFont,
                italicFont: italicFont,
                color: NSColor.white,
                paragraphStyle: style,
                shadow: textShadow
            )

            // Track word positions in the rendered (clean) text
            let renderedString = renderedBody.string
            let cleanWords = renderedString.components(separatedBy: .whitespacesAndNewlines).filter
            { !$0.isEmpty }
            let bodyStart = fullAttributed.length
            var bodySearchStart = renderedString.startIndex
            for word in cleanWords {
                if let range = renderedString.range(
                    of: word, range: bodySearchStart..<renderedString.endIndex)
                {
                    let charOffset = renderedString.distance(
                        from: renderedString.startIndex, to: range.lowerBound)
                    wordPositions.append(bodyStart + charOffset)
                    wordLengths.append(word.count)
                    bodySearchStart = range.upperBound
                } else {
                    wordPositions.append(bodyStart)
                    wordLengths.append(word.count)
                }
            }

            fullAttributed.append(renderedBody)
            fullAttributed.append(
                NSAttributedString(
                    string: "\n\n",
                    attributes: [
                        .font: baseFont,
                        .foregroundColor: NSColor.white,
                        .paragraphStyle: style,
                    ]))
        }

        // Add top/bottom padding so text can scroll to center at start/end
        let paddingHeight = max(viewportHeight / 2.0, 200)
        let paddingStr = NSAttributedString(
            string: "\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: paddingHeight / 4),
                .foregroundColor: NSColor.clear,
            ])
        let paddedContent = NSMutableAttributedString()
        paddedContent.append(paddingStr)
        paddedContent.append(fullAttributed)
        paddedContent.append(paddingStr)

        // Offset word positions by padding length
        let paddingLen = paddingStr.length
        coordinator.wordCharPositions = wordPositions.map { $0 + paddingLen }
        coordinator.wordCharLengths = wordLengths

        textView.textStorage?.setAttributedString(paddedContent)
        let svWidth = coordinator.scrollView?.contentView.bounds.width ?? 0
        if svWidth > 0 { textView.setFrameSize(NSSize(width: svWidth, height: 0)) }

        // Ensure text container width matches so layout wraps correctly
        if let tc = textView.textContainer, svWidth > 0 {
            let insetW = textView.textContainerInset.width
            tc.size = NSSize(width: svWidth - insetW * 2, height: .greatestFiniteMagnitude)
        }

        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        // Set frame to full content height so the scroll view knows the document is scrollable.
        if let lm = textView.layoutManager, let tc = textView.textContainer {
            let fullRange = lm.glyphRange(for: tc)
            let contentRect = lm.boundingRect(forGlyphRange: fullRange, in: tc)
            let inset = textView.textContainerInset
            let fullHeight = contentRect.height + inset.height * 2
            textView.setFrameSize(NSSize(width: textView.frame.width, height: fullHeight))
            textView.minSize = NSSize(width: 0, height: fullHeight)
        }

        // Build pixel position lookup after layout
        coordinator.buildWordPixelMap()
    }
}
