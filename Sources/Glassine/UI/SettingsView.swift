import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings as a translucent card over the main window (⌘,). Esc or a click
/// outside puts it away; it can never end up behind the window it configures.
struct SettingsOverlay: View {
    @EnvironmentObject var state: AppState

    private var theme: Theme { state.theme }

    private var tab: Pane {
        let n = Pane.allCases.count
        return Pane.allCases[((state.settingsTab % n) + n) % n]
    }

    enum Pane: String, CaseIterable, Identifiable {
        case general, editor, themes
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .editor: return "textformat"
            case .themes: return "paintpalette"
            }
        }
    }

    var body: some View {
        ZStack {
            theme.tint.color.opacity(theme.isDark ? 0.35 : 0.25)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { state.showingSettings = false }

            card
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                ForEach(Pane.allCases) { pane in
                    Button {
                        state.settingsTab = Pane.allCases.firstIndex(of: pane) ?? 0
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: pane.icon).font(.system(size: 11, weight: .medium))
                            Text(pane.label).font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            Capsule().fill(tab == pane ? theme.accent.color.opacity(0.22) : theme.text.color.opacity(0.001))
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .opacity(tab == pane ? 1 : 0.6)
                }
                Spacer()
                Text("⌘Z undoes · Esc")
                    .font(.system(size: 11))
                    .opacity(0.4)
                    .help("⌘Z takes back the last change to a setting, ⇧⌘Z puts it back; Esc closes")
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            Divider().opacity(0.5)

            Group {
                switch tab {
                case .general: GeneralSettings()
                case .editor: EditorSettings()
                case .themes: ThemeSettings()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(tab)
            .transition(.opacity.combined(with: .offset(y: 6)))
            .animation(.easeOut(duration: 0.18), value: tab)
        }
        .frame(width: 580)
        .frame(maxHeight: 760)
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
        .onTapGesture { }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @EnvironmentObject var state: AppState

    private var data: Binding<SettingsData> {
        Binding(get: { state.settings.data }, set: { state.settings.data = $0 })
    }

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Location") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(state.library.displayPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                        HStack {
                            Button("Reveal in Finder") { state.revealLibrary() }
                            Button("Change…") { state.chooseLibraryFolder() }
                            if state.settings.data.libraryPath != nil {
                                Button("Use iCloud Drive") { state.resetLibraryToDefault() }
                            }
                        }
                        .controlSize(.small)
                    }
                }
                Text(state.library.isInICloud
                     ? "This folder lives in iCloud Drive, so documents sync to your other devices automatically."
                     : (Distribution.isSandboxed
                        ? "iCloud Drive is off, so documents stay on this Mac. Turn on iCloud Drive in System Settings to sync them."
                        : "This folder is not in iCloud Drive. Choose a folder inside iCloud Drive to sync."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Files") {
                Toggle("Name files after the first line", isOn: data.nameFilesFromFirstLine)
                Text("New documents start as “Untitled” and take their name from the first line as you write. Renaming a file yourself pins its name.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Sort documents by", selection: data.sortDocumentsBy) {
                    ForEach(SortMode.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Saving") {
                LabeledContent("Autosave", value: "Always on")
                Text("Changes are written about half a second after you stop typing, and at least every few seconds while you type. Nothing to remember.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #if canImport(Sparkle)
            Section("Updates") {
                Toggle("Check for new versions once a day", isOn: Binding(
                    get: { state.settings.data.checkForUpdates },
                    set: { state.settings.data.checkForUpdates = $0; Updater.shared.checksAutomatically = $0 }
                ))
                HStack {
                    Text("Glassine \(Updater.currentVersion)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { Updater.shared.check() }
                }
                Text("A new version is offered here, downloaded, checked against its signature and installed in place; Glassine relaunches into it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #else
            Section("Updates") {
                Text("Glassine \(Distribution.version) · App Store. Updates arrive through the App Store.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #endif
        }
        .formStyle(.grouped)
    }
}

// MARK: - Editor

struct EditorSettings: View {
    @EnvironmentObject var state: AppState
    @State private var families: [String] = []

    private var data: Binding<SettingsData> {
        Binding(get: { state.settings.data }, set: { state.settings.data = $0 })
    }

    var body: some View {
        Form {
            Section("Type") {
                Picker("Font", selection: data.fontFamily) {
                    ForEach(SystemFontChoice.all, id: \.id) { Text($0.label).tag($0.id) }
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                sliderRow("Size", value: data.fontSize, range: 11...32, step: 1, format: "%.0f pt")
                sliderRow("Line height", value: data.lineHeight, range: 1.0...2.2, step: 0.05, format: "%.2f×")
                sliderRow("Paragraph spacing", value: data.paragraphSpacing, range: 0...1.5, step: 0.05, format: "%.2f em")
                sliderRow("Paragraph indent", value: data.paragraphIndent, range: 0...3, step: 0.1, format: "%.1f em")
                sliderRow("Letter spacing", value: data.letterSpacing, range: -1...2, step: 0.1, format: "%.1f pt")
                Toggle("Larger headings", isOn: data.scaledHeadings)
                Toggle("Center headings", isOn: data.centerHeadings)
            }
            Section("Markdown") {
                Toggle("Hide Markdown syntax", isOn: data.hideSyntax)
                Text("The markers — #, **, ==, the brackets of a link — stay in the file and leave the page, except in the sentence you are writing. ⌃⌘M switches this from the keyboard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Layout") {
                sliderRow("Column width", value: data.columnWidth, range: 420...1100, step: 10, format: "%.0f pt")
                sliderRow("Top margin", value: data.topInset, range: 24...240, step: 4, format: "%.0f pt")
            }
            Section("Caret") {
                Toggle("Smooth movement", isOn: data.smoothCaret)
                sliderRow("Glide time", value: data.caretSpeed, range: 0.04...0.50, step: 0.01, format: "%.0f ms", scale: 1000)
                    .disabled(!state.settings.data.smoothCaret)
                Toggle("Smooth while typing", isOn: data.smoothWhileTyping)
                    .disabled(!state.settings.data.smoothCaret)
                Text("Turn this off to keep gliding for arrow keys and clicks, but snap instantly as you type.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Blink", selection: data.caretBlink) {
                    ForEach(CaretBlink.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                sliderRow("Width", value: data.caretWidth, range: 1...4, step: 0.5, format: "%.1f pt")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shape")
                    CaretShapePicker(shape: data.caretShape, color: Color(nsColor: state.theme.caretColor))
                    Text(state.settings.data.caretShape.blurb)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Tricks when idle", isOn: data.caretTricks)
                Text("Left alone for a few seconds, the caret hops, bounces, flips, wiggles, stretches or leans — and again every several seconds until you type. The caret uses the theme's caret color (usually the accent). Reduce Motion in System Settings disables gliding and the tricks.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Modes") {
                Toggle("Typewriter scrolling", isOn: data.typewriterMode)
                Toggle("Also re-center after clicking", isOn: data.typewriterOnClick)
                    .disabled(!state.settings.data.typewriterMode)
                Toggle("Focus mode", isOn: data.focusMode)
                Picker("Focus on", selection: data.focusScope) {
                    ForEach(FocusScope.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!state.settings.data.focusMode)
                sliderRow("Unfocused text", value: data.focusDimming, range: 0...1, step: 0.05, format: "%.0f%%", scale: 100)
                    .disabled(!state.settings.data.focusMode)
                Text("How bright the rest of the page stays while you focus: 100% is no dimming at all, 0% hides it completely.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show counter", isOn: data.showCounter)
                Picker("Counter shows", selection: data.counterMode) {
                    ForEach(CounterMode.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!state.settings.data.showCounter)
            }
            Section("While typing") {
                Toggle("Smart quotes", isOn: data.smartQuotes)
                Toggle("Smart dashes", isOn: data.smartDashes)
                Toggle("Check spelling", isOn: data.spellCheck)
                Toggle("Correct spelling automatically", isOn: data.autocorrect)
                Toggle("Inline predictions", isOn: data.inlinePredictions)
                Toggle("Continue lists on Return", isOn: data.continueLists)
                Toggle("Move finished tasks to the bottom after a moment", isOn: data.moveCompletedTasks)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            families = NSFontManager.shared.availableFontFamilies
                .filter { !$0.hasPrefix(".") }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }
}

// MARK: - Themes

/// The two halves of the Themes pane: the themes, and what sits behind the glass.
enum ThemesPanePart: String, CaseIterable, Identifiable {
    case themes, backdrops
    var id: String { rawValue }
    var label: String { self == .themes ? "Theme" : "Behind the glass" }
}

struct ThemeSettings: View {
    @EnvironmentObject var state: AppState
    @State private var editing: Theme?

    private var data: Binding<SettingsData> {
        Binding(get: { state.settings.data }, set: { state.settings.data = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            partBar
            Divider()
            switch state.themesPanePart {
            case .themes:
                appearanceBar
                Divider()
                themeSplit
            case .backdrops:
                backdropSplit
            }
        }
    }

    /// The switch between the themes and what sits behind the glass. It lives
    /// in AppState, so Settings reopens on the half it was closed on.
    private var partBar: some View {
        HStack {
            Spacer()
            Picker("", selection: Binding(get: { state.themesPanePart }, set: { state.themesPanePart = $0 })) {
                ForEach(ThemesPanePart.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Either one theme all the time, or a light/dark pair that follows macOS.
    private var appearanceBar: some View {
        HStack(spacing: 14) {
            Spacer()
            Picker("Appearance", selection: data.appearanceMode) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
            }
            .fixedSize()
            if state.settings.data.appearanceMode == .system {
                Picker("Light", selection: data.lightThemeID) {
                    ForEach(state.themes.all.filter { !$0.isDark }) { Text($0.name).tag($0.id) }
                }
                .fixedSize()
                Picker("Dark", selection: data.darkThemeID) {
                    ForEach(state.themes.all.filter { $0.isDark }) { Text($0.name).tag($0.id) }
                }
                .fixedSize()
            }
            Spacer()
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Behind the glass

    private var currentBackdrop: BackdropPreset { state.backdrops.preset(id: state.settings.data.backdrop) }

    /// The backdrops — built in and the user's own — beside the editor for
    /// the selected one, the way the themes are laid out.
    private var backdropSplit: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: Binding(
                    get: { state.settings.data.backdrop },
                    set: { if let id = $0 { state.settings.data.backdrop = id } }
                )) {
                    Section("Built in") {
                        ForEach(BackdropPreset.builtIns) { b in BackdropRowLabel(preset: b, theme: state.theme).tag(b.id) }
                    }
                    if !state.backdrops.custom.isEmpty {
                        Section("Mine") {
                            ForEach(state.backdrops.custom) { b in BackdropRowLabel(preset: b, theme: state.theme).tag(b.id) }
                        }
                    }
                }
                .listStyle(.sidebar)
                HStack(spacing: 6) {
                    Button {
                        let copy = state.backdrops.duplicate(currentBackdrop, for: state.theme)
                        state.settings.data.backdrop = copy.id
                    } label: { Image(systemName: "plus") }
                    .help("Duplicate the selected backdrop so you can change its colours")
                    Button {
                        let b = currentBackdrop
                        guard !b.isBuiltIn else { return }
                        state.backdrops.delete(b)
                        state.settings.data.backdrop = BackdropPreset.dusk.id
                    } label: { Image(systemName: "minus") }
                    .disabled(currentBackdrop.isBuiltIn)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 190)

            Divider()

            BackdropEditor(preset: currentBackdrop)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var themeSplit: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: Binding(
                    get: { state.settings.data.themeID },
                    set: { if let id = $0 { state.settings.data.themeID = id } }
                )) {
                    Section("Built in") {
                        ForEach(Theme.builtIns) { t in ThemeRowLabel(theme: t).tag(t.id) }
                    }
                    if !state.themes.custom.isEmpty {
                        Section("Mine") {
                            ForEach(state.themes.custom) { t in ThemeRowLabel(theme: t).tag(t.id) }
                        }
                    }
                }
                .listStyle(.sidebar)
                HStack(spacing: 6) {
                    Button {
                        let copy = state.themes.duplicate(state.theme)
                        state.settings.data.themeID = copy.id
                    } label: { Image(systemName: "plus") }
                    .help("Duplicate the selected theme so you can edit it")
                    Button {
                        let t = state.theme
                        guard !t.isBuiltIn else { return }
                        state.themes.delete(t)
                        state.settings.data.themeID = Theme.graphite.id
                    } label: { Image(systemName: "minus") }
                    .disabled(state.theme.isBuiltIn)
                    Spacer()
                    Menu {
                        Button("Import Theme…", action: importTheme)
                        Button("Export “\(state.theme.name)”…", action: exportTheme)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 190)

            Divider()

            ThemeEditor(theme: state.theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        panel.nameFieldStringValue = state.theme.name.sanitizedFileStem + ".glassinetheme.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? state.themes.export(state.theme, to: url)
        }
    }
}

/// A backdrop in the list: its colours as a strip, and its name.
struct BackdropRowLabel: View {
    let preset: BackdropPreset
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if preset.isDesktop {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                } else {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: preset.colors(for: theme).map(\.color), startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.primary.opacity(0.15)))
                }
            }
            .frame(width: 18, height: 18)
            Text(preset.name)
        }
    }
}

/// The selected backdrop: its colours, to change on one of the user's own,
/// and the drift and frost that apply to all of them.
struct BackdropEditor: View {
    @EnvironmentObject var state: AppState
    let preset: BackdropPreset

    private var data: Binding<SettingsData> {
        Binding(get: { state.settings.data }, set: { state.settings.data = $0 })
    }

    private var colors: [HexColor] { preset.colors(for: state.theme) }

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
        Form {
            if preset.isDesktop {
                Section {
                    Text(preset.blurb)
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Pick a set of colours to put folds of colour inside the window instead — deep and slow, like silk lit from one side — for a desk without a wallpaper worth looking through. Press + on a set to make a copy whose colours are yours to change.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                if locked {
                    Section {
                        HStack {
                            Image(systemName: "lock").foregroundStyle(.secondary)
                            Text("Built-in backdrops can't be edited. Press + to duplicate “\(preset.name)” and make it yours.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Name") {
                    if locked {
                        LabeledContent("Name", value: preset.name)
                        Text(preset.blurb).font(.caption).foregroundStyle(.secondary)
                    } else {
                        TextField("Name", text: nameBinding)
                    }
                }
                Section("Colours") {
                    ForEach(colors.indices, id: \.self) { i in
                        HStack {
                            ColorPicker(i == 0 ? "Ground and first fold" : "Colour \(i + 1)", selection: colorBinding(i), supportsOpacity: false)
                            if !locked, colors.count > BackdropPreset.minColors {
                                Button {
                                    var p = preset
                                    p.colors.remove(at: i)
                                    state.backdrops.update(p)
                                } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help("Remove this colour")
                            }
                        }
                    }
                    if !locked, colors.count < BackdropPreset.maxColors {
                        Button("Add a colour") {
                            var p = preset
                            p.colors.append(p.colors.last ?? BackdropPreset.hsb(250, 0.8))
                            state.backdrops.update(p)
                        }
                    }
                    Text("Three to five, and every one of them is on screen at once: the folds run round the set in this order, so each colour has folds of its own. Hue and saturation are what count — the theme sets the lightness, deep on a dark theme and pale on a light one, so the text stays readable over every part. The first colour also tints the ground.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(locked)
                Section("Motion, frost and grain") {
                    Toggle("Drift", isOn: data.backdropDrift)
                    sliderRow("Frost", value: data.backdropFrost, range: 0...1, step: 0.05, format: "%.0f%%", scale: 100)
                    sliderRow("Paper grain", value: data.backdropGrain, range: 0...0.2, step: 0.005, format: "%.1f%%", scale: 100)
                    Text("For every backdrop. Drift moves the folds, slowly; never under Reduce Motion. Frost pales and softens the colour, gently at first and all the way at 100%. Paper grain lies over the folds the way the theme's grain lies over the desktop's blur; this one is its own, since silk wants more of it than glass.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ThemeRowLabel: View {
    let theme: Theme
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.tint.color)
                    .frame(width: 18, height: 18)
                Circle().fill(theme.accent.color).frame(width: 7, height: 7)
            }
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.primary.opacity(0.15)))
            Text(theme.name)
        }
    }
}

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
        Form {
            if locked {
                Section {
                    HStack {
                        Image(systemName: "lock").foregroundStyle(.secondary)
                        Text("Built-in themes can't be edited. Press + to duplicate “\(theme.name)” and make it yours.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Name") {
                TextField("Name", text: binding(\.name))
                Toggle("Dark appearance", isOn: binding(\.isDark))
            }
            Section("Glass") {
                Picker("Material", selection: binding(\.material)) {
                    ForEach(GlassMaterial.allCases) { Text($0.label).tag($0) }
                }
                ColorPicker("Tint", selection: colorBinding(\.tint), supportsOpacity: false)
                sliderRow("Tint strength", value: binding(\.tintOpacity), range: 0...1, step: 0.01, format: "%.0f%%", scale: 100)
                sliderRow("Paper grain", value: binding(\.grain), range: 0...0.2, step: 0.005, format: "%.1f%%", scale: 100)
                sliderRow("Sidebar tint", value: binding(\.sidebarOpacity), range: 0...1, step: 0.01, format: "%.0f%%", scale: 100)
            }
            Section("Text") {
                ColorPicker("Text", selection: colorBinding(\.text), supportsOpacity: false)
                ColorPicker("Headings", selection: optionalColorBinding(\.heading, fallback: theme.headingColor), supportsOpacity: false)
                ColorPicker("Accent", selection: colorBinding(\.accent), supportsOpacity: false)
                ColorPicker("Markdown syntax", selection: colorBinding(\.syntax), supportsOpacity: false)
                ColorPicker("Quotes", selection: optionalColorBinding(\.quote, fallback: theme.quoteColor), supportsOpacity: false)
                ColorPicker("Code", selection: optionalColorBinding(\.code, fallback: theme.codeColor), supportsOpacity: false)
                ColorPicker("Links", selection: optionalColorBinding(\.link, fallback: theme.linkColor), supportsOpacity: false)
                ColorPicker("Caret", selection: optionalColorBinding(\.caret, fallback: theme.caretColor), supportsOpacity: false)
                ColorPicker("Selection", selection: optionalColorBinding(\.selection, fallback: theme.selectionColor), supportsOpacity: true)
            }
        }
        .formStyle(.grouped)
        .disabled(locked)
    }
}

// MARK: - Helpers

@ViewBuilder
func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String, scale: Double = 1) -> some View {
    HStack {
        Text(title)
        Slider(value: value, in: range, step: step)
        Text(String(format: format, value.wrappedValue * scale))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .trailing)
    }
}
