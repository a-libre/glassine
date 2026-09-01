import AppKit
import SwiftUI

/// Craft-style mosaic of the whole library: one card per document with its
/// title and a small rendered preview. Click or press Return to open.
struct GalleryView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var nav = GalleryNavigator()
    @FocusState private var searchFocused: Bool
    /// Shared with the editor so an opened card can grow into the page.
    let zoom: Namespace.ID

    private var theme: Theme { state.theme }

    private var documents: [DocumentRef] {
        if let filtered = state.filteredDocuments { return filtered }
        return state.sorted(state.library.allDocuments)
    }

    private var headerTitle: String {
        if let tag = state.tagFilter { return "#\(tag)" }
        if !state.searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "Search" }
        return "All Documents"
    }

    var body: some View {
        GeometryReader { geo in
            let docs = documents
            let columns = max(2, min(5, Int((geo.size.width - 56) / 270)))
            let plan = MasonryPlan(items: docs, columns: columns, spacing: 14) { GalleryCard.estimatedHeight(for: $0) }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if docs.isEmpty {
                            emptyState
                        } else {
                            HStack(alignment: .top, spacing: 14) {
                                ForEach(plan.columns.indices, id: \.self) { c in
                                    LazyVStack(spacing: 14) {
                                        ForEach(plan.columns[c]) { doc in
                                            GalleryCard(doc: doc, isSelected: nav.selectedID == doc.id, zoom: zoom)
                                                .id(doc.id)
                                                .background(CardFrameReporter(id: doc.id))
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 52)
                    .padding(.bottom, 48)
                }
                .coordinateSpace(name: GalleryNavigator.coordinateSpace)
                .onPreferenceChange(CardFramesKey.self) { nav.frames = $0 }
                .onChange(of: nav.selectedID) { _, id in
                    guard let id else { return }
                    // Next pass: by then the cards have laid out and reported where they are.
                    DispatchQueue.main.async {
                        guard let anchor = nav.scrollAnchor(toReveal: id, viewportHeight: geo.size.height) else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: anchor) }
                    }
                }
            }
            .onAppear {
                nav.plan = plan
                nav.ensureSelection(preferring: state.document?.relativePath)
            }
            .onChange(of: plan.signature) { _, _ in
                nav.plan = plan
                nav.planChanged(query: state.searchText)
            }
        }
        .foregroundStyle(theme.text.color)
        .background(WindowTap { nav.window = $0 })
        .background(
            // Escape works from anywhere in the window, not just when something has focus.
            Button("") {
                if !state.searchText.isEmpty {
                    state.searchText = ""
                    searchFocused = false
                } else if state.tagFilter != nil {
                    state.tagFilter = nil
                } else if state.document != nil {
                    state.showingGallery = false
                }
            }
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)
        )
        .onAppear {
            nav.install { [weak state] event in
                guard let state else { return false }
                return GalleryView.handle(event, nav: nav, state: state)
            }
            // Whatever text field had focus (the sidebar search, say) gives it up so the
            // arrow keys go to the cards straight away.
            DispatchQueue.main.async { nav.blurFieldEditor() }
            takeSearchFocusIfAsked()
        }
        .onChange(of: state.searchFocusRequest) { _, _ in takeSearchFocusIfAsked() }
        .onDisappear { nav.uninstall() }
    }

    private func takeSearchFocusIfAsked() {
        guard state.searchFocusPending else { return }
        state.searchFocusPending = false
        DispatchQueue.main.async { searchFocused = true }
    }

    /// Keyboard handling for the mosaic. Returns true when the event was consumed.
    private static func handle(_ event: NSEvent, nav: GalleryNavigator, state: AppState) -> Bool {
        guard let window = event.window, window === (nav.window ?? NSApp.mainWindow) else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        // A text field being edited (the search box) owns a field editor; the document
        // editor's text view is not one, and it is gone from the window here anyway.
        let fieldEditor = (window.firstResponder as? NSTextView).flatMap { $0.isFieldEditor ? $0 : nil }
        let before = nav.selectedID
        var handled = false
        var key = "?"

        switch event.specialKey {
        case .leftArrow?, .rightArrow?:
            key = event.specialKey == .leftArrow ? "←" : "→"
            guard modifiers.isEmpty else { break }
            // With a query in the box, left/right move the caret through it.
            if let fieldEditor, !fieldEditor.string.isEmpty { break }
            nav.blurFieldEditor()
            nav.move(event.specialKey == .leftArrow ? .left : .right)
            handled = true
        case .upArrow?, .downArrow?:
            key = event.specialKey == .upArrow ? "↑" : "↓"
            guard modifiers.isEmpty else { break }
            // Up/down leave the search box (keeping the query) and walk the cards.
            if fieldEditor != nil { nav.blurFieldEditor() }
            nav.move(event.specialKey == .upArrow ? .up : .down)
            handled = true
        case .carriageReturn?, .enter?:
            key = "↩"
            guard modifiers.isEmpty || modifiers == .command, let doc = nav.selectedDocument else { break }
            if modifiers == .command {
                state.openInReview(doc)
            } else {
                state.open(doc, fromCard: true)
            }
            handled = true
        default:
            return false
        }

        let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        nav.note("\(key) mods=\(modifiers.rawValue) responder=\(responder) fieldEditor=\(fieldEditor != nil) \(before ?? "-") → \(nav.selectedID ?? "-") handled=\(handled) frames=\(nav.frames.count)")
        return handled
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                state.newDocument()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(theme.text.color.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("New Document (⌘N)")

            Text(headerTitle)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("\(documents.count)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .opacity(0.4)
            if state.tagFilter != nil {
                Button {
                    state.tagFilter = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).opacity(0.45)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            gallerySearch
            SortMenu()
            if state.document != nil {
                Button {
                    state.showingGallery = false
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold))
                        Text("Back to document").font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule().fill(theme.text.color.opacity(0.08)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Back to the open document (Esc)")
            }
        }
    }

    private var gallerySearch: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .opacity(0.45)
            TextField("Search", text: $state.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
                .onSubmit {
                    if let doc = nav.selectedDocument ?? state.filteredDocuments?.first { state.open(doc) }
                }
            if !state.searchText.isEmpty {
                Button {
                    state.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).opacity(0.45)
                }
                .buttonStyle(.plain)
            } else if !searchFocused {
                Text("⌘F")
                    .font(.system(size: 10.5))
                    .opacity(0.3)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 210, height: 28)
        .background(Capsule().fill(theme.text.color.opacity(theme.isDark ? 0.07 : 0.05)))
        .help("Search titles, tags and text (⌘F)")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "leaf")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.accent.color.opacity(0.7))
            Text(state.filteredDocuments != nil ? "Nothing matches" : "No documents yet")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .opacity(0.6)
            if state.filteredDocuments == nil {
                Button("New Document") { state.newDocument() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Layout plan

/// Distributes documents into columns, shortest column first, using an
/// estimated height per card, and remembers where each one landed so the
/// keyboard can move spatially.
struct MasonryPlan {
    struct Slot { let column: Int; let row: Int; let midY: CGFloat }

    let columns: [[DocumentRef]]
    let slots: [String: Slot]
    let signature: Int

    init(items: [DocumentRef], columns count: Int, spacing: CGFloat, estimate: (DocumentRef) -> CGFloat) {
        let n = max(1, count)
        var cols = Array(repeating: [DocumentRef](), count: n)
        var heights = Array(repeating: CGFloat(0), count: n)
        var slots: [String: Slot] = [:]
        var hasher = Hasher()
        hasher.combine(n)
        for item in items {
            var target = 0
            for i in heights.indices where heights[i] < heights[target] { target = i }
            let h = estimate(item)
            slots[item.id] = Slot(column: target, row: cols[target].count, midY: heights[target] + h / 2)
            cols[target].append(item)
            heights[target] += h + spacing
            hasher.combine(item.id)
        }
        self.columns = cols
        self.slots = slots
        self.signature = hasher.finalize()
    }

    var firstID: String? { columns.first(where: { !$0.isEmpty })?.first?.id }
}

final class GalleryNavigator: ObservableObject {
    enum Direction { case up, down, left, right }

    static let coordinateSpace = "glassine.gallery"
    /// The navigator of the mosaic currently on screen, for diagnostics.
    static weak var current: GalleryNavigator?

    @Published var selectedID: String?
    var plan: MasonryPlan?
    weak var window: NSWindow?
    /// Where the cards that exist right now sit, in the scroll view's coordinates.
    /// Cards the lazy stacks have not built yet are absent.
    var frames: [String: CGRect] = [:]
    private var monitor: Any?
    private var lastQuery = ""
    private(set) var log: [String] = []

    var selectedDocument: DocumentRef? {
        guard let id = selectedID, let plan else { return nil }
        for col in plan.columns { if let d = col.first(where: { $0.id == id }) { return d } }
        return nil
    }

    func ensureSelection(preferring preferred: String?) {
        guard let plan else { return }
        let all = plan.columns.flatMap { $0 }
        if let preferred, all.contains(where: { $0.id == preferred }) {
            if selectedID == nil { selectedID = preferred }
            return
        }
        if let current = selectedID, all.contains(where: { $0.id == current }) { return }
        selectedID = plan.firstID
    }

    /// The layout was rebuilt: keep the selection if it still exists, except when the
    /// search query changed, where the top result is what Return should open.
    func planChanged(query: String) {
        if query != lastQuery {
            lastQuery = query
            if !query.isEmpty { selectedID = plan?.firstID; return }
        }
        ensureSelection(preferring: nil)
    }

    func move(_ direction: Direction) {
        guard let plan else { return }
        guard let id = selectedID, let slot = plan.slots[id] else {
            selectedID = plan.firstID
            return
        }
        switch direction {
        case .up:
            if slot.row > 0 { selectedID = plan.columns[slot.column][slot.row - 1].id }
        case .down:
            let col = plan.columns[slot.column]
            if slot.row + 1 < col.count { selectedID = col[slot.row + 1].id }
        case .left, .right:
            let target = slot.column + (direction == .left ? -1 : 1)
            guard target >= 0, target < plan.columns.count, !plan.columns[target].isEmpty else { return }
            // Nearest card vertically in the neighbouring column.
            let best = plan.columns[target].min { a, b in
                abs((plan.slots[a.id]?.midY ?? 0) - slot.midY) < abs((plan.slots[b.id]?.midY ?? 0) - slot.midY)
            }
            selectedID = best?.id
        }
    }

    /// How to scroll so the card is fully on screen, or nil when it already is.
    /// Unbuilt cards (off screen in a lazy stack) are centred.
    func scrollAnchor(toReveal id: String, viewportHeight: CGFloat) -> UnitPoint? {
        guard let frame = frames[id] else { return .center }
        let margin: CGFloat = 12
        if frame.minY < margin { return .top }
        if frame.maxY > viewportHeight - margin {
            // Taller than the viewport: showing the top is more useful than the bottom.
            return frame.height > viewportHeight - 2 * margin ? .top : .bottom
        }
        return nil
    }

    /// Ends editing in whatever text field has focus (the search box).
    func blurFieldEditor() {
        guard let window = window ?? NSApp.keyWindow,
              let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return }
        window.makeFirstResponder(nil)
    }

    func install(_ handler: @escaping (NSEvent) -> Bool) {
        uninstall()
        GalleryNavigator.current = self
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event) ? nil : event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if GalleryNavigator.current === self { GalleryNavigator.current = nil }
    }

    func note(_ line: String) {
        log.append(line)
        if log.count > 20 { log.removeFirst(log.count - 20) }
    }

    var debugDescription: String {
        let sel = selectedID ?? "-"
        let slot = selectedID.flatMap { plan?.slots[$0] }.map { "col \($0.column) row \($0.row)" } ?? "no slot"
        let cols = plan?.columns.map(\.count).map(String.init).joined(separator: "/") ?? "no plan"
        return "gallery: selected=\(sel) (\(slot)) columns=\(cols) frames=\(frames.count) monitor=\(monitor != nil) window=\(window != nil)\n"
            + log.joined(separator: "\n")
    }

    deinit { uninstall() }
}

/// Reports the NSWindow hosting a SwiftUI view.
struct WindowTap: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> TapView { let v = TapView(); v.onWindow = onWindow; return v }
    func updateNSView(_ v: TapView, context: Context) { v.onWindow = onWindow; v.report() }

    final class TapView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
        func report() { if let window { onWindow?(window) } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Each built card reports its frame in the scroll view's coordinate space so the
/// navigator knows whether the selection is on screen.
struct CardFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct CardFrameReporter: View {
    let id: String
    var body: some View {
        GeometryReader { g in
            Color.clear.preference(key: CardFramesKey.self, value: [id: g.frame(in: .named(GalleryNavigator.coordinateSpace))])
        }
    }
}

// MARK: - Card

struct GalleryCard: View {
    @EnvironmentObject var state: AppState
    let doc: DocumentRef
    var isSelected: Bool = false
    let zoom: Namespace.ID
    @State private var hovering = false

    static let previewCap: CGFloat = 280

    private var theme: Theme { state.theme }
    private var isCurrent: Bool { state.document?.relativePath == doc.id }
    private var starred: Bool { state.settings.isStarred(doc.id) }
    private var lines: [PreviewLine] { MarkdownPreview.lines(for: doc) }

    static func estimatedHeight(for doc: DocumentRef) -> CGFloat {
        let lines = MarkdownPreview.lines(for: doc)
        let titleLines: CGFloat = doc.title.count > 26 ? 2 : 1
        let body = lines.reduce(CGFloat(0)) { $0 + $1.estimatedHeight }
        return 16 + titleLines * 20 + 10 + min(body, previewCap) + 16
    }

    private var previewOverflows: Bool {
        lines.reduce(CGFloat(0)) { $0 + $1.estimatedHeight } > GalleryCard.previewCap
    }

    private var shadowColor: Color {
        if isSelected { return theme.accent.color.opacity(0.25) }
        if hovering { return Color.black.opacity(theme.isDark ? 0.22 : 0.08) }
        return .clear
    }

    private var borderColor: Color {
        if isSelected { return theme.accent.color.opacity(0.95) }
        if isCurrent { return theme.accent.color.opacity(0.45) }
        return theme.text.color.opacity(hovering ? 0.18 : 0.08)
    }

    var body: some View {
        Button {
            state.open(doc, fromCard: true)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 6) {
                    Text(doc.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(theme.headingColor.asColor)
                    Spacer(minLength: 0)
                    if starred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.accent.color)
                            .padding(.top, 3)
                    }
                }
                if lines.isEmpty {
                    if doc.contentLoaded {
                        Text("Empty")
                            .font(.system(size: 11))
                            .italic()
                            .opacity(0.35)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(lines) { line in
                            PreviewLineView(line: line, theme: theme)
                        }
                    }
                    .foregroundStyle(theme.text.color.opacity(0.74))
                    .frame(maxWidth: .infinity, maxHeight: GalleryCard.previewCap, alignment: .topLeading)
                    .clipped()
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: previewOverflows ? 0.70 : 1),
                                .init(color: previewOverflows ? .clear : .black, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.text.color.opacity(isSelected ? 0.09 : (hovering ? 0.075 : 0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : (isCurrent ? 1.5 : 1))
            )
            .shadow(color: shadowColor, radius: isSelected ? 12 : 10, y: isSelected ? 2 : 4)
            .offset(y: hovering && !isSelected ? -1 : 0)
            .overlay(alignment: .bottomTrailing) {
                if hovering || isSelected {
                    Text(caption)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.45)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(theme.tint.color.opacity(0.85)))
                        .padding(10)
                        .transition(.opacity)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: doc.id, in: zoom)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .contextMenu {
            Button("Open") { state.open(doc, fromCard: true) }
            Button("Open in Review") { state.openInReview(doc) }
            Divider()
            Button(starred ? "Unstar" : "Star") { state.toggleStar(doc.id) }
            Button("Rename…") { state.promptRename(doc.id, isFolder: false) }
            Button("Duplicate") { state.duplicate(doc.id) }
            Divider()
            Button("Copy as Markdown") { state.copyDocument(doc, asMarkdown: true) }
            Button("Copy as Rich Text") { state.copyDocument(doc, asMarkdown: false) }
            Divider()
            Menu("Move To") {
                Button("Documents (top level)") { state.move(doc.id, toFolder: "") }
                ForEach(state.library.root.allFolders) { f in
                    Button(f.id.replacingOccurrences(of: "/", with: " / ")) { state.move(doc.id, toFolder: f.id) }
                }
            }
            Button("Reveal in Finder") { state.library.revealInFinder(doc.id) }
            Divider()
            Button("Move to Trash", role: .destructive) { state.trash(doc.id) }
        }
    }

    private var caption: String {
        let when = doc.modified.shortRelative
        return doc.folder.isEmpty ? when : "\(doc.folder) · \(when)"
    }
}

// MARK: - Preview rendering

struct PreviewLine: Identifiable {
    enum Kind {
        case heading(Int), body, bullet, numbered(String), quote, code, rule, blank
    }
    let id: Int
    let kind: Kind
    let text: AttributedString

    var estimatedHeight: CGFloat {
        switch kind {
        case .blank: return 6
        case .rule: return 9
        case .heading: return 20
        case .code: return 14
        default:
            // Roughly 46 characters per line at the preview size, capped at three lines.
            let chars = text.characters.count
            let wrapped = min(3, max(1, Int(ceil(Double(chars) / 46.0))))
            return CGFloat(wrapped) * 14 + 3
        }
    }
}

enum MarkdownPreview {
    private static var cache: [String: [PreviewLine]] = [:]
    private static let heading = try! NSRegularExpression(pattern: "^(#{1,6})[ \\t]+(.*)$")
    private static let bullet = try! NSRegularExpression(pattern: "^[ \\t]*[-*+][ \\t]+(?:\\[[ xX]\\][ \\t]+)?(.*)$")
    private static let numbered = try! NSRegularExpression(pattern: "^[ \\t]*(\\d{1,3})[.)][ \\t]+(.*)$")
    private static let quote = try! NSRegularExpression(pattern: "^[ \\t]*>[ \\t]?(.*)$")
    private static let rule = try! NSRegularExpression(pattern: "^[ \\t]*(?:(?:-[ \\t]*){3,}|(?:\\*[ \\t]*){3,}|(?:_[ \\t]*){3,})$")

    static func lines(for doc: DocumentRef, limit: Int = 26) -> [PreviewLine] {
        guard doc.contentLoaded else { return [] }
        let key = "\(doc.id)|\(doc.modified.timeIntervalSince1970)|\(doc.size)"
        if let hit = cache[key] { return hit }
        let result = parse(doc.preview, title: doc.title, limit: limit)
        if cache.count > 600 { cache.removeAll() }
        cache[key] = result
        return result
    }

    private static func match(_ regex: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length))
    }

    private static func inline(_ s: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        if let a = try? AttributedString(markdown: s, options: options) { return a }
        return AttributedString(s)
    }

    static func parse(_ text: String, title: String, limit: Int) -> [PreviewLine] {
        var out: [PreviewLine] = []
        var inFence = false
        var lastWasBlank = true
        var skippedTitle = false
        let normalizedTitle = title.lowercased()

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if out.count >= limit { break }
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence {
                out.append(PreviewLine(id: out.count, kind: .code, text: AttributedString(line)))
                lastWasBlank = false
                continue
            }
            if trimmed.isEmpty {
                if !lastWasBlank && !out.isEmpty {
                    out.append(PreviewLine(id: out.count, kind: .blank, text: AttributedString()))
                }
                lastWasBlank = true
                continue
            }
            // The first real line usually is the title (Glassine names files from it); don't repeat it.
            if !skippedTitle {
                skippedTitle = true
                if line.derivedMarkdownTitle.lowercased() == normalizedTitle { continue }
            }
            lastWasBlank = false
            let ns = line as NSString

            if let m = match(heading, line) {
                let level = m.range(at: 1).length
                out.append(PreviewLine(id: out.count, kind: .heading(min(level, 3)), text: inline(ns.substring(with: m.range(at: 2)))))
            } else if match(rule, line) != nil {
                out.append(PreviewLine(id: out.count, kind: .rule, text: AttributedString()))
            } else if let m = match(quote, line) {
                out.append(PreviewLine(id: out.count, kind: .quote, text: inline(ns.substring(with: m.range(at: 1)))))
            } else if let m = match(bullet, line) {
                out.append(PreviewLine(id: out.count, kind: .bullet, text: inline(ns.substring(with: m.range(at: 1)))))
            } else if let m = match(numbered, line) {
                let n = ns.substring(with: m.range(at: 1)) + "."
                out.append(PreviewLine(id: out.count, kind: .numbered(n), text: inline(ns.substring(with: m.range(at: 2)))))
            } else if line.hasPrefix("    ") || line.hasPrefix("\t") {
                out.append(PreviewLine(id: out.count, kind: .code, text: AttributedString(trimmed)))
            } else {
                out.append(PreviewLine(id: out.count, kind: .body, text: inline(trimmed)))
            }
        }
        // Trim a trailing blank.
        if case .blank? = out.last?.kind { out.removeLast() }
        return out
    }
}

struct PreviewLineView: View {
    let line: PreviewLine
    let theme: Theme

    var body: some View {
        switch line.kind {
        case .blank:
            Color.clear.frame(height: 3)
        case .rule:
            Rectangle().fill(theme.text.color.opacity(0.14)).frame(height: 1).padding(.vertical, 4)
        case .heading(let level):
            Text(line.text)
                .font(.system(size: level == 1 ? 12.5 : (level == 2 ? 11.5 : 11), weight: .semibold))
                .foregroundStyle(theme.headingColor.asColor.opacity(0.95))
                .lineLimit(2)
                .padding(.top, 2)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("•").foregroundStyle(theme.accent.color)
                Text(line.text).lineLimit(2)
            }
            .font(.system(size: 10.5))
        case .numbered(let n):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(n).foregroundStyle(theme.accent.color).monospacedDigit()
                Text(line.text).lineLimit(2)
            }
            .font(.system(size: 10.5))
        case .quote:
            Text(line.text)
                .font(.system(size: 10.5))
                .italic()
                .opacity(0.8)
                .lineLimit(2)
                .padding(.leading, 8)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(theme.accent.color.opacity(0.5)).frame(width: 2)
                }
        case .code:
            Text(line.text)
                .font(.system(size: 9.5, design: .monospaced))
                .opacity(0.85)
                .lineLimit(1)
        case .body:
            Text(line.text)
                .font(.system(size: 10.5))
                .lineLimit(3)
        }
    }
}
