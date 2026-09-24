// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest

/// The panels that hang off a control — the editor's two and the icon picker —
/// and what they do when the screen is short of room for them.
///
/// **A UI test because the claim is a frame.** A popover is handed a height
/// rather than asked for one, and one asked for more than it can have is
/// *clipped* — laid out at its natural length inside a shorter box, so the
/// controls at both ends are drawn outside the panel and report
/// `hittable == false` while still existing. Nothing a store or a metrics
/// preset can be asked knows any of that; only a running app on a real screen
/// does. `BoardSettingsSheetTests` measured the same defect on the colour well.
///
/// What is pinned is the pair that answers it: the panel names **no arrow
/// edge** on iOS, so UIKit hangs it on the side with the room rather than the
/// one side a named edge permits, and it **scrolls what it is not given**, so
/// even a screen with no roomy side loses nothing.
///
/// **iPhone simulator only** — the iPad has room on every side of these
/// controls, and a keyboard that takes a third of the screen rather than half
/// of it, which is the reason all of this was the phone's.
///
///     xcodebuild test -scheme LittleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:LittleKanbanUITests/PickerFitTests
final class PickerFitTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        // The orientation outlives the process — `TabRailTests` has the long
        // version of why that matters to the next suite along.
        XCUIDevice.shared.orientation = .portrait
    }

    /// Straight into a seeded card's editor, rather than tapping through a
    /// board the last run may have rearranged. NW-118 carries a due date and
    /// two labels, so both panels open on their tallest shape: the calendar
    /// with its **Clear due date** row, the label list with ticks in it.
    private func editor(_ orientation: UIDeviceOrientation = .portrait) throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the panels have room on every side of an iPad"
        )
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = [
            "-LittleKanbanSkipFirstRun", "YES",
            "-LittleKanbanOpenSheet", "NW-118",
        ]
        app.launch()
        // The title field: the one element both the phone's sheet and the desk's
        // inspector have and label alike. It was the close control until the
        // phone's sheet stopped drawing one — see `EditorHeaderTests`.
        XCTAssertTrue(app.textFields["Title"].waitForExistence(timeout: 20),
                      "the editor never opened")
        return app
    }

    /// Scrolls the editor to its foot, which is where the defect lives: a panel
    /// that may hang only *above* its control has less and less to hang in as
    /// the control rises, and is clamped into what little there is while the
    /// whole lower screen sits empty.
    ///
    /// The seeded card opens with its Due row 520pt down an 874pt screen, where
    /// above is the roomier side and a named edge and a free one agree — so the
    /// bug does not show at all until the editor is scrolled, which is what a
    /// reader does on the way to either control. Scrolled to the end it stands
    /// at about 346, with 246pt above it and 453 below, and the two answers part
    /// company: the panel is 469.
    private func bringUp(_ control: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(control.waitForExistence(timeout: 10), "the editor has no such control")
        let opened = control.frame.midY
        // Three is past the end of this card's scroll — 932pt of content in a
        // 705pt viewport — and a swipe at the end of a scroll costs nothing.
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertLessThan(control.frame.midY, opened,
                          "the editor would not scroll the control up the screen")
    }

    /// Board Settings, which is where the icon well can be reached from a launch
    /// argument rather than by opening a sheet inside a sheet. The well there is
    /// the same control the saved-view editor draws — see ``SymbolWell`` — and
    /// the picker behind it is one view.
    private func boardSettings() throws -> XCUIApplication {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "the panels have room on every side of an iPad"
        )
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "-LittleKanbanSkipFirstRun", "YES",
            "-LittleKanbanOpenBoardSettings", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["Select Icon"].waitForExistence(timeout: 20),
                      "board settings never opened")
        return app
    }

    /// The panel itself, which iOS publishes as a popover of its own.
    private func panel(in app: XCUIApplication) -> XCUIElement {
        let panel = app.popovers.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "no panel came up")
        return panel
    }

    /// Every named control is on the screen and can be pressed. The ends are
    /// what matter — a clipped panel keeps its middle and loses its first and
    /// last rows — so each caller passes both.
    ///
    /// `isHittable` rather than "inside the panel's frame": a panel that has to
    /// scroll the last few points of itself is doing the right thing, and what
    /// is being pinned is that nothing is *unreachable*. Clipped content fails
    /// both halves anyway — it is drawn outside the box, so it is off the screen
    /// or behind the panel's own clip, and either way it cannot be pressed.
    private func assertWhole(
        _ named: [String], of panel: XCUIElement, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(app.frame.contains(panel.frame),
                      "the panel is off the screen at \(panel.frame) in \(app.frame)",
                      file: file, line: line)
        for name in named {
            // Inside the panel rather than anywhere on screen: "Today" is a
            // preset here and the header's own title behind it — the phone
            // lands on that saved view — and a query across the app picks
            // whichever it reaches first.
            let control = panel.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", name))
                .firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5),
                          "\(name) is not in the panel", file: file, line: line)
            XCTAssertTrue(app.frame.contains(control.frame),
                          "\(name) is drawn off the screen at \(control.frame), panel \(panel.frame)",
                          file: file, line: line)
            // A moment for a panel that is still animating into place — a
            // clipped control never becomes pressable, so the wait costs the
            // claim nothing.
            XCTAssertTrue(control.waitForHittable(timeout: 3),
                          "\(name) cannot be pressed at \(control.frame)", file: file, line: line)
        }
    }

    /// **The calendar.** The Due card sits about 520pt down an 874pt screen, so
    /// a panel pinned above it — which is the only placement a named `.bottom`
    /// edge permits — was clamped into what was left, with the presets and the
    /// month's own name cut off the top and the last weeks off the bottom.
    ///
    /// The panel is 469pt for a card that has a date to clear, so it does not
    /// fit above a Due row near the top of the screen and does fit below it.
    /// Everything named here is pressable where it stands; where the panel is
    /// a few points short of its natural height it gives them to the scroll
    /// rather than drawing a row outside the box.
    func testTheCalendarOpensWhole() throws {
        let app = try editor()
        let due = app.buttons["Due date"]
        bringUp(due, in: app)
        due.tap()
        let calendar = panel(in: app)
        assertWhole(
            // The first row of the panel, the row under it, and the last.
            ["Today", "Next week", "Previous month", "Next month", "Clear due date"],
            of: calendar, in: app
        )
    }

    /// **The label picker**, whose `+` sits lower still. What went missing
    /// there was the search field and **New Label** off the top — the two
    /// things the panel is opened *to use* — and the last labels off the foot.
    ///
    /// With the five seeded labels the panel is about 339pt and fits above the
    /// `+` whichever way it is placed, so what this pins is the requirement —
    /// the whole of the panel on screen and pressable — rather than the
    /// placement. `testTheCalendarOpensWhole` is where the placement itself is
    /// discriminated, its panel being 469. A real vocabulary reaches the list's
    /// 320pt cap and the panel with it, which is the case the screenshots came
    /// from.
    func testTheLabelPickerOpensWhole() throws {
        let app = try editor()
        let add = app.buttons["Add label"]
        bringUp(add, in: app)
        add.tap()
        let picker = panel(in: app)
        // "Polish" is the last seeded label and is not one of NW-118's own, so
        // the only one of these on screen is the row in the panel.
        assertWhole(["Search labels", "New Label", "Polish"], of: picker, in: app)
    }

    /// **And where no side is roomy enough.** A phone lying down has 402pt of
    /// height and the calendar is taller than that, so neither above nor below
    /// can hold it whole — placement has run out of answers and the panel has
    /// to give the height back itself. It scrolls: the top is on screen to
    /// begin with and the foot is one swipe away, where before both ends were
    /// drawn outside the box and neither could be reached at all.
    func testAPanelTallerThanTheScreenScrollsRatherThanBeingCut() throws {
        let app = try editor(.landscapeLeft)
        app.buttons["Due date"].tap()
        let calendar = panel(in: app)
        XCTAssertTrue(app.frame.contains(calendar.frame),
                      "the panel is off the screen at \(calendar.frame) in \(app.frame)")

        let presets = app.buttons["Today"].firstMatch
        XCTAssertTrue(presets.waitForExistence(timeout: 5), "no presets on the panel")
        XCTAssertTrue(presets.isHittable, "the top of the panel is not on screen")

        let clear = app.buttons["Clear due date"].firstMatch
        XCTAssertTrue(clear.exists, "the panel has no Clear row to reach")
        calendar.swipeUp()
        XCTAssertTrue(clear.waitForHittable(timeout: 5),
                      "the foot of the panel could not be scrolled to at \(clear.frame)")
    }

    /// The label picker on the same short screen, which cannot scroll what it
    /// is not given — its list stands its ground so the panel can come back
    /// from the compose form, `LabelPickerList.standsItsGround`. Where the
    /// screen has no room for the panel at all, the floor is what has to give:
    /// the panel takes the height it is handed and the rows scroll inside it.
    func testTheLabelPickerFitsAShortScreenToo() throws {
        let app = try editor(.landscapeLeft)
        let add = app.buttons["Add label"]
        bringUp(add, in: app)
        add.tap()
        let picker = panel(in: app)
        XCTAssertTrue(app.frame.contains(picker.frame),
                      "the panel is off the screen at \(picker.frame) in \(app.frame)")
        // The two things the panel is opened to use, which are what a clipped
        // one loses first: they are at the top of it, and the top is what a
        // panel pinned into too little room has drawn above the screen.
        for name in ["Search labels", "New Label"] {
            let control = picker.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", name))
                .firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), "\(name) is not in the panel")
            XCTAssertTrue(control.waitForHittable(timeout: 3),
                          "\(name) cannot be pressed at \(control.frame)")
        }
    }

    /// **The icon picker keeps its search field when the keyboard arrives.**
    ///
    /// Tapping the field raises the keyboard, UIKit shortens the popover to
    /// stand clear of it — and SwiftUI lifted the panel's contents by the same
    /// overlap a second time, on a frame that had already moved. What went up
    /// out of the top of the panel was the search field itself: the reader was
    /// left typing into a field they could no longer see. The grid is the one
    /// row here that can yield, and now does — measured, 300pt to 96 — while
    /// the field and the group menu do not move at all.
    func testTheIconPickersFieldStaysPutWhenTheKeyboardRises() throws {
        let app = try boardSettings()
        app.buttons["Select Icon"].tap()
        let picker = panel(in: app)

        let field = app.textFields["Search icons"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the picker has no search field")
        let before = field.frame

        field.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5),
                      "the field took no keyboard")

        XCTAssertEqual(field.frame, before, "the field moved when the keyboard came up")
        XCTAssertTrue(picker.frame.contains(field.frame),
                      "the field is outside the panel at \(field.frame), panel \(picker.frame)")
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.element.frame.minY,
                                 "the field is under the keyboard that is writing into it")
        XCTAssertTrue(field.waitForHittable(timeout: 3), "the field cannot be pressed")

        // And the group menu under it, which is the other fixed row: the grid
        // is what gives the height up.
        let group = app.buttons["Icon group"].firstMatch
        XCTAssertTrue(group.exists, "the picker has no group menu")
        XCTAssertTrue(picker.frame.contains(group.frame),
                      "the group menu is outside the panel at \(group.frame)")

        // The whole point of the field, end to end: what is typed lands in one
        // the reader can still see.
        app.typeText("plane")
        XCTAssertEqual(field.value as? String, "plane", "the typing did not reach the field")
        XCTAssertTrue(picker.frame.contains(field.frame),
                      "the field left the panel as it was typed into")
    }
}

private extension XCUIElement {
    /// `waitForExistence`, for the other half of the question: a control inside
    /// a scroll view exists long before it can be pressed.
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let hittable = NSPredicate(format: "hittable == true")
        let waiter = XCTNSPredicateExpectation(predicate: hittable, object: self)
        return XCTWaiter().wait(for: [waiter], timeout: timeout) == .completed
    }
}
