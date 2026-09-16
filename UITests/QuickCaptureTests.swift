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
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:LittleKanbanUITests/QuickCaptureTests
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
            "-LittleKanbanSkipFirstRun", "YES",
            "-LittleKanbanTab", "board",
            // Both doors the panel can already be through on the way in: the
            // harness flag `InboxDragTests` uses, and the user preference
            // Settings ▸ Board offers. `isInboxOpen` is initialised from the
            // *or* of the two, and this suite's whole claim is about a panel
            // being up that should not be — so it starts from one that is
            // definitely down. Left to the device, it is not: this test failed
            // its own precondition on a simulator where an earlier run had left
            // the preference on.
            "-LittleKanbanShowInbox", "NO",
            "-LittleKanbanOpenInboxAtLaunch", "NO",
        ]
        app.launch()

        // The panel's own heading, by the identifier `PhoneInboxSheet.titleID`
        // publishes: the tab bar's Inbox is a *button* with the same word on it
        // and a card can wear a chip saying it, so the word alone is not the
        // panel.
        let panelHeading = app.staticTexts["InboxPanelTitle"]
        XCTAssertFalse(panelHeading.exists, "the Inbox panel was already up before the capture")

        let plus = app.buttons["New task"]
        XCTAssertTrue(plus.waitForExistence(timeout: 15), "no quick-capture button on the bar")
        plus.tap()

        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the + did not open a card to type into")

        // **Half one**, made while the sheet is up, which is where the bug
        // showed: the panel is enumerable behind a sheet, so this is a real
        // question rather than a vacuous one. It used to be a count of the
        // buttons called "Close" — one meant the sheet alone — and neither
        // surface draws one now, so it asks for the panel by the heading the
        // count was standing in for.
        XCTAssertFalse(
            panelHeading.exists,
            "the Inbox panel came up behind the detail sheet — the capture raised it"
        )

        // **Half two.** The sheet is put away by pulling it down, which is the
        // only way out of it now. By its grabber — the button UIKit labels
        // "Sheet Grabber" — because on the iOS 27.0 beta simulator runtime a
        // synthesized drag that begins over the editor's content no longer
        // hands the pan to the sheet, while one begun on the grabber still
        // does. A real finger is not so fussy: measured on a device, the whole
        // sheet answers to the pull. `firstMatch` is safe here where it is not
        // in the Inbox suites — this suite's whole claim is that the editor is
        // the *only* sheet up, so there is one grabber to match.
        let grabber = app.buttons.matching(
            NSPredicate(format: "label == %@", "Sheet Grabber")
        ).firstMatch
        XCTAssertTrue(grabber.waitForExistence(timeout: 5), "the sheet has no grabber to pull by")
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.05,
                thenDragTo: app.windows.firstMatch.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)
                ),
                withVelocity: .default,
                thenHoldForDuration: 0.1
            )
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
