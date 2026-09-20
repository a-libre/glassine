#if targetEnvironment(simulator)
import UIKit

/// A hand on the keyboard for ios/build-sim.sh, in the simulator only: the
/// simulator can be photographed from the command line but not typed into, so
/// a launch can ask the editor to take the caret somewhere and type.
///
///   -glassine.launchCaret 40          the caret there, and the keyboard up
///   -glassine.typeText "- one\n"      typed a character at a time (\n is Return)
///
/// Each character goes the way a keystroke does — asked of the delegate first,
/// then inserted — so list continuation, dates and the styler all take part.
enum SimulatorScript {
    private static var ran = false

    static func runIfAsked(on textView: GlassineTextView) {
        let defaults = UserDefaults.standard
        guard !ran, defaults.object(forKey: "glassine.launchCaret") != nil || defaults.string(forKey: "glassine.typeText") != nil else { return }
        ran = true
        let length = (textView.plainText as NSString).length
        let caret = defaults.object(forKey: "glassine.launchCaret") != nil ? defaults.integer(forKey: "glassine.launchCaret") : length
        textView.becomeFirstResponder()
        textView.selectedRange = NSRange(location: min(max(0, caret), length), length: 0)
        let script = (defaults.string(forKey: "glassine.typeText") ?? "").replacingOccurrences(of: "\\n", with: "\n")
        var delay = 0.6
        for ch in script {
            let s = String(ch)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak textView] in
                guard let textView else { return }
                if textView.textView(textView, shouldChangeTextIn: textView.selectedRange, replacementText: s) {
                    textView.insertText(s)
                }
            }
            delay += 0.06
        }
    }
}
#endif
