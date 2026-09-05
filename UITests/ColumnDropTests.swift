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
///     xcrun simctl uninstall <device> com.n14395.Cardstock
///     xcodebuild test -scheme CardstockUITests \
///       -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M4)'
///     xcodebuild test -scheme CardstockUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
final class ColumnDropTests: XCTestCase {
    /// - Parameter showingTicks: whether the cards draw their completion
    ///   circle. It is a preference and it is **off** by default — see
    ///   `Preferences.cardTickKey`, which explains why — so a case that
    ///   finishes cards by pressing them has to ask for it. Off for everything
    ///   else, because the tick is a control the board does not normally carry
    ///   and a suite should measure the board people have.
    private func launched(showingTicks: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CardstockSkipFirstRun", "YES",
            // The inspector holds the room the fourth column needs.
            "-CardstockHideInspector", "YES",
            // The board, said out loud. A phone lands on **Today** on a cold
            // launch — `BoardStore.landingSurface` — and Today is a flat list
            // with no columns in it, so a suite about dropping a card on a
            // column has to name the surface the columns are on. Only visible
            // on a fresh install, which is exactly how this suite should be run.
            "-CardstockTab", "board",
        // The key is `Preferences.cardTickKey`, spelled out because a UI test
        // runs out of process and cannot import the app to ask.
        ] + (showingTicks ? ["-CardstockShowsCardTick", "YES"] : [])
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
    /// **On its side**, because that is the one shape where columns share a
    /// phone screen. A drop on the ground of the column a card is already in is
    /// a no-op by design, so in portrait — one column per screen — there is no
    /// cross-column drop for a single drag to make.
    ///
    /// **In Progress is emptied first**, by ticking its cards rather than by
    /// trashing them: a tick sends a card to Done in one tap, it makes the
    /// target the case that used to be unreachable by any gesture, and it leaves
    /// a whole page of ground to aim at rather than the sliver a landscape phone
    /// has left under two cards.
    ///
    /// **The neighbour it is dropped from is the column to its right**, which is
    /// Done: every card in Done is done, so "Mark as not done" picks a card out
    /// of it without naming one, and which card that is depends on what the last
    /// run left behind.
    func testACardDropsOnAnEmptyPhoneColumn() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad's whole board is the test above"
        )
        // Turned before it is launched, not after: the pager is a scroll view
        // and a rotation resets it to the first column, so a test that set the
        // page up in portrait would find itself looking at Backlog.
        XCUIDevice.shared.orientation = .landscapeLeft
        // The ticks below are how this case empties the column, and the tick
        // is a preference that arrives off.
        let app = launched(showingTicks: true)
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20), "the app never came up")

        let empty = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Nothing in In Progress"))
            .firstMatch
        // **In Progress's own gutter**, which is the strip between its heading
        // and its cards. Three columns share the screen turned this way and two
        // of them are ahead of this one, so "the first tick on screen" is Up
        // Next's — and the loop would empty a column this test is not about,
        // then run out.
        //
        // The heading is the anchor because it is the one part of a page that is
        // always on screen: a page is a third of the width now, its cards wrap
        // to two and three lines each, and the dashed row that would otherwise
        // name the column is below the fold.
        let heading = try XCTUnwrap(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "In Progress,"))
                .allElementsBoundByIndex
                .first { app.frame.contains($0.frame) },
            "In Progress is not one of the columns on screen"
        ).frame
        // **The strip this column occupies**, as the two card edges either side
        // of it: the nearest one to the right of the heading is this column's
        // own, and the next distinct one is where the column after it starts.
        // Everything drawn in this column is between them, and the columns
        // either side are 250pt away.
        //
        // **It used to be the gutter between the heading and the first card**,
        // which is where the tick was drawn — a leading gutter in front of
        // everything the card had to say. It is in the card's *trailing* corner
        // now, so the strip that used to hold it holds nothing: measured, In
        // Progress's ticks sit at x=515 while the old band was 332 to 347, so
        // the loop found none, pressed none, and the column it was to empty
        // stayed full. Nothing said so — a `first` that matches nothing is a
        // `break`, and the failure landed on the assertion after it.
        let edges = app.buttons.allElementsBoundByIndex
            .filter {
                $0.frame.width > 100 && app.frame.contains($0.frame)
                    && $0.frame.minX > heading.minX
            }
            .map { $0.frame.minX }
            .sorted()
        let cardEdge = try XCTUnwrap(edges.first, "In Progress has no cards on screen to empty")
        // Past the duplicates: a column's cards all share a left edge.
        let nextEdge = edges.first { $0 > cardEdge + 1 } ?? app.frame.maxX

        // Picked by frame rather than by `isHittable`: the pager builds the
        // pages either side as well, and asking a tick two columns away whether
        // it is hittable *throws* — "activation point invalid" — rather than
        // answering no.
        for _ in 0..<10 {
            if empty.exists { break }
            let ticks = app.buttons.matching(identifier: "Mark as done")
                .allElementsBoundByIndex
            let onScreen = ticks.first {
                $0.frame.width > 0 && app.frame.contains($0.frame)
                    && $0.frame.midX > cardEdge && $0.frame.midX < nextEdge
            }
            guard let tick = onScreen else { break }
            tick.tap()
        }
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "In Progress never emptied")

        let page = empty.frame
        XCTAssertTrue(app.frame.contains(page), "the empty column is not the one on screen")

        // A card from the column beside it, found by its size rather than by the
        // words on it: which card is in which column depends on what the last
        // run left behind, and this claim is about the ground rather than about
        // any particular card. A card is the only thing on a board wide enough
        // to be one — the ticks and the dashed row are told apart by the labels
        // they carry.
        //
        // **The card itself, rather than the tick beside it.** This found a
        // tick and stepped 110pt to its *right* to reach the card it belonged
        // to, which was the arithmetic of a tick drawn in a leading gutter. The
        // tick is in the card's trailing corner now, so the same step lands in
        // the column after it — and the press that should have lifted a card
        // would have landed on empty page. Asking for the card directly has no
        // arithmetic in it to go stale.
        let neighbour = app.buttons.allElementsBoundByIndex.first {
            let frame = $0.frame
            guard frame.width > 100, app.frame.contains(frame), frame.midX > page.maxX
            else { return false }
            return !$0.label.hasPrefix("Mark as") && !$0.label.contains("Add task to")
        }
        guard let row = neighbour?.frame else {
            return XCTFail("no card in the column beside In Progress")
        }
        let moving = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: row.midX, dy: row.midY))

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
