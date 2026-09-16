import XCTest

/// Typing a checklist, one sub-task after another.
///
/// Return **ends editing** — that is what it is for, and `ChecklistView`'s own
/// rows rely on it. The draft that adds sub-tasks is the one field that has to
/// survive it: it moves down under the sub-task it just made, and the next one
/// is meant to be typed straight into it. Losing the keyboard there costs a
/// click a line, which on a checklist of six is five clicks nobody asked for.
///
/// **This is the only surface the claim can be tested on.** Whether a field
/// holds the keyboard is not a value the unit target can read, and on macOS it
/// cannot be driven either: an accessibility-set focus does not set SwiftUI's
/// `@FocusState`, so the field keeps AppKit's first responder and the test
/// passes whether or not the fix is there — measured, and the reason this is a
/// UI test on the simulator instead. `ChecklistView` is shared, so what runs
/// here is the same view the desk draws.
///
/// Fresh install as the fixture, same as `InboxDragTests`:
///
///     xcrun simctl uninstall <device> com.n14395.LittleKanban
final class ChecklistFocusTests: XCTestCase {
    private func launched() throws -> XCUIApplication {
        // The inspector is the surface this drives — "opening it is what a
        // click on a card does" is the iPad's sentence, and the card it taps
        // sits in a board column the phone's cold launch (Today) never shows.
        // Without the skip a phone run failed on "no card on screen" instead
        // of standing aside, the way every guarded sibling does.
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "the checklist this drives is the inspector's, and the inspector is the iPad's"
        )
        let app = XCUIApplication()
        app.launchArguments = ["-LittleKanbanSkipFirstRun", "YES"]
        app.launch()
        return app
    }

    override func setUp() {
        continueAfterFailure = false
    }

    func testTheDraftKeepsTheKeyboardAfterAddingASubTask() throws {
        let app = try launched()

        // Any card will do — the inspector draws the same checklist on all of
        // them. Opening it is what a click on a card does.
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Shared boards with roles"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "no card on screen")
        card.tap()

        let draft = app.textFields["Add new sub-task"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5), "no sub-task draft in the inspector")
        draft.tap()

        // Typed through the *application*, not the element: `element.typeText`
        // taps first, which would put the keyboard back and prove nothing.
        app.typeText("alpha\n")

        let added = app.textFields["Sub-task"].firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5), "the sub-task was not added")

        // The whole claim: the next line goes into the draft without touching
        // it. If the keyboard went, this either types into nothing or throws.
        app.typeText("beta")
        XCTAssertEqual(app.textFields["Add new sub-task"].value as? String, "beta",
                       "the draft lost the keyboard when the sub-task was added")
    }
}
