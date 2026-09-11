import Foundation
import QuartzCore

/// One undo stack for every setting — the preferences in SettingsData and
/// the custom themes — so that ⌘Z in Settings takes back the last change,
/// whichever pane, menu or command made it, and ⇧⌘Z puts it back. A run of
/// changes to the same setting inside a second — a slider being dragged, a
/// colour being picked — is one step. The stores register their own steps
/// from their didSets; this keeps the stack and decides what counts.
final class SettingsUndo {
    static let shared = SettingsUndo()

    let manager: UndoManager = {
        let m = UndoManager()
        m.levelsOfUndo = 100
        return m
    }()

    private var lastKeys: Set<String> = []
    private var lastAt: CFTimeInterval = 0
    private static let sameStepWithin: CFTimeInterval = 1.0

    var canUndo: Bool { manager.canUndo }
    var canRedo: Bool { manager.canRedo }
    func undo() { ScreenshotMode.note("settings: undo"); manager.undo() }
    func redo() { ScreenshotMode.note("settings: redo"); manager.redo() }

    /// From a store's didSet. `keys` names what changed, so that the same
    /// knob turned again a moment later joins the step already registered —
    /// whose way back, to the value before the first turn, is the right one.
    /// `restore` puts the old value back; the didSet it causes registers the
    /// way forward again, on the redo stack.
    func note(keys: Set<String>, restore: @escaping () -> Void) {
        guard !keys.isEmpty else { return }
        let now = CACurrentMediaTime()
        let inFlight = manager.isUndoing || manager.isRedoing
        if !inFlight, keys == lastKeys, now - lastAt < SettingsUndo.sameStepWithin {
            ScreenshotMode.note("settings: \(keys.sorted()) joins the last step")
            lastAt = now
            return
        }
        ScreenshotMode.note("settings: \(keys.sorted()) \(inFlight ? "(undo/redo in flight)" : "registered"); undo=\(manager.canUndo) redo=\(manager.canRedo)")
        lastKeys = inFlight ? [] : keys
        lastAt = now
        manager.registerUndo(withTarget: self) { _ in restore() }
    }

    /// The top-level keys whose values differ between the two, as encoded.
    static func changedKeys<T: Encodable>(_ a: T, _ b: T) -> Set<String> {
        func object(_ v: T) -> [String: Any] {
            guard let data = try? JSONEncoder().encode(v),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return obj
        }
        let x = object(a), y = object(b)
        var keys = Set<String>()
        for k in Set(x.keys).union(y.keys) {
            switch (x[k], y[k]) {
            case (nil, nil):
                continue
            case let (l?, r?):
                if !(l as AnyObject).isEqual(r) { keys.insert(k) }
            default:
                keys.insert(k)
            }
        }
        return keys
    }
}
