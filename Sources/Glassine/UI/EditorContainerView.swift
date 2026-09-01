import SwiftUI

struct EditorContainerView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoom

    private var theme: Theme { state.theme }

    var body: some View {
        ZStack(alignment: .bottom) {
            if state.showingDaily {
                DailyTimelineView(zoom: zoom)
            } else if state.showingGallery || state.document == nil {
                GalleryView(zoom: zoom)
            } else if let doc = state.document, state.reviewMode {
                ReviewView(document: doc, initialScrollFraction: state.reviewEntryScrollFraction)
                    .id(doc.id)
            } else if let doc = state.document {
                if let card = state.zoomingCard {
                    // Picks up the card's frame and grows to fill the page, then fades.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.text.color.opacity(theme.isDark ? 0.07 : 0.05))
                        .matchedGeometryEffect(id: card, in: zoom)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                EditorView(
                    document: doc,
                    config: state.styleConfig,
                    initialCaret: state.savedCaret(for: doc.relativePath),
                    onCaretMoved: { state.caretMoved(to: $0) },
                    onEscape: { state.escapeFromEditor() }
                )
                .id(doc.id)
                .ignoresSafeArea()
                .mask(edgeFade(bottom: state.settings.data.showCounter ? 34 : 16))
                if state.settings.data.showCounter {
                    FooterBar(document: doc)
                        .opacity(state.isQuiet ? 0.1 : 1)
                        .animation(.easeOut(duration: state.isQuiet ? 0.7 : 0.15), value: state.isQuiet)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.24), value: state.showingGallery)
        .animation(.easeOut(duration: 0.24), value: state.showingDaily)
        .animation(.easeOut(duration: 0.18), value: state.reviewMode)
        .animation(.easeOut(duration: 0.18), value: state.document?.relativePath)
        .animation(.easeOut(duration: 0.3), value: state.zoomingCard)
    }

    /// Text slips out under the top edge and the footer instead of being cut off.
    private func edgeFade(bottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 26)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: bottom)
        }
        .ignoresSafeArea()
    }
}

struct FooterBar: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var document: DocumentModel

    private var theme: Theme { state.theme }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            saveIndicator
            if let notice = state.transientNotice {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    Text(notice)
                }
                .foregroundStyle(theme.accent.color.opacity(0.95))
                .transition(.opacity)
            } else {
                Text(document.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                cycleCounter()
            } label: {
                Text(counterText)
                    .monospacedDigit()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to change what's counted")
            copyButton
        }
        .animation(.easeInOut(duration: 0.15), value: state.transientNotice)
        .font(.system(size: 11, weight: .regular, design: .rounded))
        .foregroundStyle(theme.text.color.opacity(0.45))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(height: 30)
        .allowsHitTesting(true)
    }

    private var copyButton: some View {
        Menu {
            Button("Copy as Markdown   ⌘⇧C") { state.copyCurrentDocument(asMarkdown: true) }
            Button("Copy as Rich Text   ⌥⌘C") { state.copyCurrentDocument(asMarkdown: false) }
            Divider()
            Button("Review   ⌘↩") { state.toggleReview() }
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        } primaryAction: {
            state.copyCurrentDocument(asMarkdown: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Copy the whole document as Markdown (⌘⇧C). Click and hold for rich text.")
    }

    @ViewBuilder
    private var saveIndicator: some View {
        switch document.saveState {
        case .clean:
            Circle().fill(theme.text.color.opacity(0.18)).frame(width: 6, height: 6)
        case .dirty:
            Circle().fill(theme.accent.color.opacity(0.55)).frame(width: 6, height: 6)
        case .saving:
            Circle().fill(theme.accent.color.opacity(0.9)).frame(width: 6, height: 6)
        case .saved:
            HStack(spacing: 4) {
                Image(systemName: state.library.isInICloud ? "checkmark.icloud" : "checkmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text("Saved")
            }
            .foregroundStyle(theme.accent.color.opacity(0.9))
            .transition(.opacity)
        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text("Not saved")
            }
            .foregroundStyle(.red.opacity(0.9))
            .help(message)
        }
    }

    private var counterText: String {
        let words = document.wordCount
        let chars = document.characterCount
        let minutes = document.readingMinutes
        func reading() -> String {
            if minutes < 1 { return "under a minute" }
            let m = Int(minutes.rounded())
            return "\(m) min read"
        }
        switch state.settings.data.counterMode {
        case .words: return "\(words) words"
        case .characters: return "\(chars) characters"
        case .readingTime: return reading()
        case .all: return "\(words) words · \(chars) characters · \(reading())"
        }
    }

    private func cycleCounter() {
        let all = CounterMode.allCases
        let i = all.firstIndex(of: state.settings.data.counterMode) ?? 0
        state.settings.data.counterMode = all[(i + 1) % all.count]
    }
}

struct EmptyLibraryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "leaf")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(state.theme.accent.color.opacity(0.7))
            Text("Nothing open")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(state.theme.text.color.opacity(0.6))
            Text("Pick something in the sidebar, or press ⌘N to start a new document.")
                .font(.system(size: 12.5))
                .foregroundStyle(state.theme.text.color.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button("New Document") { state.newDocument() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
