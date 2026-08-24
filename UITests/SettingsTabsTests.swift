import XCTest

/// Settings on iOS is four subjects reached from a strip, not one scroll past
/// all of them — the shape the macOS window has always had.
///
/// **A UI test because the claim is about what is on screen.** Every section
/// view is the same object it was when they were stacked in a single
/// `ScrollView`; what changed is that three of them are *not built* while the
/// fourth is showing. Nothing a store can be asked knows that. The only way to
/// tell a strip from a scroll is to open the sheet and look for a control that
/// belongs to a subject nobody has chosen.
///
/// **Both idioms.** The sheet is the iPad's settings surface as well as the
/// phone's, and the strip is the same strip — wide enough there to hold all four
/// at once, which is precisely the case where a regression would go unnoticed on
/// a phone.
///
///     xcodebuild test -scheme SimpleKanbanUITests \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:SimpleKanbanUITests/SettingsTabsTests
final class SettingsTabsTests: XCTestCase {
    /// A subject, and one control that its pane has and no other pane does.
    /// Named rather than closured so the list stays a plain value: a `[(String,
    /// (XCUIApplication) -> XCUIElement)]` is neither `Sendable` nor buildable
    /// outside the main actor, and Swift 6 says so.
    private struct Subject {
        let chipID: String
        /// The control's accessibility label. `choice(_:value:)` publishes the
        /// row's title as the menu button's label, and a `Toggle` publishes its
        /// own, so these are the words the user reads.
        let control: String
        /// Whether the control is a switch. Everything else here is a button.
        var isToggle = false
    }

    /// The four, in the order the strip draws them. **General** leads, so it is
    /// the one the sheet opens on and the one the other tests measure against.
    ///
    /// Each marker is picked from a *group* the pane holds alone: Appearance is
    /// General's, Order cards by is the Board's, the reminder switch is
    /// Notifications', and the iCloud switch is Data's. A marker that two panes
    /// could show would pass this suite while the strip did nothing.
    ///
    /// General's was "Theme" until the theme engine took that word for something
    /// bigger: the light/dark override is *Appearance* now and Themes is the row
    /// under it. See **Themes** in the README.
    private let subjects = [
        Subject(chipID: "SettingsTab.general", control: "Appearance"),
        Subject(chipID: "SettingsTab.board", control: "Order cards by"),
        Subject(chipID: "SettingsTab.notifications",
                control: "Remind me on the due date", isToggle: true),
        Subject(chipID: "SettingsTab.data",
                control: "Keep this board on my other devices", isToggle: true),
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    /// Opens the sheet through the launch argument rather than through the
    /// drawer: which door leads here is `EdgeSwipeTests`' business, and tapping
    /// through two surfaces to reach the one under test is two more ways for
    /// this to fail for a reason that is not about tabs.
    private func launchWithSettingsOpen() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SimpleKanbanSkipFirstRun", "YES",
            "-SimpleKanbanOpenSettings", "YES",
        ]
        app.launch()
        return app
    }

    /// Matched on a prefix rather than on the whole label. A `choice` row and a
    /// `Toggle` publish their title and nothing else, but an `action` row is a
    /// button wrapped round a title, a note and a count, and SwiftUI hands
    /// VoiceOver all three run together — "Manage labels, Rename, recolour and
    /// delete the board's labels., 4". The title is the part this suite is
    /// naming, and it is the part that stays put when a note is reworded.
    private func marker(_ subject: Subject, in app: XCUIApplication) -> XCUIElement {
        let query = subject.isToggle ? app.switches : app.buttons
        return query
            .matching(NSPredicate(format: "label BEGINSWITH %@", subject.control))
            .firstMatch
    }

    func testEverySubjectIsReachableFromTheStrip() throws {
        let app = launchWithSettingsOpen()

        let general = app.buttons["SettingsTab.general"]
        XCTAssertTrue(general.waitForExistence(timeout: 15), "the settings sheet never opened")

        // The chip last chosen, which the strip has centred and which is
        // therefore both on screen and *part of the strip* — the thing to drag
        // when the next subject is still past the right-hand edge. Swiping the
        // app instead lands in the pane below, which scrolls the other way and
        // leaves the strip exactly where it was.
        var anchor = general
        var previous: XCUIElement?
        for subject in subjects {
            let chip = app.buttons[subject.chipID]
            XCTAssertTrue(chip.waitForExistence(timeout: 5),
                          "\(subject.chipID) is not in the strip")

            var nudges = 0
            while !chip.isHittable, nudges < 4 {
                anchor.swipeLeft()
                nudges += 1
            }
            XCTAssertTrue(chip.isHittable,
                          "\(subject.chipID) could not be scrolled into the strip")
            chip.tap()

            let control = marker(subject, in: app)
            XCTAssertTrue(control.waitForExistence(timeout: 5),
                          "choosing \(subject.chipID) did not bring its pane on screen")
            XCTAssertTrue(chip.isSelected,
                          "\(subject.chipID) is showing but its chip does not say so")

            // The half that tells a strip from a scroll: the subject before this
            // one has to have *gone*, not merely scrolled off.
            if let previous {
                XCTAssertTrue(previous.waitForNonExistence(timeout: 5),
                              "the previous subject is still on screen beside \(subject.chipID)")
            }
            previous = control
            anchor = chip
        }
    }

    func testTheSheetOpensOnOneSubject() throws {
        let app = launchWithSettingsOpen()

        let general = app.buttons["SettingsTab.general"]
        XCTAssertTrue(general.waitForExistence(timeout: 15), "the settings sheet never opened")
        XCTAssertTrue(general.isSelected, "the sheet did not open on General")

        for subject in subjects.dropFirst() {
            XCTAssertFalse(marker(subject, in: app).exists,
                           "\(subject.chipID) is on screen without having been chosen")
        }
    }

    /// **The Trash is not in here any more.** It was the subject the sheet
    /// opened on; it is the user's own work rather than a preference, and it has
    /// doors of its own now — see `TrashSurfaceTests` for the store's half and
    /// `UITests/TrashSurfaceTests` for the phone's.
    func testTheTrashIsNotOneOfTheSubjects() throws {
        let app = launchWithSettingsOpen()

        XCTAssertTrue(app.buttons["SettingsTab.general"].waitForExistence(timeout: 15),
                      "the settings sheet never opened")
        XCTAssertFalse(app.buttons["SettingsTab.trash"].exists,
                       "the Trash is a settings subject again")
    }
}
