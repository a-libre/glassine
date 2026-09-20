#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// Menu bar commands. Everything here is reachable by keyboard — on the Mac
/// from the menu bar, on an iPad from its menu bar and the ⌘-hold sheet, and on
/// an iPhone from whatever keyboard is attached to it. What only a Mac has (a
/// window to bring back, Finder, panels, floating above other apps) is fenced.
struct GlassineCommands: Commands {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    /// The window first, then the command: the menus work with the window
    /// closed, and a command that needs the window brings it back.
    private func withWindow(_ action: @escaping () -> Void) {
        #if os(macOS)
        if !AppDelegate.showMainWindow() { openWindow(id: "main") }
        #endif
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
            #if os(macOS)
            Button("Open…") { withWindow { state.openFilePanel() } }
                .keyboardShortcut("o", modifiers: .command)
            #endif
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
            #if os(macOS)
            Divider()
            Button("Export as PDF…") { state.exportPDF() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(state.document == nil)
            Divider()
            Button("Reveal Document in Finder") { state.revealCurrentDocument() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(state.document == nil)
            Button("Reveal Library in Finder") { state.revealLibrary() }
            #endif
        }

        #if os(macOS)
        // Window → Glassine: the window itself, for after it has been closed.
        // It stands in for the item SwiftUI would put here for the scene.
        CommandGroup(replacing: .singleWindowList) {
            Button("Glassine") { withWindow { } }
        }
        #endif

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
            Toggle("Review Beside the Editor", isOn: Binding(
                get: { state.settings.data.reviewBeside },
                set: { _ in state.toggleReviewBeside() }
            ))
            .keyboardShortcut(.return, modifiers: [.command, .shift])
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
            #if os(macOS)
            Toggle("Float on Top", isOn: Binding(
                get: { state.settings.data.floatOnTop },
                set: { _ in state.toggleFloating() }
            ))
            .keyboardShortcut(".", modifiers: .command)
            #endif
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
            #if os(macOS)
            Button("Open Library Folder") { state.revealLibrary() }
            #endif
            #if canImport(Sparkle)
            Button("Check for Updates…") { Updater.shared.check() }
            #endif
            #if os(macOS)
            if Distribution.isDemo {
                Divider()
                Button("Reset Demo Library") { withWindow { state.resetDemoLibrary() } }
                Button("Window at 1440 × 900") { withWindow { DemoLibrary.placeWindowForPictures() } }
            }
            #endif
            Divider()
            Button("Copy Debug Info") { state.copyDebugInfo() }
                .keyboardShortcut("d", modifiers: [.command, .option, .shift])
        }
    }

    /// To whatever has the keyboard — the editor, when it is the editor.
    private func send(_ selector: Selector) {
        #if os(macOS)
        NSApp.sendAction(selector, to: nil, from: nil)
        #else
        UIApplication.shared.sendAction(selector, to: nil, from: nil, for: nil)
        #endif
    }

    /// The editor's find bar.
    private func showFindBar() {
        #if os(macOS)
        // NSTextView reads which action from the sender's tag.
        let sender = NSMenuItem()
        sender.tag = NSTextFinder.Action.showFindInterface.rawValue
        NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: sender)
        #else
        send(#selector(GlassineTextView.findInDocument(_:)))
        #endif
    }

}
