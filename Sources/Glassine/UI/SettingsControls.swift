import AppKit
import CoreText
import SwiftUI

// The pieces the Settings card is built from: panels of rows in the theme's
// own colours, a slider and a pill picker drawn to match the rest of the app,
// tiles for themes and backdrops, and two specimens — a piece of page set in
// the current type, and a line with a live caret — so a setting shows what
// it does instead of describing it.

// MARK: - Search

/// What is typed into the search field at the top of Settings. Rows that
/// match light up; the rest step back.
private struct SettingsQueryKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var settingsQuery: String {
        get { self[SettingsQueryKey.self] }
        set { self[SettingsQueryKey.self] = newValue }
    }
}

// MARK: - Panel and row

/// A group of rows on a faint rounded ground with a hairline round it, the
/// way the sidebar draws its rows — never the system's grouped form.
struct SettingsPanel<Content: View>: View {
    let theme: Theme
    var title: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.6)
                    .opacity(0.45)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.text.color.opacity(theme.isDark ? 0.05 : 0.035))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.text.color.opacity(theme.isDark ? 0.08 : 0.07), lineWidth: 1)
                )
        }
    }
}

/// One setting: its name, a line about it if it needs one, and the control
/// at the right. A row whose value is not the default offers, on hover, a
/// way back to it. While a search is typed the row lights up when it
/// matches and steps back when it does not.
struct SettingRow<Control: View>: View {
    let theme: Theme
    let title: String
    var caption: String? = nil
    var keywords: String = ""
    var isDefault: Bool = true
    var reset: (() -> Void)? = nil
    @ViewBuilder let control: () -> Control

    @Environment(\.settingsQuery) private var query
    @State private var hovering = false

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var matches: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(q)
            || (caption ?? "").localizedCaseInsensitiveContains(q)
            || keywords.localizedCaseInsensitiveContains(q)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let caption {
                    Text(caption)
                        .font(.system(size: 11))
                        .opacity(0.55)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let reset, !isDefault {
                Button(action: reset) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 0.55 : 0)
                .help("Back to the default")
            }
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.accent.color.opacity(searching && matches ? 0.14 : 0))
                .padding(3)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.text.color.opacity(0.06)).frame(height: 1)
        }
        .opacity(searching && !matches ? 0.38 : 1)
        .animation(.easeOut(duration: 0.15), value: query)
        .onHover { hovering = $0 }
    }
}

// MARK: - Controls

/// A switch in the theme's accent.
struct GlassToggle: View {
    let theme: Theme
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(theme.accent.color)
    }
}

/// A slider drawn in the theme's colours: a hairline track, the accent up
/// to the knob, and the value beside it in figures that count up and down.
struct GlassSlider: View {
    let theme: Theme
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var format: String = "%.0f"
    var scale: Double = 1
    var width: CGFloat = 150

    @State private var dragging = false
    @State private var hovering = false

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
    }

    private func set(fraction f: CGFloat) {
        let raw = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
        let stepped = step > 0 ? (raw / step).rounded() * step : raw
        value = min(range.upperBound, max(range.lowerBound, stepped))
    }

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let knob: CGFloat = 14
                let x = knob / 2 + fraction * (w - knob)
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.text.color.opacity(theme.isDark ? 0.14 : 0.12)).frame(height: 4)
                    Capsule().fill(theme.accent.color.opacity(0.9)).frame(width: max(0, x), height: 4)
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                        .frame(width: knob, height: knob)
                        .scaleEffect(dragging ? 1.18 : (hovering ? 1.08 : 1))
                        .offset(x: x - knob / 2)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            dragging = true
                            set(fraction: (g.location.x - knob / 2) / max(1, w - knob))
                        }
                        .onEnded { _ in dragging = false }
                )
            }
            .frame(width: width, height: 22)
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
            .animation(.easeOut(duration: 0.12), value: hovering)

            Text(String(format: format, value * scale))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .opacity(0.6)
                .frame(width: 54, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: value)
        }
    }
}

/// A row of choices in one capsule; the chosen one carries a pill of the
/// accent that slides between them.
struct PillPicker<T: Hashable>: View {
    let theme: Theme
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let picked = option == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background {
                            if picked {
                                Capsule().fill(theme.accent.color.opacity(theme.isDark ? 0.28 : 0.2))
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(picked ? 1 : 0.6)
            }
        }
        .padding(2)
        .background(Capsule().fill(theme.text.color.opacity(theme.isDark ? 0.07 : 0.05)))
    }
}

/// A small capsule button in the theme's colours; `prominent` fills it with
/// the accent.
struct GlassButtonStyle: ButtonStyle {
    let theme: Theme
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(theme: theme, prominent: prominent, pressed: configuration.isPressed) { configuration.label }
    }

    private struct Styled<Label: View>: View {
        let theme: Theme
        let prominent: Bool
        let pressed: Bool
        @ViewBuilder let label: () -> Label
        @State private var hovering = false

        var body: some View {
            label()
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(theme.text.color.opacity(prominent ? 0 : 0.1), lineWidth: 1))
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var fill: Color {
            if prominent {
                return theme.accent.color.opacity(pressed ? 0.4 : (hovering ? 0.32 : 0.24))
            }
            return theme.text.color.opacity(pressed ? 0.16 : (hovering ? 0.12 : 0.07))
        }
    }
}

/// A menu that looks like the rest of the card: the current choice in a
/// capsule with a small chevron.
struct GlassMenu<Label: View, Content: View>: View {
    let theme: Theme
    @ViewBuilder let label: () -> Label
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(GlassMenuButtonStyle(theme: theme))
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The capsule a GlassMenu's label sits in, with the chevron after it.
struct GlassMenuButtonStyle: ButtonStyle {
    let theme: Theme

    func makeBody(configuration: Configuration) -> some View {
        Styled(theme: theme, pressed: configuration.isPressed) { configuration.label }
    }

    private struct Styled<Label: View>: View {
        let theme: Theme
        let pressed: Bool
        @ViewBuilder let label: () -> Label
        @State private var hovering = false

        var body: some View {
            HStack(spacing: 6) {
                label()
                    .font(.system(size: 12))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.5)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 24)
            .background(Capsule().fill(theme.text.color.opacity(pressed ? 0.14 : (hovering ? 0.11 : 0.07))))
            .overlay(Capsule().strokeBorder(theme.text.color.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

/// A colour well with a name beside it, for the colour grids.
struct ColourCell: View {
    let theme: Theme
    let title: String
    @Binding var color: Color
    var supportsOpacity: Bool = false

    @Environment(\.settingsQuery) private var query

    private var dimmed: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && !title.localizedCaseInsensitiveContains(q) && !"colour color".contains(q.lowercased())
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 12.5))
            Spacer(minLength: 6)
            ColorPicker("", selection: $color, supportsOpacity: supportsOpacity)
                .labelsHidden()
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.text.color.opacity(0.06)).frame(height: 1)
        }
        .opacity(dimmed ? 0.38 : 1)
    }
}

// MARK: - Tiles

/// A theme as a small piece of its own page: its tint, a heading and two
/// lines of text in its colours, and its accent as a dot. The chosen one
/// wears a ring of its accent.
struct ThemeTile: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.tint.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aa")
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(Color(nsColor: theme.headingColor))
                        Capsule().fill(theme.text.color.opacity(0.6)).frame(width: 40, height: 3)
                        Capsule().fill(theme.text.color.opacity(0.35)).frame(width: 26, height: 3)
                    }
                    .padding(10)
                    Circle()
                        .fill(theme.accent.color)
                        .frame(width: 8, height: 8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(9)
                }
                .frame(height: 58)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? theme.accent.color : Color.primary.opacity(hovering ? 0.25 : 0.12),
                                      lineWidth: selected ? 2 : 1)
                )
                .scaleEffect(hovering && !selected ? 1.02 : 1)
                Text(theme.name)
                    .font(.system(size: 11.5, weight: selected ? .medium : .regular))
                    .lineLimit(1)
                    .opacity(selected ? 1 : 0.65)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(theme.name)
    }
}

extension BackdropPreset {
    /// The set's colours as the folds will show them under this theme —
    /// the same lightness the shader gives them — for a still tile.
    func tileColors(for theme: Theme) -> [Color] {
        let dark = theme.isDark
        let set = colors(for: theme)
        guard !set.isEmpty else { return [] }
        return set.map { hex in
            let c = hex.nsColor.usingColorSpace(.deviceRGB) ?? .gray
            let s = dark ? min(0.92, c.saturationComponent) : min(0.7, c.saturationComponent * 0.85)
            let b = dark ? min(max(c.brightnessComponent, 0.32), 0.62) * 0.82 : min(max(c.brightnessComponent, 0.78), 0.9)
            return Color(nsColor: NSColor(hue: c.hueComponent, saturation: s, brightness: b, alpha: 1))
        }
    }
}

/// A backdrop as a still tile: its colours folded into one another, or a
/// dashed frame for the desktop.
struct BackdropSwatch: View {
    let preset: BackdropPreset
    let theme: Theme

    var body: some View {
        if preset.isDesktop {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .overlay(
                    Image(systemName: "macwindow")
                        .font(.system(size: 15, weight: .light))
                        .opacity(0.45)
                )
        } else {
            let cs = preset.tileColors(for: theme)
            if #available(macOS 15, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.58, 0.42], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1],
                    ],
                    colors: (0..<9).map { cs[($0 * 2 + $0 / 3) % cs.count] }
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                LinearGradient(colors: cs, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

struct BackdropTile: View {
    let preset: BackdropPreset
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                BackdropSwatch(preset: preset, theme: theme)
                    .frame(height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? theme.accent.color : Color.primary.opacity(hovering ? 0.25 : 0.12),
                                          lineWidth: selected ? 2 : 1)
                    )
                    .scaleEffect(hovering && !selected ? 1.02 : 1)
                Text(preset.name)
                    .font(.system(size: 11.5, weight: selected ? .medium : .regular))
                    .lineLimit(1)
                    .opacity(selected ? 1 : 0.65)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(preset.name)
    }
}

// MARK: - Specimens

/// A piece of page set the way the editor sets it — the same fonts, line
/// height, spacing, indent and heading treatment — so the Type section shows
/// its settings instead of describing them.
struct TypeSpecimen: NSViewRepresentable {
    let config: StyleConfig

    func makeNSView(context: Context) -> NSTextView {
        let tv = NSTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        tv.textStorage?.setAttributedString(TypeSpecimen.text(for: config))
    }

    static func text(for config: StyleConfig) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var heading = config.baseAttributes
        heading[.font] = config.headingFont(level: 1)
        heading[.foregroundColor] = config.theme.headingColor
        heading[.paragraphStyle] = config.headingParagraphStyle(level: 1)
        out.append(NSAttributedString(string: "Morning pages\n", attributes: heading))
        let body = config.baseAttributes
        out.append(NSAttributedString(
            string: "Set the type the way you like to read it; the page behind this card follows along.\n"
                + "A second paragraph shows the space between them, and the indent, if you set one.",
            attributes: body))
        return out
    }
}

/// A line of the body text with a caret that lives: it glides from word to
/// word on the glide time, blinks the way it is set to, wears the chosen
/// shape at the chosen width — and, if the tricks are on, hops when it has
/// rested a while at the end of the line.
struct CaretSpecimen: View {
    let config: StyleConfig
    @State private var motion = Motion()

    private var lineHeight: CGFloat {
        let f = config.bodyFont
        return (f.ascender - f.descender).rounded()
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                motion.draw(in: &ctx, size: size, at: timeline.date.timeIntervalSinceReferenceDate, config: config)
            }
        }
        .frame(height: lineHeight + 28)
        .accessibilityLabel("A line of text with the caret gliding along it")
    }

    /// Where the caret is and where it is going. A class, so a frame can
    /// advance it from inside the drawing closure.
    final class Motion {
        static let sample = "The caret glides from word to word, then rests."
        private var line: CTLine?
        private var lineKey = ""
        private var stops: [CGFloat] = []
        private var slots: [CGFloat] = []
        private var index = 0
        private var from: CGFloat = 0
        private var to: CGFloat = 0
        private var start: TimeInterval = 0
        private var settled: TimeInterval = 0
        private var nextMove: TimeInterval = 0
        private var hopAt: TimeInterval = .infinity

        private func rebuild(_ config: StyleConfig) {
            let font = config.bodyFont
            let key = "\(font.fontName)/\(font.pointSize)/\(config.letterSpacing)/\(config.theme.text.hex)"
            guard key != lineKey else { return }
            lineKey = key
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: config.theme.text.nsColor]
            if config.letterSpacing != 0 { attrs[.kern] = config.letterSpacing }
            let text = NSAttributedString(string: Motion.sample, attributes: attrs)
            let ct = CTLineCreateWithAttributedString(text)
            line = ct
            let chars = Array(Motion.sample)
            stops = []
            slots = []
            for i in chars.indices where chars[i] != " " && (i == 0 || chars[i - 1] == " ") {
                let x = CTLineGetOffsetForStringIndex(ct, i, nil)
                let next = CTLineGetOffsetForStringIndex(ct, i + 1, nil)
                stops.append(x)
                slots.append(max(4, next - x))
            }
            stops.append(CTLineGetOffsetForStringIndex(ct, chars.count, nil))
            slots.append(font.pointSize * 0.55)
            index = min(index, stops.count - 1)
            from = stops[index]
            to = from
        }

        private func position(at t: TimeInterval, config: StyleConfig) -> CGFloat {
            guard config.smoothCaret, config.caretDuration > 0 else { return to }
            let p = min(1, max(0, (t - start) / config.caretDuration))
            return from + (to - from) * Motion.glide(CGFloat(p))
        }

        /// The editor's glide curve: a cubic Bézier with control points
        /// (0.25, 0.8) and (0.3, 1.0), solved for x.
        private static func glide(_ x: CGFloat) -> CGFloat {
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            let x1: CGFloat = 0.25, y1: CGFloat = 0.8, x2: CGFloat = 0.3, y2: CGFloat = 1.0
            func bx(_ u: CGFloat) -> CGFloat { 3 * (1 - u) * (1 - u) * u * x1 + 3 * (1 - u) * u * u * x2 + u * u * u }
            func by(_ u: CGFloat) -> CGFloat { 3 * (1 - u) * (1 - u) * u * y1 + 3 * (1 - u) * u * u * y2 + u * u * u }
            var lo: CGFloat = 0, hi: CGFloat = 1, u = x
            for _ in 0..<18 {
                u = (lo + hi) / 2
                if bx(u) < x { lo = u } else { hi = u }
            }
            return by(u)
        }

        private func blink(at t: TimeInterval, config: StyleConfig) -> CGFloat {
            guard config.caretBlink != .none else { return 1 }
            let rest = t - settled - 0.55
            guard rest > 0 else { return 1 }
            switch config.caretBlink {
            case .hard:
                return rest.truncatingRemainder(dividingBy: 1.0) < 0.5 ? 1 : 0
            case .soft:
                let p = rest.truncatingRemainder(dividingBy: 1.25) / 1.25
                let keys: [(CGFloat, CGFloat)] = [(0, 1), (0.35, 1), (0.55, 0.12), (0.75, 0.12), (1, 1)]
                for i in 1..<keys.count where CGFloat(p) <= keys[i].0 {
                    let (t0, v0) = keys[i - 1], (t1, v1) = keys[i]
                    let f = (CGFloat(p) - t0) / max(0.0001, t1 - t0)
                    let s = f * f * (3 - 2 * f)
                    return v0 + (v1 - v0) * s
                }
                return 1
            case .none:
                return 1
            }
        }

        private func advance(at t: TimeInterval, config: StyleConfig) {
            if nextMove == 0 { nextMove = t + 1.4; settled = t; hopAt = .infinity }
            if t >= hopAt + 0.9 { hopAt = .infinity }
            guard t >= nextMove, hopAt == .infinity else { return }
            from = position(at: t, config: config)
            index = (index + 1) % stops.count
            to = stops[index]
            start = t
            let duration = config.smoothCaret ? config.caretDuration : 0
            settled = t + duration
            if index == stops.count - 1 {
                // The end of the line: a longer rest, and a trick if they are on.
                if config.caretTricks {
                    hopAt = settled + 2.5
                    nextMove = hopAt + 1.4
                } else {
                    nextMove = settled + 2.2
                }
            } else {
                nextMove = settled + .random(in: 0.7...1.3)
            }
        }

        func draw(in ctx: inout GraphicsContext, size: CGSize, at t: TimeInterval, config: StyleConfig) {
            rebuild(config)
            guard let line, !stops.isEmpty else { return }
            advance(at: t, config: config)
            let font = config.bodyFont
            let h = (font.ascender - font.descender).rounded()
            let top = ((size.height - h) / 2).rounded()
            let baseline = top + font.ascender
            let left: CGFloat = 14

            ctx.withCGContext { cg in
                cg.saveGState()
                cg.textMatrix = .identity
                cg.translateBy(x: left, y: baseline)
                cg.scaleBy(x: 1, y: -1)
                CTLineDraw(line, cg)
                cg.restoreGState()
            }

            let x = left + position(at: t, config: config)
            var hop: CGFloat = 0
            if hopAt != .infinity, t >= hopAt {
                let p = min(1, (t - hopAt) / 0.42)
                hop = -7 * sin(CGFloat(p) * .pi)
            }
            let colour = Color(nsColor: config.theme.caretColor)
            // Steady while it performs, as in the editor.
            let alpha = hopAt != .infinity && t >= hopAt ? 1 : blink(at: t, config: config)
            let g = config.caretShape.geometry(barWidth: config.caretWidth, height: h, baseline: font.ascender, slot: slots[index])
            var shift = CGAffineTransform(translationX: x.rounded(), y: top + hop)
            if let faint = g.faint?.copy(using: &shift) {
                if g.fades {
                    let box = faint.boundingBox
                    let gradient = Gradient(colors: [colour.opacity(0), colour.opacity(CaretShape.fadePeakAlpha * alpha)])
                    ctx.fill(Path(faint), with: .linearGradient(gradient, startPoint: CGPoint(x: box.minX, y: box.midY),
                                                                endPoint: CGPoint(x: box.maxX, y: box.midY)))
                } else {
                    ctx.fill(Path(faint), with: .color(colour.opacity(CaretShape.faintAlpha * alpha)))
                }
            }
            if let solid = g.solid.copy(using: &shift) {
                var layer = ctx
                if g.halo { layer.addFilter(.shadow(color: colour.opacity(0.9 * alpha), radius: 3)) }
                layer.fill(Path(solid), with: .color(colour.opacity(alpha)))
            }
        }
    }
}
