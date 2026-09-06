import AppKit
import SwiftUI

/// The Daily section, drawn the way Vantage draws a day: today's note lies flat
/// and readable at the front, and earlier days recede up the corridor — tilted
/// back, smaller, fainter — toward a vanishing point. Scrolling walks the
/// corridor; a click opens a day; Esc goes back.
struct DailyTimelineView: View {
    @EnvironmentObject var state: AppState
    /// Shared with the editor so an opened card can grow into the page.
    let zoom: Namespace.ID
    @StateObject private var walker = TimelineWalker()

    private var theme: Theme { state.theme }

    /// Every day is the same size in the corridor, whatever it holds: this much
    /// preview, on a plate this tall.
    static let previewCap: CGFloat = 130
    static let cardHeight: CGFloat = 200
    /// The label above a card and the space under it, part of what tilts.
    static let labelBand: CGFloat = 24
    /// Where the fade on a day behind another ends, as a fraction of its plate.
    static let fadeSolidUntil = 0.42
    static let fadeClearAt = 0.62

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    /// Only the notes named for a day. Anything else that lands in the Daily
    /// folder stays in the sidebar and out of the corridor.
    private var notes: [(doc: DocumentRef, date: Date)] {
        state.library.allDocuments
            .filter { $0.folder == DailyNotes.folder }
            .compactMap { doc in DailyNotes.date(fromTitle: doc.title).map { (doc, $0) } }
            .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        GeometryReader { geo in
            let items = notes
            let hasToday = items.first.map { Calendar.current.isDateInToday($0.1) } ?? false
            let slotCount = items.count + (hasToday ? 0 : 1)

            ZStack(alignment: .topLeading) {
                corridor(items: items, hasToday: hasToday, size: geo.size)

                header(count: items.count)
                    .padding(.leading, 28)
                    .padding(.top, 52)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onAppear {
                walker.maxDepth = Double(max(0, slotCount - 1))
                walker.offset = 0
                walker.install()
            }
            .onChange(of: slotCount) { _, n in walker.maxDepth = Double(max(0, n - 1)) }
            .onDisappear { walker.uninstall() }
        }
        .foregroundStyle(theme.text.color)
        .background(
            // Esc steps back to wherever you were.
            Button("") { state.showingDaily = false }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
        )
    }

    // MARK: - The corridor

    private func corridor(items: [(doc: DocumentRef, date: Date)], hasToday: Bool, size: CGSize) -> some View {
        let width: CGFloat = min(470, size.width - 120)
        let frontY = size.height - 200
        // Each day sits a fifth of its own height clear of the one in front of it,
        // whatever the window's height; the corridor rises from the front card.
        let rises = DailyTimelineView.rises(count: 12)

        return ZStack {
            if !hasToday {
                slot(depth: 0 - walker.offset, width: width, frontY: frontY, rises: rises,
                     centerX: size.width / 2, label: "TODAY", labelColor: theme.accent.color) {
                    startTodayCard(width: width)
                }
            }
            ForEach(Array(items.enumerated()), id: \.element.doc.id) { i, item in
                let depth = Double(i + (hasToday ? 0 : 1)) - walker.offset
                slot(depth: depth, width: width, frontY: frontY, rises: rises,
                     centerX: size.width / 2,
                     label: label(for: item.date),
                     labelColor: depth < 0.5 ? theme.accent.color : theme.text.color.opacity(0.5)) {
                    GalleryCard(doc: item.doc, zoom: zoom, previewCap: DailyTimelineView.previewCap, fixedHeight: DailyTimelineView.cardHeight)
                }
            }

            if items.isEmpty {
                Text("Daily notes collect here — today in front, earlier days up the corridor.")
                    .font(.system(size: 12))
                    .opacity(0.45)
                    .position(x: size.width / 2, y: frontY - 190)
            }
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
                      centerX: CGFloat, label: String, labelColor: Color,
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
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(labelColor)
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
            }
            Text("scroll to walk back")
                .font(.system(size: 11))
                .opacity(0.3)
                .padding(.leading, 4)
        }
    }

    private func startTodayCard(width: CGFloat) -> some View {
        Button {
            state.openTodaysNote()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent.color)
                Text("Start today's note")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("⌥⌘D")
                    .font(.system(size: 11))
                    .opacity(0.35)
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

    private func label(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "TODAY" }
        if cal.isDateInYesterday(date) { return "YESTERDAY" }
        return DailyTimelineView.shortFormatter.string(from: date).uppercased()
    }
}

/// Turns the scroll wheel into movement along the corridor: scrolling up walks
/// into the past, scrolling down comes back, and lifting off settles on a day.
final class TimelineWalker: ObservableObject {
    @Published var offset: Double = 0
    var maxDepth: Double = 0
    private var monitor: Any?

    func install() {
        uninstall()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = event.window, AppDelegate.isMainWindow(window) else { return event }
            let step = Double(event.scrollingDeltaY) / 140
            let target = min(self.maxDepth, max(0, self.offset + step))
            if event.phase == .ended || event.momentumPhase == .ended {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    self.offset = min(self.maxDepth, max(0, target.rounded()))
                }
            } else if event.phase == .cancelled {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    self.offset = min(self.maxDepth, max(0, self.offset.rounded()))
                }
            } else {
                self.offset = target
            }
            return nil
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { uninstall() }
}
