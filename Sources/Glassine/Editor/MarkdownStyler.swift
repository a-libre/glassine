import AppKit

/// Applies lightweight, Paper-style Markdown styling: syntax stays visible but
/// dimmed; headings, emphasis, code, quotes, lists and links are rendered inline.
final class MarkdownStyler {
    var config: StyleConfig {
        didSet { rebuildCaches() }
    }

    private var bodyFont: NSFont!
    private var boldFont: NSFont!
    private var italicFont: NSFont!
    private var boldItalicFont: NSFont!
    private var monoFont: NSFont!
    private var headingFonts: [NSFont] = []
    private var baseAttrs: [NSAttributedString.Key: Any] = [:]
    private var baseParagraph: NSParagraphStyle!
    private var quoteParagraph: NSParagraphStyle!
    private var codeParagraph: NSParagraphStyle!
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
        boldItalicFont = config.boldItalicFont
        monoFont = config.monoFont
        headingFonts = (1...6).map { config.headingFont(level: $0) }
        baseAttrs = config.baseAttributes
        baseParagraph = config.baseParagraphStyle()
        let indent = (config.fontSize * 1.1).rounded()
        quoteParagraph = config.indentedParagraphStyle(firstLineIndent: indent, headIndent: indent, tight: false)
        codeParagraph = config.indentedParagraphStyle(firstLineIndent: 0, headIndent: 0, tight: true)
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
    private static let link = rx("(!?\\[)([^\\]\\n]*)(\\]\\()([^)\\s]*)((?:\\s+\"[^\"]*\")?\\))")
    private static let bareURL = rx("(?<![\\(\\w])https?://[^\\s<>()\\]]+")
    private static let tag = rx("(?<![\\w#/&])#([A-Za-z_][\\w\\-/]*)")
    private static let hexLike = rx("^[0-9A-Fa-f]{3}$|^[0-9A-Fa-f]{6}$")

    // MARK: - Public

    /// Restyles the paragraphs touching `range`. Pass the full range to style
    /// the whole document.
    func restyle(_ storage: NSTextStorage, range: NSRange) {
        let ns = storage.string as NSString
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

        storage.beginEditing()
        // Reset the whole target range in one go, then decorate paragraph by paragraph.
        storage.setAttributes(baseAttrs, range: target)

        var insideFence = hasFences ? isInsideFence(at: target.location, fenceStarts: fenceStarts) : false
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
            self.styleParagraph(storage, ns: ns, text: paraText, paraRange: paraRange, enclosing: enclosing)
        }
        storage.endEditing()
    }

    // MARK: - Fences

    private func fenceLineStarts(_ ns: NSString) -> [Int] {
        var starts: [Int] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs]) { sub, range, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespaces), s.hasPrefix("```") || s.hasPrefix("~~~") {
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
        } else if MarkdownStyler.hr.firstMatch(in: text, options: [], range: full) != nil {
            storage.addAttribute(.foregroundColor, value: syntaxColor, range: paraRange)
            inlineAllowed = false
        } else if let m = MarkdownStyler.quote.firstMatch(in: text, options: [], range: full) {
            storage.addAttribute(.paragraphStyle, value: quoteParagraph!, range: enclosing)
            storage.addAttribute(.foregroundColor, value: theme.quoteColor, range: paraRange)
            storage.addAttribute(.font, value: italicFont!, range: paraRange)
            storage.addAttribute(.foregroundColor, value: theme.accent.withAlpha(0.6), range: absRange(m.range(at: 1)))
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
                let box = textNS.substring(with: m.range(at: 4))
                storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(m.range(at: 4)))
                storage.addAttribute(.font, value: monoFont!, range: absRange(m.range(at: 4)))
                if box.lowercased().contains("x") {
                    let rest = NSRange(location: m.range.upperBoundValue, length: full.length - m.range.upperBoundValue)
                    storage.addAttribute(.foregroundColor, value: syntaxColor, range: absRange(rest))
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: absRange(rest))
                    storage.addAttribute(.strikethroughColor, value: syntaxColor, range: absRange(rest))
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
        }
        for m in MarkdownStyler.bareURL.matches(in: text, options: [], range: full) where !inCode(m.range) {
            storage.addAttribute(.foregroundColor, value: theme.linkColor.withAlphaComponent(0.85), range: absRange(m.range))
        }
        for m in MarkdownStyler.tag.matches(in: text, options: [], range: full) where !inCode(m.range) {
            let name = textNS.substring(with: m.range(at: 1))
            if MarkdownStyler.hexLike.firstMatch(in: name, options: [], range: NSRange(location: 0, length: (name as NSString).length)) != nil { continue }
            storage.addAttribute(.foregroundColor, value: theme.accent.withAlpha(0.9), range: absRange(m.range))
        }
    }
}
