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

/// Draws softly rounded rectangles for inline code, capsules for dates and
/// chips (on the text view's behalf, before the text system draws), the line of
/// a horizontal rule, and the strikethrough of finished tasks as a gradient.
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
        // A date or a chip gets its capsule from drawCapsules(in:origin:), which
        // the text view calls before the text system draws — nothing here.
        let isCapsule = textStorage.map { charRange.location < $0.length
            && $0.attribute(DateToken.attributeKey, at: charRange.location, effectiveRange: nil) != nil } ?? false
        guard !isCapsule else { return }
        color.setFill()
        for rect in rects {
            NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: 0), xRadius: 3.5, yRadius: 3.5).fill()
        }
    }

    /// Capsules for dates and chips, drawn by the text view before the text
    /// system draws anything, so nothing the text system clips to — the text
    /// container's edges — can cut one off where it reaches into a margin.
    /// Each token gets a capsule around its drawn glyphs, line by line: a
    /// marker that is not drawn takes no room in it, a token that wraps gets
    /// one per line, and each is as tall as its type — ascender to descender —
    /// rather than the whole line, so a short word gets a pill and not an egg.
    func drawCapsules(in rect: NSRect, origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0, let container = textContainers.first else { return }
        let glyphs = glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        guard glyphs.length > 0 else { return }
        let chars = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // The runs are read within the stretch on screen — with room either
        // side for a token that straddles its edge — rather than the whole
        // document: asked over the whole, a run with no token in it was
        // walked to the end of the document on every draw.
        let reach = 64
        let near = NSRange(location: max(0, chars.location - reach),
                           length: min(storage.length, chars.upperBoundValue + reach) - max(0, chars.location - reach))
        var index = chars.location
        while index < chars.upperBoundValue {
            var tokenRange = NSRange(location: 0, length: 0)
            let isToken = storage.attribute(DateToken.attributeKey, at: index, longestEffectiveRange: &tokenRange, in: near) != nil
            guard tokenRange.length > 0 else { break }
            if isToken, let color = storage.attribute(.backgroundColor, at: tokenRange.location, effectiveRange: nil) as? NSColor {
                for piece in capsulePieces(for: tokenRange, in: container) {
                    drawCapsule(piece.offsetBy(dx: origin.x, dy: origin.y), color: color)
                }
            }
            index = tokenRange.upperBoundValue
        }
    }

    /// The rectangles a token's capsule is made of, one per line it has drawn
    /// glyphs on, in container coordinates. The glyph range can reach a glyph
    /// past the token's characters (a kerned space before it, say), so each
    /// glyph is checked against them.
    private func capsulePieces(for tokenRange: NSRange, in container: NSTextContainer) -> [NSRect] {
        let glyphs = glyphRange(forCharacterRange: tokenRange, actualCharacterRange: nil)
        var pieces: [(line: CGFloat, rect: NSRect)] = []
        for g in glyphs.location..<glyphs.upperBoundValue {
            guard NSLocationInRange(characterIndexForGlyph(at: g), tokenRange) else { continue }
            let property = propertyForGlyph(at: g)
            guard property != .null, property != .controlCharacter else { continue }
            let line = lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let box = boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: container)
            guard box.width > 0 else { continue }
            let font = (textStorage?.attribute(.font, at: characterIndexForGlyph(at: g), effectiveRange: nil) as? NSFont)
                ?? NSFont.systemFont(ofSize: 16)
            let baseline = line.minY + location(forGlyphAt: g).y
            let type = NSRect(x: box.minX, y: baseline - font.ascender, width: box.width, height: font.ascender - font.descender)
            if let i = pieces.firstIndex(where: { $0.line == line.minY }) {
                pieces[i].rect = pieces[i].rect.union(type)
            } else {
                pieces.append((line.minY, type))
            }
        }
        return pieces.map { $0.rect }
    }

    /// A capsule lit from the top, with a hairline edge: enough to read as a chip.
    private func drawCapsule(_ glyphRect: NSRect, color: NSColor) {
        let rect = glyphRect.insetBy(dx: -DateToken.capsulePadding, dy: -2)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        let alpha = color.alphaComponent
        if let gradient = NSGradient(starting: color.withAlphaComponent(min(1, alpha * 1.5)),
                                     ending: color.withAlphaComponent(alpha * 0.8)) {
            gradient.draw(in: path, angle: 90)
        } else {
            color.setFill()
            path.fill()
        }
        color.withAlphaComponent(min(1, alpha * 1.1)).setStroke()
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: rect.height / 2, yRadius: rect.height / 2)
        edge.lineWidth = 1
        edge.stroke()
    }

    /// Where the Markdown shows as written: the sentence the caret is in.
    private var revealRange: NSRange {
        (firstTextView as? GlassineTextView)?.syntaxRevealRange ?? NSRange(location: NSNotFound, length: 0)
    }

    /// A horizontal rule's dashes are laid out like any text — so their line
    /// is measured like any line — but never drawn, the caret on that line
    /// or not: a rule has nothing in it to edit, and the caret sits on the
    /// line as it does on any other. The rule itself is drawn in drawBackground.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage else { super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin); return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        // The same for a table's pipes and its separator: laid out, never
        // drawn, hairlines in their place (drawBackground).
        var skipped: [NSRange] = []
        for key in [Syntax.ruleKey, MarkdownTable.pipeKey, MarkdownTable.ruleKey] {
            storage.enumerateAttribute(key, in: chars, options: []) { value, range, _ in
                if value != nil { skipped.append(range) }
            }
        }
        guard !skipped.isEmpty else { super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin); return }
        skipped.sort { $0.location < $1.location }
        var at = chars.location
        for r in skipped {
            if r.location > at {
                let piece = NSIntersectionRange(self.glyphRange(forCharacterRange: NSRange(location: at, length: r.location - at), actualCharacterRange: nil), glyphsToShow)
                if piece.length > 0 { super.drawGlyphs(forGlyphRange: piece, at: origin) }
            }
            at = max(at, r.upperBoundValue)
        }
        if at < chars.upperBoundValue {
            let piece = NSIntersectionRange(self.glyphRange(forCharacterRange: NSRange(location: at, length: chars.upperBoundValue - at), actualCharacterRange: nil), glyphsToShow)
            if piece.length > 0 { super.drawGlyphs(forGlyphRange: piece, at: origin) }
        }
    }

    /// A horizontal rule: a line across the middle of the column, where the
    /// dashes are, whether or not the caret is on that line.
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(Syntax.ruleKey, in: chars, options: []) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0,
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
        // A picture: drawn in the room its paragraph keeps above its line.
        var pictured: [Int] = []
        storage.enumerateAttribute(ImageEmbed.key, in: chars, options: []) { value, range, _ in
            guard let placement = value as? ImageEmbed.Placement else { return }
            let para = storage.ns.paragraphRange(for: range)
            guard !pictured.contains(para.location) else { return }
            pictured.append(para.location)
            self.drawPicture(placement, paragraph: para, storage: storage, origin: origin)
        }
        // A table: its grid, drawn once per table in view.
        var drawn: [Int] = []
        storage.enumerateAttribute(MarkdownTable.gridKey, in: chars, options: []) { value, range, _ in
            guard let grid = value as? MarkdownTable.Grid else { return }
            var whole = NSRange(location: range.location, length: 0)
            _ = storage.attribute(MarkdownTable.gridKey, at: range.location, longestEffectiveRange: &whole,
                                  in: NSRange(location: 0, length: storage.length))
            guard !drawn.contains(whole.location) else { return }
            drawn.append(whole.location)
            self.drawTable(whole, grid: grid, storage: storage, origin: origin)
        }
    }

    /// The grid of one table: a border with rounded corners, a line under
    /// every row, a line where every pipe is, the header on a faint fill.
    /// Rows sit flush, each with its air above and below its words, so the
    /// row's box is the union of its line fragments — less, for the last
    /// row, the page's spacing after the table.
    /// The picture of an image line, centred in the room above its caption,
    /// with rounded corners — and as dim as its paragraph when focus mode has
    /// dimmed it. Before the file has been decoded, a faint plate its size.
    private func drawPicture(_ placement: ImageEmbed.Placement, paragraph: NSRange, storage: NSTextStorage, origin: NSPoint) {
        let glyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
        guard glyphs.length > 0, let container = textContainer(forGlyphAt: glyphs.location, effectiveRange: nil) else { return }
        let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let used = lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let room = used.minY - fragment.minY
        guard room > 4 else { return }
        let size = placement.size
        let x = origin.x + fragment.minX + ((container.size.width - size.width) / 2).rounded()
        let y = origin.y + fragment.minY + ((room - size.height) / 2).rounded()
        let rect = NSRect(x: x, y: y, width: size.width, height: size.height)
        // The paragraph's dimming, read off the colour focus mode has set on its text.
        var fraction: CGFloat = 1
        if let dim = temporaryAttribute(.foregroundColor, atCharacterIndex: paragraph.location, effectiveRange: nil) as? NSColor,
           let base = storage.attribute(.foregroundColor, at: paragraph.location, effectiveRange: nil) as? NSColor, base.alphaComponent > 0 {
            fraction = max(0.12, min(1, dim.alphaComponent / base.alphaComponent))
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: ImageEmbed.cornerRadius, yRadius: ImageEmbed.cornerRadius).addClip()
        if let url = placement.url, let image = ImageStore.shared.image(for: url) {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: fraction, respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high])
        } else {
            let plate = (storage.attribute(.foregroundColor, at: paragraph.location, effectiveRange: nil) as? NSColor) ?? .gray
            plate.withAlphaComponent(0.08 * fraction).setFill()
            rect.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawTable(_ tableRange: NSRange, grid: MarkdownTable.Grid, storage: NSTextStorage, origin: NSPoint) {
        struct Box { let index: Int; let range: NSRange; let top: CGFloat; let bottom: CGFloat; let firstLine: NSRect }
        var boxes: [Box] = []
        storage.enumerateAttribute(MarkdownTable.rowKey, in: tableRange, options: []) { value, range, _ in
            guard let index = value as? Int else { return }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            var top = CGFloat.greatestFiniteMagnitude, bottom = -CGFloat.greatestFiniteMagnitude
            var first: NSRect?
            var lastUsed: NSRect?
            self.enumerateLineFragments(forGlyphRange: glyphs) { rect, used, _, _, _ in
                top = min(top, rect.minY)
                bottom = max(bottom, rect.maxY)
                if first == nil || rect.minY < first!.minY { first = rect }
                if lastUsed == nil || used.maxY > lastUsed!.maxY { lastUsed = used }
            }
            guard let firstLine = first, let used = lastUsed else { return }
            // The last row's fragment carries the page's spacing after the
            // table; the row ends after its own air.
            if let style = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
               style.paragraphSpacing > style.paragraphSpacingBefore + 0.5 {
                bottom = min(bottom, used.maxY + style.paragraphSpacingBefore)
            }
            boxes.append(Box(index: index, range: range, top: top, bottom: bottom, firstLine: firstLine))
        }
        boxes.sort { $0.index < $1.index }
        guard let head = boxes.first, let foot = boxes.last, boxes.count >= 2,
              let edge = storage.attribute(MarkdownTable.edgeKey, at: head.range.location, effectiveRange: nil) as? CGFloat else { return }
        let left = (origin.x + head.firstLine.minX + grid.pipe / 2).rounded() - 0.5
        let right = (origin.x + head.firstLine.minX + edge).rounded() - 0.5
        let top = (origin.y + head.top).rounded() - 0.5
        let bottom = (origin.y + foot.bottom).rounded() - 0.5
        guard right > left + 4, bottom > top + 4 else { return }
        let frame = NSRect(x: left, y: top, width: right - left, height: bottom - top)
        let outline = NSBezierPath(roundedRect: frame, xRadius: grid.radius, yRadius: grid.radius)

        // The header, on its fill: down to the middle of the separator's strip.
        let dividerY: (Box) -> CGFloat = { box in
            box.index == 1 ? (origin.y + (box.top + box.bottom) / 2).rounded() - 0.5 : (origin.y + box.top).rounded() - 0.5
        }
        if let separator = boxes.first(where: { $0.index == 1 }) {
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            grid.fill.setFill()
            NSRect(x: left, y: top, width: right - left, height: dividerY(separator) - top).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        grid.line.setStroke()
        grid.line.setFill()
        outline.lineWidth = 1
        outline.stroke()
        // A line under every row: the separator's through its middle, the
        // others along their top edge.
        for box in boxes where box.index >= 1 {
            if box.index == 2 { continue }   // its top is the separator's bottom; the separator's middle has the line
            let y = dividerY(box)
            NSRect(x: left + 0.5, y: y, width: right - left - 1, height: 1).fill()
        }
        // A line where every pipe is, the height of the table, but for the
        // first and the last, which the border draws. The pipes of the
        // separator's strip are set small; their line is where a body pipe's
        // would be. A row with a cell too long for its column has the cells
        // after that one follow it on its last line, so in that row the
        // lines stop at that cell's opening pipe.
        let ns = storage.ns
        var columns: [CGFloat] = []
        var merged: [Int: CGFloat] = [:]   // row index → x beyond which it has no column lines
        for box in boxes where box.index != 1 {
            let wrapPipe = storage.attribute(MarkdownTable.wrapKey, at: box.range.location, effectiveRange: nil) as? Int
            storage.enumerateAttribute(MarkdownTable.pipeKey, in: box.range, options: []) { value, range, _ in
                guard value != nil else { return }
                for i in range.location..<range.upperBoundValue {
                    if let w = wrapPipe, i > w { continue }
                    let g = self.glyphIndexForCharacter(at: i)
                    guard g < self.numberOfGlyphs else { continue }
                    let line = self.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                    guard line.minY <= box.firstLine.minY + 0.5 else { continue }   // only on the row's first line
                    let loc = self.location(forGlyphAt: g)
                    let x: CGFloat
                    if let inset = storage.attribute(MarkdownTable.pipeInsetKey, at: i, effectiveRange: nil) as? CGFloat {
                        x = line.minX + loc.x + inset
                    } else {
                        x = line.minX + loc.x + grid.pipe / 2
                    }
                    let px = (origin.x + x).rounded() - 0.5
                    if let w = wrapPipe, i == w { merged[box.index] = px }
                    if i == box.range.location { continue }
                    // The closing pipe: nothing but spaces after it in the row.
                    let after = NSRange(location: i + 1, length: box.range.upperBoundValue - i - 1)
                    if after.length == 0 || ns.substring(with: after).trimmingCharacters(in: .whitespaces).isEmpty { continue }
                    if !columns.contains(where: { abs($0 - px) < 1.5 }) { columns.append(px) }
                }
            }
        }
        for x in columns where x > left + 2 && x < right - 2 {
            // One segment per row, so a merged row can go without the line.
            for box in boxes {
                if let stop = merged[box.index], x > stop + 1.5 { continue }
                let y0 = box.index == 0 ? top + 0.5 : (origin.y + box.top).rounded() - 0.5
                let y1 = box.index == boxes.count - 1 ? bottom - 0.5 : (origin.y + box.bottom).rounded() - 0.5
                guard y1 > y0 else { continue }
                NSRect(x: x, y: y0, width: 1, height: y1 - y0).fill()
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
