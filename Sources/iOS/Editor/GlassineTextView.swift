import UIKit

/// The editor's text view on iOS. It stands on the same TextKit 1 stack as the
/// Mac's (a storage, a layout manager, one container), so the styler, the
/// capsules and the caret's geometry can be the same code.
///
/// This is the frame of it: text in, text out, and the names shared code asks
/// for. The styling, the gliding caret, typewriter and focus modes arrive next.
final class GlassineTextView: UITextView {
    /// The editor currently on screen (there is only ever one).
    static weak var current: GlassineTextView?

    var config: StyleConfig
    var onTextChanged: (() -> Void)?
    var onSelectionChanged: (() -> Void)?

    /// The sentence whose Markdown is showing while the rest is hidden.
    private(set) var syntaxRevealRange = NSRange(location: NSNotFound, length: 0)

    init(config: StyleConfig) {
        self.config = config
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = false
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = .clear
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        GlassineTextView.current = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// How far the viewport is scrolled through the document, 0–1.
    var scrollFraction: Double {
        let maxY = contentSize.height - bounds.height
        guard maxY > 0 else { return 0 }
        return Double(max(0, min(1, contentOffset.y / maxY)))
    }

    // MARK: - What shared code asks of the text view

    var caretLocation: Int { selectedRange.location }
    var plainText: String { text ?? "" }

    func load(text: String, caretAt caret: Int?) {
        self.text = text
        let end = (text as NSString).length
        selectedRange = NSRange(location: min(max(0, caret ?? end), end), length: 0)
    }

    func replaceText(with text: String) {
        let caret = selectedRange.location
        load(text: text, caretAt: caret)
    }
}
