import XCTest

/// What the phone's ⋯ menu holds, and — the half that is easy to lose — what it
/// does not.
///
/// The menu had grown into a second copy of the drawer: **Switch Board…** beside
/// a hamburger that lists every board with its mark and its count, and the whole
/// **Views** list beside a drawer that draws the same views with theirs and the
/// Archive under them. It also carried **Clear Search**, which two controls on
/// the screen itself already do — the field's × and the filtered indicator under
/// the header. What it did *not* carry was Settings, which was reachable only by
/// opening the drawer and scrolling to the foot of it. **Rename Board…** became
/// **Board Settings…** in the same spirit: renaming is one field of a sheet that
/// also holds the board's icon and every one of its columns, and two items for
/// one destination is the duplication this menu was cleared of.
///
/// **A UI test because a menu is only what it renders.** Nothing a store can be
/// asked knows which items a `Menu` built, and an item deleted from one section
/// is one paste away from coming back in another.
///
/// **iPhone only** — the iPad and the desk have their own chrome for all of
/// this, and none of it is this menu.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:LittleKanbanUITests/BoardMenuTests
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
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES", "-LittleKanbanTab", "board"]
        app.launch()

        let menu = app.buttons["Board actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "the phone's board menu never appeared")
        menu.tap()
        // The item that has always been here, waited for rather than assumed:
        // it is what says the menu is open *and* that its items are readable,
        // without which every absence below would pass for the wrong reason.
        XCTAssertTrue(
            app.buttons["Board Settings…"].waitForExistence(timeout: 5),
            "the menu did not open, or its items are not enumerable"
        )
        return app
    }

    /// The app's own settings. It opens the same sheet the drawer's row does —
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

    /// **The first item names the surface that is on screen.** On a saved view
    /// the menu offered *Board Settings…* — the settings of the board standing
    /// behind the view, which is not what the reader is looking at and not what
    /// they would expect the row to change. A view has settings of its own, and
    /// this menu is the phone's only door to them that is not the drawer.
    ///
    /// The editor is raised through `BoardStore.editingViewID` rather than
    /// presented by the menu, for the drawer's reason: a menu is gone by the
    /// time the sheet would open. So this presses it and waits for the sheet,
    /// which is the half a rendered menu cannot show.
    func testOnASavedViewTheFirstItemEditsTheView() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the board menu is the phone's"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES", "-LittleKanbanTab", "board"]
        app.launch()

        // Onto a view, through the drawer — the only way to one on this surface.
        XCTAssertTrue(app.buttons["Show boards"].waitForExistence(timeout: 20), "no board")
        app.buttons["Show boards"].firstMatch.tap()
        let today = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Today")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5), "the drawer has no Today row")
        today.tap()

        let menu = app.buttons["Board actions"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the header lost its menu on a view")
        menu.tap()

        let edit = app.buttons["Edit View…"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5),
                      "the menu offers no way to edit the view that is on screen")
        XCTAssertFalse(app.buttons["Board Settings…"].exists,
                       "the menu still offers the settings of the board behind the view")

        edit.tap()
        // The editor, by the name in its own header — the menu item carries the
        // ellipsis and the sheet does not, so this cannot match the row that
        // opened it.
        XCTAssertTrue(app.staticTexts["Edit View"].waitForExistence(timeout: 10),
                      "Edit View… did not raise the editor")
    }

    /// And what stays, because "removed the clutter" is one edit away from
    /// "removed the menu": these four have no other home on this surface.
    func testTheBoardMenuKeepsWhatIsReachableNowhereElse() throws {
        let app = try openMenu()

        for kept in ["Board Settings…", "Manage Labels"] {
            XCTAssertTrue(app.buttons[kept].exists, "\(kept) has gone from the board menu")
        }
        // "Archive 2 Completed" — the row counts what it will file, so it is
        // matched the way the Trash row below is, not by the exact words the
        // menu-bar item uses.
        let archive = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@",
                                  "Archive ", "Completed"))
            .firstMatch
        XCTAssertTrue(archive.exists, "Archive Completed has gone from the board menu")
        // "Trash", or "Trash (4)" once something is in it — `TrashSurfaceTests`
        // presses it; this only counts it among the survivors.
        let trash = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Trash"))
            .firstMatch
        XCTAssertTrue(trash.exists, "the board menu's way into the Trash has gone")
    }
}
