import SwiftUI

struct EditorContainerView: View {
    @EnvironmentObject var state: AppState
    @Namespace private var zoom
    @State private var dividerStartFraction: Double?
    /// The page's share of the width while the divider is being dragged;
    /// written to the settings once the drag ends (see ContentView's sidebar).
    @State private var liveFraction: Double?
    @State private var dividerHovered = false

    private var theme: Theme { state.theme }
    private var beside: Bool { state.settings.data.reviewBeside }
    private var besideFraction: Double { liveFraction ?? state.settings.data.reviewBesideFraction }

    var body: some View {
        ZStack(alignment: .bottom) {
            if state.showingDaily {
                DailyTimelineView(zoom: zoom)
            } else if state.showingGallery || state.document == nil {
                GalleryView(zoom: zoom)
            } else if let doc = state.document, state.reviewMode {
                ReviewView(document: doc, initialScrollFraction: state.reviewEntryScrollFraction)
                    .id(doc.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.992)))
            } else if let doc = state.document {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        editor(doc)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            // Another page coming in slides this one aside (Pages.swift).
                            .transition(state.pageSlide == 0 ? .opacity : .asymmetric(
                                insertion: .move(edge: state.pageSlide > 0 ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: state.pageSlide > 0 ? .leading : .trailing).combined(with: .opacity)))
                        if beside {
                            // The page beside the editor: rendered as the text changes,
                            // scrolled to the caret's block, sized by the divider.
                            divider
                            ReviewView(document: doc, initialScrollFraction: 0, beside: true)
                                .id(doc.id)
                                .frame(width: (geo.size.width * besideFraction).rounded())
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // While the pages are fanned out the one on screen steps back.
        .scaleEffect(state.carousel == nil ? 1 : 0.965)
        .opacity(state.carousel == nil ? 1 : 0.4)
        .animation(Motion.quiet(.easeOut(duration: 0.2)), value: state.carousel == nil)
        .animation(Motion.quiet(.easeOut(duration: 0.24)), value: state.showingGallery)
        .animation(Motion.quiet(.easeOut(duration: 0.24)), value: state.showingDaily)
        .animation(Motion.quiet(.easeOut(duration: 0.18)), value: state.reviewMode)
        .animation(Motion.quiet(.easeOut(duration: 0.22)), value: beside)
        .animation(Motion.quiet(state.pageSlide == 0 ? .easeOut(duration: 0.18) : .spring(response: 0.34, dampingFraction: 0.86)), value: state.document?.relativePath)
        .animation(Motion.quiet(.easeOut(duration: 0.3)), value: state.zoomingCard)
    }

    private func editor(_ doc: DocumentModel) -> some View {
        ZStack(alignment: .bottom) {
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
                onEscape: { state.escapeFromEditor() },
                onCaretLine: beside ? { state.caretLine = $0 } : nil
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

    /// A hairline between the editor and the page, dragged to share the width;
    /// the share is kept, like the sidebar's width.
    private var divider: some View {
        Rectangle()
            .fill(theme.text.color.opacity(theme.isDark ? 0.10 : 0.12))
            .frame(width: 1)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onHover { inside in
                dividerHovered = inside
                guard dividerStartFraction == nil else { return }
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("glassineRoot"))
                    .onChanged { value in
                        guard let width = NSApp.keyWindow?.contentView?.bounds.width, width > 0 else { return }
                        if dividerStartFraction == nil { dividerStartFraction = state.settings.data.reviewBesideFraction }
                        // The page loses what the pointer moved to the right.
                        let editorWidth = width - (state.settings.data.sidebarVisible ? CGFloat(state.settings.data.sidebarWidth) : 0)
                        let f = (dividerStartFraction ?? 0.5) - Double(value.translation.width / max(1, editorWidth))
                        let fraction = (min(0.7, max(0.3, f)) * 1000).rounded() / 1000
                        if fraction != liveFraction { liveFraction = fraction }
                    }
                    .onEnded { _ in
                        if let fraction = liveFraction, fraction != state.settings.data.reviewBesideFraction {
                            state.settings.data.reviewBesideFraction = fraction
                        }
                        liveFraction = nil
                        dividerStartFraction = nil
                        if !dividerHovered { NSCursor.pop() }
                    }
            )
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
            // The name and the pips; ⌥⇥ with one page open gives them a
            // small shake together, since one page draws no pips to shake.
            HStack(spacing: 10) {
                Text(document.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                PagePips()
            }
            .modifier(Nudge(trigger: state.carouselNudge))
            if let notice = state.transientNotice {
                // "Copied…" comes in beside the name rather than in its place.
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    Text(notice)
                }
                .foregroundStyle(theme.accent.color.opacity(0.95))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Spacer()
            CounterButton(text: counterText, theme: theme) { cycleCounter() }
                .animation(.easeOut(duration: 0.2), value: counterText)
            if state.settings.data.floatOnTop {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.accent.color.opacity(0.85))
                    .rotationEffect(.degrees(35))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
                    .help("Floating over other windows. ⌘. to stop.")
            }
            copyButton
        }
        .animation(.easeInOut(duration: 0.15), value: state.transientNotice)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: state.settings.data.floatOnTop)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: document.saveState)
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
            Button(state.settings.data.reviewBeside ? "Put Away the Page Beside   ⌘⇧↩" : "Review Beside the Editor   ⌘⇧↩") { state.toggleReviewBeside() }
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
        if document.isLoading {
            // The file is on its way down from iCloud; the page fills in when it lands.
            HStack(spacing: 4) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                Text("Coming down from iCloud…")
            }
            .foregroundStyle(theme.accent.color.opacity(0.9))
            .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
        } else if let error = document.loadError {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text("Couldn't read the file")
            }
            .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
            .help("\(error) The page is read-only, so nothing is written over the file.")
        } else {
            saveStateIndicator
        }
    }

    @ViewBuilder
    private var saveStateIndicator: some View {
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
            .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
        case .failed(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text("Not saved")
            }
            .foregroundStyle(Color(nsColor: .systemRed).opacity(0.9))
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

/// The counter at the foot of the page. A click walks it through what it
/// counts — words, characters, the reading time, everything — and under the
/// pointer it brightens a little, so that there is something to click is
/// not a secret.
struct CounterButton: View {
    let text: String
    let theme: Theme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.text.color.opacity(hovering ? 0.08 : 0))
                )
                .foregroundStyle(theme.text.color.opacity(hovering ? 0.75 : 0.45))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Words, characters, reading time, or all three — click to change what's counted")
    }
}

/// A small sideways shake, for a key that found nothing to do.
struct Nudge: ViewModifier {
    let trigger: Int
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: trigger) { _, _ in
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.07)) { offset = 4 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { withAnimation(.easeInOut(duration: 0.07)) { offset = -3 } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { withAnimation(.easeInOut(duration: 0.07)) { offset = 2 } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.21) { withAnimation(.easeInOut(duration: 0.08)) { offset = 0 } }
            }
    }
}
