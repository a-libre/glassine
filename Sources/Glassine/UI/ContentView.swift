import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var dragStartWidth: CGFloat?
    /// The sidebar's width while its handle is being dragged. It lives here,
    /// not in the settings, until the drag ends: a setting changed on every
    /// frame of a drag had every view in the window redo its body on every
    /// frame, when all that changes is where one edge sits.
    @State private var liveSidebarWidth: CGFloat?
    @State private var handleHovered = false

    private var theme: Theme { state.theme }
    private var sidebarVisible: Bool { state.settings.data.sidebarVisible }
    private var sidebarWidth: CGFloat { liveSidebarWidth ?? CGFloat(state.settings.data.sidebarWidth) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GlassBackdrop(theme: theme, backdrop: state.backdrops.preset(id: state.settings.data.backdrop),
                          drifts: state.settings.data.backdropDrift, frost: state.settings.data.backdropFrost,
                          grain: state.settings.data.backdropGrain)

            HStack(spacing: 0) {
                if sidebarVisible {
                    SidebarView()
                        .frame(width: sidebarWidth)
                        .overlay(alignment: .trailing) { resizeHandle }
                        // While the pages are fanned out the sidebar steps
                        // back with the page, so the fan is the one thing lit.
                        .opacity(state.carousel == nil ? 1 : 0.45)
                        .animation(Motion.quiet(.easeOut(duration: 0.2)), value: state.carousel == nil)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                EditorContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if !sidebarVisible {
                FloatingSidebarToggle()
                    .padding(.leading, 78)
                    .padding(.top, 9)
                    .transition(.opacity)
                    .opacity(state.isQuiet ? 0.08 : 1)
                    .animation(.easeOut(duration: state.isQuiet ? 0.7 : 0.15), value: state.isQuiet)
            }

            if let carousel = state.carousel {
                // The pages belong to the page's side of the window: the fan
                // is centred over the editor, never over the sidebar.
                PageCarouselView(carousel: carousel)
                    // A card that runs past the page's edge dissolves there
                    // rather than being cut off against the sidebar.
                    .mask(
                        HStack(spacing: 0) {
                            if sidebarVisible {
                                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 72)
                            }
                            Color.black
                        }
                        .ignoresSafeArea()
                    )
                    .padding(.leading, sidebarVisible ? sidebarWidth : 0)
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    .zIndex(8)
            }

            if state.showingSearch {
                SearchOverlay()
                    .id(state.searchSession)
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

            if state.showingTour {
                TourView()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(12)
            }

            // A prompt — a name, or "Move to the Trash?" — and anything that
            // went wrong are asked and said on the glass, over the page.
            if let prompt = state.pendingPrompt {
                PromptOverlay(prompt: prompt)
                    .id(prompt.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(13)
            }
            if let message = state.errorMessage {
                ErrorOverlay(message: message)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(14)
            }
        }
        .animation(Motion.quiet(.easeOut(duration: 0.16)), value: state.showingShortcuts)
        .animation(Motion.quiet(.easeOut(duration: 0.16)), value: state.showingSettings)
        .animation(Motion.quiet(.easeOut(duration: 0.22)), value: state.showingTour)
        .animation(Motion.quiet(.easeOut(duration: 0.14)), value: state.showingSearch)
        .animation(Motion.quiet(.easeOut(duration: 0.16)), value: state.showingCommandBar)
        .animation(Motion.quiet(.easeOut(duration: 0.18)), value: state.carousel == nil)
        .animation(Motion.quiet(.easeOut(duration: 0.16)), value: state.pendingPrompt?.id)
        .animation(Motion.quiet(.easeOut(duration: 0.16)), value: state.errorMessage)
        .coordinateSpace(name: "glassineRoot")
        .frame(minWidth: 620, minHeight: 400)
        .background(WindowConfigurator(theme: theme, floats: state.settings.data.floatOnTop))
        .preferredColorScheme(theme.colorScheme)
        .ignoresSafeArea()
        .onChange(of: state.pendingPrompt?.id) { _, id in handOverKeyboard(toPrompt: id != nil) }
        .onChange(of: state.errorMessage) { _, message in handOverKeyboard(toPrompt: message != nil) }
    }

    /// While a prompt is up the page's editor gives up the keyboard, so
    /// Return answers the prompt rather than starting a new line, and a
    /// stray word does not land on the page behind. The editor takes it back
    /// when the prompt goes.
    private func handOverKeyboard(toPrompt up: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        if up {
            if window.firstResponder is GlassineTextView { window.makeFirstResponder(nil) }
        } else if state.pendingPrompt == nil, state.errorMessage == nil, let editor = GlassineTextView.current, editor.window === window {
            window.makeFirstResponder(editor)
        }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                handleHovered = inside
                guard dragStartWidth == nil else { return }   // mid-drag the pointer strays; keep the cursor
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                // Measured in window space: the handle itself moves with every
                // width change, so its own space would feed back into the drag.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = CGFloat(state.settings.data.sidebarWidth) }
                        let w = (dragStartWidth ?? 250) + value.translation.width
                        let width = min(420, max(190, w)).rounded()
                        if width != liveSidebarWidth { liveSidebarWidth = width }
                    }
                    .onEnded { _ in
                        // Written down once, as the drag ends.
                        if let width = liveSidebarWidth, Double(width) != state.settings.data.sidebarWidth {
                            state.settings.data.sidebarWidth = Double(width)
                        }
                        liveSidebarWidth = nil
                        dragStartWidth = nil
                        if !handleHovered { NSCursor.pop() }
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
