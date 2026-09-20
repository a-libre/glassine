import SwiftUI
import UIKit

/// Hosts the UIKit text view inside SwiftUI and bridges it to the open document.
struct EditorView: UIViewRepresentable {
    @ObservedObject var document: DocumentModel
    let config: StyleConfig
    let initialCaret: Int?
    let onCaretMoved: (Int) -> Void
    var onEscape: (() -> Void)? = nil
    /// The line the caret is on, a beat after it moves — asked for only while
    /// a page beside the editor is following it.
    var onCaretLine: ((Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> GlassineTextView {
        let textView = GlassineTextView(config: config)
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.attach(document: document, caret: initialCaret)
        return textView
    }

    func updateUIView(_ textView: GlassineTextView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.documentID != document.id {
            context.coordinator.attach(document: document, caret: initialCaret)
        }
        if textView.config != config { textView.config = config }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditorView
        weak var textView: GlassineTextView?
        private(set) var documentID: UUID?
        private weak var document: DocumentModel?
        private var isLoading = false
        private var caretSaveDebouncer = Debouncer(delay: 0.8)
        private var caretLineDebouncer = Debouncer(delay: 0.12)

        init(_ parent: EditorView) { self.parent = parent }

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
        }

        func textViewDidChange(_ view: UITextView) {
            guard !isLoading, let textView, let document else { return }
            document.textDidChange(textView.plainText)
        }

        func textViewDidChangeSelection(_ view: UITextView) {
            guard !isLoading, let textView else { return }
            let loc = textView.caretLocation
            caretSaveDebouncer.call { [weak self] in self?.parent.onCaretMoved(loc) }
            if parent.onCaretLine != nil {
                caretLineDebouncer.call { [weak self] in
                    guard let self, let follow = self.parent.onCaretLine, let textView = self.textView else { return }
                    follow(EditorView.lineIndex(at: loc, in: textView.plainText as NSString))
                }
            }
        }
    }
}
