import XCTest

/// The task detail sheet rises to about four fifths of the screen, not to the
/// top of it.
///
/// **A UI test because a detent is not a value the app holds.**
/// `.presentationDetents([.fraction(0.8)])` is a request to UIKit, and what
/// comes back is a sheet at whatever height the system decided — which is the
/// thing worth checking, since the same modifier is ignored on an iPad's form
/// sheet and quietly clamped when a keyboard is up. Nothing in the store knows
/// how tall the sheet ended up.
///
/// **Measured off the sheet's own top chrome** rather than off a frame for the
/// sheet, which XCUITest does not hand out for a SwiftUI presentation. The
/// Close button sits a fixed distance below the sheet's top edge, so where it
/// lands *in the window* says where the sheet's top is. On an iPhone 17 Pro
/// (402x874) it was measured at y=70 while the sheet was `.large` and y=243.5 at
/// four fifths — 8% of the screen down against 28%. The band below is wide
/// enough to hold every phone this build runs on and far too narrow to admit a
/// full-height sheet.
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

    func testTheDetailSheetStopsShortOfTheTop() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the iPad presents this view as a form sheet, which detents do not size"
        )

        let app = XCUIApplication()
        app.launchArguments = ["-SimpleKanbanSkipFirstRun", "YES", "-SimpleKanbanTab", "board"]
        app.launch()

        // The pager's arrow: on this screen in portrait and on no other tab, so
        // it is the cheapest proof the board is up before tapping into it.
        XCTAssertTrue(app.buttons["Next column"].waitForExistence(timeout: 15),
                      "the board never came up")

        // Tapped by coordinate rather than by card title: this simulator's board
        // is whatever the suites before it left behind, and the middle of the
        // column is a card whatever that is. `RowSwipeTests` names nothing for
        // the same reason.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()

        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "tapping a card raised no detail sheet")

        let window = app.windows.firstMatch.frame
        let top = close.frame.minY

        XCTAssertGreaterThan(
            top, window.height * 0.15,
            "the detail sheet is going to the top of the screen again — its chrome is \(top)pt down a \(window.height)pt window, and a full-height sheet puts it at about 8%"
        )
        XCTAssertLessThan(
            top, window.height * 0.35,
            "the detail sheet is not rising far enough — its chrome is \(top)pt down a \(window.height)pt window"
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
        XCTAssertTrue(app.buttons["Next column"].waitForExistence(timeout: 15),
                      "the board never came up")
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

        XCTAssertEqual(
            title.value as? String, before + "!",
            "the title field did not take the keystroke — a sheet below `.large` resizes when the keyboard arrives, and this is where that goes wrong"
        )
        XCTAssertTrue(app.buttons["Close"].exists,
                      "the sheet went away while the keyboard came up")
    }
}
