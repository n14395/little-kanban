import XCTest

/// What the task editor's header row holds.
///
/// **It used to lead with the task code** — `NW-118`, `IN-157` — at the leading
/// edge of the desk's inspector and the phone's sheet alike. That line was the
/// one thing on the panel nothing could be done with: a code cannot be edited,
/// it names nothing the user chose, and every route that needs one carries it
/// already — the `littlekanban://` link, the reminder, the export, Spotlight,
/// the plain-text half of a drag. It cost the first line above the title on the
/// surface where the title is the point, so it is gone. See **Codes**.
///
/// **A UI test because the claim is about what is drawn.** The code is still on
/// the model, still minted, still what the search field matches and what the
/// Trash row prints to tell two cards of the same name apart — so nothing a
/// store can be asked has changed, and only the panel itself can say whether it
/// draws one.
///
/// **Both idioms**, because the line was in both panels and was taken out of
/// both:
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:LittleKanbanUITests/EditorHeaderTests
final class EditorHeaderTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTheEditorDrawsNoTaskCode() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // Straight into the editor for a seeded card, rather than tapping
        // through a board whose contents the last run may have rearranged.
        app.launchArguments = [
            "-LittleKanbanSkipFirstRun", "YES",
            "-LittleKanbanOpenSheet", "NW-118",
        ]
        app.launch()

        // The title field, which both panels label the same way. It was the
        // close control — "Close" on the phone's sheet, "Close details" on the
        // desk's inspector — and the phone's sheet has none now: it is put away
        // by pulling it down, the way the grabber above it says.
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 20),
                      "the editor never opened")

        // The card's own code, and one from the Inbox for good measure: an
        // exact match, because a note or a checklist row is entitled to mention
        // a code in passing and this is a claim about the header's label.
        for code in ["NW-118", "IN-157"] {
            let label = app.staticTexts
                .matching(NSPredicate(format: "label == %@", code))
                .firstMatch
            XCTAssertFalse(label.exists, "\(code) is still drawn in the editor")
        }
    }
}
