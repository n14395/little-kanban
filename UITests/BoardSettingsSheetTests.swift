import XCTest

/// The board's own settings, as a surface: that every route reaches it, and that
/// the one control in it which moves other people's cards asks first.
///
/// **A UI test because both claims are about what is on screen.**
/// `BoardSettingsTests` pins the numbers a warning quotes — how many cards a
/// column holds, where they would land, which column completed work goes to —
/// and every one of them would go on being right with the alert deleted, the
/// button wired straight to `trashColumn`, and a column's cards moved on a tap.
///
/// **iOS simulator**, both idioms: the sheet is the same view on the phone and
/// the iPad, and on the desk at its own sizes.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:SimpleKanbanUITests/BoardSettingsSheetTests
final class BoardSettingsSheetTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Straight in through the launch hook rather than through a menu: which
    /// control opens it is the next test's business, and tapping through two
    /// surfaces to reach the one under test is two more ways to fail for a
    /// reason that is not about the sheet.
    private func opened() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanOpenBoardSettings", "YES",
        ]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Board Settings"].waitForExistence(timeout: 20),
            "the board settings sheet never came up"
        )
        return app
    }

    /// Everything the sheet was built to hold, in one place: the board's name
    /// and colour — which on the phone existed nowhere at all — and its columns,
    /// which existed only one at a time behind a column header the phone does
    /// not draw.
    func testTheSheetHoldsTheBoardAndItsColumns() throws {
        let app = opened()

        for section in ["Name", "Colour", "Columns"] {
            let label = app.staticTexts
                .matching(NSPredicate(format: "label ==[c] %@", section))
                .firstMatch
            XCTAssertTrue(label.exists, "the sheet has no \(section) section")
        }
        XCTAssertTrue(app.textFields["Board name"].exists, "the board cannot be renamed here")
        // The seeded board's four columns, each a row of its own.
        for column in ["Backlog", "Up Next", "In Progress", "Done"] {
            XCTAssertNotNil(columnRow(column, in: app), "\(column) is not listed")
        }
        XCTAssertTrue(app.buttons["+ Add column"].exists, "no way to add a column")
    }

    /// A column's row **inside the sheet**, which on the iPad is not the only
    /// thing on screen called "Up Next": the board behind a form sheet stays
    /// enumerable, and the task inspector's status segments are buttons with a
    /// column's name on them. The sheet's rows are the ones between its header
    /// and its Trash Board button.
    private func columnRow(_ name: String, in app: XCUIApplication) -> XCUIElement? {
        let header = app.staticTexts["Board Settings"].frame
        let foot = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Trash Board"))
            .firstMatch.frame
        return app.buttons
            .matching(NSPredicate(format: "label == %@", name))
            .allElementsBoundByIndex
            .first { $0.frame.minY > header.maxY && $0.frame.maxY < foot.minY }
    }

    /// **The warning.** Trashing a column moves every card on it somewhere else,
    /// and the cards are not necessarily the cards of whoever is in here
    /// reshaping a board — so the button asks, in this board's own numbers, and
    /// Cancel leaves the column exactly where it was.
    func testTrashingAColumnAsksFirstAndCancelKeepsIt() throws {
        let app = opened()

        let row = try XCTUnwrap(columnRow("Up Next", in: app), "no Up Next column to trash")
        row.tap()

        let trash = app.buttons["Trash Column"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5), "the column's editor has no Trash")
        trash.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "the column was trashed without asking")
        XCTAssertTrue(
            alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Up Next")).count > 0,
            "the alert does not say which column"
        )
        XCTAssertTrue(
            alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "cards move")).count > 0,
            "the alert does not say what happens to the cards"
        )
        XCTAssertTrue(
            alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Trash")).count > 0,
            "the alert does not say the column can be fetched back"
        )

        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), "the alert would not go away")
        XCTAssertNotNil(columnRow("Up Next", in: app), "Cancel trashed the column anyway")
    }
}
