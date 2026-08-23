import XCTest

/// Where the tab bar is, and what is left in its slots.
///
/// **A UI test because the claim is a size class and a rotation.** `isShort` is
/// read in a view body and answers to the shape of the screen, so no store can
/// be asked; and what is being checked here is a *frame* — that the bar is up
/// the leading edge rather than along the foot, and that a slot on the rail is
/// a glyph in a square rather than a glyph and a word. Neither is visible to a
/// unit test. `ColumnStripTests` makes the same argument about the pager.
///
/// **iPhone simulator only** — the iPad has no tab bar; it has a source list.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
final class TabRailTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        // The orientation outlives the process, so a test that left the
        // simulator on its side would hand the next one a shape it did not ask
        // for. `ColumnStripTests` has the long version.
        XCUIDevice.shared.orientation = .portrait
    }

    func testTheBarIsAWordedFootInPortraitAndAGlyphRailInLandscape() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the tab bar is the phone's — the iPad has a source list"
        )
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES"]
        app.launch()

        // The quick-capture button is the bar's far end and is the one control
        // on it with a label nothing else shares.
        let capture = app.buttons["New task"]
        XCTAssertTrue(capture.waitForExistence(timeout: 15), "no tab bar")
        let board = app.buttons["Board"].firstMatch
        XCTAssertTrue(board.exists, "no Board slot on the tab bar")

        let portrait = app.frame
        XCTAssertGreaterThan(
            capture.frame.minY, portrait.height * 0.75,
            "the quick-capture button is not at the foot of the screen in portrait"
        )
        XCTAssertGreaterThan(
            board.frame.width, board.frame.height,
            "the Board slot's word is not running across the bar in portrait"
        )

        XCUIDevice.shared.orientation = .landscapeLeft
        // The rotation is not instant and the frames are read straight off the
        // tree, so wait for the shape to have actually changed rather than for
        // an element to appear — every one of them exists in both.
        let landscape = expectation(description: "the screen turned")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            if app.frame.width > app.frame.height {
                timer.invalidate()
                landscape.fulfill()
            }
        }
        wait(for: [landscape], timeout: 10)
        poll.invalidate()

        let turned = app.frame

        // A quarter of the width is generous: the rail is around 76pt of an
        // 850pt screen. What is being ruled out is the bar still being a bar.
        XCTAssertLessThan(
            capture.frame.maxX, turned.width * 0.25,
            "the quick-capture button is not on the leading edge in landscape"
        )
        XCTAssertLessThan(
            board.frame.maxX, turned.width * 0.25,
            "the Board slot is not on the leading edge in landscape"
        )
        // A word standing on end made the slot about 100pt long; a glyph in its
        // square is 44 by 44. This is what pins "only the icons remain".
        XCTAssertLessThan(
            board.frame.height, 60,
            "the Board slot still carries its word on the rail"
        )
        XCTAssertEqual(
            board.frame.height, board.frame.width, accuracy: 12,
            "the Board slot is not a glyph in a square"
        )
        // The board itself has to have been given the rest, rather than the rail
        // being laid over the top of it: the header's own control starts after
        // the rail ends.
        let drawer = app.buttons["Show boards"]
        XCTAssertTrue(drawer.exists, "no header in landscape")
        XCTAssertGreaterThan(
            drawer.frame.minX, capture.frame.maxX,
            "the rail is drawn over the board rather than beside it"
        )
    }
}
