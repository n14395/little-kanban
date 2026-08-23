import XCTest

/// What the phone's ⋯ menu holds, and — the half that is easy to lose — what it
/// does not.
///
/// The menu had grown into a second copy of the drawer: **Switch Board…** beside
/// a hamburger that lists every board with its dot and its count, and the whole
/// **Views** list beside a drawer that draws the same views with theirs and the
/// Archive under them. It also carried **Clear Search**, which two controls on
/// the screen itself already do — the field's × and the filtered indicator under
/// the header. What it did *not* carry was Settings, which was reachable only by
/// opening the drawer and scrolling to the foot of it.
///
/// **A UI test because a menu is only what it renders.** Nothing a store can be
/// asked knows which items a `Menu` built, and an item deleted from one section
/// is one paste away from coming back in another.
///
/// **iPhone only** — the iPad and the desk have their own chrome for all of
/// this, and none of it is this menu.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:SimpleKanbanUITests/BoardMenuTests
final class BoardMenuTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The menu, open. Everything below reads the items under it, so a failure
    /// to open is reported here rather than as an item that is missing.
    private func openMenu() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the board menu is the phone's"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES", "-SimpleKanbanTab", "board"]
        app.launch()

        let menu = app.buttons["Board actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "the phone's board menu never appeared")
        menu.tap()
        // The item that has always been here, waited for rather than assumed:
        // it is what says the menu is open *and* that its items are readable,
        // without which every absence below would pass for the wrong reason.
        XCTAssertTrue(
            app.buttons["Rename Board…"].waitForExistence(timeout: 5),
            "the menu did not open, or its items are not enumerable"
        )
        return app
    }

    /// The one that was added. It opens the same sheet the drawer's row does —
    /// `SettingsTabsTests` is what that sheet *is*; this is only the door.
    func testTheBoardMenuOpensSettings() throws {
        let app = try openMenu()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "the board menu has no way into Settings")
        settings.tap()

        XCTAssertTrue(
            app.buttons["SettingsTab.general"].waitForExistence(timeout: 5),
            "pressing Settings did not raise the settings sheet"
        )
    }

    /// The three that were taken out, by the exact words they had. Exact rather
    /// than `CONTAINS`: a card behind the menu can carry a due chip that says
    /// "Today", and a test that matched loosely would fail on a card instead of
    /// on the menu.
    func testTheBoardMenuDoesNotRepeatTheDrawerOrTheSearchField() throws {
        let app = try openMenu()

        for gone in ["Switch Board…", "Clear Search", "Today", "Upcoming", "High priority",
                     "Due this week", "Recently updated", "Archive"] {
            let item = app.buttons.matching(NSPredicate(format: "label == %@", gone)).firstMatch
            XCTAssertFalse(item.exists, "\(gone) is back in the board menu — the drawer draws it")
        }
    }

    /// And what stays, because "removed the clutter" is one edit away from
    /// "removed the menu": these four have no other home on this surface.
    func testTheBoardMenuKeepsWhatIsReachableNowhereElse() throws {
        let app = try openMenu()

        for kept in ["Rename Board…", "Archive Completed", "Manage Labels"] {
            XCTAssertTrue(app.buttons[kept].exists, "\(kept) has gone from the board menu")
        }
        // "Trash", or "Trash (4)" once something is in it — `TrashSurfaceTests`
        // presses it; this only counts it among the survivors.
        let trash = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Trash"))
            .firstMatch
        XCTAssertTrue(trash.exists, "the board menu's way into the Trash has gone")
    }
}
