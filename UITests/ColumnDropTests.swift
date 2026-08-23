import XCTest

/// Where in a column a card may be dropped.
///
/// A column is as tall as the board — its tint and its highlight run to the
/// bottom of the strip — and the cards in it are a stack at the top. Under a
/// finger the space below the last card is where a drop naturally lands: it is
/// the part of the column that is obviously *empty*, and it is most of the
/// column on a board that is not full.
///
/// **A UI test for the reason `InboxDragTests` gives.** `store.move(_:to:)` is
/// unit-tested and passes whether or not the space below the cards is wired to
/// anything; what this exercises is which container gets the drop.
///
/// One test per idiom, because the two surfaces draw a column with different
/// containers and it is the container that answers this: the iPad's strip has
/// always been a stack, and the phone's page was `TaskListView`'s `List` until
/// it was given a stack of its own — see ``PhoneColumnPage``.
///
/// **iOS simulator only.**
///
///     xcrun simctl uninstall <device> com.n14395.SimpleKanban
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M4)'
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
final class ColumnDropTests: XCTestCase {
    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            // The inspector holds the room the fourth column needs.
            "-SimpleKanbanHideInspector", "YES",
        ]
        app.launch()
        return app
    }

    private func card(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", title))
            .firstMatch
    }

    private func drag(_ from: XCUIElement, to target: XCUICoordinate) {
        from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 2.0, thenDragTo: target,
                   withVelocity: .slow, thenHoldForDuration: 1.0)
    }

    /// The phone's lift, which is a *shorter* press. Both idioms put a menu on
    /// a long press — ``PhoneTaskRowActions`` here — and on the phone a press
    /// held for the iPad's two seconds raises the menu instead of picking the
    /// card up, so the drag that follows it drags nothing.
    /// `CardDropTargetTests` uses the same 0.55s for the same reason.
    private func lift(_ from: XCUICoordinate, to target: XCUICoordinate) {
        from.press(forDuration: 0.55, thenDragTo: target,
                   withVelocity: .slow, thenHoldForDuration: 0.6)
    }

    override func setUp() {
        continueAfterFailure = false
    }

    /// The orientation outlives the process, so the phone's half puts it back —
    /// every other suite here reads portrait.
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// The whole of the claim: a card dropped low in a column — far below the
    /// last card in it, where there is nothing but the column's own background —
    /// lands in that column.
    func testACardDropsInTheEmptySpaceBelowAColumnsCards() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the phone shows one column at a time — its half of this is below"
        )
        let app = launched()

        let moving = card("Board templates", in: app)
        XCTAssertTrue(moving.waitForExistence(timeout: 15), "no Backlog card on screen")

        // The column's own "+", which is the one element that is the column
        // rather than something in it.
        let upNext = app.buttons["Add task to Up Next"]
        XCTAssertTrue(upNext.waitForExistence(timeout: 5), "no Up Next column on screen")

        // The stack's own centre line rather than the header button's: the "+"
        // sits at the column's trailing edge, and a card that landed would be
        // drawn where the cards are.
        let lastCard = card("Due-date chips turn red when overdue", in: app)
        XCTAssertTrue(lastCard.exists, "no last card in Up Next")
        let column = lastCard.frame.midX
        XCTAssertLessThan(abs(column - upNext.frame.midX), 200, "that is not the Up Next stack")

        // Deep in the empty part of the column: below its last card, and as far
        // down the board as the strip goes.
        let bottom = app.frame.maxY - 60
        XCTAssertGreaterThan(bottom, lastCard.frame.maxY + 100,
                             "no empty space below the cards to drop into")
        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: column, dy: bottom))

        drag(moving, to: target)
        // A second attempt if the first press never became a lift, which
        // happens on the first drag of a launched app and only there — the
        // card is still exactly where it started, not somewhere between. It is
        // the gesture that is unreliable, not the board: without the drop area
        // this is checking for, both attempts land nowhere, which is what the
        // suite failed with before the fix.
        if abs(card("Board templates", in: app).frame.midX - column) > 20 {
            drag(card("Board templates", in: app), to: target)
        }

        let landed = card("Board templates", in: app)
        XCTAssertTrue(landed.waitForExistence(timeout: 5), "the card vanished entirely")
        XCTAssertEqual(landed.frame.midX, column, accuracy: 20,
                       "the card is still in Backlog — the drop below the cards did nothing")
    }

    /// The same claim on the phone, where it was two gaps rather than one: a
    /// page was `TaskListView`'s `List`, and a `List` keeps a drop inside its
    /// own bounds, so the space under the cards took nothing — and a column with
    /// *nothing but* that space could not be dragged to at all. Both are one
    /// container change; see ``PhoneColumnPage``.
    ///
    /// **On its side**, because that is the one shape where two columns share a
    /// phone screen. A drop on the ground of the column a card is already in is
    /// a no-op by design, so in portrait — one column per screen — there is no
    /// cross-column drop for a single drag to make.
    ///
    /// **In Progress is emptied first**, by ticking its cards rather than by
    /// trashing them: a tick sends a card to Done in one tap, it makes the
    /// target the case that used to be unreachable by any gesture, and it leaves
    /// a whole page of ground to aim at rather than the sliver a landscape phone
    /// has left under two cards.
    func testACardDropsOnAnEmptyPhoneColumn() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad's whole board is the test above"
        )
        // Turned before it is launched, not after: the pager is a scroll view
        // and a rotation resets it to the first column, so a test that set the
        // page up in portrait would find itself looking at Backlog.
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launched()
        XCTAssertTrue(app.buttons["Board"].waitForExistence(timeout: 20), "the app never came up")

        let empty = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Nothing in In Progress"))
            .firstMatch
        // The pager opens on In Progress, so it and Done are the two columns
        // sharing the screen. Every card in Done is done, and its tick reads
        // "Mark as not done" — so the ticks matched here are In Progress's, and
        // the loop runs out exactly when that column does.
        //
        // Picked by frame rather than by `isHittable`: the pager builds the
        // pages either side as well, and asking a tick two columns away whether
        // it is hittable *throws* — "activation point invalid" — rather than
        // answering no.
        for _ in 0..<10 {
            if empty.exists { break }
            let ticks = app.buttons.matching(identifier: "Mark as done")
                .allElementsBoundByIndex
            let onScreen = ticks.first { $0.frame.width > 0 && app.frame.contains($0.frame) }
            guard let tick = onScreen else { break }
            tick.tap()
        }
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "In Progress never emptied")

        let page = empty.frame
        XCTAssertTrue(app.frame.contains(page), "the empty column is not the one on screen")

        // A card from the column beside it, found by the tick in its gutter
        // rather than by the words on it: which card is in which column depends
        // on what the last run left behind, and this claim is about the ground
        // rather than about any particular card. Every card in Done is done, so
        // "Mark as not done" is what its ticks say.
        let ticks = app.buttons.matching(identifier: "Mark as not done").allElementsBoundByIndex
        let neighbour = ticks.first {
            $0.frame.width > 0 && app.frame.contains($0.frame) && $0.frame.midX > page.maxX
        }
        guard let row = neighbour?.frame else {
            return XCTFail("no card in the column beside In Progress")
        }
        // The card, not the tick: the tick is a button in the card's gutter and
        // the press has to land on the card itself to pick it up.
        let moving = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: row.midX + 110, dy: row.midY + 20))

        // Deep in the empty part of the page: below everything drawn in it, and
        // as far down as the column goes.
        let bottom = app.frame.maxY - 40
        XCTAssertGreaterThan(bottom, page.maxY + 40, "no ground below the empty state to drop into")
        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: page.midX, dy: bottom))

        lift(moving, to: target)
        // The retry the iPad's half explains: the first press of a launched app
        // is the one that does not always become a lift.
        if empty.exists {
            lift(moving, to: target)
        }

        XCTAssertTrue(
            empty.waitForNonExistence(timeout: 5),
            "In Progress is still empty — the drop on the ground below its content did nothing"
        )
    }
}
