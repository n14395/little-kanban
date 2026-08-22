import XCTest

/// The phone's column strip — the two chevrons and the dots between them — is
/// drawn in portrait and not when the phone is on its side.
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
///     xcodebuild test -scheme SimpleKanbanUITests \
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
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES"]
        app.launch()

        // The chevron rather than a dot: the dots are named for their columns,
        // which are the user's and can be renamed or deleted, and the arrows
        // are the strip itself.
        let back = app.buttons["Previous column"]
        XCTAssertTrue(back.waitForExistence(timeout: 15), "no column strip in portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(back.waitForNonExistence(timeout: 5),
                      "the strip is still drawn with the phone on its side")

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(back.waitForExistence(timeout: 5),
                      "the strip did not come back on the way to portrait")
    }
}
