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
