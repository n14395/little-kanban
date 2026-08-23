import XCTest

/// A card does not open up under a sideways finger. Cards move when they have
/// been picked up, and that is the only time.
///
/// The flat surfaces — Search, the Inbox, a saved view, the Archive — carried
/// swipe actions until 6.4: Complete on the leading edge, Trash on the trailing
/// one. The board's rows never had them, because the pager owns the horizontal
/// drag there, so the two halves of the app disagreed about what a sideways drag
/// on a card meant. They agree now, and they agree on *nothing comes out*.
///
/// **A UI test because the claim is about a gesture.** `swipeActions` are
/// declared on a row and delivered by the list; nothing in the store knows
/// whether a row has any, and a view that has stopped declaring them looks
/// exactly like one that never did. The only way to check is to swipe a real
/// card on a real list and see whether anything appears from under it.
///
/// **The paging swipe is untouched**, and that it still fires is
/// `EdgeSwipeTests`' claim rather than this suite's — which is why the board's
/// case here asks the narrower question. On the board a sideways drag turns the
/// page, so the card is *expected* to travel; what must not happen is a button
/// coming out from beneath it.
///
/// **Nothing is named.** No card title and no column: this simulator's board is
/// whatever the suites before it left behind — cards trashed, columns paged away
/// from — and a fixture anchor is how a test about gestures ends up failing
/// about seed data. The Search tab's first row and the middle of the board are
/// both there whatever the board holds.
///
/// **iPhone simulator only** — the phone's tab bar is what puts these two
/// surfaces on screen.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:SimpleKanbanUITests/RowSwipeTests
final class RowSwipeTests: XCTestCase {
    /// What the two edges used to put there. Named as the buttons they were
    /// rather than as the verbs they do: a swipe action *is* a button, and a
    /// button is what would come back if the modifier did. Restore and Reopen
    /// are the Archive's and a done card's versions of the leading one.
    private let revealed = ["Complete", "Trash", "Reopen", "Restore"]

    override func setUp() {
        continueAfterFailure = false
    }

    private func launched(on tab: String) throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the phone's tab bar is what puts these two surfaces on screen"
        )
        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanTab", tab,
        ]
        app.launch()
        return app
    }

    private func assertNothingIsRevealed(in app: XCUIApplication, after swipe: String, on surface: String) {
        for button in revealed {
            XCTAssertFalse(
                app.buttons[button].exists,
                "a \(swipe) swipe on \(surface) revealed \(button)"
            )
        }
    }

    /// The surface the swipes were actually on. Here the card must not move
    /// either — the frame is what catches a *partial* swipe, since a row that
    /// slides 60pt and springs back has still opened under the finger, and a
    /// check that only looked for buttons would call that a pass.
    func testACardOnAFlatListDoesNotSwipeEitherWay() throws {
        let app = try launched(on: "search")

        // The flat surfaces are `TaskListView`, which is a `List`, so its rows
        // are cells — the one place in this app where a card is reachable
        // without knowing anything about the board behind it.
        let row = app.cells.element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no cards at all on the Search tab")
        let restingPlace = row.frame

        row.swipeRight()
        assertNothingIsRevealed(in: app, after: "leading", on: "the Search tab")
        XCTAssertTrue(row.exists, "a leading swipe took the card away — a full swipe still fires")
        XCTAssertEqual(row.frame.minX, restingPlace.minX, accuracy: 1,
                       "the card slid sideways on a leading swipe")

        row.swipeLeft()
        assertNothingIsRevealed(in: app, after: "trailing", on: "the Search tab")
        XCTAssertTrue(row.exists, "a trailing swipe took the card away — a full swipe still fires")
        XCTAssertEqual(row.frame.minX, restingPlace.minX, accuracy: 1,
                       "the card slid sideways on a trailing swipe")
    }

    /// The board, where the actions were withheld rather than absent — the
    /// withholding was a `!store.isColumnPaging` guard *inside* the modifier,
    /// and a guard is the kind of thing that comes back the moment somebody
    /// edits around it. Swiped through the app rather than through an element:
    /// the middle of this screen is the column, whatever is in it.
    func testTheBoardRevealsNothingWhenThePageTurns() throws {
        let app = try launched(on: "board")

        // The tab bar's own slot, selected — the cheapest proof the launch
        // argument took and the board is what is under the finger. Named by the
        // tab rather than by anything on the board, for the reason the suite
        // note gives: whatever this simulator's board holds, it is still Board.
        let boardTab = app.buttons["Board"]
        XCTAssertTrue(boardTab.waitForExistence(timeout: 15), "the app never came up")
        XCTAssertTrue(boardTab.isSelected, "the board is not the tab on screen")

        app.swipeLeft()
        assertNothingIsRevealed(in: app, after: "trailing", on: "the board")

        app.swipeRight()
        assertNothingIsRevealed(in: app, after: "leading", on: "the board")
    }
}
