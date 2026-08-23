import XCTest

/// The phone's column chips carry everything that can be done to a column.
///
/// **The gap this closes.** Columns became board data long before the phone had
/// any way to touch them: every call site for the store's column mutations was
/// on the desk, and a column here could only be renamed, recoloured, reordered
/// or thrown away by opening the drawer, long-pressing the board row, and
/// finding the column in the sheet that came up. Three surfaces deep, for the
/// four things a column *is*.
///
/// The chip is the one control the phone draws a column as, so it is where the
/// menu belongs. Its tap is taken — it is the switcher, and pages to that
/// column — which is exactly the case iOS gives a context menu for, and is what
/// the desk's column header offers behind its ⋯ button.
///
/// **A UI test because a context menu has nothing to enumerate at runtime.** It
/// is a `@ViewBuilder` handed to `.contextMenu`; no store knows what is in it,
/// and the one thing worth asserting — that a long press on a chip produces
/// these items and that **Edit Column…** lands on *that* column's editor — can
/// only be pressed.
///
/// **It changes nothing.** The menu is opened and the editor is read, not
/// written: the board file outlives the process, and a suite that renames or
/// moves a column hands the next one a board it did not ask for.
///
/// **iPhone simulator only** — the chips are the phone's portrait switcher. The
/// iPad draws the board itself, with the desk's header menu on every column.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17' \
///       -only-testing:SimpleKanbanUITests/ColumnChipMenuTests
final class ColumnChipMenuTests: XCTestCase {
    /// The second seeded column, not the first: "opened the right column" is
    /// not a claim a first-column fixture can fail.
    private let column = "Up Next"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launched() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the column chips are the phone's portrait switcher"
        )
        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanTab", "board",
            "-SimpleKanbanShowInbox", "NO",
        ]
        app.launch()
        return app
    }

    /// The chip, by the label its row combines — the column's name and its
    /// count, so matched on the name it starts with.
    private func chip(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    private func item(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    /// **A second and a half, and it is not padding.** A press of 1.0 does not
    /// raise the menu at all in the simulator — measured, and it fails on the
    /// first item every time, which reads exactly like a menu that was never
    /// built. UIKit's own recogniser fires well before that; what needs the
    /// extra is the chip's home in a horizontal `ScrollView`, where a shorter
    /// hold is claimed by the scroller as the start of a swipe.
    private func longPress(_ element: XCUIElement) {
        element.press(forDuration: 1.5)
    }

    func testALongPressOnAChipOffersEverythingAColumnCanBe() throws {
        let app = try launched()

        let target = chip(column, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 15), "no \(column) chip in the strip")
        longPress(target)

        // The four the desk's column header offers, minus the archive — that one
        // is drawn only on a Done column with something in it, and this is not
        // one. `BoardColumnView` draws the same list under the same rules.
        for name in ["Edit Column", "Move Left", "Move Right", "Trash Column"] {
            XCTAssertTrue(
                item(name, in: app).waitForExistence(timeout: 5),
                "the chip's menu has no \(name)"
            )
        }

        // Left is disabled on the first column and right on the last, so the
        // middle chip has both live — which is the half that says the items are
        // wired to *this* chip's place in the strip rather than to nothing.
        XCTAssertTrue(item("Move Left", in: app).isEnabled, "Move Left is dead on a middle column")
        XCTAssertTrue(item("Move Right", in: app).isEnabled, "Move Right is dead on a middle column")
    }

    func testEditColumnOpensTheEditorOnThatColumn() throws {
        let app = try launched()

        let target = chip(column, in: app)
        XCTAssertTrue(target.waitForExistence(timeout: 15), "no \(column) chip in the strip")
        longPress(target)

        let edit = item("Edit Column", in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the chip's menu has no Edit Column…")
        edit.tap()

        // **The claim.** The board editor's column row is *unfolded* — its Name
        // field only exists while one is — and it is unfolded on the column the
        // chip named. A sheet that opened on the board and left every column
        // closed has no such field at all, which is the failure this separates
        // from "opened the wrong one".
        let name = app.textFields["Column name"]
        XCTAssertTrue(
            name.waitForExistence(timeout: 10),
            "Edit Column… opened the board editor with every column still folded up"
        )
        XCTAssertEqual(name.value as? String, column, "the editor opened on the wrong column")

        // And the abbreviation beside it, which is the field's own sibling and
        // the one thing nothing else on this platform can edit.
        XCTAssertTrue(app.textFields["Short name"].exists, "the column editor is missing its Short field")

        // **The sheet is left standing**, and deliberately. Closing it is not
        // part of the claim, and neither way of doing it is sound here: the
        // header's Done is not the only button called that — the board's columns
        // are listed under it and one of them is *named* Done, whose row
        // publishes itself under its own name, so a tap by label is ambiguous
        // and says so — while a swipe down over a `.large` sheet full of
        // scrolling content scrolls the content. The app is torn down with the
        // test, and nothing in here was written, so there is nothing to undo.
    }
}
