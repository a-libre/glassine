import AppKit
import SwiftUI

// MARK: - Search overlay (⌘F)

/// Where the mosaic's inline search box sits, so the overlay can glide out of it.
struct SearchFieldFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// ⌘F from anywhere: the search box glides from its spot in the mosaic header to
/// the middle of the window and takes the keyboard. The mosaic filters live
/// behind it; arrows walk the results, Return opens, Esc clears and closes.
struct SearchOverlay: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focused: Bool
    @State private var centered = false

    private var theme: Theme { state.theme }

    var body: some View {
        GeometryReader { geo in
            let target = CGPoint(x: geo.size.width / 2, y: min(geo.size.height * 0.30, 240))
            let origin = state.searchFieldFrame
            let hasOrigin = origin != .zero
            let start = hasOrigin ? CGPoint(x: origin.midX, y: origin.midY) : target

            ZStack(alignment: .topLeading) {
                // Click anywhere else to put it back.
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { state.showingSearch = false }

                bar
                    .frame(width: centered ? 460 : (hasOrigin ? origin.width : 460),
                           height: centered ? 46 : (hasOrigin ? origin.height : 46))
                    .position(centered ? target : start)
                    .opacity(centered ? 1 : (hasOrigin ? 0.85 : 0))
            }
            .onAppear {
                DispatchQueue.main.async { focused = true }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { centered = true }
            }
        }
        .ignoresSafeArea()
    }

    private var bar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .opacity(0.5)
            TextField("Search everything", text: $state.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit {
                    if let doc = state.filteredDocuments?.first { state.open(doc, fromCard: true) }
                }
            if !state.searchText.trimmingCharacters(in: .whitespaces).isEmpty, let n = state.filteredDocuments?.count {
                Text("\(n)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .opacity(0.45)
            }
            keycap("esc")
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                theme.tint.color.opacity(theme.isDark ? 0.35 : 0.5)
            }
        )
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(theme.text.color.opacity(theme.isDark ? 0.14 : 0.1), lineWidth: 1))
        .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.15), radius: 22, y: 8)
        .foregroundStyle(theme.text.color)
    }

    private func keycap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(theme.text.color.opacity(0.08)))
            .opacity(0.6)
    }
}

// MARK: - Command bar (⌘K)

/// A small palette of what makes sense right now: Review styles in Review,
/// sort orders in the mosaic, modes and copying in the editor. Type to filter,
/// arrows to choose, Return to run.
struct CommandBar: View {
    @EnvironmentObject var state: AppState
    @FocusState private var focused: Bool

    private var theme: Theme { state.theme }

    var body: some View {
        ZStack(alignment: .top) {
            theme.tint.color.opacity(theme.isDark ? 0.25 : 0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { state.showingCommandBar = false }

            card
                .padding(.top, 110)
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .medium))
                    .opacity(0.5)
                TextField("Type a command", text: $state.commandQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
            }
            .padding(.horizontal, 15)
            .frame(height: 46)

            Divider().opacity(0.4)

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 1) {
                        let cmds = state.filteredCommands
                        ForEach(Array(cmds.enumerated()), id: \.element.id) { i, cmd in
                            Button {
                                state.runCommand(at: i)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(cmd.title)
                                        .font(.system(size: 13))
                                    Spacer()
                                    if let keys = cmd.keys {
                                        Text(keys)
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .opacity(0.45)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(i == state.commandSelection ? theme.accent.color.opacity(0.24) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(cmd.id)
                        }
                        if state.filteredCommands.isEmpty {
                            Text("Nothing matches")
                                .font(.system(size: 12))
                                .opacity(0.4)
                                .padding(14)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 322)
                .onChange(of: state.commandSelection) { _, i in
                    let cmds = state.filteredCommands
                    if i >= 0, i < cmds.count { proxy.scrollTo(cmds[i].id) }
                }
            }
        }
        .frame(width: 520)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                theme.tint.color.opacity(theme.isDark ? 0.38 : 0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.text.color.opacity(theme.isDark ? 0.12 : 0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.18), radius: 28, y: 10)
        .foregroundStyle(theme.text.color)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: state.commandQuery) { _, _ in state.commandSelection = 0 }
        .onTapGesture { }
    }
}
