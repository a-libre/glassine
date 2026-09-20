import SwiftUI
import QuartzCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The seam between the shared code and the two shells. Shared files name
// colours, fonts and the handful of things an app asks of its system through
// here, so the same line compiles for the Mac and for iOS. On the Mac every
// alias is the AppKit type it always was and every call below is the call it
// replaced — nothing here changes what the Mac app does.

#if os(macOS)
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformFontDescriptor = NSFontDescriptor
typealias PlatformImage = NSImage
typealias PlatformView = NSView
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformFontDescriptor = UIFontDescriptor
typealias PlatformImage = UIImage
typealias PlatformView = UIView
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

enum Platform {
    /// The system's Reduce Motion setting.
    static var reduceMotion: Bool {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        UIAccessibility.isReduceMotionEnabled
        #endif
    }

    /// Where, and under what name, a change to Reduce Motion is announced.
    static var reduceMotionChanged: (center: NotificationCenter, name: Notification.Name) {
        #if os(macOS)
        (NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        #else
        (NotificationCenter.default, UIAccessibility.reduceMotionStatusDidChangeNotification)
        #endif
    }

    /// Whether the app is the one in front.
    static var isActive: Bool {
        #if os(macOS)
        NSApp.isActive
        #else
        UIApplication.shared.applicationState == .active
        #endif
    }

    #if os(macOS)
    static let didBecomeActive = NSApplication.didBecomeActiveNotification
    static let willResignActive = NSApplication.willResignActiveNotification
    static let willTerminate = NSApplication.willTerminateNotification
    #else
    static let didBecomeActive = UIApplication.didBecomeActiveNotification
    static let willResignActive = UIApplication.willResignActiveNotification
    static let willTerminate = UIApplication.willTerminateNotification
    #endif

    /// Opens a link in the browser, or a file in whatever owns it.
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    /// Shows files in Finder. iOS has no counterpart an app may drive.
    static func reveal(_ urls: [URL]) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        #endif
    }

    /// Puts plain text on the clipboard, replacing what was there.
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    /// A view's opacity, animated by the system's own means.
    static func fade(_ view: PlatformView, to alpha: CGFloat, duration: TimeInterval, easeOut: Bool = false) {
        #if os(macOS)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            if easeOut { ctx.timingFunction = CAMediaTimingFunction(name: .easeOut) }
            view.animator().alphaValue = alpha
        }
        #else
        UIView.animate(withDuration: duration, delay: 0, options: easeOut ? [.curveEaseOut] : [], animations: { view.alpha = alpha })
        #endif
    }

    /// The pointer over something that drags sideways. Touch has no pointer to dress.
    static func pushResizeCursor() {
        #if os(macOS)
        NSCursor.resizeLeftRight.push()
        #endif
    }
    static func popCursor() {
        #if os(macOS)
        NSCursor.pop()
        #endif
    }

    #if !os(macOS)
    /// The height the status bar (or the island) takes from the top of the window.
    static var topSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }
    #endif

    /// How wide the app's window is showing, in points.
    static var windowWidth: CGFloat? {
        #if os(macOS)
        NSApp.keyWindow?.contentView?.bounds.width
        #else
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.bounds.width
        #endif
    }

    /// The name this device goes by, for the line a sync writes in its history.
    static var deviceName: String {
        #if os(macOS)
        Host.current().localizedName ?? "a Mac"
        #else
        UIDevice.current.name
        #endif
    }

    /// Every font family installed, as the system names them.
    static var fontFamilies: [String] {
        #if os(macOS)
        NSFontManager.shared.availableFontFamilies
        #else
        UIFont.familyNames
        #endif
    }

    /// A picture that ships inside the app, by its file's name.
    static func bundledImage(_ name: String) -> Image? {
        #if os(macOS)
        Bundle.main.image(forResource: name).map { Image(nsImage: $0) }
        #else
        UIImage(named: name).map { Image(uiImage: $0) }
        #endif
    }

    /// The app's icon as it is showing now.
    static var appIcon: Image {
        #if os(macOS)
        Image(nsImage: NSApp.applicationIconImage)
        #else
        Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
        #endif
    }
}

extension View {
    /// Esc, however the platform delivers it: the Mac's exit command, or the
    /// key itself from a keyboard attached to an iPhone or iPad.
    @ViewBuilder
    func onEscapeKey(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        onKeyPress(.escape) { action(); return .handled }
        #endif
    }
}

extension Color {
    /// SwiftUI's colour from the system's own colour type, whichever that is.
    init(platformColor: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}
