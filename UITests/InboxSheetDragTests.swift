import XCTest

/// The Inbox comes out of the page when it is dragged downwards — including
/// when the finger is over the cards.
///
/// This is the behaviour a bottom sheet has everywhere else on the system, and
/// the Inbox spent a while not having it. While it was a hand-rolled overlay a
/// pull down over the cards was the list's, always: measured against that build,
/// a 306pt drag from the first card left the panel exactly where it was, while
/// the same drag on the header put it away. Only the header worked, and a panel
/// you can only put away by aiming at its title is one that does not do what its
/// grabber promises.
///
/// It is a real `.sheet` at a detent now, so the rule comes from UIKit rather
/// than from anything here — which is *why* this suite exists rather than why it
/// does not. A detent, a scroll view and a dismissal interact in a way no unit
/// test can see, and the arrangement that produces it is a presentation
/// modifier one edit away from being changed back.
///
/// **The scroll half is not pinned here.** "Dragging over the cards scrolls
/// them" needs a list with somewhere to scroll to, and the seeded Inbox is four
/// cards in a sheet four fifths of the screen tall — it fits, so there is
/// nothing to scroll and nothing to assert. Adding cards to force it would leave
/// them behind for every other suite. What is checked is the half that was
/// broken.
///
/// **iPhone simulator only** — the iPad puts the Inbox in a panel beside the
/// board, where none of this applies.
///
///     xcodebuild test -scheme CardstockUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:CardstockUITests/InboxSheetDragTests
final class InboxSheetDragTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launched() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad draws the Inbox as a panel beside the board, not as a sheet"
        )
        let app = XCUIApplication()
        app.launchArguments = [
            "-CardstockSkipFirstRun", "YES",
            "-CardstockTab", "board",
            "-CardstockShowInbox", "YES",
        ]
        app.launch()
        return app
    }

    /// The sheet's own heading: the one element that is the sheet's and no
    /// other's on this screen. The word "Inbox" is not — the tab bar has a
    /// button called that and a card can carry a chip saying it, and an earlier
    /// version of this suite measured the sheet's header at 92% down the screen
    /// because of exactly that. So it is found by the identifier
    /// `PhoneInboxSheet.titleID` publishes.
    ///
    /// **It was the sheet's ✕**, which is not in the app any more: the grabber
    /// says how the panel goes away and the button was repeating it. Which
    /// makes this suite the one that now carries the whole claim — if the drag
    /// stops working there is no button left to fall back on.
    private func panelTitle(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["InboxPanelTitle"]
    }

    /// Dragged down through the given fraction of the window.
    ///
    /// Far enough to clear UIKit's own threshold, which is a share of the
    /// sheet: at four tenths of an 874pt window this is 350pt, against a sheet
    /// that is 699pt at the four fifths this one is held at — and was 787pt at
    /// the nine tenths it used to be, where the same drag already cleared it. A
    /// 262pt drag measured as *not* enough against the taller sheet, so the
    /// margin here is deliberate rather than generous, and it only grew when
    /// the sheet came down.
    private func dragDown(_ app: XCUIApplication, from y: CGFloat) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: min(0.97, y + 0.4))),
                withVelocity: .default,
                thenHoldForDuration: 0.1
            )
    }

    /// **The case that was broken.** A pull down that begins on a card, with the
    /// list already at its top, belongs to the sheet: there is nothing above to
    /// scroll to, so the only thing the list could do with the pan is rubber-band
    /// against a wall.
    func testAPullDownOverTheCardsTakesTheSheetWithIt() throws {
        let app = try launched()
        let title = panelTitle(app)
        XCTAssertTrue(title.waitForExistence(timeout: 15), "the Inbox sheet never came up")

        // By the words on it rather than as `app.cells.element(boundBy: 0)`,
        // which is what this used to say: the sheet's cards were a `List`'s rows
        // and are ``PhoneCardStack``'s now — a stack has no cells, and the query
        // matched nothing at all. What the test is about is unchanged.
        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Widget on the iOS home screen"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "no cards in the Inbox to drag from")

        dragDown(app, from: card.frame.midY / app.windows.firstMatch.frame.height)

        // Waited for rather than read: the sheet takes a moment to leave, and
        // counting the instant the finger lifts reads "still there" every time.
        XCTAssertTrue(
            title.waitForNonExistence(timeout: 3),
            "a pull down over the cards left the Inbox where it was — the list took the pan and rubber-banded instead of handing it over"
        )
    }

    /// The header, which worked before and has to keep working: it is the part
    /// of a sheet people aim at when the grabber tells them they can.
    func testAPullDownOnTheHeaderTakesTheSheetWithIt() throws {
        let app = try launched()
        let title = panelTitle(app)
        XCTAssertTrue(title.waitForExistence(timeout: 15), "the Inbox sheet never came up")

        dragDown(app, from: title.frame.midY / app.windows.firstMatch.frame.height)

        XCTAssertTrue(
            title.waitForNonExistence(timeout: 3),
            "a pull down on the header left the Inbox where it was"
        )
    }
}
