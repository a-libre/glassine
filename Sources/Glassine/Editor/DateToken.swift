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
    /// Strikes still being drawn in, by the character index where the struck
    /// text begins: how far across it the line has got, 0 to 1.
    var strikeProgress: [Int: CGFloat] = [:]
    /// Strikes fading with their line, by the same key: the alpha to draw at.
    var strikeAlpha: [Int: CGFloat] = [:]

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        guard rectCount > 0 else { return }
        // Copy these out before asking the layout manager anything else: the
        // buffer they live in is shared, and the queries below write into it.
        let rects = (0..<rectCount).map { rectArray[$0] }
        var tokenRange = NSRange(location: 0, length: 0)
        let isDate = textStorage.map { charRange.location < $0.length
            && $0.attribute(DateToken.attributeKey, at: charRange.location, longestEffectiveRange: &tokenRange,
                            in: NSRange(location: 0, length: $0.length)) != nil } ?? false
        color.setFill()
        guard isDate else {
            for rect in rects {
                NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: 0), xRadius: 3.5, yRadius: 3.5).fill()
            }
            return
        }

        // A date token can come through here in more than one run — the "@" is
        // dimmer than the date, so it can be a run of its own — and each would
        // get a capsule. The first run draws the whole token; the rest draw nothing.
        guard charRange.location == tokenRange.location else { return }
        var capsules = rects
        if charRange.length < tokenRange.length,
           let container = textContainer(forGlyphAt: glyphIndexForCharacter(at: charRange.location), effectiveRange: nil) {
            let none = NSRange(location: NSNotFound, length: 0)
            var n = 0
            let runFirst = self.rectArray(forCharacterRange: charRange, withinSelectedCharacterRange: none,
                                          in: container, rectCount: &n).flatMap { n > 0 ? $0[0] : nil }
            let token = self.rectArray(forCharacterRange: tokenRange, withinSelectedCharacterRange: none,
                                       in: container, rectCount: &n).map { p in (0..<n).map { p[$0] } } ?? []
            // Those are container coordinates; the run's own first rect, which we
            // hold in both systems, says how far the view has moved them.
            if let runFirst, !token.isEmpty {
                let dx = rects[0].minX - runFirst.minX, dy = rects[0].minY - runFirst.minY
                capsules = token.map { $0.offsetBy(dx: dx, dy: dy) }
            }
        }
        for var rect in capsules {
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
        var band = NSRect(x: extent.minX, y: y, width: extent.width, height: thickness)
        if let p = strikeProgress[doneRange.location] {
            // The sweep runs over the whole struck text, glyph by glyph; this
            // line draws its share of wherever the front has got to.
            let front = CGFloat(doneGlyphs.location) + p * CGFloat(doneGlyphs.length)
            let a = CGFloat(lineDone.location), b = CGFloat(lineDone.upperBoundValue)
            let share = max(0, min(1, (front - a) / max(1, b - a)))
            guard share > 0 else { return }
            band.size.width = extent.width * share
        }

        NSGraphicsContext.saveGraphicsState()
        if let alpha = strikeAlpha[doneRange.location] { NSGraphicsContext.current?.cgContext.setAlpha(alpha) }
        NSBezierPath(rect: NSRect(x: run.minX, y: y - 1, width: run.width, height: thickness + 2)).addClip()
        gradient.draw(in: band, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
    }
}
