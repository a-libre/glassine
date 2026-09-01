import AppKit
import SwiftUI

/// Hosts the AppKit text view inside SwiftUI and bridges it to the open document.
struct EditorView: NSViewRepresentable {
    @ObservedObject var document: DocumentModel
    let config: StyleConfig
    let initialCaret: Int?
    let onCaretMoved: (Int) -> Void
    var onEscape: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = GlassineTextView(config: config)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.scrollerKnobStyle = config.theme.isDark ? .light : .dark
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.onTextChanged = { [weak coordinator = context.coordinator] in coordinator?.textChanged() }
        textView.onSelectionChanged = { [weak coordinator = context.coordinator] in coordinator?.selectionChanged() }
        textView.onEscape = { [weak coordinator = context.coordinator] in coordinator?.parent.onEscape?() }
        context.coordinator.textView = textView
        context.coordinator.attach(document: document, caret: initialCaret)

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if context.coordinator.documentID != document.id {
            context.coordinator.attach(document: document, caret: initialCaret)
        }
        if textView.config != config {
            textView.config = config
            scrollView.scrollerKnobStyle = config.theme.isDark ? .light : .dark
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        weak var textView: GlassineTextView?
        private(set) var documentID: UUID?
        private weak var document: DocumentModel?
        private var isLoading = false
        private var caretSaveDebouncer = Debouncer(delay: 0.8)

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func attach(document: DocumentModel, caret: Int?) {
            self.document = document
            documentID = document.id
            guard let textView else { return }
            isLoading = true
            textView.load(text: document.text, caretAt: caret)
            isLoading = false
            document.onReloaded = { [weak self, weak document] in
                guard let self, let textView = self.textView, let document else { return }
                self.isLoading = true
                textView.replaceText(with: document.text)
                self.isLoading = false
            }
            DispatchQueue.main.async { [weak textView] in
                textView?.window?.makeFirstResponder(textView)
            }
        }

        func textChanged() {
            guard !isLoading, let textView, let document else { return }
            document.textDidChange(textView.string)
        }

        func selectionChanged() {
            guard !isLoading, let textView else { return }
            let loc = textView.selectedRange().location
            caretSaveDebouncer.call { [weak self] in
                self?.parent.onCaretMoved(loc)
            }
        }

        // MARK: NSTextViewDelegate

        func undoManager(for view: NSTextView) -> UndoManager? {
            document?.undoManager
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL { NSWorkspace.shared.open(url); return true }
            if let s = link as? String, let url = URL(string: s) { NSWorkspace.shared.open(url); return true }
            return false
        }
    }
}
