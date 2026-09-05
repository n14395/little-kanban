import XCTest

/// The board getting out from under the detail panel.
///
/// The panel opens *beside* the board and takes its width out of the board's,
/// so a card picked at the right-hand edge is behind the panel by the time the
/// panel is there — selected, its own detail on screen, and the card itself no
/// longer visible.
///
/// **A UI test because the claim is about pixels.** `scrollTo` goes to a
/// `ScrollViewProxy`: nothing to read back, no record of having been called, so
/// `BoardRevealTests` can only pin the wiring. Whether the card ends up clear
/// of the panel is a question the running app has to answer — and the two
/// spellings that do not work look identical in source to the one that does.
/// Measured on macOS through the accessibility API while this was written, and
/// asserted here because the iPad is the surface a test can drive: a scroll
/// issued as the panel opens, and one issued a runloop turn later, both left
/// the card exactly where it was under a panel arriving over the top of it.
///
/// **iPad only.** The phone draws one column per page and has no panel beside
/// it; its detail is a sheet over the whole screen.
///
///     xcrun simctl uninstall <device> com.n14395.Cardstock
///     xcodebuild test -scheme CardstockUITests \
///       -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
final class InspectorRevealTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// One card per seeded column, left to right. The fixture is the seed
    /// board, as it is for every other test here; what this needs from it is
    /// only that the columns are in a known order and each has something in it.
    private static let cards = [
        "Board templates",
        "Offline queue for edits",
        "Drag-and-drop between columns",
        "Sync engine v2",
    ]

    private func card(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    func testACardPickedAtTheBoardsEdgeEndsUpClearOfThePanel() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the phone has no panel beside the board — its detail is a sheet over the whole screen"
        )

        let app = XCUIApplication()
        app.launchArguments = [
            "-CardstockSkipFirstRun", "YES",
            // The panel has to *arrive* for there to be anything to measure.
            "-CardstockHideInspector", "YES",
        ]
        app.launch()

        XCTAssertTrue(card(Self.cards[0], in: app).waitForExistence(timeout: 20), "no board on screen")

        // The rightmost card the board is actually showing whole, which is the
        // one the panel is about to arrive on top of. Found rather than named:
        // how many columns fit depends on the iPad and on which way up it is,
        // and a hard-coded column is a test that measures nothing on the
        // devices where that column was off screen anyway.
        let window = app.windows.firstMatch.frame
        let atRisk = Self.cards
            .map { card($0, in: app) }
            .filter { $0.exists && $0.frame.maxX <= window.maxX && $0.frame.minX >= window.minX }
            .max { $0.frame.maxX < $1.frame.maxX }
        let picked = try XCTUnwrap(atRisk, "the board is not showing a whole card, so there is nothing to cover")
        let before = picked.frame

        picked.tap()

        // The panel's own title field, which is the leftmost thing in it that a
        // query can name — so it sits *inside* the panel's leading edge, and
        // every assertion against it is the stricter one.
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the panel did not open")
        let panelEdge = title.frame.minX

        // Without this the test could pass on a board wide enough that nothing
        // was ever covered — which is most of what a bigger iPad in landscape
        // is, and exactly the shape a green run would be least deserved on.
        XCTAssertGreaterThan(
            before.maxX, panelEdge,
            "the card was never behind the panel, so this run proves nothing about the scroll"
        )

        // Polled: the board moves once the panel has finished taking its width,
        // which is deliberately after the tap rather than with it.
        let settled = expectation(description: "the board moved out from under the panel")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            if picked.exists, picked.frame.maxX <= panelEdge {
                timer.invalidate()
                settled.fulfill()
            }
        }
        wait(for: [settled], timeout: 10)
        poll.invalidate()

        // And it moved the least it could: the card is still on the board's
        // right-hand side rather than dragged to the far edge of it.
        XCTAssertGreaterThan(
            picked.frame.minX, window.minX,
            "the board scrolled further than showing the card needed"
        )
    }

    /// The other half, so the first cannot be satisfied by scrolling the board
    /// whenever the panel is touched: a card nowhere near the right-hand edge
    /// is not covered by anything, and the board must sit still for it.
    func testACardWellClearOfThePanelDoesNotMoveTheBoard() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the phone has no panel beside the board"
        )

        let app = XCUIApplication()
        app.launchArguments = [
            "-CardstockSkipFirstRun", "YES",
            "-CardstockHideInspector", "YES",
        ]
        app.launch()

        let leftmost = card(Self.cards[0], in: app)
        XCTAssertTrue(leftmost.waitForExistence(timeout: 20), "no board on screen")
        let before = leftmost.frame

        leftmost.tap()

        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the panel did not open")
        XCTAssertLessThan(
            before.maxX, title.frame.minX,
            "the leftmost card is behind the panel, so this run cannot tell a still board from a scrolled one"
        )

        // Long enough for the panel to have taken its width and for the scroll
        // that would follow to have happened. Nothing should have.
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(
            leftmost.frame.minX, before.minX, accuracy: 1,
            "the board scrolled for a card that was never covered"
        )
    }
}
