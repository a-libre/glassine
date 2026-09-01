import SwiftUI

/// The Daily section: today's note in front, earlier days receding behind it —
/// each a little smaller and fainter — the way Vantage draws a day. Click a card
/// to open it; Esc goes back.
struct DailyTimelineView: View {
    @EnvironmentObject var state: AppState
    /// Shared with the editor so an opened card can grow into the page.
    let zoom: Namespace.ID

    private var theme: Theme { state.theme }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f
    }()

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private var notes: [(doc: DocumentRef, date: Date)] {
        state.library.allDocuments
            .filter { $0.folder == "Daily" }
            .map { ($0, DailyTimelineView.titleFormatter.date(from: $0.title) ?? $0.created) }
            .sorted { $0.1 > $1.1 }
    }

    private var hasToday: Bool {
        notes.first.map { Calendar.current.isDateInToday($0.date) } ?? false
    }

    var body: some View {
        let items = notes
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                header(count: items.count)
                    .padding(.bottom, 22)

                if !hasToday {
                    startTodayCard
                        .padding(.bottom, 26)
                }

                ForEach(Array(items.enumerated()), id: \.element.doc.id) { i, item in
                    let depth = i + (hasToday ? 0 : 1)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(label(for: item.date))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(0.4)
                            .foregroundStyle(depth == 0 ? theme.accent.color : theme.text.color.opacity(0.45))
                            .padding(.leading, 4)
                        GalleryCard(doc: item.doc, zoom: zoom)
                    }
                    .frame(width: 460)
                    .scaleEffect(scale(for: depth), anchor: .top)
                    .opacity(fade(for: depth))
                    .padding(.bottom, depth == 0 ? 28 : 18)
                }

                if items.isEmpty {
                    Text("Daily notes collect here, newest in front.")
                        .font(.system(size: 12))
                        .opacity(0.45)
                        .padding(.top, 6)
                }
                Spacer(minLength: 70)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 52)
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

    private func header(count: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Daily")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .opacity(0.4)
            }
            Spacer()
        }
        .frame(width: 460)
    }

    private var startTodayCard: some View {
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
                Text("⌘D")
                    .font(.system(size: 11))
                    .opacity(0.35)
            }
            .padding(.horizontal, 16)
            .frame(width: 460, height: 52)
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

    /// The front card is full size; each day back steps down a little and settles.
    private func scale(for depth: Int) -> CGFloat {
        depth == 0 ? 1.0 : max(0.86, 0.95 - CGFloat(depth - 1) * 0.02)
    }

    private func fade(for depth: Int) -> Double {
        depth == 0 ? 1.0 : max(0.4, 0.78 - Double(depth - 1) * 0.09)
    }
}
