// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// What the search field does on the two pointer platforms: it opens a panel of
/// results from every board, and it leaves the board behind it alone.
///
/// **A UI test because the claim is about two surfaces at once.** That the
/// matcher ranks correctly is `TaskSearchTests`, and that no surface narrows
/// itself any more is `SearchScopingTests` — both of those can be asked of a
/// store. What neither can see is the pair: a query running, a panel of matches
/// over the board, and the board still holding the cards that did *not* match.
/// That was the whole defect — typing took the board away — and it only exists
/// on screen.
///
/// **iPad only.** The phone's Search tab is the same list drawn full-screen and
/// has no panel to open; the desk's half of this was measured through the
/// accessibility API while it was written, which is the only way to drive that
/// platform (see the project's notes on the probe).
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
///       -only-testing:LittleKanbanUITests/SearchResultsTests
final class SearchResultsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launched() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-LittleKanbanSkipFirstRun", "YES",
            // The board, said out loud: a cold launch lands on Today, which has
            // no columns for this to check are still full.
            "-LittleKanbanTab", "board",
            // The panel and the inspector both want the trailing edge of the
            // window, and a result that opens the inspector is easier to read
            // when only one of them was there to begin with.
            "-LittleKanbanHideInspector", "YES",
        ]
        app.launch()
        return app
    }

    /// The field, wherever the bar has put it. A narrow window folds it into a
    /// button — `ToolbarFoldTests` is about that — and this suite is about what
    /// happens once there is a field, on either side of the fold.
    private func searchField(in app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["SearchField"]
        if !field.waitForExistence(timeout: 5) {
            app.buttons["SearchToggle"].tap()
        }
        return field
    }

    private func result(_ title: String, in app: XCUIApplication) -> XCUIElement {
        // A row combines its title, its column chip and its board into one
        // element — so the title alone would also match the *card* on the board,
        // which is exactly the thing this suite has to tell it apart from.
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(title), "))
            .firstMatch
    }

    func testTypingOpensTheResultsAndLeavesTheBoardWhereItWas() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the phone searches in a tab of its own — there is no panel to open"
        )
        let app = launched()

        // A card that does not answer to what is about to be typed. It used to
        // disappear the moment the field had anything in it, which is the whole
        // reason this test exists.
        let untouched = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Board templates"))
            .firstMatch
        XCTAssertTrue(untouched.waitForExistence(timeout: 20), "no board on screen")
        let before = untouched.frame

        let field = searchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field in the bar")
        field.tap()
        field.typeText("sync")

        let hit = result("Sync engine v2", in: app)
        XCTAssertTrue(hit.waitForExistence(timeout: 5), "the results panel never opened")
        // The row says where the card is, which is the half of an answer a
        // filtered board could never give.
        XCTAssertTrue(hit.label.contains("Done"), "a result does not name its column: \(hit.label)")

        // And the board is still the board.
        XCTAssertTrue(untouched.exists, "the query took a card off the board")
        XCTAssertEqual(untouched.frame.minX, before.minX, accuracy: 1,
                       "the board moved under the panel")
    }

    /// What one row says, and in what order: the title, a line of the
    /// description, then **board, column, priority**.
    ///
    /// Read off the row's accessibility label, which is the combined element the
    /// panel builds — so this is the reading order a VoiceOver user gets as well
    /// as the drawing order a sighted one sees. The order is a funnel: which
    /// board, then which column of it, and only then what the card is like.
    func testARowSaysWhatTheCardIsAndThenWhereItLives() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the phone searches in a tab of its own"
        )
        let app = launched()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Board templates"))
                .firstMatch.waitForExistence(timeout: 20),
            "no board on screen"
        )

        let field = searchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field in the bar")
        field.tap()
        field.typeText("sync")

        let hit = result("Sync engine v2", in: app)
        XCTAssertTrue(hit.waitForExistence(timeout: 5), "the results panel never opened")
        let label = hit.label

        // The description, which is what tells two cards with similar titles
        // apart and is the reason the row grew a second line.
        XCTAssertTrue(label.contains("Per-field CRDT"),
                      "the row does not show a line of the description: \(label)")

        func index(_ needle: String) -> Int? {
            label.range(of: needle).map { label.distance(from: label.startIndex, to: $0.lowerBound) }
        }
        let board = try XCTUnwrap(index("Northwind"), "the row does not name its board: \(label)")
        let column = try XCTUnwrap(index("Column: Done"), "the row does not name its column: \(label)")
        let priority = try XCTUnwrap(index("priority"), "the row does not say the priority: \(label)")
        XCTAssertLessThan(board, column, "the column comes before the board: \(label)")
        XCTAssertLessThan(column, priority, "the priority comes before the column: \(label)")

        // And **not** the labels. They were on this line for one build: a card
        // carries any number of them, they are the widest thing the line can
        // hold, and none of them tells one result from another. "API" is this
        // card's, and appears nowhere else in what the row says.
        XCTAssertFalse(label.contains("API"), "the row is still carrying labels: \(label)")
    }

    /// **Clicking away puts the panel down.** It is an overlay the bar draws
    /// rather than a popover, so nothing dismissed it on its own: a reader who
    /// typed, read the list and then went back to the board was left with the
    /// list over the top of it, and the only ways out were Escape, a result and
    /// the ×.
    ///
    /// The other half of the claim is what *survives* the click. The tap ends
    /// the reading of the list rather than the search, so what was typed is
    /// still in the field with its × beside it — which is what tells this apart
    /// from Escape, where the query goes too. A tap that quietly threw away what
    /// had been typed would pass the first assertion here and be the wrong
    /// behaviour.
    ///
    /// The tap is a coordinate rather than an element: the whole point of the
    /// change is that the surface under the panel stops taking clicks while it
    /// is up, so nothing down there is hittable to aim at.
    func testClickingAwayPutsTheResultsDownAndKeepsTheQuery() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the phone searches in a tab of its own"
        )
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launched()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Board templates"))
                .firstMatch.waitForExistence(timeout: 20),
            "no board on screen"
        )

        let field = searchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field in the bar")
        field.tap()
        field.typeText("sync")

        let hit = result("Sync engine v2", in: app)
        XCTAssertTrue(hit.waitForExistence(timeout: 5), "the results panel never opened")

        // A point on the board, and it takes some choosing. Landscape, so that
        // the window is a known 1376×1032: the panel hangs from the field at
        // the *trailing* end of the bar and is 440pt wide, and the keyboard is
        // up — a search has the field — and takes the bottom third. High and to
        // the left is clear of both, and outside the source list, which is a
        // column of the split view rather than something the bar can cover.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35)).tap()

        XCTAssertTrue(hit.waitForNonExistence(timeout: 5),
                      "the panel outlived a tap that landed somewhere else")
        XCTAssertTrue(app.buttons["Clear search"].exists,
                      "the tap took the query with it — that is what Escape is for")
    }

    func testChoosingAResultGoesToTheCardAndEndsTheSearch() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the phone searches in a tab of its own"
        )
        let app = launched()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Board templates"))
                .firstMatch.waitForExistence(timeout: 20),
            "no board on screen"
        )

        let field = searchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "no search field in the bar")
        field.tap()
        field.typeText("sync")

        let hit = result("Sync engine v2", in: app)
        XCTAssertTrue(hit.waitForExistence(timeout: 5), "the results panel never opened")
        hit.tap()

        // The detail panel, opened on the card that was chosen: its title field
        // is the one editable thing in it and carries the title.
        let title = app.textFields.matching(NSPredicate(format: "value == %@", "Sync engine v2")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the chosen card's detail did not open")

        // And the search is over: the panel is down and the field is empty.
        // Read off the × rather than off the field's value — an empty text field
        // reports its *placeholder* as its value, so "Search tasks" is what an
        // empty one says and comparing against "" fails on a field that is
        // already clear.
        XCTAssertTrue(hit.waitForNonExistence(timeout: 5), "the results panel is still up")
        XCTAssertTrue(
            app.buttons["Clear search"].waitForNonExistence(timeout: 5),
            "the query outlived the result it found"
        )
    }
}
