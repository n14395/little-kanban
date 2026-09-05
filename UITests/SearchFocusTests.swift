import XCTest

/// Reaching search and typing in it.
///
/// **A UI test because the claim is a first responder**, which no store can be
/// asked about — and because the hit areas involved are not the ones they look
/// like: a `TextField`'s own touch area is the height of the text it draws,
/// around 22pt of the 44 the row claims, so the pill around it is not the field
/// and whether a tap on it reaches the field is a question about what is in
/// front of what.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
final class SearchFocusTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func searching() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad's search field lives in its toolbar"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Show boards"].waitForExistence(timeout: 15), "no board")
        XCTAssertFalse(app.keyboards.element.exists, "the keyboard was up before search")
        app.buttons["Search"].firstMatch.tap()
        return app
    }

    /// Search is a tab you go to in order to type in it, so it arrives ready.
    /// It used to arrive as an empty field with no keyboard and no caret, which
    /// cost a second tap — and that tap had to land in the field's own 22pt band
    /// of text rather than anywhere on the pill it is drawn in.
    func testTheSearchTabOpensWithTheKeyboardUp() throws {
        let app = try searching()
        let field = app.textFields["Search all tasks"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field on the Search tab")

        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5),
                      "the Search tab came up without the keyboard")
        field.typeText("caf")
        XCTAssertEqual(field.value as? String, "caf", "the typing did not reach the field")
    }

}
