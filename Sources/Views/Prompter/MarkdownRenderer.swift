import AppKit

/// Parses inline markdown (**bold**, *italic*) into an NSAttributedString.
/// Strips the markdown syntax characters so the display text is clean.
enum MarkdownRenderer {

    static func render(
        _ text: String,
        baseFont: NSFont,
        boldFont: NSFont,
        italicFont: NSFont,
        color: NSColor,
        paragraphStyle: NSParagraphStyle,
        shadow: NSShadow? = nil
    ) -> NSMutableAttributedString {
        var baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]
        if let shadow { baseAttrs[.shadow] = shadow }

        let result = NSMutableAttributedString()
        var remaining = text[text.startIndex..<text.endIndex]

        while !remaining.isEmpty {
            // Look for **bold**
            if let boldStart = remaining.range(of: "**") {
                let before = String(remaining[remaining.startIndex..<boldStart.lowerBound])
                result.append(NSAttributedString(string: before, attributes: baseAttrs))

                let afterMarker = remaining[boldStart.upperBound...]
                if let boldEnd = afterMarker.range(of: "**") {
                    let boldText = String(afterMarker[afterMarker.startIndex..<boldEnd.lowerBound])
                    var boldAttrs = baseAttrs
                    boldAttrs[.font] = boldFont
                    result.append(NSAttributedString(string: boldText, attributes: boldAttrs))
                    remaining = remaining[boldEnd.upperBound...]
                } else {
                    result.append(NSAttributedString(string: "**", attributes: baseAttrs))
                    remaining = afterMarker
                }
            }
            // Look for *italic*
            else if let italicStart = remaining.range(of: "*") {
                let before = String(remaining[remaining.startIndex..<italicStart.lowerBound])
                result.append(NSAttributedString(string: before, attributes: baseAttrs))

                let afterMarker = remaining[italicStart.upperBound...]
                if let italicEnd = afterMarker.range(of: "*") {
                    let italicText = String(afterMarker[afterMarker.startIndex..<italicEnd.lowerBound])
                    var itAttrs = baseAttrs
                    itAttrs[.font] = italicFont
                    result.append(NSAttributedString(string: italicText, attributes: itAttrs))
                    remaining = remaining[italicEnd.upperBound...]
                } else {
                    result.append(NSAttributedString(string: "*", attributes: baseAttrs))
                    remaining = afterMarker
                }
            } else {
                result.append(NSAttributedString(string: String(remaining), attributes: baseAttrs))
                break
            }
        }

        return result
    }
}
