// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// Where the tab bar is, and what is left in its slots.
///
/// **A UI test because the claim is a size class and a rotation.** `isShort` is
/// read in a view body and answers to the shape of the screen, so no store can
/// be asked; and what is being checked here is a *frame* — that the bar has left
/// the foot for the header's title row, and that a slot up there is a glyph in a
/// square rather than a glyph and a word. Neither is visible to a unit test.
/// `ColumnStripTests` makes the same argument about the pager.
///
/// **The name is older than the shape.** The bar stood on end up the leading
/// edge for a while, and this suite was written for that rail; landscape now
/// puts it in the header instead, beside the board's name. What is being pinned
/// has not changed — *the bar is not along the foot, and the words are gone* —
/// only where the frames have to land.
///
/// **iPhone simulator only** — the iPad has no tab bar; it has a source list.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17' \
///       -only-testing:LittleKanbanUITests/TabRailTests
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

    /// Turns the device and waits for the *shape* to have changed rather than
    /// for an element to appear: every control here exists in both, so there is
    /// nothing whose arrival would mean the rotation had landed.
    private func turn(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let wants = orientation == .portrait
        let turned = expectation(description: "the screen turned")
        let poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            let isPortrait = app.frame.height > app.frame.width
            if isPortrait == wants {
                timer.invalidate()
                turned.fulfill()
            }
        }
        wait(for: [turned], timeout: 10)
        poll.invalidate()
    }

    func testTheBarIsAWordedFootInPortraitAndGlyphsInTheHeaderInLandscape() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the tab bar is the phone's — the iPad has a source list"
        )
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        // On the board, and said rather than left to the launch: a cold launch
        // lands on Today — see `BoardStore.landingSurface` — and the shape this
        // suite is about is the one the board is drawn in, three columns wide
        // under a header that has given up its chips. `ColumnStripTests` names
        // the tab for the same reason.
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES", "-LittleKanbanTab", "board"]
        app.launch()

        // The quick-capture button is the bar's far end and is the one control
        // on it with a label nothing else shares.
        let capture = app.buttons["New task"]
        XCTAssertTrue(capture.waitForExistence(timeout: 15), "no tab bar")
        // The Search slot, which leads the pill now that the Board slot is
        // gone — it named the surface you were already looking at.
        let search = app.buttons["Search"].firstMatch
        XCTAssertTrue(search.exists, "no Search slot on the tab bar")

        let portrait = app.frame
        XCTAssertGreaterThan(
            capture.frame.minY, portrait.height * 0.75,
            "the quick-capture button is not at the foot of the screen in portrait"
        )
        XCTAssertGreaterThan(
            search.frame.width, search.frame.height,
            "the Search slot's word is not running across the bar in portrait"
        )

        turn(app, to: .landscapeLeft)
        let turned = app.frame

        // **The header's row, which is the top eighth of a screen this shape.**
        // A quarter would pass with the bar still floating over the middle of
        // it; the row itself is 47pt of around 400, so an eighth is generous
        // and still rules out anywhere else it has ever been.
        XCTAssertLessThan(
            capture.frame.maxY, turned.height * 0.2,
            "the quick-capture button is not in the header in landscape"
        )
        XCTAssertLessThan(
            search.frame.maxY, turned.height * 0.2,
            "the Search slot is not in the header in landscape"
        )

        // A word standing on end made the slot about 100pt long; a glyph in its
        // square is 44 by 44. This is what pins "only the icons remain".
        XCTAssertLessThan(
            search.frame.height, 60,
            "the Search slot still carries its word in the header"
        )
        XCTAssertEqual(
            search.frame.height, search.frame.width, accuracy: 12,
            "the Search slot is not a glyph in a square"
        )

        // **Between the title and the ⋯**, which is the whole of where it went:
        // after the drawer button that leads the row, and before the board menu
        // that ends it. Ordering rather than absolute position, because what is
        // between them is a serif title whose width is the board's name.
        let drawer = app.buttons["Show boards"]
        XCTAssertTrue(drawer.exists, "no header in landscape")
        XCTAssertGreaterThan(
            search.frame.minX, drawer.frame.maxX,
            "the tab bar is not after the drawer button in the header row"
        )
        let menu = app.buttons["Board actions"]
        XCTAssertTrue(menu.exists, "no board menu in the header")
        XCTAssertLessThan(
            capture.frame.maxX, menu.frame.minX + 1,
            "the tab bar has run past the ⋯ at the end of the header row"
        )

        // And the board got the leading edge back — the rail used to hold the
        // first 76pt of it, and `safeAreaInset` moved the header along with the
        // rest. The drawer button is the header's first control, so its position
        // is where the whole surface starts.
        XCTAssertLessThan(
            drawer.frame.minX, turned.width * 0.1,
            "something is still inset from the leading edge in landscape"
        )

        // Kept whatever the result, because the point of it is to be looked at
        // — the default lifetime throws it away on a pass, which is exactly the
        // run whose layout somebody wants to see.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "landscape-header"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **The Inbox slot carries its count, in both shapes.**
    ///
    /// A UI test for this suite's own reason: the number is drawn two different
    /// ways — a pill beside the word along the foot, a badge on the glyph in
    /// the header — and which one is on screen answers to the shape of the
    /// screen, which no store can be asked. What is pinned here is the part
    /// that has to be true of both: the control reports the count as its
    /// accessibility *value*, so a reader hears "Inbox, 15" rather than meeting
    /// a button whose name changes every time a card is captured.
    ///
    /// The exact number is the seed board's and is not asserted — what matters
    /// is that it is the Inbox's number and that it survives the rotation.
    func testTheInboxSlotCarriesItsCountInBothShapes() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the tab bar is the phone's — the iPad has a source list"
        )
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES", "-LittleKanbanTab", "board"]
        app.launch()

        let inbox = app.buttons["Inbox"].firstMatch
        XCTAssertTrue(inbox.waitForExistence(timeout: 15), "no Inbox slot on the tab bar")

        let spoken = try XCTUnwrap(inbox.value as? String, "the Inbox slot says nothing about its count")
        let count = try XCTUnwrap(Int(spoken), "the Inbox slot's value is not a number: \(spoken)")
        XCTAssertGreaterThan(count, 0, "the seed board has an Inbox, so there is a count to show")

        // The same number on its side, where it is drawn as a badge instead.
        turn(app, to: .landscapeLeft)
        let turnedInbox = app.buttons["Inbox"].firstMatch
        XCTAssertTrue(turnedInbox.waitForExistence(timeout: 10), "no Inbox slot in the header")
        XCTAssertEqual(
            turnedInbox.value as? String, spoken,
            "the Inbox count did not survive the rotation"
        )
    }
}

