import XCTest

/// Dragging a card between the Inbox panel and the board, both ways.
///
/// **The one interaction in this app no unit test can reach.** `store.unfile`
/// and `store.move(_:to:)` are covered, and they pass whether or not anything
/// on screen is wired to them: what a drag exercises is the wiring —
/// `.draggable`, `.dropDestination`, and which container gets the gesture
/// first. Only a real press-and-drag can tell those apart, which is why this
/// suite exists and why it is a UI test rather than another `@Test`.
///
/// It found exactly that class of defect on its first run. The panel drew its
/// cards in `TaskListView`'s `List`, and a `List` handles drags inside its own
/// bounds — so a card dropped anywhere in the panel except squarely on top of
/// another card never reached the panel's drop destination behind it. Dragging
/// *out* of the panel worked the whole time, which is what made it look fine.
///
/// **iOS simulator only.** Driving the host Mac's pointer is not a
/// verification, it is a fight with whoever is using the machine.
///
/// The board is seeded on first launch, so a fresh install is the fixture:
///
///     xcrun simctl uninstall <device> com.n14395.SimpleKanban
///
/// Without that the second run measures the board the first run left behind —
/// which is how these two first "failed" while the drags were working
/// perfectly.
final class InboxDragTests: XCTestCase {
    /// The toolbar's Inbox toggle, by identifier rather than by label. Three
    /// things on this screen are called "Inbox" — this button, the panel's own
    /// header and the source list's view row — and a query that caught the
    /// wrong one passed while the button under test was missing. It did,
    /// exactly once, the moment the view row was added.
    private let inboxButton = "InboxToggle"

    /// How far a card has to travel before it counts as having moved at all,
    /// rather than settled back a few points from where it was picked up.
    private let moved: CGFloat = 40

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanShowInbox", "YES",
            // On an iPad in portrait the inspector is holding the room the
            // panel needs; with it open there is no column to drag to.
            "-SimpleKanbanHideInspector", "YES",
        ]
        app.launch()
        return app
    }

    /// A card's own element. Every card combines its children into one, so its
    /// label is its title and everything under it.
    private func card(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", title))
            .firstMatch
    }

    private func drag(_ from: XCUIElement, to target: XCUICoordinate) {
        from.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0, thenDragTo: target,
                   withVelocity: .slow, thenHoldForDuration: 0.6)
    }

    override func setUp() {
        continueAfterFailure = false
    }

    /// Catch something in the Inbox, then put it on the board without leaving
    /// the board — which is the whole reason the Inbox is a panel.
    func testACardDragsFromTheInboxOntoAColumn() {
        let app = launched()

        let inboxCard = card("Widget on the iOS home screen", in: app)
        XCTAssertTrue(inboxCard.waitForExistence(timeout: 10), "no Inbox card on screen")
        let startedAt = inboxCard.frame.midX

        let backlog = card("Add task to Backlog", in: app)
        XCTAssertTrue(backlog.waitForExistence(timeout: 5), "no Backlog column on screen")

        // Well below the column's header, into the stack itself.
        drag(inboxCard, to: backlog.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 8)))

        let landed = card("Widget on the iOS home screen", in: app)
        XCTAssertTrue(landed.waitForExistence(timeout: 5), "the card vanished entirely")
        XCTAssertGreaterThan(landed.frame.midX, startedAt + moved,
                             "the card is still in the panel — the drag did nothing")
    }

    /// The button is only beside a board. Picking Today takes the board away,
    /// and with it the thing the button opens — a toggle for a panel that
    /// cannot appear is a control that does nothing when clicked.
    func testTheInboxButtonGoesAwayOnASavedView() {
        let app = launched()

        let inbox = app.buttons[inboxButton]
        XCTAssertTrue(inbox.waitForExistence(timeout: 10), "no Inbox button in the toolbar")

        // The source list is where Today is, and on an iPad in portrait it
        // starts hidden.
        let toggle = app.buttons["Toggle sidebar"]
        if toggle.exists { toggle.tap() }
        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Today")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5), "no Today row in the source list")
        today.tap()

        XCTAssertTrue(inbox.waitForNonExistence(timeout: 5),
                      "the Inbox button is still there on a saved view")

        // And it comes back with the board.
        let board = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Northwind")).firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 5), "no board row in the source list")
        board.tap()
        XCTAssertTrue(inbox.waitForExistence(timeout: 5), "the Inbox button did not come back")
    }

    /// And back, which is the route a card filed by mistake takes. **Dropped on
    /// empty space rather than onto another card**, on purpose: that is the
    /// case a `List` used to swallow, and dropping onto a card would have
    /// passed throughout.
    func testACardDragsFromAColumnBackIntoTheInbox() {
        let app = launched()

        let boardCard = card("Board templates", in: app)
        XCTAssertTrue(boardCard.waitForExistence(timeout: 10), "no board card on screen")
        let startedAt = boardCard.frame.midX

        let inboxCard = card("Cards jump 1px on drop", in: app)
        XCTAssertTrue(inboxCard.waitForExistence(timeout: 5), "no Inbox panel on screen")

        drag(boardCard, to: inboxCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 6)))

        let landed = card("Board templates", in: app)
        XCTAssertTrue(landed.waitForExistence(timeout: 5), "the card vanished entirely")
        XCTAssertLessThan(landed.frame.midX, startedAt - moved,
                          "the card is still on the board — the drop did nothing")
    }
}
