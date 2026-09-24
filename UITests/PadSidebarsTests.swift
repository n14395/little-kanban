// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// The three panels of an iPad window taking turns when it cannot hold them all.
///
/// The source list, the Inbox panel and the task editor are each a column wide;
/// two open on the left and one on the right, and a window that has not got
/// room for what is open and a board cannot show them together. What it used to
/// do was refuse to choose: the Inbox panel declined to draw — a button that did
/// not appear to work — and the editor drew itself on top of the board.
/// Whichever is opened now keeps its room, and the panel furthest from it is
/// the first to give way.
///
/// **A UI test because both halves are layout.** Whether the window can hold
/// both is a measurement of what the split view left the detail column —
/// `Tests/PadSurfaceTests` owns that arithmetic — and whether the *other* panel
/// actually went is a question about two view hierarchies, one of which is
/// UIKit's.
///
/// **iPad only**, and it has to be a 13" in portrait or narrower with the
/// inspector out: a 13" in landscape holds all four columns at once, which is
/// what the layout was drawn for and the case that must not start closing
/// anything.
///
/// **Run it on the 11".** A 13" in portrait cleared the first version of this
/// arithmetic by 12pt and passed while the shipped behaviour was broken — 834pt
/// is where an inspector's width in the wrong sum leaves the panel declining
/// after the source list has already closed for it, and this fails there with
/// *the Inbox button did nothing*.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
///       -only-testing:LittleKanbanUITests/PadSidebarsTests
final class PadSidebarsTests: XCTestCase {
    /// A row only the source list draws.
    private let listMark = "New board"
    /// The bar's own way in and out of the task editor.
    private let editorToggle = "Toggle details sidebar"
    /// The task editor has two faces — a card's title field when something is
    /// picked, and one sentence of empty state when nothing is — and which one
    /// a launch lands on is not this suite's business. Either is the editor
    /// being out.
    private func editorIsOut(in app: XCUIApplication) -> Bool {
        app.textFields["Title"].exists
            || app.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH %@", "No task selected")).count > 0
    }

    /// `waitForExistence` is per element and this is a question about two, so
    /// it is asked the long way.
    private func waitForEditor(
        _ out: Bool, in app: XCUIApplication, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if editorIsOut(in: app) == out { return }
            usleep(200_000)
        }
        XCTFail(message, file: file, line: line)
    }
    /// The Inbox panel's own heading. The bar's toggle and the list's row are
    /// both *buttons* with that word on them, so a static text reading "Inbox"
    /// is the panel and nothing else.
    private let panelMark = "Inbox"

    override func setUp() {
        continueAfterFailure = false
    }

    /// The board with the source list out beside it, which is where both of
    /// these start. The inspector is left where it launches — out — because it
    /// is the third column that makes a 13" in portrait too narrow for the other
    /// two, and this test is about that window.
    private func boardWithTheListOut() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the split view is the iPad's"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["InboxToggle"].waitForExistence(timeout: 20), "no board")

        // Pressed until the list is out rather than a fixed number of times:
        // `columnVisibility` starts `.automatic` and the split view writes its
        // own answer back into the binding, so which way the first press goes
        // depends on what the system decided at launch.
        let toggle = app.buttons["Toggle sidebar"]
        for _ in 0..<2 where !app.buttons[listMark].exists {
            toggle.tap()
            _ = app.buttons[listMark].waitForExistence(timeout: 3)
        }
        XCTAssertTrue(app.buttons[listMark].exists, "the source list would not come out")
        XCTAssertFalse(app.staticTexts[panelMark].exists, "the Inbox panel was already out")
        return app
    }

    /// Opening the Inbox takes the room from the source list.
    func testOpeningTheInboxClosesTheSourceList() throws {
        let app = try boardWithTheListOut()

        app.buttons["InboxToggle"].tap()

        XCTAssertTrue(app.staticTexts[panelMark].waitForExistence(timeout: 5),
                      "the Inbox button did nothing — the panel is still waiting for room")
        XCTAssertFalse(app.buttons[listMark].exists,
                       "both panels are out at once in a window that has room for one")
    }

    /// And opening the source list takes it back. The same rule from the other
    /// side: whichever was asked for is the one that gets the room.
    func testOpeningTheSourceListClosesTheInbox() throws {
        let app = try boardWithTheListOut()
        app.buttons["InboxToggle"].tap()
        XCTAssertTrue(app.staticTexts[panelMark].waitForExistence(timeout: 5), "the panel never opened")

        app.buttons["Toggle sidebar"].tap()

        XCTAssertTrue(app.buttons[listMark].waitForExistence(timeout: 5),
                      "the source list would not come back")
        XCTAssertTrue(app.staticTexts[panelMark].waitForNonExistence(timeout: 5),
                      "the Inbox panel stayed out beside the list it has no room to share with")
    }

    /// **The panel on the other side is in the same competition.** It used to
    /// sit out: with the editor open and the source list coming out beside a
    /// board that had no room for both, the editor stopped being a column and
    /// drew itself *over* the board instead — which is the last resort, not the
    /// answer to a panel the reader has just asked for.
    ///
    /// This is the case that needs no Inbox at all: an 11" in portrait is 834pt,
    /// and the list and the editor alone are more than it has.
    func testOpeningTheSourceListCollapsesTheTaskEditor() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the split view is the iPad's"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["InboxToggle"].waitForExistence(timeout: 20), "no board")

        // Whatever the launch left, this test starts with the editor out —
        // there is nothing to collapse otherwise, and a test that cannot fail
        // is worse than none.
        if !editorIsOut(in: app) { app.buttons[editorToggle].tap() }
        waitForEditor(true, in: app, "the task editor would not open")

        let toggle = app.buttons["Toggle sidebar"]
        for _ in 0..<2 where !app.buttons[listMark].exists {
            toggle.tap()
            _ = app.buttons[listMark].waitForExistence(timeout: 3)
        }
        XCTAssertTrue(app.buttons[listMark].exists, "the source list would not come out")

        waitForEditor(false, in: app,
                      "the editor stayed out beside a list this window cannot hold with it")
    }

    /// And the same rule from the far side: opening the editor — which is what
    /// tapping a card does — takes the room back from the left.
    ///
    /// The source list has already gone by this point (the Inbox took its room),
    /// so what is left to give is the panel, and it goes rather than the editor
    /// landing on top of the board.
    func testOpeningTheTaskEditorClosesThePanelOnTheLeft() throws {
        let app = try boardWithTheListOut()
        app.buttons["InboxToggle"].tap()
        XCTAssertTrue(app.staticTexts[panelMark].waitForExistence(timeout: 5), "the panel never opened")

        // The bar's own button rather than a card, and for a reason worth
        // writing down: a card's title is board data, and this simulator's board
        // is whatever the suites before this one left it as. What the rule
        // watches is the editor *opening*, which is the same transition either
        // way in.
        XCTAssertFalse(editorIsOut(in: app), "the editor was already out — the list should have taken it")
        app.buttons[editorToggle].tap()

        waitForEditor(true, in: app, "the editor would not open")
        XCTAssertTrue(app.staticTexts[panelMark].waitForNonExistence(timeout: 5),
                      "the Inbox panel stayed out beside an editor there is no room for")
    }
}
