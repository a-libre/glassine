import QuartzCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The caret as a set of layers: a box that glides and blinks, holding the
/// shape itself — a solid path in the caret colour over a faint one — so a
/// change of shape never touches the motion, with a layer in between for the
/// idle tricks to turn and toss. Core Animation is the same on the Mac and on
/// iOS, so this is the caret for both; all it asks of a text view is where
/// the insertion point is.
///
/// The iOS text view draws its caret with this today. The Mac's text view
/// still carries its own, older copy of the same code (GlassineTextView's
/// "Smooth caret" and "Idle tricks"); it moves over to this one next.
final class CaretLayers {
    /// What the shape is fitted to. A change in any of these rebuilds the paths.
    private struct GeometryKey: Equatable {
        var shape: CaretShape
        var width: CGFloat
        var height: CGFloat
        var baseline: CGFloat
        var slot: CGFloat
    }

    /// Where the insertion point is, as the text view measures it.
    struct Placement {
        /// The bar, in the host layer's coordinates (top-down).
        var rect: CGRect
        /// From the top of the bar to the baseline.
        var baseline: CGFloat
        /// The width of the character after the caret, for a shape that sits over it.
        var slot: CGFloat
    }

    let box = CALayer()
    private let trickLayer = CALayer()
    private let shapeLayer = CAShapeLayer()
    private let faintLayer = CAGradientLayer()
    private let faintMask = CAShapeLayer()
    private var geometryKey: GeometryKey?
    /// Room around the bar for the pieces of a shape that reach past it.
    private static let reach: CGFloat = 32

    private(set) var isVisible = false
    private var lastRect: CGRect = .zero
    private var blinkWork: DispatchWorkItem?
    private var trickWork: DispatchWorkItem?
    private var lastTrick: CaretTrick?

    var config: StyleConfig {
        didSet {
            guard config != oldValue else { return }
            applyColours()
            geometryKey = nil
        }
    }
    /// Whether the caret may perform: the view is the one being typed in.
    var mayPerform: () -> Bool = { true }

    init(config: StyleConfig) {
        self.config = config
        box.anchorPoint = .zero
        box.opacity = 0
        box.zPosition = 10
        box.shadowOffset = .zero
        box.shadowRadius = 6
        box.shadowOpacity = 0
        trickLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        box.addSublayer(trickLayer)
        for l in [faintLayer, shapeLayer] as [CALayer] {
            l.anchorPoint = .zero
            trickLayer.addSublayer(l)
        }
        faintLayer.startPoint = CGPoint(x: 0, y: 0.5)
        faintLayer.endPoint = CGPoint(x: 1, y: 0.5)
        faintMask.anchorPoint = .zero
        faintLayer.mask = faintMask
        applyColours()
    }

    func install(in host: CALayer) { host.addSublayer(box) }

    func setScale(_ scale: CGFloat) {
        for l in [box, trickLayer, shapeLayer, faintLayer, faintMask] as [CALayer] { l.contentsScale = scale }
    }

    private func applyColours() {
        shapeLayer.fillColor = config.theme.caretColor.cgColor
        box.shadowColor = config.theme.caretColor.cgColor
    }

    // MARK: - Placing

    /// Puts the caret at `placement`, gliding there when `animated`. A move to
    /// another line while typing — a word wrapping at the margin, a Return —
    /// gets a quarter more glide: the long diagonal back to the left is a
    /// bigger move than a step to the next letter.
    func place(_ placement: Placement, animated: Bool, typing: Bool) {
        let rect = placement.rect
        let wasVisible = isVisible
        isVisible = true
        let previous = lastRect
        let moved = !rect.equalTo(lastRect)
        lastRect = rect
        let animate = animated && wasVisible && moved && config.smoothCaret && !Platform.reduceMotion
        let toAnotherLine = typing && moved && wasVisible && abs(rect.minY - previous.minY) > 1
        if moved { cancelTrick() }
        CATransaction.begin()
        if animate {
            CATransaction.setAnimationDuration(config.caretDuration * (toAnotherLine ? 1.25 : 1))
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.8, 0.3, 1.0))
        } else {
            CATransaction.setDisableActions(true)
        }
        box.frame = rect
        if trickLayer.bounds.size != rect.size {
            trickLayer.bounds = CGRect(origin: .zero, size: rect.size)
            trickLayer.position = CGPoint(x: rect.width / 2, y: rect.height / 2)
        }
        layoutShape(placement)
        CATransaction.commit()
        if moved || !wasVisible {
            restartBlink()
            scheduleTrick()
        }
    }

    func hide() {
        guard isVisible || box.opacity != 0 else { return }
        isVisible = false
        blinkWork?.cancel()
        cancelTrick()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.removeAllAnimations()
        box.opacity = 0
        CATransaction.commit()
    }

    /// The shape, fitted to the bar the caret would be: rebuilt only when the
    /// shape, the bar's size or (for a ghost) the next character's width has
    /// changed. Inside the caller's transaction, so a change of size glides
    /// along with the box.
    private func layoutShape(_ placement: Placement) {
        let shape = config.caretShape
        let rect = placement.rect
        let key = GeometryKey(shape: shape, width: rect.width, height: rect.height,
                              baseline: placement.baseline, slot: shape == .ghost ? placement.slot : 0)
        guard key != geometryKey else { return }
        geometryKey = key
        let g = shape.geometry(barWidth: key.width, height: key.height, baseline: key.baseline, slot: key.slot)
        // The sublayers are larger than the box on every side, so the pieces
        // that reach past the bar are never at the mercy of a clip.
        let reach = CaretLayers.reach
        var shift = CGAffineTransform(translationX: reach, y: reach)
        let frame = CGRect(x: -reach, y: -reach, width: key.width + 2 * reach, height: key.height + 2 * reach)
        shapeLayer.frame = frame
        faintLayer.frame = frame
        faintMask.frame = CGRect(origin: .zero, size: frame.size)
        shapeLayer.path = g.solid.copy(using: &shift)
        let tint = config.theme.caretColor
        if let faint = g.faint?.copy(using: &shift) {
            faintMask.path = faint
            if g.fades {
                // From nothing at the far end of the piece to its full strength at the bar.
                let bounds = faint.boundingBox
                faintLayer.colors = [tint.withAlphaComponent(0).cgColor, tint.withAlphaComponent(CaretShape.fadePeakAlpha).cgColor]
                faintLayer.startPoint = CGPoint(x: bounds.minX / frame.width, y: 0.5)
                faintLayer.endPoint = CGPoint(x: bounds.maxX / frame.width, y: 0.5)
            } else {
                let flat = tint.withAlphaComponent(CaretShape.faintAlpha).cgColor
                faintLayer.colors = [flat, flat]
            }
            faintLayer.isHidden = false
        } else {
            faintLayer.isHidden = true
        }
        box.shadowOpacity = g.halo ? 0.9 : 0
    }

    // MARK: - Blinking

    private func restartBlink() {
        blinkWork?.cancel()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.removeAnimation(forKey: "blink")
        box.opacity = 1
        CATransaction.commit()
        guard config.caretBlink != .none else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible else { return }
            let anim = CAKeyframeAnimation(keyPath: "opacity")
            switch self.config.caretBlink {
            case .soft:
                anim.values = [1.0, 1.0, 0.12, 0.12, 1.0]
                anim.keyTimes = [0, 0.35, 0.55, 0.75, 1.0]
                anim.calculationMode = .cubic
                anim.duration = 1.25
            case .hard:
                anim.values = [1.0, 1.0, 0.0, 0.0]
                anim.keyTimes = [0, 0.5, 0.5, 1.0]
                anim.calculationMode = .discrete
                anim.duration = 1.0
            case .none:
                return
            }
            anim.repeatCount = .infinity
            self.box.add(anim, forKey: "blink")
        }
        blinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    // MARK: - Idle tricks

    /// The next trick — two and a half to four seconds after the caret settles,
    /// four to nine between one and the next — unless the caret moves first.
    private func scheduleTrick(after delay: TimeInterval? = nil) {
        trickWork?.cancel()
        trickWork = nil
        guard config.caretTricks, !Platform.reduceMotion else { return }
        let work = DispatchWorkItem { [weak self] in self?.performTrick() }
        trickWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay ?? .random(in: 2.5...4)), execute: work)
    }

    private func cancelTrick() {
        trickWork?.cancel()
        trickWork = nil
        guard trickLayer.animationKeys()?.isEmpty == false else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trickLayer.removeAllAnimations()
        CATransaction.commit()
    }

    private func performTrick() {
        trickWork = nil
        guard isVisible, mayPerform(), config.caretTricks, !Platform.reduceMotion else { return }
        var choices = CaretTrick.allCases
        if let last = lastTrick, choices.count > 1 { choices.removeAll { $0 == last } }
        guard let trick = choices.randomElement() else { return }
        lastTrick = trick
        // Steady while it performs: a flip at the low ebb of a blink would go unseen.
        blinkWork?.cancel()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.removeAnimation(forKey: "blink")
        box.opacity = 1
        CATransaction.commit()
        let duration = trick.run(on: trickLayer, height: box.bounds.height)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.isVisible else { return }
            self.restartBlink()
        }
        scheduleTrick(after: .random(in: 4...9))
    }
}

/// What the caret gets up to while nobody is typing: a few seconds after it
/// last moved it does one of these, and another every several seconds until
/// it moves again. Never the same one twice running.
enum CaretTrick: String, CaseIterable {
    case hop, bounce, flip, wiggle, stretch, lean

    /// Runs the trick on the layer and says how long it takes. The layer
    /// pivots on its centre; y grows downward, so "up" is negative.
    @discardableResult
    func run(on layer: CALayer, height: CGFloat) -> TimeInterval {
        let up = -max(8, height * 0.9)
        let easeOut = CAMediaTimingFunction(name: .easeOut)
        let easeIn = CAMediaTimingFunction(name: .easeIn)
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        let linear = CAMediaTimingFunction(name: .linear)
        let duration: TimeInterval
        let anims: [CAKeyframeAnimation]
        switch self {
        case .hop:
            // Crouch, jump, land with a squash.
            duration = 0.8
            anims = [
                Self.frames("transform.translation.y", [0, up, 0, 0], [0, 0.4, 0.8, 1], [easeOut, easeIn, linear]),
                Self.frames("transform.scale.y", [1, 0.78, 1.12, 1, 1, 0.8, 1], [0, 0.08, 0.28, 0.5, 0.8, 0.88, 1]),
            ]
        case .bounce:
            // Three, each smaller, like a dropped ball.
            duration = 1.15
            anims = [
                Self.frames("transform.translation.y", [0, up, 0, up * 0.5, 0, up * 0.22, 0, 0],
                            [0, 0.2, 0.4, 0.56, 0.72, 0.82, 0.92, 1],
                            [easeOut, easeIn, easeOut, easeIn, easeOut, easeIn, linear]),
                Self.frames("transform.scale.y", [1, 0.78, 1, 1, 0.84, 1, 1, 0.9, 1, 1, 0.94, 1, 1],
                            [0, 0.04, 0.1, 0.38, 0.42, 0.46, 0.7, 0.73, 0.76, 0.905, 0.925, 0.945, 1]),
            ]
        case .flip:
            // A cartwheel in the air.
            duration = 0.95
            anims = [
                Self.frames("transform.translation.y", [0, up * 1.2, 0, 0], [0, 0.42, 0.84, 1], [easeOut, easeIn, linear]),
                Self.frames("transform.rotation.z", [0, .pi * 2, .pi * 2], [0, 0.84, 1], [ease, linear]),
            ]
        case .wiggle:
            // A shake of the head.
            duration = 0.75
            anims = [
                Self.frames("transform.rotation.z", [0, 0.26, -0.22, 0.17, -0.11, 0.05, 0],
                            [0, 0.15, 0.32, 0.5, 0.68, 0.85, 1], cubic: true),
            ]
        case .stretch:
            // A yawn: tall, held, settled.
            duration = 1.0
            anims = [
                Self.frames("transform.scale.y", [1, 1.38, 1.38, 0.9, 1.04, 1], [0, 0.3, 0.5, 0.75, 0.9, 1], cubic: true),
            ]
        case .lean:
            // A look ahead at the next word.
            duration = 0.95
            anims = [
                Self.frames("transform.rotation.z", [0, 0.32, 0.32, 0], [0, 0.3, 0.65, 1], [ease, linear, ease]),
                Self.frames("transform.translation.x", [0, 6, 6, 0], [0, 0.3, 0.65, 1], [ease, linear, ease]),
            ]
        }
        for a in anims {
            a.duration = duration
            layer.add(a, forKey: "trick.\(a.keyPath ?? "")")
        }
        return duration
    }

    private static func frames(_ keyPath: String, _ values: [CGFloat], _ times: [Double],
                               _ timing: [CAMediaTimingFunction]? = nil, cubic: Bool = false) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = values
        a.keyTimes = times.map { NSNumber(value: $0) }
        if cubic { a.calculationMode = .cubic } else if let timing { a.timingFunctions = timing }
        a.isRemovedOnCompletion = true
        return a
    }
}
