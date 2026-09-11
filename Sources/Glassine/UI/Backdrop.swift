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
/// through wherever it is.
enum BackdropStyle: String, Codable, CaseIterable, Identifiable {
    case desktop, aurora, dusk, ocean, ember, moss, rose, graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .desktop: return "The desktop, through the glass"
        case .aurora: return "Aurora — the theme's own colours"
        case .dusk: return "Dusk — violet and indigo"
        case .ocean: return "Ocean — blue and teal"
        case .ember: return "Ember — red, orange and gold"
        case .moss: return "Moss — green and lime"
        case .rose: return "Rose — pink, mauve and peach"
        case .graphite: return "Graphite — grey, barely tinted"
        }
    }

    var shortLabel: String {
        switch self {
        case .desktop: return "Desktop"
        case .aurora: return "Aurora"
        default: return rawValue.capitalized
        }
    }

    /// The hues (in degrees) and saturations of the colours the folds run
    /// through. Their lightness comes from the theme, so a dark theme gets
    /// deep silk and a light one a pale morning, whichever palette is picked.
    func washes(for theme: Theme) -> [Wash] {
        switch self {
        case .desktop:
            return []
        case .aurora:
            let tint = theme.tint.nsColor.usingColorSpace(.deviceRGB) ?? .gray
            let accent = theme.accent.nsColor.usingColorSpace(.deviceRGB) ?? .blue
            let t = tint.hueComponent * 360
            let a = accent.hueComponent * 360
            // Little saturation in the tint means a neutral theme: keep the
            // colours quiet rather than inventing a colour it never had.
            let s = max(0.25, min(0.6, tint.saturationComponent + 0.15))
            let between = t + (((a - t + 540).truncatingRemainder(dividingBy: 360)) - 180) / 2
            return [Wash(t, s), Wash(t + 22, s * 0.9), Wash(t - 26, s * 0.9),
                    Wash(a, min(0.65, s + 0.2)), Wash(between, s * 0.8), Wash(t + 8, s)]
        case .dusk:
            return [Wash(262, 0.55), Wash(232, 0.55), Wash(280, 0.5), Wash(214, 0.5), Wash(292, 0.42), Wash(248, 0.5)]
        case .ocean:
            return [Wash(208, 0.55), Wash(190, 0.5), Wash(226, 0.55), Wash(174, 0.45), Wash(216, 0.5), Wash(198, 0.5)]
        case .ember:
            return [Wash(14, 0.6), Wash(30, 0.6), Wash(354, 0.5), Wash(42, 0.55), Wash(330, 0.4), Wash(20, 0.55)]
        case .moss:
            return [Wash(130, 0.45), Wash(96, 0.45), Wash(160, 0.4), Wash(76, 0.4), Wash(176, 0.35), Wash(118, 0.45)]
        case .rose:
            return [Wash(340, 0.45), Wash(356, 0.45), Wash(320, 0.4), Wash(18, 0.4), Wash(300, 0.3), Wash(346, 0.45)]
        case .graphite:
            return [Wash(220, 0.05), Wash(240, 0.04), Wash(200, 0.05), Wash(260, 0.04), Wash(220, 0.03), Wash(230, 0.05)]
        }
    }

    struct Wash: Equatable {
        var hue: CGFloat      // degrees
        var saturation: CGFloat
        init(_ hue: CGFloat, _ saturation: CGFloat) {
            self.hue = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            self.saturation = saturation
        }
    }
}

/// Everything the view needs to draw a backdrop, and nothing that changes
/// without the drawing having to.
struct BackdropConfig: Equatable {
    var washes: [BackdropStyle.Wash]
    var isDark: Bool
    var drifts: Bool
    var frost: Double

    init(style: BackdropStyle, theme: Theme, drifts: Bool, frost: Double) {
        washes = style.washes(for: theme)
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

    /// The palette, as the shader wants it: five colours the folds run
    /// through and one for the bright edge, plus the ground. On a dark theme
    /// the colours are deep — saturated, never bright — and the ground is
    /// close to black; on a light theme they are pale over near white.
    private func applyConfig() {
        let dark = config.isDark
        let frost = CGFloat(config.frost)
        let washes = config.washes.isEmpty ? [BackdropStyle.Wash(230, 0.3)] : config.washes
        func wash(_ i: Int) -> BackdropStyle.Wash { washes[i % washes.count] }
        func rgb(_ c: NSColor) -> SIMD4<Float> {
            let s = c.usingColorSpace(.sRGB) ?? c
            return SIMD4(Float(s.redComponent), Float(s.greenComponent), Float(s.blueComponent), 1)
        }
        let ground = wash(0)
        uniforms.ground = rgb(NSColor(
            hue: ground.hue / 360, saturation: ground.saturation * (dark ? 0.7 : 0.2) * (1 - 0.5 * frost),
            brightness: dark ? 0.045 : 0.965, alpha: 1))
        var rng = SeededGenerator(seed: 0x6C61_7373_696E_65)   // the same silk every launch
        var colors: [SIMD4<Float>] = []
        for i in 0..<5 {
            let w = wash(i)
            let saturation = dark ? min(0.92, w.saturation * 1.5) : min(0.7, w.saturation * 1.1)
            let brightness = dark ? (0.45 + 0.15 * rng.next() + 0.1 * frost) : (0.8 + 0.06 * rng.next())
            colors.append(rgb(NSColor(hue: w.hue / 360, saturation: saturation * (1 - 0.55 * frost),
                                      brightness: brightness, alpha: 1)))
        }
        // The edge: the same silk, catching the light.
        colors.append(rgb(NSColor(hue: wash(1).hue / 360, saturation: (dark ? 0.35 : 0.12) * (1 - 0.5 * frost),
                                  brightness: dark ? 0.85 : 1, alpha: 1)))
        uniforms.colors = (colors[0], colors[1], colors[2], colors[3], colors[4], colors[5])
        uniforms.dark = dark ? 1 : 0
        uniforms.frost = Float(frost)
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

    /// Laid out to match `Uniforms` in the shader.
    private struct BackdropUniforms {
        var time: Float = 0
        var aspect: Float = 1
        var dark: Float = 1
        var frost: Float = 0
        var ground = SIMD4<Float>(0, 0, 0, 1)
        var colors: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) =
            (.zero, .zero, .zero, .zero, .zero, .zero)
    }

    /// A small deterministic generator (SplitMix64), so the palette's
    /// lightness varies the same way every launch.
    private struct SeededGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> CGFloat {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return CGFloat(z >> 11) / CGFloat(1 << 53)
        }
    }

    /// One triangle over the whole layer, and a fragment shader that warps a
    /// field of value noise through itself twice (after Quílez), reads the
    /// folds off it as sweeping bands, and lights them.
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
        float3 c0 = u.colors[0].rgb, c1 = u.colors[1].rgb, c2 = u.colors[2].rgb;
        float3 c3 = u.colors[3].rgb, c4 = u.colors[4].rgb, hi = u.colors[5].rgb;
        float3 col = mix(c0, c3, 0.5 + 0.5 * b1);
        col = mix(col, c1, (0.5 + 0.5 * b2) * 0.7);
        col = mix(col, c2, smoothstep(0.3, 0.75, f) * 0.6);
        col = mix(col, c4, saturate(r.x * 1.4 - 0.3) * 0.5);
        float light = 0.6 * lit + 0.4 * lit2;
        float3 g = u.ground.rgb;
        float3 outc;
        if (u.dark > 0.5) {
            outc = g + col * ((0.18 + 0.82 * light + ridge) * 0.8) + hi * (e1 * 0.18 + e2 * 0.1);
        } else {
            outc = mix(g, col, 0.35 + 0.65 * light) + hi * (e1 * 0.08 + e2 * 0.04);
        }
        return float4(saturate(outc), 1.0);
    }
    """
}

struct BackdropCanvas: NSViewRepresentable {
    let config: BackdropConfig

    func makeNSView(context: Context) -> BackdropView { BackdropView(config: config) }
    func updateNSView(_ v: BackdropView, context: Context) { v.config = config }
}
