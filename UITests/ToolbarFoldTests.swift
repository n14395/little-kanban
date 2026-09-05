import XCTest

/// The iPad's header when the column it sits in runs out of width: the search
/// field folds into a button, and the button drops the field into a row of its
/// own with the keyboard already in it.
///
/// **A UI test because every claim here is about a live layout.** Whether the
/// bar folded is a question about what the split view left the detail column
/// after the source list and the Inbox panel took theirs; whether the row that
/// drops out of it holds the keyboard is a question about a first responder.
/// `Tests/ToolbarFoldTests` owns the arithmetic — at what width the fold
/// happens, and that it happens before the row overflows — which is the half
/// that can be asked of a number.
///
/// **iPad only.** The phone has no toolbar: its search is a tab.
///
///     xcodebuild test -scheme CardstockUITests \
///       -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
///       -only-testing:CardstockUITests/ToolbarFoldTests
final class ToolbarFoldTests: XCTestCase {
    private let field = "SearchField"
    private let toggle = "SearchToggle"

    override func setUp() {
        continueAfterFailure = false
    }

    /// A board with the field still in its bar, which is where the fold starts
    /// from.
    ///
    /// Portrait, and the inspector out of the way: the panel that does half the
    /// narrowing needs a column's width to open into, and with the inspector out
    /// as well `PadRootView` will simply decline to show the Inbox rather than
    /// squeeze the board — and the test would then be measuring nothing.
    private func board() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the toolbar is the iPad's — the phone searches from a tab"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-CardstockSkipFirstRun", "YES",
            "-CardstockHideInspector", "YES",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["InboxToggle"].waitForExistence(timeout: 20), "no board")
        // Not an assertion: an iPad narrow enough to have folded already has
        // nothing left for this test to fold, and saying so is better than
        // failing on a device that is behaving correctly.
        try XCTSkipUnless(
            app.textFields[field].exists,
            "this iPad's board column is already too narrow to hold the field"
        )
        return app
    }

    /// Both of the things that stand beside the board, out — which is what it
    /// takes on a 13" now that the New task button has come off the bar and
    /// given the row its 117pt back. The source list and the Inbox panel are the
    /// only two things that narrow this column: the inspector is laid out
    /// *below* the toolbar and takes nothing from it.
    ///
    /// The source list is pressed *until the bar folds* rather than a fixed
    /// number of times, and that is not laziness: `columnVisibility` starts
    /// `.automatic` and the split view **writes its own answer back into the
    /// binding**, so which way the first press goes depends on what the system
    /// decided at launch — measured, two presses on a 13" in portrait left the
    /// list hidden again. Bounded at two, with the assertion in the test rather
    /// than in here, so a bar that never folds still fails.
    ///
    /// Which press does it also differs by iPad: an 11" is narrow enough that
    /// the panel alone folds the bar and the loop never runs.
    private func narrow(_ app: XCUIApplication) {
        app.buttons["InboxToggle"].tap()
        let sidebar = app.buttons["Toggle sidebar"]
        for _ in 0..<2 where !app.buttons[toggle].exists {
            sidebar.tap()
            _ = app.buttons[toggle].waitForExistence(timeout: 3)
        }
    }

    /// The fold itself. Both columns open *inside* the window beside the bar, so
    /// putting them out is 620pt off it — the same squeeze a Stage Manager
    /// window dragged narrower would apply, reachable from two buttons.
    func testTheFieldFoldsIntoAButtonWhenTheColumnsTakeTheRoom() throws {
        let app = try board()
        XCTAssertFalse(app.buttons[toggle].exists, "the bar had both the field and the button")

        narrow(app)

        XCTAssertTrue(app.buttons[toggle].waitForExistence(timeout: 5),
                      "the bar lost the room for its field and did not fold it")
        XCTAssertFalse(app.textFields[field].exists,
                       "the field is still in the bar beside the button it folded into")
    }

    /// And what the button is for. It was folded away from a field, so pressing
    /// it has to arrive at a field — focused, with the keyboard up, ready for
    /// the first character. Anything less and the fold has cost the reader a
    /// press and a hunt for a 22pt band of text.
    func testTheButtonDropsAFocusedFieldWithTheKeyboardUp() throws {
        let app = try board()
        narrow(app)
        XCTAssertTrue(app.buttons[toggle].waitForExistence(timeout: 5), "the field never folded")
        XCTAssertFalse(app.keyboards.element.exists, "the keyboard was up before search")

        app.buttons[toggle].tap()

        let dropped = app.textFields[field]
        XCTAssertTrue(dropped.waitForExistence(timeout: 5), "the button dropped no field")
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5),
                      "the field came down without the keyboard")
        dropped.typeText("caf")
        XCTAssertEqual(dropped.value as? String, "caf", "the typing did not reach the field")
    }

    /// Putting the row away is a cancel. The field is the only place this
    /// surface shows the query, so a query that outlived it would be a board
    /// quietly missing cards with nothing on screen to say why and nothing to
    /// press to get them back.
    func testPuttingTheRowAwayTakesTheQueryWithIt() throws {
        let app = try board()
        narrow(app)
        XCTAssertTrue(app.buttons[toggle].waitForExistence(timeout: 5), "the field never folded")

        app.buttons[toggle].tap()
        let dropped = app.textFields[field]
        XCTAssertTrue(dropped.waitForExistence(timeout: 5), "the button dropped no field")
        dropped.typeText("caf")
        XCTAssertTrue(app.buttons["Clear search"].waitForExistence(timeout: 5),
                      "a typed query showed no way to clear it")

        app.buttons[toggle].tap()

        XCTAssertFalse(dropped.waitForExistence(timeout: 2), "the row stayed down")
        // Opened again, on an empty field rather than on the search that was
        // cancelled: an × is drawn only while there is something to clear.
        app.buttons[toggle].tap()
        XCTAssertTrue(dropped.waitForExistence(timeout: 5), "the row would not come back")
        XCTAssertFalse(app.buttons["Clear search"].exists,
                       "the cancelled query is still narrowing the board")
    }
}
