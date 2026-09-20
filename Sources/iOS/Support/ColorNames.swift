import UIKit

// Shared code reads colours through a few names AppKit gave them. UIColor has
// the same facts under other names; these are those names, for iOS only.

/// The colour spaces shared code asks for. UIColor is sRGB already (extended
/// where it needs to be), so asking for either is asking for the colour itself.
enum PlatformColorSpace { case sRGB, deviceRGB }

extension UIColor {
    convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    func usingColorSpace(_ space: PlatformColorSpace) -> UIColor? { self }

    private var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
    private var hsba: (h: CGFloat, s: CGFloat, b: CGFloat, a: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b, a)
    }
    var redComponent: CGFloat { rgba.r }
    var greenComponent: CGFloat { rgba.g }
    var blueComponent: CGFloat { rgba.b }
    var alphaComponent: CGFloat { rgba.a }
    var hueComponent: CGFloat { hsba.h }
    var saturationComponent: CGFloat { hsba.s }
    var brightnessComponent: CGFloat { hsba.b }
}

extension UIColor {
    /// A colour part of the way from this one to another, component by
    /// component, as AppKit's method of the same name mixes them.
    func blended(withFraction fraction: CGFloat, of other: UIColor) -> UIColor? {
        let t = max(0, min(1, fraction)), a = rgba, b = other.rgba
        return UIColor(red: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t,
                       blue: a.b + (b.b - a.b) * t, alpha: a.a + (b.a - a.a) * t)
    }
}
