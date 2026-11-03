import AppKit
import SwiftUI

/// The Timelapse, drawn the way Vantage draws a day: today lies flat and
/// readable at the front, and earlier days recede up the corridor — tilted
/// back, smaller, fainter — toward a vanishing point. Scrolling walks the
/// corridor, ↑ and ↓ a day at a time; a click opens a day, ↩ opens the one in
/// front; Esc goes to All Documents, whose Esc comes back here.
///
/// Two scopes, a ⇥ apart: the daily notes alone, one a day — or everything,
/// where each day holds every document written or last edited then, the
/// day's note first, in a row that recedes with the rest. A day's name is a
/// way into its wall: every document of that day as cards (the calendar in
/// the sidebar opens the same wall).
struct DailyTimelineView: View {
    @EnvironmentObject var state: AppState
    /// Shared with the editor so an opened card can grow into the page.
    let zoom: Namespace.ID
    @StateObject private var walker = TimelineWalker()

    private var theme: Theme { state.theme }
    private var scope: TimelapseScope { state.settings.data.timelapseScope }

    /// Every day is the same size in the corridor, whatever it holds: this much
    /// preview, on a plate this tall.
    static let previewCap: CGFloat = 130
    static let cardHeight: CGFloat = 200
    /// The label above a card and the space under it, part of what tilts.
    static let labelBand: CGFloat = 24
    /// Where the fade on a day behind another ends, as a fraction of its plate.
    static let fadeSolidUntil = 0.42
    static let fadeClearAt = 0.62
    /// How many of a day's documents stand in its row; the rest are a count.
    static let rowCap = 4

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    /// One day of the corridor: its note, and — in the Everything scope —
    /// what else was written that day.
    struct Day: Identifiable {
        let key: Int
        let date: Date
        let note: DocumentRef?
        let others: [DocumentRef]
        var id: Int { key }
        var isToday: Bool { Calendar.current.isDateInToday(date) }
        /// Which card is the source of the open-zoom: a document shows under
        /// the day it was last edited and, if different, the day it was made;
        /// only one of the two can grow into the page. A day's note is the
        /// source under its day, and shows nowhere else.
        func zoomSource(_ doc: DocumentRef) -> Bool { note?.id == doc.id || DailyNotes.dayKey(doc.modified) == key }
    }

    /// The days, today first — always today, even with nothing written yet,
    /// so the corridor starts where the writer stands.
    private var days: [Day] {
        let notes = state.dailyNotesByDay
        var keys = Set(notes.keys)
        let byDay = scope == .everything ? state.documentsByDay : [:]
        if scope == .everything { keys.formUnion(byDay.keys) }
        let today = DailyNotes.dayKey(Date())
        keys.insert(today)
        // A day's note stands under its own day and nowhere else: a note
        // begun the morning after shows under its day, not under the day it
        // was written — and never twice, since two cards of one document
        // both claiming to be the source of the open-zoom left the second a
        // sliver of a plate.
        let noteIDs = Set(notes.values.map(\.id))
        return keys.sorted(by: >).compactMap { key in
            let note = notes[key]
            let others = scope == .everything ? (byDay[key] ?? []).filter { !noteIDs.contains($0.id) } : []
            // A day with nothing left on it — the morning a note was begun
            // for the day before, and nothing else — is no day of the corridor.
            guard note != nil || !others.isEmpty || key == today else { return nil }
            return Day(key: key, date: key == today ? Date() : AppState.date(forDayKey: key), note: note, others: others)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let items = days
            let written = items.filter { $0.note != nil || !$0.others.isEmpty }.count

            ZStack(alignment: .topLeading) {
                // The ground of the corridor carries the window.
                Color.clear.dragsWindowByGround()

                corridor(items: items, size: geo.size)
                    // The far days dissolve before they reach the header, so
                    // nothing of the corridor is drawn through its words.
                    .mask(
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 72)
                            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 56)
                            Color.black
                        }
                        .ignoresSafeArea()
                    )

                header(count: written)
                    .padding(.leading, 28)
                    .padding(.top, 52)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onAppear {
                walker.maxDepth = Double(max(0, items.count - 1))
                walker.offset = 0
                walker.openFront = { openFront(items) }
                walker.toggleScope = { toggleScope() }
                walker.install()
            }
            .onChange(of: items.count) { _, n in
                walker.maxDepth = Double(max(0, n - 1))
                walker.openFront = { openFront(items) }
            }
            .onChange(of: scope) { _, _ in
                // The days change under the walker; stand at the front again.
                withAnimation(Motion.quiet(.spring(response: 0.36, dampingFraction: 0.84))) { walker.offset = 0 }
            }
            .onDisappear { walker.uninstall() }
        }
        .foregroundStyle(theme.text.color)
        .background(
            // Esc: All Documents. Esc there comes back here.
            Button("") { state.escapeFromTimelapse() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
        )
    }

    private func toggleScope() {
        withAnimation(Motion.quiet(.spring(response: 0.36, dampingFraction: 0.84))) {
            state.settings.data.timelapseScope = scope == .notes ? .everything : .notes
        }
    }

    /// ↩: the day in front — its note; failing that its one document; failing
    /// that, its wall. A day with nothing yet starts its note.
    private func openFront(_ items: [Day]) {
        let i = walker.frontIndex
        guard i >= 0, i < items.count else { return }
        let day = items[i]
        if let note = day.note { state.open(note, fromCard: true); return }
        if day.others.count == 1, scope == .everything { state.open(day.others[0], fromCard: true); return }
        if day.others.isEmpty { state.openNote(for: day.date); return }
        state.showDay(day.date)
    }

    // MARK: - The corridor

    private func corridor(items: [Day], size: CGSize) -> some View {
        // One note a day stands at reading width; a day's row of documents
        // takes most of the window.
        let width: CGFloat = scope == .everything ? min(940, size.width - 120) : min(470, size.width - 120)
        // Today's card starts at the middle of the window and reaches into the
        // lower half; the days before it climb the upper half toward the top.
        let frontY = size.height / 2 + 90
        // Each day sits a fifth of its own height clear of the one in front of it,
        // whatever the window's height; the corridor rises from the front card.
        let rises = DailyTimelineView.rises(count: 12)

        return ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, day in
                let depth = Double(i) - walker.offset
                slot(depth: depth, width: width, frontY: frontY, rises: rises,
                     centerX: size.width / 2,
                     label: label(for: day.date),
                     labelColor: depth < 0.5 ? theme.accent.color : theme.text.color.opacity(0.5),
                     day: day) {
                    dayContent(day, width: width)
                }
            }

            if items.count == 1, items[0].note == nil, items[0].others.isEmpty {
                Text(scope == .notes
                     ? "Daily notes collect here — today in front, earlier days up the corridor."
                     : "Every day you write collects here — today in front, earlier days up the corridor.")
                    .font(.system(size: 12))
                    .opacity(0.45)
                    .position(x: size.width / 2, y: frontY - 180)
            }
        }
    }

    /// What stands in a day's slot: its note — or, in the Everything scope,
    /// its documents in a row, the note first, up to four and then a count
    /// that opens the day's wall. Today without a note starts with the way
    /// to begin one.
    @ViewBuilder
    private func dayContent(_ day: Day, width: CGFloat) -> some View {
        if scope == .notes {
            if let note = day.note {
                GalleryCard(doc: note, zoom: zoom, previewCap: DailyTimelineView.previewCap, fixedHeight: DailyTimelineView.cardHeight)
            } else {
                startCard(for: day, width: width)
            }
        } else {
            let docs = (day.note.map { [$0] } ?? []) + day.others
            let shown = Array(docs.prefix(DailyTimelineView.rowCap))
            let more = docs.count - shown.count
            let starts = day.note == nil && day.isToday
            let slots = shown.count + (starts ? 1 : 0) + (more > 0 ? 1 : 0)
            let gap: CGFloat = 14
            let moreWidth: CGFloat = 74
            let cardWidth = min(470, (width - gap * CGFloat(max(0, slots - 1)) - (more > 0 ? moreWidth : 0)) / CGFloat(max(1, slots - (more > 0 ? 1 : 0))))
            HStack(alignment: .top, spacing: gap) {
                if starts {
                    startCard(for: day, width: cardWidth)
                }
                ForEach(shown) { doc in
                    GalleryCard(doc: doc, zoom: zoom, previewCap: DailyTimelineView.previewCap,
                                fixedHeight: DailyTimelineView.cardHeight, zoomSource: day.zoomSource(doc))
                        .frame(width: cardWidth)
                }
                if more > 0 {
                    moreCard(count: more, for: day)
                        .frame(width: moreWidth, height: DailyTimelineView.cardHeight)
                }
            }
            .frame(width: width, alignment: slots <= 1 ? .center : .leading)
        }
    }

    // MARK: Geometry

    static func scale(at depth: Double) -> Double { pow(0.84, max(-0.6, depth)) }
    static func tilt(at depth: Double) -> Double { max(0, min(54, 10 + depth * 10)) }

    /// Half the height a day takes on screen at a depth: its plate and label,
    /// scaled and foreshortened by the tilt.
    static func projectedHalf(at depth: Double) -> CGFloat {
        (cardHeight + labelBand) / 2 * scale(at: depth) * cos(tilt(at: depth) * .pi / 180)
    }

    /// How far above the front day's centre each whole depth sits. A day's
    /// visible foot — where its fade reaches nothing — clears the top of the day
    /// in front by a fifth of its own height, so the corridor reads as a stack
    /// of cards with air between them rather than a spread across the window.
    static func rises(count: Int) -> [CGFloat] {
        // Where the fade ends, as a fraction of the whole tilting block (label included).
        let foot = (labelBand + fadeClearAt * cardHeight) / (cardHeight + labelBand)
        var rises: [CGFloat] = [0]
        var previousHalf = projectedHalf(at: 0)
        for d in 1..<count {
            let half = projectedHalf(at: Double(d))
            let gap = max(8, 0.2 * 2 * half)
            rises.append(rises[d - 1] + previousHalf + gap + (2 * foot - 1) * half)
            previousHalf = half
        }
        return rises
    }

    /// The rise at a continuous depth: between whole depths, on the way from one
    /// to the next; in front of the front day, sliding down and out.
    static func rise(at depth: Double, rises: [CGFloat]) -> CGFloat {
        if depth <= 0 { return CGFloat(depth) * (2 * projectedHalf(at: 0) + 24) }
        let lower = min(rises.count - 2, Int(depth.rounded(.down)))
        let t = CGFloat(depth - Double(lower))
        return rises[lower] + (rises[lower + 1] - rises[lower]) * min(1, t)
    }

    /// Places one day at its continuous depth. Depth 0 is the front; positive is
    /// further up the corridor; between -1 and 0 the card is sliding past the
    /// camera (scrolled beyond it) and fades out below.
    @ViewBuilder
    private func slot(depth: Double, width: CGFloat, frontY: CGFloat, rises: [CGFloat],
                      centerX: CGFloat, label: String, labelColor: Color, day: Day,
                      @ViewBuilder content: () -> some View) -> some View {
        // A day that has climbed up under the header is gone; one on its way there fades.
        let travel = DailyTimelineView.rise(at: depth, rises: rises)
        let headroom = min(1, max(0, (frontY - travel - 84) / 40))
        if depth > -1, depth < 8.5, headroom > 0 {
            let scale = DailyTimelineView.scale(at: depth)
            let tilt = DailyTimelineView.tilt(at: depth)
            let fade = (depth < 0 ? max(0, 1 + depth) : max(0.12, 1 - depth * 0.13)) * headroom
            // A day behind another dissolves before it reaches the one in front:
            // its lower part fades to nothing, so no two days touch. The front
            // day is whole; a day sliding back picks up the fade as it goes.
            let haze = min(1, max(0, depth))
            let solidUntil = DailyTimelineView.fadeSolidUntil + (1 - DailyTimelineView.fadeSolidUntil) * (1 - haze)
            let clearAt = DailyTimelineView.fadeClearAt + (1 - DailyTimelineView.fadeClearAt) * (1 - haze)

            VStack(alignment: .leading, spacing: 7) {
                DayLabel(text: label, count: scope == .everything ? day.others.count + (day.note == nil ? 0 : 1) : 0,
                         color: labelColor, theme: theme) {
                    state.showDay(day.date)
                }
                .padding(.leading, 4)
                content()
                    // Its own height, not the corridor's: a short day is a short card.
                    .fixedSize(horizontal: false, vertical: true)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: solidUntil),
                                .init(color: .clear, location: clearAt),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            .frame(width: width)
            .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.62)
            .scaleEffect(scale)
            .position(x: centerX, y: frontY - travel)
            .opacity(fade)
            .zIndex(100 - depth)
        }
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Timelapse")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .opacity(0.4)
                    .contentTransition(.numericText())
            }
            PillPicker(theme: theme, selection: Binding(
                get: { scope },
                set: { s in withAnimation(Motion.quiet(.spring(response: 0.36, dampingFraction: 0.84))) { state.settings.data.timelapseScope = s } }),
                options: TimelapseScope.allCases, label: { $0.label })
                .padding(.leading, 6)
                .help("What each day holds: its note alone, or everything written that day (⇥ switches).")
            Text(scope == .notes ? "↑ walks back · ⇥ everything" : "↑ walks back · ⇥ notes alone")
                .font(.system(size: 11))
                .opacity(0.3)
                .padding(.leading, 4)
                .contentTransition(.opacity)
        }
        .animation(.easeOut(duration: 0.2), value: count)
    }

    /// The way into a day without a note: today's, or the day's.
    private func startCard(for day: Day, width: CGFloat) -> some View {
        Button {
            state.openNote(for: day.date)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent.color)
                Text(day.isToday ? "Start today's note" : "Start the day's note")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if day.isToday {
                    Text("⌘D")
                        .font(.system(size: 11))
                        .opacity(0.35)
                }
            }
            .padding(.horizontal, 16)
            .frame(width: width, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.text.color.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme.accent.color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// "+3": the documents a row has no room for, and the way to the day's wall.
    private func moreCard(count: Int, for day: Day) -> some View {
        Button {
            state.showDay(day.date)
        } label: {
            VStack(spacing: 4) {
                Text("+\(count)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.headingColor.asColor)
                Text("more")
                    .font(.system(size: 10.5))
                    .opacity(0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.text.color.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme.text.color.opacity(0.08), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Every document of this day, as a wall")
    }

    private func label(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "TODAY" }
        if cal.isDateInYesterday(date) { return "YESTERDAY" }
        return DailyTimelineView.shortFormatter.string(from: date).uppercased()
    }
}

/// A day's name above its slot: a button into the day's wall, with how many
/// documents the day holds when there is more than the note.
private struct DayLabel: View {
    let text: String
    let count: Int
    let color: Color
    let theme: Theme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.6)
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .opacity(hovering ? 0.7 : 0)
                    .offset(x: hovering ? 0 : -3)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.text.color.opacity(hovering ? 0.08 : 0)))
            .padding(.horizontal, -6)
            .padding(.vertical, -3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
        .help("This day's wall: every document written then")
    }
}

/// Turns the scroll wheel into movement along the corridor: scrolling up walks
/// into the past, scrolling down comes back, and lifting off settles on a day.
/// ↑ and ↓ walk a day at a time; ↩ opens the day in front.
final class TimelineWalker: ObservableObject {
    @Published var offset: Double = 0
    var maxDepth: Double = 0
    private var monitor: Any?
    private var keyMonitor: Any?
    /// What ↩ does: open whatever stands at the front of the corridor.
    var openFront: (() -> Void)?
    /// What ⇥ does: show every document of each day, or the daily notes alone.
    var toggleScope: (() -> Void)?
    /// The corridor on screen, for a self-shot to walk.
    static weak var current: TimelineWalker?

    /// The whole day nearest the front — what ↩ opens, what the keys step from.
    var frontIndex: Int { Int(offset.rounded()) }

    /// One day further back (or forward, negative), settling the way a scroll does.
    func walk(by days: Double) {
        withAnimation(Motion.quiet(.spring(response: 0.32, dampingFraction: 0.82))) {
            offset = min(maxDepth, max(0, (offset + days).rounded()))
        }
    }

    func install() {
        uninstall()
        TimelineWalker.current = self
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = event.window, AppDelegate.isMainWindow(window),
                  // A card over the corridor — Settings, say — scrolls itself.
                  !AppState.shared.overlayUp else { return event }
            let step = Double(event.scrollingDeltaY) / 140
            let target = min(self.maxDepth, max(0, self.offset + step))
            if event.phase == .ended || event.momentumPhase == .ended {
                withAnimation(Motion.quiet(.spring(response: 0.32, dampingFraction: 0.82))) {
                    self.offset = min(self.maxDepth, max(0, target.rounded()))
                }
            } else if event.phase == .cancelled {
                withAnimation(Motion.quiet(.spring(response: 0.32, dampingFraction: 0.82))) {
                    self.offset = min(self.maxDepth, max(0, self.offset.rounded()))
                }
            } else {
                self.offset = target
            }
            return nil
        }
        // ↑ walks into the past, ↓ comes back — the way the scroll wheel goes —
        // ↩ opens the day in front, ⇥ switches what the days show.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = event.window, AppDelegate.isMainWindow(window),
                  AppState.shared.showingDaily, !AppState.shared.overlayUp else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
            guard flags.isEmpty else { return event }
            switch event.keyCode {
            case 126: self.walk(by: 1); return nil      // ↑
            case 125: self.walk(by: -1); return nil     // ↓
            case 36, 76: self.openFront?(); return nil  // ↩
            case 48: self.toggleScope?(); return nil    // ⇥
            default: return event
            }
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        monitor = nil
        keyMonitor = nil
    }

    deinit { uninstall() }
}
