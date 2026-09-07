import AppKit

/// Date tokens: `@today`, `@yesterday` and `@tomorrow` expand as you type into
/// `@September 1, 2026`, which stays readable in any Markdown app and which
/// Glassine draws as a small capsule. ISO dates (`@2026-09-01`) get the capsule too.
enum DateToken {
    static let attributeKey = NSAttributedString.Key("glassine.dateToken")
    /// How far a capsule reaches beyond its glyphs on each side. The styler
    /// kerns the spaces on either side by the same amount, so the capsule's
    /// edge — not the word inside it — stands a space clear of its neighbours.
    static let capsulePadding: CGFloat = 4

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

        // A token can come through here in more than one run — the "@" is dimmer
        // than the date, a chip's marks dimmer than its word — and each would get
        // a capsule. The run holding the token's first drawn glyph draws the whole
        // token; the rest draw nothing.
        // The glyph range can reach a glyph past the token's characters (a
        // kerned space before it, say), so each glyph is checked against them.
        let glyphs = glyphRange(forCharacterRange: tokenRange, actualCharacterRange: nil)
        func drawn(_ g: Int) -> Bool {
            guard NSLocationInRange(characterIndexForGlyph(at: g), tokenRange) else { return false }
            let property = propertyForGlyph(at: g)
            return property != .null && property != .controlCharacter
        }
        guard let firstDrawn = (glyphs.location..<glyphs.upperBoundValue).first(where: drawn),
              NSLocationInRange(characterIndexForGlyph(at: firstDrawn), charRange) else { return }
        // The capsule follows the token's drawn glyphs, line by line. A marker
        // that is not drawn takes no room in it, and a token that wraps — or
        // whose hidden marks are left behind at the end of a line — gets a
        // capsule around what it shows on each line and nothing where it
        // shows nothing: never the empty remainder of the line it left.
        var capsules: [NSRect] = []
        if let container = textContainer(forGlyphAt: firstDrawn, effectiveRange: nil) {
            let none = NSRange(location: NSNotFound, length: 0)
            var n = 0
            let runFirst = self.rectArray(forCharacterRange: charRange, withinSelectedCharacterRange: none,
                                          in: container, rectCount: &n).flatMap { n > 0 ? $0[0] : nil }
            var pieces: [(line: CGFloat, rect: NSRect)] = []
            for g in glyphs.location..<glyphs.upperBoundValue where drawn(g) {
                let line = lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                let box = boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: container)
                guard box.width > 0 else { continue }
                if let i = pieces.firstIndex(where: { $0.line == line.minY }) {
                    pieces[i].rect = pieces[i].rect.union(box)
                } else {
                    pieces.append((line.minY, box))
                }
            }
            // Those are container coordinates; the run's own first rect, which we
            // hold in both systems, says how far the view has moved them.
            if let runFirst {
                let dx = rects[0].minX - runFirst.minX, dy = rects[0].minY - runFirst.minY
                capsules = pieces.map { $0.rect.offsetBy(dx: dx, dy: dy) }
            }
        }
        if capsules.isEmpty { capsules = rects }
        for var rect in capsules {
            // A capsule lit from the top, with a hairline edge: enough to read as a chip.
            rect = rect.insetBy(dx: -DateToken.capsulePadding, dy: -1.5)
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

    /// A horizontal rule: its dashes are not drawn (see the text view's glyph
    /// generation), and a line across the middle of the column stands in for
    /// them — unless the caret is on that line, when the dashes show instead.
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(Syntax.ruleKey, in: chars, options: []) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0, self.propertyForGlyph(at: glyphs.location) == .null,
                  let container = self.textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { return }
            let line = self.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 16)
            let baseline = origin.y + line.minY + self.location(forGlyphAt: glyphs.location).y
            let width = (container.size.width * 0.4).rounded()
            let x = origin.x + line.minX + ((container.size.width - width) / 2).rounded()
            let y = (baseline - font.xHeight * 0.55).rounded() - 0.5
            color.setFill()
            NSRect(x: x, y: y, width: width, height: 1).fill()
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
