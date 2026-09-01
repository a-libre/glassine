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

/// Draws rounded backgrounds: capsules for date tokens, softly rounded
/// rectangles for inline code. Everything else is inherited.
final class GlassineLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        let isDate = charRange.location < (textStorage?.length ?? 0)
            && textStorage?.attribute(DateToken.attributeKey, at: charRange.location, effectiveRange: nil) != nil
        color.setFill()
        for i in 0..<rectCount {
            var rect = rectArray[i]
            if isDate {
                rect = rect.insetBy(dx: -4, dy: -1.5)
                NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            } else {
                rect = rect.insetBy(dx: -1, dy: 0)
                NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5).fill()
            }
        }
    }
}
