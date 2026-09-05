import XCTest

/// The Inbox on the phone, now that it is a real `.sheet` held at a detent
/// rather than an overlay of the app's own.
///
/// **How thick it is on its side is in here too.** A detent is a request UIKit
/// grants only where the height is regular: in a compact one it ignores the
/// detent and lays the sheet out at the whole screen, which drew the Inbox
/// turned sideways as a full-screen page with cards stretched 874pt across. The
/// panel sizes itself there — see `PhoneInboxSheet.panel` — and the last case
/// here is what says so, because a width after a rotation is exactly the kind of
/// claim nothing else in the repo can hold.
///
/// **The pull is back in here, for the one shape that owns it.** On its side
/// the Inbox is not a sheet at all — a sheet in a compact height covers the
/// screen and takes the board out of the hierarchy under it, so there was
/// nothing behind the panel for a scrim to be a scrim over. It is an overlay of
/// `PhoneRootView`'s there, which means the pull that puts it away is ours
/// again, and unlike a system sheet's pan a `DragGesture` of our own is
/// something a synthetic drag can actually drive.
///
/// **What is not in here, and why.** The panel used to carry a hand-rolled drag:
/// an offset, a spring back, a rule for how far is far enough, and a
/// `scrollDisabled` deciding whether a pan belonged to the list or to the panel.
/// All four had tests, and all four are gone with the code — UIKit owns that
/// behaviour upright. It cannot be tested from here either: a synthetic
/// `press(forDuration:thenDragTo:)` does not drive a system sheet's pan, which
/// was measured rather than assumed — a recording of the simulator shows the
/// sheet perfectly still through a 500pt drag that dismisses it under a real
/// finger. `DetailSheetHeightTests` reaches the same wall for the editor and
/// pins the height instead, which is what these do.
///
/// **iPhone only** — the iPad's Inbox stands beside the board as a panel.
///
///     xcodebuild test -scheme CardstockUITests \
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
            "-CardstockSkipFirstRun", "YES",
            "-CardstockShowInbox", "YES",
        ]
        app.launch()
        return app
    }

    /// The panel's own heading, which is how the panel is found now that it
    /// draws no ✕ — the grabber above it says how it goes away, and the button
    /// was repeating that. By the identifier `PhoneInboxSheet.titleID`
    /// publishes rather than by the word: the tab bar has an Inbox button, the
    /// drawer an Inbox row, and a card can wear an Inbox chip.
    private func inboxTitle(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["InboxPanelTitle"]
    }

    /// Puts a sheet away the way a finger does. `InboxSheetDragTests` measured
    /// the reach — four tenths of the *window*, which clears UIKit's own
    /// threshold at either of the two detents this app asks for — and owns the
    /// claim that it works at all; here it is only the way out of a sheet.
    private func dragDown(_ app: XCUIApplication, from y: CGFloat) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: min(0.97, y + 0.4))
                ),
                withVelocity: .default,
                thenHoldForDuration: 0.1
            )
    }

    /// Turns the device and waits for the *shape* to have changed rather than
    /// for an element to appear: the panel is up in both, so there is nothing
    /// whose arrival would mean the rotation had landed.
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

    /// Most of the screen, and not the whole of it — the same claim
    /// `DetailSheetHeightTests` makes about the editor, measured the same way.
    /// A detent is a request to UIKit, not a value the app holds, so where the
    /// sheet's own chrome lands in the window is the only thing that knows how
    /// tall it ended up.
    ///
    /// **Four fifths, a tenth short of the editor's nine** — see
    /// `PhoneInboxSheet.Metrics.heightFraction` for why the two differ. The
    /// panel's own top edge on an iPhone 17 Pro (402x874) is about 231pt, which
    /// is 26% of the way down: the fraction is of the height inside the safe
    /// areas, so it sits some 60pt lower than `0.2 × 874` alone would put it. At
    /// nine tenths that edge is about 155 and `.large` would be about 62.
    ///
    /// **The mark moved twice and the band still holds.** It was the ✕, which
    /// sat flush with the top of the panel; it is the heading now, which sits
    /// where the ✕ did — nothing 44pt tall is beside it any more, so it fills
    /// the row rather than being centred in it — plus
    /// `PhoneSheetChrome.topClearance`, because with the button gone there was
    /// nothing holding the name off the grabber and it drew through it. So 231
    /// became 257, and 27% of the window became 29%. Nine tenths would read 21%
    /// and `.large` about 10%.
    ///
    /// It has to be a band rather than a number: the clearance is a fixed
    /// *point* offset, so it is a larger share of a short window than of a tall
    /// one, and this one has to hold every iPhone the suite may be pointed at.
    func testTheInboxRisesToMostOfTheScreenAndStopsShortOfTheTop() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad's Inbox is a panel beside the board, which detents do not size"
        )
        XCUIDevice.shared.orientation = .portrait

        let app = opened()
        let heading = inboxTitle(in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 20), "no Inbox sheet on screen")

        let window = app.windows.firstMatch.frame
        let top = heading.frame.minY
        XCTAssertGreaterThan(
            top, window.height * 0.22,
            "the Inbox is rising too far — its header is \(top)pt down a \(window.height)pt window, and the board it was opened over has stopped showing"
        )
        XCTAssertLessThan(
            top, window.height * 0.33,
            "the Inbox is not rising far enough — its header is \(top)pt down a \(window.height)pt window, and it was asked for four fifths"
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
        XCTAssertTrue(inboxTitle(in: app).waitForExistence(timeout: 20), "no Inbox sheet on screen")

        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Cards jump 1px on drop")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "no card in the Inbox")
        card.tap()

        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10),
                      "tapping a card in the Inbox raised no editor — the root cannot present over this sheet, so the Inbox has to")
        XCTAssertEqual(title.value as? String, "Cards jump 1px on drop", "the wrong card opened")

        // The editor goes away by being pulled down — it has no ✕ either, and
        // the two used to be told apart by identifier here because both called
        // themselves Close. It is at nine tenths, so a drag that starts a
        // seventh of the way down the window starts on the editor and not on
        // the Inbox behind it.
        dragDown(app, from: 0.15)
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "the editor would not close")

        XCTAssertTrue(inboxTitle(in: app).waitForExistence(timeout: 5),
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
        app.launchArguments = ["-CardstockSkipFirstRun", "YES"]
        app.launch()

        let slot = app.buttons["Inbox"].firstMatch
        XCTAssertTrue(slot.waitForExistence(timeout: 20), "no Inbox slot on the tab bar")
        XCTAssertFalse(inboxTitle(in: app).exists, "the Inbox is up before anything was tapped")
        slot.tap()

        XCTAssertTrue(inboxTitle(in: app).waitForExistence(timeout: 5),
                      "the tab bar's Inbox slot did not raise the sheet")
    }

    /// **No thicker turned than it is upright.** The panel is capped at the
    /// screen's short edge, which is that phone's own portrait width held
    /// either way up — `PhoneNavDrawer.width(in:screen:)` reaches the same
    /// number the same way and for the same reason.
    func testThePanelIsNoThickerTurnedThanItIsUpright() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad's Inbox is a panel beside the board, which no rotation resizes"
        )
        XCUIDevice.shared.orientation = .portrait

        let app = opened()
        let heading = inboxTitle(in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 20), "no Inbox sheet on screen")

        // The phone's own portrait width, taken from the phone rather than
        // written down: this suite runs on whatever simulator it is pointed at,
        // and the number that must not be exceeded is that device's and no
        // other's.
        let upright = app.frame.width

        // A card is the panel's width less its padding, and is the thing that
        // *looked* wrong: a task card 642pt across is a card in name only. By
        // the words on it, the way every other Inbox suite finds one.
        let card = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", "Widget on the iOS home screen"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "no cards in the Inbox to measure")
        let uprightCard = card.frame.width

        turn(app, to: .landscapeLeft)
        let turned = app.frame
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "the panel did not survive the rotation")

        // **The claim.** Not quite the same number as upright — a sheet at a
        // detent is inset 8pt each side and scaled by `(W - 16) / W`, and one
        // laid out at the whole screen is not, so the same layout width comes
        // out a percent or two wider turned. What is being ruled out is the
        // screen, and no reading of 2% gets near 874.
        XCTAssertLessThan(
            card.frame.width, upright,
            "the Inbox panel is wider on its side than the phone is upright"
        )
        XCTAssertEqual(
            card.frame.width, uprightCard, accuracy: uprightCard * 0.08,
            "the Inbox panel is not the width it is upright"
        )

        // **Inset from both edges**, which is the other half of "it is a panel":
        // a page clipped to 402pt at one edge would pass the measurement above
        // and still be a page. By the two ends of the *card*, which is the
        // widest thing in the panel and so the one that would give a hidden
        // overrun away. It used to read the trailing end off the header's ×,
        // which is not there any more — and the heading that replaced it sits
        // at the leading edge, where a trailing measurement would pass whatever
        // the panel did.
        XCTAssertLessThan(
            card.frame.maxX, turned.width - 150,
            "the Inbox panel still reaches the trailing edge of the screen"
        )
        XCTAssertGreaterThan(
            card.frame.minX, turned.width * 0.2,
            "the Inbox panel still reaches the leading edge of the screen"
        )

        // And it still stops short of the top, which is the portrait case above
        // made again in the shape that lost it: laid out at the whole screen the
        // header sat at y = 0.
        XCTAssertGreaterThan(
            heading.frame.minY, 20,
            "the Inbox panel reaches the top of the screen on its side"
        )

        // Kept whatever the result, because the point of it is to be looked at
        // — the default lifetime throws it away on a pass, which is exactly the
        // run whose layout somebody wants to see.
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "inbox-landscape"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// **On its side the pull is ours, and it works.** The panel is an overlay
    /// there and has no system dismissal of its own: what puts it away is a
    /// drag on the strip at its top, ``PhoneInboxSheet/pull``. A capsule drawn
    /// at the head of a panel that came up from the bottom is a promise, and one
    /// that a hand-rolled panel spent a while not keeping — see the note above
    /// about the build where only the header worked.
    ///
    /// The strip is found by measuring rather than by name: it is hidden from a
    /// reader, having nothing to say to one, so there is no identifier to ask
    /// for. It sits directly above the header, which the heading is in.
    func testThePullOnItsSidePutsThePanelAway() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "iPhone only")
        XCUIDevice.shared.orientation = .portrait

        let app = opened()
        let heading = inboxTitle(in: app)
        XCTAssertTrue(heading.waitForExistence(timeout: 20), "no Inbox sheet on screen")

        turn(app, to: .landscapeLeft)
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "the panel did not survive the rotation")

        let header = heading.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: header.midX, dy: header.minY - 12))
        let end = origin.withOffset(CGVector(dx: header.midX, dy: header.minY + 220))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .default,
                    thenHoldForDuration: 0.1)

        XCTAssertTrue(inboxTitle(in: app).waitForNonExistence(timeout: 5),
                      "a pull down on the panel's own handle did not put it away")
    }
}
