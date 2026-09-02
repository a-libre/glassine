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
        case general, editor, caret, themes
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .editor: return "textformat"
            case .caret: return "cursorarrow.motionlines"
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
                Text("Esc")
                    .font(.system(size: 11))
                    .opacity(0.4)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            Divider().opacity(0.5)

            Group {
                switch tab {
                case .general: GeneralSettings()
                case .editor: EditorSettings()
                case .caret: CaretSettings()
                case .themes: ThemeSettings()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Text(state.library.rootURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
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
                     : "This folder is not in iCloud Drive. Choose a folder inside iCloud Drive to sync.")
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
            Section("Updates") {
                Toggle("Check for new versions once a day", isOn: data.checkForUpdates)
                HStack {
                    Text("Glassine \(UpdateChecker.currentVersion)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { UpdateChecker.check(userInitiated: true) }
                }
            }
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
                sliderRow("Letter spacing", value: data.letterSpacing, range: -1...2, step: 0.1, format: "%.1f pt")
                Toggle("Larger headings", isOn: data.scaledHeadings)
            }
            Section("Layout") {
                sliderRow("Column width", value: data.columnWidth, range: 420...1100, step: 10, format: "%.0f pt")
                sliderRow("Top margin", value: data.topInset, range: 24...240, step: 4, format: "%.0f pt")
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

// MARK: - Caret

struct CaretSettings: View {
    @EnvironmentObject var state: AppState

    private var data: Binding<SettingsData> {
        Binding(get: { state.settings.data }, set: { state.settings.data = $0 })
    }

    var body: some View {
        Form {
            Section("Movement") {
                Toggle("Smooth movement", isOn: data.smoothCaret)
                sliderRow("Glide time", value: data.caretSpeed, range: 0.04...0.30, step: 0.01, format: "%.0f ms", scale: 1000)
                    .disabled(!state.settings.data.smoothCaret)
                Toggle("Smooth while typing", isOn: data.smoothWhileTyping)
                    .disabled(!state.settings.data.smoothCaret)
                Text("Turn this off to keep gliding for arrow keys and clicks, but snap instantly as you type.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Look") {
                Picker("Blink", selection: data.caretBlink) {
                    ForEach(CaretBlink.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                sliderRow("Width", value: data.caretWidth, range: 1...4, step: 0.5, format: "%.1f pt")
                Text("The caret uses the theme's caret color (usually the accent). Reduce Motion in System Settings disables gliding.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Themes

struct ThemeSettings: View {
    @EnvironmentObject var state: AppState
    @State private var editing: Theme?

    private var data: Binding<SettingsData> {
        Binding(get: { state.settings.data }, set: { state.settings.data = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            appearanceBar
            Divider()
            themeSplit
        }
    }

    /// Either one theme all the time, or a light/dark pair that follows macOS.
    private var appearanceBar: some View {
        HStack(spacing: 14) {
            Picker("Appearance", selection: data.appearanceMode) {
                ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
            }
            .frame(maxWidth: 320)
            if state.settings.data.appearanceMode == .system {
                Picker("Light", selection: data.lightThemeID) {
                    ForEach(state.themes.all.filter { !$0.isDark }) { Text($0.name).tag($0.id) }
                }
                Picker("Dark", selection: data.darkThemeID) {
                    ForEach(state.themes.all.filter { $0.isDark }) { Text($0.name).tag($0.id) }
                }
            }
            Spacer()
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
