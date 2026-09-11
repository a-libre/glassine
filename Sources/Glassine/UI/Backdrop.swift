import AppKit
import Metal
import QuartzCore
import SwiftUI

// MARK: - What sits behind the glass

/// The glass shows whatever is behind the window — the desktop, usually. That
/// is the look when the wallpaper is right, and nothing much when it is not:
/// a plain grey desktop, or a picture that fights the page. A backdrop puts
/// folds of colour behind the glass instead, inside the window — deep,
/// sweeping, slowly moving — so the glass has something worth looking
/// through wherever it is. A backdrop is a set of three to five colours: the
/// built-in sets, or one of the user's own, made by duplicating a set and
/// changing its colours in Settings → Themes → Behind the glass.
struct BackdropPreset: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// Three to five. Their hue and saturation are what count; the theme sets
    /// the lightness — deep on a dark theme, pale on a light one — so the
    /// text stays readable over every part. The first sets the ground.
    var colors: [HexColor]
    var isBuiltIn: Bool = false

    static let desktopID = "desktop"
    static let auroraID = "aurora"
    static let minColors = 3
    static let maxColors = 5

    var isDesktop: Bool { id == BackdropPreset.desktopID }
    var isAurora: Bool { id == BackdropPreset.auroraID }

    /// The colours the folds run through under this theme. Aurora's come
    /// from the theme itself — its tint and its accent, and hues either side.
    func colors(for theme: Theme) -> [HexColor] {
        guard isAurora else { return colors }
        let tint = theme.tint.nsColor.usingColorSpace(.deviceRGB) ?? .gray
        let accent = theme.accent.nsColor.usingColorSpace(.deviceRGB) ?? .blue
        let t = tint.hueComponent * 360
        let a = accent.hueComponent * 360
        // Little saturation in the tint means a neutral theme: keep the
        // colours quiet rather than inventing a colour it never had.
        let s = max(0.3, min(0.75, tint.saturationComponent + 0.3))
        let between = t + (((a - t + 540).truncatingRemainder(dividingBy: 360)) - 180) / 2
        return [hsb(t, s), hsb(a, min(0.85, s + 0.15)), hsb(t + 30, s * 0.9), hsb(between, s), hsb(t - 30, s * 0.9)]
    }

    /// A line about the set, for the editor.
    var blurb: String {
        switch id {
        case BackdropPreset.desktopID: return "No backdrop: the window is a blur of whatever is behind it — the desktop, or the windows behind."
        case BackdropPreset.auroraID: return "The theme's own colours — its tint and its accent, and hues either side of them — run through the folds. Changes with the theme."
        case "dusk": return "Indigo, cobalt and violet, with a thread of magenta."
        case "nebula": return "Magenta, indigo and teal."
        case "ocean": return "Navy, cyan and teal, with a touch of violet."
        case "borealis": return "Green, teal and violet."
        case "ember": return "Crimson, orange and gold, with plum."
        case "sunset": return "Violet, orange, rose and gold."
        case "moss": return "Green, lime and teal, with gold."
        case "rose": return "Rose, peach, mauve and coral."
        case "graphite": return "Grey, barely tinted."
        default: return ""
        }
    }

    /// A colour by hue (degrees) and saturation, at the middle lightness the
    /// theme will move anyway.
    static func hsb(_ hue: CGFloat, _ saturation: CGFloat, _ brightness: CGFloat = 0.55) -> HexColor {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        return HexColor(NSColor(hue: h / 360, saturation: saturation, brightness: brightness, alpha: 1))
    }
    private func hsb(_ hue: CGFloat, _ saturation: CGFloat) -> HexColor { BackdropPreset.hsb(hue, saturation) }

    static let desktop = BackdropPreset(id: desktopID, name: "Desktop", colors: [], isBuiltIn: true)
    static let aurora = BackdropPreset(id: auroraID, name: "Aurora", colors: [], isBuiltIn: true)
    static let dusk = BackdropPreset(id: "dusk", name: "Dusk", isBuiltIn: true,
                                     hues: [(250, 0.8), (218, 0.85), (282, 0.75), (312, 0.6), (262, 0.7)])
    static let nebula = BackdropPreset(id: "nebula", name: "Nebula", isBuiltIn: true,
                                       hues: [(300, 0.7), (240, 0.8), (182, 0.75), (268, 0.7), (335, 0.6)])
    static let ocean = BackdropPreset(id: "ocean", name: "Ocean", isBuiltIn: true,
                                      hues: [(222, 0.85), (190, 0.8), (168, 0.7), (255, 0.55), (205, 0.8)])
    static let borealis = BackdropPreset(id: "borealis", name: "Borealis", isBuiltIn: true,
                                         hues: [(145, 0.75), (185, 0.7), (265, 0.6), (100, 0.65), (200, 0.7)])
    static let ember = BackdropPreset(id: "ember", name: "Ember", isBuiltIn: true,
                                      hues: [(352, 0.8), (24, 0.9), (42, 0.85), (322, 0.6), (10, 0.8)])
    static let sunset = BackdropPreset(id: "sunset", name: "Sunset", isBuiltIn: true,
                                       hues: [(275, 0.7), (25, 0.85), (345, 0.7), (45, 0.8), (245, 0.75)])
    static let moss = BackdropPreset(id: "moss", name: "Moss", isBuiltIn: true,
                                     hues: [(130, 0.7), (85, 0.7), (175, 0.6), (50, 0.6), (155, 0.7)])
    static let rose = BackdropPreset(id: "rose", name: "Rose", isBuiltIn: true,
                                     hues: [(340, 0.7), (20, 0.65), (300, 0.5), (5, 0.7), (330, 0.6)])
    static let graphite = BackdropPreset(id: "graphite", name: "Graphite", isBuiltIn: true,
                                         hues: [(220, 0.08), (240, 0.06), (200, 0.08), (260, 0.06), (230, 0.05)])
    static let builtIns: [BackdropPreset] = [desktop, aurora, dusk, nebula, ocean, borealis, ember, sunset, moss, rose, graphite]

    init(id: String, name: String, colors: [HexColor], isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.colors = colors
        self.isBuiltIn = isBuiltIn
    }

    private init(id: String, name: String, isBuiltIn: Bool, hues: [(CGFloat, CGFloat)]) {
        self.init(id: id, name: name, colors: hues.map { BackdropPreset.hsb($0.0, $0.1) }, isBuiltIn: isBuiltIn)
    }

    func renamed(_ newName: String) -> BackdropPreset {
        var p = self
        p.id = UUID().uuidString
        p.name = newName
        p.isBuiltIn = false
        return p
    }
}

/// The user's own backdrops, kept beside the custom themes.
final class BackdropStore: ObservableObject {
    static let defaultsKey = "glassine.customBackdrops.v1"

    @Published var custom: [BackdropPreset] {
        didSet {
            persist()
            // Each edit is a step ⌘Z in Settings can take back; a run of
            // edits to one backdrop inside a second is one step.
            let before = oldValue
            guard before != custom else { return }
            let byID = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let nowByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let keys = Set(byID.keys).union(nowByID.keys).filter { byID[$0] != nowByID[$0] }
            SettingsUndo.shared.note(keys: Set(keys.map { "backdrop." + $0 })) { [weak self] in self?.custom = before }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: BackdropStore.defaultsKey),
           let decoded = try? JSONDecoder().decode([BackdropPreset].self, from: data) {
            custom = decoded
        } else {
            custom = []
        }
    }

    var all: [BackdropPreset] { BackdropPreset.builtIns + custom }

    func preset(id: String) -> BackdropPreset {
        all.first(where: { $0.id == id }) ?? BackdropPreset.desktop
    }

    func update(_ preset: BackdropPreset) {
        guard !preset.isBuiltIn else { return }
        if let i = custom.firstIndex(where: { $0.id == preset.id }) {
            custom[i] = preset
        } else {
            custom.append(preset)
        }
    }

    /// A copy to edit. Aurora's copy takes the colours it has under the
    /// theme of the moment; the desktop has none to copy, so its copy is Dusk's.
    @discardableResult
    func duplicate(_ preset: BackdropPreset, for theme: Theme) -> BackdropPreset {
        var copy = preset.renamed(preset.name + " Copy")
        copy.colors = preset.isDesktop ? BackdropPreset.dusk.colors : preset.colors(for: theme)
        custom.append(copy)
        return copy
    }

    func delete(_ preset: BackdropPreset) {
        custom.removeAll { $0.id == preset.id }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: BackdropStore.defaultsKey)
        }
    }
}

/// Everything the view needs to draw a backdrop, and nothing that changes
/// without the drawing having to.
struct BackdropConfig: Equatable {
    var colors: [HexColor]
    var isDark: Bool
    var drifts: Bool
    var frost: Double

    init(preset: BackdropPreset, theme: Theme, drifts: Bool, frost: Double) {
        colors = preset.colors(for: theme)
        isDark = theme.isDark
        self.drifts = drifts && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.frost = frost
    }
}

// MARK: - The view

/// Folds of colour, like silk lit from one side: a field of noise warped
/// through itself twice, so that it sweeps in long bands, each with a lit
/// side, a shadowed side and a thin bright edge where it turns. A small
/// Metal shader draws it — at a quarter of the window's size, since there is
/// nothing sharp in it, and twenty times a second while it drifts — so it
/// costs the writing nothing. Built dark first: on a dark theme the ground is
/// near black and the colour lives in the folds, deep rather than bright, so
/// pale text stays readable over every part of it. The clock stops while the
/// window is covered or hidden.
final class BackdropView: NSView {
    var config: BackdropConfig {
        didSet {
            guard config != oldValue else { return }
            applyConfig()
            updateClock()
            render()
        }
    }

    private let metalLayer = CAMetalLayer()
    private let device = MTLCreateSystemDefaultDevice()
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var uniforms = BackdropUniforms()
    private var clock: Timer?
    private var time: Float = 0
    private var occlusionObserver: NSObjectProtocol?
    private var motionObserver: NSObjectProtocol?
    private static let framesPerSecond = 20.0
    private static let renderScale: CGFloat = 0.25

    init(config: BackdropConfig) {
        self.config = config
        super.init(frame: .zero)
        layer = metalLayer
        wantsLayer = true
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        metalLayer.magnificationFilter = .linear
        setUpMetal()
        applyConfig()
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateClock() }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        clock?.invalidate()
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o) }
        if let o = motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    override var isOpaque: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let scale = (window?.backingScaleFactor ?? 2) * BackdropView.renderScale
        let size = CGSize(width: max(64, (bounds.width * scale).rounded()), height: max(64, (bounds.height * scale).rounded()))
        if metalLayer.drawableSize != size {
            metalLayer.drawableSize = size
            uniforms.aspect = Float(size.width / size.height)
            render()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o) }
        occlusionObserver = nil
        guard let window else { clock?.invalidate(); clock = nil; return }
        metalLayer.contentsScale = window.backingScaleFactor
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in self?.updateClock() }
        needsLayout = true
        updateClock()
    }

    // MARK: Metal

    private func setUpMetal() {
        guard let device else { return }
        do {
            let library = try device.makeLibrary(source: BackdropView.shader, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "backdropVertex")
            desc.fragmentFunction = library.makeFunction(name: "backdropFragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
            queue = device.makeCommandQueue()
        } catch {
            NSLog("Glassine: backdrop shader failed to build: \(error)")
        }
    }

    /// The palette, as the shader wants it: the set's colours in order — a
    /// ramp the folds run round, so every colour has folds of its own — one
    /// for the bright edge, and the ground. The set's hues and saturations
    /// are kept; the lightness is the theme's — on a dark theme deep, never
    /// bright, over a ground close to black; on a light theme pale over near
    /// white. Frost is the shader's to apply.
    private func applyConfig() {
        let dark = config.isDark
        let colors = config.colors.isEmpty ? BackdropPreset.dusk.colors : config.colors
        let count = min(colors.count, BackdropPreset.maxColors)
        func hsb(_ i: Int) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
            let c = colors[i % colors.count].nsColor.usingColorSpace(.deviceRGB) ?? .gray
            return (c.hueComponent, c.saturationComponent, c.brightnessComponent)
        }
        func rgb(_ c: NSColor) -> SIMD4<Float> {
            let s = c.usingColorSpace(.sRGB) ?? c
            return SIMD4(Float(s.redComponent), Float(s.greenComponent), Float(s.blueComponent), 1)
        }
        let ground = hsb(0)
        uniforms.ground = rgb(NSColor(
            hue: ground.h, saturation: ground.s * (dark ? 0.7 : 0.2),
            brightness: dark ? 0.045 : 0.965, alpha: 1))
        uniforms.ground.w = Float(count)   // how many of the slots the ramp runs round
        var slots: [SIMD4<Float>] = []
        for i in 0..<BackdropPreset.maxColors {
            let c = hsb(i)
            let saturation = dark ? min(0.92, c.s) : min(0.7, c.s * 0.85)
            let brightness = dark ? min(max(c.b, 0.32), 0.62) : min(max(c.b, 0.78), 0.9)
            slots.append(rgb(NSColor(hue: c.h, saturation: saturation, brightness: brightness, alpha: 1)))
        }
        // The edge: the same silk, catching the light.
        let edge = hsb(1)
        slots.append(rgb(NSColor(hue: edge.h, saturation: dark ? 0.35 : 0.12,
                                 brightness: dark ? 0.85 : 1, alpha: 1)))
        uniforms.colors = (slots[0], slots[1], slots[2], slots[3], slots[4], slots[5])
        uniforms.dark = dark ? 1 : 0
        uniforms.frost = Float(config.frost)
        metalLayer.backgroundColor = NSColor(red: CGFloat(uniforms.ground.x), green: CGFloat(uniforms.ground.y),
                                             blue: CGFloat(uniforms.ground.z), alpha: 1).cgColor
    }

    /// Ticking while the window can be seen and the backdrop drifts; a
    /// still picture otherwise.
    private func updateClock() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        let running = visible && config.drifts && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if running, clock == nil {
            let step = 1 / BackdropView.framesPerSecond
            let timer = Timer(timeInterval: step, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.time += Float(step)
                self.render()
            }
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
        } else if !running, let timer = clock {
            timer.invalidate()
            clock = nil
        }
    }

    private func render() {
        guard let pipeline, let queue, metalLayer.drawableSize.width > 0,
              let drawable = metalLayer.nextDrawable() else { return }
        uniforms.time = time
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        withUnsafeBytes(of: &uniforms) { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// Laid out to match `Uniforms` in the shader. `ground.w` carries the
    /// number of colours in the ramp.
    private struct BackdropUniforms {
        var time: Float = 0
        var aspect: Float = 1
        var dark: Float = 1
        var frost: Float = 0
        var ground = SIMD4<Float>(0, 0, 0, 3)
        var colors: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) =
            (.zero, .zero, .zero, .zero, .zero, .zero)
    }

    /// One triangle over the whole layer, and a fragment shader that warps a
    /// field of value noise through itself twice (after Quílez), reads the
    /// folds off it as sweeping bands, runs the set's colours round them as
    /// a ramp — so three, four or five colours are on screen at once, each
    /// with folds of its own — and lights them.
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms { float time; float aspect; float dark; float frost; float4 ground; float4 colors[6]; };
    struct V2F { float4 position [[position]]; float2 uv; };

    vertex V2F backdropVertex(uint id [[vertex_id]]) {
        float2 corners[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        V2F o;
        o.position = float4(corners[id], 0.0, 1.0);
        o.uv = corners[id] * 0.5 + 0.5;
        return o;
    }

    static float hash21(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    static float vnoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash21(i), hash21(i + float2(1.0, 0.0)), u.x),
                   mix(hash21(i + float2(0.0, 1.0)), hash21(i + float2(1.0, 1.0)), u.x), u.y);
    }

    static float fbm(float2 p, int octaves) {
        float v = 0.0, a = 0.5;
        float2x2 m = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
        for (int i = 0; i < octaves; i++) { v += a * vnoise(p); p = m * p * 2.0 + float2(7.3, 1.9); a *= 0.5; }
        return v;
    }

    static float luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
    static float chroma(float3 c) { return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b)); }

    // A blend that keeps its colour: mixed in RGB, then the chroma put back
    // to what the two ends would average, so two hues far apart do not go
    // grey between them.
    static float3 chromaMix(float3 a, float3 b, float t) {
        float3 m = mix(a, b, t);
        float target = mix(chroma(a), chroma(b), t);
        float L = luma(m);
        return saturate(L + (m - L) * (target / max(chroma(m), 1e-4)));
    }

    // The set's colours as a loop: u from 0 to 1 runs through all of them
    // and back to the first.
    static float3 ramp(constant float4* colors, int n, float u) {
        float idx = u * float(n);
        int i0 = int(floor(idx)) % n;
        int i1 = (i0 + 1) % n;
        float tt = fract(idx);
        tt = tt * tt * (3.0 - 2.0 * tt);
        return chromaMix(colors[i0].rgb, colors[i1].rgb, tt);
    }

    fragment float4 backdropFragment(V2F in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float2 p = float2(in.uv.x * u.aspect, in.uv.y) + float2(3.7, 11.2);
        float t = u.time * 0.045;
        // Two rounds of warping on a smooth field: the sweeps come from
        // here, and stay long and soft because the field is.
        float2 pw = p * 0.7;
        float2 q = float2(fbm(pw + float2(t * 0.6, -t * 0.4), 2), fbm(pw + float2(5.2, 1.3) - t * 0.5, 2));
        float2 r = float2(fbm(pw + 3.0 * q + float2(1.7, 9.2) + t * 0.2, 2), fbm(pw + 3.0 * q + float2(8.3, 2.8) - t * 0.25, 2));
        // Finer detail for the colour alone.
        float f = fbm(p * 1.6 + 2.0 * r, 4);
        // Two systems of folds crossing at an angle, each with a lit side.
        float ph1 = (p.x * 1.1 + p.y * 0.8) * 2.0 + r.x * 3.0 + q.y * 2.0 + t * 0.7;
        float ph2 = (p.x * -0.6 + p.y * 1.4) * 2.6 + r.y * 2.5 + q.x * 1.5 - t * 0.5;
        float b1 = sin(ph1), b2 = sin(ph2);
        float lit = 0.5 + 0.5 * sin(ph1 + 1.2), lit2 = 0.5 + 0.5 * sin(ph2 + 1.0);
        // The thin bright edge where a fold turns, and a broader glow along it.
        float e1 = pow(1.0 - abs(b1), 9.0) * smoothstep(0.35, 0.65, r.y);
        float e2 = pow(1.0 - abs(b2), 9.0) * 0.5 * smoothstep(0.4, 0.7, q.x);
        float ridge = pow(1.0 - abs(b1), 3.0) * 0.5;
        // Where on the ramp each point sits: the folds carry it round, the
        // detail and the warp shift it, and it creeps with time — so every
        // colour of the set has folds of its own, and they trade places slowly.
        float uu = fract(0.5 + 0.32 * b1 + 0.22 * b2 + 0.18 * (f - 0.5) + 0.35 * r.x + t * 0.05);
        int n = max(1, int(u.ground.w));
        float3 col = ramp(u.colors, n, uu);
        float3 hi = u.colors[5].rgb;
        float light = 0.6 * lit + 0.4 * lit2;
        // Frost: the folds pale, the edges soften, the whole loses colour —
        // gently at first, since a little haze goes a long way over a dark
        // ground, and all the way at 100%.
        float fr = u.frost * u.frost;
        float edges = (e1 * 0.18 + e2 * 0.1) * (1.0 - 0.6 * u.frost);
        float3 g = u.ground.rgb;
        float3 outc;
        if (u.dark > 0.5) {
            outc = g + 0.06 * fr + col * ((0.18 + 0.82 * light + ridge) * 0.8) + hi * edges;
        } else {
            outc = mix(g, col, 0.35 + 0.65 * light) + hi * edges * 0.45;
        }
        float L = luma(outc);
        outc = L + (outc - L) * (1.0 - 0.5 * fr);
        return float4(saturate(outc), 1.0);
    }
    """
}

struct BackdropCanvas: NSViewRepresentable {
    let config: BackdropConfig

    func makeNSView(context: Context) -> BackdropView { BackdropView(config: config) }
    func updateNSView(_ v: BackdropView, context: Context) { v.config = config }
}
