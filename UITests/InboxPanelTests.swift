import XCTest

/// The Inbox on the phone, now that it is a real `.sheet` held at a detent
/// rather than an overlay of the app's own.
///
/// **What is not in here, and why.** The panel used to carry a hand-rolled drag:
/// an offset, a spring back, a rule for how far is far enough, and a
/// `scrollDisabled` deciding whether a pan belonged to the list or to the panel.
/// All four had tests, and all four are gone with the code — UIKit owns that
/// behaviour now. It cannot be tested from here either: a synthetic
/// `press(forDuration:thenDragTo:)` does not drive a system sheet's pan, which
/// was measured rather than assumed — a recording of the simulator shows the
/// sheet perfectly still through a 500pt drag that dismisses it under a real
/// finger. `DetailSheetHeightTests` reaches the same wall for the editor and
/// pins the height instead, which is what these do.
///
/// **iPhone only** — the iPad's Inbox stands beside the board as a panel.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17e'
final class InboxPanelTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func opened() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanShowInbox", "YES",
        ]
        app.launch()
        return app
    }

    /// The Inbox's own ×. By identifier rather than by label, because the
    /// editor's × is called Close too and both are on screen together once a
    /// card in here has been tapped.
    private func inboxClose(in app: XCUIApplication) -> XCUIElement {
        app.buttons["InboxClose"]
    }

    /// Most of the screen, and not the whole of it — the same claim
    /// `DetailSheetHeightTests` makes about the editor, measured the same way.
    /// A detent is a request to UIKit, not a value the app holds, so where the
    /// sheet's own chrome lands in the window is the only thing that knows how
    /// tall it ended up.
    func testTheInboxRisesToMostOfTheScreenAndStopsShortOfTheTop() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad's Inbox is a panel beside the board, which detents do not size"
        )
        XCUIDevice.shared.orientation = .portrait

        let app = opened()
        let close = inboxClose(in: app)
        XCTAssertTrue(close.waitForExistence(timeout: 20), "no Inbox sheet on screen")

        let window = app.windows.firstMatch.frame
        let top = close.frame.minY
        XCTAssertGreaterThan(
            top, window.height * 0.05,
            "the Inbox is going to the top of the screen — its header is \(top)pt down a \(window.height)pt window, and nothing of the board is left showing"
        )
        XCTAssertLessThan(
            top, window.height * 0.25,
            "the Inbox is not rising far enough — its header is \(top)pt down a \(window.height)pt window, and it was asked for nine tenths"
        )
    }

    /// **A card in the Inbox opens the editor over it.** This is the one thing
    /// the swap to a real sheet genuinely put at risk: a sheet is presented *by*
    /// whatever is on screen, and the root cannot put a second one up while this
    /// one is over it — the tap would do nothing at all. So the Inbox presents
    /// the editor itself, and this is what says so.
    func testACardInTheInboxOpensTheEditorAndComesBackAfterwards() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone only")
        XCUIDevice.shared.orientation = .portrait

        let app = opened()
        XCTAssertTrue(inboxClose(in: app).waitForExistence(timeout: 20), "no Inbox sheet on screen")

        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Cards jump 1px on drop")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "no card in the Inbox")
        card.tap()

        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10),
                      "tapping a card in the Inbox raised no editor — the root cannot present over this sheet, so the Inbox has to")
        XCTAssertEqual(title.value as? String, "Cards jump 1px on drop", "the wrong card opened")

        // The editor's own ×, which is a different button from the Inbox's.
        app.buttons.matching(NSPredicate(format: "label == %@", "Close"))
            .allElementsBoundByIndex
            .first { $0.identifier != "InboxClose" }?
            .tap()

        XCTAssertTrue(inboxClose(in: app).waitForExistence(timeout: 5),
                      "the Inbox went away with the editor it put up")
    }

    /// The route anyone actually takes: the Inbox slot on the tab bar, which is
    /// a toggle rather than a destination. The suite's other cases start with
    /// the sheet already up, so without this nothing would notice if the toggle
    /// stopped raising it.
    func testTheTabBarSlotRaisesTheSheet() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone only")
        XCUIDevice.shared.orientation = .portrait

        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES"]
        app.launch()

        let slot = app.buttons["Inbox"].firstMatch
        XCTAssertTrue(slot.waitForExistence(timeout: 20), "no Inbox slot on the tab bar")
        XCTAssertFalse(inboxClose(in: app).exists, "the Inbox is up before anything was tapped")
        slot.tap()

        XCTAssertTrue(inboxClose(in: app).waitForExistence(timeout: 5),
                      "the tab bar's Inbox slot did not raise the sheet")
    }

    func testTheCloseButtonStillCloses() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone only")
        XCUIDevice.shared.orientation = .portrait

        let app = opened()
        let close = inboxClose(in: app)
        XCTAssertTrue(close.waitForExistence(timeout: 20), "no Inbox sheet on screen")
        close.tap()
        XCTAssertTrue(inboxClose(in: app).waitForNonExistence(timeout: 5),
                      "the × did not close the Inbox")
    }
}
