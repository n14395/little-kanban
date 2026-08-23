import XCTest

/// The two panels that open on the left of an iPad window taking turns when it
/// cannot hold both.
///
/// The source list and the Inbox panel are each a column wide and each open on
/// the same side, so a window that has not got two columns and a board cannot
/// show them together. What it used to do there was **nothing**: the panel
/// declined to draw and the Inbox button was a control that did not appear to
/// work. Whichever is opened now closes the other.
///
/// **A UI test because both halves are layout.** Whether the window can hold
/// both is a measurement of what the split view left the detail column —
/// `Tests/PadSurfaceTests` owns that arithmetic — and whether the *other* panel
/// actually went is a question about two view hierarchies, one of which is
/// UIKit's.
///
/// **iPad only**, and it has to be a 13" in portrait or narrower with the
/// inspector out: a 13" in landscape holds all four columns at once, which is
/// what the layout was drawn for and the case that must not start closing
/// anything.
///
/// **Run it on the 11".** A 13" in portrait cleared the first version of this
/// arithmetic by 12pt and passed while the shipped behaviour was broken — 834pt
/// is where an inspector's width in the wrong sum leaves the panel declining
/// after the source list has already closed for it, and this fails there with
/// *the Inbox button did nothing*.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
///       -only-testing:SimpleKanbanUITests/PadSidebarsTests
final class PadSidebarsTests: XCTestCase {
    /// A row only the source list draws.
    private let listMark = "New board"
    /// The Inbox panel's own heading. The bar's toggle and the list's row are
    /// both *buttons* with that word on them, so a static text reading "Inbox"
    /// is the panel and nothing else.
    private let panelMark = "Inbox"

    override func setUp() {
        continueAfterFailure = false
    }

    /// The board with the source list out beside it, which is where both of
    /// these start. The inspector is left where it launches — out — because it
    /// is the third column that makes a 13" in portrait too narrow for the other
    /// two, and this test is about that window.
    private func boardWithTheListOut() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the split view is the iPad's"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["InboxToggle"].waitForExistence(timeout: 20), "no board")

        // Pressed until the list is out rather than a fixed number of times:
        // `columnVisibility` starts `.automatic` and the split view writes its
        // own answer back into the binding, so which way the first press goes
        // depends on what the system decided at launch.
        let toggle = app.buttons["Toggle sidebar"]
        for _ in 0..<2 where !app.buttons[listMark].exists {
            toggle.tap()
            _ = app.buttons[listMark].waitForExistence(timeout: 3)
        }
        XCTAssertTrue(app.buttons[listMark].exists, "the source list would not come out")
        XCTAssertFalse(app.staticTexts[panelMark].exists, "the Inbox panel was already out")
        return app
    }

    /// Opening the Inbox takes the room from the source list.
    func testOpeningTheInboxClosesTheSourceList() throws {
        let app = try boardWithTheListOut()

        app.buttons["InboxToggle"].tap()

        XCTAssertTrue(app.staticTexts[panelMark].waitForExistence(timeout: 5),
                      "the Inbox button did nothing — the panel is still waiting for room")
        XCTAssertFalse(app.buttons[listMark].exists,
                       "both panels are out at once in a window that has room for one")
    }

    /// And opening the source list takes it back. The same rule from the other
    /// side: whichever was asked for is the one that gets the room.
    func testOpeningTheSourceListClosesTheInbox() throws {
        let app = try boardWithTheListOut()
        app.buttons["InboxToggle"].tap()
        XCTAssertTrue(app.staticTexts[panelMark].waitForExistence(timeout: 5), "the panel never opened")

        app.buttons["Toggle sidebar"].tap()

        XCTAssertTrue(app.buttons[listMark].waitForExistence(timeout: 5),
                      "the source list would not come back")
        XCTAssertTrue(app.staticTexts[panelMark].waitForNonExistence(timeout: 5),
                      "the Inbox panel stayed out beside the list it has no room to share with")
    }
}
