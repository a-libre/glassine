import Foundation

// The few things about the editor that are the same whichever shell draws it.
// `EditorView` and `GlassineTextView` are declared once per platform
// (Sources/Mac, Sources/iOS); what they share is declared here, once.

extension EditorView {
    /// The line a caret position is on: the count of line breaks before it,
    /// which is the count the renderer marks its blocks with.
    static func lineIndex(at location: Int, in text: NSString) -> Int {
        let before = text.substring(to: max(0, min(location, text.length)))
        return before.utf8.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }
}

extension GlassineTextView {
    /// How long a checked-off task waits before it sinks below the open ones.
    static let sinkDelay: TimeInterval = 1.6
}
