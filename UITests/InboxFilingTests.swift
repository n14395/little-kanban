import XCTest

/// Filing a card *out* of the Inbox from the editor takes the Inbox panel down
/// with it, the way filing one *into* the Inbox raises it.
///
/// **The half that already worked** is the one this is modelled on: open a card
/// that lives on a board, pick Inbox from the editor's Move to menu, and
/// `BoardStore.showPlace(of:)` raises the panel — so the editor drops, the Inbox
/// slides up, and the editor comes back over it. You watch the card arrive
/// somewhere.
///
/// **The half that said nothing** was the reverse. `showPlace` selected the
/// board and paged to the card's column exactly as it should, and every one of
/// those changes happened behind a modal panel still listing the Inbox the card
/// had just left, with the editor on top of that. The only thing that moved was
/// the pill's own label.
///
/// **A UI test because the claim is about presentation.** Nothing a store can be
/// asked knows which sheets are stacked over which: `isInboxOpen` is one flag
/// meaning a modal on the phone and a side panel on the iPad, and what is being
/// asserted here is that one sheet went away while another stayed.
///
/// **What can actually be observed**, and it is not the sequence. A sheet makes its
/// presenter inaccessible while it is over it, so with the editor up the panel
/// underneath reports `exists == false` whether it is still there or has gone —
/// the one question this suite is asking. So it is asked in two halves that
/// together only hold if the panel closed and the editor came back:
///
/// 1. **Straight after the pick**, the editor is still up and its pill now names
///    the board. If the panel had taken the editor down and kept itself, or if
///    the editor had never returned, there would be no pill to read.
/// 2. **Then the editor is closed**, and what is behind it is the board — the
///    floating `New task`, and no Inbox heading. That is the measurement
///    `QuickCaptureTests` makes for the mirror-image bug, in the same words: a
///    panel left standing is only visible once the thing over it is gone.
///
/// **Neither surface has a ✕ any more** — both are put away by pulling them
/// down, which is what the grabber above each has always said. So the panel is
/// found by the heading `PhoneInboxSheet.titleID` names, and the editor by its
/// title field; the two used to be told apart by identifier because both of
/// their buttons called themselves "Close".
///
/// **iPhone simulator only** — the iPad's Inbox stands beside the board rather
/// than over it, so a card filed from there is on screen the moment it moves and
/// there is nothing to take down.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17' \
///       -only-testing:LittleKanbanUITests/InboxFilingTests
final class InboxFilingTests: XCTestCase {
    /// A seeded Inbox card — no board, no column, and no labels either, so its
    /// row's combined label starts with the title rather than with a chip.
    private let inboxCard = "Widget on the iOS home screen"
    private let board = "Northwind iOS 3.0"

    override func setUp() {
        continueAfterFailure = false
    }

    func testFilingACardFromTheInboxEditorClosesTheInbox() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad draws the Inbox beside the board, so nothing has to come down"
        )

        let app = XCUIApplication()
        app.launchArguments = [
            "-LittleKanbanSkipFirstRun", "YES",
            "-LittleKanbanTab", "board",
            // Up from the start: which door opens the panel is the tab rail's
            // business, and tapping through one more surface is one more way
            // for this to fail for a reason that is not about filing.
            "-LittleKanbanShowInbox", "YES",
        ]
        app.launch()

        // The panel's own heading — see this suite's note on why each surface
        // is found the way it is.
        let panel = app.staticTexts["InboxPanelTitle"]
        XCTAssertTrue(panel.waitForExistence(timeout: 15), "the Inbox panel never came up")

        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", inboxCard))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no \(inboxCard) in the Inbox")
        row.tap()

        // The editor, up over the panel — which is where a card tapped in the
        // Inbox opens. The panel is not enumerable from here; see the note at
        // the top of this suite.
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "tapping the card did not open the editor")

        // The Move to row's board pill, found by `BoardDestinationMenu.pillID`
        // and valued with where the card is now. By identifier and not by label,
        // for the reason that constant gives: "Board" is the phone's first tab
        // as well, and the editor is a sheet at a detent.
        let pill = app.buttons[BoardDestinationIDs.pill]
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "the editor has no board pill")
        XCTAssertEqual(pill.value as? String, "Inbox", "the card is not in the Inbox to begin with")
        pill.tap()

        let destination = app.buttons[board]
        XCTAssertTrue(destination.waitForExistence(timeout: 5), "the destinations menu has no \(board)")
        destination.tap()

        // **Half one.** The editor came back — it went down with the panel — and
        // it came back on the card that moved.
        XCTAssertTrue(
            app.buttons[BoardDestinationIDs.pill].waitForExistence(timeout: 10),
            "the editor did not come back after the card was filed"
        )
        XCTAssertEqual(
            app.buttons[BoardDestinationIDs.pill].value as? String, board,
            "the editor is showing a card that did not move"
        )
        XCTAssertTrue(app.textFields["Title"].exists, "the editor came back with no card in it")

        // **Half two**, and the one the change is for: close the editor and what
        // is behind it is the board, not the list the card has left. Pulled
        // down, which is the only way out of it now.
        dragDown(app, from: 0.15)
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "the editor would not close")

        XCTAssertFalse(
            panel.exists,
            "the Inbox panel is still standing over the board the card was filed onto"
        )
        XCTAssertTrue(
            app.buttons["New task"].waitForExistence(timeout: 5),
            "the board did not come back after the card was filed onto it"
        )

        putItBack(app)
    }

    /// Sends the card home, so the suite leaves the seeded Inbox as it found it.
    ///
    /// **Not tidiness — the other suites need those three cards.** Run without
    /// this, `InboxSheetDragTests` fails on "no cards in the Inbox to drag from"
    /// and `InboxPanelTests` on the card it opens, both for a reason that has
    /// nothing to do with what they are testing. The board file outlives the
    /// process, so a suite that moves a seeded card owns putting it back.
    ///
    /// It is also the direction that already worked, asserted on the way past:
    /// picking the Inbox raises the panel, and closing the editor leaves it
    /// standing — which is the behaviour the change above is modelled on.
    private func putItBack(_ app: XCUIApplication) {
        let onBoard = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", inboxCard))
            .firstMatch
        XCTAssertTrue(onBoard.waitForExistence(timeout: 10),
                      "\(inboxCard) is not on \(board) after being filed onto it")
        onBoard.tap()

        let pill = app.buttons[BoardDestinationIDs.pill]
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "the card on the board would not open")
        pill.tap()

        let inbox = app.buttons[BoardDestinationIDs.inboxRow]
        XCTAssertTrue(inbox.waitForExistence(timeout: 5), "the destinations menu has no Inbox row")
        inbox.tap()

        XCTAssertTrue(app.buttons[BoardDestinationIDs.pill].waitForExistence(timeout: 10),
                      "the editor did not come back after the card went to the Inbox")
        dragDown(app, from: 0.15)

        XCTAssertTrue(
            app.staticTexts["InboxPanelTitle"].waitForExistence(timeout: 5),
            "filing a card to the Inbox did not leave the panel standing behind the editor"
        )
    }

    /// Puts a sheet away the way a finger does, now that neither surface draws a
    /// ✕. The reach — four tenths of the window — is `InboxSheetDragTests`'s
    /// measurement, and that suite owns the claim that a synthetic drag drives
    /// a system sheet's pan at all.
    private func dragDown(_ app: XCUIApplication, from y: CGFloat) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: min(0.97, y + 0.4))
                ),
                withVelocity: .default,
                thenHoldForDuration: 0.1
            )
    }
}

/// The identifiers `BoardDestinationMenu` publishes, spelled once here rather
/// than at each use. The UI-test target cannot import the app, so this is the
/// near side of a contract whose far side is `BoardDestinationMenu.pillID` and
/// `BoardDestinationItems.inboxRowID`.
private enum BoardDestinationIDs {
    static let pill = "BoardDestination"
    static let inboxRow = "BoardDestination.inbox"
}
