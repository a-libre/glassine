import AppKit
import SwiftUI

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
    /// heading marks, list markers and emphasis stripped.
    var derivedMarkdownTitle: String {
        for rawLine in self.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("```") || line.hasPrefix("---") { continue }
            line = line.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "^>\\s*", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "^([-*+]|\\d+[.)])\\s+(\\[[ xX]\\]\\s+)?", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "!?\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: "[*_~`]", with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty { return line }
        }
        return ""
    }
}

extension URL {
    var isDirectoryURL: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    var contentModificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
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
    var shortRelative: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
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
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
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
