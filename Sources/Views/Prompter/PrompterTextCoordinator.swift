import AppKit

/// Coordinator for PrompterTextView — manages smooth scrolling,
/// animated word highlighting, and the word-to-pixel position lookup table.
final class PrompterTextCoordinator {
    var textView: NSTextView?
    var scrollView: NSScrollView?
    var lastContentKey: String = ""
    var lastFontSize: Double = 0
    var lastLayoutWidth: CGFloat = 0
    var viewportHeight: CGFloat = 400

    /// Character index of each word start in the text storage.
    var wordCharPositions: [Int] = []

    /// Character length of each word.
    var wordCharLengths: [Int] = []

    /// Y pixel offset of each word (built once after layout).
    var wordPixelY: [CGFloat] = []

    /// Total content height.
    var contentHeight: CGFloat = 0

    /// Current displayed scroll offset (for smooth interpolation toward speech target).
    private var displayedOffset: CGFloat = 0

    /// Additional pixel offset applied by user scroll, on top of speech-driven position.
    /// Decays back to zero so speech eventually re-centers the Q word.
    private var userScrollOffset: CGFloat = 0

    /// Currently highlighted word index.
    private var highlightedWordIndex: Int = -1

    /// Target scroll position from engine (fractional word index).
    var targetScrollPosition: Double = 0
    var targetTotalWords: Int = 0

    /// Timer for smooth interpolation (~60fps).
    private var displayLink: Timer?

    /// Whether the interpolation timer is currently scheduled.
    var isDisplayLinkRunning: Bool { displayLink != nil }

    func startDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak self] _ in
            self?.interpolateScroll()
        }
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func interpolateScroll() {
        let pos = targetScrollPosition
        updateHighlight(for: pos)
        // Small look-ahead so upcoming text past section breaks stays visible
        let scrollTarget = min(pos + 2.0, Double(max(0, wordCharPositions.count - 1)))
        scrollToWord(at: scrollTarget)
    }

    deinit {
        stopDisplayLink()
    }

    // MARK: - User Scroll

    /// Called by PrompterScrollView when the user scrolls with trackpad/mouse.
    /// Shifts the viewport without touching the engine or Q word.
    func handleScrollWheel(deltaY: CGFloat) {
        guard let scrollView else { return }
        let docHeight = scrollView.documentView?.frame.height ?? 0
        let vpHeight = scrollView.contentView.bounds.height
        let maxScroll = max(0, docHeight - vpHeight)

        userScrollOffset = (userScrollOffset - deltaY).clamped(to: -maxScroll...maxScroll)

        // Apply immediately so the scroll feels instant
        let base = displayedOffset - userScrollOffset  // speech-only position
        let combined = (base + userScrollOffset).clamped(to: 0...maxScroll)
        displayedOffset = combined
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: displayedOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Word Highlight

    /// Highlight the current word. Visual expansion is handled by PrompterLayoutManager.
    func updateHighlight(for position: Double) {
        guard let textView = textView,
            let layoutManager = textView.layoutManager,
            !wordCharPositions.isEmpty
        else { return }

        let wordIndex = max(0, min(Int(position), wordCharPositions.count - 1))
        guard wordIndex != highlightedWordIndex, wordIndex < wordCharPositions.count else { return }

        let storage = textView.textStorage!
        let color = CueColors.accentNS.withAlphaComponent(0.25)

        // Remove old highlight and invalidate its glow region
        if highlightedWordIndex >= 0 && highlightedWordIndex < wordCharPositions.count {
            let oldPos = wordCharPositions[highlightedWordIndex]
            let oldLen = min(wordCharLengths[highlightedWordIndex], max(0, storage.length - oldPos))
            if oldPos < storage.length && oldLen > 0 {
                let oldRange = NSRange(location: oldPos, length: oldLen)
                layoutManager.removeTemporaryAttribute(
                    .backgroundColor, forCharacterRange: oldRange)
                if let dirtyRect = glowDirtyRect(for: oldRange) {
                    textView.setNeedsDisplay(dirtyRect)
                }
            }
        }

        // Apply new highlight (exact word range — layout manager expands visually)
        let charPos = wordCharPositions[wordIndex]
        let charLen = min(wordCharLengths[wordIndex], storage.length - charPos)
        if charLen > 0 {
            let newRange = NSRange(location: charPos, length: charLen)
            layoutManager.addTemporaryAttribute(
                .backgroundColor, value: color, forCharacterRange: newRange)
            if let dirtyRect = glowDirtyRect(for: newRange) {
                textView.setNeedsDisplay(dirtyRect)
            }
        }

        highlightedWordIndex = wordIndex
    }

    /// Compute the view-coordinate rect covering a word's glyphs plus the glow expansion.
    private func glowDirtyRect(for charRange: NSRange) -> NSRect? {
        guard let textView = textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return nil }
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: charRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let origin = textView.textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        let margin = PrompterLayoutManager.glowExtent + 1.0
        return rect.insetBy(dx: -margin, dy: -margin)
    }

    // MARK: - Layout

    /// Build the word-to-pixel lookup table from the laid-out text.
    func buildWordPixelMap() {
        guard let textView = textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else { return }

        wordPixelY = []
        let textStorage = textView.textStorage!

        for charPos in wordCharPositions {
            let clampedPos = min(charPos, textStorage.length - 1)
            guard clampedPos >= 0 else {
                wordPixelY.append(0)
                continue
            }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedPos)
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex, effectiveRange: nil)
            wordPixelY.append(lineRect.origin.y)
        }

        // Total content height
        let fullRange = layoutManager.glyphRange(for: textContainer)
        let bounds = layoutManager.boundingRect(forGlyphRange: fullRange, in: textContainer)
        contentHeight = bounds.height

        highlightedWordIndex = -1
    }

    // MARK: - Scrolling

    /// Smoothly scroll so the current word is centered in the viewport.
    func scrollToWord(at position: Double) {
        guard let textView = textView,
            let scrollView = scrollView,
            let layoutManager = textView.layoutManager,
            !wordCharPositions.isEmpty
        else { return }

        let wordIndex = max(0, min(Int(position), wordCharPositions.count - 1))
        let charPos = wordCharPositions[wordIndex]
        let storage = textView.textStorage!
        let clampedPos = min(charPos, storage.length - 1)
        guard clampedPos >= 0 else { return }

        // Get the Y position of this word via the layout manager
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: clampedPos)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let wordY = lineRect.origin.y + textView.textContainerInset.height

        // Target: put this word slightly above center so upcoming text is visible below
        let vpHeight = scrollView.contentView.bounds.height
        let speechTarget = wordY - vpHeight * 0.35 + lineRect.height / 2.0

        // Clamp to valid scroll range
        let docHeight = scrollView.documentView?.frame.height ?? 0
        let maxScroll = max(0, docHeight - vpHeight)
        let clampedTarget = max(0, min(speechTarget + userScrollOffset, maxScroll))

        // Decay userScrollOffset toward zero so speech gradually re-centers
        userScrollOffset *= 0.97

        // Smooth interpolation
        let alpha: CGFloat = 0.10
        displayedOffset += (clampedTarget - displayedOffset) * alpha
        if abs(clampedTarget - displayedOffset) < 0.5 {
            displayedOffset = clampedTarget
        }

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: displayedOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

/// NSScrollView subclass that forwards scroll wheel events to the coordinator.
final class PrompterScrollView: NSScrollView {
    weak var coordinator: PrompterTextCoordinator?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        if abs(delta) > 0 {
            coordinator?.handleScrollWheel(deltaY: delta)
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
