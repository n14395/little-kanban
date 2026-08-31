import XCTest

/// The task detail sheet rises to about nine tenths of the screen, not to the
/// top of it.
///
/// **A UI test because a detent is not a value the app holds.**
/// `.presentationDetents([.fraction(0.8)])` is a request to UIKit, and what
/// comes back is a sheet at whatever height the system decided — which is the
/// thing worth checking, since the same modifier is ignored on an iPad's form
/// sheet and quietly clamped when a keyboard is up. Nothing in the store knows
/// how tall the sheet ended up.
///
/// **Measured off the topmost thing in the sheet** rather than off a frame for
/// the sheet, which XCUITest does not hand out for a SwiftUI presentation. That
/// thing sits a fixed distance below the sheet's top edge, so where it lands *in
/// the window* says where the sheet's top is.
///
/// **It was the Close button and is now the title field.** The sheet drew a ✕ in
/// a header row of its own until the grabber above it was found to be saying the
/// same thing — a sheet is put away by pulling it down — so the row went and the
/// title is what stands at the top. The mark did not move when the button did:
/// each was the first child of the sheet's stack under the same padding. It
/// moved when that padding went from 8pt to `PhoneSheetChrome.topClearance`,
/// because with the header row gone there was nothing between the first line and
/// the grabber, which the system draws *over* the top of the sheet.
///
/// **So the band moved by 18pt and was re-derived.** The sheet's own top edge on
/// an iPhone 17 Pro (402x874), read off the chrome rather than off a frame
/// XCUITest will not hand out: about 62pt at `.large`, 155 at nine tenths, 231 at
/// four fifths — the fraction is of the height inside the safe areas, so each
/// sits some 60pt lower than `(1 - fraction) × 874` alone would put it. The mark
/// is 26pt below whichever of those it is, giving 10%, 21% and 29% of the window.
///
/// 15% to 25% holds the middle and clears the other two by about five points
/// each way, which is the room the reading itself needs: the offset is a fixed
/// *point* value, so it is a larger share of a short window than of a tall one,
/// and the band has to hold every iPhone this build runs on. The old band was
/// 12–24% against a mark 8pt down.
///
/// **iPhone simulator only.** The iPad presents the same view as a form sheet,
/// which is centred and sized by the system; detents do not apply to it.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:SimpleKanbanUITests/DetailSheetHeightTests
final class DetailSheetHeightTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// A column chip by name: on this screen and on no other tab, so it is the
    /// cheapest proof the board is up before tapping into it. Matched on the
    /// opening of the label because the chip carries the column's count as well
    /// as its name, the way `CardDropTargetTests` matches the same thing.
    ///
    /// **It was the pager's arrow**, `app.buttons["Next column"]`, and that
    /// button is not in the app any more — the chip strip replaced it. Nothing
    /// said so: the query simply never matched, both cases in here failed with
    /// "the board never came up", and a suite that cannot reach the sheet
    /// cannot say anything about how tall it is.
    private func boardIsUp(_ app: XCUIApplication) -> Bool {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Backlog"))
            .firstMatch
            .waitForExistence(timeout: 15)
    }

    func testTheDetailSheetStopsShortOfTheTop() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad presents this view as a form sheet, which detents do not size"
        )

        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES", "-SimpleKanbanTab", "board"]
        app.launch()

        XCTAssertTrue(boardIsUp(app), "the board never came up")

        // Tapped by coordinate rather than by card title: this simulator's board
        // is whatever the suites before it left behind, and the middle of the
        // column is a card whatever that is. `RowSwipeTests` names nothing for
        // the same reason.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()

        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "tapping a card raised no detail sheet")

        let window = app.windows.firstMatch.frame
        let top = title.frame.minY

        XCTAssertGreaterThan(
            top, window.height * 0.15,
            "the detail sheet is going to the top of the screen again — its title is \(top)pt down a \(window.height)pt window, and a full-height sheet puts it at about 10%"
        )
        XCTAssertLessThan(
            top, window.height * 0.25,
            "the detail sheet is not rising far enough — its title is \(top)pt down a \(window.height)pt window, and the four fifths this was raised from put it at about 29%"
        )
    }

    /// The sheet still takes typing at four fifths.
    ///
    /// **The reason this case exists.** A sheet below `.large` is the one the
    /// system *resizes* when a keyboard comes up — it can be pushed to a taller
    /// detent, or scrolled under the keyboard, or dismissed by the same drag
    /// that would have scrolled it. Going from `.large` to a fraction is exactly
    /// the change that turns a working text field into one that cannot be
    /// reached or cannot keep focus, and none of that shows in a height
    /// measurement. `ChecklistFocusTests` would have covered it, but it looks
    /// for a card by name and this simulator's board no longer has that card, so
    /// it fails before the sheet is ever opened — at `.large` too, checked.
    func testTheDetailSheetStillTakesTypingAtThatHeight() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad presents this view as a form sheet, which detents do not size"
        )

        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES", "-SimpleKanbanTab", "board"]
        app.launch()
        XCTAssertTrue(boardIsUp(app), "the board never came up")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()

        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "no title field in the detail sheet")
        let before = title.value as? String ?? ""

        title.tap()
        // Typed through the *application* rather than the element: typing on the
        // element taps it first, which would put focus back and prove nothing
        // about whether the field kept it while the sheet resized to the
        // keyboard. `ChecklistFocusTests` makes the same distinction.
        app.typeText("!")

        // **Counted rather than appended**, because where the caret sits is not
        // what this case is about: tapping a field puts the caret where the
        // finger landed, and on this one that is the front of the title as
        // readily as the end — measured, `!Task detail inspector`. The question
        // is whether the keystroke arrived at all while the sheet resized under
        // the keyboard.
        let after = title.value as? String ?? ""
        XCTAssertEqual(
            after.count, before.count + 1,
            "the title field did not take the keystroke — a sheet below `.large` resizes when the keyboard arrives, and this is where that goes wrong; the field holds \"\(after)\""
        )
        XCTAssertTrue(after.contains("!"),
                      "the field changed by a character that was not the one typed: \"\(after)\"")
        XCTAssertTrue(title.exists, "the sheet went away while the keyboard came up")
    }
}
