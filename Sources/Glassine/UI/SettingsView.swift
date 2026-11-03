import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings as a translucent card over the main window (⌘,): a rail of
/// sections down the left, one section at a time on the right, and a search
/// box that finds any setting by name. Every section fits its page; the type
/// and the caret are shown, not described. Esc or a click outside puts the
/// card away — it can never end up behind the window it configures — and ⌘Z
/// takes back the last change to a setting.
struct SettingsOverlay: View {
    @EnvironmentObject var state: AppState
    @FocusState private var searchFocused: Bool
    @Namespace private var railSpace

    private var theme: Theme { state.theme }

    private var tab: Pane { Pane.at(state.settingsTab) }

    /// The sections, in the order ⇥ walks them.
    enum Pane: String, CaseIterable, Identifiable {
        case library, type, caret, modes, typing, look, about

        var id: String { rawValue }
        var index: Int { Pane.allCases.firstIndex(of: self) ?? 0 }

        static func at(_ i: Int) -> Pane {
            let n = allCases.count
            return allCases[((i % n) + n) % n]
        }

        /// A pane by name — the old names of the two halves of Look included,
        /// for the launch arguments and links that still use them.
        static func named(_ name: String) -> Pane? {
            if let p = Pane(rawValue: name) { return p }
            if name == "theme" || name == "backdrop" || name == "backdrops" || name == "themes" { return .look }
            return nil
        }

        var label: String {
            switch self {
            case .library: return "Library"
            case .type: return "Type"
            case .caret: return "Caret"
            case .modes: return "Modes"
            case .typing: return "Typing"
            case .look: return "Look"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .library: return "books.vertical"
            case .type: return "textformat"
            case .caret: return "character.cursor.ibeam"
            case .modes: return "scope"
            case .typing: return "keyboard"
            case .look: return "paintpalette"
            case .about: return "info.circle"
            }
        }

        /// A line under the title, about what the section holds.
        var subtitle: String {
            switch self {
            case .library: return "Where the documents live, and how they are named and sorted."
            case .type: return "The face, the size and the rhythm of the page."
            case .caret: return "How it moves, blinks and looks — and what it gets up to when you stop."
            case .modes: return "Typewriter scrolling, focus, and the counter."
            case .typing: return "What the Mac's text services do as you write."
            case .look: return "The page and what lies behind it, chosen together — and kept, or shared, as one."
            case .about: return "This copy of Glassine, and where to read more."
            }
        }

        /// What a search finds this section by: its rows, and the words
        /// people reach for.
        var keywords: String {
            switch self {
            case .library:
                return "library location folder icloud drive dropbox obsidian vault reveal finder change files name first line untitled sort documents last edited date created autosave saving sync github repository token sign in work mac second mac history pages tabs open keep switch option control tab carousel close one at a time"
            case .type:
                return "type font face family size points line height paragraph spacing indent letter spacing tracking larger headings center headings markdown hide syntax markers page column width top margin layout"
            case .caret:
                return "caret cursor smooth movement glide time speed typing blink soft classic never width shape bar pin serif wedge ghost comet glow hollow tricks idle hop bounce flip wiggle stretch lean colour"
            case .modes:
                return "modes typewriter scrolling re-center click focus mode paragraph sentence unfocused text dimming counter words characters reading time everything"
            case .typing:
                return "typing smart quotes dashes spelling check correct autocorrect inline predictions continue lists return move finished tasks bottom checkbox"
            case .look:
                return "look looks appearance theme page light dark follow the system always chosen material glass tint strength paper grain sidebar colours text headings accent markdown syntax quotes code links caret selection duplicate import export share save name file behind the glass backdrop background desktop wallpaper aurora silk folds colour drift motion frost soft sky slate deep water pine plum umber linen dusk nebula ocean borealis ember sunset moss rose graphite midnight sepia frost paper"
            case .about:
                return "about version build updates check for new versions daily check now sparkle app store manual website source github changelog shortcuts restore defaults reset"
            }
        }

        func matches(_ query: String) -> Bool {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return true }
            return label.localizedCaseInsensitiveContains(q) || keywords.localizedCaseInsensitiveContains(q)
        }

        /// The rail, in groups; About sits on its own at the bottom.
        static let groups: [(title: String, panes: [Pane])] = [
            ("General", [.library]),
            ("Editor", [.type, .caret, .modes, .typing]),
            ("Appearance", [.look]),
        ]
    }

    private var query: String { state.settingsQuery.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            Scrim(theme: theme) { state.showingSettings = false }
            card
        }
        .onChange(of: state.settingsQuery) { _, _ in followSearch() }
        .onAppear { followSearch() }
        .onChange(of: state.settingsSearchFocus) { _, _ in searchFocused = true }
        .onDisappear { state.settingsQuery = "" }
    }

    /// A search the section on screen has nothing for goes to the first
    /// section that has something.
    private func followSearch() {
        guard !query.isEmpty, !tab.matches(query) else { return }
        if let first = Pane.allCases.first(where: { $0.matches(query) }) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { state.settingsTab = first.index }
        }
    }

    private var card: some View {
        HStack(spacing: 0) {
            rail
                .frame(width: 178)
            Rectangle()
                .fill(theme.text.color.opacity(theme.isDark ? 0.08 : 0.07))
                .frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 748)
        .frame(maxHeight: 664)
        .glassCard(theme)
        .padding(.vertical, 30)
        .environment(\.settingsQuery, state.settingsQuery)
        .onTapGesture { }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

            let showing = Pane.groups.map { g in (title: g.title, panes: g.panes.filter { $0.matches(query) }) }
            let anything = showing.contains { !$0.panes.isEmpty } || Pane.about.matches(query)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(showing.indices, id: \.self) { i in
                    if !showing[i].panes.isEmpty {
                        Text(showing[i].title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.7)
                            .opacity(0.4)
                            .padding(.leading, 8)
                            .padding(.top, i == 0 ? 4 : 12)
                            .padding(.bottom, 4)
                        ForEach(showing[i].panes) { railRow($0) }
                    }
                }
                if !anything {
                    Text("Nothing here for “\(query)”")
                        .font(.system(size: 11.5))
                        .opacity(0.45)
                        .padding(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: state.settingsTab)
            .animation(.easeOut(duration: 0.15), value: state.settingsQuery)

            Spacer(minLength: 8)

            if Pane.about.matches(query) {
                railRow(.about).padding(.horizontal, 8)
            }
            hints
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .opacity(0.45)
            TextField("Find a setting", text: $state.settingsQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
            if !state.settingsQuery.isEmpty {
                Button {
                    state.settingsQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .opacity(0.45)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Capsule().fill(theme.text.color.opacity(theme.isDark ? 0.08 : 0.06)))
        .overlay(Capsule().strokeBorder(theme.text.color.opacity(searchFocused ? 0.2 : 0.08), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: searchFocused)
    }

    private func railRow(_ pane: Pane) -> some View {
        let selected = tab == pane
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { state.settingsTab = pane.index }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: pane.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .opacity(selected ? 0.95 : 0.55)
                Text(pane.label)
                    .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                    .opacity(selected ? 1 : 0.72)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.text.color.opacity(theme.isDark ? 0.13 : 0.10))
                        .matchedGeometryEffect(id: "selection", in: railSpace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle(theme: theme, selected: false))
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 3) {
            hint("⌘Z", "undoes a change")
            hint("⇥", "next section")
            hint("esc", "closes")
        }
        .opacity(0.5)
    }

    private func hint(_ keys: String, _ what: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 4)
                .frame(height: 15)
                .background(RoundedRectangle(cornerRadius: 3.5).fill(theme.text.color.opacity(0.1)))
            Text(what).font(.system(size: 10.5))
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tab.label)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(tab.subtitle)
                        .font(.system(size: 12))
                        .opacity(0.55)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                SidebarIconButton(systemName: "xmark", help: "Close (Esc)") { state.showingSettings = false }
                    .padding(.top, 1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch tab {
                    case .library: LibrarySection()
                    case .type: TypeSection()
                    case .caret: CaretSection()
                    case .modes: ModesSection()
                    case .typing: TypingSection()
                    case .look: LookSection()
                    case .about: AboutSection()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
        }
        .id(tab)
        .transition(.opacity.combined(with: .offset(y: 6)))
        .animation(.easeOut(duration: 0.18), value: tab)
    }
}

// MARK: - Rows by key path

/// The rows of a section, bound to the settings by key path, so every row
/// knows its default and offers the way back to it.
struct SettingsForm {
    let state: AppState
    private static let defaults = SettingsData()

    var theme: Theme { state.theme }

    func binding<T>(_ kp: WritableKeyPath<SettingsData, T>) -> Binding<T> {
        Binding(get: { state.settings.data[keyPath: kp] }, set: { state.settings.data[keyPath: kp] = $0 })
    }

    func isDefault<T: Equatable>(_ kp: WritableKeyPath<SettingsData, T>) -> Bool {
        state.settings.data[keyPath: kp] == SettingsForm.defaults[keyPath: kp]
    }

    func reset<T>(_ kp: WritableKeyPath<SettingsData, T>) {
        state.settings.data[keyPath: kp] = SettingsForm.defaults[keyPath: kp]
    }

    func toggle(_ title: String, _ kp: WritableKeyPath<SettingsData, Bool>,
                caption: String? = nil, keywords: String = "", disabled: Bool = false) -> some View {
        SettingRow(theme: theme, title: title, caption: caption, keywords: keywords,
                   isDefault: isDefault(kp), reset: { reset(kp) }) {
            GlassToggle(theme: theme, isOn: binding(kp))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .animation(.easeOut(duration: 0.15), value: disabled)
    }

    func slider(_ title: String, _ kp: WritableKeyPath<SettingsData, Double>,
                range: ClosedRange<Double>, step: Double, format: String, scale: Double = 1,
                caption: String? = nil, keywords: String = "", disabled: Bool = false) -> some View {
        SettingRow(theme: theme, title: title, caption: caption, keywords: keywords,
                   isDefault: isDefault(kp), reset: { reset(kp) }) {
            GlassSlider(theme: theme, value: binding(kp), range: range, step: step, format: format, scale: scale)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .animation(.easeOut(duration: 0.15), value: disabled)
    }

    func pills<T: Hashable>(_ title: String, _ kp: WritableKeyPath<SettingsData, T>,
                            options: [T], label: @escaping (T) -> String,
                            caption: String? = nil, keywords: String = "", disabled: Bool = false) -> some View {
        SettingRow(theme: theme, title: title, caption: caption, keywords: keywords,
                   isDefault: isDefault(kp), reset: { reset(kp) }) {
            PillPicker(theme: theme, selection: binding(kp), options: options, label: label)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .animation(.easeOut(duration: 0.15), value: disabled)
    }
}

/// A line of small print inside a panel, for what a group of rows needs said once.
private struct PanelNote: View {
    let theme: Theme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .opacity(0.55)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }
}

/// A row that is a link out: its name, a word about it, and an arrow.
private struct LinkRow: View {
    let theme: Theme
    let title: String
    let detail: String
    let action: () -> Void

    @Environment(\.settingsQuery) private var query
    @State private var hovering = false

    private var dimmed: Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && !title.localizedCaseInsensitiveContains(q) && !detail.localizedCaseInsensitiveContains(q)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 11)).opacity(0.5)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(hovering ? 0.7 : 0.35)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.text.color.opacity(hovering ? 0.06 : 0))
                    .padding(3)
            )
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.text.color.opacity(0.06)).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .opacity(dimmed ? 0.38 : 1)
    }
}

/// A small text field in the card's own style; `secure` for a token.
private struct GlassTextField: View {
    let theme: Theme
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = 200
    var secure: Bool = false
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12.5))
        .onSubmit { onSubmit?() }
        .padding(.horizontal, 9)
        .frame(width: width, height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.text.color.opacity(theme.isDark ? 0.08 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.text.color.opacity(0.1), lineWidth: 1))
    }
}

/// A note that a built-in thing is not for editing, with the way to a copy that is.
private struct LockedNote: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock").font(.system(size: 11)).opacity(0.5)
            Text(text).font(.system(size: 11.5)).opacity(0.6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

private func gridColumns(_ n: Int) -> [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 12), count: n)
}

private func groupLabel(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10.5, weight: .semibold))
        .kerning(0.6)
        .opacity(0.45)
        .padding(.leading, 4)
}

// MARK: - Library

struct LibrarySection: View {
    @EnvironmentObject var state: AppState

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPanel(theme: theme, title: "Location") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: state.library.isInICloud ? "icloud" : "folder")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.6)
                        Text(state.library.displayPath)
                            .font(.system(size: 11.5, design: .monospaced))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .opacity(0.85)
                    }
                    Text(state.library.isInICloud
                         ? "In iCloud Drive, so the documents reach your other devices on their own."
                         : (Distribution.isSandboxed
                            ? "iCloud Drive is off, so the documents stay on this Mac. Turn on iCloud Drive in System Settings to sync them."
                            : "Not in iCloud Drive. Choose a folder inside iCloud Drive to sync the documents."))
                        .font(.system(size: 11))
                        .opacity(0.55)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Reveal in Finder") { state.revealLibrary() }
                        Button("Change…") { state.chooseLibraryFolder() }
                        if state.settings.data.libraryPath != nil {
                            Button("Use iCloud Drive") { state.resetLibraryToDefault() }
                        }
                    }
                    .buttonStyle(GlassButtonStyle(theme: theme))
                    .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SyncPanel()

            SettingsPanel(theme: theme, title: "Pages") {
                form.toggle("Keep pages open", \.keepPagesOpen,
                            caption: "A document stays open as a page until you close it (⌘W). Hold ⌥ (or ⌃) and press Tab to fan the open pages out and step between them; let go to open one. Off, a document opened takes the place of the last.",
                            keywords: "tabs open pages switch option control tab carousel close one at a time")
            }

            SettingsPanel(theme: theme, title: "Files") {
                form.toggle("Name files after the first line", \.nameFilesFromFirstLine,
                            caption: "A new document starts as Untitled and takes its name from its first line as you write. Renaming a file yourself pins its name.",
                            keywords: "untitled rename")
                form.pills("Sort documents by", \.sortDocumentsBy, options: SortMode.allCases, label: { $0.label },
                           keywords: "order last edited name date created")
            }

            SettingsPanel(theme: theme, title: "Saving") {
                SettingRow(theme: theme, title: "Autosave",
                           caption: "Changes are written about half a second after you stop typing, and at least every few seconds while you type. Nothing to remember.",
                           keywords: "save") {
                    Text("Always on")
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.55)
                }
            }
        }
    }
}

// MARK: - Sync

/// The library's sync with GitHub: connect, see how it stands, disconnect.
/// Connecting happens inside the panel, no sheets — a code to enter on
/// github.com when Glassine is registered to sign in that way, or a token
/// pasted in — then a repository chosen or made.
struct SyncPanel: View {
    @EnvironmentObject var state: AppState

    private enum Step { case summary, choose, token, code, repositories }
    @State private var step: Step = .summary
    @State private var repoField = ""
    @State private var tokenField = ""
    @State private var busy = false
    @State private var error: String?
    @State private var code: GitHubAPI.DeviceCode?
    @State private var repos: [GitHubAPI.Repository] = []
    @State private var chosenRepo = ""
    @State private var newRepoName = "glassine-library"
    @State private var making = false
    @State private var signInTask: Task<Void, Never>?

    private var theme: Theme { state.theme }
    private var sync: SyncEngine { state.sync }

    var body: some View {
        SettingsPanel(theme: theme, title: "Sync") {
            if sync.isConnected {
                connected
            } else {
                switch step {
                case .summary: summary
                case .choose: choose
                case .token: tokenForm
                case .code: codeStep
                case .repositories: repositoryStep
                }
            }
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .onDisappear { signInTask?.cancel() }
    }

    // MARK: Connected

    private var connected: some View {
        Group {
            SettingRow(theme: theme, title: "Repository", keywords: "github repository") {
                HStack(spacing: 6) {
                    Text(sync.repository ?? "")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .opacity(0.85)
                    Button {
                        if let repo = sync.repository, let url = URL(string: "https://github.com/\(repo)") { NSWorkspace.shared.open(url) }
                    } label: {
                        Image(systemName: "arrow.up.forward").font(.system(size: 9, weight: .semibold)).opacity(0.5)
                    }
                    .buttonStyle(.plain)
                    .help("Open on github.com")
                }
            }
            SettingRow(theme: theme, title: "Status", keywords: "sync now status") {
                HStack(spacing: 10) {
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        Text(sync.statusText)
                            .font(.system(size: 11.5))
                            .foregroundStyle(statusColour)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 260, alignment: .trailing)
                    }
                    Button("Sync Now") { sync.sync() }
                        .buttonStyle(GlassButtonStyle(theme: theme))
                        .disabled(sync.status == .syncing)
                }
            }
            if let note = sync.note {
                PanelNote(theme: theme, text: note)
            }
            SettingRow(theme: theme, title: "Disconnect",
                       caption: "The documents stay on this Mac and in the repository; only the connection and the token go.",
                       keywords: "sign out forget token") {
                Button("Disconnect") { sync.disconnect(); step = .summary; error = nil }
                    .buttonStyle(GlassButtonStyle(theme: theme))
            }
        }
    }

    private var statusColour: Color {
        switch sync.status {
        case .offline, .failed: return Color(nsColor: .systemOrange)
        default: return theme.text.color.opacity(0.6)
        }
    }

    // MARK: Not yet

    private var summary: some View {
        SettingRow(theme: theme, title: "Sync with GitHub",
                   caption: "Keeps this library in a private repository of yours, so a second Mac — one you'd rather not sign into iCloud on — has the same documents, and every version of every note is kept. Nothing leaves this Mac until you connect.",
                   keywords: "github repository sync connect") {
            Button("Connect…") { error = nil; step = sync.canSignIn ? .choose : .token }
                .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
        }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in on github.com with a code Glassine shows you, or paste a token you made there.")
                .font(.system(size: 11.5)).opacity(0.7)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Sign in with GitHub", action: signIn)
                    .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
                Button("Use a token") { step = .token }
                    .buttonStyle(GlassButtonStyle(theme: theme))
                Spacer()
                Button("Cancel") { step = .summary }
                    .buttonStyle(GlassButtonStyle(theme: theme))
            }
        }
        .padding(12)
    }

    private var tokenForm: some View {
        Group {
            SettingRow(theme: theme, title: "Repository", caption: "owner/name — private, and empty to begin with.") {
                GlassTextField(theme: theme, placeholder: "alex/notes", text: $repoField)
            }
            SettingRow(theme: theme, title: "Token",
                       caption: "A fine-grained token for that one repository, with Contents: read and write. It goes in the keychain.") {
                GlassTextField(theme: theme, placeholder: "github_pat_…", text: $tokenField, secure: true) { connectWithToken() }
            }
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small)
                    Text("Checking with GitHub…").font(.system(size: 11.5)).opacity(0.6)
                } else {
                    Button("Connect", action: connectWithToken)
                        .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
                        .disabled(repoField.isEmpty || tokenField.isEmpty)
                        .opacity(repoField.isEmpty || tokenField.isEmpty ? 0.5 : 1)
                    Button("Cancel") { step = .summary; error = nil }
                        .buttonStyle(GlassButtonStyle(theme: theme))
                }
                Spacer()
                Button("Make a token…") { open("https://github.com/settings/personal-access-tokens/new") }
                    .buttonStyle(GlassButtonStyle(theme: theme))
                Button("New repository…") {
                    let name = repoField.split(separator: "/").last.map(String.init) ?? "glassine-library"
                    open("https://github.com/new?name=\(name)&visibility=private")
                }
                .buttonStyle(GlassButtonStyle(theme: theme))
                Button("How to") { open("https://docs.glassine.ink/library/sync") }
                    .buttonStyle(GlassButtonStyle(theme: theme))
            }
            .padding(12)
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter this code on github.com — it is on your clipboard, and the page is open:")
                .font(.system(size: 11.5)).opacity(0.7)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Text(code?.userCode ?? "")
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .kerning(2)
                    .textSelection(.enabled)
                Button("Open github.com") { if let url = code?.verificationURL { NSWorkspace.shared.open(url) } }
                    .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
                Button("Copy Code") { copy(code?.userCode ?? "") }
                    .buttonStyle(GlassButtonStyle(theme: theme))
                Spacer()
                ProgressView().controlSize(.small)
                Text("Waiting…").font(.system(size: 11.5)).opacity(0.6)
                Button("Cancel") { signInTask?.cancel(); step = .summary }
                    .buttonStyle(GlassButtonStyle(theme: theme))
            }
        }
        .padding(12)
    }

    private var repositoryStep: some View {
        Group {
            PanelNote(theme: theme, text: "Signed in as \(state.settings.data.syncLogin ?? "you"). Which repository holds the library? A private, empty one is best; one that already holds a Glassine library brings its documents here.")
            if !repos.isEmpty {
                SettingRow(theme: theme, title: "One of yours") {
                    HStack(spacing: 8) {
                        GlassMenu(theme: theme) {
                            Text(chosenRepo.isEmpty ? "Choose…" : chosenRepo).font(.system(size: 12)).lineLimit(1).frame(maxWidth: 220)
                        } content: {
                            ForEach(repos, id: \.fullName) { r in
                                Button(r.isPrivate ? r.fullName : "\(r.fullName) (public)") { chosenRepo = r.fullName }
                            }
                        }
                        Button("Use") { useRepository(chosenRepo) }
                            .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
                            .disabled(chosenRepo.isEmpty || busy)
                            .opacity(chosenRepo.isEmpty ? 0.5 : 1)
                    }
                }
            }
            SettingRow(theme: theme, title: "Or a new private one") {
                HStack(spacing: 8) {
                    GlassTextField(theme: theme, placeholder: "glassine-library", text: $newRepoName, width: 160) { createRepository() }
                    Button("Create", action: createRepository)
                        .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
                        .disabled(newRepoName.isEmpty || busy)
                }
            }
            HStack {
                if busy {
                    ProgressView().controlSize(.small)
                    Text(making ? "Making it…" : "Connecting…").font(.system(size: 11.5)).opacity(0.6)
                }
                Spacer()
                Button("Cancel") { step = .summary; error = nil }
                    .buttonStyle(GlassButtonStyle(theme: theme))
            }
            .padding(12)
        }
    }

    // MARK: Doing

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func connectWithToken() {
        guard !busy, !repoField.isEmpty, !tokenField.isEmpty else { return }
        busy = true
        error = nil
        Task { @MainActor in
            do {
                try await sync.connect(repository: repoField, token: tokenField)
                tokenField = ""
                step = .summary
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func signIn() {
        guard !busy else { return }
        busy = true
        error = nil
        signInTask = Task { @MainActor in
            do {
                let c = try await sync.beginSignIn()
                code = c
                copy(c.userCode)
                NSWorkspace.shared.open(c.verificationURL)
                step = .code
                _ = try await sync.finishSignIn(c)
                repos = try await sync.repositories()
                chosenRepo = ""
                step = .repositories
            } catch is CancellationError {
                step = .summary
            } catch {
                self.error = error.localizedDescription
                step = .choose
            }
            busy = false
        }
    }

    private func useRepository(_ name: String) {
        guard !busy, !name.isEmpty else { return }
        busy = true
        error = nil
        Task { @MainActor in
            do {
                try await sync.use(repositoryNamed: name)
                step = .summary
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    private func createRepository() {
        guard !busy, !newRepoName.isEmpty else { return }
        busy = true
        making = true
        error = nil
        Task { @MainActor in
            do {
                try await sync.createAndUse(repositoryNamed: newRepoName)
                step = .summary
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
            making = false
        }
    }
}

// MARK: - Type

struct TypeSection: View {
    @EnvironmentObject var state: AppState
    @State private var families: [String] = []

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }
    private var data: SettingsData { state.settings.data }

    private var fontLabel: String {
        SystemFontChoice.all.first { $0.id == data.fontFamily }?.label ?? data.fontFamily
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            specimen

            SettingsPanel(theme: theme, title: "Face") {
                SettingRow(theme: theme, title: "Font", keywords: "face family typeface serif sans mono rounded",
                           isDefault: form.isDefault(\.fontFamily), reset: { form.reset(\.fontFamily) }) {
                    GlassMenu(theme: theme) {
                        Text(fontLabel)
                            .font(Font(StyleConfig.baseFont(family: data.fontFamily, size: 12) as CTFont))
                            .lineLimit(1)
                            .frame(maxWidth: 220)
                    } content: {
                        ForEach(SystemFontChoice.all, id: \.id) { choice in
                            Button(choice.label) { state.settings.data.fontFamily = choice.id }
                        }
                        Divider()
                        ForEach(families, id: \.self) { family in
                            Button(family) { state.settings.data.fontFamily = family }
                        }
                    }
                }
                form.slider("Size", \.fontSize, range: 11...32, step: 1, format: "%.0f pt",
                            keywords: "points bigger smaller")
                form.slider("Letter spacing", \.letterSpacing, range: -1...2, step: 0.1, format: "%.1f pt",
                            keywords: "tracking kerning")
            }

            SettingsPanel(theme: theme, title: "Rhythm") {
                form.slider("Line height", \.lineHeight, range: 1.0...2.2, step: 0.05, format: "%.2f×",
                            keywords: "leading")
                form.slider("Paragraph spacing", \.paragraphSpacing, range: 0...1.5, step: 0.05, format: "%.2f em",
                            keywords: "gap between paragraphs")
                form.slider("Paragraph indent", \.paragraphIndent, range: 0...3, step: 0.1, format: "%.1f em",
                            keywords: "first line")
            }

            SettingsPanel(theme: theme, title: "Headings and marks") {
                form.toggle("Larger headings", \.scaledHeadings, keywords: "heading size scale")
                form.toggle("Center headings", \.centerHeadings, keywords: "centred alignment")
                form.toggle("Hide Markdown syntax", \.hideSyntax,
                            caption: "The markers — #, **, ==, the brackets of a link — stay in the file and leave the page, except in the sentence you are writing. ⌃⌘M switches this from the keyboard.",
                            keywords: "markers symbols")
            }

            SettingsPanel(theme: theme, title: "Page") {
                form.slider("Column width", \.columnWidth, range: 420...1100, step: 10, format: "%.0f pt",
                            keywords: "measure line length")
                form.slider("Top margin", \.topInset, range: 24...240, step: 4, format: "%.0f pt",
                            keywords: "inset space above")
            }
        }
        .onAppear {
            families = NSFontManager.shared.availableFontFamilies
                .filter { !$0.hasPrefix(".") }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }

    /// A piece of page in the current type, cut off at the bottom the way a
    /// window cuts a page off — the settings under it change it as they move.
    private var specimen: some View {
        TypeSpecimen(config: state.styleConfig)
            .frame(maxWidth: .infinity)
            .frame(height: 164)
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.76), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.tint.color.opacity(theme.isDark ? 0.5 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.text.color.opacity(theme.isDark ? 0.08 : 0.07), lineWidth: 1)
            )
    }
}

// MARK: - Caret

struct CaretSection: View {
    @EnvironmentObject var state: AppState

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }
    private var data: SettingsData { state.settings.data }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CaretSpecimen(config: state.styleConfig)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.tint.color.opacity(theme.isDark ? 0.5 : 0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.text.color.opacity(theme.isDark ? 0.08 : 0.07), lineWidth: 1)
                )

            SettingsPanel(theme: theme, title: "Movement") {
                form.toggle("Smooth movement", \.smoothCaret, keywords: "glide animate")
                form.slider("Glide time", \.caretSpeed, range: 0.04...0.50, step: 0.01, format: "%.0f ms", scale: 1000,
                            keywords: "speed duration", disabled: !data.smoothCaret)
                form.toggle("Smooth while typing", \.smoothWhileTyping,
                            caption: "Off, the caret keeps gliding for arrow keys and clicks but snaps as you type.",
                            keywords: "snap", disabled: !data.smoothCaret)
                form.pills("Blink", \.caretBlink, options: CaretBlink.allCases, label: { $0.label },
                           keywords: "soft classic never fade")
            }

            SettingsPanel(theme: theme, title: "Look") {
                form.slider("Width", \.caretWidth, range: 1...4, step: 0.5, format: "%.1f pt", keywords: "thick thin")
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Shape").font(.system(size: 13))
                        Spacer()
                        Text(data.caretShape.blurb)
                            .font(.system(size: 11))
                            .opacity(0.55)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    CaretShapePicker(shape: form.binding(\.caretShape), color: Color(nsColor: theme.caretColor), accent: theme.accent.color)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            SettingsPanel(theme: theme, title: "When you stop") {
                form.toggle("Tricks when idle", \.caretTricks,
                            caption: "Left alone for a few seconds, the caret hops, bounces, flips, wiggles, stretches or leans — and again every several seconds until you type. Reduce Motion in System Settings disables gliding and the tricks.",
                            keywords: "hop bounce flip wiggle stretch lean easter egg")
            }
        }
    }
}

// MARK: - Modes

struct ModesSection: View {
    @EnvironmentObject var state: AppState

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }
    private var data: SettingsData { state.settings.data }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPanel(theme: theme, title: "Typewriter") {
                form.toggle("Typewriter scrolling", \.typewriterMode,
                            caption: "The line you are writing stays at the middle of the window; the page moves instead. ⌃⌘T from the keyboard.",
                            keywords: "center line scroll")
                form.toggle("Also re-center after clicking", \.typewriterOnClick, keywords: "click mouse",
                            disabled: !data.typewriterMode)
            }

            SettingsPanel(theme: theme, title: "Focus") {
                form.toggle("Focus mode", \.focusMode,
                            caption: "Everything but what you are writing steps back. ⌃⌘F from the keyboard.",
                            keywords: "dim highlight current")
                form.pills("Focus on", \.focusScope, options: FocusScope.allCases, label: { $0.label },
                           keywords: "paragraph sentence", disabled: !data.focusMode)
                form.slider("Unfocused text", \.focusDimming, range: 0...1, step: 0.05, format: "%.0f%%", scale: 100,
                            caption: "How bright the rest of the page stays: 100% is no dimming at all, 0% hides it.",
                            keywords: "dimming brightness fade", disabled: !data.focusMode)
            }

            SettingsPanel(theme: theme, title: "Counter") {
                form.toggle("Show counter", \.showCounter, keywords: "word count footer")
                form.pills("Counter shows", \.counterMode, options: CounterMode.allCases, label: { $0.label },
                           keywords: "words characters reading time everything", disabled: !data.showCounter)
            }
        }
    }
}

// MARK: - Typing

struct TypingSection: View {
    @EnvironmentObject var state: AppState

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPanel(theme: theme, title: "As you write") {
                form.toggle("Smart quotes", \.smartQuotes, keywords: "curly quotation marks")
                form.toggle("Smart dashes", \.smartDashes, keywords: "em dash en dash hyphen")
                form.toggle("Check spelling", \.spellCheck, keywords: "spellcheck underline")
                form.toggle("Correct spelling automatically", \.autocorrect, keywords: "autocorrect")
                form.toggle("Inline predictions", \.inlinePredictions, keywords: "suggest complete")
            }

            SettingsPanel(theme: theme, title: "Lists and tasks") {
                form.toggle("Continue lists on Return", \.continueLists,
                            caption: "A new bullet, the next number, an empty task box. Return on an empty item ends the list.",
                            keywords: "bullets numbered")
                form.toggle("Move finished tasks to the bottom", \.moveCompletedTasks,
                            caption: "A task you check off sinks, a moment later, below the last unfinished item in its list.",
                            keywords: "checkbox done completed sink")
            }
        }
    }
}

// MARK: - Look

/// The one section for how the app looks, and the one thing it deals in: a
/// look. Tiles at the top — the built-in looks, then yours — and under
/// them the makings of the look on screen: its name, the colours of the
/// page, the glass, and what lies behind it. A theme and a backdrop are
/// still what a look is made of underneath, but they are never shown as
/// things of their own: a built-in look is for looking at, Duplicate makes
/// one that is yours, and a look of yours is edited in place — every change
/// is on the page behind the card as it is made.
struct LookSection: View {
    @EnvironmentObject var state: AppState
    @State private var naming = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }
    private var data: SettingsData { state.settings.data }
    private var current: Look? { state.currentLook }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                groupLabel("Built in")
                LazyVGrid(columns: gridColumns(4), spacing: 12) {
                    ForEach(Look.builtIns) { l in tile(l) }
                }
                if !state.looks.custom.isEmpty {
                    groupLabel("Mine").padding(.top, 6)
                    LazyVGrid(columns: gridColumns(4), spacing: 12) {
                        ForEach(state.looks.custom) { l in tile(l) }
                    }
                }
            }

            if naming {
                HStack(spacing: 8) {
                    GlassTextField(theme: theme, placeholder: state.suggestedLookName, text: $newName)
                        .frame(width: 260)
                        .focused($nameFocused)
                        .onSubmit(saveNamed)
                    Button("Save", action: saveNamed)
                        .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
                    Button("Cancel") { withAnimation(.easeOut(duration: 0.15)) { naming = false } }
                        .buttonStyle(GlassButtonStyle(theme: theme))
                    Spacer()
                }
                .transition(.opacity.combined(with: .offset(y: -4)))
            } else {
                HStack(spacing: 8) {
                    if let current {
                        Button("Duplicate") { state.duplicateLook(current) }
                            .buttonStyle(GlassButtonStyle(theme: theme, prominent: current.isBuiltIn))
                            .help("A copy of “\(current.name)” whose every colour is yours to change")
                        Button("Delete") { state.deleteLook(current) }
                            .buttonStyle(GlassButtonStyle(theme: theme))
                            .disabled(current.isBuiltIn)
                            .opacity(current.isBuiltIn ? 0.4 : 1)
                    } else {
                        // The page is wearing a mix no tile stands for — after
                        // following the system across a light and a dark look, say.
                        Button("Save this look…") {
                            newName = ""
                            withAnimation(.easeOut(duration: 0.15)) { naming = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nameFocused = true }
                        }
                        .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
                        .help("The page as it is now — \(state.suggestedLookName) — as a look of yours")
                    }
                    Spacer()
                    Button("Import…") { state.importLook() }
                        .buttonStyle(GlassButtonStyle(theme: theme))
                        .help("A .glassinelook file, from another Mac or another person")
                    Button("Export…") { state.exportLook() }
                        .buttonStyle(GlassButtonStyle(theme: theme))
                        .help("This look as one file, everything it needs inside")
                }
                .transition(.opacity)
            }

            SettingsPanel(theme: theme, title: "Appearance") {
                form.pills("Look", \.appearanceMode, options: AppearanceMode.allCases, label: { $0.label },
                           keywords: "light dark follow system automatic")
                if data.appearanceMode == .system {
                    SettingRow(theme: theme, title: "In light mode", keywords: "light look") { lookMenu(dark: false) }
                    SettingRow(theme: theme, title: "In dark mode", keywords: "dark look") { lookMenu(dark: true) }
                }
            }

            LookEditor(look: current)
        }
    }

    private func tile(_ l: Look) -> some View {
        LookTile(look: l, theme: state.themes.theme(id: l.themeID), backdrop: state.backdrops.preset(id: l.backdropID),
                 selected: current?.id == l.id) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.applyLook(l) }
        }
    }

    private func saveNamed() {
        state.saveLook(named: newName)
        withAnimation(.easeOut(duration: 0.15)) { naming = false }
    }

    /// The look for one half of the day, when the appearance follows the
    /// system: the looks whose page is light, or dark.
    private func lookMenu(dark: Bool) -> some View {
        let options = state.looks.all.filter { state.themes.theme(id: $0.themeID).isDark == dark }
        let slotTheme = dark ? data.darkThemeID : data.lightThemeID
        let current = options.first { $0.themeID == slotTheme && $0.backdropID == data.backdrop } ?? options.first { $0.themeID == slotTheme }
        return GlassMenu(theme: theme) {
            HStack(spacing: 6) {
                if let current {
                    Circle().fill(state.themes.theme(id: current.themeID).accent.color).frame(width: 7, height: 7)
                }
                Text(current?.name ?? "—").font(.system(size: 12))
            }
        } content: {
            ForEach(options) { l in
                Button(l.name) { state.applyLook(l) }
            }
        }
    }
}

/// The makings of the look on screen. A built-in look shows its makings
/// and takes no changes; a look of yours changes under your hands, and the
/// page behind the card with it. Underneath, a look's page is a theme and
/// what is behind the glass a backdrop; a change to a part a built-in
/// supplies makes the look a copy of its own first, so nothing built in is
/// ever written on.
struct LookEditor: View {
    @EnvironmentObject var state: AppState
    let look: Look?

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }
    private var backdrop: BackdropPreset { state.backdrop }
    private var locked: Bool { look?.isBuiltIn ?? false }

    // The page's colours and glass go through the look, which forks a
    // built-in theme into one of its own on the first change.
    private func themeBinding<T>(_ keyPath: WritableKeyPath<Theme, T>) -> Binding<T> {
        Binding(get: { state.theme[keyPath: keyPath] },
                set: { v in state.editLookTheme { $0[keyPath: keyPath] = v } })
    }

    private func colorBinding(_ keyPath: WritableKeyPath<Theme, HexColor>) -> Binding<Color> {
        Binding(get: { state.theme[keyPath: keyPath].color },
                set: { v in state.editLookTheme { $0[keyPath: keyPath] = HexColor(v) } })
    }

    private func optionalColorBinding(_ keyPath: WritableKeyPath<Theme, HexColor?>, fallback: NSColor) -> Binding<Color> {
        Binding(get: { (state.theme[keyPath: keyPath]?.nsColor ?? fallback).asColor },
                set: { v in state.editLookTheme { $0[keyPath: keyPath] = HexColor(v) } })
    }

    private func foldBinding(_ i: Int) -> Binding<Color> {
        let colors = backdrop.colors(for: theme)
        return Binding(get: { colors.indices.contains(i) ? colors[i].color : .gray },
                       set: { v in state.editLookBackdrop { p in if p.colors.indices.contains(i) { p.colors[i] = HexColor(v) } } })
    }

    private var nameBinding: Binding<String> {
        Binding(get: { look?.name ?? state.suggestedLookName },
                set: { v in if var l = look, !l.isBuiltIn { l.name = v; state.looks.update(l) } })
    }

    /// Drift, frost and grain are the page's settings, and the look's.
    private func tuning<T>(_ kp: WritableKeyPath<SettingsData, T>, _ lp: WritableKeyPath<Look, T>) -> Binding<T> {
        Binding(get: { state.settings.data[keyPath: kp] },
                set: { v in
                    state.settings.data[keyPath: kp] = v
                    if var l = look, !l.isBuiltIn { l[keyPath: lp] = v; state.looks.update(l) }
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let look, locked {
                LockedNote(text: "“\(look.name)” is built in, so these are for looking at. Duplicate makes a copy whose every colour is yours.")
            }
            Group {
                SettingsPanel(theme: theme, title: "Name") {
                    SettingRow(theme: theme, title: "Name") {
                        if locked || look == nil {
                            Text(look?.name ?? state.suggestedLookName).font(.system(size: 12.5)).opacity(0.7)
                        } else {
                            GlassTextField(theme: theme, placeholder: "Name", text: nameBinding)
                        }
                    }
                    SettingRow(theme: theme, title: "Dark appearance", caption: "A dark page, and deep folds behind it; off, a light page over pale ones.", keywords: "light dark") {
                        GlassToggle(theme: theme, isOn: themeBinding(\.isDark))
                    }
                }

                SettingsPanel(theme: theme, title: "The page") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                        ColourCell(theme: theme, title: "Text", color: colorBinding(\.text))
                        ColourCell(theme: theme, title: "Headings", color: optionalColorBinding(\.heading, fallback: theme.headingColor))
                        ColourCell(theme: theme, title: "Accent", color: colorBinding(\.accent))
                        ColourCell(theme: theme, title: "Markdown syntax", color: colorBinding(\.syntax))
                        ColourCell(theme: theme, title: "Quotes", color: optionalColorBinding(\.quote, fallback: theme.quoteColor))
                        ColourCell(theme: theme, title: "Code", color: optionalColorBinding(\.code, fallback: theme.codeColor))
                        ColourCell(theme: theme, title: "Links", color: optionalColorBinding(\.link, fallback: theme.linkColor))
                        ColourCell(theme: theme, title: "Caret", color: optionalColorBinding(\.caret, fallback: theme.caretColor))
                        ColourCell(theme: theme, title: "Selection", color: optionalColorBinding(\.selection, fallback: theme.selectionColor), supportsOpacity: true)
                    }
                    SettingRow(theme: theme, title: "Glass", keywords: "material blur soft deep sidebar thin frosted opaque") {
                        GlassMenu(theme: theme) {
                            Text(theme.material.label).font(.system(size: 12))
                        } content: {
                            ForEach(GlassMaterial.allCases) { m in
                                Button(m.label) { themeBinding(\.material).wrappedValue = m }
                            }
                        }
                    }
                    SettingRow(theme: theme, title: "Tint", keywords: "colour glass") {
                        ColorPicker("", selection: colorBinding(\.tint), supportsOpacity: false)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    SettingRow(theme: theme, title: "Tint strength", keywords: "opacity") {
                        GlassSlider(theme: theme, value: themeBinding(\.tintOpacity), range: 0...1, step: 0.01, format: "%.0f%%", scale: 100)
                    }
                    SettingRow(theme: theme, title: "Sidebar tint", keywords: "sidebar opacity") {
                        GlassSlider(theme: theme, value: themeBinding(\.sidebarOpacity), range: 0...1, step: 0.01, format: "%.0f%%", scale: 100)
                    }
                }

                SettingsPanel(theme: theme, title: "Behind the glass") {
                    SettingRow(theme: theme, title: "Behind the glass", keywords: "backdrop desktop wallpaper folds colour") {
                        PillPicker(theme: theme, selection: Binding(
                            get: { backdrop.isDesktop ? 1 : 0 },
                            set: { state.setLookBehind(desktop: $0 == 1) }),
                            options: [0, 1], label: { $0 == 1 ? "The desktop" : "Folds of colour" })
                    }
                    if backdrop.isDesktop {
                        PanelNote(theme: theme, text: "The window is a blur of whatever is behind it — the wallpaper, or the windows behind. The page's own grain lies over it.")
                        SettingRow(theme: theme, title: "Paper grain", keywords: "noise texture") {
                            GlassSlider(theme: theme, value: themeBinding(\.grain), range: 0...0.2, step: 0.005, format: "%.1f%%", scale: 100)
                        }
                    } else {
                        folds
                        SettingRow(theme: theme, title: "Drift", caption: "The folds move, slowly. Never under Reduce Motion.", keywords: "motion animate still") {
                            GlassToggle(theme: theme, isOn: tuning(\.backdropDrift, \.drift))
                        }
                        SettingRow(theme: theme, title: "Frost", caption: "Pales and softens the colour — gently at first, all the way at 100%.", keywords: "pale soft wash") {
                            GlassSlider(theme: theme, value: tuning(\.backdropFrost, \.frost), range: 0...1, step: 0.05, format: "%.0f%%", scale: 100)
                        }
                        SettingRow(theme: theme, title: "Paper grain", caption: "A fine, still texture over the folds.", keywords: "noise texture") {
                            GlassSlider(theme: theme, value: tuning(\.backdropGrain, \.grain), range: 0...0.2, step: 0.005, format: "%.1f%%", scale: 100)
                        }
                    }
                }
            }
            .disabled(locked)
            .opacity(locked ? 0.55 : 1)
        }
    }

    /// The colours the folds run round: three to five wells, in order.
    private var folds: some View {
        let colors = backdrop.colors(for: theme)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach(colors.indices, id: \.self) { i in
                    VStack(spacing: 3) {
                        ColorPicker("", selection: foldBinding(i), supportsOpacity: false)
                            .labelsHidden()
                        if !locked, colors.count > BackdropPreset.minColors {
                            Button {
                                state.editLookBackdrop { $0.colors.remove(at: i) }
                            } label: {
                                Image(systemName: "minus.circle").font(.system(size: 10)).opacity(0.5)
                            }
                            .buttonStyle(.plain)
                            .help("Remove this colour")
                        } else {
                            Text(i == 0 ? "ground" : " ").font(.system(size: 9)).opacity(0.45)
                        }
                    }
                }
                if !locked, colors.count < BackdropPreset.maxColors {
                    Button {
                        state.editLookBackdrop { $0.colors.append($0.colors.last ?? BackdropPreset.hsb(250, 0.5, 0.12)) }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 30, height: 22)
                            .background(RoundedRectangle(cornerRadius: 5).fill(theme.text.color.opacity(0.08)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 14)
                    .help("Add a colour")
                }
                Spacer()
            }
            Text("Three to five, all on screen at once: the folds run round them in this order. Hue and saturation are what count — the page sets the lightness, deep under a dark page and pale under a light one. The first colour also tints the ground.")
                .font(.system(size: 11))
                .opacity(0.55)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }
}

// MARK: - About

struct AboutSection: View {
    @EnvironmentObject var state: AppState

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Glassine")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("Version \(Distribution.version) (\(build)) · \(Distribution.channel)")
                        .font(.system(size: 12))
                        .opacity(0.55)
                    Text("A quiet place to write Markdown.")
                        .font(.system(size: 12))
                        .opacity(0.55)
                }
            }
            .padding(.leading, 2)

            #if canImport(Sparkle)
            SettingsPanel(theme: theme, title: "Updates") {
                SettingRow(theme: theme, title: "Check for new versions once a day",
                           caption: "A new version is offered here, downloaded, checked against its signature and installed in place; Glassine relaunches into it.",
                           keywords: "update automatic sparkle",
                           isDefault: form.isDefault(\.checkForUpdates), reset: { setChecks(SettingsData().checkForUpdates) }) {
                    GlassToggle(theme: theme, isOn: Binding(get: { state.settings.data.checkForUpdates }, set: { setChecks($0) }))
                }
                SettingRow(theme: theme, title: "Look now", keywords: "check now update") {
                    Button("Check for Updates…") { Updater.shared.check() }
                        .buttonStyle(GlassButtonStyle(theme: theme))
                }
            }
            #else
            SettingsPanel(theme: theme, title: Distribution.isDemo ? "This copy" : "Updates") {
                PanelNote(theme: theme, text: Distribution.isDemo
                    ? "A demonstration copy, for pictures and recordings: the library is a set of sample pages in a folder of its own, and nothing else on the Mac is in view. Help → Reset Demo Library writes them fresh."
                    : "This copy came from the App Store, so new versions arrive through the App Store.")
            }
            #endif

            SettingsPanel(theme: theme, title: "Read more") {
                LinkRow(theme: theme, title: "Manual", detail: "docs.glassine.ink") { open("https://docs.glassine.ink") }
                LinkRow(theme: theme, title: "What's new", detail: "the changelog") { open("https://docs.glassine.ink/about/changelog") }
                LinkRow(theme: theme, title: "Website", detail: "glassine.ink") { open("https://glassine.ink") }
                LinkRow(theme: theme, title: "Source", detail: "github.com/a-libre/glassine") { open("https://github.com/a-libre/glassine") }
                SettingRow(theme: theme, title: "Shortcuts", caption: "Every key on one sheet.", keywords: "keyboard keys") {
                    Button("Show  ⌘/") {
                        state.showingSettings = false
                        state.showingShortcuts = true
                    }
                    .buttonStyle(GlassButtonStyle(theme: theme))
                }
                SettingRow(theme: theme, title: "The tour", caption: "The first launch's walk through the app and its choices.", keywords: "tour onboarding welcome introduction") {
                    Button("Show") {
                        state.showingSettings = false
                        state.showingTour = true
                    }
                    .buttonStyle(GlassButtonStyle(theme: theme))
                }
            }

            SettingsPanel(theme: theme, title: "Settings") {
                SettingRow(theme: theme, title: "Restore defaults",
                           caption: "Every setting back to how it came, the look too. ⌘Z brings yours back.",
                           keywords: "reset factory") {
                    Button("Restore…") {
                        state.settings.data = SettingsData().withBookkeeping(of: state.settings.data)
                    }
                    .buttonStyle(GlassButtonStyle(theme: theme))
                }
            }
        }
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    #if canImport(Sparkle)
    private func setChecks(_ on: Bool) {
        state.settings.data.checkForUpdates = on
        Updater.shared.checksAutomatically = on
    }
    #endif
}
