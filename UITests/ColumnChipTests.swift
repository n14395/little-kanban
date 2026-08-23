import XCTest

/// The strip of column chips at the top of the phone's board, and whether the
/// one naming the column you are on is actually on the screen.
///
/// Four columns with ordinary names overrun a phone: on the seed board the Done
/// chip is 70pt wide and the strip clips at 19 of them. Paging to Done used to
/// highlight a chip that was half off the edge and leave it there — the one
/// control on the surface whose whole job is saying where you are.
///
/// **A UI test because the claim is a scroll offset.** Nothing a store can be
/// asked knows where a chip is; `scrollTo` leaves no value behind, and the only
/// way to tell whether it moved is to measure a chip against the strip that
/// clips it.
///
/// **iPhone portrait only** — on its side the phone drops the chips for the
/// per-page headings, and the iPad has no strip at all.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17e'
final class ColumnChipTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// A chip, by the label the row combines — the name and its count. The
    /// buttons rather than every element with that label: a page heading names
    /// its column too, and one of those would measure the wrong thing entirely.
    private func chip(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    func testTheStripBringsTheColumnYouAreOnIntoView() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the chips are the phone's; the iPad draws the whole board"
        )
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES"]
        app.launch()

        let done = chip("Done, 3", in: app)
        XCTAssertTrue(done.waitForExistence(timeout: 20), "no column chips on screen")
        // The strip is the scroll view the chips are drawn in, which is the one
        // above the board's own — the board's fills the rest of the screen.
        let strip = app.scrollViews.allElementsBoundByIndex
            .min { $0.frame.minY < $1.frame.minY }
        let bounds = try XCTUnwrap(strip?.frame, "no strip to measure against")
        XCTAssertLessThan(bounds.height, 100, "that is the board, not the chip strip")

        // The fixture is the overrun itself: with every chip already in view
        // there would be nothing to scroll and this would pass on any build.
        XCTAssertGreaterThan(done.frame.maxX, bounds.maxX,
                             "the chips all fit — this board cannot show the defect")

        // To the last column. Swiped through the app rather than tapped on a
        // chip: the chip for the column this is about is the one off the edge,
        // which is the thing that cannot be tapped.
        for _ in 0..<3 where !done.isSelected {
            app.swipeLeft()
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(done.isSelected, "never reached the last column")

        XCTAssertLessThanOrEqual(done.frame.maxX, bounds.maxX + 1,
                                 "the chip for the column you are on is cut off at the trailing edge")
        XCTAssertGreaterThanOrEqual(done.frame.minX, bounds.minX - 1,
                                    "the chip for the column you are on is cut off at the leading edge")

        // …and back, because a strip that scrolls one way and not the other
        // would pass the half of this that matters least.
        let backlog = chip("Backlog, 4", in: app)
        for _ in 0..<3 where !backlog.isSelected {
            app.swipeRight()
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(backlog.isSelected, "never got back to the first column")
        XCTAssertGreaterThanOrEqual(backlog.frame.minX, bounds.minX - 1,
                                    "the strip did not come back for the first column")
    }
}
