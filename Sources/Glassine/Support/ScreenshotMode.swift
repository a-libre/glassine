import AppKit
import ImageIO

/// Lets the app photograph itself, for the App Store listing.
///
/// docs/appstore/screenshots.sh launches the sandboxed build once per picture:
///
///     open -n Glassine.app --args -glassine.shoot 1-editor.png \
///         -glassine.launchSettings <base64 JSON> -glassine.launchView review \
///         -glassine.launchCaret 224 -glassine.shootDelay 3
///
/// The app then sizes its window, waits for the view to settle, asks the
/// window server for a picture of that one window — named by its number, and
/// nothing else — so the glass comes out as the glass, writes an opaque PNG
/// into its own tmp folder, and quits. Only the app's own window is ever
/// named in the request, which is what keeps it clear of the Screen Recording
/// permission: nothing on the machine needs granting, and no other app's
/// window is ever touched.
///
/// The store pictures pass `-glassine.shootCapture 1` and get the fuller
/// composite instead — the window and everything beneath it, the backdrop
/// included, so the glass carries the backdrop's colour the way it does on
/// screen. macOS treats that request as screen recording and says so with a
/// notice each time, which is why it is not the default: the layout checks
/// that run all day never need it.
///
/// The glass needs something behind it to be glass, and a window captured on its
/// own has nothing behind it. So a backdrop window — a soft, generated wallpaper
/// — is put directly beneath the app's window, and both are captured together:
/// the blur is real, and the picture does not depend on whatever desktop the
/// machine happens to have.
///
/// Every setting arrives with the launch and is never saved (see AppSettings),
/// so a run leaves the real preferences alone.
enum ScreenshotMode {
    static var isActive: Bool { UserDefaults.standard.string(forKey: "glassine.shoot") != nil }
    private static var backdrop: NSWindow?

    /// Where the pictures go: the app's own temporary folder, which is inside
    /// its sandbox container and so the one place it can always write.
    static var outputFolder: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("glassine-shots", isDirectory: true)
    }

    static func runIfRequested() {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: "glassine.shoot") else { return }
        let size = parseSize(defaults.string(forKey: "glassine.launchWindow")) ?? NSSize(width: 1440, height: 900)
        let delay = defaults.string(forKey: "glassine.shootDelay").flatMap(Double.init) ?? 3
        let composite = defaults.bool(forKey: "glassine.shootCapture")
        // Two beats: one for SwiftUI to finish sizing the window, then the
        // real wait for the content — a web view in Review, a scan of the library.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let window = mainWindow() else { finish(name: name, error: "no main window"); return }
            place(window, size: size)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            showBackdrop(behind: window, dark: AppState.shared.theme.isDark)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // The window alone, asked for by its number: the one window of ours,
                // and nothing else. The backdrop beneath it is still on screen, so the
                // glass has it to blur. Screen coordinates here have their origin at
                // the top left of the main display.
                let id = CGWindowID(window.windowNumber)
                let screenHeight = NSScreen.screens.first?.frame.height ?? 0
                let f = window.frame
                let rect = CGRect(x: f.minX, y: screenHeight - f.maxY, width: f.width, height: f.height)
                if composite {
                    let below = CGWindowListCreateImage(rect, [.optionOnScreenBelowWindow, .optionIncludingWindow], id, [.bestResolution])
                    guard let image = below ?? CGWindowListCreateImage(rect, .optionIncludingWindow, id, [.bestResolution]),
                          image.width > 1, image.height > 1 else {
                        finish(name: name, error: "the window server returned no image for window \(id)"); return
                    }
                    write(image, name: name)
                    return
                }
                // The array holds the window number itself, pointer-sized, not a boxed number.
                let slot = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 1)
                defer { slot.deallocate() }
                slot[0] = UnsafeRawPointer(bitPattern: UInt(id))
                guard let array = CFArrayCreate(kCFAllocatorDefault, slot, 1, nil),
                      let image = CGImage(windowListFromArrayScreenBounds: rect, windowArray: array, imageOption: [.bestResolution]),
                      image.width > 1, image.height > 1 else {
                    finish(name: name, error: "the window server returned no image for window \(id)"); return
                }
                write(image, name: name)
            }
        }
    }

    private static func mainWindow() -> NSWindow? {
        NSApp.windows.first(where: { AppDelegate.isMainWindow($0) && $0.isVisible })
            ?? NSApp.windows.first(where: AppDelegate.isMainWindow)
    }

    /// The window at exactly this many points, centred on the screen. At the
    /// display's backing scale that is the pixel size App Store Connect wants:
    /// 1440×900 points is 2880×1800 pixels on any Retina Mac.
    private static func place(_ window: NSWindow, size: NSSize) {
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// A full-screen sheet of colour directly beneath the app's window, so the
    /// glass has something to blur. Dark for dark themes, light for light ones.
    private static func showBackdrop(behind window: NSWindow, dark: Bool) {
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = true
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.stationary, .ignoresCycle]
        w.contentView = BackdropView(dark: dark)
        w.orderFront(nil)
        w.order(.below, relativeTo: window.windowNumber)
        backdrop = w
    }

    /// Opaque RGB, because App Store Connect refuses an alpha channel.
    private static func write(_ image: CGImage, name: String) {
        let folder = outputFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            finish(name: name, error: "could not make a bitmap context"); return
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            finish(name: name, error: "could not encode the image"); return
        }
        CGImageDestinationAddImage(dest, flat, nil)
        guard CGImageDestinationFinalize(dest) else { finish(name: name, error: "could not write \(url.path)"); return }
        finish(name: name, error: nil)
    }

    /// A companion file says how it went, so the script never waits on a
    /// picture that is not coming.
    private static func finish(name: String, error: String?) {
        let folder = outputFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let note = folder.appendingPathComponent(name + ".status")
        try? (error ?? "ok").write(to: note, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// A line in the run's log, for the script to show when a picture fails.
    static func note(_ line: String) {
        guard isActive else { return }
        let url = outputFolder.appendingPathComponent("log.txt")
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        let text = "\(Date()) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(text.utf8)); h.closeFile() }
        else { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }

    /// A quiet wallpaper: one deep field with a few soft blooms of colour.
    final class BackdropView: NSView {
        let dark: Bool
        init(dark: Bool) { self.dark = dark; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }

        override func draw(_ dirtyRect: NSRect) {
            let b = bounds
            let base: NSColor
            let blooms: [(NSColor, CGFloat, CGFloat, CGFloat)]   // colour, centre x, centre y (0–1), radius (of width)
            if dark {
                base = NSColor(red: 0.07, green: 0.08, blue: 0.15, alpha: 1)
                blooms = [(NSColor(red: 0.42, green: 0.31, blue: 0.82, alpha: 0.55), 0.22, 0.72, 0.55),
                          (NSColor(red: 0.18, green: 0.62, blue: 0.76, alpha: 0.35), 0.82, 0.22, 0.45),
                          (NSColor(red: 0.88, green: 0.54, blue: 0.37, alpha: 0.22), 0.66, 0.88, 0.40)]
            } else {
                base = NSColor(red: 0.95, green: 0.94, blue: 0.92, alpha: 1)
                blooms = [(NSColor(red: 0.62, green: 0.77, blue: 0.91, alpha: 0.6), 0.2, 0.75, 0.55),
                          (NSColor(red: 0.95, green: 0.76, blue: 0.63, alpha: 0.5), 0.8, 0.3, 0.45),
                          (NSColor(red: 0.79, green: 0.72, blue: 0.92, alpha: 0.4), 0.6, 0.9, 0.40)]
            }
            base.setFill()
            b.fill()
            for (color, cx, cy, r) in blooms {
                let radius = b.width * r
                let center = NSPoint(x: b.minX + b.width * cx, y: b.minY + b.height * cy)
                let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                NSGradient(starting: color, ending: color.withAlphaComponent(0))?
                    .draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            }
        }
    }

    private static func parseSize(_ text: String?) -> NSSize? {
        guard let text, let x = text.firstIndex(of: "x"),
              let w = Double(text[..<x]), let h = Double(text[text.index(after: x)...]) else { return nil }
        return NSSize(width: w, height: h)
    }
}
