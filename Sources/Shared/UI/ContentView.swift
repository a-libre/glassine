import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var promptText = ""
    @State private var dragStartWidth: CGFloat?
    @State private var handleHovered = false

    private var theme: Theme { state.theme }
    private var sidebarVisible: Bool { state.settings.data.sidebarVisible }

    #if os(iOS)
    // A phone — or a slim iPad window — has no width to give a sidebar: there
    // it is a drawer that slides over the page, and puts itself away once it
    // has been used.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.windowMetrics) private var metrics
    private var isCompact: Bool { sizeClass == .compact }
    @State private var settledCompact = false
    #else
    private let isCompact = false
    #endif

    var body: some View {
        ZStack(alignment: .topLeading) {
            GlassBackdrop(theme: theme, backdrop: state.backdrops.preset(id: state.settings.data.backdrop),
                          drifts: state.settings.data.backdropDrift, frost: state.settings.data.backdropFrost,
                          grain: state.settings.data.backdropGrain)

            HStack(spacing: 0) {
                if sidebarVisible, !isCompact {
                    SidebarView()
                        .frame(width: CGFloat(state.settings.data.sidebarWidth))
                        .overlay(alignment: .trailing) { resizeHandle }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                EditorContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            #if os(iOS)
            if isCompact, sidebarVisible {
                // The drawer, over a scrim that closes it.
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { state.toggleSidebar() }
                    .transition(.opacity)
                    .zIndex(7)
                SidebarView()
                    .padding(.top, metrics.top)
                    .padding(.bottom, metrics.bottom)
                    .frame(width: min(300, max(240, metrics.width * 0.82)))
                    .frame(maxHeight: .infinity)
                    .background(theme.tint.color.opacity(0.92))
                    .transition(.move(edge: .leading))
                    .zIndex(8)
            }
            #endif

            if !sidebarVisible {
                FloatingSidebarToggle()
                    .padding(.leading, togglePadding.leading)
                    .padding(.top, togglePadding.top)
                    .transition(.opacity)
                    .opacity(state.isQuiet ? 0.08 : 1)
                    .animation(.easeOut(duration: state.isQuiet ? 0.7 : 0.15), value: state.isQuiet)
            }

            if state.showingSearch {
                SearchOverlay()
                    .zIndex(9)
            }

            if state.showingCommandBar {
                CommandBar()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(9)
            }

            if state.showingShortcuts {
                ShortcutSheet()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(10)
            }

            if state.showingSettings {
                SettingsOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(11)
            }
        }
        .animation(.easeOut(duration: 0.16), value: state.showingShortcuts)
        .animation(.easeOut(duration: 0.16), value: state.showingSettings)
        .animation(.easeOut(duration: 0.14), value: state.showingSearch)
        .animation(.easeOut(duration: 0.16), value: state.showingCommandBar)
        .coordinateSpace(name: "glassineRoot")
        #if os(iOS)
        .animation(.easeOut(duration: 0.22), value: sidebarVisible)
        .onAppear { settleCompact() }
        .onChange(of: sizeClass) { _, _ in settleCompact() }
        // The drawer has done its work once something was chosen from it.
        .onChange(of: state.document?.id) { _, _ in closeDrawer() }
        .onChange(of: state.showingGallery) { _, _ in closeDrawer() }
        .onChange(of: state.showingDaily) { _, _ in closeDrawer() }
        #endif
        .windowChrome(theme: theme, floats: state.settings.data.floatOnTop)
        .preferredColorScheme(theme.colorScheme)
        .ignoresSafeArea()
        .sheet(item: $state.pendingPrompt) { prompt in
            NamePromptSheet(prompt: prompt)
                .environmentObject(state)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    #if os(iOS)
    /// A phone starts on the page, not on the drawer.
    private func settleCompact() {
        guard isCompact, !settledCompact else { return }
        settledCompact = true
        if state.settings.data.sidebarVisible { state.settings.data.sidebarVisible = false }
    }

    private func closeDrawer() {
        if isCompact, state.settings.data.sidebarVisible { state.settings.data.sidebarVisible = false }
    }
    #endif

    /// Beside the traffic lights on the Mac; under the status bar on iOS.
    private var togglePadding: (leading: CGFloat, top: CGFloat) {
        #if os(macOS)
        (78, 9)
        #else
        (12, metrics.top + 2)
        #endif
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                handleHovered = inside
                guard dragStartWidth == nil else { return }   // mid-drag the pointer strays; keep the cursor
                if inside { Platform.pushResizeCursor() } else { Platform.popCursor() }
            }
            .gesture(
                // Measured in window space: the handle itself moves with every
                // width change, so its own space would feed back into the drag.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = CGFloat(state.settings.data.sidebarWidth) }
                        let w = (dragStartWidth ?? 250) + value.translation.width
                        let width = Double(min(420, max(190, w)).rounded())
                        if width != state.settings.data.sidebarWidth { state.settings.data.sidebarWidth = width }
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        if !handleHovered { Platform.popCursor() }
                    }
            )
    }
}

/// Appears at the top-left (next to the traffic lights) when the sidebar is hidden.
struct FloatingSidebarToggle: View {
    @EnvironmentObject var state: AppState
    @State private var hovering = false

    var body: some View {
        Button {
            state.toggleSidebar()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(state.theme.text.color)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(state.theme.text.color.opacity(hovering ? 0.10 : 0))
                )
                .opacity(hovering ? 0.95 : 0.35)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Show Sidebar (⌘S)")
    }
}

/// Small sheet used for "New Folder" and "Rename".
struct NamePromptSheet: View {
    @EnvironmentObject var state: AppState
    let prompt: AppState.Prompt
    @State private var text: String = ""
    @FocusState private var focused: Bool

    private var title: String {
        switch prompt {
        case .newFolder: return "New Folder"
        case .rename(_, let isFolder): return isFolder ? "Rename Folder" : "Rename Document"
        }
    }

    private var confirmLabel: String {
        if case .newFolder = prompt { return "Create" }
        return "Rename"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            TextField("Name", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(confirm)
            HStack {
                Spacer()
                Button("Cancel") { state.pendingPrompt = nil }
                    .keyboardShortcut(.cancelAction)
                Button(confirmLabel, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            if case .rename(let path, _) = prompt {
                text = (path as NSString).lastPathComponent
                if !state.library.url(forRelativePath: path).isDirectoryURL {
                    text = (text as NSString).deletingPathExtension
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }

    private func confirm() {
        let name = text.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        switch prompt {
        case .newFolder(let parent):
            state.pendingPrompt = nil
            state.createFolder(named: name, in: parent)
        case .rename(let path, let isFolder):
            state.pendingPrompt = nil
            state.rename(path, to: name, isFolder: isFolder)
        }
    }
}
