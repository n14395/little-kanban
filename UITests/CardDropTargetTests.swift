import XCTest

/// Where a card lands when it is dropped on another one.
///
/// **A UI test because the claim is a hit area.** The store's half is pinned by
/// `DropCaretTests` — `drop(_:at:)` inserts into the gap the caret names — and
/// it would pass just as happily if the two halves of a card were never wired
/// up, or were wired the wrong way round, or were laid out so that neither
/// could be reached with a finger. What only a real drag can say is which of
/// them the finger was actually in.
///
/// The card is dropped on the **upper** half of a row it is travelling
/// *downwards* towards, which is the case the old rule could not express: a drop
/// that named a card resolved by direction of travel, so coming from above meant
/// landing below, and the gap above the target was unreachable from anywhere
/// north of it.
///
/// **Both idioms**, and the board is re-seeded first — the simulator keeps
/// whatever the last run left, and this reads positions:
///
///     xcrun simctl uninstall <device> com.n14395.SimpleKanban
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
///
/// The phone was skipped here until its board pages stopped being a `List`:
/// hosted in collection view cells, a card released on a row landed nowhere at
/// all — measured with the half-row zones and with a plain whole-row
/// destination. They are ``PhoneColumnPage``'s stack now, and the same drag that
/// found nothing finds the gap it was aimed at. See `ColumnDropTests` for the
/// other half of that change, the ground around the cards.
final class CardDropTargetTests: XCTestCase {
    /// Three of Backlog's four seeded cards, in the order it starts in.
    private let first = "Board templates"
    private let second = "Shared boards"
    private let third = "Menu bar quick-add"

    override func setUp() {
        continueAfterFailure = false
    }

    /// A card by the words on it. The row combines its own children, so the
    /// label is the whole card and the title is inside it.
    private func card(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    func testACardDroppedOnTheTopHalfOfARowLandsAboveIt() {
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        // **The board, said out loud.** A phone lands on **Today** on a cold
        // launch — `BoardStore.landingSurface` — and Today is a flat list with
        // no columns in it, so without this the Backlog chip below never
        // arrives and the case fails at "no board" without reaching a drag.
        // `ColumnDropTests` and `GroundDropFootTests` name the tab for the same
        // reason; this one was written before the phone landed anywhere else
        // and was left behind when it did.
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanTab", "board",
        ]
        app.launch()
        // Backlog by name, which both idioms draw: a chip on the phone, a column
        // heading on the iPad. The phone opens on In Progress and has to be
        // sent there; the iPad has the whole board already. Matched on the
        // opening of the label rather than the whole of it — the phone's chip
        // carries the column's count as well as its name.
        let backlog = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Backlog"))
            .firstMatch
        XCTAssertTrue(backlog.waitForExistence(timeout: 20), "no board")
        if UIDevice.current.userInterfaceIdiom == .phone { backlog.tap() }
        XCTAssertTrue(card(first, in: app).waitForExistence(timeout: 10), "no cards in Backlog")
        let moving = card(first, in: app)
        let anchor = card(third, in: app)
        XCTAssertTrue(moving.waitForExistence(timeout: 5), "no card called \(first)")
        XCTAssertTrue(anchor.exists, "no card called \(third)")
        XCTAssertLessThan(moving.frame.minY, anchor.frame.minY, "the board did not start in order")
        // A press long enough to lift and short enough not to raise the
        // long-press menu, then down into the *upper* fifth of the third row.
        moving.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.55,
                thenDragTo: anchor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                withVelocity: .slow,
                thenHoldForDuration: 0.4
            )

        // Between the second and the third, which is the gap the caret drew.
        let settled = expectation(description: "the card landed")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            let moved = self.card(self.first, in: app)
            let middle = self.card(self.second, in: app)
            let below = self.card(self.third, in: app)
            guard moved.exists, middle.exists, below.exists else { return }
            if middle.frame.minY < moved.frame.minY, moved.frame.minY < below.frame.minY {
                timer.invalidate()
                settled.fulfill()
            }
        }
        wait(for: [settled], timeout: 10)
        poll.invalidate()
    }
}
