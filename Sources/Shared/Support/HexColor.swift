import AppKit
import SwiftUI

/// A color stored as "#RRGGBB" or "#RRGGBBAA". Codable as a plain string so
/// themes are easy to read and edit as JSON.
struct HexColor: Codable, Hashable {
    var hex: String

    init(_ hex: String) {
        self.hex = HexColor.normalize(hex)
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int((r * 255).rounded()), gi = Int((g * 255).rounded()), bi = Int((b * 255).rounded())
        let ai = Int((a * 255).rounded())
        if ai >= 255 {
            hex = String(format: "#%02X%02X%02X", ri, gi, bi)
        } else {
            hex = String(format: "#%02X%02X%02X%02X", ri, gi, bi, ai)
        }
    }

    init(_ color: Color) {
        self.init(NSColor(color))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        hex = HexColor.normalize(try c.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }

    private static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !t.hasPrefix("#") { t = "#" + t }
        return t
    }

    var components: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var s = hex
        s.removeFirst()
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else {
            return (0.5, 0.5, 0.5, 1)
        }
        if s.count == 6 {
            return (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255, 1)
        }
        return (CGFloat((v >> 24) & 0xFF) / 255, CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
    }

    var nsColor: NSColor {
        let c = components
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    var color: Color { Color(nsColor: nsColor) }

    func withAlpha(_ alpha: CGFloat) -> NSColor { nsColor.withAlphaComponent(alpha) }

    /// Perceived luminance 0...1 (sRGB, approximate).
    var luminance: CGFloat {
        let c = components
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }
}
