import XCTest

/// Re-ordering the board's columns by dragging one by its header.
///
/// **A UI test because the claim is the wiring.** `BoardStore.dropColumn` is
/// pinned by `ColumnReorderTests` and passes whether or not anything on screen
/// is attached to it: what a drag exercises is `.draggable` on the header, the
/// drop destination that is only in the tree while a column is in the air, and
/// which of the two destinations on a column gets the payload — the card one is
/// on the same view. Only a real press-and-drag can tell those apart.
///
/// **It is also the only thing that can say the lift wins the board's
/// scroller.** With `.draggable` on the name alone this failed exactly as a
/// user would see it: the board slid sideways under the finger and the column
/// did not move. Nothing in a store can tell that apart from a drop that was
/// refused. See `BoardColumnView.lifted()` for what the grip had to become.
///
/// **iPad only.** The phone draws one column per page and has no strip to
/// re-order; the desk has this board but not a simulator to drive it in.
///
/// The board is seeded on first launch, so a fresh install is the fixture — and
/// this reads positions, so a second run measures what the first one left:
///
///     xcrun simctl uninstall <device> com.n14395.SimpleKanban
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
final class ColumnDragTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A column by its header name. `staticTexts` rather than `buttons`: the
    /// name is the one part of the header that is not a control, so it is what
    /// a query can name — and pressing it presses the header behind it, which
    /// is the grip.
    private func columnName(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    func testAColumnDraggedByItsHeaderTakesTheTargetsPlace() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the phone has no column strip to re-order — one column fills the screen"
        )

        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES"]
        app.launch()

        let backlog = columnName("Backlog", in: app)
        let doing = columnName("In Progress", in: app)
        XCTAssertTrue(backlog.waitForExistence(timeout: 20), "no board on screen")
        XCTAssertTrue(doing.exists, "no In Progress column")
        XCTAssertLessThan(backlog.frame.minX, doing.frame.minX, "the board did not start in order")

        // Pressed on the name, which is the header, which is the grip. The drop
        // lands in the middle of the target column — the whole of it takes a
        // column while one is in the air.
        backlog.press(
            forDuration: 0.6,
            thenDragTo: doing,
            withVelocity: .slow,
            thenHoldForDuration: 0.6
        )

        // Backlog is now where In Progress was: third of four, so to the right
        // of it. Polled, because the move animates and the frames settle after.
        let settled = expectation(description: "the column landed")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            let moved = self.columnName("Backlog", in: app)
            let target = self.columnName("In Progress", in: app)
            guard moved.exists, target.exists else { return }
            if target.frame.minX < moved.frame.minX {
                timer.invalidate()
                settled.fulfill()
            }
        }
        wait(for: [settled], timeout: 10)
        poll.invalidate()
    }
}
