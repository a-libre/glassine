import AppKit

/// Applies lightweight, Paper-style Markdown styling: syntax stays visible but
/// dimmed; headings, emphasis, code, quotes, lists and links are rendered inline.
/// The `[ ]` / `[x]` of a task item. Clicking it toggles the item (see
/// GlassineTextView.mouseDown); the attribute value is whether it is checked.
enum TaskBox {
    static let attributeKey = NSAttributedString.Key("glassine.taskBox")
    /// On the text of a finished task. The value is `[start, end]` colours for the
    /// strikethrough, which GlassineLayoutManager draws as a gradient.
    static let doneKey = NSAttributedString.Key("glassine.taskDone")
}

/// Markdown markers, so the editor can hide them: `Syntax.hiddenKey` on the
/// characters that are syntax and nothing else, `Syntax.bulletKey` on a list's
/// `-`, `*` or `+`, which is drawn as a bullet instead.
enum Syntax {
    static let hiddenKey = NSAttributedString.Key("glassine.syntaxHidden")
    static let bulletKey = NSAttributedString.Key("glassine.bullet")
    /// On the dashes of a horizontal rule; the value is the colour to draw the line in.
    static let ruleKey = NSAttributedString.Key("glassine.rule")
}

final class MarkdownStyler {
    var config: StyleConfig {
        didSet { rebuildCaches() }
    }

    private var bodyFont: NSFont!
    private var boldFont: NSFont!
    private var italicFont: NSFont!
    private var monoFont: NSFont!
    private var headingFonts: [NSFont] = []
    private var baseAttrs: [NSAttributedString.Key: Any] = [:]
    private var baseParagraph: NSParagraphStyle!
    private var quoteParagraph: NSParagraphStyle!
    private var codeParagraph: NSParagraphStyle!
    private var tableRowParagraph: NSParagraphStyle!
    private var tableSeparatorParagraph: NSParagraphStyle!
    private var tableLastRowParagraph: NSParagraphStyle!
    private var listStyleCache: [String: NSParagraphStyle] = [:]
    private var lastFenceCount = -1

    init(config: StyleConfig) {
        self.config = config
        rebuildCaches()
    }

    private func rebuildCaches() {
        bodyFont = config.bodyFont
        boldFont = config.boldFont
        italicFont = config.italicFont
        monoFont = config.monoFont
        headingFonts = (1...6).map { config.headingFont(level: $0) }
        baseAttrs = config.baseAttributes
        baseParagraph = config.baseParagraphStyle()
        let indent = (config.fontSize * 1.1).rounded()
        quoteParagraph = config.indentedParagraphStyle(firstLineIndent: indent, headIndent: indent, tight: false)
        codeParagraph = config.indentedParagraphStyle(firstLineIndent: 0, headIndent: 0, tight: true)
        // A row has a little air above and below its words, as a table's
        // cells do; the grid's lines run through it, since the spacing
        // belongs to the row's lines. The separator is a thin strip with
        // none, where the line under the header is drawn.
        let air = (config.fontSize * 0.3).rounded()
        let row = config.baseParagraphStyle()
        row.firstLineHeadIndent = 0
        row.paragraphSpacingBefore = air
        row.paragraphSpacing = air
        tableRowParagraph = row
        let separator = config.baseParagraphStyle()
        separator.firstLineHeadIndent = 0
        separator.paragraphSpacingBefore = 0
        separator.paragraphSpacing = 0
        separator.lineHeightMultiple = 1
        tableSeparatorParagraph = separator
        let lastRow = config.baseParagraphStyle()
        lastRow.firstLineHeadIndent = 0
        lastRow.paragraphSpacingBefore = air
        lastRow.paragraphSpacing += air
        tableLastRowParagraph = lastRow
        listStyleCache = [:]
        lastFenceCount = -1
    }

    // MARK: - Regexes

    private static func rx(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    private static let heading = rx("^(#{1,6})([ \\t]+)(.*?)[ \\t]*$")
    private static let hr = rx("^[ \\t]*(?:(?:-[ \\t]*){3,}|(?:\\*[ \\t]*){3,}|(?:_[ \\t]*){3,})$")
    private static let quote = rx("^([ \\t]*>[ \\t]?)(.*)$")
    private static let list = rx("^([ \\t]*)([-*+]|\\d{1,3}[.)])([ \\t]+)(\\[[ xX]\\][ \\t]+)?")
    private static let indentedCode = rx("^(?: {4}|\\t)")
    private static let codeSpan = rx("(`+)([^`\\n]+?)\\1")
    private static let bold = rx("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italicStar = rx("(?<![\\*\\w])(\\*)(?=\\S)([^*\\n]+?)(?<=\\S)\\1(?!\\*)")
    private static let italicUnderscore = rx("(?<![\\w_])(_)(?=\\S)([^_\\n]+?)(?<=\\S)\\1(?![\\w_])")
    private static let strike = rx("(~~)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let chip = rx("(==)(?=\\S)([^=\\n]+?)(?<=\\S)\\1")
    private static let link = rx("(!?\\[)([^\\]\\n]*)(\\]\\()([^)\\s]*)((?:\\s+\"[^\"]*\")?\\))")
    private static let bareURL = rx("(?<![\\(\\w])https?://[^\\s<>()\\]]+")
    private static let tag = rx("(?<![\\w#/&])#([A-Za-z_][\\w\\-/]*)")
    private static let dateToken = rx(DateToken.pattern)
    private static let hexLike = rx("^[0-9A-Fa-f]{3}$|^[0-9A-Fa-f]{6}$")

    // MARK: - Public

    /// Restyles the paragraphs touching `range`. Pass the full range to style
    /// the whole document.
    func restyle(_ storage: NSTextStorage, range: NSRange) {
        let ns = storage.ns
        let length = ns.length
        guard length >= 0 else { return }
        var target = ns.paragraphRange(for: range.clamped(to: length))

        // Fenced code blocks change everything after them; keep it simple and
        // restyle from the first affected fence to the end when fences change.
        let hasFences = ns.range(of: "```").location != NSNotFound || ns.range(of: "~~~").location != NSNotFound
        var fenceStarts: [Int] = []
        if hasFences {
            fenceStarts = fenceLineStarts(ns)
            let editedText = ns.substring(with: target)
            let touchesFence = editedText.contains("```") || editedText.contains("~~~")
            if touchesFence || fenceStarts.count != lastFenceCount {
                target = NSRange(location: target.location, length: length - target.location)
                if fenceStarts.count != lastFenceCount && lastFenceCount != -1 {
                    target = NSRange(location: 0, length: length)
                }
            }
            lastFenceCount = fenceStarts.count
        } else {
            lastFenceCount = 0
        }

        // A table's columns are measured across all its rows, so an edit in
        // one row restyles the whole table.
        if target.length > 0 || target.location < length {
            target = NSUnionRange(target, MarkdownTable.blockRange(ns, around: target.location))
            target = NSUnionRange(target, MarkdownTable.blockRange(ns, around: max(target.location, target.upperBoundValue - 1)))
            target = ns.paragraphRange(for: target.clamped(to: length))
        }

        storage.beginEditing()
        // Reset the whole target range in one go, then decorate paragraph by paragraph.
        storage.setAttributes(baseAttrs, range: target)

        var insideFence = hasFences ? isInsideFence(at: target.location, fenceStarts: fenceStarts) : false
        var pipeLines: [NSRange] = []
        ns.enumerateSubstrings(in: target, options: [.byParagraphs, .substringNotRequired]) { _, paraRange, enclosing, _ in
            let paraText = ns.substring(with: paraRange)
            let trimmed = paraText.trimmingCharacters(in: .whitespaces)
            let isFenceLine = trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
            if isFenceLine {
                self.applyCodeLine(storage, paraRange: paraRange, enclosing: enclosing, isFence: true)
                insideFence.toggle()
                return
            }
            if insideFence {
                self.applyCodeLine(storage, paraRange: paraRange, enclosing: enclosing, isFence: false)
                return
            }
            if MarkdownTable.looksLikeRow(paraText) { pipeLines.append(paraRange) }
            self.styleParagraph(storage, ns: ns, text: paraText, paraRange: paraRange, enclosing: enclosing)
        }
        // Runs of pipe lines whose second line is a separator are tables.
        var run: [NSRange] = []
        func flush() {
            if let table = MarkdownTable.table(ns, paragraphs: run) { layOutTable(table, storage) }
            run = []
        }
        for line in pipeLines {
            if let last = run.last, line.location != last.upperBoundValue + 1 { flush() }
            run.append(line)
        }
        flush()
        storage.endEditing()
    }

    private func layOutTable(_ table: MarkdownTable.Table, _ storage: NSTextStorage) {
        let theme = config.theme
        // The width the table has is the text container's, when the view has
        // sized it; the column setting stands in until then.
        var available = config.columnWidth
        if let container = storage.layoutManagers.first?.textContainers.first,
           container.size.width > 20, container.size.width < 50_000 {
            available = container.size.width - 2 * container.lineFragmentPadding
        }
        let grid = MarkdownTable.Grid(line: theme.text.withAlpha(theme.isDark ? 0.2 : 0.16),
                                      fill: theme.text.withAlpha(theme.isDark ? 0.05 : 0.04),
                                      radius: 6,
                                      pipe: ("|" as NSString).size(withAttributes: [.font: bodyFont!]).width)
        MarkdownTable.layOut(table, in: storage, config: config, grid: grid,
                             headerFont: boldFont, rowParagraph: tableRowParagraph, separatorParagraph: tableSeparatorParagraph,
                             lastRowParagraph: tableLastRowParagraph, availableWidth: available)
    }

    /// Restyles every table in the text — for a column that changed width,
    /// since a table is laid out to the width it has.
    func restyleTables(_ storage: NSTextStorage) {
        let ns = storage.ns
        guard ns.range(of: "|").location != NSNotFound else { return }
        var at = 0
        while at < ns.length {
            let block = MarkdownTable.blockRange(ns, around: at)
            if block.length > 0, MarkdownTable.looksLikeRow(ns.substring(with: ns.paragraphRange(for: NSRange(location: at, length: 0)))) {
                restyle(storage, range: block)
            }
            at = max(block.upperBoundValue, at + 1)
        }
    }

    // MARK: - Fences

    /// Where every fence line starts. Run after each keystroke in a document
    /// that has a fence anywhere, so it reads the paragraphs in place — a
    /// substring was made and trimmed for every one before — and only looks
    /// at a line's first characters past its indent.
    private func fenceLineStarts(_ ns: NSString) -> [Int] {
        var starts: [Int] = []
        let length = ns.length
        ns.enumerateSubstrings(in: NSRange(location: 0, length: length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            var i = range.location
            let end = min(length, range.upperBoundValue)
            while i < end, ns.character(at: i) == 32 || ns.character(at: i) == 9 { i += 1 }
            guard i + 2 < end else { return }
            let c = ns.character(at: i)
            if (c == 96 || c == 126), ns.character(at: i + 1) == c, ns.character(at: i + 2) == c {
                starts.append(range.location)
            }
        }
        return starts
    }

    private func isInsideFence(at location: Int, fenceStarts: [Int]) -> Bool {
        var inside = false
        for s in fenceStarts where s < location { inside.toggle() }
        return inside
    }

    // MARK: - Paragraph styling

    private func applyCodeLine(_ storage: NSTextStorage, paraRange: NSRange, enclosing: NSRange, isFence: Bool) {
        storage.addAttribute(.paragraphStyle, value: codeParagraph!, range: enclosing)
        storage.addAttribute(.font, value: monoFont!, range: paraRange)
        storage.addAttribute(.foregroundColor, value: isFence ? config.theme.syntax.nsColor : config.theme.codeColor, range: paraRange)
    }

    private func styleParagraph(_ storage: NSTextStorage, ns: NSString, text: String, paraRange: NSRange, enclosing: NSRange) {
        let theme = config.theme
        let syntaxColor = theme.syntax.nsColor
        let textNS = text as NSString
        let full = NSRange(location: 0, length: textNS.length)
        func absRange(_ r: NSRange) -> NSRange { NSRange(location: paraRange.location + r.location, length: r.length) }

        var inlineAllowed = true

        if let m = MarkdownStyler.heading.firstMatch(in: text, options: [], range: full) {
            let level = m.range(at: 1).length
            storage.addAttribute(.paragraphStyle, value: config.headingParagraphStyle(level: level), range: enclosing)
            storage.addAttribute(.font, value: headingFonts[level - 1], range: paraRange)
            storage.addAttribute(.foregroundColor, value: theme.headingColor, range: paraRange)
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(m.range(at: 1)))
            storage.addAttribute(Syntax.hiddenKey, value: true,
                                 range: absRange(NSRange(location: m.range(at: 1).location, length: m.range(at: 1).length + m.range(at: 2).length)))
        } else if MarkdownStyler.hr.firstMatch(in: text, options: [], range: full) != nil {
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: paraRange)
            storage.addAttribute(Syntax.ruleKey, value: theme.text.withAlpha(theme.isDark ? 0.3 : 0.24), range: paraRange)
            inlineAllowed = false
        } else if let m = MarkdownStyler.quote.firstMatch(in: text, options: [], range: full) {
            storage.addAttribute(.paragraphStyle, value: quoteParagraph!, range: enclosing)
            storage.addAttribute(.foregroundColor, value: theme.quoteColor, range: paraRange)
            storage.addAttribute(.font, value: italicFont!, range: paraRange)
            storage.addAttribute(.foregroundColor, value: theme.accent.withAlpha(0.6), range: absRange(m.range(at: 1)))
            storage.addAttribute(Syntax.hiddenKey, value: true, range: absRange(m.range(at: 1)))
        } else if let m = MarkdownStyler.list.firstMatch(in: text, options: [], range: full) {
            let indentText = textNS.substring(with: m.range(at: 1))
            let markerText = textNS.substring(with: m.range(at: 2))
            let gapText = textNS.substring(with: m.range(at: 3))
            let indentWidth = (indentText as NSString).size(withAttributes: [.font: bodyFont!]).width
            let markerWidth = ((markerText + gapText) as NSString).size(withAttributes: [.font: bodyFont!]).width
            let key = "\(indentWidth.rounded())-\(markerWidth.rounded())"
            let style = listStyleCache[key] ?? {
                let s = config.indentedParagraphStyle(firstLineIndent: indentWidth, headIndent: indentWidth + markerWidth, tight: true)
                listStyleCache[key] = s
                return s
            }()
            storage.addAttribute(.paragraphStyle, value: style, range: enclosing)
            storage.addAttribute(.foregroundColor, value: theme.accent.nsColor, range: absRange(m.range(at: 2)))
            if m.range(at: 4).location != NSNotFound {
                // A task's `- ` steps aside when the syntax is hidden; the box is the marker.
                let dash = NSRange(location: m.range(at: 2).location, length: m.range(at: 2).length + m.range(at: 3).length)
                storage.addAttribute(Syntax.hiddenKey, value: true, range: absRange(dash))
            } else if let first = markerText.first, "-*+".contains(first) {
                storage.addAttribute(Syntax.bulletKey, value: true, range: absRange(m.range(at: 2)))
            }
            if m.range(at: 4).location != NSNotFound {
                let box = textNS.substring(with: m.range(at: 4))
                let checked = box.lowercased().contains("x")
                storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(m.range(at: 4)))
                storage.addAttribute(.font, value: monoFont!, range: absRange(m.range(at: 4)))
                // The brackets are a click target: pointing hand, and a toggle on mouse down.
                let boxRange = NSRange(location: absRange(m.range(at: 4)).location, length: 3)
                storage.addAttribute(TaskBox.attributeKey, value: checked, range: boxRange)
                storage.addAttribute(.cursor, value: NSCursor.pointingHand, range: boxRange)
                if checked {
                    storage.addAttribute(.foregroundColor, value: theme.accent.withAlpha(0.85), range: boxRange)
                    let rest = NSRange(location: m.range.upperBoundValue, length: full.length - m.range.upperBoundValue)
                    storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(rest))
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: absRange(rest))
                    storage.addAttribute(.strikethroughColor, value: syntaxColor, range: absRange(rest))
                    storage.addAttribute(TaskBox.doneKey, value: [theme.accent.withAlpha(0.9), syntaxColor.withAlphaComponent(0.4)], range: absRange(rest))
                }
            }
        } else if MarkdownStyler.indentedCode.firstMatch(in: text, options: [], range: full) != nil {
            storage.addAttribute(.paragraphStyle, value: codeParagraph!, range: enclosing)
            storage.addAttribute(.font, value: monoFont!, range: paraRange)
            storage.addAttribute(.foregroundColor, value: theme.codeColor, range: paraRange)
            inlineAllowed = false
        }

        guard inlineAllowed, textNS.length > 1 else { return }

        // Code spans first; nothing else applies inside them.
        var codeRanges: [NSRange] = []
        for m in MarkdownStyler.codeSpan.matches(in: text, options: [], range: full) {
            codeRanges.append(m.range)
            storage.addAttribute(.font, value: monoFont!, range: absRange(m.range(at: 2)))
            storage.addAttribute(.foregroundColor, value: theme.codeColor, range: absRange(m.range(at: 2)))
            storage.addAttribute(.backgroundColor, value: theme.codeBackgroundColor, range: absRange(m.range))
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(m.range(at: 1)))
            let closing = NSRange(location: m.range.upperBoundValue - m.range(at: 1).length, length: m.range(at: 1).length)
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(closing))
            storage.addAttribute(Syntax.hiddenKey, value: true, range: absRange(m.range(at: 1)))
            storage.addAttribute(Syntax.hiddenKey, value: true, range: absRange(closing))
        }
        func inCode(_ r: NSRange) -> Bool {
            codeRanges.contains { NSIntersectionRange($0, r).length > 0 }
        }

        func emphasize(_ regex: NSRegularExpression, trait: NSFontDescriptor.SymbolicTraits, strike: Bool = false) {
            for m in regex.matches(in: text, options: [], range: full) where !inCode(m.range) {
                let inner = absRange(m.range(at: 2))
                let markerLen = m.range(at: 1).length
                let open = absRange(NSRange(location: m.range.location, length: markerLen))
                let close = absRange(NSRange(location: m.range.upperBoundValue - markerLen, length: markerLen))
                if strike {
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: inner)
                    storage.addAttribute(.strikethroughColor, value: syntaxColor, range: inner)
                } else {
                    storage.enumerateAttribute(.font, in: inner, options: []) { value, r, _ in
                        let f = (value as? NSFont) ?? bodyFont!
                        storage.addAttribute(.font, value: f.withTraits(trait), range: r)
                    }
                }
                storage.addAttribute(.foregroundColor, value: syntaxColor, range: open)
                storage.addAttribute(.foregroundColor, value: syntaxColor, range: close)
                storage.addAttribute(Syntax.hiddenKey, value: true, range: open)
                storage.addAttribute(Syntax.hiddenKey, value: true, range: close)
            }
        }
        emphasize(MarkdownStyler.bold, trait: .bold)
        emphasize(MarkdownStyler.italicStar, trait: .italic)
        emphasize(MarkdownStyler.italicUnderscore, trait: .italic)
        emphasize(MarkdownStyler.strike, trait: [], strike: true)

        for m in MarkdownStyler.link.matches(in: text, options: [], range: full) where !inCode(m.range) {
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(m.range(at: 1)))
            storage.addAttribute(.foregroundColor, value: theme.linkColor, range: absRange(m.range(at: 2)))
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(m.range(at: 3)))
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(m.range(at: 4)))
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(m.range(at: 5)))
            for i in [1, 3, 4, 5] { storage.addAttribute(Syntax.hiddenKey, value: true, range: absRange(m.range(at: i))) }
        }
        // `==word==`: a capsule like a date's, around anything.
        var capsules: [NSRange] = []
        for m in MarkdownStyler.chip.matches(in: text, options: [], range: full) where !inCode(m.range) {
            let r = absRange(m.range)
            capsules.append(r)
            storage.addAttribute(.foregroundColor, value: theme.accent.nsColor, range: r)
            storage.addAttribute(.backgroundColor, value: theme.accent.withAlpha(theme.isDark ? 0.18 : 0.14), range: r)
            storage.addAttribute(DateToken.attributeKey, value: true, range: r)
            let open = absRange(m.range(at: 1))
            let close = NSRange(location: r.upperBoundValue - 2, length: 2)
            for marker in [open, close] {
                storage.addAttribute(.foregroundColor, value: theme.accent.withAlpha(0.45), range: marker)
                storage.addAttribute(Syntax.hiddenKey, value: true, range: marker)
            }
        }
        for m in MarkdownStyler.bareURL.matches(in: text, options: [], range: full) where !inCode(m.range) {
            storage.addAttribute(.foregroundColor, value: theme.linkColor.withAlphaComponent(0.85), range: absRange(m.range))
        }
        for m in MarkdownStyler.tag.matches(in: text, options: [], range: full) where !inCode(m.range) {
            let name = textNS.substring(with: m.range(at: 1))
            if MarkdownStyler.hexLike.firstMatch(in: name, options: [], range: NSRange(location: 0, length: (name as NSString).length)) != nil { continue }
            storage.addAttribute(.foregroundColor, value: theme.accent.withAlpha(0.9), range: absRange(m.range))
        }
        for m in MarkdownStyler.dateToken.matches(in: text, options: [], range: full) where !inCode(m.range) {
            let r = absRange(m.range)
            capsules.append(r)
            storage.addAttribute(.foregroundColor, value: theme.accent.nsColor, range: r)
            storage.addAttribute(.backgroundColor, value: theme.accent.withAlpha(theme.isDark ? 0.18 : 0.14), range: r)
            storage.addAttribute(DateToken.attributeKey, value: true, range: r)
            // The "@" stays in the file but steps back visually.
            storage.addAttribute(.foregroundColor, value: theme.accent.withAlpha(0.55), range: NSRange(location: r.location, length: 1))
        }
        // Room around a capsule: a space on either side of one is kerned by the
        // capsule's own reach, so the capsule stands a full space clear of the
        // words around it instead of eating the space and touching them.
        let room = DateToken.capsulePadding + config.letterSpacing
        for r in capsules {
            if r.location > paraRange.location, ns.character(at: r.location - 1) == 32 {
                storage.addAttribute(.kern, value: room, range: NSRange(location: r.location - 1, length: 1))
            }
            if r.upperBoundValue < paraRange.upperBoundValue, ns.character(at: r.upperBoundValue) == 32 {
                storage.addAttribute(.kern, value: room, range: NSRange(location: r.upperBoundValue, length: 1))
            }
        }
    }
}
