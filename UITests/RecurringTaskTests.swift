import XCTest

/// The "Repeat this task" row in the phone editor: ticking it on arms a rule
/// and opens the settings popover, and ticking it off asks before anything is
/// lost — the panel's one confirmation, and the reason this is a UI test: the
/// alert, the popover and the toggle's read-back are all presentation, and
/// only a running app can say they actually come up.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:LittleKanbanUITests/RecurringTaskTests
final class RecurringTaskTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Straight into a seeded card's editor — `PickerFitTests.editor`'s route,
    /// for its reason: no tapping through a board the last run rearranged.
    private func editor() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the phone's sheet is the surface under test"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-LittleKanbanSkipFirstRun", "YES",
            "-LittleKanbanOpenSheet", "NW-118",
        ]
        app.launch()
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 20),
                      "the editor never opened")
        return app
    }

    /// The toggle lives under the checklist, past the first screenful.
    private func repeatToggle(in app: XCUIApplication) -> XCUIElement {
        let toggle = app.switches["Repeat this task"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10),
                      "the editor has no repeat toggle")
        // Three is past the end of this card's scroll, and a swipe at the end
        // of a scroll costs nothing — `PickerFitTests.bringUp`.
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertTrue(toggle.waitForHittable(timeout: 5),
                      "the repeat toggle could not be scrolled into reach")
        return toggle
    }

    private func dismissPopover(in app: XCUIApplication) {
        let region = app.otherElements["PopoverDismissRegion"]
        if region.exists {
            region.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        }
    }

    func testTickingOnOpensTheSettingsAndTickingOffAsksFirst() throws {
        let app = try editor()
        let toggle = repeatToggle(in: app)

        // On: the rule is armed and its settings come straight up.
        toggle.tap()
        let panel = app.popovers.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5),
                      "ticking the toggle on opened no settings")
        let basis = panel.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "On schedule"))
            .firstMatch
        XCTAssertTrue(basis.waitForExistence(timeout: 5),
                      "the settings panel is missing its controls")

        // Put the panel away; the summary line stays under the toggle.
        dismissPopover(in: app)
        let summary = app.buttons["Repeat settings"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5),
                      "no summary row under the armed toggle")

        // Off asks first, and Cancel keeps the rule exactly as it was.
        toggle.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "unticking the toggle asked nothing before clearing the rule")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5),
                      "Cancel took the rule anyway")

        // And the destructive button is what actually clears it.
        toggle.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5),
                      "the warning did not come up a second time")
        alert.buttons["Stop Repeating"].tap()
        XCTAssertTrue(summary.waitForNonexistence(timeout: 5),
                      "confirming left the rule standing")
    }
}

private extension XCUIElement {
    /// `waitForExistence`, for the other half of the question — a control in a
    /// scroll view exists long before it can be pressed. `PickerFitTests`
    /// carries the same.
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let hittable = NSPredicate(format: "hittable == true")
        let waiter = XCTNSPredicateExpectation(predicate: hittable, object: self)
        return XCTWaiter().wait(for: [waiter], timeout: timeout) == .completed
    }

    func waitForNonexistence(timeout: TimeInterval) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        let waiter = XCTNSPredicateExpectation(predicate: gone, object: self)
        return XCTWaiter().wait(for: [waiter], timeout: timeout) == .completed
    }
}
