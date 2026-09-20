import SwiftUI

/// The full window background: the glass — a blur of what is behind the
/// window, or a backdrop of the app's own — under the theme's tint and grain.
struct GlassBackdrop: View {
    let theme: Theme
    var backdrop: BackdropPreset = .desktop
    var drifts: Bool = true
    var frost: Double = 0.3
    /// The grain over a backdrop; the theme's own grain lies over the desktop's blur.
    var grain: Double = 0.08

    var body: some View {
        ZStack {
            if !backdrop.isDesktop {
                BackdropCanvas(config: BackdropConfig(preset: backdrop, theme: theme, drifts: drifts, frost: frost))
                // The backdrop brings the colour; the theme's tint only harmonises
                // it, so it lies much lighter here than over the desktop's blur —
                // a veil, not a wash, or every set would take the tint's hue.
                theme.tint.color.opacity((theme.material == .opaque ? 0.6 : theme.tintOpacity) * 0.25)
                // Frost: a veil of light over the colour, the way frosted glass
                // pales what is behind it — squared, since a little haze goes a
                // long way over a dark ground. The shader pales the folds too.
                Color.white.opacity(frost * frost * (theme.isDark ? 0.10 : 0.4))
            } else if theme.material == .opaque {
                theme.tint.color
            } else {
                VisualEffectBackground(material: theme.material.effectMaterial)
                theme.tint.color.opacity(theme.tintOpacity)
            }
            GrainOverlay(opacity: backdrop.isDesktop ? theme.grain : grain)
        }
        .ignoresSafeArea()
    }
}
