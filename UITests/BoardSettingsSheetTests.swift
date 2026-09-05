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
///     xcodebuild test -scheme CardstockUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:CardstockUITests/BoardSettingsSheetTests
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
            "-CardstockSkipFirstRun", "YES",
            "-CardstockOpenBoardSettings", "YES",
        ]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Board Settings"].waitForExistence(timeout: 20),
            "the board settings sheet never came up"
        )
        return app
    }

    /// Everything the sheet was built to hold, in one place: the board's name
    /// and icon — which on the phone existed nowhere at all — and its columns,
    /// which existed only one at a time behind a column header the phone does
    /// not draw.
    func testTheSheetHoldsTheBoardAndItsColumns() throws {
        let app = opened()

        for section in ["Name", "Icon", "Columns"] {
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

    /// **A new column is named, abbreviated and coloured in one go**, and the
    /// composer still clears the software keyboard now that it holds all three.
    ///
    /// **Landscape, because that is where this has already gone wrong once.**
    /// 402pt of phone minus a keyboard leaves around 238 for a composer that
    /// was near 200 when it carried a Role picker above its Name field — the
    /// picker measured unhittable, and every column made in landscape came out
    /// a Backlog with nothing said. The roles left in v9 and the Short field
    /// has taken back some of the height they freed, so the clearance is
    /// measured rather than assumed: `isHittable` is what a control being under
    /// the keyboard actually looks like from out here.
    ///
    /// Skipped where there is no software keyboard to clear — a simulator with
    /// a hardware keyboard attached would pass this whatever the layout did,
    /// and a test that cannot fail is worse than none.
    func testAColumnIsNamedAbbreviatedAndColouredClearOfTheKeyboard() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the keyboard only takes half the screen on a phone"
        )
        let app = opened()
        XCUIDevice.shared.orientation = .landscapeLeft

        let add = app.buttons["+ Add column"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "no way to add a column")
        add.tap()

        let name = app.textFields["Column name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the composer has no Name field")
        name.tap()
        name.typeText("Blocked")

        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 3) else {
            throw XCTSkip("no software keyboard on this simulator, so there is nothing to clear")
        }

        // The two controls that could not be reached before this change at all:
        // the abbreviation and the dot were editable only by making the column
        // and then opening the row that had just appeared.
        let short = app.textFields["Short name"]
        XCTAssertTrue(short.exists, "the composer has no Short field")
        XCTAssertTrue(
            short.isHittable,
            "the Short field is under the keyboard — \(short.frame) against \(keyboard.frame)"
        )
        let well = try XCTUnwrap(
            composerColourWell(beside: name, in: app), "the composer has no colour control"
        )
        XCTAssertTrue(
            well.isHittable,
            "the colour well is under the keyboard — \(well.frame) against \(keyboard.frame)"
        )
        let confirm = app.buttons["Add Column"]
        XCTAssertTrue(
            confirm.isHittable,
            "Add Column is under the keyboard — \(confirm.frame) against \(keyboard.frame)"
        )

        short.tap()
        short.typeText("Blk")
        // **This measures the well and does not press it**, which is now a
        // scope line rather than a scar. The claim this test is *for* is the
        // keyboard, and the well is the control the keyboard could cover.
        //
        // It used to be a scar: pressing the well opened a popover XCUITest
        // found at x≈744, y≈−124 on a 402pt screen, could not scroll to and
        // could not close. The cause was the well naming an arrow edge, which
        // on iOS is the only placement UIKit may use rather than the one it
        // prefers — see ``ColorWell/arrowEdge``. Touch leaves it unnamed now
        // and the picker scrolls when it is squeezed, so pressing through it
        // is a test somebody can write; it belongs to the picker rather than
        // to the keyboard, which is why it is not written here.

        confirm.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5), "the composer stayed open")
        XCTAssertNotNil(columnRow("Blocked", in: app), "the column was never added")
    }

    /// The composer's colour control, found *below* the Name field this
    /// composer owns.
    ///
    /// It used to look for a swatch named "Indigo", because the composer drew a
    /// row of six of them. `DotPicker` is gone — every colour in the app is now
    /// picked with one ``ColorWell``, a button labelled *Select Colour* wearing
    /// the colour it has, with the colour's name as its accessibility *value*
    /// rather than its label. See **The colour picker** in the README.
    ///
    /// The frame filter used to be what told this control from the board's own
    /// colour well above the columns. Since v16 the board wears an icon and its
    /// well says *Select Icon*, so a column's is the only thing this query can
    /// match — the filter stays because a *second* composer, open on another
    /// column, would bring the ambiguity straight back.
    private func composerColourWell(
        beside name: XCUIElement, in app: XCUIApplication
    ) -> XCUIElement? {
        app.buttons
            .matching(NSPredicate(format: "label == %@", "Select Colour"))
            .allElementsBoundByIndex
            .first { $0.frame.minY >= name.frame.minY - 1 }
    }

    /// **Dragging a column row lands it in the gap the caret marked**, which is
    /// the wiring `ColumnReorderTests` cannot see: `dropColumn(_:at:)` answers
    /// the same whether or not anything on screen is attached to it.
    ///
    /// What a real drag exercises is the lift — the payload closure
    /// `.draggable` evaluates when the *session* starts, which is the only
    /// signal this sheet has that a column is in the air — and the two
    /// half-height drop zones that are in the tree only while one is.
    ///
    /// **Aimed at the top of a row while dragging downwards**, which is the one
    /// aim the two rules disagree about and is exactly the report that started
    /// this: dropping Backlog on In Progress used to land it *after* In
    /// Progress, because a drop that names a row can only be resolved by the
    /// direction of travel. The gap the pointer is in says *before*, so this
    /// asserts Backlog second rather than third — the old rule satisfies every
    /// other line here and fails that one.
    ///
    /// Re-seeded first: this reads positions, so a second run on the same
    /// simulator would otherwise measure what the first one left.
    func testAColumnDraggedIntoAGapLandsInIt() throws {
        let app = opened()

        let backlog = try XCTUnwrap(columnRow("Backlog", in: app), "no Backlog column")
        let upNext = try XCTUnwrap(columnRow("Up Next", in: app), "no Up Next column")
        let inProgress = try XCTUnwrap(columnRow("In Progress", in: app), "no In Progress column")
        XCTAssertLessThan(
            backlog.frame.minY, upNext.frame.minY, "the sheet did not start in board order"
        )
        XCTAssertLessThan(
            upNext.frame.minY, inProgress.frame.minY, "the sheet did not start in board order"
        )

        // The top of In Progress: the half that means *above this column*,
        // which is the gap between it and Up Next.
        let grip = backlog.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let gap = inProgress.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        grip.press(
            forDuration: 0.6, thenDragTo: gap, withVelocity: .slow, thenHoldForDuration: 0.6
        )

        // Polled, because the rows animate into place and their frames settle
        // after the gesture ends — the same wait the board strip's drag needed.
        let landed = expectation(description: "the column landed in the gap it was aimed at")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            guard let moved = self.columnRow("Backlog", in: app),
                  let above = self.columnRow("Up Next", in: app),
                  let below = self.columnRow("In Progress", in: app)
            else { return }
            if above.frame.minY < moved.frame.minY, moved.frame.minY < below.frame.minY {
                timer.invalidate()
                landed.fulfill()
            }
        }
        wait(for: [landed], timeout: 10)
        poll.invalidate()

        // And Done is still last, which is what makes it the Done column.
        let done = try XCTUnwrap(columnRow("Done", in: app), "the board lost its Done column")
        let moved = try XCTUnwrap(columnRow("Backlog", in: app), "the board lost the column it moved")
        XCTAssertLessThan(moved.frame.minY, done.frame.minY, "the column landed past Done")
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
