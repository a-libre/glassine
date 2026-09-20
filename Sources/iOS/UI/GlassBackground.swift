import SwiftUI
import UIKit

/// The system's blur, under the names the shared views already use for the
/// Mac's materials. There is no desktop behind an iOS app, so "behind the
/// window" and "within the window" are the same thing here: a blur of
/// whatever the app itself has drawn underneath.
struct VisualEffectBackground: UIViewRepresentable {
    enum Material { case underWindowBackground, hudWindow, sidebar, popover, titlebar, windowBackground }
    enum BlendingMode { case behindWindow, withinWindow }

    var material: Material
    var blendingMode: BlendingMode = .behindWindow

    private var style: UIBlurEffect.Style {
        switch material {
        case .underWindowBackground, .windowBackground: return .systemUltraThinMaterial
        case .hudWindow: return .systemThickMaterial
        case .sidebar: return .systemMaterial
        case .popover: return .systemThinMaterial
        case .titlebar: return .systemChromeMaterial
        }
    }

    func makeUIView(context: Context) -> UIVisualEffectView { UIVisualEffectView(effect: UIBlurEffect(style: style)) }
    func updateUIView(_ v: UIVisualEffectView, context: Context) { v.effect = UIBlurEffect(style: style) }
}

/// A subtle paper-grain overlay, generated once with Core Image — the same
/// tile the Mac lays down, tiled by UIKit.
struct GrainOverlay: UIViewRepresentable {
    var opacity: Double

    func makeUIView(context: Context) -> GrainView { GrainView() }
    func updateUIView(_ v: GrainView, context: Context) {
        v.alpha = opacity
        v.isHidden = opacity <= 0.001
    }

    final class GrainView: UIView {
        static let tile: UIImage? = {
            guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
            let cropped = noise.cropped(to: CGRect(x: 0, y: 0, width: 192, height: 192))
            guard let mono = CIFilter(name: "CIColorControls", parameters: [
                kCIInputImageKey: cropped, kCIInputSaturationKey: 0, kCIInputContrastKey: 1.0,
            ])?.outputImage else { return nil }
            let ctx = CIContext(options: [.useSoftwareRenderer: false])
            guard let cg = ctx.createCGImage(mono, from: cropped.extent) else { return nil }
            return UIImage(cgImage: cg, scale: 2, orientation: .up)   // 192 px → a 96 pt tile
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isOpaque = false
            isUserInteractionEnabled = false
            if let tile = GrainView.tile { backgroundColor = UIColor(patternImage: tile) }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
    }
}

extension View {
    /// What the root view asks of its window. An iOS scene is the size the
    /// device makes it and has no title bar to hide, so: nothing.
    func windowChrome(theme: Theme, floats: Bool) -> some View { self }
}
