import XCTest

/// The strip of chips under the composer — what the capture grammar is about to
/// take, and the tap that hands one back.
///
/// **A UI test because the claim is that the reading is *visible* before it
/// happens.** `CaptureParseTests` proves the grammar reads the line and
/// `CaptureCommitTests` proves the card arrives wearing it, and both would pass
/// unchanged if the strip never drew — which would leave a field that silently
/// rewrites what somebody typed, the one thing the design says it must not be.
/// Only a real composer with a real keyboard in front of it can say whether the
/// chips appeared, whether they are named, and whether pressing one does
/// anything.
///
/// **iPad, because the phone has no inline composer at all** and the desk is not
/// a simulator. The header's `+` opens the Inbox's composer — see
/// `UITests/PadCaptureTests`, which is what proves that button reaches this
/// field in the first place.
///
///     xcodebuild test -scheme CardstockUITests \
///       -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
///       -only-testing:CardstockUITests/CaptureGrammarTests
final class CaptureGrammarTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A composer with `line` typed into it.
    private func composing(_ line: String) throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the inline composer is the iPad's and the desk's; the phone opens a sheet"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-CardstockSkipFirstRun", "YES"]
        app.launch()

        let capture = app.buttons["New task"]
        XCTAssertTrue(capture.waitForExistence(timeout: 20), "no capture button on the board header")
        capture.tap()

        let field = app.textFields["Task title, then ⏎"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the + did not open a composer")
        field.tap()
        field.typeText(line)
        return app
    }

    /// `Bug` is one of the five seeded labels, so `#bug` has something to match.
    /// The due chip is matched on its opening words rather than in full: it
    /// names the resolved day, which is a different date every time this runs.
    func testTheStripNamesEverythingItIsAboutToTake() throws {
        let app = try composing("Ship the beta next friday !high #bug")

        let label = app.buttons["Remove label Bug"]
        XCTAssertTrue(label.waitForExistence(timeout: 5),
                      "the composer took a label without showing it")
        XCTAssertTrue(app.buttons["Remove priority High"].exists,
                      "the composer took a priority without showing it")
        let due = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Remove due date")
        ).firstMatch
        XCTAssertTrue(due.exists, "the composer took a due date without showing it")
    }

    /// The escape hatch. Pressing a chip is the only way to keep a token as
    /// text, so a chip that draws but does nothing is the same as no chip.
    func testPressingAChipHandsThatTokenBackAndLeavesTheRest() throws {
        let app = try composing("Ship the beta next friday !high #bug")

        let label = app.buttons["Remove label Bug"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), "no label chip to press")
        label.tap()

        XCTAssertFalse(label.waitForExistence(timeout: 2),
                       "the label chip was pressed and the label is still being taken")
        XCTAssertTrue(app.buttons["Remove priority High"].exists,
                      "handing back the label took the priority with it")
    }

    /// A line with nothing in it for the grammar leaves the composer exactly as
    /// it has always been — which is what makes the feature safe to ship on by
    /// default.
    func testAPlainLineDrawsNoStripAtAll() throws {
        let app = try composing("Ship the beta")

        let anyChip = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Remove ")
        ).firstMatch
        XCTAssertFalse(anyChip.waitForExistence(timeout: 2),
                       "a title with no tokens in it still drew a capture strip")
    }
}
