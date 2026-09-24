// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// What the phone's Search tab calls itself, and how you get off it.
///
/// **A UI test because both claims are about what is on screen.** The title is a
/// private computed property inside `PhoneHeader` — the store knows the tab and
/// the surface, and nothing it can be asked knows which word the header drew —
/// and the way back out is a tap on a control whose meaning depends on whether
/// it is lit. `SavedViewTitleTests` makes the same argument about a saved view
/// taking the title, and this is the surface that argument left out: search
/// went on wearing the active board's name over a list drawn from every board
/// and the Inbox alike.
///
/// **iPhone simulator only** — the iPad has no tab bar and searches from its
/// toolbar, where the field is the control and there is no title to take.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:LittleKanbanUITests/SearchTabTests
final class SearchTabTests: XCTestCase {
    /// The header's title, found by identifier rather than by label, for
    /// `SavedViewTitleTests`' reason: the words a title uses are words the
    /// cards under it use too.
    private let titleID = "PhoneHeaderTitle"

    override func setUp() {
        continueAfterFailure = false
    }

    /// On the board, and said rather than left to the launch: a cold launch
    /// lands on Today (`BoardStore.landingSurface`), and a saved view outranks
    /// the tab — so without this the title being compared against is the view's
    /// and the claim is about something else. `TabRailTests` names the tab for
    /// the same reason.
    private func launched() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the tab bar is the phone's — the iPad searches from its toolbar"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES", "-LittleKanbanTab", "board"]
        app.launch()
        XCTAssertTrue(app.buttons["Show boards"].waitForExistence(timeout: 15), "no board")
        return app
    }

    private func title(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", titleID))
            .firstMatch
    }

    /// The board's name is not what a search is: the results come from every
    /// board and the Inbox, so the title was answering "where am I" with
    /// somewhere the list is mostly not from.
    func testTheSearchTabTakesTheTitle() throws {
        let app = try launched()
        let header = title(in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 10), "the header has no title")
        let board = header.label
        XCTAssertNotEqual(board, "Search", "the board is already called Search")

        app.buttons["Search"].firstMatch.tap()
        XCTAssertTrue(app.textFields["Search all tasks"].waitForExistence(timeout: 10),
                      "the Search tab did not open")

        XCTAssertEqual(title(in: app).label, "Search",
                       "the Search tab is still wearing the board's name")
    }

    /// **The slot is a switch, not a destination.** The Board slot is gone from
    /// this bar — it named the surface you were already looking at — so a
    /// search you could only enter was a search you left by opening the drawer
    /// and picking the board you were already on. The field is what has to go
    /// with the title: it is the whole of the surface.
    func testTheSearchSlotPutsTheSearchAwayAgain() throws {
        let app = try launched()
        let header = title(in: app)
        XCTAssertTrue(header.waitForExistence(timeout: 10), "the header has no title")
        let board = header.label

        let slot = app.buttons["Search"].firstMatch
        slot.tap()
        let field = app.textFields["Search all tasks"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the Search tab did not open")
        XCTAssertEqual(title(in: app).label, "Search", "the Search tab did not take the title")

        // The keyboard is up by now — the tab is one you go to in order to type
        // in it, see `SearchFocusTests` — and the bar lifts above it, which is
        // the arrangement that makes a second tap possible at all.
        slot.tap()

        XCTAssertTrue(field.waitForNonExistence(timeout: 5),
                      "the search field survived the tap that closed the search")
        XCTAssertEqual(title(in: app).label, board,
                       "closing the search did not put the board's name back")
    }
}
