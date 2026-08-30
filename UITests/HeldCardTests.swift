import XCTest

/// A card that has been picked up and put straight back down is still a card
/// you can open.
///
/// **A UI test because the claim is a hit area.** Nothing in the store knows
/// that a card is unreachable: `sheetID` is set by a tap that never arrived,
/// and every unit test that opens a card by calling the store passes while the
/// card on screen sits under something that is taking its taps. What went wrong
/// is spelled entirely in the view tree, so only a real finger can find it.
///
/// **What it caught.** A card's two insertion halves are clear panes laid over
/// the card — `BoardTaskCard.dropZones` — and they were mounted on
/// `BoardStore.draggingID`, which on a build without `onDragSessionUpdated` is
/// set by the *lift* and cleared by the *drop*. A long press that lifted a card
/// and released it in place had a lift and no drop: the panes went up over
/// every card in the list and stayed there for the whole of
/// `BoardStore.liftExpiry`, twenty seconds in which nothing in that list could
/// be opened. Measured on the simulator, a press-and-hold released in place
/// reports no drop targeting anywhere, so the panes now wait for a destination
/// to say the drag is real — see ``BoardStore/isCardTravelling``.
///
/// **Both idioms, and both lists**, because the two cards are two files: the
/// phone draws `PhoneTaskCard` and the iPad `BoardTaskCard`, and the Inbox is
/// the other surface a card can be dragged in.
///
///     xcrun simctl uninstall <device> com.n14395.SimpleKanban
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:SimpleKanbanUITests/HeldCardTests
final class HeldCardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A card's own element. Every card combines its children into one, so its
    /// label is its title and everything under it.
    private func card(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", title))
            .firstMatch
    }

    /// Whether the card that was tapped is now open: the phone's detail sheet,
    /// the iPad's inspector, matched on the opening of the closer's label the
    /// way `EditorHeaderTests` does — "Close" on the sheet, "Close details" on
    /// the inspector.
    ///
    /// **Minus the Inbox sheet's own ×**, which is also called Close and is on
    /// screen from the moment the panel opens. It carries an identifier for
    /// exactly this reason and this is the query that reads it; without the
    /// exclusion the Inbox case passed before it had done anything.
    private func editorIsUp(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@",
                                  "Close", "InboxClose"))
            .firstMatch
            .waitForExistence(timeout: timeout)
    }

    /// Held long enough to lift the card, and let go without going anywhere —
    /// which is a hand that changed its mind, and a hand that meant to tap.
    private func holdAndLetGo(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.2)
    }

    private func launched(showingInbox: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanTab", "board",
            // The iPad's answer to "the card opened" is its inspector, so it
            // has to start shut — open, its closer is on screen before
            // anything has been tapped and the test proves nothing. The phone
            // has no inspector and ignores this.
            "-SimpleKanbanHideInspector", "YES",
        ] + (showingInbox ? ["-SimpleKanbanShowInbox", "YES"] : [])
        app.launch()
        return app
    }

    func testACardOnTheBoardOpensAfterAHoldThatDroppedNothing() {
        let app = launched(showingInbox: false)

        // Backlog by name, which both idioms draw: a chip on the phone, a
        // column heading on the iPad. The phone opens on In Progress and has to
        // be sent there. `CardDropTargetTests` matches it the same way.
        let backlog = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Backlog"))
            .firstMatch
        XCTAssertTrue(backlog.waitForExistence(timeout: 20), "no board")
        if UIDevice.current.userInterfaceIdiom == .phone { backlog.tap() }

        let held = card("Board templates", in: app)
        XCTAssertTrue(held.waitForExistence(timeout: 10), "no card called Board templates")

        holdAndLetGo(held)
        XCTAssertFalse(editorIsUp(app, timeout: 1),
                       "holding a card opened it — the press is being read as a tap")

        card("Board templates", in: app).tap()
        XCTAssertTrue(editorIsUp(app, timeout: 5),
                      "the card would not open after being held: something is over it taking the tap")
    }

    func testACardInTheInboxOpensAfterAHoldThatDroppedNothing() {
        let app = launched(showingInbox: true)

        let held = card("Widget on the iOS home screen", in: app)
        XCTAssertTrue(held.waitForExistence(timeout: 20), "no Inbox card on screen")

        holdAndLetGo(held)
        XCTAssertFalse(editorIsUp(app, timeout: 1),
                       "holding a card opened it — the press is being read as a tap")

        card("Widget on the iOS home screen", in: app).tap()
        XCTAssertTrue(editorIsUp(app, timeout: 5),
                      "the card would not open after being held: something is over it taking the tap")
    }
}
