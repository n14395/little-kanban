// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// The phone's strip of column chips is drawn in portrait and not when the
/// phone is on its side, where each page carries a heading of its own.
///
/// **A UI test because the claim is a size class.** `verticalSizeClass` is read
/// in a view body and answers to the shape of the screen, so nothing a store
/// can be asked will tell portrait from landscape; the only way to check it is
/// to turn a real device and look. That is also why it turns back at the end —
/// a rule that hides the strip and never brings it back would pass the first
/// half of this on its own.
///
/// **iPhone simulator only** — the iPad has no strip; it has the board.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
final class ColumnStripTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        // The orientation outlives the process, so a test that left the
        // simulator on its side would hand the next one a shape it did not ask
        // for. That is not hypothetical: every other suite here reads portrait.
        XCUIDevice.shared.orientation = .portrait
    }

    func testTheStripIsDrawnInPortraitAndNotInLandscape() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the column strip is the phone's — the iPad draws the board itself"
        )
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = [
            "-LittleKanbanSkipFirstRun", "YES",
            // The board, said out loud. A launch lands on **Today** now — see
            // `BoardStore.landingSurface` — and Today has no columns, so a suite
            // about the column strip has to name the surface the strip is on
            // rather than take it for granted.
            "-LittleKanbanTab", "board",
        ]
        app.launch()

        // A chip, by the label its row combines — the name and its count. The
        // buttons rather than every element with that label: on its side the
        // page headings name the same columns, and they are static text.
        let chip = app.buttons.matching(NSPredicate(format: "label == %@", "Backlog, 4")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15), "no column strip in portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(chip.waitForNonExistence(timeout: 5),
                      "the strip is still drawn with the phone on its side")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(chip.waitForExistence(timeout: 5),
                      "the strip did not come back on the way to portrait")
    }

    /// What the strip is traded for: **three columns at once**, side by side and
    /// in the board's own order.
    ///
    /// A UI test for the first test's reason — the count is
    /// `containerRelativeFrame(count:)` against a size class, so nothing a store
    /// can be asked knows it — and a claim about *three* rather than about
    /// "more than one" because the arithmetic is exact: the pager divides the
    /// width inside the safe area, so three pages fill the screen edge to edge
    /// the way two used to, and a count that did not divide would show a half
    /// column at the trailing edge.
    ///
    /// **Which three is deliberately not asserted.** The pager opens on the
    /// column `mobileColumnID` names and clamps at the end of the board, so on
    /// the seed's four columns the three on screen depend on where the board was
    /// left. That the fourth is *not* on screen is asserted, by the count.
    func testThePhoneOnItsSidePutsThreeColumnsOnScreen() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the pager is the phone's — the iPad draws the whole board"
        )
        XCUIDevice.shared.orientation = .landscapeLeft

        let app = XCUIApplication()
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES", "-LittleKanbanTab", "board"]
        app.launch()

        // The seed board's columns, in board order. A page's heading is the pill
        // over its cards, which combines into one accessibility element reading
        // `name, count` — so the name is matched with the comma after it and the
        // count is taken as read. Anything the pager has built off the side of
        // the screen is filtered out by frame.
        //
        // **Not `app.buttons`**, which is the first test's query and the reason
        // it is spelled differently here: a chip and a heading carry the same
        // words, and the chip is the one you can press. Matching either would
        // make the portrait half below pass on the strip it is supposed to prove
        // is the *only* thing naming a column up there.
        let names = ["Backlog", "Up Next", "In Progress", "Done"]
        func headingsOnScreen() -> [(name: String, frame: CGRect)] {
            names.compactMap { name in
                app.staticTexts
                    .matching(NSPredicate(format: "label BEGINSWITH %@", "\(name),"))
                    .allElementsBoundByIndex
                    .first { app.frame.contains($0.frame) }
                    .map { (name, $0.frame) }
            }
        }

        var found = headingsOnScreen()
        let deadline = Date().addingTimeInterval(20)
        while found.count < 3, Date() < deadline { found = headingsOnScreen() }
        XCTAssertEqual(
            found.count, 3,
            "the phone on its side is showing \(found.count) columns: \(found.map(\.name))"
        )

        // Side by side, in the board's own order, and a page apart: `names` is in
        // board order and `compactMap` keeps it, so comparing that order to the
        // order the headings actually sit in is the whole claim.
        XCTAssertEqual(
            found.map(\.name), found.sorted { $0.frame.minX < $1.frame.minX }.map(\.name),
            "the columns on screen are not in the board's order"
        )
        let edges = found.map(\.frame.minX).sorted()
        XCTAssertEqual(
            edges[1] - edges[0], edges[2] - edges[1], accuracy: 1,
            "the three pages are not the same width"
        )
        XCTAssertGreaterThan(
            edges[2], app.frame.midX,
            "the third column starts before the middle of the screen, so it is not a third of it"
        )

        // And none upright, where a page is the whole screen and the chips the
        // first test reads have already said which column it is.
        XCUIDevice.shared.orientation = .portrait
        var upright = headingsOnScreen()
        let settled = Date().addingTimeInterval(5)
        while !upright.isEmpty, Date() < settled { upright = headingsOnScreen() }
        XCTAssertEqual(
            upright.count, 0,
            "a page is still drawing a heading in portrait: \(upright.map(\.name))"
        )
    }
}
