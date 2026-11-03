import SwiftUI

/// The open pages fanned across the window while ⌥ or ⌃ is held (see
/// Pages.swift): a row of cards in the order the pages were last used, the
/// highlighted one flat and full-size at the middle, the others turned a
/// little toward it and stepped back, the way Stage Manager keeps the other
/// windows at the side. Each card is the page itself in little — its title
/// and its first lines in the theme's colours — so a page is found by what
/// is on it rather than by a name in a strip. Tab steps along and the row
/// slides to keep the highlight at the middle; the pointer takes the
/// highlight with it without moving the row; a digit jumps; and a click, ↩
/// or the modifier let go opens the page under the highlight.
struct PageCarouselView: View {
    @EnvironmentObject var state: AppState
    let carousel: PageCarousel

    private var theme: Theme { state.theme }
    private static let cardWidth: CGFloat = 236
    private static let cardHeight: CGFloat = 168
    private static let gap: CGFloat = 14

    private var documents: [DocumentRef] {
        carousel.order.compactMap { state.library.document(withID: $0) }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        GeometryReader { geo in
            let docs = documents
            let step = Self.cardWidth + Self.gap
            // The highlighted card sits at the middle; the row slides under it.
            let offset = (geo.size.width - Self.cardWidth) / 2 - CGFloat(carousel.anchor) * step
            let rowY = (geo.size.height - Self.cardHeight) / 2 - 16
            ZStack(alignment: .topLeading) {
                // The mouse is read by Pages.swift while the cards are fanned
                // (a press beside the cards leaves things as they were); this
                // layer only keeps the page underneath from taking the pointer.
                Color.clear.contentShape(Rectangle())
                HStack(spacing: Self.gap) {
                    ForEach(Array(docs.enumerated()), id: \.element.id) { i, doc in
                        let lit = i == carousel.index
                        let away = i - carousel.index   // negative to the left
                        PageCard(doc: doc, highlighted: lit, current: state.document?.relativePath == doc.id,
                                 number: i < 9 ? i + 1 : nil, closable: lit && docs.count > 1)
                            .frame(width: Self.cardWidth, height: Self.cardHeight)
                            .background(CarouselFrameReporter(id: doc.id))
                            .scaleEffect(lit ? 1 : 0.88)
                            .rotation3DEffect(.degrees(reduceMotion || lit ? 0 : (away < 0 ? 9 : -9)),
                                              axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                            .opacity(lit ? 1 : (abs(away) == 1 ? 0.78 : 0.6))
                            .zIndex(lit ? 1 : 0)
                            .onHover { inside in if inside { state.hoverCarousel(i) } }
                    }
                }
                .offset(x: offset, y: rowY)
                .animation(Motion.quiet(.spring(response: 0.32, dampingFraction: 0.82)), value: carousel.index)
                .animation(Motion.quiet(.spring(response: 0.32, dampingFraction: 0.82)), value: carousel.anchor)
                .animation(Motion.quiet(.spring(response: 0.32, dampingFraction: 0.82)), value: carousel.order)

                // The highlighted page's name, where it stands, and the keys.
                VStack(spacing: 7) {
                    if carousel.index < docs.count {
                        HStack(spacing: 8) {
                            Text(docs[carousel.index].title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.headingColor.asColor.opacity(0.9))
                                .lineLimit(1)
                            Text("\(carousel.index + 1) of \(docs.count)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.text.color.opacity(0.4))
                                .contentTransition(.numericText())
                        }
                        .contentTransition(.opacity)
                    }
                    Text("⇥ steps · ⌫ or × closes · click, ↩ or let go of \(modifierName) to open")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundStyle(theme.text.color.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .offset(y: rowY + Self.cardHeight + 22)
                .animation(.easeOut(duration: 0.12), value: carousel.index)
            }
            .onPreferenceChange(CarouselFramesKey.self) { state.carouselCardFrames = $0 }
            .onPreferenceChange(CarouselCloseFramesKey.self) { state.carouselCloseFrames = $0 }
        }
        .ignoresSafeArea()
        .onDisappear { state.carouselCardFrames = [:]; state.carouselCloseFrames = [:] }
    }

    private var modifierName: String { state.carouselModifier == .control ? "⌃" : "⌥" }
}

/// Where each fanned card is, in the window's coordinates (the root space).
struct CarouselFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct CarouselFrameReporter: View {
    let id: String
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: CarouselFramesKey.self, value: [id: g.frame(in: .named("glassineRoot"))])
        }
    }
}

/// Where each card's × is, the same way; the click is matched by hand too.
struct CarouselCloseFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct CarouselCloseReporter: View {
    let id: String
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: CarouselCloseFramesKey.self, value: [id: g.frame(in: .named("glassineRoot")).insetBy(dx: -6, dy: -6)])
        }
    }
}

/// A page in little: its title and its first lines, as the mosaic's cards
/// draw them, on a plate of the theme's glass. A small number in the corner
/// is the key that jumps to it.
struct PageCard: View {
    @EnvironmentObject var state: AppState
    let doc: DocumentRef
    var highlighted: Bool
    var current: Bool
    var number: Int? = nil
    /// A × in the corner, for the card under the highlight: a click on it
    /// closes the page and the cards close up (Pages.swift matches the click).
    var closable: Bool = false

    private var theme: Theme { state.theme }
    private var lines: [PreviewLine] { Array(MarkdownPreview.lines(for: doc, limit: 12).prefix(11)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 6) {
                Text(doc.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(theme.headingColor.asColor)
                Spacer(minLength: 0)
                if closable {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(theme.text.color.opacity(0.7))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(theme.text.color.opacity(0.12)))
                        .background(CarouselCloseReporter(id: doc.id))
                        .help("Close this page")
                        .transition(.scale.combined(with: .opacity))
                }
                if let number {
                    Text("\(number)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(highlighted ? theme.accent.color : theme.text.color.opacity(0.45))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(theme.text.color.opacity(highlighted ? 0.1 : 0.06)))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines) { line in
                    PreviewLineView(line: line, theme: theme)
                }
            }
            .foregroundStyle(theme.text.color.opacity(0.72))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.tint.color.opacity(theme.isDark ? 0.84 : 0.92))
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.text.color.opacity(highlighted ? 0.1 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(highlighted ? theme.accent.color.opacity(0.95) : theme.text.color.opacity(current ? 0.28 : 0.1),
                              lineWidth: highlighted ? 2 : 1)
        )
        .shadow(color: Color.black.opacity(highlighted ? (theme.isDark ? 0.42 : 0.18) : 0.12), radius: highlighted ? 20 : 8, y: highlighted ? 9 : 3)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The open pages as a row of pips in the footer: one a page, the one on
/// screen lit, in the order they were last used. A click goes to that page;
/// the pointer resting on one lifts a small picture of the page above it,
/// so the page can be told before it is chosen.
struct PagePips: View {
    @EnvironmentObject var state: AppState
    @State private var hovered: String?
    /// The pip whose preview is up: the hovered one, a beat after the
    /// pointer arrives, and until it leaves the row.
    @State private var previewing: String?
    @State private var previewWork: DispatchWorkItem?

    private var theme: Theme { state.theme }
    private static let previewSize = CGSize(width: 200, height: 142)

    var body: some View {
        let pages = state.openPages.filter { state.library.document(withID: $0) != nil }
        if state.keepsPagesOpen, pages.count > 1 {
            HStack(spacing: 5) {
                ForEach(pages.prefix(9), id: \.self) { id in
                    let isCurrent = state.document?.relativePath == id
                    Capsule()
                        .fill(isCurrent ? theme.accent.color.opacity(0.9) : theme.text.color.opacity(hovered == id ? 0.6 : 0.28))
                        .frame(width: isCurrent ? 12 : 5, height: 5)
                        .contentShape(Rectangle().inset(by: -4))
                        .onHover { inside in hover(id, inside) }
                        .onTapGesture {
                            // ⌥-click closes the page; a click goes to it.
                            if NSEvent.modifierFlags.contains(.option) { state.closePage(id) } else { state.switchToPage(id) }
                        }
                        .help((state.library.document(withID: id)?.title ?? id) + " — click to open, ⌥-click to close, right-click for more")
                        .contextMenu {
                            Button("Close Page") { state.closePage(id) }
                            Button("Close Other Pages") { state.closeOtherPages(keeping: id) }
                            Button("Close All Pages") { state.closeAllPages() }
                        }
                        .overlay(alignment: .bottom) {
                            // The preview rides on its own pip so it sits over it.
                            if previewing == id, let doc = state.library.document(withID: id) {
                                preview(doc)
                                    .offset(y: -14)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.86, anchor: .bottom).combined(with: .opacity),
                                        removal: .opacity))
                            }
                        }
                }
                if pages.count > 9 {
                    Text("+\(pages.count - 9)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .opacity(0.5)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: state.document?.relativePath)
            .animation(.easeOut(duration: 0.15), value: pages)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: previewing)
            .padding(.leading, 6)
            .onChange(of: state.document?.relativePath) { _, _ in
                previewWork?.cancel()
                previewing = nil
            }
        }
    }

    /// The preview comes up after the pointer has rested a moment on a pip —
    /// a pass across the row brings nothing — and moves at once to the next.
    private func hover(_ id: String, _ inside: Bool) {
        previewWork?.cancel()
        if inside {
            hovered = id
            if previewing != nil {
                previewing = id
            } else {
                let work = DispatchWorkItem { if hovered == id { previewing = id } }
                previewWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
            }
        } else {
            if hovered == id { hovered = nil }
            // A moment's grace, so crossing the gap to the next pip keeps the
            // preview up and moving rather than blinking it off and on.
            let work = DispatchWorkItem { if hovered == nil { previewing = nil } }
            previewWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }

    private func preview(_ doc: DocumentRef) -> some View {
        PageCard(doc: doc, highlighted: false, current: false)
            .frame(width: Self.previewSize.width, height: Self.previewSize.height)
            .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.2), radius: 18, y: 8)
            .allowsHitTesting(false)
            .fixedSize()
    }
}
