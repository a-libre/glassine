#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The demonstration copy's library — `build.sh --demo` makes "Glassine
/// Demo.app": the same app under a name of its own, so its settings are its
/// own, with the showcase pages from docs/appstore/library in place of a
/// library. Nothing of the real library, or of iCloud Drive, is ever in view:
/// a copy to take pictures of and record from.
///
/// The pages are written into an empty library with the daily notes dated
/// from today, so the Timelapse and the gallery look lived-in on whatever day
/// the demo is opened; Help → Reset Demo Library writes them fresh.
enum DemoLibrary {
    static let folderName = "Glassine Demo"

    /// ~/Library/Application Support/Glassine Demo/Library — in nobody's
    /// iCloud Drive and behind no permission prompt.
    static var rootURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("\(folderName)/Library", isDirectory: true)
    }

    /// The pages, copied into the bundle by build.sh.
    private static var source: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("DemoLibrary", isDirectory: true)
    }

    /// The gallery lays its cards out by last edit, so the pages most worth a
    /// look come first: hours ago, per page. The rest keep an older date.
    private static let order: [(path: String, hoursAgo: Double)] = [
        ("Welcome to Glassine.md", 9),
        ("Ideas/Names for the Boat.md", 6), ("Notes/Reading List.md", 5), ("Ideas/Small Rituals.md", 4),
        ("Ideas/A Letter to September.md", 3), ("Notes/Launch Checklist.md", 2), ("Essays/On Writing Slowly.md", 1),
    ]

    /// The pages the first look should have open and starred.
    static let opened = "Essays/On Writing Slowly.md"
    static let starred = ["Essays/On Writing Slowly.md", "Notes/Launch Checklist.md"]
    /// ("*documents" is the sidebar's Documents section itself.)
    static let expanded = ["*documents", "Essays", "Notes", "Ideas", "Daily"]

    /// Writes the pages into `root`. Daily/N.md becomes the note for N days
    /// ago; `{{DATE}}` in it is that day's title, and `{{TOKEN}}` or
    /// `{{TOKEN-3}}` anywhere is today, or three days ago, written the way a
    /// date token is.
    @discardableResult
    static func seed(into root: URL) -> Bool {
        guard let source, let items = try? FileManager.default.subpathsOfDirectory(atPath: source.path) else { return false }
        let fm = FileManager.default
        let cal = Calendar.current
        let now = Date()
        let dayBefore = now.addingTimeInterval(-2 * 86_400)
        for rel in items.sorted() {
            let from = source.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard rel.hasSuffix(".md"), fm.fileExists(atPath: from.path, isDirectory: &isDir), !isDir.boolValue,
                  var text = try? String(contentsOf: from, encoding: .utf8) else { continue }
            var target = root.appendingPathComponent(rel)
            var stamp = dayBefore
            if rel.hasPrefix(DailyNotes.folder + "/"),
               let ago = Int((rel as NSString).lastPathComponent.dropLast(3)),
               let day = cal.date(byAdding: .day, value: -ago, to: cal.startOfDay(for: now)) {
                let title = DailyNotes.title(for: day)
                text = text.replacingOccurrences(of: "{{DATE}}", with: title)
                target = root.appendingPathComponent(DailyNotes.folder + "/" + title.sanitizedFileStem + ".md")
                stamp = cal.date(bySettingHour: 14, minute: 0, second: 0, of: day) ?? day
            }
            if let hours = order.first(where: { $0.path == rel })?.hoursAgo { stamp = now.addingTimeInterval(-hours * 3600) }
            write(tokens(in: text, now: now), to: target, dated: stamp)
        }
        let welcome = order.first { $0.path == "Welcome to Glassine.md" }?.hoursAgo ?? 9
        write(WelcomeDocument.text, to: root.appendingPathComponent("Welcome to Glassine.md"), dated: now.addingTimeInterval(-welcome * 3600))
        return true
    }

    private static func write(_ text: String, to url: URL, dated stamp: Date) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url, options: .atomic)
        try? fm.setAttributes([.creationDate: stamp, .modificationDate: stamp], ofItemAtPath: url.path)
    }

    private static let tokenPattern = try! NSRegularExpression(pattern: "\\{\\{TOKEN(?:-(\\d+))?\\}\\}")

    private static func tokens(in text: String, now: Date) -> String {
        guard text.contains("{{TOKEN") else { return text }
        let ns = NSMutableString(string: text)
        for m in tokenPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let ago = m.range(at: 1).location == NSNotFound ? 0 : (Int(ns.substring(with: m.range(at: 1))) ?? 0)
            let date = Calendar.current.date(byAdding: .day, value: -ago, to: now) ?? now
            ns.replaceCharacters(in: m.range, with: DateToken.format(date))
        }
        return ns as String
    }

    /// The App Store's picture size, in points: 2880 × 1800 pixels on a
    /// Retina display, one of the four sizes the store takes for a Mac.
    static let pictureSize = CGSize(width: 1440, height: 900)

    /// Puts the main window at the picture size, centred on its screen.
    static func placeWindowForPictures() {
        #if os(macOS)
        guard let window = NSApp.windows.first(where: { AppDelegate.isMainWindow($0) && $0.isVisible })
                ?? NSApp.windows.first(where: AppDelegate.isMainWindow) else { return }
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let size = pictureSize
        let origin = CGPoint(x: (screen.midX - size.width / 2).rounded(), y: (screen.midY - size.height / 2).rounded())
        window.setFrame(CGRect(origin: origin, size: size), display: true, animate: true)
        #endif
    }
}
