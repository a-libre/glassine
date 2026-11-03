import AppKit
import SwiftUI

extension NSTextStorage {
    /// The text as an NSString, without a copy. `storage.string` bridges the
    /// storage's mutable string to a Swift String, and a mutable string is
    /// copied on the way — the whole document, on every read; the caret's
    /// own bookkeeping read it several times a keystroke. The mutable string
    /// is the live text itself, read in place.
    var ns: NSString { mutableString }
}

extension NSRange {
    var upperBoundValue: Int { location + length }
    func clamped(to length: Int) -> NSRange {
        let loc = max(0, min(location, length))
        let len = max(0, min(self.length, length - loc))
        return NSRange(location: loc, length: len)
    }
}

extension String {
    var nsLength: Int { (self as NSString).length }

    /// A file-system safe version of this string suitable for a file name stem.
    var sanitizedFileStem: String {
        var s = self
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>\u{0}")
        s = s.components(separatedBy: bad).joined(separator: "-")
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        if s.count > 80 {
            s = String(s.prefix(80)).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// Derives a human title from Markdown text: first non-empty line, with
    /// heading marks, list markers and emphasis stripped. Asked after every
    /// keystroke (the file is named from it), so it reads the text line by
    /// line and stops at the first that counts, rather than splitting the
    /// whole document into lines first.
    var derivedMarkdownTitle: String {
        let ns = self as NSString
        let length = ns.length
        var start = 0
        while start < length {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
            start = lineEnd
            if let title = String.title(ofLine: ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))) {
                return title
            }
            if lineEnd == lineStart { break }
        }
        return ""
    }

    private static let titleStrips: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: "^#{1,6}\\s*"), ""),
        (try! NSRegularExpression(pattern: "^>\\s*"), ""),
        (try! NSRegularExpression(pattern: "^([-*+]|\\d+[.)])\\s+(\\[[ xX]\\]\\s+)?"), ""),
        (try! NSRegularExpression(pattern: "!?\\[([^\\]]*)\\]\\([^)]*\\)"), "$1"),
        (try! NSRegularExpression(pattern: "[*_~`]"), ""),
    ]

    /// One line as a title, or nil when it is blank, a fence or a rule.
    private static func title(ofLine raw: String) -> String? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("```") || line.hasPrefix("---") { return nil }
        for (rx, template) in titleStrips {
            line = rx.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: line.nsLength), withTemplate: template)
        }
        line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }
}

extension URL {
    var isDirectoryURL: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    /// The file's modification date, read from the disk each time. (A URL
    /// caches its resource values, and off the main thread the cache is never
    /// cleared: a date asked for on the save queue after a write came back as
    /// the date from before it, and every save then looked like a change from
    /// outside.)
    var contentModificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    func pathRelative(to base: URL) -> String {
        let basePath = base.standardizedFileURL.path
        let path = standardizedFileURL.path
        if path == basePath { return "" }
        if path.hasPrefix(basePath + "/") {
            return String(path.dropFirst(basePath.count + 1))
        }
        return lastPathComponent
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let f = pow(10.0, Double(places))
        return (self * f).rounded() / f
    }
}

extension Date {
    /// "3 min. ago", "yesterday": the formatter is made once, since every
    /// row of the sidebar and every lit card asks for this as it is drawn.
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var shortRelative: String { Date.relative.localizedString(for: self, relativeTo: Date()) }
}

extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let desc = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits))
        if let f = NSFont(descriptor: desc, size: pointSize), f.fontDescriptor.symbolicTraits.contains(traits) {
            return f
        }
        // Fall back to the font manager for families without descriptor-based variants.
        var mask: NSFontTraitMask = []
        if traits.contains(.bold) { mask.insert(.boldFontMask) }
        if traits.contains(.italic) { mask.insert(.italicFontMask) }
        return NSFontManager.shared.convert(self, toHaveTrait: mask)
    }
}

extension View {
    @ViewBuilder
}

/// A tiny debouncer for main-thread work.
final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let delay: TimeInterval
    init(delay: TimeInterval) { self.delay = delay }
    func call(_ block: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    func cancel() { workItem?.cancel(); workItem = nil }
}
