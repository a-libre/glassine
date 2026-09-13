import AppKit
import SwiftUI

@main
struct GlassineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        Window("Glassine", id: "main") {
            ContentView()
                .environmentObject(state)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1120, height: 760)
        // Not `.commandsRemoved()`: that takes the standard menus with it —
        // Edit's Undo, Cut, Copy, Paste and Select All, the app menu's Hide
        // and Quit, Window's Minimize and Close — and every key on them.
        // The scene's own Window-menu item is replaced in GlassineCommands.
        .commands { GlassineCommands(state: state) }

    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // A sync round between a folder and a stand-in for a repository,
        // then exit — the merge, tested with no network. See GitHubSync.swift.
        _ = SyncEngine.runHeadlessTestIfRequested()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = nil
        NSWindow.allowsAutomaticWindowTabbing = false
        AppIcon.followAppearance()
        // Whatever the launch itself set is not a change to take back.
        DispatchQueue.main.async { SettingsUndo.shared.manager.removeAllActions() }
        ScreenshotMode.runIfRequested()
        // ⌘\ toggles the sidebar as well as ⌘S; menu items can carry only one shortcut.
        // ⌘F searches the library; the system's Find… item would otherwise claim it.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = event.window, AppDelegate.isMainWindow(window) else { return event }
            let state = AppState.shared
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if state.showingCommandBar {
                switch event.keyCode {
                case 53: state.showingCommandBar = false; return nil
                case 125: state.commandSelection = min(state.commandSelection + 1, max(0, state.filteredCommands.count - 1)); return nil
                case 126: state.commandSelection = max(0, state.commandSelection - 1); return nil
                case 36, 76: state.runCommand(at: state.commandSelection); return nil
                default: break
                }
            }
            if state.showingSearch, event.keyCode == 53 {
                state.searchText = ""
                state.hideSearch()
                return nil
            }
            if state.showingShortcuts, event.keyCode == 53 || (flags == .command && event.charactersIgnoringModifiers == "/") {
                state.showingShortcuts = false
                return nil
            }
            if state.showingSettings {
                // Esc clears a search first, then closes the card.
                if event.keyCode == 53 {
                    if !state.settingsQuery.isEmpty {
                        state.settingsQuery = ""
                    } else {
                        state.showingSettings = false
                    }
                    return nil
                }
                // ⌘F puts the keyboard in the card's own search field.
                if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "f" {
                    state.settingsSearchFocus += 1
                    return nil
                }
                // Tab walks the sections; ⇧Tab walks back. A field being edited
                // inside the card keeps its normal tabbing; the document editor
                // behind the overlay does not get a tab typed into it.
                let fieldEditing = (window.firstResponder as? NSTextView)?.isFieldEditor ?? false
                if event.keyCode == 48, flags.isEmpty || flags == .shift, !fieldEditing {
                    let step = flags == .shift ? -1 : 1
                    let n = SettingsOverlay.Pane.allCases.count
                    state.settingsTab = ((state.settingsTab + step) % n + n) % n
                    return nil
                }
            }
            // ⇥ / ⇧⇥ in Review walk the styles, the way they walk the panes
            // of Settings. The web view would otherwise take the tab for its
            // own focus ring.
            if event.keyCode == 48, flags.isEmpty || flags == .shift, state.inReview,
               !state.showingSettings, !state.showingCommandBar, !state.showingSearch, !state.showingShortcuts {
                state.cycleReviewStyle(by: flags == .shift ? -1 : 1)
                return nil
            }
            // ⌘⇧S: Review, a second key for it beside ⌘↩ — ⌘S shows the
            // sidebar, so the shifted key sits under the same finger.
            if event.charactersIgnoringModifiers?.lowercased() == "s", flags == [.command, .shift] {
                state.toggleReview()
                return nil
            }
            // ⌘Z / ⇧⌘Z: text edits go first; when the focused text has
            // nothing left, the library's own stack takes back file operations —
            // a stray new document, a rename, a move, a duplicate, a trash.
            if event.charactersIgnoringModifiers?.lowercased() == "z",
               flags == .command || flags == [.command, .shift] {
                let redo = flags.contains(.shift)
                // With Settings open, ⌘Z takes back the last change to a
                // setting — from any pane, menu or command — never the text
                // behind the card. A field being edited in the card keeps its own.
                if state.showingSettings {
                    if let tv = window.firstResponder as? NSTextView, tv.isFieldEditor { return event }
                    let undo = SettingsUndo.shared
                    if redo ? undo.canRedo : undo.canUndo {
                        if redo { undo.redo() } else { undo.undo() }
                    }
                    return nil
                }
                if let tv = window.firstResponder as? NSTextView,
                   let text = tv.undoManager, redo ? text.canRedo : text.canUndo {
                    return event
                }
                let lib = state.libraryUndo
                if state.pendingPrompt == nil, redo ? lib.canRedo : lib.canUndo {
                    if redo { lib.redo() } else { lib.undo() }
                    return nil
                }
                return event
            }
            guard flags == .command else {
                // Any ordinary key in the editor counts as typing.
                if !flags.contains(.command), window.firstResponder is GlassineTextView { state.noteTyping() }
                return event
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "\\":
                state.toggleSidebar()
                return nil
            // The three rows at the top of the sidebar, in order, for the left
            // hand alone while the right is on the mouse. ⌘P, ⌘D and ⌘N still work.
            case "1":
                state.showGallery()
                return nil
            case "2":
                state.showDaily()
                return nil
            case "3":
                state.newDocument()
                return nil
            case "f":
                state.focusSearch()
                return nil
            case "k":
                state.toggleCommandBar()
                return nil
            default:
                return event
            }
        }
        // Moving the pointer brings the quiet chrome back.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]) { event in
            AppState.shared.noteMouse()
            return event
        }
        DispatchQueue.main.async { AppDelegate.retireSystemFindShortcut() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { AppDelegate.retireSystemFindShortcut() }
        #if canImport(Sparkle)
        Updater.start(checkingAutomatically: AppState.shared.settings.data.checkForUpdates)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Files handed to the app — Open With in Finder, a drop on the Dock
    /// icon, `open -a Glassine`. The last one named is the one that opens.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last else { return }
        if !AppDelegate.showMainWindow() {
            // The window is not up yet on a launch by file: come back once it is.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.application(application, open: urls)
            }
            return
        }
        AppState.shared.openFile(at: url)
    }

    /// The Edit → Find → Find… item that SwiftUI adds carries ⌘F. Take that away so the
    /// menu bar shows ⌘F next to Search Library only; the item still works by mouse
    /// and Find in Document (⌘⇧F) opens the same find bar.
    static func retireSystemFindShortcut() {
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let sub = item.submenu { walk(sub); continue }
                let isFind = item.action == #selector(NSResponder.performTextFinderAction(_:))
                    || item.action == NSSelectorFromString("performFindPanelAction:")
                if isFind, item.keyEquivalent.lowercased() == "f", item.keyEquivalentModifierMask == [.command] {
                    item.keyEquivalent = ""
                }
            }
        }
        if let main = NSApp.mainMenu { walk(main) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppState.shared.saveEverythingNow()
        return .terminateNow
    }

    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix("main") == true || window.title == "Glassine"
    }

    /// The one window, back on screen after it has been closed: Window →
    /// Glassine, a click on the Dock icon, and any menu command that needs a
    /// window come here. SwiftUI keeps the window when it is closed, so
    /// ordering it front is enough.
    @discardableResult
    static func showMainWindow() -> Bool {
        guard let window = NSApp.windows.first(where: isMainWindow) else { return false }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, AppDelegate.showMainWindow() { return false }
        return true
    }
}

/// Menu bar commands. Everything here is reachable by keyboard.
struct GlassineCommands: Commands {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    /// The window first, then the command: the menus work with the window
    /// closed, and a command that needs the window brings it back.
    private func withWindow(_ action: @escaping () -> Void) {
        if !AppDelegate.showMainWindow() { openWindow(id: "main") }
        action()
    }

    var body: some Commands {
        CommandGroup(replacing: .printItem) { }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { withWindow { state.showingSettings = true } }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .newItem) {
            Button("New Document") { withWindow { state.newDocument() } }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Folder…") { withWindow { state.promptNewFolder() } }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open…") { withWindow { state.openFilePanel() } }
                .keyboardShortcut("o", modifiers: .command)
            Button("Today's Note") { withWindow { state.openTodaysNote() } }
                .keyboardShortcut("d", modifiers: [.command, .option])
            Divider()
            Button("Save Now") { state.document?.save() }
                .disabled(state.document == nil)
            Button("Rename…") {
                if let rel = state.document?.relativePath { state.promptRename(rel, isFolder: false) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(state.document == nil || state.looseDocument != nil)
            Button("Duplicate") {
                if let rel = state.document?.relativePath { state.duplicate(rel) }
            }
            .disabled(state.document == nil || state.looseDocument != nil)
            Button("Add to Library") { state.addLooseDocumentToLibrary() }
                .disabled(state.looseDocument == nil)
            Button(state.currentDocumentIsShelved ? "Unshelve" : "Shelve") { state.toggleShelvedCurrentDocument() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(state.document == nil || state.looseDocument != nil)
            Button("Move to Trash") { state.trashCurrentDocument() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(state.document == nil || state.looseDocument != nil)
            Divider()
            Button("Export as PDF…") { state.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(state.document == nil)
            Divider()
            Button("Reveal Document in Finder") { state.revealCurrentDocument() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state.document == nil)
            Button("Reveal Library in Finder") { state.revealLibrary() }
        }

        // Window → Glassine: the window itself, for after it has been closed.
        // It stands in for the item SwiftUI would put here for the scene.
        CommandGroup(replacing: .singleWindowList) {
            Button("Glassine") { withWindow { } }
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Document as Markdown") { state.copyCurrentDocument(asMarkdown: true) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(state.document == nil)
            Button("Copy Document as Rich Text") { state.copyCurrentDocument(asMarkdown: false) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(state.document == nil)
            Divider()
            Button("Find in Document…") { showFindBar() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(state.document == nil || state.galleryOnScreen || state.reviewMode)
        }

        CommandMenu("Format") {
            Button("Bold") { send(#selector(GlassineTextView.markdownBold(_:))) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { send(#selector(GlassineTextView.markdownItalic(_:))) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Inline Code") { send(#selector(GlassineTextView.markdownCode(_:))) }
                .keyboardShortcut("e", modifiers: .command)
            Button("Strikethrough") { send(#selector(GlassineTextView.markdownStrike(_:))) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Link") { send(#selector(GlassineTextView.markdownLink(_:))) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Chip") { send(#selector(GlassineTextView.markdownChip(_:))) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("Heading 1") { send(#selector(GlassineTextView.markdownHeading1(_:))) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Heading 2") { send(#selector(GlassineTextView.markdownHeading2(_:))) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Heading 3") { send(#selector(GlassineTextView.markdownHeading3(_:))) }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button("Body Text") { send(#selector(GlassineTextView.markdownClearHeading(_:))) }
                .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
            Button("Toggle Task") { send(#selector(GlassineTextView.markdownToggleTask(_:))) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button(state.settings.data.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") { state.toggleSidebar() }
                .keyboardShortcut("s", modifiers: .command)
            Button("All Documents") { withWindow { state.showGallery() } }
                .keyboardShortcut("p", modifiers: .command)
            Button("Search Library") { withWindow { state.focusSearch() } }
                .keyboardShortcut("f", modifiers: .command)
            Button("Command Bar") { withWindow { state.toggleCommandBar() } }
                .keyboardShortcut("k", modifiers: .command)
            Button("Timelapse") { withWindow { state.showDaily() } }
                .keyboardShortcut("d", modifiers: .command)
            Button(state.reviewMode && !state.showingGallery ? "Leave Review" : "Review") { state.toggleReview() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(state.document == nil)
            Picker("Review Style", selection: Binding(
                get: { state.settings.data.reviewStyle },
                set: { state.settings.data.reviewStyle = $0 }
            )) {
                ForEach(ReviewStyle.allCases) { s in Text(s.label).tag(s) }
            }
            Divider()
            Toggle("Typewriter Scrolling", isOn: Binding(
                get: { state.settings.data.typewriterMode },
                set: { state.settings.data.typewriterMode = $0 }
            ))
            .keyboardShortcut("t", modifiers: [.command, .control])
            Toggle("Focus Mode", isOn: Binding(
                get: { state.settings.data.focusMode },
                set: { state.settings.data.focusMode = $0 }
            ))
            .keyboardShortcut("f", modifiers: [.command, .control])
            Toggle("Hide Markdown Syntax", isOn: Binding(
                get: { state.settings.data.hideSyntax },
                set: { _ in state.toggleHideSyntax() }
            ))
            .keyboardShortcut("m", modifiers: [.command, .control])
            Toggle("Show Counter", isOn: Binding(
                get: { state.settings.data.showCounter },
                set: { state.settings.data.showCounter = $0 }
            ))
            Toggle("Float on Top", isOn: Binding(
                get: { state.settings.data.floatOnTop },
                set: { _ in state.toggleFloating() }
            ))
            .keyboardShortcut(".", modifiers: .command)
            Divider()
            Picker("Theme", selection: Binding(
                get: { state.theme.id },
                set: { state.chooseTheme($0) }
            )) {
                ForEach(state.themes.all) { t in
                    Text(t.name).tag(t.id)
                }
            }
            Picker("Backdrop", selection: Binding(
                get: { state.settings.data.backdrop },
                set: { state.settings.data.backdrop = $0 }
            )) {
                ForEach(state.backdrops.all) { b in Text(b.name).tag(b.id) }
            }
            Divider()
            Button("Bigger Text") { state.adjustFontSize(by: 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { state.adjustFontSize(by: -1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Default Text Size") { state.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
        }

        CommandGroup(replacing: .help) {
            Button("Glassine Shortcuts") { withWindow { state.showingShortcuts.toggle() } }
                .keyboardShortcut("/", modifiers: .command)
            Button("Open Library Folder") { state.revealLibrary() }
            #if canImport(Sparkle)
            Button("Check for Updates…") { Updater.shared.check() }
            #endif
            Divider()
            Button("Copy Debug Info") { state.copyDebugInfo() }
                .keyboardShortcut("d", modifiers: [.command, .option, .shift])
        }
    }

    private func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    /// The editor's find bar. NSTextView reads which action from the sender's tag.
    private func showFindBar() {
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: sender)
    }

}
