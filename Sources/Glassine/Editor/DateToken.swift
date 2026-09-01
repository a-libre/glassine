import AppKit

/// Date tokens: `@today`, `@yesterday` and `@tomorrow` expand as you type into
/// `@September 1, 2026`, which stays readable in any Markdown app and which
/// Glassine draws as a small capsule. ISO dates (`@2026-09-01`) get the capsule too.
enum DateToken {
    static let attributeKey = NSAttributedString.Key("glassine.dateToken")

    /// Matches a stored token: `@September 1, 2026` or `@2026-09-01`.
    static let pattern = "@(?:\\d{4}-\\d{2}-\\d{2}|(?:January|February|March|April|May|June|July|August|September|October|November|December) \\d{1,2}, \\d{4})(?![\\w])"

    /// Matches a shortcut word right before the caret.
    static let shortcutRegex = try! NSRegularExpression(pattern: "(?:^|(?<=[\\s(\\[]))@(today|yesterday|tomorrow)$", options: [.caseInsensitive])

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    static func format(_ date: Date) -> String { formatter.string(from: date) }

    /// The date a shortcut word stands for.
    static func date(for word: String) -> Date? {
        let offset: Int
        switch word.lowercased() {
        case "today": offset = 0
        case "tomorrow": offset = 1
        case "yesterday": offset = -1
        default: return nil
        }
        return Calendar.current.date(byAdding: .day, value: offset, to: Date())
    }
}

/// Draws rounded backgrounds — capsules for date tokens, softly rounded rectangles
/// for inline code — and the strikethrough of finished tasks as a gradient.
/// Everything else is inherited.
final class GlassineLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        let isDate = charRange.location < (textStorage?.length ?? 0)
            && textStorage?.attribute(DateToken.attributeKey, at: charRange.location, effectiveRange: nil) != nil
        color.setFill()
        for i in 0..<rectCount {
            var rect = rectArray[i]
            if isDate {
                // A capsule lit from the top, with a hairline edge: enough to read as a chip.
                rect = rect.insetBy(dx: -4, dy: -1.5)
                let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
                let alpha = color.alphaComponent
                if let gradient = NSGradient(starting: color.withAlphaComponent(min(1, alpha * 1.5)),
                                             ending: color.withAlphaComponent(alpha * 0.8)) {
                    gradient.draw(in: path, angle: 90)
                } else {
                    path.fill()
                }
                color.withAlphaComponent(min(1, alpha * 1.1)).setStroke()
                let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2)
                edge.lineWidth = 1
                edge.stroke()
                color.setFill()
            } else {
                rect = rect.insetBy(dx: -1, dy: 0)
                NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5).fill()
            }
        }
    }

    /// Finished tasks: one strike per line, fading from the accent to the muted text colour.
    override func drawStrikethrough(forGlyphRange glyphRange: NSRange, strikethroughType: NSUnderlineStyle,
                                    baselineOffset: CGFloat, lineFragmentRect lineRect: NSRect,
                                    lineFragmentGlyphRange lineGlyphRange: NSRange, containerOrigin: NSPoint) {
        let charIndex = characterIndexForGlyph(at: glyphRange.location)
        var doneRange = NSRange(location: 0, length: 0)
        guard let storage = textStorage, charIndex < storage.length,
              let colors = storage.attribute(TaskBox.doneKey, at: charIndex, longestEffectiveRange: &doneRange,
                                             in: NSRange(location: 0, length: storage.length)) as? [NSColor],
              colors.count == 2,
              let gradient = NSGradient(starting: colors[0], ending: colors[1]),
              let container = textContainer(forGlyphAt: glyphRange.location, effectiveRange: nil) else {
            super.drawStrikethrough(forGlyphRange: glyphRange, strikethroughType: strikethroughType,
                                    baselineOffset: baselineOffset, lineFragmentRect: lineRect,
                                    lineFragmentGlyphRange: lineGlyphRange, containerOrigin: containerOrigin)
            return
        }
        // The gradient spans the whole struck text on this line, so a bold word or a
        // link in the middle (separate runs) does not restart it.
        let doneGlyphs = self.glyphRange(forCharacterRange: doneRange, actualCharacterRange: nil)
        let lineDone = NSIntersectionRange(doneGlyphs, lineGlyphRange)
        guard lineDone.length > 0 else { return }
        let extent = boundingRect(forGlyphRange: lineDone, in: container).offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
        let run = boundingRect(forGlyphRange: glyphRange, in: container).offsetBy(dx: containerOrigin.x, dy: containerOrigin.y)
        let font = storage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 16)
        let thickness: CGFloat = font.pointSize >= 24 ? 1.5 : 1
        // The glyph location's y is the baseline, measured from the top of the line fragment.
        let baseline = lineRect.minY + containerOrigin.y + location(forGlyphAt: glyphRange.location).y
        let y = (baseline - font.xHeight * 0.55).rounded() - thickness / 2
        let band = NSRect(x: extent.minX, y: y, width: extent.width, height: thickness)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: run.minX, y: y - 1, width: run.width, height: thickness + 2)).addClip()
        gradient.draw(in: band, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }
}
