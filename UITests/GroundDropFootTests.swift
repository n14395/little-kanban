import XCTest

/// Where a card lands when it is dropped **below** a list rather than on one of
/// its rows.
///
/// **The bottom**, wherever the card came from. The ground briefly kept the dragged
/// card's rank instead — a card first in one column arrived first in the next —
/// so a card released in the space under a column's cards jumped *up* past them
/// on release, to a place nothing had marked. The store half of the rule is
/// `DropCaretTests`; this is the half only a finger can ask.
///
/// **It aims at the dashed "+ Add task to…" row**, not at bare ground beside it.
/// That row is a button, it sits over the page's drop destination, and it is
/// exactly where a thumb lands when it means "the bottom of this list" — a claim
/// checked only against the ground the row does not cover would leave the case
/// people actually make untested. (The row passes the drop through: a button
/// takes clicks, and a drop is not one. Measured, both ways round.)
///
/// **iPhone, on its side**, which is the one shape where columns share the
/// screen and a whole cross-column drag can be made without turning a page.
/// Nothing here needs a re-seeded board: which card is where is read off the
/// screen, so the suites that rearrange one can run before it.
///
///     xcodebuild test -scheme CardstockUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:CardstockUITests/GroundDropFootTests
final class GroundDropFootTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// The cards on screen, top to bottom, on one side of `divide`.
    ///
    /// **Read off the screen rather than named**, because which card is in which
    /// column depends on what the last suite in the run left behind, and this one
    /// is about a *position*, not about any particular card. A card is a button
    /// wide enough to be one: the ticks in their gutters and the dashed row under
    /// them are buttons too, and are told apart by the labels they carry.
    ///
    /// **100, not 150.** Three columns share a landscape screen, and a card in
    /// one is 142pt wide on a 17 Pro and narrower on anything smaller — under
    /// the number this filter used while two columns shared it. Everything else
    /// on screen here is a 44pt square of chrome, so the gap the threshold has
    /// to fall in is a wide one.
    private func cards(
        in app: XCUIApplication, trailingOf divide: CGFloat? = nil, leadingOf: CGFloat? = nil
    ) -> [XCUIElement] {
        app.buttons.allElementsBoundByIndex
            .filter { element in
                let frame = element.frame
                guard frame.width > 100, app.frame.contains(frame) else { return false }
                let label = element.label
                guard !label.hasPrefix("Mark as"), !label.contains("Add task to") else { return false }
                if let divide, frame.midX < divide { return false }
                if let leadingOf, frame.midX > leadingOf { return false }
                return true
            }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    func testACardDroppedBelowAColumnsCardsLandsAtTheBottomOfIt() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the reported case is the phone's, where the ground is most of the screen"
        )
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        // The board, said out loud: a phone lands on **Today** on a cold launch
        // — `BoardStore.landingSurface` — and Today is a flat list with no
        // column ground under it. `ColumnStripTests` names the tab for the same
        // reason.
        app.launchArguments = ["-CardstockSkipFirstRun", "YES", "-CardstockTab", "board"]
        app.launch()
        XCTAssertTrue(app.buttons["New task"].waitForExistence(timeout: 20), "the app never came up")

        // The dashed row under the leading column's cards: the target, and the
        // line that divides it from the columns beside it. On screen and this
        // column's — the pager builds the pages either side as well, and their
        // dashed rows are off in negative space.
        //
        // **Scrolled to rather than assumed.** Three columns share the screen
        // turned this way, so a page is a third of the width and its cards wrap
        // to two and three lines each; a column with three of them is then
        // taller than a 402pt screen, and the row under them is below the fold
        // at launch. The swipe is in the leading column — the one being dropped
        // on — and is a swipe rather than a press-and-drag so the card under the
        // finger scrolls instead of lifting.
        func dashedRow() -> XCUIElement? {
            app.buttons
                .matching(NSPredicate(format: "label CONTAINS %@", "Add task to"))
                .allElementsBoundByIndex
                .first { app.frame.contains($0.frame) }
        }
        var found = dashedRow()
        for _ in 0..<4 where found == nil {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.4)))
            found = dashedRow()
        }
        let dashed = try XCTUnwrap(
            found, "no dashed add row on screen — the leading column has no cards under it"
        )
        let row = dashed.frame

        // **The dashed row's own column, bounded on both sides.** `leadingOf`
        // alone is everything to the *left* of it, which with three columns
        // sharing a landscape screen is two of them — so the "last card in the
        // column being dropped on" was the last card in either of two columns,
        // whichever the sort happened to end on. It was the right one by luck
        // here and would not have been on a board arranged differently.
        let landing = cards(in: app, trailingOf: row.minX - 5, leadingOf: row.maxX + 5)
        let beside = cards(in: app, trailingOf: row.maxX)
        let foot = try XCTUnwrap(landing.last?.frame, "no cards in the column being dropped on")
        XCTAssertGreaterThan(row.minY, foot.maxY, "the add row is not below that column's cards")
        // The card carried is the one at the **top** of the column beside it,
        // which is the whole of the reported bug: it used to arrive at the top of
        // the column it was dropped on rather than at the bottom.
        //
        // Leftmost first and topmost second, because `beside` is now two columns
        // rather than one: three share the screen, and the tops of all of them
        // are level. Nearest is the shortest drag, and — the reason it is chosen
        // rather than left to whichever the sort happened to put first — the same
        // card every run.
        let moving = try XCTUnwrap(
            beside.min {
                ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY)
            },
            "no card in the column beside it"
        )
        let carried = moving.label

        let target = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: row.midX, dy: row.midY))
        func card(_ label: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        }
        func drag() {
            card(carried)
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.55, thenDragTo: target,
                       withVelocity: .slow, thenHoldForDuration: 0.6)
        }
        drag()
        // The first press of a launched app is the one that does not always
        // become a lift — the retry `ColumnDropTests` explains.
        if card(carried).frame.midX > row.maxX { drag() }

        // In the column it was dropped on, and last in it — polled, because the
        // drop lands a beat after the finger lifts.
        //
        // **Read as an order, not as a height.** This compared the landed card's
        // `minY` with the `foot` frame measured *before* the drag, and a drag
        // that ends near the bottom of a column scrolls it: measured, the column
        // moved up 154pt while the card was held over the dashed row, so the
        // card arrived at the foot and read as 44pt *above* where the old foot
        // used to be. Both numbers were true and neither was comparable with the
        // other. What the case is about is which card is at the bottom, and that
        // survives a scroll — so it asks the column, after the drop, for its
        // last card. The count guards the moment mid-animation when the column
        // holds one card and anything is trivially last in it.
        let settled = expectation(description: "the card landed at the foot")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            let column = self.cards(in: app, trailingOf: row.minX - 5, leadingOf: row.maxX + 5)
            guard column.count >= 2, let last = column.last else { return }
            if last.label == carried {
                timer.invalidate()
                settled.fulfill()
            }
        }
        wait(for: [settled], timeout: 12)
        poll.invalidate()
    }
}
