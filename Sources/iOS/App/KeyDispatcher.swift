import UIKit

/// What an attached keyboard's keys do — the Mac's menu shortcuts
/// (Shared/App/GlassineCommands.swift) and the extras its key monitor carries
/// (Sources/Mac/App/GlassineApp.swift), in that monitor's order: whatever is
/// on top of the page gets the first say. Returns true when the key was used.
enum KeyDispatcher {
    private static var state: AppState { AppState.shared }
    private static var editor: GlassineTextView? {
        guard let editor = GlassineTextView.current, editor.window != nil else { return nil }
        return editor
    }
    /// The editor, when it is the one being typed in.
    private static var activeEditor: GlassineTextView? { editor?.isFirstResponder == true ? editor : nil }

    static func handle(_ key: UIKey) -> Bool {
        let flags = key.modifierFlags.intersection([.command, .shift, .alternate, .control])
        let code = key.keyCode
        let input = character(for: key)
        let handled = dispatch(input: input, code: code, flags: flags)
        #if targetEnvironment(simulator)
        if !flags.isEmpty || handled {
            SimulatorScript.log("key '\(input)' code=\(code.rawValue) flags=\(flags.rawValue) → \(handled ? "taken" : "passed on")")
        }
        #endif
        if !handled, flags.isDisjoint(with: [.command, .control]), activeEditor != nil { state.noteTyping() }
        return handled
    }

    /// The key's own character, whatever Option or Shift would make of it.
    private static func character(for key: UIKey) -> String {
        switch key.keyCode {
        case .keyboard1: return "1"
        case .keyboard2: return "2"
        case .keyboard3: return "3"
        case .keyboard0: return "0"
        case .keyboardEqualSign: return "="
        case .keyboardHyphen: return "-"
        case .keyboardSlash: return "/"
        case .keyboardBackslash: return "\\"
        case .keyboardComma: return ","
        case .keyboardPeriod: return "."
        default: break
        }
        if (UIKeyboardHIDUsage.keyboardA.rawValue...UIKeyboardHIDUsage.keyboardZ.rawValue).contains(key.keyCode.rawValue) {
            let scalar = UnicodeScalar(UInt8(97 + key.keyCode.rawValue - UIKeyboardHIDUsage.keyboardA.rawValue))
            return String(Character(scalar))
        }
        return key.charactersIgnoringModifiers.lowercased()
    }

    /// Esc: whatever is on top of the page goes first; with nothing on top, the
    /// editor backs out to the cards.
    @discardableResult
    static func escape() -> Bool {
        if state.showingCommandBar { state.showingCommandBar = false; return true }
        if state.showingSearch { state.searchText = ""; state.hideSearch(); return true }
        if state.showingShortcuts { state.showingShortcuts = false; return true }
        if state.showingSettings {
            // Esc clears a search first, then closes the card.
            if !state.settingsQuery.isEmpty { state.settingsQuery = "" } else { state.showingSettings = false }
            return true
        }
        #if targetEnvironment(simulator)
        SimulatorScript.log("escape with nothing on top")
        #endif
        return false
    }

    private static func dispatch(input: String, code: UIKeyboardHIDUsage, flags: UIKeyModifierFlags) -> Bool {
        let escape = code == .keyboardEscape
        let tab = code == .keyboardTab
        let returnKey = code == .keyboardReturnOrEnter || code == .keypadEnter
        let plain = flags.isEmpty
        let command: UIKeyModifierFlags = .command
        let commandShift: UIKeyModifierFlags = [.command, .shift]
        let commandOption: UIKeyModifierFlags = [.command, .alternate]
        let commandControl: UIKeyModifierFlags = [.command, .control]

        // What is on top of the page first.
        if escape, plain, Self.escape() { return true }
        if state.showingCommandBar {
            if code == .keyboardDownArrow { state.commandSelection = min(state.commandSelection + 1, max(0, state.filteredCommands.count - 1)); return true }
            if code == .keyboardUpArrow { state.commandSelection = max(0, state.commandSelection - 1); return true }
            if returnKey { state.runCommand(at: state.commandSelection); return true }
        }
        if state.showingShortcuts, flags == command, input == "/" { state.showingShortcuts = false; return true }
        if state.showingSettings {
            if flags == command, input == "f" { state.settingsSearchFocus += 1; return true }
            // Tab walks the sections; a field being edited in the card keeps its own tabbing.
            if tab, plain || flags == .shift, !(UIResponder.first is UITextField) {
                let n = SettingsOverlay.Pane.allCases.count
                state.settingsTab = ((state.settingsTab + (flags == .shift ? -1 : 1)) % n + n) % n
                return true
            }
        }
        let overlay = state.showingCommandBar || state.showingSearch || state.showingShortcuts || state.showingSettings
        // ⇥ / ⇧⇥ in Review walk the styles, the way they walk the panes of Settings.
        if tab, plain || flags == .shift, state.inReview, !overlay {
            state.cycleReviewStyle(by: flags == .shift ? -1 : 1)
            return true
        }
        // Esc in the editor: back out to the cards (the text view's own key command does the same).
        guard flags.contains(.command) else { return false }

        let hasDocument = state.document != nil
        let inLibrary = hasDocument && state.looseDocument == nil
        let canEdit = activeEditor != nil && !overlay

        switch (input, flags) {
        // The sidebar's rows, the sidebar itself, Review's second key.
        case ("\\", command), ("s", command): state.toggleSidebar()
        case ("1", command), ("p", command): state.showGallery()
        case ("2", command), ("d", command): state.showDaily()
        case ("3", command), ("n", command): state.newDocument()
        case ("s", commandShift): if hasDocument { state.toggleReview() } else { return false }
        // File
        case (",", command): state.showingSettings = true
        case ("n", commandShift): state.promptNewFolder()
        case ("d", commandOption): state.openTodaysNote()
        case ("r", command):
            guard inLibrary, let rel = state.document?.relativePath else { return false }
            state.promptRename(rel, isFolder: false)
        case ("c", commandShift): if hasDocument { state.copyCurrentDocument(asMarkdown: true) } else { return false }
        case ("c", commandOption): if hasDocument { state.copyCurrentDocument(asMarkdown: false) } else { return false }
        // View
        case ("f", command): state.focusSearch()
        case ("k", command): state.toggleCommandBar()
        case ("/", command): state.showingShortcuts.toggle()
        case ("f", commandShift):
            guard hasDocument, !state.galleryOnScreen, !state.reviewMode, let editor else { return false }
            editor.findInDocument(nil)
        case ("t", commandControl): state.settings.data.typewriterMode.toggle()
        case ("f", commandControl): state.settings.data.focusMode.toggle()
        case ("m", commandControl): state.toggleHideSyntax()
        case ("=", command), ("=", commandShift): state.adjustFontSize(by: 1)
        case ("-", command): state.adjustFontSize(by: -1)
        case ("0", command): state.resetFontSize()
        case ("d", [.command, .alternate, .shift]): state.copyDebugInfo()
        default:
            if returnKeyMatches(code, flags, command) {
                guard hasDocument else { return false }
                state.toggleReview()
            } else if returnKeyMatches(code, flags, commandShift) {
                guard hasDocument else { return false }
                state.toggleReviewBeside()
            } else if canEdit, let editor = activeEditor {
                return format(editor, input: input, flags: flags)
            } else {
                return false
            }
        }
        return true
    }

    private static func returnKeyMatches(_ code: UIKeyboardHIDUsage, _ flags: UIKeyModifierFlags, _ wanted: UIKeyModifierFlags) -> Bool {
        (code == .keyboardReturnOrEnter || code == .keypadEnter) && flags == wanted
    }

    /// The Format menu, for the text being typed in.
    private static func format(_ editor: GlassineTextView, input: String, flags: UIKeyModifierFlags) -> Bool {
        let command: UIKeyModifierFlags = .command
        let commandShift: UIKeyModifierFlags = [.command, .shift]
        let commandOption: UIKeyModifierFlags = [.command, .alternate]
        switch (input, flags) {
        case ("b", command): editor.markdownBold(nil)
        case ("i", command): editor.markdownItalic(nil)
        case ("e", command): editor.markdownCode(nil)
        case ("x", commandShift): editor.markdownStrike(nil)
        case ("k", commandShift): editor.markdownLink(nil)
        case ("h", commandShift): editor.markdownChip(nil)
        case ("1", commandOption): editor.markdownHeading1(nil)
        case ("2", commandOption): editor.markdownHeading2(nil)
        case ("3", commandOption): editor.markdownHeading3(nil)
        case ("0", commandOption): editor.markdownClearHeading(nil)
        case ("l", commandShift): editor.markdownToggleTask(nil)
        default: return false
        }
        return true
    }
}

extension UIResponder {
    private static weak var found: UIResponder?

    /// Whatever has the keyboard right now.
    static var first: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(reportAsFirst(_:)), to: nil, from: nil, for: nil)
        return found
    }

    @objc private func reportAsFirst(_ sender: Any?) { UIResponder.found = self }
}
