import AppKit
import SwiftUI

/// Craft-style mosaic of the whole library: one card per document with its
/// title and a small rendered preview. Click or press Return to open; pick a
/// card up and carry it to put the library in your own order.
struct GalleryView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var nav = GalleryNavigator()
    @State private var drag = WallDrag()
    @FocusState private var searchFocused: Bool
    /// Shared with the editor so an opened card can grow into the page.
    let zoom: Namespace.ID
    /// Bumped when a card reports a height the plan did not have yet, so the
    /// wall is laid out again with it.
    @State private var measured = 0
    /// The stretch of the wall the scroll view shows, with a margin either
    /// side, in the wall's own coordinates — in coarse steps, so the cards
    /// are not rebuilt on every turn of the wheel.
    @State private var band: ClosedRange<CGFloat> = 0 ... 1536
    /// When the wall came on screen: the cards cascade in for a moment after,
    /// and arrive at once from then on (scrolled to, say).
    @State private var arrived = Date()

    private var theme: Theme { state.theme }

    private var documents: [DocumentRef] {
        if let filtered = state.filteredDocuments { return filtered }
        return state.sorted(state.activeDocuments)   // the Shelf stays off the wall; search still reaches it
    }

    /// Cards can be carried into an order only on the whole wall: a search, a
    /// tag or a day shows a selection, and an order among a selection is not one.
    private var reorderable: Bool { state.filteredDocuments == nil }

    private var headerTitle: String {
        if let day = state.dayFilter { return GalleryView.dayName(day) }
        if let tag = state.tagFilter { return "#\(tag)" }
        if !state.searchText.trimmingCharacters(in: .whitespaces).isEmpty { return "Search" }
        return "All Documents"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    /// "Today", "Yesterday", or "Thursday, October 15" — the day's wall by name.
    static func dayName(_ key: Int) -> String {
        let date = AppState.date(forDayKey: key)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return dayFormatter.string(from: date)
    }

    /// The day's own note, when the wall is a day's: open it, or start it.
    @ViewBuilder
    private var dayNoteButton: some View {
        if let day = state.dayFilter {
            let date = AppState.date(forDayKey: day)
            let note = state.dailyNotesByDay[day]
            Button {
                if let note { state.open(note, fromCard: true) } else { state.openNote(for: date) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: note == nil ? "plus" : "sun.max")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.accent.color)
                    Text(note == nil ? "Start the day's note" : "The day's note")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(Capsule().fill(theme.text.color.opacity(theme.isDark ? 0.07 : 0.05)))
                .overlay(Capsule().strokeBorder(theme.accent.color.opacity(note == nil ? 0.4 : 0), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(note == nil ? "A note for \(GalleryView.dayName(day)), in the Daily folder" : "Open the note for \(GalleryView.dayName(day))")
        }
    }

    static let sideInset: CGFloat = 28
    static let spacing: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let docs = documents
            let shown = drag.active ? drag.arranged(docs) : docs
            let wallWidth = max(100, geo.size.width - 2 * GalleryView.sideInset)
            let columns = max(2, min(5, Int((geo.size.width - 56) / 270)))
            let plan = WallPlan(items: shown, columns: columns, width: wallWidth, spacing: GalleryView.spacing, version: measured)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if docs.isEmpty {
                        emptyState
                    } else {
                        wall(plan, viewport: geo.size)
                    }
                }
                .padding(.horizontal, GalleryView.sideInset)
                .padding(.top, 52)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .topLeading)
                // The ground between and below the cards carries the window.
                .background(Color.clear.dragsWindowByGround())
                .background(ScrollHostFinder { nav.scrollView = $0; drag.scrollView = $0 })
            }
            .coordinateSpace(name: GalleryNavigator.coordinateSpace)
            .overlay(alignment: .topLeading) {
                // The card being carried rides over the wall, under the pointer.
                if let id = drag.id, let doc = docs.first(where: { $0.id == id }) {
                    LiftedCard(doc: doc, drag: drag, zoom: zoom)
                }
            }
            .onPreferenceChange(CardFramesKey.self) { nav.frames = $0 }
            .onChange(of: nav.selectedID) { _, id in
                guard let id else { return }
                // Next pass: by then the wall has laid out and said where it is.
                DispatchQueue.main.async { nav.reveal(id, viewportHeight: geo.size.height) }
            }
            .onAppear {
                nav.plan = plan
                drag.viewport = geo.size
                nav.ensureSelection(preferring: state.document?.relativePath)
                // For a check shot: the wall is on screen once the pass that
                // built it has been committed, which is the next turn of the loop.
                ScreenshotMode.lap("gallery", "appeared")
                DispatchQueue.main.async { ScreenshotMode.lap("gallery", "up") }
            }
            .onChange(of: plan.signature) { _, _ in
                nav.plan = plan
                nav.planChanged(query: state.searchText)
            }
            .onChange(of: geo.size) { _, size in drag.viewport = size }
        }
        .environment(drag)
        .foregroundStyle(theme.text.color)
        .background(WindowTap { nav.window = $0 })
        .background(
            // Escape works from anywhere in the window, not just when something
            // has focus: a search, a tag or a day is cleared first; with the
            // whole wall showing, Esc goes to the Timelapse, whose Esc comes back.
            Button("") {
                if !state.searchText.isEmpty { searchFocused = false }
                state.escapeFromGallery()
            }
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)
        )
        .onAppear {
            arrived = Date()
            nav.install { [weak state, weak nav] event in
                guard let state, let nav else { return false }
                return GalleryView.handle(event, nav: nav, state: state)
            }
            // Whatever text field had focus (the sidebar search, say) gives it up so the
            // arrow keys go to the cards straight away.
            DispatchQueue.main.async { nav.blurFieldEditor() }
            takeSearchFocusIfAsked()
        }
        .onChange(of: state.searchFocusRequest) { _, _ in takeSearchFocusIfAsked() }
        .onDisappear { nav.uninstall(); drag.clear() }
    }

    // MARK: - The wall

    /// The cards at the places the plan gives them. Only the cards in and
    /// around the visible stretch are built; the rest are the plan's frames,
    /// which is all the scroll view needs of them. The card being carried,
    /// the selected one and the one a page is growing out of are always built.
    private func wall(_ plan: WallPlan, viewport: CGSize) -> some View {
        let keep = Set([nav.selectedID, drag.id, state.zoomingCard].compactMap { $0 })
        let cascade = Date().timeIntervalSince(arrived) < 0.6
        // The drag works from the plan on screen, and makes plans of its own
        // the same way.
        drag.plan = plan
        drag.planner = { docs in WallPlan(items: docs, columns: plan.columns.count, width: plan.width, spacing: plan.spacing) }
        drag.noteHeights(of: plan)
        // The keys and the reveal work from the plan as laid out — with the
        // heights the cards reported, not the first guesses. (The signature
        // the navigator is told about on change covers the order alone.)
        nav.plan = plan
        return ZStack(alignment: .topLeading) {
            ForEach(plan.visible(in: band, keeping: keep), id: \.id) { doc in
                let frame = plan.frames[doc.id] ?? .zero
                GalleryCard(doc: doc, isSelected: nav.selectedID == doc.id, zoom: zoom,
                            carried: drag.id == doc.id, reorderable: reorderable)
                    .frame(width: frame.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        if WallHeights.record(doc, width: frame.width, height: h) { measured &+= 1 }
                    }
                    .modifier(CardEntrance(id: doc.id, row: plan.slots[doc.id]?.row ?? 0, cascade: cascade))
                    .background(CardFrameReporter(id: doc.id))
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: plan.width, height: plan.height, alignment: .topLeading)
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named(GalleryNavigator.coordinateSpace)).origin } action: { origin in
            nav.wallOrigin = origin
            drag.wallMoved(to: origin)
            // A viewport's worth either side, so a card is built — and has
            // said how tall it really is — before it scrolls into view.
            let margin = max(500, viewport.height)
            let step: CGFloat = 256
            let lo = floor((-origin.y - margin) / step) * step
            let hi = ceil((-origin.y + viewport.height + margin) / step) * step
            if band.lowerBound != lo || band.upperBound != hi { band = lo ... hi }
        }
    }

    private func takeSearchFocusIfAsked() {
        guard state.searchFocusPending else { return }
        state.searchFocusPending = false
        DispatchQueue.main.async { searchFocused = true }
    }

    /// Keyboard handling for the mosaic. Returns true when the event was consumed.
    private static func handle(_ event: NSEvent, nav: GalleryNavigator, state: AppState) -> Bool {
        // A card over the wall — Settings, the command bar — has the keys;
        // Return in a field there is not a card to open.
        guard state.galleryOnScreen, !state.overlayUp else { return false }
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
            if !state.showingSearch { nav.blurFieldEditor() }
            nav.move(event.specialKey == .leftArrow ? .left : .right)
            handled = true
        case .upArrow?, .downArrow?:
            key = event.specialKey == .upArrow ? "↑" : "↓"
            guard modifiers.isEmpty else { break }
            // Up/down walk the cards; the sidebar's box gives up the keyboard, the
            // ⌘F overlay keeps it so the query stays live.
            if fieldEditor != nil, !state.showingSearch { nav.blurFieldEditor() }
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
                .contentTransition(.opacity)
            Text("\(documents.count)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .opacity(0.4)
                .contentTransition(.numericText())
            if state.tagFilter != nil || state.dayFilter != nil {
                Button {
                    if state.dayFilter != nil { state.dayFilter = nil } else { state.tagFilter = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13)).opacity(0.45)
                }
                .buttonStyle(.plain)
                .help("Back to every document (Esc)")
            }
            dayNoteButton
            Spacer()
            gallerySearch
            if state.dayFilter == nil { SortMenu() }
        }
        .animation(.easeOut(duration: 0.18), value: state.dayFilter)
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
        .background(GeometryReader { g in
            Color.clear.preference(key: SearchFieldFrameKey.self, value: g.frame(in: .named("glassineRoot")))
        })
        .opacity(state.showingSearch ? 0 : 1)
        .onPreferenceChange(SearchFieldFrameKey.self) { state.searchFieldFrame = $0 }
        .help("Search titles, tags and text (⌘F)")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: state.dayFilter != nil ? "moon.zzz" : "leaf")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.accent.color.opacity(0.7))
            Text(state.dayFilter != nil && state.searchText.isEmpty && state.tagFilter == nil
                 ? "Nothing written that day"
                 : (state.filteredDocuments != nil ? "Nothing matches" : "No documents yet"))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .opacity(0.6)
            if state.filteredDocuments == nil {
                Button("New Document  ⌘N") { state.newDocument() }
                    .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Layout plan

/// Where every card goes: the documents taken in order, each into the
/// shortest column so far, at the height the card was last measured at (an
/// estimate until it has been built once). The frames are the wall's own
/// coordinates. The plan is also what the keyboard moves through and what a
/// carried card is placed by.
struct WallPlan {
    struct Slot { let column: Int; let row: Int; let midY: CGFloat }

    let items: [DocumentRef]
    let columns: [[DocumentRef]]
    let frames: [String: CGRect]
    let slots: [String: Slot]
    let columnWidth: CGFloat
    let spacing: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// Changes when the order of the cards or the number of columns does.
    let signature: Int

    init(items: [DocumentRef], columns count: Int, width: CGFloat, spacing: CGFloat, version: Int = 0) {
        let n = max(1, count)
        let columnWidth = ((width - spacing * CGFloat(n - 1)) / CGFloat(n)).rounded(.down)
        var cols = Array(repeating: [DocumentRef](), count: n)
        var heights = Array(repeating: CGFloat(0), count: n)
        var frames: [String: CGRect] = [:]
        var slots: [String: Slot] = [:]
        var hasher = Hasher()
        hasher.combine(n)
        for item in items {
            let target = WallPlan.shortest(heights)
            let h = WallHeights.height(for: item, width: columnWidth)
            frames[item.id] = CGRect(x: CGFloat(target) * (columnWidth + spacing), y: heights[target], width: columnWidth, height: h)
            slots[item.id] = Slot(column: target, row: cols[target].count, midY: heights[target] + h / 2)
            cols[target].append(item)
            heights[target] += h + spacing
            hasher.combine(item.id)
        }
        self.items = items
        self.columns = cols
        self.frames = frames
        self.slots = slots
        self.columnWidth = columnWidth
        self.spacing = spacing
        self.width = width
        self.height = max(0, (heights.max() ?? 0) - spacing)
        self.signature = hasher.finalize()
    }

    /// The column a card goes into next: the shortest, the leftmost of equals.
    private static func shortest(_ heights: [CGFloat]) -> Int {
        var target = 0
        for i in heights.indices where heights[i] < heights[target] { target = i }
        return target
    }

    var firstID: String? { columns.first(where: { !$0.isEmpty })?.first?.id }

    /// The cards that lie in the band, and any in `keeping` wherever they are.
    func visible(in band: ClosedRange<CGFloat>, keeping: Set<String>) -> [DocumentRef] {
        items.filter { doc in
            guard let f = frames[doc.id] else { return false }
            return (f.maxY >= band.lowerBound && f.minY <= band.upperBound) || keeping.contains(doc.id)
        }
    }

}

/// How tall each card is at each width, as the cards themselves report it —
/// kept across openings of the wall, so the plan is right from the first
/// pass the second time. A card not yet built at this width takes its
/// height at the nearest width it was built at (a window being resized
/// moves the words by a line, not a card's worth), and one never built is
/// estimated from its lines.
enum WallHeights {
    /// By document (and its edit), then by column width.
    private static var heights: [String: [Int: CGFloat]] = [:]

    private static func key(_ doc: DocumentRef) -> String {
        "\(doc.id)|\(doc.modified.timeIntervalSince1970)|\(doc.size)"
    }

    static func height(for doc: DocumentRef, width: CGFloat) -> CGFloat {
        let w = Int(width)
        guard let known = heights[key(doc)] else { return GalleryCard.estimatedHeight(for: doc) }
        if let h = known[w] { return h }
        if let near = known.min(by: { abs($0.key - w) < abs($1.key - w) }) { return near.value }
        return GalleryCard.estimatedHeight(for: doc)
    }

    /// True when this is news — the plan should be made again.
    static func record(_ doc: DocumentRef, width: CGFloat, height: CGFloat) -> Bool {
        guard height > 0 else { return false }
        let k = key(doc), w = Int(width)
        if let h = heights[k]?[w], abs(h - height) < 0.5 { return false }
        if heights.count > 2000 { heights.removeAll() }
        heights[k, default: [:]][w] = height
        return true
    }
}

final class GalleryNavigator: ObservableObject {
    enum Direction { case up, down, left, right }

    static let coordinateSpace = "glassine.gallery"
    /// The navigator of the mosaic currently on screen, for diagnostics.
    static weak var current: GalleryNavigator?

    @Published var selectedID: String?
    var plan: WallPlan?
    weak var window: NSWindow?
    weak var scrollView: NSScrollView?
    /// Where the wall's top left is in the scroll view's coordinates — below
    /// zero once scrolled.
    var wallOrigin: CGPoint = .zero
    /// Where the cards that exist right now sit, in the scroll view's coordinates.
    /// Cards outside the band the wall builds are absent.
    var frames: [String: CGRect] = [:]
    private var monitor: Any?
    private var lastQuery = ""
    private(set) var log: [String] = []

    var selectedDocument: DocumentRef? {
        guard let id = selectedID, let plan else { return nil }
        return plan.items.first(where: { $0.id == id })
    }

    func ensureSelection(preferring preferred: String?) {
        guard let plan else { return }
        let all = plan.items
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

    /// Scrolls so the card is fully on screen, if it is not: the plan knows
    /// where every card is, built or not.
    func reveal(_ id: String, viewportHeight: CGFloat) {
        guard let plan, let f = plan.frames[id], let scrollView else { return }
        let margin: CGFloat = 12
        let top = wallOrigin.y + f.minY, bottom = wallOrigin.y + f.maxY
        var delta: CGFloat = 0
        if top < margin {
            delta = top - margin
        } else if bottom > viewportHeight - margin {
            // Taller than the viewport: showing the top is more useful than the bottom.
            delta = f.height > viewportHeight - 2 * margin ? top - margin : bottom - (viewportHeight - margin)
        }
        guard abs(delta) >= 1 else { return }
        scrollView.glide(by: delta)
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

// MARK: - Carrying a card

/// A card being carried across the wall.
///
/// Like a row in the sidebar's tree, the card itself lifts under the pointer
/// and travels with it; the wall lays itself out around the place it would
/// take if let go, with a spring, and a faint plate marks that place. Letting
/// go glides the card into it, and the whole wall's order is written down as
/// the library's *Your order*. The wall watches only the order and which card
/// is up; the lifted card alone watches the pointer, so the rest of the wall
/// is not redrawn on every move.
///
/// The carry is a carry on a board, not in a list: the card leaves its
/// column, which closes up under it, and goes into the column under the
/// pointer at the gap nearest it, whose cards below make room. Nothing else
/// moves — except at the foot of the wall, which stays level: a card at the
/// very foot of a column that has grown too tall crosses to the shortest.
/// The wall is still one order laid out shortest-column-first, so the board
/// the pointer makes is written back as the order that lays out as it (see
/// `sequence(withCardAt:)`), and a place the order cannot hold is not offered.
///
/// Coordinates are the scroll view's (`GalleryNavigator.coordinateSpace`),
/// which do not move with the scroll; the wall says where its own origin is
/// in them, which is how the pointer is placed on the plan.
@Observable
final class WallDrag {
    /// Within this much of the top or bottom of the wall the pointer scrolls it.
    static let scrollZone: CGFloat = 48
    /// The fastest the edges scroll, in points a frame.
    static let scrollSpeed: CGFloat = 14

    /// The document being carried, or nil.
    private(set) var id: String?
    /// The wall's order with the carried card where it would land now.
    private(set) var order: [String] = []
    /// Where the pointer is, in the scroll view's coordinates.
    private(set) var pointer: CGPoint = .zero
    /// Where in the card it was picked up, from its top left.
    private(set) var grab: CGSize = .zero
    /// How wide the card is on the wall, and how tall it was when picked up.
    private(set) var width: CGFloat = 0
    @ObservationIgnored private var height: CGFloat = 0
    /// Let go, and gliding into its place before the order is written down.
    private(set) var settling = false
    var active: Bool { id != nil }

    /// The plan the wall is laid out by right now, and how it makes one of
    /// any order; the wall keeps both current.
    @ObservationIgnored var plan: WallPlan?
    @ObservationIgnored var planner: (([DocumentRef]) -> WallPlan)?
    @ObservationIgnored var viewport: CGSize = .zero
    @ObservationIgnored weak var scrollView: NSScrollView?
    @ObservationIgnored private var wallOrigin: CGPoint = .zero
    /// The board without the carried card — the wall's columns as they
    /// stood at the pick-up, the card taken out of its own — and each card's
    /// height. The place the pointer means is read off this, which does not
    /// change as the card moves, so the choice cannot chase its own reflow.
    @ObservationIgnored private var board: [[String]] = []
    @ObservationIgnored private var heights: [String: CGFloat] = [:]
    /// The top of each gap in each column of the board: `tops[c][j]` is
    /// where a card put in at j would start.
    @ObservationIgnored private var tops: [[CGFloat]] = []
    @ObservationIgnored private var columnWidth: CGFloat = 0
    @ObservationIgnored private var spacing: CGFloat = 0
    /// The sequence for each place tried, once: the board does not change.
    @ObservationIgnored private var tried: [Int: (ids: [String], holds: Bool)] = [:]
    @ObservationIgnored private var placed = -1
    @ObservationIgnored private var speed: CGFloat = 0
    @ObservationIgnored private var scroller: Timer?

    // MARK: - The carry

    /// `point` is the pointer, in the scroll view's coordinates. False when
    /// there is nothing to carry it among.
    @discardableResult
    func begin(id: String, at point: CGPoint) -> Bool {
        guard !active, let plan, let frame = plan.frames[id] else { return false }
        self.id = id
        order = plan.items.map(\.id)
        pointer = point
        grab = CGSize(width: point.x - (wallOrigin.x + frame.minX), height: point.y - (wallOrigin.y + frame.minY))
        width = frame.width
        height = frame.height
        settling = false
        columnWidth = plan.columnWidth
        spacing = plan.spacing
        heights = plan.frames.mapValues(\.height)
        board = plan.columns.map { $0.map(\.id).filter { $0 != id } }
        tops = board.map { column in
            var y: CGFloat = 0
            var out = [y]
            for card in column { y += (heights[card] ?? 0) + plan.spacing; out.append(y) }
            return out
        }
        tried = [:]
        placed = -1
        NSCursor.closedHand.push()
        ScreenshotMode.note("wall drag begin \(id) at \(order.firstIndex(of: id) ?? -1) of \(order.count)")
        return true
    }

    func update(to point: CGPoint) {
        guard active, !settling else { return }
        pointer = point
        recompute()
        scrollIfAtEdge()
    }

    func wallMoved(to origin: CGPoint) {
        wallOrigin = origin
    }

    /// A card built while the wall scrolled under the carry may have come
    /// out a different height from the plan's guess; the board takes the
    /// new heights so its sequences keep laying out as it shows.
    func noteHeights(of plan: WallPlan) {
        guard active else { return }
        var changed = false
        for (card, frame) in plan.frames where heights[card] != frame.height {
            heights[card] = frame.height
            changed = true
        }
        guard changed else { return }
        tops = board.map { column in
            var y: CGFloat = 0
            var out = [y]
            for card in column { y += (heights[card] ?? 0) + spacing; out.append(y) }
            return out
        }
        tried = [:]
        placed = -1
    }

    /// The documents in the order being tried, for the wall to lay out. One
    /// that arrived since the pick-up goes at the end; one that went is skipped.
    func arranged(_ docs: [DocumentRef]) -> [DocumentRef] {
        var byID: [String: DocumentRef] = [:]
        for d in docs { byID[d.id] = d }
        var out = order.compactMap { byID.removeValue(forKey: $0) }
        out += docs.filter { byID[$0.id] != nil }
        return out
    }

    /// Let go: the card glides into its place, then `commit` writes the order
    /// down and the carry is cleared.
    func letGo(then commit: @escaping ([String]) -> Void) {
        stopScrolling()
        guard let id else { return }
        let final = order
        ScreenshotMode.note("wall drag end \(id) at \(final.firstIndex(of: id) ?? -1)")
        // The wall may not have laid out the last move yet: plan it afresh.
        let laid = planner.map { $0(arranged(plan?.items ?? [])) } ?? plan
        let hole = laid?.frames[id] ?? CGRect(origin: CGPoint(x: pointer.x - grab.width - wallOrigin.x, y: pointer.y - grab.height - wallOrigin.y), size: .zero)
        let home = CGPoint(x: wallOrigin.x + hole.minX + grab.width, y: wallOrigin.y + hole.minY + grab.height)
        let finish = {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                commit(final)
                self.clear()
            }
        }
        if GlassineTextView.reduceMotion || hypot(pointer.x - home.x, pointer.y - home.y) < 1 { finish(); return }
        settling = true
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) { pointer = home }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27, execute: finish)
    }

    func clear() {
        stopScrolling()
        if id != nil { NSCursor.pop() }
        id = nil
        order = []
        board = []
        tops = []
        heights = [:]
        tried = [:]
        settling = false
        placed = -1
    }

    /// The place the pointer means: the column under the middle of the held
    /// card, and in it the gap nearest that middle — among the gaps the order
    /// can hold the card in. Nothing in the pointer's column can hold it only
    /// when the wall is strange (a column with nothing in it); then the
    /// nearest gap anywhere.
    private func recompute() {
        guard id != nil, !board.isEmpty else { return }
        // The middle of the card as it is held, on the wall.
        let center = CGPoint(x: pointer.x - grab.width - wallOrigin.x + width / 2,
                             y: pointer.y - grab.height - wallOrigin.y + height / 2)
        let pitch = columnWidth + spacing
        let under = max(0, min(board.count - 1, Int(((center.x - columnWidth / 2) / pitch).rounded())))
        var best = -1
        var bestDistance = CGFloat.infinity
        func consider(_ c: Int, _ j: Int, _ distance: CGFloat) {
            guard distance < bestDistance, sequence(withCardAt: c, j).holds else { return }
            best = c * 100_000 + j
            bestDistance = distance
        }
        for j in tops[under].indices { consider(under, j, abs(tops[under][j] + height / 2 - center.y)) }
        if best < 0 {
            for c in board.indices where c != under {
                let x = CGFloat(c) * pitch + columnWidth / 2
                for j in tops[c].indices { consider(c, j, hypot(x - center.x, tops[c][j] + height / 2 - center.y)) }
            }
        }
        guard best >= 0, best != placed, let next = tried[best]?.ids else { return }
        placed = best
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { order = next }
    }

    /// The wall's order with the carried card put into column `c` at gap `j`
    /// of the board — the sequence that lays out as that board, shortest
    /// column first — and whether the card's place survives the laying out.
    ///
    /// The sequence is the board read off bottom-up the way the layout reads
    /// it in: at each step the next card is the one at the head of the
    /// column the layout would fill next, the shortest so far. While every
    /// column still has cards, the layout puts each card back exactly where
    /// the board has it. Once a column is spent while shortest the layout
    /// fills it anyway, with whatever comes next — the cards at the foot of
    /// the taller columns, taken lowest column first — and from there the
    /// foot of the wall is the layout's, not the board's. A place for the
    /// carried card past that point is not one the order can hold.
    private func sequence(withCardAt c: Int, _ j: Int) -> (ids: [String], holds: Bool) {
        let key = c * 100_000 + j
        if let hit = tried[key] { return hit }
        guard let id else { return ([], false) }
        var lists = board
        lists[c].insert(id, at: j)
        let n = lists.count
        let total = lists.reduce(0) { $0 + $1.count }
        var heads = Array(repeating: 0, count: n)
        var consumed = Array(repeating: CGFloat(0), count: n)
        var laid = Array(repeating: CGFloat(0), count: n)
        var out: [String] = []
        out.reserveCapacity(total)
        var diverged = false
        var holds = true
        for _ in 0..<total {
            var target = 0
            for i in 1..<n where laid[i] < laid[target] { target = i }
            var source = target
            if heads[target] >= lists[target].count {
                diverged = true
                source = -1
                for i in 0..<n where heads[i] < lists[i].count {
                    if source < 0 || consumed[i] < consumed[source] { source = i }
                }
            }
            let card = lists[source][heads[source]]
            heads[source] += 1
            if card == id, diverged { holds = false }
            let h = (heights[card] ?? 0) + spacing
            laid[target] += h
            consumed[source] += h
            out.append(card)
        }
        let result = (ids: out, holds: holds)
        tried[key] = result
        return result
    }

    // MARK: - Scrolling at the edges

    private func scrollIfAtEdge() {
        guard viewport.height > 0 else { return }
        let zone = WallDrag.scrollZone
        var v: CGFloat = 0
        if pointer.y < zone {
            v = -(zone - pointer.y) / zone
        } else if pointer.y > viewport.height - zone {
            v = (pointer.y - (viewport.height - zone)) / zone
        }
        speed = max(-1, min(1, v)) * WallDrag.scrollSpeed
        if speed == 0 {
            stopScrolling()
        } else if scroller == nil {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.scrollTick() }
            RunLoop.main.add(t, forMode: .common)
            scroller = t
        }
    }

    private func scrollTick() {
        guard active, !settling, speed != 0, let scrollView else { stopScrolling(); return }
        let before = scrollView.verticalOffset
        scrollView.scroll(by: speed)
        if scrollView.verticalOffset == before { stopScrolling(); return }   // the end of the wall
        // The wall has moved under the pointer; its new origin arrives with
        // the next layout, so place the pointer by where it will be.
        wallOrigin.y -= scrollView.verticalOffset - before
        recompute()
    }

    private func stopScrolling() {
        scroller?.invalidate()
        scroller = nil
        speed = 0
    }
}

/// The carried card, drawn over the wall under the pointer; the wall shows a
/// plate where it would land. It takes no clicks — the card it stands for,
/// still on the wall, has the drag.
private struct LiftedCard: View {
    @EnvironmentObject var state: AppState
    let doc: DocumentRef
    let drag: WallDrag
    let zoom: Namespace.ID

    var body: some View {
        let dark = state.theme.isDark
        GalleryCard(doc: doc, zoom: zoom, zoomSource: false, lifted: true)
            .frame(width: drag.width)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(drag.settling ? 1 : 1.03)
            .shadow(color: .black.opacity(drag.settling ? 0 : (dark ? 0.5 : 0.2)), radius: 18, y: 10)
            .animation(.easeOut(duration: 0.2), value: drag.settling)
            .offset(x: drag.pointer.x - drag.grab.width, y: drag.pointer.y - drag.grab.height)
            .allowsHitTesting(false)
            .transition(.identity)
    }
}

// MARK: - Card

struct GalleryCard: View {
    @EnvironmentObject var state: AppState
    @Environment(WallDrag.self) private var drag: WallDrag?
    let doc: DocumentRef
    var isSelected: Bool = false
    let zoom: Namespace.ID
    /// How much of the preview to show before it fades; the mosaic uses the default.
    var previewCap: CGFloat = GalleryCard.previewCap
    /// A set height for the plate, whatever the document holds; the corridor uses it.
    var fixedHeight: CGFloat? = nil
    /// Whether this card is the one the page grows out of and shrinks back
    /// into. The Timelapse can show a document twice — under the day it was
    /// made and the day it was last edited — and only one of them can be.
    var zoomSource: Bool = true
    /// This card is being carried: on the wall it stands as the plate the
    /// carried card will land on.
    var carried: Bool = false
    /// This is the carried card itself, riding over the wall.
    var lifted: Bool = false
    /// Whether the card can be picked up and carried into a new place on the
    /// wall; elsewhere a card is only a button.
    var reorderable: Bool = false
    @State private var hovering = false
    @State private var pressed = false

    static let previewCap: CGFloat = 280

    private var theme: Theme { state.theme }
    private var isCurrent: Bool { state.document?.relativePath == doc.id }
    private var starred: Bool { state.settings.isStarred(doc.id) }
    private var lines: [PreviewLine] { MarkdownPreview.lines(for: doc) }
    private var previewSegments: [PreviewSegment] { MarkdownPreview.segments(for: doc, theme: theme) }
    /// Another card is being carried over this one: it keeps still.
    private var wallBusy: Bool { (drag?.active ?? false) && !lifted }
    private var lit: Bool { hovering && !wallBusy }

    static func estimatedHeight(for doc: DocumentRef) -> CGFloat {
        let lines = MarkdownPreview.lines(for: doc)
        let titleLines: CGFloat = doc.title.count > 26 ? 2 : 1
        let body = lines.reduce(CGFloat(0)) { $0 + $1.estimatedHeight }
        return 16 + titleLines * 20 + 10 + min(body, previewCap) + 16
    }

    private var previewOverflows: Bool {
        lines.reduce(CGFloat(0)) { $0 + $1.estimatedHeight } > previewCap
    }

    private var shadowColor: Color {
        if lifted { return .clear }
        if isSelected { return theme.accent.color.opacity(0.25) }
        if lit { return Color.black.opacity(theme.isDark ? 0.22 : 0.08) }
        return .clear
    }

    private var borderColor: Color {
        if isSelected { return theme.accent.color.opacity(0.95) }
        if isCurrent { return theme.accent.color.opacity(0.45) }
        return theme.text.color.opacity(lit ? 0.18 : 0.08)
    }

    private var plateOpacity: Double {
        if lifted { return theme.isDark ? 0.16 : 0.1 }
        if isSelected { return 0.09 }
        if pressed { return 0.1 }
        return lit ? 0.075 : 0.05
    }

    var body: some View {
        Group {
            if reorderable, drag != nil {
                face
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .gesture(carryGesture)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { state.open(doc, fromCard: true) }
            } else {
                Button {
                    state.open(doc, fromCard: true)
                } label: {
                    face.contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .matchedGeometryEffect(id: doc.id, in: zoom, isSource: zoomSource)
        .onHover { hovering = $0 }
        .animation(Motion.quiet(.spring(response: 0.28, dampingFraction: 0.72)), value: lit)
        .animation(Motion.quiet(.easeOut(duration: 0.12)), value: pressed)
        .animation(Motion.quiet(.easeOut(duration: 0.12)), value: isSelected)
        .animation(Motion.quiet(.easeOut(duration: 0.2)), value: state.zoomingCard)
        .animation(Motion.quiet(.easeOut(duration: 0.16)), value: carried)
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: starred)
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
                ForEach(state.moveTargets) { f in
                    Button(f.id.replacingOccurrences(of: "/", with: " / ")) { state.move(doc.id, toFolder: f.id) }
                }
            }
            Button(Shelf.holds(doc.id) ? "Unshelve" : "Shelve") { state.toggleShelved(doc.id) }
            Divider()
            Button("Reveal in Finder") { state.library.revealInFinder(doc.id) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(doc.url.path, forType: .string)
            }
            Divider()
            Button("Move to Trash", role: .destructive) { state.trash(doc.id) }
        }
    }

    /// The card as drawn: title, preview, plate and border. While it stands
    /// for a card being carried it is the plate alone, dashed, where the
    /// card will land.
    private var face: some View {
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
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
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
                // One run of text for the whole preview rather than a view
                // a line: a wall of thirty cards is thirty layouts, not
                // eight hundred. A table is the one block drawn as a view,
                // between the runs on either side of it. The fade at the
                // foot is a mask, and a mask is a layer of its own — so
                // only a preview that overflows gets one.
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(previewSegments.enumerated()), id: \.offset) { _, segment in
                        switch segment {
                        case .text(let run):
                            Text(run).lineSpacing(2)
                        case .table(let table):
                            PreviewTableView(table: table, theme: theme)
                        }
                    }
                }
                .foregroundStyle(theme.text.color.opacity(0.74))
                .frame(maxWidth: .infinity, maxHeight: previewCap, alignment: .topLeading)
                .clipped()
                .modifier(PreviewFade(on: previewOverflows))
            }
        }
        // While the card is flying — growing into the page or shrinking back
        // out of it — it is a plain plate; the words return once it lands.
        .opacity(state.zoomingCard == doc.id || carried ? 0 : 1)
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: fixedHeight, maxHeight: fixedHeight, alignment: .topLeading)
        .background(
            // The shadow is the plate's, not the card's: a shadow on the
            // whole card has every word drawn again into an offscreen
            // image, for every card, on every frame they move.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.text.color.opacity(carried ? 0.03 : plateOpacity))
                .shadow(color: shadowColor, radius: isSelected ? 12 : 10, y: isSelected ? 2 : 4)
        )
        .background(
            // The lifted card is opaque to the wall it crosses: a wash of the
            // window's tint under its plate.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.tint.color.opacity(lifted ? 0.96 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(carried ? theme.accent.color.opacity(0.45) : borderColor,
                              style: StrokeStyle(lineWidth: isSelected ? 2 : (isCurrent ? 1.5 : 1), dash: carried ? [5, 4] : []))
        )
        .offset(y: lit && !isSelected ? -2 : 0)
        .scaleEffect(pressed ? 0.985 : 1)
        .overlay(alignment: .bottomTrailing) {
            if (lit || isSelected) && !carried {
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
    }

    // MARK: - Carrying

    /// Pressed, the card is a button; moved, it lifts and travels with the
    /// pointer while the wall makes room (WallDrag). Points are the scroll
    /// view's, which the pointer can leave without the drag ending.
    private var carryGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(GalleryNavigator.coordinateSpace))
            .onChanged { v in
                let moved = hypot(v.translation.width, v.translation.height)
                if drag?.id != doc.id {
                    if moved < 4 { pressed = true; return }
                    guard let drag, !drag.active, drag.begin(id: doc.id, at: v.startLocation) else { return }
                    pressed = false
                }
                drag?.update(to: v.location)
            }
            .onEnded { v in
                pressed = false
                if let drag, drag.id == doc.id {
                    drag.letGo { order in state.placeOnWall(order) }
                } else if hypot(v.translation.width, v.translation.height) < 4 {
                    state.open(doc, fromCard: true)
                }
            }
    }

    private var caption: String {
        let when = doc.modified.shortRelative
        return doc.folder.isEmpty ? when : "\(doc.folder) · \(when)"
    }
}

// MARK: - Preview rendering

/// A pipe table as a preview shows it: a few columns of a few rows, the
/// header first, each cell one line.
struct PreviewTable {
    enum Alignment { case leading, center, trailing }
    let alignments: [Alignment]
    let header: [AttributedString]
    let rows: [[AttributedString]]
    /// Rows beyond those shown, and columns beyond those shown.
    let moreRows: Int
    let moreColumns: Int
    var columns: Int { alignments.count }
    static let maxColumns = 4
    static let maxRows = 5
    /// About what the grid stands, a row being a line of small type.
    var estimatedHeight: CGFloat { CGFloat(rows.count + 1) * 17 + 6 }
}

struct PreviewLine: Identifiable {
    enum Kind {
        case heading(Int), body, bullet, numbered(String), quote, code, rule, blank, table(PreviewTable)
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
        case .table(let t): return t.estimatedHeight
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

    private static var segmentCache: [String: [PreviewSegment]] = [:]

    /// The preview as runs of text — the lines set in their kinds, one
    /// under the other — for a card to lay out in one go, with any table
    /// between the runs as a block of its own, since a run of text cannot
    /// draw a grid. Most previews are one run. Cached with the lines, per
    /// theme.
    static func segments(for doc: DocumentRef, theme: Theme) -> [PreviewSegment] {
        let lines = lines(for: doc)
        guard !lines.isEmpty else { return [] }
        let key = "\(doc.id)|\(doc.modified.timeIntervalSince1970)|\(doc.size)|\(theme.accent.hex)|\((theme.heading ?? theme.text).hex)|\(theme.text.hex)"
        if let hit = segmentCache[key] { return hit }
        var result: [PreviewSegment] = []
        var run: [PreviewLine] = []
        func flush() {
            // A blank at either end of a run is the table's own margin.
            var kept = run
            while let last = kept.last, case .blank = last.kind { kept.removeLast() }
            while let first = kept.first, case .blank = first.kind { kept.removeFirst() }
            if !kept.isEmpty { result.append(.text(attributed(kept, theme: theme))) }
            run = []
        }
        for line in lines {
            if case .table(let table) = line.kind {
                flush()
                result.append(.table(table))
            } else {
                run.append(line)
            }
        }
        flush()
        if segmentCache.count > 600 { segmentCache.removeAll() }
        segmentCache[key] = result
        return result
    }

    /// A line of the preview cut to about what its view used to show — two
    /// or three wrapped lines of forty-six characters — with an ellipsis.
    private static func clipped(_ text: AttributedString, lines: Int, width: Int = 46) -> AttributedString {
        let cap = lines * width
        let chars = text.characters
        guard chars.count > cap else { return text }
        let end = chars.index(chars.startIndex, offsetBy: cap - 1)
        var cut = AttributedString(text[text.startIndex..<end])
        cut.append(AttributedString("…"))
        return cut
    }

    static func attributed(_ lines: [PreviewLine], theme: Theme) -> AttributedString {
        var out = AttributedString()
        let body = Font.system(size: 10.5)
        let accent = theme.accent.color
        var first = true
        for line in lines {
            if !first { out.append(AttributedString("\n")) }
            first = false
            switch line.kind {
            case .blank:
                var gap = AttributedString(" ")
                gap.font = .system(size: 3)
                out.append(gap)
            case .rule:
                var rule = AttributedString("―――")
                rule.font = .system(size: 8)
                rule.foregroundColor = theme.text.color.opacity(0.3)
                out.append(rule)
            case .heading(let level):
                var t = clipped(line.text, lines: 2, width: 40)
                t.font = .system(size: level == 1 ? 12.5 : (level == 2 ? 11.5 : 11), weight: .semibold)
                t.foregroundColor = theme.headingColor.asColor.opacity(0.95)
                out.append(t)
            case .bullet:
                var dot = AttributedString("•  ")
                dot.font = body
                dot.foregroundColor = accent
                out.append(dot)
                var t = clipped(line.text, lines: 2)
                t.font = body
                out.append(t)
            case .numbered(let n):
                var num = AttributedString(n + " ")
                num.font = body.monospacedDigit()
                num.foregroundColor = accent
                out.append(num)
                var t = clipped(line.text, lines: 2)
                t.font = body
                out.append(t)
            case .quote:
                var bar = AttributedString("▏ ")
                bar.font = body
                bar.foregroundColor = accent.opacity(0.6)
                out.append(bar)
                var t = clipped(line.text, lines: 2)
                t.font = body.italic()
                t.foregroundColor = theme.text.color.opacity(0.6)
                out.append(t)
            case .code:
                var t = clipped(line.text, lines: 1, width: 56)
                t.font = .system(size: 9.5, design: .monospaced)
                t.foregroundColor = theme.text.color.opacity(0.63)
                out.append(t)
            case .body:
                var t = clipped(line.text, lines: 3)
                t.font = body
                out.append(t)
            case .table:
                // Drawn as a block of its own (segments); never in a run.
                break
            }
        }
        return out
    }

    private static let tableSeparator = try! NSRegularExpression(pattern: "^[ \\t]*\\|?[ \\t]*:?[-\u{2013}\u{2014}]+:?[ \\t]*(\\|[ \\t]*:?[-\u{2013}\u{2014}]+:?[ \\t]*)*\\|?[ \\t]*$")

    /// The cells of a row, with the outer pipes off and each cell's spaces trimmed.
    private static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.replacingOccurrences(of: "\\|", with: "\u{0}").components(separatedBy: "|")
            .map { $0.replacingOccurrences(of: "\u{0}", with: "|").trimmingCharacters(in: .whitespaces) }
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

        let all = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < all.count {
            if out.count >= limit { break }
            let line = all[i]
            i += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // A pipe table: a row, a separator under it, rows after it; a few
            // of its columns and rows, the rest counted.
            if !inFence, trimmed.contains("|"), i < all.count, match(tableSeparator, all[i]) != nil, all[i].contains(where: { $0 == "-" || $0 == "\u{2013}" || $0 == "\u{2014}" }) {
                let header = cells(line)
                let aligns = cells(all[i]).map { c -> PreviewTable.Alignment in
                    c.hasPrefix(":") && c.hasSuffix(":") ? .center : c.hasSuffix(":") ? .trailing : .leading
                }
                i += 1
                var rows: [[String]] = []
                while i < all.count, all[i].contains("|"), !all[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells(all[i]))
                    i += 1
                }
                let columns = max(header.count, aligns.count)
                let shown = min(columns, PreviewTable.maxColumns)
                func fit(_ r: [String]) -> [AttributedString] {
                    (0..<shown).map { c in inline(c < r.count ? r[c] : "") }
                }
                var alignments = (0..<shown).map { c in c < aligns.count ? aligns[c] : .leading }
                if alignments.count < shown { alignments += Array(repeating: .leading, count: shown - alignments.count) }
                let table = PreviewTable(alignments: alignments, header: fit(header),
                                         rows: rows.prefix(PreviewTable.maxRows).map(fit),
                                         moreRows: max(0, rows.count - PreviewTable.maxRows), moreColumns: columns - shown)
                if !skippedTitle { skippedTitle = true }
                out.append(PreviewLine(id: out.count, kind: .table(table), text: AttributedString()))
                lastWasBlank = false
                continue
            }

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
            // The first real line usually is the title (Glassine names files
            // from it); don't repeat it. The file's name is the line with
            // what a name cannot hold taken out — a `?`, a `/`, a `:` — so
            // the line is compared as the name it would have made.
            if !skippedTitle {
                skippedTitle = true
                let first = line.derivedMarkdownTitle
                if first.lowercased() == normalizedTitle || first.sanitizedFileStem.lowercased() == normalizedTitle { continue }
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

/// The fade at the foot of a preview that has more to it than the card shows.
private struct PreviewFade: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content.mask(
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.70), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
        } else {
            content
        }
    }
}

/// A run of a preview's text, or a table between runs.
enum PreviewSegment {
    case text(AttributedString)
    case table(PreviewTable)
}

/// A pipe table in little: a grid of small type, a line under the header
/// and between the rows, a line between the columns, the header on a faint
/// fill — the editor's table at a tenth of the size. Each cell is one line,
/// cut short with an ellipsis; a note at the foot counts what is left out.
struct PreviewTableView: View {
    let table: PreviewTable
    let theme: Theme

    private var line: Color { theme.text.color.opacity(theme.isDark ? 0.18 : 0.14) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { c, text in
                        cell(text, column: c, header: true)
                    }
                }
                .background(theme.text.color.opacity(theme.isDark ? 0.06 : 0.045))
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    Rectangle().fill(line).frame(height: 0.5)
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { c, text in
                            cell(text, column: c, header: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(line, lineWidth: 0.5))
            if table.moreRows > 0 || table.moreColumns > 0 {
                Text(more)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.text.color.opacity(0.4))
            }
        }
        .padding(.vertical, 2)
    }

    private var more: String {
        var parts: [String] = []
        if table.moreRows > 0 { parts.append("\(table.moreRows) more row\(table.moreRows == 1 ? "" : "s")") }
        if table.moreColumns > 0 { parts.append("\(table.moreColumns) more column\(table.moreColumns == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func cell(_ text: AttributedString, column: Int, header: Bool) -> some View {
        let align: Alignment = {
            switch table.alignments[min(column, table.alignments.count - 1)] {
            case .leading: return .leading
            case .center: return .center
            case .trailing: return .trailing
            }
        }()
        return Text(text)
            .font(.system(size: 9.5, weight: header ? .semibold : .regular))
            .foregroundStyle(header ? theme.headingColor.asColor.opacity(0.95) : theme.text.color.opacity(0.78))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .frame(maxWidth: .infinity, alignment: align)
            .overlay(alignment: .leading) {
                if column > 0 { Rectangle().fill(line).frame(width: 0.5) }
            }
    }
}

/// One line of a preview as a view of its own — the fanned pages still draw
/// theirs this way; the wall sets a card's lines as runs of text.
struct PreviewLineView: View {
    let line: PreviewLine
    let theme: Theme

    var body: some View {
        switch line.kind {
        case .table(let table):
            PreviewTableView(table: table, theme: theme)
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

// MARK: - Card entrance

/// Cards arrive in a soft cascade, each a beat after the one above it, when
/// the wall first shows; a card built later — scrolled to — is simply there.
/// The card a page is shrinking back into skips the cascade — it is already
/// on its way.
private struct CardEntrance: ViewModifier {
    @EnvironmentObject var state: AppState
    let id: String
    let row: Int
    let cascade: Bool
    @State private var shown = false

    private var immediate: Bool {
        !cascade || state.zoomingCard == id || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            // The animation stays with the card: a global withAnimation with a
            // delay can outlive a mosaic that is removed before the delay is up
            // and leave it half-faded on screen.
            .animation(immediate ? nil : .easeOut(duration: 0.32).delay(min(0.24, Double(row) * 0.04)), value: shown)
            .onAppear {
                guard !shown else { return }
                if immediate { shown = true } else { DispatchQueue.main.async { shown = true } }
            }
    }
}
