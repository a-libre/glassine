import AppKit
import CoreImage
import SwiftUI

/// Blurs whatever is behind the window (desktop, other windows) — the base of the glass look.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var isEmphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = isEmphasized
        v.autoresizingMask = [.width, .height]
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = isEmphasized
    }
}

/// A subtle paper-grain overlay, generated once with Core Image.
struct GrainOverlay: NSViewRepresentable {
    var opacity: Double

    func makeNSView(context: Context) -> GrainView { GrainView() }
    func updateNSView(_ v: GrainView, context: Context) {
        v.alphaValue = opacity
        v.isHidden = opacity <= 0.001
    }

    final class GrainView: NSView {
        static let tile: NSImage? = {
            guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
            let cropped = noise.cropped(to: CGRect(x: 0, y: 0, width: 192, height: 192))
            guard let mono = CIFilter(name: "CIColorControls", parameters: [
                kCIInputImageKey: cropped, kCIInputSaturationKey: 0, kCIInputContrastKey: 1.0,
            ])?.outputImage else { return nil }
            let ctx = CIContext(options: [.useSoftwareRenderer: false])
            guard let cg = ctx.createCGImage(mono, from: cropped.extent) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: 96, height: 96))
        }()

        override var isOpaque: Bool { false }

        override func draw(_ dirtyRect: NSRect) {
            guard let tile = GrainView.tile else { return }
            NSColor(patternImage: tile).setFill()
            bounds.fill(using: .sourceOver)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The full window backdrop: blur + theme tint + grain.
struct GlassBackdrop: View {
    let theme: Theme

    var body: some View {
        ZStack {
            if theme.material == .opaque {
                theme.tint.color
            } else {
                VisualEffectBackground(material: theme.material.nsMaterial)
                theme.tint.color.opacity(theme.tintOpacity)
            }
            GrainOverlay(opacity: theme.grain)
        }
        .ignoresSafeArea()
    }
}

/// Configures the hosting NSWindow for the transparent, title-less look.
struct WindowConfigurator: NSViewRepresentable {
    let theme: Theme
    let floats: Bool

    func makeNSView(context: Context) -> ConfiguratorView {
        let v = ConfiguratorView()
        v.theme = theme
        v.floats = floats
        return v
    }

    func updateNSView(_ v: ConfiguratorView, context: Context) {
        v.theme = theme
        v.floats = floats
        v.configureIfPossible()
    }

    final class ConfiguratorView: NSView {
        var theme: Theme?
        var floats = false
        private var configured = false
        /// Watches the window's first resizes after launch; see configureIfPossible.
        private var frameGuard: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureIfPossible()
        }

        func configureIfPossible() {
            guard let window, let theme else { return }
            if !configured {
                configured = true
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
                window.titlebarSeparatorStyle = .none
                window.toolbarStyle = .unifiedCompact
                // Naming the frame restores the saved one at once, but SwiftUI then sizes
                // the window to its content before it is shown, and the autosave dutifully
                // records that over what you had. So put the saved frame back the moment
                // SwiftUI's pass changes it. Without this the app forgot its window size
                // on every launch.
                window.setFrameAutosaveName("GlassineMainWindow")
                if UserDefaults.standard.string(forKey: "NSWindow Frame GlassineMainWindow") != nil, !ScreenshotMode.isActive {
                    let saved = window.frame
                    let until = Date().addingTimeInterval(1.5)
                    frameGuard = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self, weak window] _ in
                        guard let self, let window else { return }
                        let done = Date() > until || window.frame != saved
                        if window.frame != saved, Date() <= until { window.setFrame(saved, display: false) }
                        if done, let guardToken = self.frameGuard {
                            NotificationCenter.default.removeObserver(guardToken)
                            self.frameGuard = nil
                        }
                    }
                }
                window.minSize = NSSize(width: 620, height: 400)
                window.tabbingMode = .disallowed
                window.acceptsMouseMovedEvents = true
            }
            // Keep the window opaque: behind-window blur still works (Finder's sidebar is the
            // same trick), and a non-opaque window would let clicks fall through to the desktop
            // wherever the backing store is transparent.
            if !window.isOpaque { window.isOpaque = true }
            // Floating: above other apps' windows, and — the part that matters with
            // Stage Manager on — allowed to stay on screen beside another app's set
            // instead of being swept off with the rest of Glassine.
            let level: NSWindow.Level = floats ? .floating : .normal
            if window.level != level { window.level = level }
            if floats != window.collectionBehavior.contains(.canJoinAllApplications) {
                if floats {
                    window.collectionBehavior.remove(.primary)
                    window.collectionBehavior.insert(.canJoinAllApplications)
                } else {
                    window.collectionBehavior.remove(.canJoinAllApplications)
                }
            }
            window.backgroundColor = theme.tint.nsColor
            let appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
            if window.appearance != appearance { window.appearance = appearance }
            window.invalidateShadow()
        }
    }
}
