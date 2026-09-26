import Foundation

/// What makes a document a daily note: it lives in the Daily folder and its
/// name is a date. The view, the ⌥⌘D command and the renamer all agree here.
enum DailyNotes {
    static let folder = "Daily"

    /// "Thursday, September 3, 2026" — the file name of a day's note.
    static func title(for date: Date) -> String { titleFormatter.string(from: date) }

    /// The day a note's name stands for, if it is one. "@September 3, 2026"
    /// counts too, for notes that began life as a date token.
    static func date(fromTitle title: String) -> Date? {
        var t = title.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("@") { t.removeFirst() }
        return titleFormatter.date(from: t) ?? tokenFormatter.date(from: t)
    }

    /// True for "Daily/Thursday, September 3, 2026.md" and nothing else.
    static func isDailyNote(relativePath: String) -> Bool {
        guard relativePath.hasPrefix(folder + "/") else { return false }
        let stem = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        return date(fromTitle: stem) != nil
    }

    /// A day as one number, 20260903 for September 3, 2026 — the key the
    /// calendar and the day index share.
    static func dayKey(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()

    private static let tokenFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()
}
