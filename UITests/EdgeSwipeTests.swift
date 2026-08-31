import XCTest

/// The edge swipe — a pull inwards from the screen's leading edge, which is how
/// every other iOS app reaches what is parked behind that edge, and which on
/// this one brings out the phone's drawer and the iPad's source list.
///
/// **No unit test can reach this one either.** What the gesture exercises is
/// which recognizer gets the pan: the board is a horizontal scroll view on both
/// idioms, and a `DragGesture` on a strip at the edge loses to it — the same
/// rule that took the swipe actions off the board's rows. Only a real
/// press-and-drag over the board can tell a `UIScreenEdgePanGestureRecognizer`
/// that won from one that was swallowed, which is why this is a UI test and why
/// every swipe here starts over the board rather than over a flat list.
///
/// **Both idioms, and each skips on the other.** The phone opens a drawer and
/// the iPad reveals a split view's source list, so the two cases are different
/// surfaces and different assertions — but they are one gesture and one bug if
/// it regresses, which is why they are one file:
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
final class EdgeSwipeTests: XCTestCase {
    /// The drawer's own dismiss button. By label, and now the only "Close" on
    /// the phone at all: the detail sheet and the Inbox panel each had one and
    /// neither does any more — both are put away by pulling them down. The
    /// drawer keeps its ✕ because it comes in from the side, where there is no
    /// grabber saying so.
    private let drawerClose = "Close"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launched(on idiom: UIUserInterfaceIdiom) throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == idiom,
            "this half of the gesture belongs to the other idiom"
        )
        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES"]
        app.launch()
        return app
    }

    /// Where a pan starts and where it lets go. `dx: 0` is the screen's own
    /// edge, which is what the recognizer requires; `dy: 0.5` puts it squarely
    /// over the pager, which is the container that would otherwise claim it.
    private func swipe(
        _ app: XCUIApplication, fromX: CGFloat, toX: CGFloat,
        velocity: XCUIGestureVelocity = .default
    ) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: velocity,
                    thenHoldForDuration: 0.1)
    }

    func testAPullFromTheLeadingEdgeOpensTheDrawer() throws {
        let app = try launched(on: .phone)

        let hamburger = app.buttons["Show boards"]
        XCTAssertTrue(hamburger.waitForExistence(timeout: 10), "the board never came up")
        XCTAssertFalse(app.buttons[drawerClose].exists, "the drawer was open before the swipe")

        swipe(app, fromX: 0, toX: 0.7)

        XCTAssertTrue(app.buttons[drawerClose].waitForExistence(timeout: 5),
                      "the edge swipe did not open the drawer")
    }

    /// The drawer follows the finger, so where the finger stops decides.
    ///
    /// **This is the check that the pan is being *followed* rather than merely
    /// noticed.** It used to arrive whole on the recognizer's first report and
    /// slide itself in over its own 0.28s while the finger went wherever it
    /// liked, so a pull of a fifth of the screen and a pull of most of it were
    /// the same act and both ended with the drawer open. Now the panel is
    /// wherever the finger is and the lift decides. An intermediate frame is not
    /// something XCUITest can be asked about, but the two ends of the same slow
    /// drag are, and under the old rule they could not have differed.
    ///
    /// **Slowly**, both of them. A throw is allowed to open the drawer from
    /// anywhere — that is what `drawerFlick` is for, and it is what makes the
    /// full-width swipe above pass whatever its distance — so a test about
    /// *distance* has to take the throw out of it.
    func testASlowPullIsJudgedOnHowFarItCame() throws {
        let app = try launched(on: .phone)
        let hamburger = app.buttons["Show boards"]
        XCTAssertTrue(hamburger.waitForExistence(timeout: 10), "the board never came up")

        // A fifth of the screen is a quarter of the way in: not far enough.
        swipe(app, fromX: 0, toX: 0.2, velocity: .slow)
        XCTAssertTrue(app.buttons[drawerClose].waitForNonExistence(timeout: 5),
                      "a slow pull that stopped short left the drawer open")
        XCTAssertTrue(hamburger.exists, "the board did not come back")

        // The same drag, taken past the middle of the panel.
        swipe(app, fromX: 0, toX: 0.8, velocity: .slow)
        XCTAssertTrue(app.buttons[drawerClose].waitForExistence(timeout: 5),
                      "a slow pull that came most of the way did not open the drawer")
    }

    /// The other half, and the one that fails if the gesture is too greedy.
    ///
    /// Every competing pan is made to wait for the edge recognizer to give up
    /// (`shouldBeRequiredToFailBy`), so the claim this has to check is not only
    /// that the drawer stays shut but that the pager still *works*: a rule that
    /// held the board's swipe would have traded one gesture for another. It
    /// reads the dots, which carry `.isSelected` on the column the board is on.
    func testASwipeFromTheMiddleOfTheBoardStillPagesIt() throws {
        // The dots this reads are portrait's — in landscape three columns share
        // the screen under their own headings and the strip is not drawn.
        XCUIDevice.shared.orientation = .portrait
        let app = try launched(on: .phone)

        XCTAssertTrue(app.buttons["Show boards"].waitForExistence(timeout: 10),
                      "the board never came up")
        let before = try XCTUnwrap(selectedColumn(in: app), "no column dot is selected")

        swipe(app, fromX: 0.5, toX: 0.95)

        XCTAssertFalse(app.buttons[drawerClose].exists,
                       "a swipe from the middle of the board opened the drawer")
        // The pager animates, so the dot is read after it has settled rather
        // than in the same frame the finger lifted.
        var after = selectedColumn(in: app)
        let deadline = Date().addingTimeInterval(3)
        while after == before, Date() < deadline { after = selectedColumn(in: app) }
        XCTAssertNotEqual(after, before,
                          "the board did not page — the edge gesture took the pager's swipe")
    }

    /// Which column the dots say the board is on. They are buttons labelled by
    /// column name, and the current one carries `.isSelected`.
    private func selectedColumn(in app: XCUIApplication) -> String? {
        for name in ["Backlog", "Up Next", "In Progress", "Done"] {
            let dot = app.buttons[name]
            if dot.exists, dot.isSelected { return name }
        }
        return nil
    }

    /// The iPad's half. A `NavigationSplitView` looks like it should answer this
    /// on its own — `UISplitViewController` has `presentsWithGesture`, and it is
    /// on by default — and measured here it did not: before `leadingEdgeSwipe`
    /// was wired to `PadRootView`, this test failed with the source list exactly
    /// where it started. The board's horizontal scroll view was taking the pan.
    ///
    /// Portrait, because that is the shape where the list is off screen and the
    /// gesture has something to do.
    func testAPullFromTheLeadingEdgeRevealsTheSourceList() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = try launched(on: .pad)

        XCTAssertTrue(app.buttons["Toggle sidebar"].waitForExistence(timeout: 15),
                      "the board never came up")
        let boardRow = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Northwind")).firstMatch
        XCTAssertFalse(boardRow.exists, "the source list was already out in portrait")

        swipe(app, fromX: 0, toX: 0.6)

        XCTAssertTrue(boardRow.waitForExistence(timeout: 5),
                      "the edge pull did not bring out the source list")
    }
}
