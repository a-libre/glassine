import XCTest

/// An attached keyboard, on iPhone and iPad alike: the Mac's shortcuts, pressed
/// as keys, doing what they do on the Mac.
final class KeyboardTests: XCTestCase {
    private let libraryPath = "/tmp/glassine-uitest-library-keys"

    private func launch(trace: String = "/tmp/glassine-uitest-keys.log") -> XCUIApplication {
        try? FileManager.default.removeItem(atPath: libraryPath)
        try? FileManager.default.createDirectory(atPath: libraryPath, withIntermediateDirectories: true)
        try? "# Keys\n\nA line to work on: word\n\n- a list item".write(toFile: libraryPath + "/Keys.md", atomically: true, encoding: .utf8)
        let json = "{\"sidebarVisible\":false,\"typewriterMode\":false,\"focusMode\":false,\"caretTricks\":false,"
            + "\"backdropDrift\":false,\"libraryPath\":\"\(libraryPath)\",\"lastOpenedDocument\":\"Keys.md\"}"
        let app = XCUIApplication()
        app.launchArguments = ["-glassine.launchSettings", Data(json.utf8).base64EncodedString(), "-glassine.launchCaret", "100000", "-glassine.trace", trace]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15))
        sleep(2)
        // The first synthesized key "attaches" the keyboard and loses its modifiers
        // on the way; a Shift press alone takes that fall.
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: .shift)
        sleep(1)
        return app
    }

    private func editorText(_ app: XCUIApplication) -> String { app.textViews.firstMatch.value as? String ?? "" }

    func testFormatKeysInTheEditor() {
        let app = launch()
        app.typeText(" and ")
        app.typeKey("b", modifierFlags: .command)          // **bold** with "bold" selected
        app.typeText("strong")                             // typed over the placeholder
        XCTAssertTrue(editorText(app).hasSuffix("- a list item and **strong**"), editorText(app))
        app.typeKey("b", modifierFlags: .command)          // at the end of the span: steps out past the marks
        app.typeText(" ")
        app.typeKey("i", modifierFlags: .command)
        app.typeText("soft")
        XCTAssertTrue(editorText(app).contains("**strong** *soft*"), editorText(app))
        app.typeKey("l", modifierFlags: [.command, .shift]) // the bullet gains a box
        XCTAssertTrue(editorText(app).contains("- [ ] a list item"), editorText(app))
        app.typeKey("\t", modifierFlags: [])                // Tab nests the item
        XCTAssertTrue(editorText(app).contains("    - [ ] a list item"), editorText(app))
        app.typeKey("\t", modifierFlags: .shift)            // Shift-Tab brings it back
        XCTAssertFalse(editorText(app).contains("    - [ ]"), editorText(app))
        app.typeKey("i", modifierFlags: .command)           // at the end of the span: steps out past the mark
        app.typeText("\n")                                  // Return at the end of the item continues the list
        XCTAssertTrue(editorText(app).hasSuffix("\n- [ ] "), editorText(app))
    }

    /// Esc is not among these: a UI test's Escape never reaches an iOS app in the
    /// simulator (neither as a press nor as a key command), so overlays are put
    /// away here by the keys that toggle them. Esc is for a hand to try.
    func testAppKeys() {
        let app = launch(trace: "/tmp/glassine-uitest-appkeys.log")
        let commandField = app.textFields["Type a command"]
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(commandField.waitForExistence(timeout: 3), "⌘K did not open the command bar")
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(commandField.waitForNonExistence(timeout: 3), "⌘K did not close the command bar")

        let timelapse = app.staticTexts["Timelapse"]        // a row only the sidebar has
        XCTAssertFalse(timelapse.exists, "the sidebar should start hidden")
        app.typeKey("\\", modifierFlags: .command)
        XCTAssertTrue(timelapse.waitForExistence(timeout: 3), "⌘\\ did not show the sidebar")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(timelapse.waitForNonExistence(timeout: 3), "⌘S did not hide the sidebar")

        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Shortcuts"].waitForExistence(timeout: 3), "⌘/ did not show the shortcut sheet")
        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Shortcuts"].waitForNonExistence(timeout: 3), "⌘/ did not put the shortcut sheet away")

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(app.textFields["Search"].waitForExistence(timeout: 3), "⌘1 did not open All Documents")

        // As on the Mac, search opens over the cards and stays until Esc.
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.textFields["Search everything"].waitForExistence(timeout: 3), "⌘F did not open search")

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Library"].waitForExistence(timeout: 3), "⌘, did not open Settings")
    }
}
