import AppKit

/// The Dock icon follows the Mac's appearance: the paper icon by day and, when
/// the system is in dark mode, the dark one — the same sheet at night. The
/// Dock and the app switcher show the running app's icon, so they change
/// live; Finder and Launchpad read the icon file and keep the paper one.
enum AppIcon {
    private static var observation: NSKeyValueObservation?
    private static var observer: NSObjectProtocol?

    private static let dark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon-Dark", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }()

    static func followAppearance() {
        guard dark != nil else { return }
        apply()
        observation = NSApp.observe(\.effectiveAppearance) { _, _ in apply() }
        // Belt and braces: the system posts this when the appearance flips.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { _ in apply() }
    }

    private static func apply() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // nil puts the bundle's own icon back.
        NSApp.applicationIconImage = isDark ? dark : nil
    }
}
