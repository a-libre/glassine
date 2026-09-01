import AppKit

/// Everything the text view and styler need to render a document, derived
/// from the current theme and settings. Value type so changes are easy to detect.
struct StyleConfig: Equatable {
    let theme: Theme
    let fontFamily: String
    let fontSize: CGFloat
    let lineHeightMultiple: CGFloat
    let paragraphSpacingEm: CGFloat
    let letterSpacing: CGFloat
    let scaledHeadings: Bool
    let columnWidth: CGFloat
    let topInset: CGFloat

    // Caret
    let smoothCaret: Bool
    let caretDuration: CFTimeInterval
    let smoothWhileTyping: Bool
    let caretBlink: CaretBlink
    let caretWidth: CGFloat

    // Modes
    let typewriter: Bool
    let typewriterOnClick: Bool
    let focus: Bool
    let focusScope: FocusScope
    let focusDimming: CGFloat

    // Text system behaviors
    let smartQuotes: Bool
    let smartDashes: Bool
    let autocorrect: Bool
    let spellCheck: Bool
    let inlinePredictions: Bool
    let continueLists: Bool

    init(theme: Theme, settings: SettingsData) {
        self.theme = theme
        fontFamily = settings.fontFamily
        fontSize = CGFloat(settings.fontSize)
        lineHeightMultiple = CGFloat(settings.lineHeight)
        paragraphSpacingEm = CGFloat(settings.paragraphSpacing)
        letterSpacing = CGFloat(settings.letterSpacing)
        scaledHeadings = settings.scaledHeadings
        columnWidth = CGFloat(settings.columnWidth)
        topInset = CGFloat(settings.topInset)
        smoothCaret = settings.smoothCaret
        caretDuration = settings.caretSpeed
        smoothWhileTyping = settings.smoothWhileTyping
        caretBlink = settings.caretBlink
        caretWidth = CGFloat(settings.caretWidth)
        typewriter = settings.typewriterMode
        typewriterOnClick = settings.typewriterOnClick
        focus = settings.focusMode
        focusScope = settings.focusScope
        focusDimming = CGFloat(settings.focusDimming)
        smartQuotes = settings.smartQuotes
        smartDashes = settings.smartDashes
        autocorrect = settings.autocorrect
        spellCheck = settings.spellCheck
        inlinePredictions = settings.inlinePredictions
        continueLists = settings.continueLists
    }

    // MARK: - Fonts

    static func baseFont(family: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        switch family {
        case SystemFontChoice.sans:
            return .systemFont(ofSize: size, weight: weight)
        case SystemFontChoice.mono:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case SystemFontChoice.serif, SystemFontChoice.rounded:
            let design: NSFontDescriptor.SystemDesign = family == SystemFontChoice.serif ? .serif : .rounded
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            if let d = base.fontDescriptor.withDesign(design), let f = NSFont(descriptor: d, size: size) {
                return f
            }
            return base
        default:
            let fm = NSFontManager.shared
            let w: Int
            switch weight {
            case .bold, .heavy, .black: w = 9
            case .semibold: w = 8
            case .medium: w = 6
            default: w = 5
            }
            if let f = fm.font(withFamily: family, traits: [], weight: w, size: size) { return f }
            if let f = NSFont(name: family, size: size) { return f }
            return .systemFont(ofSize: size, weight: weight)
        }
    }

    var bodyFont: NSFont { StyleConfig.baseFont(family: fontFamily, size: fontSize) }
    var boldFont: NSFont { bodyFont.withTraits(.bold) }
    var italicFont: NSFont { bodyFont.withTraits(.italic) }
    var boldItalicFont: NSFont { bodyFont.withTraits([.bold, .italic]) }
    var monoFont: NSFont { .monospacedSystemFont(ofSize: fontSize * 0.88, weight: .regular) }

    func headingFont(level: Int) -> NSFont {
        let scale: CGFloat
        if scaledHeadings {
            switch level {
            case 1: scale = 1.5
            case 2: scale = 1.25
            case 3: scale = 1.1
            default: scale = 1.0
            }
        } else {
            scale = 1.0
        }
        let size = (fontSize * scale).rounded()
        let weight: NSFont.Weight = level <= 2 ? .bold : .semibold
        return StyleConfig.baseFont(family: fontFamily, size: size, weight: weight).withTraits(.bold)
    }

    // MARK: - Paragraph styles

    var paragraphSpacing: CGFloat { (fontSize * paragraphSpacingEm).rounded() }

    func baseParagraphStyle() -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = lineHeightMultiple
        p.paragraphSpacing = paragraphSpacing
        p.lineBreakMode = .byWordWrapping
        return p
    }

    func headingParagraphStyle(level: Int) -> NSParagraphStyle {
        let p = baseParagraphStyle()
        p.paragraphSpacingBefore = level == 1 ? paragraphSpacing * 1.2 : paragraphSpacing * 0.8
        p.paragraphSpacing = paragraphSpacing * 0.6
        return p
    }

    func indentedParagraphStyle(firstLineIndent: CGFloat, headIndent: CGFloat, tight: Bool) -> NSParagraphStyle {
        let p = baseParagraphStyle()
        p.firstLineHeadIndent = firstLineIndent
        p.headIndent = headIndent
        if tight { p.paragraphSpacing = paragraphSpacing * 0.25 }
        return p
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: theme.text.nsColor,
            .paragraphStyle: baseParagraphStyle(),
        ]
        if letterSpacing != 0 { a[.kern] = letterSpacing }
        return a
    }

    /// Height of one body line, used for typewriter offsets.
    var bodyLineHeight: CGFloat {
        let f = bodyFont
        return (f.ascender - f.descender + f.leading) * lineHeightMultiple
    }
}
