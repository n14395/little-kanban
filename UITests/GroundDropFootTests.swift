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
/// **iPhone, on its side**, which is the one shape where two columns share the
/// screen and a whole cross-column drag can be made without turning a page.
/// Nothing here needs a re-seeded board: which card is where is read off the
/// screen, so the suites that rearrange one can run before it.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:SimpleKanbanUITests/GroundDropFootTests
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
    private func cards(
        in app: XCUIApplication, trailingOf divide: CGFloat? = nil, leadingOf: CGFloat? = nil
    ) -> [XCUIElement] {
        app.buttons.allElementsBoundByIndex
            .filter { element in
                let frame = element.frame
                guard frame.width > 150, app.frame.contains(frame) else { return false }
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
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Board"].waitForExistence(timeout: 20), "the app never came up")

        // The dashed row under the leading column's cards: the target, and the
        // line that divides the two columns on screen. On screen and this
        // column's — the pager builds the pages either side as well, and their
        // dashed rows are off in negative space.
        let dashed = try XCTUnwrap(
            app.buttons
                .matching(NSPredicate(format: "label CONTAINS %@", "Add task to"))
                .allElementsBoundByIndex
                .first { app.frame.contains($0.frame) },
            "no dashed add row on screen — the leading column has no cards under it"
        )
        let row = dashed.frame

        let landing = cards(in: app, leadingOf: row.maxX)
        let beside = cards(in: app, trailingOf: row.maxX)
        let foot = try XCTUnwrap(landing.last?.frame, "no cards in the column being dropped on")
        XCTAssertGreaterThan(row.minY, foot.maxY, "the add row is not below that column's cards")
        // The card carried is the one at the **top** of the column beside it,
        // which is the whole of the reported bug: it used to arrive at the top of
        // the column it was dropped on rather than at the bottom.
        let moving = try XCTUnwrap(beside.first, "no card in the column beside it")
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

        // In the column it was dropped on, and under everything that was already
        // in it — polled, because the drop lands a beat after the finger lifts.
        let settled = expectation(description: "the card landed at the foot")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            let moved = card(carried).frame
            guard moved.width > 0 else { return }
            if abs(moved.midX - foot.midX) < 30, moved.minY > foot.minY {
                timer.invalidate()
                settled.fulfill()
            }
        }
        wait(for: [settled], timeout: 12)
        poll.invalidate()
    }
}
