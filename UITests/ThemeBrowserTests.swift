import XCTest

/// Picking a theme, on the surface where it actually happens.
///
/// **A UI test because the rule is about two slots and one tap.** Pressing a
/// tile calls `store.selectTheme(_:)`, and that method puts the theme in
/// whichever of the light and dark slots its own appearance names — a store test
/// can and does ask it that directly. What a store test cannot ask is whether
/// the *tile a person presses* is wired to the theme whose picture it is drawing,
/// in a lazy grid of twenty-odd of them where every tile is the same shape. Get
/// that wrong by one and every unit test still passes while the picker hands out
/// the wrong theme.
///
/// The second claim is the one the two-slot arrangement lives or dies on:
/// pressing a dark theme must leave the light slot exactly where it was. If it
/// did not, somebody setting their night theme in the afternoon would find the
/// app unreadable at noon the next day — and they would have no way to tell it
/// had happened, because the slot they broke is the one that is not on screen.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:SimpleKanbanUITests/ThemeBrowserTests
final class ThemeBrowserTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Straight to Settings through the launch argument, for
    /// `SettingsTabsTests`' reason: which door leads here belongs to the tests
    /// about doors, and tapping through two surfaces to reach the one under test
    /// is two more ways to fail for a reason that is not about themes.
    private func openBrowser() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanOpenSettings", "YES",
        ]
        app.launch()

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Themes'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the settings sheet never opened")
        row.tap()
        return app
    }

    /// The two summary lines at the top of the browser. They are
    /// `accessibilityElement(children: .combine)`, so each reads as "Light,
    /// Porcelain" — the slot and the theme in it, which is exactly the pair this
    /// suite is about.
    private func slot(_ appearance: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", appearance)).firstMatch
    }

    /// Brings a tile into view. The grid is lazy and twenty-odd tall, so a theme
    /// far down it does not exist until it has been scrolled to — a plain
    /// `waitForExistence` on the last one waits out its timeout and fails
    /// truthfully but uselessly.
    private func reveal(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let tile = app.buttons[name]
        var swipes = 0
        while !tile.exists || !tile.isHittable, swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        return tile
    }

    func testATilePutsItsThemeInItsOwnSlotAndLeavesTheOtherAlone() throws {
        let app = openBrowser()

        let light = slot("Light", in: app)
        let dark = slot("Dark", in: app)
        XCTAssertTrue(light.waitForExistence(timeout: 10), "the browser never opened")
        let lightBefore = light.label
        XCTAssertNotEqual(lightBefore, dark.label, "both slots are showing the same theme")

        // Rainforest is a dark theme well down the grid, which makes it a fair
        // test of the lazy rows as well as of the wiring.
        let rainforest = reveal("Rainforest", in: app)
        XCTAssertTrue(rainforest.isHittable, "Rainforest could not be scrolled to")
        XCTAssertEqual(rainforest.value as? String, "Dark",
                       "Rainforest is not offering itself as a dark theme")
        rainforest.tap()

        XCTAssertTrue(
            slot("Dark", in: app).label.contains("Rainforest"),
            "pressing Rainforest did not put it in the dark slot"
        )
        XCTAssertEqual(
            slot("Light", in: app).label, lightBefore,
            "pressing a dark theme moved the light slot"
        )
    }

    /// The tile is the target, and it is the whole picture rather than the name
    /// under it: a 248×152 button is not something anybody has to aim at, and the
    /// small round menu beside the name is — so that one is checked too, since it
    /// is the control most likely to be crowded off the row by a long theme name.
    func testEveryTileAndItsMenuCanBeHit() throws {
        let app = openBrowser()
        // The summary line rather than a tile: the grid is lazy and one column
        // wide on a phone, so most of the twenty do not exist until they have
        // been scrolled to — waiting on one of those is waiting for the wrong
        // thing and failing for the wrong reason.
        XCTAssertTrue(slot("Light", in: app).waitForExistence(timeout: 10),
                      "the browser never opened")

        for name in ["Oxblood", "Porcelain"] {
            let tile = reveal(name, in: app)
            XCTAssertTrue(tile.isHittable, "\(name)'s tile cannot be tapped")
            XCTAssertGreaterThanOrEqual(tile.frame.height, 44, "\(name)'s tile is under a finger")

            let menu = app.buttons["Actions for \(name)"]
            XCTAssertTrue(menu.exists, "\(name) has no actions menu")
            XCTAssertGreaterThanOrEqual(
                min(menu.frame.width, menu.frame.height), 44,
                "\(name)'s actions menu is under a finger"
            )
        }
    }
}
