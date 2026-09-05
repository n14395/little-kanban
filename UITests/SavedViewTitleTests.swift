import XCTest

/// What the phone says you are looking at, and what happens when you ask for it
/// twice.
///
/// **A UI test because both claims are about what is on screen.** A saved view
/// standing in front of the board takes the title — it used to be named in a
/// strip *under* the title, while the title went on naming the board you were
/// not looking at — and the strip is gone along with its Back to Board button.
/// Nothing a store can be asked knows which of those two the header is drawing:
/// `activeView` is the same either way.
///
/// The second is the rule the drawer got wrong. Picking the view you are already
/// on used to take you somewhere else, which makes a destination row a toggle
/// with two meanings and no way to tell which one you are about to get. It has
/// to close the drawer and change nothing.
///
///     xcodebuild test -scheme CardstockUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:CardstockUITests/SavedViewTitleTests
final class SavedViewTitleTests: XCTestCase {
    /// The header's title, found by identifier rather than by label: "Today" is
    /// a word the cards under it also use — a due chip says it — and a query by
    /// label picks whichever it reaches first.
    private let titleID = "PhoneHeaderTitle"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-CardstockSkipFirstRun", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Show boards"].waitForExistence(timeout: 15),
                      "the board never came up")
        return app
    }

    /// Opens the drawer and picks a view. The drawer closes itself on a pick, so
    /// every call has to open it again — but only if it is not already open:
    /// SwiftUI publishes the panel as an `Alert`, which XCUITest treats as an
    /// interruption and sometimes leaves standing, and a second tap on the
    /// hamburger with the drawer already up shuts it instead.
    private func pick(_ view: String, in app: XCUIApplication) {
        let close = app.buttons["Close"]
        if !close.exists {
            app.buttons["Show boards"].tap()
            XCTAssertTrue(close.waitForExistence(timeout: 5), "the drawer did not open")
        }
        let row = app.buttons[view]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(view) is not in the drawer")
        row.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5), "the drawer stayed open after a pick")
    }

    private func title(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", titleID))
            .firstMatch
    }

    /// Two views rather than a view against the board, because what the board's
    /// title says is not this suite's to know: the app may have resumed onto a
    /// view, and hard-coding a seed board's name would tie this to `SeedData`.
    /// A title that follows *which* view is open cannot be a title that names
    /// something else and happens to match.
    func testOpeningAViewPutsItsNameInTheTitle() throws {
        let app = launched()
        XCTAssertTrue(title(in: app).waitForExistence(timeout: 10), "the header has no title")

        pick("Today", in: app)
        XCTAssertEqual(title(in: app).label, "Today",
                       "the title does not name the view that is open")

        pick("Upcoming", in: app)
        XCTAssertEqual(title(in: app).label, "Upcoming",
                       "the title did not follow the next view")
    }

    /// The strip is gone, and with it the second way out of a view. The drawer
    /// one thumb away was always the first.
    func testAViewHasNoBarOfItsOwnUnderTheTitle() throws {
        let app = launched()
        pick("Today", in: app)
        XCTAssertEqual(title(in: app).label, "Today", "the view did not open")

        XCTAssertFalse(app.buttons["Back to board"].exists,
                       "the saved-view strip is still under the title")
    }

    func testPickingTheViewYouAreOnLeavesYouThere() throws {
        let app = launched()
        pick("Today", in: app)
        XCTAssertEqual(title(in: app).label, "Today", "the view did not open")

        pick("Today", in: app)

        XCTAssertEqual(title(in: app).label, "Today",
                       "picking the open view sent us somewhere else")
    }
}
