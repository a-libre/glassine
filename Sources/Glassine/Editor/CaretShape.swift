import AppKit
import SwiftUI

/// The shapes the caret can take. Each starts from the plain bar — the
/// rectangle a bar caret is — so every shape glides, blinks and sizes the
/// same way, and differs only in what is drawn with it: a bead on top, feet,
/// a tail, a halo, an outline, a block over the next letter, or, for the
/// wedge, a proofreader's mark under the baseline and no bar at all.
enum CaretShape: String, Codable, CaseIterable, Identifiable {
    case bar, pin, serif, wedge, ghost, comet, glow, hollow

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// A line for the settings, about the chosen shape.
    var blurb: String {
        switch self {
        case .bar: return "A plain bar, as wide as you set it."
        case .pin: return "A bar with a bead on top, like a pin in a map."
        case .serif: return "A bar with small feet, the way an I is set in a serif face."
        case .wedge: return "A proofreader's caret under the baseline, pointing at the place. No bar at all."
        case .ghost: return "A faint block over the next letter, with a hairline at its left edge."
        case .comet: return "A bar that trails a faint tail behind it, so you can see where it came from."
        case .glow: return "A bar with a soft halo."
        case .hollow: return "An outline of a bar, empty inside."
        }
    }

    /// What a shape is drawn from: a solid path in the caret colour, an
    /// optional faint one under it at a fraction of that colour, and whether
    /// the whole thing casts a glow.
    struct Geometry {
        var solid: CGPath
        var faint: CGPath?
        /// Whether the faint piece fades in from its far end toward the bar,
        /// the way a tail does, rather than being one flat tint.
        var fades: Bool = false
        var halo: Bool
    }

    /// How strong a fading piece is where it meets the bar.
    static let fadePeakAlpha: CGFloat = 0.7

    /// The geometry for a bar of the given size, in a space whose origin is
    /// the bar's top-left corner with y growing downward. `baseline` is the
    /// distance from the top of the bar to the baseline of its line; `slot`
    /// is the width of the character after the caret, or a stand-in for one
    /// where there is none. Pieces may reach outside the bar on every side.
    func geometry(barWidth cw: CGFloat, height h: CGFloat, baseline: CGFloat, slot: CGFloat) -> Geometry {
        let bar = CGRect(x: 0, y: 0, width: cw, height: h)
        let r = min(1, cw / 2, h / 2)
        let barPath = CGPath(roundedRect: bar, cornerWidth: r, cornerHeight: r, transform: nil)
        let cx = cw / 2
        switch self {
        case .bar:
            return Geometry(solid: barPath, faint: nil, halo: false)
        case .glow:
            return Geometry(solid: barPath, faint: nil, halo: true)
        case .pin:
            let d = max(5, cw * 1.8)
            let p = CGMutablePath()
            p.addPath(barPath)
            p.addEllipse(in: CGRect(x: cx - d / 2, y: 0.5 - d / 2, width: d, height: d))
            return Geometry(solid: p, faint: nil, halo: false)
        case .serif:
            let f = max(6, cw * 2.5)
            let t = max(1.5, cw * 0.45)
            let p = CGMutablePath()
            p.addPath(barPath)
            for y in [0, h - t] {
                p.addPath(CGPath(roundedRect: CGRect(x: cx - f / 2, y: y, width: f, height: t),
                                 cornerWidth: min(1, t / 2), cornerHeight: min(1, t / 2), transform: nil))
            }
            return Geometry(solid: p, faint: nil, halo: false)
        case .wedge:
            let w = max(8, cw * 2.5)
            let rise = w * 0.62
            let t = max(1.5, cw * 0.5)
            let top = baseline + 2
            let line = CGMutablePath()
            line.move(to: CGPoint(x: cx - w / 2, y: top + rise))
            line.addLine(to: CGPoint(x: cx, y: top))
            line.addLine(to: CGPoint(x: cx + w / 2, y: top + rise))
            let mark = line.copy(strokingWithWidth: t, lineCap: .round, lineJoin: .round, miterLimit: 10)
            return Geometry(solid: mark, faint: nil, halo: false)
        case .ghost:
            let hair = CGPath(rect: CGRect(x: 0, y: 0, width: min(cw, 1.5), height: h), transform: nil)
            let box = CGPath(roundedRect: CGRect(x: 0, y: 0, width: max(slot, 4), height: h),
                             cornerWidth: 2, cornerHeight: 2, transform: nil)
            return Geometry(solid: hair, faint: box, halo: false)
        case .comet:
            let length = max(18, cw * 5)
            let tail = CGMutablePath()
            tail.move(to: CGPoint(x: cx, y: 0))
            tail.addQuadCurve(to: CGPoint(x: -length, y: h / 2), control: CGPoint(x: -length * 0.3, y: h * 0.4))
            tail.addQuadCurve(to: CGPoint(x: cx, y: h), control: CGPoint(x: -length * 0.3, y: h * 0.6))
            tail.closeSubpath()
            return Geometry(solid: barPath, faint: tail, fades: true, halo: false)
        case .hollow:
            let w = max(cw + 1, 5)
            let outline = CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: 0.5, dy: 0.5),
                                 cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            let ring = outline.copy(strokingWithWidth: 1, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
            return Geometry(solid: ring, faint: nil, halo: false)
        }
    }

    /// How much of the caret colour the faint pieces get.
    static let faintAlpha: CGFloat = 0.26
}

/// One shape, drawn between two letters at settings size.
struct CaretShapeSwatch: View {
    let shape: CaretShape
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let cw: CGFloat = 3, h: CGFloat = 20
            let x = (size.width / 2 - cw / 2).rounded()
            let y = ((size.height - h) / 2).rounded()
            let cy = size.height / 2
            let letter = Text("n").font(.system(size: 16, design: .serif)).foregroundColor(.secondary)
            ctx.draw(letter, at: CGPoint(x: x - 2, y: cy), anchor: .trailing)
            ctx.draw(letter, at: CGPoint(x: x + 1.5, y: cy), anchor: .leading)
            let g = shape.geometry(barWidth: cw, height: h, baseline: 15, slot: 9.5)
            var shift = CGAffineTransform(translationX: x, y: y)
            if let faint = g.faint?.copy(using: &shift) {
                if g.fades {
                    let box = faint.boundingBox
                    let gradient = Gradient(colors: [color.opacity(0), color.opacity(CaretShape.fadePeakAlpha)])
                    ctx.fill(Path(faint), with: .linearGradient(gradient, startPoint: CGPoint(x: box.minX, y: box.midY),
                                                                endPoint: CGPoint(x: box.maxX, y: box.midY)))
                } else {
                    ctx.fill(Path(faint), with: .color(color.opacity(CaretShape.faintAlpha)))
                }
            }
            if let solid = g.solid.copy(using: &shift) {
                if g.halo { ctx.addFilter(.shadow(color: color.opacity(0.9), radius: 3)) }
                ctx.fill(Path(solid), with: .color(color))
            }
        }
    }
}

/// The row of shapes to pick from, each drawn as it will look.
struct CaretShapePicker: View {
    @Binding var shape: CaretShape
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CaretShape.allCases) { s in
                let picked = s == shape
                VStack(spacing: 3) {
                    CaretShapeSwatch(shape: s, color: color)
                        .frame(width: 46, height: 32)
                    Text(s.label)
                        .font(.caption2)
                        .foregroundStyle(picked ? .primary : .secondary)
                }
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(picked ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(picked ? Color.accentColor : Color.clear, lineWidth: 1.5))
                .contentShape(Rectangle())
                .onTapGesture { shape = s }
                .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
                .accessibilityLabel(s.label)
            }
        }
    }
}
