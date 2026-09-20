#if targetEnvironment(simulator)
import UIKit

/// A hand on the keyboard for ios/build-sim.sh, in the simulator only: the
/// simulator can be photographed from the command line but not typed into, so
/// a launch can ask the editor to take the caret somewhere and type.
///
///   -glassine.launchCaret 40          the caret there, and the keyboard up
///   -glassine.typeText "- one\n"      typed a character at a time (\n is Return)
///   -glassine.trace /tmp/trace.log    where the page is after every keystroke and
///                                     every move of the scroll view, for finding
///                                     what makes a page jump
///
/// Each character goes the way a keystroke does — asked of the delegate first,
/// then inserted — so list continuation, dates and the styler all take part.
enum SimulatorScript {
    private static var ran = false
    private static var observations: [NSKeyValueObservation] = []
    private static var traceHandle: FileHandle?
    private static let started = CACurrentMediaTime()

    static func runIfAsked(on textView: GlassineTextView) {
        let defaults = UserDefaults.standard
        guard !ran else { return }
        ran = true
        // The trace is always kept in the simulator — a flight recorder: when a
        // page misbehaves under someone's hands, what it did is already on file.
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.replacingOccurrences(of: " ", with: "-") ?? "sim"
        startTrace(of: textView, to: defaults.string(forKey: "glassine.trace") ?? "/tmp/glassine-ios-trace-\(device).log")
        // -glassine.pressKeys "cmd+k cmd+\\" : key strokes handed straight to the key dispatcher, one a second.
        if let keys = defaults.string(forKey: "glassine.runCommands") {
            var delay = 2.0
            for name in keys.split(separator: " ") {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    switch name {
                    case "commandBar": AppState.shared.toggleCommandBar()
                    case "sidebar": AppState.shared.toggleSidebar()
                    case "gallery": AppState.shared.showGallery()
                    case "shortcuts": AppState.shared.showingShortcuts.toggle()
                    default: break
                    }
                    log("ran \(name)")
                }
                delay += 1.0
            }
        }
        guard defaults.object(forKey: "glassine.launchCaret") != nil || defaults.string(forKey: "glassine.typeText") != nil else { return }
        let length = (textView.plainText as NSString).length
        let caret = defaults.object(forKey: "glassine.launchCaret") != nil ? defaults.integer(forKey: "glassine.launchCaret") : length
        textView.becomeFirstResponder()
        textView.selectedRange = NSRange(location: min(max(0, caret), length), length: 0)
        let script = (defaults.string(forKey: "glassine.typeText") ?? "").replacingOccurrences(of: "\\n", with: "\n")
        var delay = 0.9
        for ch in script {
            let s = String(ch)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak textView] in
                guard let textView else { return }
                note("key \(s == "\n" ? "↩" : s)", textView)
                if textView.textView(textView, shouldChangeTextIn: textView.selectedRange, replacementText: s) {
                    textView.insertText(s)
                }
                note("typed", textView)
            }
            delay += 0.09
        }
    }

    private static func startTrace(of textView: GlassineTextView, to path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        traceHandle = FileHandle(forWritingAtPath: path)
        note("start", textView)
        log("layout: UIKit had set nonContiguous=\(textView.foundNonContiguous); it is now \(textView.layoutManager.allowsNonContiguousLayout)")
        observations = [
            textView.observe(\.contentOffset, options: [.old, .new]) { view, change in
                guard change.oldValue?.y != change.newValue?.y else { return }
                note("offset", view)
            },
            textView.observe(\.contentSize, options: [.old, .new]) { view, change in
                guard change.oldValue?.height != change.newValue?.height else { return }
                note("size", view)
            },
        ]
    }

    /// A line in the trace from anywhere: a key heard, a command run.
    static func log(_ line: String) {
        guard let traceHandle else { return }
        traceHandle.write(String(format: "%7.3f  %@\n", CACurrentMediaTime() - started, line as NSString).data(using: .utf8)!)
    }

    /// A line in the trace from the text view itself: what it decided, and why.
    static func note(_ what: String, from view: UITextView, _ detail: String) {
        guard let traceHandle else { return }
        note(what, view)
        traceHandle.write("           ↳ \(detail)\n".data(using: .utf8)!)
    }

    private static func note(_ what: String, _ view: UITextView) {
        guard let traceHandle else { return }
        let caretY = (view as? GlassineTextView)?.insertionRect()?.midY ?? -1
        let line = String(format: "%7.3f  %-8@ offset=%8.2f  size=%8.2f  caretY=%8.2f  caretOnScreen=%7.2f  animating=%d\n",
                          CACurrentMediaTime() - started, what as NSString, view.contentOffset.y, view.contentSize.height,
                          caretY, caretY - view.contentOffset.y, (view.layer.animationKeys()?.isEmpty == false) ? 1 : 0)
        traceHandle.write(line.data(using: .utf8)!)
    }
}
#endif
