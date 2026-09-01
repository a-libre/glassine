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
        .commands { GlassineCommands(state: state) }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = nil
        NSWindow.allowsAutomaticWindowTabbing = false
        // ⌘\ toggles the sidebar as well as ⌘S; menu items can carry only one shortcut.
        // ⌘F searches the library; the system's Find… item would otherwise claim it.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = event.window, AppDelegate.isMainWindow(window) else { return event }
            let state = AppState.shared
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if state.showingShortcuts, event.keyCode == 53 || (flags == .command && event.charactersIgnoringModifiers == "/") {
                state.showingShortcuts = false
                return nil
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
            case "f":
                state.focusSearch()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if AppState.shared.settings.data.checkForUpdates {
                UpdateChecker.checkAutomaticallyIfDue()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows where AppDelegate.isMainWindow(window) {
                window.makeKeyAndOrderFront(nil)
                return false
            }
        }
        return true
    }
}

/// Menu bar commands. Everything here is reachable by keyboard.
struct GlassineCommands: Commands {
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .printItem) { }

        CommandGroup(replacing: .newItem) {
            Button("New Document") { state.newDocument() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Folder…") { state.promptNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Today's Note") { state.openTodaysNote() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Button("Save Now") { state.document?.save() }
                .disabled(state.document == nil)
            Button("Rename…") {
                if let rel = state.document?.relativePath { state.promptRename(rel, isFolder: false) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(state.document == nil)
            Button("Duplicate") {
                if let rel = state.document?.relativePath { state.duplicate(rel) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(state.document == nil)
            Button("Move to Trash") { state.trashCurrentDocument() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(state.document == nil)
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
                .keyboardShortcut("k", modifiers: .command)
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
            Button(state.showingGallery ? "Back to Document" : "All Documents") { state.toggleGallery() }
                .keyboardShortcut("p", modifiers: .command)
            Button("Search Library") { state.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
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
            Toggle("Show Counter", isOn: Binding(
                get: { state.settings.data.showCounter },
                set: { state.settings.data.showCounter = $0 }
            ))
            Divider()
            Picker("Theme", selection: Binding(
                get: { state.theme.id },
                set: { state.chooseTheme($0) }
            )) {
                ForEach(state.themes.all) { t in
                    Text(t.name).tag(t.id)
                }
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
            Button("Glassine Shortcuts") { state.showingShortcuts.toggle() }
                .keyboardShortcut("/", modifiers: .command)
            Button("Open Library Folder") { state.revealLibrary() }
            Button("Check for Updates…") { UpdateChecker.check(userInitiated: true) }
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
