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
        case library, type, caret, modes, typing, theme, backdrop, about

        var id: String { rawValue }
        var index: Int { Pane.allCases.firstIndex(of: self) ?? 0 }

        static func at(_ i: Int) -> Pane {
            let n = allCases.count
            return allCases[((i % n) + n) % n]
        }

        var label: String {
            switch self {
            case .library: return "Library"
            case .type: return "Type"
            case .caret: return "Caret"
            case .modes: return "Modes"
            case .typing: return "Typing"
            case .theme: return "Theme"
            case .backdrop: return "Behind the glass"
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
            case .theme: return "paintpalette"
            case .backdrop: return "water.waves"
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
            case .theme: return "The glass, and the colours of everything on it."
            case .backdrop: return "The desktop, or folds of colour inside the window."
            case .about: return "This copy of Glassine, and where to read more."
            }
        }

        /// What a search finds this section by: its rows, and the words
        /// people reach for.
        var keywords: String {
            switch self {
            case .library:
                return "library location folder icloud drive dropbox obsidian vault reveal finder change files name first line untitled sort documents last edited date created autosave saving"
            case .type:
                return "type font face family size points line height paragraph spacing indent letter spacing tracking larger headings center headings markdown hide syntax markers page column width top margin layout"
            case .caret:
                return "caret cursor smooth movement glide time speed typing blink soft classic never width shape bar pin serif wedge ghost comet glow hollow tricks idle hop bounce flip wiggle stretch lean colour"
            case .modes:
                return "modes typewriter scrolling re-center click focus mode paragraph sentence unfocused text dimming counter words characters reading time everything"
            case .typing:
                return "typing smart quotes dashes spelling check correct autocorrect inline predictions continue lists return move finished tasks bottom checkbox"
            case .theme:
                return "theme appearance light dark follow the system always chosen material glass tint strength paper grain sidebar colours text headings accent markdown syntax quotes code links caret selection duplicate import export name"
            case .backdrop:
                return "behind the glass backdrop desktop aurora silk folds colour drift motion frost paper grain dusk nebula ocean borealis ember sunset moss rose graphite duplicate"
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
            ("Themes", [.theme, .backdrop]),
        ]
    }

    private var query: String { state.settingsQuery.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ZStack {
            theme.tint.color.opacity(theme.isDark ? 0.35 : 0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { state.showingSettings = false }

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
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                theme.tint.color.opacity(theme.isDark ? 0.42 : 0.55)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.text.color.opacity(theme.isDark ? 0.12 : 0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.18), radius: 30, y: 12)
        .padding(.vertical, 30)
        .foregroundStyle(theme.text.color)
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
                    case .theme: ThemeSection()
                    case .backdrop: BackdropSection()
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

/// A small text field in the card's own style.
private struct GlassTextField: View {
    let theme: Theme
    let placeholder: String
    @Binding var text: String
    var width: CGFloat = 200

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
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

// MARK: - Theme

struct ThemeSection: View {
    @EnvironmentObject var state: AppState

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }
    private var data: SettingsData { state.settings.data }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsPanel(theme: theme, title: "Appearance") {
                form.pills("Theme", \.appearanceMode, options: AppearanceMode.allCases, label: { $0.label },
                           keywords: "light dark follow system automatic")
                if data.appearanceMode == .system {
                    SettingRow(theme: theme, title: "In light mode", keywords: "light theme") {
                        themeMenu(dark: false, selection: form.binding(\.lightThemeID))
                    }
                    SettingRow(theme: theme, title: "In dark mode", keywords: "dark theme") {
                        themeMenu(dark: true, selection: form.binding(\.darkThemeID))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                groupLabel("Built in")
                LazyVGrid(columns: gridColumns(5), spacing: 12) {
                    ForEach(Theme.builtIns) { t in
                        ThemeTile(theme: t, selected: data.themeID == t.id) { pick(t) }
                    }
                }
                if !state.themes.custom.isEmpty {
                    groupLabel("Mine").padding(.top, 6)
                    LazyVGrid(columns: gridColumns(5), spacing: 12) {
                        ForEach(state.themes.custom) { t in
                            ThemeTile(theme: t, selected: data.themeID == t.id) { pick(t) }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Duplicate") {
                    let copy = state.themes.duplicate(theme)
                    state.settings.data.themeID = copy.id
                }
                .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
                .help("A copy of “\(theme.name)”, yours to change")
                Button("Delete") {
                    guard !theme.isBuiltIn else { return }
                    state.themes.delete(theme)
                    state.settings.data.themeID = Theme.graphite.id
                }
                .buttonStyle(GlassButtonStyle(theme: theme))
                .disabled(theme.isBuiltIn)
                .opacity(theme.isBuiltIn ? 0.4 : 1)
                Spacer()
                Button("Import…", action: importTheme).buttonStyle(GlassButtonStyle(theme: theme))
                Button("Export…", action: exportTheme).buttonStyle(GlassButtonStyle(theme: theme))
            }

            ThemeEditor(theme: theme)
        }
    }

    private func pick(_ t: Theme) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.settings.data.themeID = t.id }
    }

    private func themeMenu(dark: Bool, selection: Binding<String>) -> some View {
        let options = state.themes.all.filter { $0.isDark == dark }
        let current = options.first { $0.id == selection.wrappedValue } ?? options.first
        return GlassMenu(theme: theme) {
            HStack(spacing: 6) {
                if let current {
                    Circle().fill(current.accent.color).frame(width: 7, height: 7)
                }
                Text(current?.name ?? "—").font(.system(size: 12))
            }
        } content: {
            ForEach(options) { t in
                Button(t.name) { selection.wrappedValue = t.id }
            }
        }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let t = try state.themes.importTheme(from: url)
                state.settings.data.themeID = t.id
            } catch {
                state.errorMessage = "Couldn't import that theme: \(error.localizedDescription)"
            }
        }
    }

    private func exportTheme() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = theme.name.sanitizedFileStem + ".glassinetheme.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? state.themes.export(theme, to: url)
        }
    }
}

/// The selected theme's makings: its name, its glass, and its colours. Built-in
/// themes show theirs but take no changes; Duplicate makes one that does.
struct ThemeEditor: View {
    @EnvironmentObject var state: AppState
    let theme: Theme

    private func binding<T>(_ keyPath: WritableKeyPath<Theme, T>) -> Binding<T> {
        Binding(
            get: { state.theme[keyPath: keyPath] },
            set: { newValue in
                var t = state.theme
                t[keyPath: keyPath] = newValue
                state.themes.update(t)
            }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<Theme, HexColor>) -> Binding<Color> {
        Binding(
            get: { state.theme[keyPath: keyPath].color },
            set: { newValue in
                var t = state.theme
                t[keyPath: keyPath] = HexColor(newValue)
                state.themes.update(t)
            }
        )
    }

    private func optionalColorBinding(_ keyPath: WritableKeyPath<Theme, HexColor?>, fallback: NSColor) -> Binding<Color> {
        Binding(
            get: { (state.theme[keyPath: keyPath]?.nsColor ?? fallback).asColor },
            set: { newValue in
                var t = state.theme
                t[keyPath: keyPath] = HexColor(newValue)
                state.themes.update(t)
            }
        )
    }

    var body: some View {
        let locked = theme.isBuiltIn
        VStack(alignment: .leading, spacing: 18) {
            if locked {
                LockedNote(text: "“\(theme.name)” is built in, so these are for looking at. Duplicate makes a copy whose every colour is yours.")
            }
            Group {
                SettingsPanel(theme: theme, title: "Name") {
                    SettingRow(theme: theme, title: "Name") {
                        GlassTextField(theme: theme, placeholder: "Name", text: binding(\.name))
                    }
                    SettingRow(theme: theme, title: "Dark appearance", keywords: "light dark") {
                        GlassToggle(theme: theme, isOn: binding(\.isDark))
                    }
                }

                SettingsPanel(theme: theme, title: "Glass") {
                    SettingRow(theme: theme, title: "Material", keywords: "glass blur soft deep sidebar thin frosted opaque") {
                        GlassMenu(theme: theme) {
                            Text(theme.material.label).font(.system(size: 12))
                        } content: {
                            ForEach(GlassMaterial.allCases) { m in
                                Button(m.label) { binding(\.material).wrappedValue = m }
                            }
                        }
                    }
                    SettingRow(theme: theme, title: "Tint", keywords: "colour glass") {
                        ColorPicker("", selection: colorBinding(\.tint), supportsOpacity: false)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    SettingRow(theme: theme, title: "Tint strength", keywords: "opacity") {
                        GlassSlider(theme: theme, value: binding(\.tintOpacity), range: 0...1, step: 0.01, format: "%.0f%%", scale: 100)
                    }
                    SettingRow(theme: theme, title: "Paper grain", keywords: "noise texture") {
                        GlassSlider(theme: theme, value: binding(\.grain), range: 0...0.2, step: 0.005, format: "%.1f%%", scale: 100)
                    }
                    SettingRow(theme: theme, title: "Sidebar tint", keywords: "sidebar opacity") {
                        GlassSlider(theme: theme, value: binding(\.sidebarOpacity), range: 0...1, step: 0.01, format: "%.0f%%", scale: 100)
                    }
                }

                SettingsPanel(theme: theme, title: "Colours") {
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
                }
            }
            .disabled(locked)
            .opacity(locked ? 0.55 : 1)
        }
    }
}

// MARK: - Behind the glass

struct BackdropSection: View {
    @EnvironmentObject var state: AppState

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }
    private var data: SettingsData { state.settings.data }
    private var current: BackdropPreset { state.backdrops.preset(id: data.backdrop) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                groupLabel("Built in")
                LazyVGrid(columns: gridColumns(6), spacing: 12) {
                    ForEach(BackdropPreset.builtIns) { b in
                        BackdropTile(preset: b, theme: theme, selected: data.backdrop == b.id) { pick(b) }
                    }
                }
                if !state.backdrops.custom.isEmpty {
                    groupLabel("Mine").padding(.top, 6)
                    LazyVGrid(columns: gridColumns(6), spacing: 12) {
                        ForEach(state.backdrops.custom) { b in
                            BackdropTile(preset: b, theme: theme, selected: data.backdrop == b.id) { pick(b) }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Duplicate") {
                    let copy = state.backdrops.duplicate(current, for: theme)
                    state.settings.data.backdrop = copy.id
                }
                .buttonStyle(GlassButtonStyle(theme: theme, prominent: true))
                .disabled(current.isDesktop)
                .opacity(current.isDesktop ? 0.4 : 1)
                .help("A copy of “\(current.name)” whose colours are yours to change")
                Button("Delete") {
                    guard !current.isBuiltIn else { return }
                    state.backdrops.delete(current)
                    state.settings.data.backdrop = BackdropPreset.dusk.id
                }
                .buttonStyle(GlassButtonStyle(theme: theme))
                .disabled(current.isBuiltIn)
                .opacity(current.isBuiltIn ? 0.4 : 1)
                Spacer()
            }

            BackdropEditor(preset: current)
        }
    }

    private func pick(_ b: BackdropPreset) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.settings.data.backdrop = b.id }
    }
}

/// The selected backdrop: its colours, to change on one of the user's own,
/// and the drift, frost and grain that apply to all of them.
struct BackdropEditor: View {
    @EnvironmentObject var state: AppState
    let preset: BackdropPreset

    private var theme: Theme { state.theme }
    private var form: SettingsForm { SettingsForm(state: state) }
    private var colors: [HexColor] { preset.colors(for: theme) }

    private func colorBinding(_ i: Int) -> Binding<Color> {
        Binding(
            get: { colors.indices.contains(i) ? colors[i].color : .gray },
            set: { newValue in
                var p = preset
                guard p.colors.indices.contains(i) else { return }
                p.colors[i] = HexColor(newValue)
                state.backdrops.update(p)
            }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(get: { preset.name }, set: { var p = preset; p.name = $0; state.backdrops.update(p) })
    }

    var body: some View {
        let locked = preset.isBuiltIn
        VStack(alignment: .leading, spacing: 18) {
            if preset.isDesktop {
                SettingsPanel(theme: theme, title: "Desktop") {
                    PanelNote(theme: theme, text: preset.blurb)
                    PanelNote(theme: theme, text: "Pick a set of colours to put folds of colour inside the window instead — deep and slow, like silk lit from one side — for a desk without a wallpaper worth looking through. Duplicate a set to make a copy whose colours are yours.")
                }
            } else {
                if locked {
                    LockedNote(text: "“\(preset.name)” is built in. Duplicate makes a copy whose colours are yours to change.")
                }
                SettingsPanel(theme: theme, title: "Set") {
                    SettingRow(theme: theme, title: "Name") {
                        if locked {
                            Text(preset.name).font(.system(size: 12.5)).opacity(0.7)
                        } else {
                            GlassTextField(theme: theme, placeholder: "Name", text: nameBinding)
                        }
                    }
                    if !preset.blurb.isEmpty {
                        PanelNote(theme: theme, text: preset.blurb)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            ForEach(colors.indices, id: \.self) { i in
                                VStack(spacing: 3) {
                                    ColorPicker("", selection: colorBinding(i), supportsOpacity: false)
                                        .labelsHidden()
                                    if !locked, colors.count > BackdropPreset.minColors {
                                        Button {
                                            var p = preset
                                            p.colors.remove(at: i)
                                            state.backdrops.update(p)
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
                                    var p = preset
                                    p.colors.append(p.colors.last ?? BackdropPreset.hsb(250, 0.8))
                                    state.backdrops.update(p)
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
                        .disabled(locked)
                        .opacity(locked ? 0.7 : 1)
                        Text("Three to five, all on screen at once: the folds run round the set in this order, so each colour has folds of its own. Hue and saturation are what count — the theme sets the lightness, deep on a dark theme and pale on a light one, so the text stays readable over every part. The first colour also tints the ground.")
                            .font(.system(size: 11))
                            .opacity(0.55)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                }
                SettingsPanel(theme: theme, title: "For every backdrop") {
                    form.toggle("Drift", \.backdropDrift,
                                caption: "The folds move, slowly. Never under Reduce Motion.",
                                keywords: "motion animate still")
                    form.slider("Frost", \.backdropFrost, range: 0...1, step: 0.05, format: "%.0f%%", scale: 100,
                                caption: "Pales and softens the colour — gently at first, all the way at 100%.",
                                keywords: "pale soft wash")
                    form.slider("Paper grain", \.backdropGrain, range: 0...0.2, step: 0.005, format: "%.1f%%", scale: 100,
                                caption: "Its own grain, over the folds; silk wants more of it than glass.",
                                keywords: "noise texture")
                }
            }
        }
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
            SettingsPanel(theme: theme, title: "Updates") {
                PanelNote(theme: theme, text: "This copy came from the App Store, so new versions arrive through the App Store.")
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
            }

            SettingsPanel(theme: theme, title: "Settings") {
                SettingRow(theme: theme, title: "Restore defaults",
                           caption: "Every setting back to how it came, the theme and backdrop too. ⌘Z brings yours back.",
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
