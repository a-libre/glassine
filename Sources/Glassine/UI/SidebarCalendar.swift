import SwiftUI

/// The month, under the sidebar's top three rows: a cell for every day, shaded
/// by how much of that day's note there is — the daily notes the Timelapse
/// shows, and nothing else. A heavy day is full accent; a few lines are a
/// tint; a day without a note is bare. Today is ringed. The note being
/// written is counted as it is typed, so today's cell deepens under the
/// writing. Click a day to open its note, or to start it; ‹ and › turn the
/// month, and *today* comes back to this one.
///
/// The shading is against your own habit, not the month's biggest day: a
/// day is full once it reaches your usual heavy day (the 85th percentile
/// of your notes, and never less than 150 words), so a month of short notes
/// does not read as a month of great ones, and a single long day does not
/// flatten the rest.
struct SidebarCalendar: View {
    @EnvironmentObject var state: AppState
    /// Months from this one; 0 is the month we are in.
    @State private var turn = 0
    /// Which way the last turn went, for the slide.
    @State private var direction = 1

    private var theme: Theme { state.theme }
    private static let calendar = Calendar.current

    /// A cell is never wider than this; the grid centres in a wider sidebar.
    static let cellCap: CGFloat = 27
    static let gap: CGFloat = 3

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f
    }()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private var collapsed: Binding<Bool> {
        Binding(get: { !state.settings.data.calendarCollapsed },
                set: { state.settings.data.calendarCollapsed = !$0 })
    }

    private var month: Date {
        let now = Date()
        let start = Self.calendar.date(from: Self.calendar.dateComponents([.year, .month], from: now)) ?? now
        return Self.calendar.date(byAdding: .month, value: turn, to: start) ?? start
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: Self.monthFormatter.string(from: month), expanded: collapsed, trailing: {
                AnyView(HStack(spacing: 0) {
                    if turn != 0 {
                        Button {
                            go(to: 0)
                        } label: {
                            Text("today")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(theme.accent.color)
                                .padding(.horizontal, 5)
                                .frame(height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                    SidebarIconButton(systemName: "chevron.left", help: "Previous month") { go(to: turn - 1) }
                    SidebarIconButton(systemName: "chevron.right", help: "Next month") { go(to: turn + 1) }
                })
            })
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: turn == 0)
            if !state.settings.data.calendarCollapsed {
                monthView
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
    }

    private func go(to n: Int) {
        direction = n >= turn ? 1 : -1
        withAnimation(GlassineTextView.reduceMotion ? nil : .easeOut(duration: 0.22)) { turn = n }
    }

    // MARK: - The month

    /// The open document, when it is a day's note: its words are counted as
    /// they are typed, ahead of the scan.
    private var openDailyNote: (doc: DocumentModel, day: Int)? {
        guard let doc = state.document, DailyNotes.isDailyNote(relativePath: doc.relativePath),
              let date = DailyNotes.date(fromTitle: doc.title) else { return nil }
        return (doc, DailyNotes.dayKey(date))
    }

    @ViewBuilder
    private var monthView: some View {
        if let live = openDailyNote {
            LiveWords(doc: live.doc) { words in
                grid(liveDay: live.day, liveWords: words)
            }
        } else {
            grid(liveDay: nil, liveWords: 0)
        }
    }

    private func grid(liveDay: Int?, liveWords: Int) -> some View {
        let notes = state.dailyNotesByDay
        let reference = Self.reference(notes, liveDay: liveDay, liveWords: liveWords)
        let today = DailyNotes.dayKey(Date())
        let (cells, rows) = monthCells()
        return VStack(spacing: Self.gap) {
            weekdayRow
            ZStack(alignment: .top) {
                VStack(spacing: Self.gap) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: Self.gap) {
                            ForEach(0..<7, id: \.self) { col in
                                if let cell = cells[row * 7 + col] {
                                    let (day, date) = cell
                                    let key = DailyNotes.dayKey(date)
                                    let words = key == liveDay ? liveWords : (notes[key]?.words ?? 0)
                                    let hasNote = key == liveDay || notes[key] != nil
                                    DayCell(day: day, words: words, hasNote: hasNote,
                                            intensity: hasNote ? Self.intensity(words, reference: reference) : 0,
                                            isToday: key == today, isOpen: key == liveDay, isFuture: key > today,
                                            title: Self.dayFormatter.string(from: date), theme: theme) {
                                        state.openNote(for: date)
                                    }
                                } else {
                                    Color.clear
                                        .frame(maxWidth: .infinity)
                                        .aspectRatio(1, contentMode: .fit)
                                }
                            }
                        }
                    }
                }
                .id(turn)
                .transition(.asymmetric(
                    insertion: .offset(x: 18 * CGFloat(direction)).combined(with: .opacity),
                    removal: .offset(x: -18 * CGFloat(direction)).combined(with: .opacity)))
            }
        }
        .frame(maxWidth: Self.cellCap * 7 + Self.gap * 6)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var weekdayRow: some View {
        let symbols = Self.calendar.veryShortStandaloneWeekdaySymbols
        let first = Self.calendar.firstWeekday - 1
        return HStack(spacing: Self.gap) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(first + i) % 7])
                    .font(.system(size: 9.5, weight: .medium))
                    .opacity(0.35)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The month's weeks of cells — as many rows as it needs — nil where the
    /// month is not, else the day of the month and its date.
    private func monthCells() -> (cells: [(Int, Date)?], rows: Int) {
        let cal = Self.calendar
        let start = month
        let count = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        let rows = (lead + count + 6) / 7
        var cells: [(Int, Date)?] = Array(repeating: nil, count: rows * 7)
        for day in 1...count {
            if let date = cal.date(byAdding: .day, value: day - 1, to: start) {
                cells[lead + day - 1] = (day, date)
            }
        }
        return (cells, rows)
    }

    // MARK: - Shading

    /// The words that make a day full: the 85th percentile of the days with
    /// a note, never under 150, so the scale is the writer's own.
    static func reference(_ notes: [Int: DocumentRef], liveDay: Int?, liveWords: Int) -> Double {
        var counts = notes.compactMap { key, doc in key == liveDay ? nil : doc.words }.filter { $0 > 0 }
        if liveDay != nil, liveWords > 0 { counts.append(liveWords) }
        guard !counts.isEmpty else { return 300 }
        counts.sort()
        let at = min(counts.count - 1, Int((Double(counts.count) * 0.85).rounded(.down)))
        return Double(max(150, counts[at]))
    }

    /// 0…1, with a curve that lets a short note show and a long one saturate.
    static func intensity(_ words: Int, reference: Double) -> Double {
        guard words > 0 else { return 0 }
        return min(1, pow(Double(words) / reference, 0.6))
    }
}

/// Re-renders its content with the note's word count as it is typed.
private struct LiveWords<Content: View>: View {
    @ObservedObject var doc: DocumentModel
    @ViewBuilder let content: (Int) -> Content
    var body: some View { content(doc.wordCount) }
}

private struct DayCell: View {
    let day: Int
    let words: Int
    let hasNote: Bool
    let intensity: Double
    let isToday: Bool
    let isOpen: Bool
    let isFuture: Bool
    let title: String
    let theme: Theme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(fill)
            if isToday || isOpen {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isToday ? theme.accent.color.opacity(0.9) : theme.text.color.opacity(0.45), lineWidth: 1)
            }
            Text("\(day)")
                .font(.system(size: 10.5, weight: hasNote || isToday ? .medium : .regular, design: .rounded))
                .foregroundStyle(digit)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(hovering ? 1.14 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
        .animation(.easeOut(duration: 0.45), value: intensity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .help(help)
    }

    private var fill: Color {
        if hasNote { return theme.accent.color.opacity(0.09 + 0.74 * intensity) }
        if hovering { return theme.text.color.opacity(theme.isDark ? 0.07 : 0.05) }
        return .clear
    }

    /// Dark digits on a bright accent, light on a deep one, once the cell
    /// is filled enough for the accent to be what is behind the digit.
    private var digit: Color {
        if hasNote && intensity > 0.5 {
            let c = theme.accent.components
            let luminance = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
            return luminance > 0.55 ? Color.black.opacity(0.78) : Color.white.opacity(0.95)
        }
        if hasNote { return theme.text.color.opacity(0.92) }
        return theme.text.color.opacity(isFuture ? 0.22 : 0.48)
    }

    private var help: String {
        if hasNote { return "\(title) — \(words) word\(words == 1 ? "" : "s")" }
        return isFuture ? "\(title) — start its note" : "\(title) — no note; click to start one"
    }
}
