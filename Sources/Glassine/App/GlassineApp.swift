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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = nil
        NSWindow.allowsAutomaticWindowTabbing = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if AppState.shared.settings.data.checkForUpdates {
                UpdateChecker.checkAutomaticallyIfDue()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppState.shared.saveEverythingNow()
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("main") == true || window.title == "Glassine" {
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
        CommandGroup(replacing: .newItem) {
            Button("New Document") { state.newDocument() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Folder…") { state.promptNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Save Now") { state.document?.save() }
                .keyboardShortcut("s", modifiers: .command)
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
                .keyboardShortcut("\\", modifiers: .command)
            Button(state.showingGallery ? "Back to Document" : "All Documents") { state.toggleGallery() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
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
                get: { state.settings.data.themeID },
                set: { state.settings.data.themeID = $0 }
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
            Button("Glassine Shortcuts") { showShortcuts() }
            Button("Open Library Folder") { state.revealLibrary() }
            Button("Check for Updates…") { UpdateChecker.check(userInitiated: true) }
            Divider()
            Button("Copy Debug Info") { send(#selector(GlassineTextView.copyDebugInfo(_:))) }
                .keyboardShortcut("d", modifiers: [.command, .option, .shift])
        }
    }

    private func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }

    private func showShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Glassine Shortcuts"
        alert.informativeText = """
        ⌘N  New document        ⌘⇧N  New folder
        ⌘\\  Toggle sidebar      ⌘,   Settings
        ⌃⌘T Typewriter          ⌃⌘F  Focus mode
        ⌘B  Bold                ⌘I   Italic
        ⌘E  Inline code         ⌘K   Link
        ⌘⌥1–3 Heading level     ⌘⌥0  Body text
        ⌘⇧L Toggle task         ⌘F   Find
        ⌘R  Rename              ⌘⌫   Move to Trash
        ⌘+ / ⌘−  Text size
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
