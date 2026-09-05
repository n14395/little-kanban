import XCTest

/// The Trash has a door of its own, and it is not in Settings.
///
/// **A UI test because that is where the claim lives.** `Tests/TrashSurfaceTests`
/// reads the source for whether each surface raises `isShowingTrash`, which
/// catches a platform losing its only way in; what it cannot see is whether the
/// thing that comes up when a user actually presses the door is the Trash. That
/// needs a run.
///
/// **iPhone only.** The phone's door is the board menu at the top right — the
/// one surface where the way in is a *press* rather than a bin in a source list
/// that this simulator does not draw. The pointer surfaces' bin is
/// `Tests/TrashSurfaceTests`' and the eye's.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:LittleKanbanUITests/TrashSurfaceTests
final class TrashSurfaceTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The board menu carries it, and pressing it brings the Trash up.
    ///
    /// Nothing is thrown away first: what the list holds depends on what the
    /// user has deleted, and a fixture that has to be empty is one the suite
    /// running before this can break. So what is checked is the sheet itself —
    /// its heading, and the Done that closes it — which is there whether the
    /// list under it has thirty rows or the empty state.
    func testTheBoardMenuOpensTheTrash() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the board menu is the phone's door to the Trash"
        )

        let app = XCUIApplication()
        app.launchArguments = [
            "-LittleKanbanSkipFirstRun", "YES",
            "-LittleKanbanTab", "board",
        ]
        app.launch()

        let menu = app.buttons["Board actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "the phone's board menu never appeared")
        menu.tap()

        // "Trash", or "Trash (4)" once something is in it — so matched on the
        // word rather than on the whole label.
        let item = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Trash"))
            .firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the board menu has no way into the Trash")
        item.tap()

        XCTAssertTrue(app.staticTexts["Trash"].waitForExistence(timeout: 5),
                      "pressing Trash did not raise the Trash")
        XCTAssertTrue(app.buttons["Done"].exists, "the Trash sheet has no way out")
    }

    /// And the launch argument the harness uses, which is the same flag the menu
    /// sets — so a door that stopped raising the sheet and a sheet that stopped
    /// being presented are two different failures rather than one.
    func testTheTrashCanBeRaisedStraightFromLaunch() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the Trash is a sheet on the phone and a popover elsewhere"
        )

        let app = XCUIApplication()
        app.launchArguments = [
            "-LittleKanbanSkipFirstRun", "YES",
            "-LittleKanbanOpenTrash", "YES",
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Trash"].waitForExistence(timeout: 15),
                      "the Trash sheet never opened")
    }
}
