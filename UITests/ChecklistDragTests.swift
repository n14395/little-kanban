import XCTest

/// Re-ordering a checklist by dragging a row's grip.
///
/// **A UI test because the defect was the wiring, not the rule.**
/// `BoardStore.dropSubtask` is covered by `SubtaskReorderTests` and answered
/// correctly the whole time this gesture was unusable: what was wrong was that
/// nothing on screen could start the drag. The row *was* the grip, on the
/// bargain that a drag begun inside its text field belonged to the field and
/// everything else started a reorder — and what "everything else" came to was
/// 8pt of padding at either end and the tick's square, the tick being a button
/// that takes the press first.
///
/// Measured here, on this simulator, before the grip existed:
///
///     press-and-drag on the row's gutter   → the order did not change
///     press-and-drag on the row's text     → ["Lift + shadow states",
///                                             "Column drop targets",
///                                             "Keyboard fallback Lift + shadow states"]
///
/// The second is the one worth keeping in view. The field's own drag ran
/// instead of the row's, so the gesture a user would reach for did not reorder
/// the checklist — it *edited* it, pasting one row's text into the end of
/// another. Only a real press-and-drag can tell that apart from a working
/// reorder, which is what this suite is for and why the texts are asserted
/// rather than just the order.
///
/// **The claim is "on every platform", and this is the platform that can be
/// driven.** `ChecklistView` is one view — the macOS inspector, the iPad's and
/// the phone's sheet all draw it — so the grip that runs here is the grip the
/// desk draws; `SubtaskReorderTests.theGripIsDrawnOnEveryPlatform` is what
/// stops that from quietly becoming untrue. Driving the host Mac's pointer is
/// not a verification, it is a fight with whoever is using the machine.
///
/// Each case launches fresh and asserts against the order it *found*, not
/// against the seed: these tests reorder a persisted board, so the second one
/// to run starts where the first one finished. What they cannot survive is a
/// board with no card on it, so a fresh install is the fixture — the same one
/// `InboxDragTests` needs, and for the same reason. Without it this suite
/// reports "no card to open" against whatever the last suite to run left
/// behind, which on the machine this was written on was a board somebody's
/// column tests had emptied.
///
///     xcrun simctl uninstall <device> com.n14395.Cardstock
///     xcodebuild test -scheme CardstockUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:CardstockUITests/ChecklistDragTests
final class ChecklistDragTests: XCTestCase {
    /// The seed card with a three-row checklist — enough rows that "up",
    /// "down" and "to the end" are three different places.
    private let card = "Drag-and-drop between columns"

    override func setUp() {
        continueAfterFailure = false
    }

    private func opened() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "driving the desk's pointer is not a verification; the phone draws the same checklist"
        )
        let app = XCUIApplication()
        app.launchArguments = ["-CardstockSkipFirstRun", "YES", "-CardstockTab", "board"]
        app.launch()

        let subject = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", card))
            .firstMatch
        XCTAssertTrue(subject.waitForExistence(timeout: 15), "no card to open — is the board seeded?")
        subject.tap()

        XCTAssertTrue(rows(app).element(boundBy: 0).waitForExistence(timeout: 10), "no checklist in the sheet")
        liftTheChecklistOffTheFoot(app)
        return app
    }

    /// Scrolls the sheet until the last checklist row is clear of the bottom of
    /// the screen.
    ///
    /// **Not a nicety — the case for the foot of the list cannot be run without
    /// it.** The checklist is the seventh section of the sheet, so on a card
    /// this size the last row lands about 28pt from the bottom edge, and a drag
    /// released there is in the band where iOS auto-scrolls the content it is
    /// over. The rows move under a pointer the test is holding still, and the
    /// drop lands in a gap nobody aimed at — measured as "dragging the first row
    /// onto the last changed nothing", while the identical gesture onto the
    /// *middle* row passed. A hand adapts to the scroll; a fixed coordinate
    /// cannot, so the geometry is made ordinary first and every case here then
    /// runs on the same one.
    private func liftTheChecklistOffTheFoot(_ app: XCUIApplication) {
        let floor = app.frame.height - 150
        for _ in 0..<3 {
            let fields = rows(app)
            guard fields.count > 0, fields.element(boundBy: fields.count - 1).frame.maxY >= floor else { return }
            // A flick rather than a press: a long press here would be a lift.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)),
                       withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    /// Every row's field, in the order they are drawn. They share one
    /// accessibility label — a placeholder is not a name, and the row's text is
    /// its *value* — so the query is the list and the index is the position.
    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.textFields.matching(NSPredicate(format: "label == %@", "Sub-task"))
    }

    private func order(_ app: XCUIApplication) -> [String] {
        let fields = rows(app)
        return (0..<fields.count).compactMap { fields.element(boundBy: $0).value as? String }
    }

    /// Presses the grip of row `from` and drags it onto a half of row `onto`.
    ///
    /// The grip is `accessibilityHidden` — a drag is not something a reader can
    /// perform, and Move Up / Move Down in the row's context menu is what they
    /// get instead — so there is no element to query and the press is aimed by
    /// coordinate. It sits just past the trailing edge of the field, in the same
    /// row: `+24` clears the 11pt gap and lands in the middle of the 30pt square
    /// the grip claims.
    ///
    /// `half` is which half of the target row to release over, and that is the
    /// whole of what the drop means: above it, or below it.
    ///
    /// **`shift` is the stand-in's doing, and the reason it is a parameter.**
    /// The gap the drag opens is a real row's worth of height, and everything
    /// below it moves down by exactly that — so a coordinate worked out from the
    /// list *before* the drag stops naming the row it named as soon as a gap
    /// opens above that row. A hand does not have this problem: it watches the
    /// gap and stops when the gap is in the right place, which is the whole
    /// point of drawing one. A fixed coordinate has to be told, and `pitch(_:)`
    /// is what it is told in.
    private func drag(
        _ app: XCUIApplication, row from: Int, onto: Int, half: CGFloat, shift: CGFloat = 0
    ) {
        let fields = rows(app)
        let source = fields.element(boundBy: from).frame
        let target = fields.element(boundBy: onto).frame
        let gripX = source.maxX + 24
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: gripX, dy: source.midY))
        let end = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: gripX, dy: target.midY + half + shift))
        // A long press is what lifts a row on touch, and the hold at the far end
        // is what gives the drop zone under the pointer time to take it.
        start.press(forDuration: 1.0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1.2)
    }

    /// One row of travel, measured off the list rather than assumed: the rows
    /// are 44pt as laid out and a little under that as drawn, because the sheet
    /// is laid out full width and then scaled — see `PhoneDetailSheet`.
    private func pitch(_ app: XCUIApplication) -> CGFloat {
        let fields = rows(app)
        return fields.element(boundBy: 1).frame.midY - fields.element(boundBy: 0).frame.midY
    }

    /// How far past a row's middle counts as its other half. 14 is clear of the
    /// middle and clear of the edge of a ~42pt row.
    private let half: CGFloat = 14

    func testARowDraggedDownLandsBelowTheRowItWasAimedAt() throws {
        let app = try opened()
        let before = order(app)
        XCTAssertEqual(before.count, 3, "this case needs the three-row checklist")

        drag(app, row: 0, onto: 1, half: half)

        XCTAssertEqual(
            order(app), [before[1], before[0], before[2]],
            "dragging the first row into the bottom half of the second did not put it second"
        )
    }

    func testARowDraggedUpLandsAboveTheRowItWasAimedAt() throws {
        let app = try opened()
        let before = order(app)
        XCTAssertEqual(before.count, 3, "this case needs the three-row checklist")

        drag(app, row: 2, onto: 0, half: -half)

        XCTAssertEqual(
            order(app), [before[2], before[0], before[1]],
            "dragging the last row into the top half of the first did not put it first"
        )
    }

    /// The foot of the list, which is the last row's own bottom half: there is
    /// no row below it to aim at, and the add row underneath is a field rather
    /// than a target.
    ///
    /// **The only case that has to travel past a row to get where it is going**,
    /// and so the only one that pays `shift`. Going from the first row to the
    /// last, the gap opens under the second row on the way — which pushes the
    /// third one down by a row before the pointer ever reaches it. Without the
    /// extra row of travel the release lands in the gap it opened *en route*,
    /// which is one place short: measured, and it put the row second rather than
    /// last. The other two cases open their gap at or beyond the row they are
    /// aimed at, so nothing they are aiming for ever moves.
    func testARowCanBeDraggedToTheFootOfTheList() throws {
        let app = try opened()
        let before = order(app)
        XCTAssertEqual(before.count, 3, "this case needs the three-row checklist")

        drag(app, row: 0, onto: 2, half: half, shift: pitch(app))

        XCTAssertEqual(
            order(app), [before[1], before[2], before[0]],
            "dragging the first row into the bottom half of the last did not put it last"
        )
    }

    /// **A row can be dragged again straight after it has been dropped.**
    ///
    /// **Every coordinate is worked out before either drag starts**, and that is
    /// the point of the case rather than a tidiness: reading the list between
    /// the two puts most of a second between them, and a second is long enough
    /// for anything settling after a drop to have settled. The bug this exists
    /// for lives in that second. The rows are a fixed pitch apart and the first
    /// drag only swaps two of them, so where everything will be is known in
    /// advance and nothing has to be asked.
    func testARowCanBeDraggedAgainStraightAfterADrop() throws {
        let app = try opened()
        let before = order(app)
        XCTAssertEqual(before.count, 3, "this case needs the three-row checklist")

        let fields = rows(app)
        let first = fields.element(boundBy: 0).frame
        let second = fields.element(boundBy: 1).frame
        let third = fields.element(boundBy: 2).frame
        let step = second.midY - first.midY
        let gripX = first.maxX + 24
        func at(_ y: CGFloat) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: gripX, dy: y))
        }

        // Row one into the bottom half of row two, which swaps them.
        at(first.midY).press(forDuration: 1.0, thenDragTo: at(second.midY + half),
                             withVelocity: .slow, thenHoldForDuration: 1.2)

        // Straight on, no reading in between: the same row is now the middle
        // one, and it travels past the last — so it pays a row of `shift`, for
        // `testARowCanBeDraggedToTheFootOfTheList`'s reason.
        at(second.midY).press(forDuration: 1.0, thenDragTo: at(third.midY + half + step),
                              withVelocity: .slow, thenHoldForDuration: 1.2)

        XCTAssertEqual(
            order(app), [before[1], before[2], before[0]],
            "the second drag did not move the row — the handle came away from it"
        )
    }

    /// **A long press on the grip starts a drag and nothing else.**
    ///
    /// It used to put the row's context menu on screen over the drag that was
    /// starting — the menu was on the whole row, and a long press is how both a
    /// menu and a touch drag begin, so taking hold of the handle did both.
    /// Reported from a phone, and invisible to the cases above: the drag *did*
    /// start, so a test that only asks where the row landed passes with the menu
    /// sitting over the screen.
    ///
    /// Pressed and held without travelling, which is the gesture that opened it.
    func testALongPressOnTheGripOpensNoMenu() throws {
        let app = try opened()
        let source = rows(app).element(boundBy: 0).frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: source.maxX + 24, dy: source.midY))
            .press(forDuration: 1.5)

        for item in ["Delete Sub-task", "Move Down", "Move Up"] {
            XCTAssertFalse(
                app.buttons[item].waitForExistence(timeout: 2),
                "a long press on the grip opened the row's menu — \(item) is on screen"
            )
        }
    }

    /// And the other half of that trade, which is what stops the fix from being
    /// "the menu was removed": everything in the row *except* the grip still
    /// opens it. The text is the part of a row a finger naturally lands on.
    func testALongPressOnTheRowStillOpensItsMenu() throws {
        let app = try opened()
        let row = rows(app).element(boundBy: 0)
        row.press(forDuration: 1.5)

        XCTAssertTrue(
            app.buttons["Delete Sub-task"].waitForExistence(timeout: 5),
            "a long press on the row no longer opens its context menu"
        )
    }

    /// **The rows moved, and their text did not.** This is the regression the
    /// suite note describes: before the grip, the gesture that looked like a
    /// reorder ran the text field's own drag and appended one row's words to
    /// another's. The set of texts surviving a drag unchanged is what says the
    /// rows travelled whole.
    func testDraggingARowMovesItRatherThanItsText() throws {
        let app = try opened()
        let before = order(app)

        drag(app, row: 0, onto: 1, half: half)
        let after = order(app)

        XCTAssertEqual(after.count, before.count, "a row was lost or gained by a reorder")
        XCTAssertEqual(after.sorted(), before.sorted(), "a row's text changed during a reorder")
        XCTAssertNotEqual(after, before, "nothing moved at all")
    }
}
