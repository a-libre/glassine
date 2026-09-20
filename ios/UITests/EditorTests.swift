import XCTest

/// The editor under real input: XCUITest's keys travel UIKit's own keyboard
/// path, the one a person's do. The app traces where the page is after every
/// keystroke and every move of the scroll view (`-glassine.trace`), and the
/// tests read that trace.
final class EditorTests: XCTestCase {
    private let tracePath = "/tmp/glassine-uitest-trace.log"
    private let libraryPath = "/tmp/glassine-uitest-library"

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.removeItem(atPath: tracePath)
        try? FileManager.default.createDirectory(atPath: libraryPath, withIntermediateDirectories: true)
        let page = "# Trace\n\nA first paragraph, so the page is not empty.\n\nThe line being typed: "
        try? page.write(toFile: libraryPath + "/Trace.md", atomically: true, encoding: .utf8)
        // Several screens long, so the line being typed is a long way down the page.
        let paragraph = "A paragraph of ordinary length, the kind a page is mostly made of, long enough to wrap onto a second line and a third on a narrow screen."
        let long = "# Long\n\n" + (1...45).map { "\($0). \(paragraph)" }.joined(separator: "\n\n") + "\n\nThe line being typed: "
        try? long.write(toFile: libraryPath + "/Long.md", atomically: true, encoding: .utf8)
    }

    private func launch(settings extra: String, document: String = "Trace.md") -> XCUIApplication {
        let json = "{\"fontSize\":17,\"sidebarVisible\":false,\"themeID\":\"dusk\",\"appearanceMode\":\"fixed\","
            + "\"backdropDrift\":false,\"caretTricks\":false,\"libraryPath\":\"\(libraryPath)\","
            + "\"lastOpenedDocument\":\"\(document)\",\(extra)}"
        let app = XCUIApplication()
        app.launchArguments = ["-glassine.launchSettings", Data(json.utf8).base64EncodedString(),
                               "-glassine.launchCaret", "100000", "-glassine.trace", tracePath]
        // TEST_RUNNER_GLASSINE_NC=1 ios/test-sim.sh … runs the editor the way UIKit sets it up.
        if ProcessInfo.processInfo.environment["GLASSINE_NC"] == "1" { app.launchArguments.append("-glassine.nonContiguousLayout") }
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15))
        sleep(2)
        return app
    }

    /// (time, event, offset, size, caretY, caretOnScreen)
    private func trace() -> [(event: String, offset: Double, caretOnScreen: Double, caretY: Double)] {
        guard let text = try? String(contentsOfFile: tracePath, encoding: .utf8) else { return [] }
        func value(_ key: String, in line: String) -> Double {
            guard let r = line.range(of: key + "=") else { return .nan }
            return Double(line[r.upperBound...].trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "") ?? .nan
        }
        return text.split(separator: "\n").map { line in
            let l = String(line)
            let event = l.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first.map(String.init) ?? ""
            return (event, value("offset", in: l), value("caretOnScreen", in: l), value("caretY", in: l))
        }
    }

    /// Typewriter mode: while the caret stays on one line the page does not
    /// move at all, and when a line wraps the page moves once, by that line,
    /// and the caret's line ends up where it was — the text scrolls under a
    /// caret that stays put.
    private func typeAndCheck(_ app: XCUIApplication) {
        for word in "typing along one line and then on to the next so that it wraps around twice over to see what the page does".split(separator: " ") {
            app.typeText(word + " ")
        }
        sleep(1)
        let all = trace().filter { !$0.offset.isNaN }
        XCTAssertGreaterThan(all.count, 10, "no trace at \(tracePath)")
        // From the first keystroke on: the launch and the keyboard's arrival are their own story.
        guard let first = all.firstIndex(where: { $0.event == "didChange" }) else { return XCTFail("nothing was typed") }
        let rows = Array(all[first...])
        var moves = 0, bounces = 0
        // Where things stood before the first key: the page there, the caret's line there.
        var last = all[first - 1].offset, caretYAtLastMove = all[first - 1].caretY
        for row in rows where row.event == "offset" {
            moves += 1
            // A move while the caret is on the same line of text is a bounce.
            if abs(row.caretY - caretYAtLastMove) < 1, abs(row.offset - last) > 0.5 { bounces += 1 }
            last = row.offset
            caretYAtLastMove = row.caretY
        }
        let began = all[first - 1].caretOnScreen, settled = rows.last!.caretOnScreen
        print("TRACE moves=\(moves) bounces=\(bounces) caretOnScreen \(began) → \(settled)")
        XCTAssertEqual(bounces, 0, "the page moved while the caret stayed on its line")
        XCTAssertEqual(settled, began, accuracy: 1.5, "the caret's line drifted on the screen")
    }

    /// Far down a long page, through a rule and out the other side: the caret's
    /// line never leaves the middle by more than the line a wrap or a Return
    /// adds, and the page never moves while the caret stays on its line.
    func testTypewriterThroughARuleOnALongPage() {
        let app = launch(settings: "\"typewriterMode\":true,\"focusMode\":true", document: "Long.md")
        for piece in ["some ", "words ", "before ", "the ", "rule, ", "enough ", "of ", "them ", "to ", "wrap ", "the ", "line ", "once ", "over.",
                      "\n", "\n", "-", "-", "-", "\n", "\n",
                      "And ", "then ", "on ", "the ", "far ", "side ", "of ", "it ", "more ", "words, ", "enough ", "again ", "to ", "wrap ", "around ", "once ", "more."] {
            app.typeText(piece)
        }
        sleep(1)
        let all = trace().filter { !$0.offset.isNaN }
        guard let first = all.firstIndex(where: { $0.event == "didChange" }) else { return XCTFail("nothing was typed") }
        let began = all[first - 1].caretOnScreen
        let rows = Array(all[first...])
        var moves = 0, bounces = 0, worst = 0.0
        var last = all[first - 1].offset, caretYAtLastMove = all[first - 1].caretY
        for row in rows where row.event == "offset" {
            moves += 1
            if abs(row.caretY - caretYAtLastMove) < 1, abs(row.offset - last) > 0.5 { bounces += 1 }
            worst = max(worst, abs(row.caretOnScreen - began))
            last = row.offset
            caretYAtLastMove = row.caretY
        }
        let sizes = Set(rows.filter { $0.event == "size" }.map { $0.offset }).count
        print("TRACE long page: moves=\(moves) bounces=\(bounces) worst=\(worst) sizeEvents=\(rows.filter { $0.event == "size" }.count) offsetsAtSize=\(sizes) caretOnScreen \(began) → \(rows.last!.caretOnScreen)")
        XCTAssertEqual(bounces, 0, "the page moved while the caret stayed on its line")
        XCTAssertLessThan(worst, 8, "the caret's line left the middle of the page")
        XCTAssertEqual(rows.last!.caretOnScreen, began, accuracy: 1.5, "the caret's line drifted on the screen")
    }

    func testTypewriterHoldsStillWhileTyping() {
        typeAndCheck(launch(settings: "\"typewriterMode\":true,\"focusMode\":true,\"hideSyntax\":false"))
    }

    /// The same, as the app comes out of the box: the sidebar showing, the
    /// backdrop drifting, the caret's tricks on.
    func testTypewriterOnFirstLaunchSettings() {
        let json = "{\"libraryPath\":\"\(libraryPath)\",\"lastOpenedDocument\":\"Trace.md\"}"
        let app = XCUIApplication()
        app.launchArguments = ["-glassine.launchSettings", Data(json.utf8).base64EncodedString(),
                               "-glassine.launchCaret", "100000", "-glassine.trace", tracePath]
        app.launch()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15))
        sleep(2)
        typeAndCheck(app)
    }
}
