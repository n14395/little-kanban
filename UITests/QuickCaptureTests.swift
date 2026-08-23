import XCTest

/// The floating "+" makes a card and opens it to be typed into. It does not
/// also open the Inbox.
///
/// The card lands in the Inbox, so the panel used to be raised along with the
/// sheet — the idea being that closing the sheet would leave the new card in a
/// list already on screen. What it actually did was put a second surface
/// *behind* one the user is typing into: never seen while it mattered, and
/// still standing over the board once the sheet was dismissed, waiting to be put
/// away by somebody who never asked for it.
///
/// **Counted, then checked again after the sheet closes.** The panel *is*
/// enumerable behind the sheet — measured: run against the old behaviour, this
/// suite found two buttons labelled "Close", the sheet's and the panel's, which
/// is the tidiest possible statement of the bug. So the first check is that
/// there is exactly one. The second, after dismissing, is the shape the user
/// actually met: close the new task and there is a slide-over standing over the
/// board. Either one alone would pass a panel that the other catches.
///
/// **It leaves no trace to clean up.** The card is created untitled and nothing
/// is typed, so closing the sheet discards it — see `BoardStore.discardIfBlank`.
/// That is why this suite can run beside the others without moving the board
/// under them.
///
/// **iPhone simulator only** — the "+" is on the phone's floating bar.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:SimpleKanbanUITests/QuickCaptureTests
final class QuickCaptureTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testQuickCaptureLeavesNoInboxPanelBehindTheSheet() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the quick-capture button is on the phone's floating bar"
        )

        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanTab", "board",
            // Both doors the panel can already be through on the way in: the
            // harness flag `InboxDragTests` uses, and the user preference
            // Settings ▸ Board offers. `isInboxOpen` is initialised from the
            // *or* of the two, and this suite's whole claim is about a panel
            // being up that should not be — so it starts from one that is
            // definitely down. Left to the device, it is not: this test failed
            // its own precondition on a simulator where an earlier run had left
            // the preference on.
            "-SimpleKanbanShowInbox", "NO",
            "-SimpleKanbanOpenInboxAtLaunch", "NO",
        ]
        app.launch()

        // The panel's own heading. The tab bar's Inbox is a *button* with the
        // same word on it, and the board behind is a board name, so a static
        // text reading "Inbox" is the panel and nothing else.
        let panelHeading = app.staticTexts["Inbox"]
        XCTAssertFalse(panelHeading.exists, "the Inbox panel was already up before the capture")

        let plus = app.buttons["New task"]
        XCTAssertTrue(plus.waitForExistence(timeout: 15), "no quick-capture button on the bar")
        plus.tap()

        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the + did not open a card to type into")

        // The sheet and the panel both put a button called "Close" in their
        // header, so the count *is* the claim: one means the sheet alone.
        XCTAssertEqual(
            app.buttons.matching(identifier: "Close").count, 1,
            "something else with a Close button came up with the detail sheet — the Inbox panel has a header just like it, and this is what it looks like from here"
        )

        // Unambiguous only because of the assertion above, which stops the run
        // before this line when it is not.
        app.buttons["Close"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "the detail sheet would not close")

        XCTAssertFalse(
            panelHeading.exists,
            "closing the new task revealed the Inbox panel — the capture raised it behind the sheet"
        )
        XCTAssertTrue(
            app.buttons["New task"].exists,
            "the board did not come back after the capture"
        )
    }
}
