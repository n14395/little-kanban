import XCTest

/// What a drag inside the phone's Inbox does.
///
/// **The Inbox is a place, so its rows have an order and its space means
/// something.** On the desk that has always been true — `InboxPanel` is a
/// column's stack, its cards carry the same two half-row drop zones the board's
/// cards do, and the panel behind them takes a card dropped anywhere in it. On
/// the phone the Inbox was `TaskListView`'s `List`, and a `List` handles drags
/// inside its own bounds: a card released on another card landed nowhere, and
/// the space around them reached nothing behind it either. So nothing in the
/// Inbox could be rearranged by dragging, and nothing could be dropped into it.
///
/// It is ``PhoneCardStack`` now, with the panel-wide destination the desk's has.
/// This pins the half a single finger can reach: **a card rearranged within the
/// Inbox**. The other half — a card arriving from the board — needs a drag that
/// outlives the sheet coming up, which is a two-finger gesture XCUITest has no
/// way to synthesise; the destination itself is read out of the source by
/// `DragReorderTests`.
///
/// **iPhone simulator only.** Nothing here needs a re-seeded board — the test
/// reads the order off the screen rather than assuming the seed's, so it can be
/// run twice running:
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:SimpleKanbanUITests/InboxSheetDropTests
final class InboxSheetDropTests: XCTestCase {
    /// The three cards the seed leaves unfiled. Named rather than counted —
    /// which row is where is read off the screen below.
    private let first = "Widget on the iOS home screen"
    private let second = "Cards jump 1px on drop"
    private let third = "Ask Riya about the empty-board illustration"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launched() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad draws the Inbox as a panel beside the board — `InboxDragTests` is its half"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanTab", "board",
            "-SimpleKanbanShowInbox", "YES",
        ]
        app.launch()
        return app
    }

    /// A card by the words on it. The row combines its own children, so the
    /// label is the whole card and the title is inside it.
    private func card(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// The top card dropped on the **upper** half of the bottom one, which is the
    /// gap between the middle and the bottom — the case that cannot be expressed
    /// by a rule reading the side off the direction of travel, which is why
    /// `CardDropTargetTests` aims at the same half on the board.
    ///
    /// **Which card is which is read off the screen rather than assumed.** The
    /// three are the seed's, but their order is not: this test rearranges them,
    /// and a second run on the same simulator would otherwise fail on the state
    /// the first one left. The claim does not need a particular order — only
    /// three rows and the two ends of them.
    func testACardIsRearrangedByDraggingWithinTheInbox() throws {
        let app = try launched()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "the Inbox never came up")
        XCTAssertTrue(card(first, in: app).waitForExistence(timeout: 10), "no cards in the Inbox")

        let rows = [first, second, third]
            .map { (title: $0, top: card($0, in: app).frame.minY) }
            .sorted { $0.top < $1.top }
        XCTAssertEqual(rows.count, 3, "the Inbox is not the three seeded cards")
        let (top, middle, bottom) = (rows[0].title, rows[1].title, rows[2].title)

        let moving = card(top, in: app)
        let anchor = card(bottom, in: app)
        XCTAssertTrue(moving.exists, "no card called \(top)")
        XCTAssertTrue(anchor.exists, "no card called \(bottom)")

        // A press long enough to lift and short enough not to raise the
        // long-press menu, then down into the *upper* fifth of the bottom row.
        moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.55,
                thenDragTo: anchor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                withVelocity: .slow,
                thenHoldForDuration: 0.4
            )

        // Between the middle and the bottom, which is the gap the caret drew.
        // Polled rather than read once: the drop lands a beat after the finger
        // lifts, and the sheet animates the rows into their new places.
        let settled = expectation(description: "the card landed")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            let moved = self.card(top, in: app)
            let above = self.card(middle, in: app)
            let below = self.card(bottom, in: app)
            guard moved.exists, above.exists, below.exists else { return }
            if above.frame.minY < moved.frame.minY, moved.frame.minY < below.frame.minY {
                timer.invalidate()
                settled.fulfill()
            }
        }
        wait(for: [settled], timeout: 10)
        poll.invalidate()
    }
}
