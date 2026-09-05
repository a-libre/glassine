import SwiftUI

/// ⌘/ — every shortcut on one translucent card, in the app's own type.
/// Esc, ⌘/ or a click outside closes it.
struct ShortcutSheet: View {
    @EnvironmentObject var state: AppState

    private var theme: Theme { state.theme }

    private struct Group {
        let title: String
        let rows: [(keys: String, label: String)]
    }

    private let left: [Group] = [
        Group(title: "Documents", rows: [
            ("⌘N", "New document"),
            ("⌘⇧N", "New folder"),
            ("⌥⌘D", "Today's note"),
            ("⌘R", "Rename"),
            ("⌘⇧⌫", "Shelve — out of the way, not gone"),
            ("⌘⌫", "Move to Trash"),
            ("⌘Z", "Undo — files too"),
            ("⌘⇧E", "Export as PDF"),
        ]),
        Group(title: "Around the app", rows: [
            ("⌘1  ⌘P", "All documents"),
            ("⌘2  ⌘D", "Timelapse — the days, receding"),
            ("⌘3  ⌘N", "New document"),
            ("⌘K", "Command bar"),
            ("⌘F", "Search the library"),
            ("⌘S", "Show or hide the sidebar"),
            ("⌘↩", "Review"),
            ("Esc", "Step back: Review → editor → all documents"),
            ("↑ ↓ ← →", "Move between cards, Return opens"),
            ("⌘,", "Settings"),
        ]),
    ]

    private let right: [Group] = [
        Group(title: "Writing", rows: [
            ("⌘B  ⌘I", "Bold, italic"),
            ("⌘E ⌘⇧K", "Inline code, link"),
            ("⌘⌥1–3", "Heading level"),
            ("⌘⌥0", "Body text"),
            ("⌘⇧L", "Task checkbox"),
            ("⇥  ⇧⇥", "Nest or un-nest a list item"),
            ("⌘⇧X", "Strikethrough"),
            ("⌘⇧F", "Find in document"),
        ]),
        Group(title: "Copy & view", rows: [
            ("⌘⇧C", "Copy as Markdown"),
            ("⌥⌘C", "Copy as rich text"),
            ("⌃⌘T", "Typewriter scrolling"),
            ("⌃⌘F", "Focus mode"),
            ("⌘+  ⌘−", "Text size"),
            ("⌘/", "This sheet"),
        ]),
    ]

    var body: some View {
        ZStack {
            // A click anywhere outside the card closes it.
            theme.tint.color.opacity(theme.isDark ? 0.35 : 0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { state.showingShortcuts = false }

            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Shortcuts")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Text("Esc to close")
                    .font(.system(size: 11))
                    .opacity(0.4)
            }
            HStack(alignment: .top, spacing: 28) {
                column(left)
                column(right)
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                theme.tint.color.opacity(theme.isDark ? 0.38 : 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.text.color.opacity(theme.isDark ? 0.12 : 0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.18), radius: 30, y: 12)
        .foregroundStyle(theme.text.color)
        .onTapGesture { }  // swallow clicks on the card itself
    }

    private func column(_ groups: [Group]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groups.indices, id: \.self) { g in
                VStack(alignment: .leading, spacing: 5) {
                    Text(groups[g].title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .opacity(0.45)
                        .padding(.bottom, 2)
                    ForEach(groups[g].rows.indices, id: \.self) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(groups[g].rows[r].keys)
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(theme.accent.color)
                                .frame(width: 74, alignment: .trailing)
                            Text(groups[g].rows[r].label)
                                .font(.system(size: 12.5))
                                .opacity(0.9)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
