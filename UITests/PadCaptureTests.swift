import XCTest

/// The `+` at the right of the iPad's board header.
///
/// **A UI test because the button is a glyph.** It carries no word, so what it
/// is called exists only as an `accessibilityLabel` — and a label is the one
/// part of a control that can be deleted without anything on screen changing.
/// Nothing a store can be asked knows whether the bar published a name for it,
/// or whether pressing it reached a composer rather than a column that scrolled.
///
/// **iPad only.** The desk captures from the foot of its source list, from ⌘N
/// and from the menu-bar extra; the phone floats its own `+` over the tab bar
/// (`UITests/QuickCaptureTests`). This bar is the iPad's, and so is this button.
///
/// All three land in the Inbox, and that is the other half of what this presses
/// for: the button used to open the composer on the board behind it, which is
/// the column heading's job.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
///       -only-testing:LittleKanbanUITests/PadCaptureTests
final class PadCaptureTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTheBarsPlusOpensACardToTypeInto() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the board header is the iPad's"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES"]
        app.launch()

        // The name the glyph does not draw. `app.buttons["New task"]` resolving
        // at all is the assertion: a `+` with no label publishes as a button
        // with an empty name, which is what a reader would have found here.
        let capture = app.buttons["New task"]
        XCTAssertTrue(capture.waitForExistence(timeout: 20),
                      "the board header published no name for its capture button")
        // And it is the bar's, not a column heading's `+` — those are the same
        // glyph and there are four of them on screen. Told apart by the row it
        // is on rather than by its own frame: the header's controls share a
        // centre line, and every column's `+` is below all of them.
        let inspector = app.buttons["Toggle details sidebar"].frame
        XCTAssertEqual(capture.frame.midY, inspector.midY, accuracy: 2,
                       "the button called New task is not the one on the header's row")

        capture.tap()

        XCTAssertTrue(app.textFields["Task title, then ⏎"].waitForExistence(timeout: 5),
                      "the + did not open a composer to type into")
        // And the composer it opened is the Inbox's, not the board's: this
        // button captures, so it lands where a card goes before anything about
        // it is decided. The panel's own "+" is the element that says the panel
        // is out — the board behind it draws no such button.
        XCTAssertTrue(app.buttons["Capture a task"].waitForExistence(timeout: 5),
                      "the + opened a composer somewhere other than the Inbox panel")
    }
}
