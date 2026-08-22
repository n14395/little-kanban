import Foundation
import Testing
@testable import Simple_Kanban

/// The twelve preferences added at once, and what each one actually changes.
///
/// `PreferenceTests` guards the *line* — that none of these reached
/// `BoardSnapshot`, where it would be a schema change that travels with an
/// export. This suite is the other half: that each one is read where it is
/// meant to be read, and that the default leaves the app behaving exactly as it
/// did before the setting existed. That second claim is the one worth having.
/// A preference nobody has touched must be invisible, and the cheapest way to
/// ship a bug is to change a default while adding the switch that names it.
@MainActor
@Suite struct PreferenceBehaviourTests {
    /// Reading a *stored* preference is tested against a suite of the test's
    /// own — never `UserDefaults.standard`, which under `xcodebuild test` is
    /// the developer's own settings.
    ///
    /// **Nothing here swaps `Preferences.defaults`.** It did, and it was a real
    /// bug: Swift Testing runs suites in parallel, so a global swapped for the
    /// length of one test is a global every other suite reads mid-swap. It
    /// crashed the host inside `SearchScopingTests`, several suites away. What
    /// the settings actually *change* is set on the store instead — which is
    /// why `trashRetention`, `defaultDueDate` and `weekMeaning` are properties
    /// there rather than reads of a global at each use.
    private func suite(_ pairs: [String: Any]) -> UserDefaults {
        let name = "SimpleKanbanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        for (key, value) in pairs { defaults.set(value, forKey: key) }
        return defaults
    }

    // MARK: Nothing changes until something is set

    /// Every default, written out. The point is not the values — it is that
    /// this test has to be edited for one of them to move, which is the review
    /// a changed default deserves.
    @Test func everyDefaultLeavesTheAppAsItWas() {
        Preferences.reading(suite([:])) {
            #expect(Preferences.newTaskDestination == .board)
            #expect(Preferences.defaultDueDate == .none)
            #expect(Preferences.autoArchive == .never)
            #expect(Preferences.trashRetention.days == TrashedItem.retentionDays)
            #expect(Preferences.backupsKept.count == 10)
            #expect(Preferences.cardDensity == .comfortable)
            #expect(Preferences.weekMeaning == .rollingSevenDays)
            #expect(Preferences.resumesLastPlace == false)
            #expect(Preferences.opensInboxAtLaunch == false)
            // The one that defaults *on*: the menu bar item is this app's only
            // route in from another app.
            #expect(Preferences.showsMenuBarExtra)
        }
    }

    /// A value this build has no case for — which is what a downgrade leaves
    /// behind — reads as the default rather than as nothing.
    @Test func aStoredValueThisBuildDoesNotKnowFallsBack() {
        Preferences.reading(suite([AutoArchive.storageKey: "fortnightly-ish"])) {
            #expect(Preferences.autoArchive == .never)
        }
    }

    /// `bool(forKey:)` cannot tell "off" from "never set", and two of these
    /// default to on, so the reader has to ask whether the key exists at all.
    @Test func aSwitchTurnedOffIsNotTheSameAsOneNeverTouched() {
        Preferences.reading(suite([Preferences.menuBarExtraKey: false])) {
            #expect(Preferences.showsMenuBarExtra == false)
        }
        Preferences.reading(suite([:])) {
            #expect(Preferences.showsMenuBarExtra)
        }
    }

    // MARK: What a week means

    /// The default is the rolling seven days the app has always counted, and
    /// `SavedView.dueThisWeek` still reads exactly as it did.
    @Test func theRollingWeekIsSevenDaysWhicheverDayItIs() {
        let today = CalendarDay(year: 2026, month: 8, day: 22)   // a Saturday
        let week = WeekMeaning.rollingSevenDays
        #expect(week.containsAhead(today, from: today))
        #expect(week.containsAhead(today.adding(days: 6), from: today))
        #expect(week.containsAhead(today.adding(days: 7), from: today) == false)
        #expect(week.containsAhead(today.adding(days: -1), from: today) == false)
    }

    /// A calendar week ends when the week ends. On a Saturday with the week
    /// starting Monday there is one day left, so tomorrow is in and the day
    /// after is not — which is the whole difference from the rolling reading,
    /// where both would be in.
    @Test func aCalendarWeekEndsWhenTheWeekDoes() {
        let saturday = CalendarDay(year: 2026, month: 8, day: 22)
        let week = WeekMeaning.monday
        #expect(week.containsAhead(saturday, from: saturday))
        #expect(week.containsAhead(saturday.adding(days: 1), from: saturday), "Sunday ends the week")
        #expect(week.containsAhead(saturday.adding(days: 2), from: saturday) == false,
                "Monday belongs to the next week")
        // And the rolling reading disagrees, which is why the setting exists.
        #expect(WeekMeaning.rollingSevenDays.containsAhead(saturday.adding(days: 2), from: saturday))
    }

    /// Looking backwards — what the weekly meter counts — is the same week read
    /// the other way, so the two cannot drift apart.
    @Test func theWeekBehindIsTheSameWeek() {
        let saturday = CalendarDay(year: 2026, month: 8, day: 22)
        let week = WeekMeaning.monday
        // Monday to Saturday is five days elapsed.
        #expect(week.containsBehind(saturday.adding(days: -5), from: saturday))
        #expect(week.containsBehind(saturday.adding(days: -6), from: saturday) == false,
                "last Sunday belongs to the week before")
        #expect(WeekMeaning.rollingSevenDays.containsBehind(saturday.adding(days: -6), from: saturday))
    }

    // MARK: What a new task arrives as

    @Test func aNewTaskTakesTheDefaultDueDate() {
        let today = CalendarDay(year: 2026, month: 8, day: 22)
        #expect(DefaultDueDate.none.day(from: today) == nil)
        #expect(DefaultDueDate.today.day(from: today) == today)
        #expect(DefaultDueDate.tomorrow.day(from: today) == today.adding(days: 1))
    }

    @Test func theDefaultIsStillNoDate() {
        let store = TestBoard.store()
        #expect(store.defaultDueDate == .none, "a fresh store dates its cards")
        let id = store.addTask(to: BoardColumn.backlog.id, title: "Undated")
        #expect(store[id]?.due == nil)
    }

    @Test func aDefaultDueDateReachesTheCardsThatAreMade() {
        let store = TestBoard.store()
        store.defaultDueDate = .today
        let id = store.addTask(to: BoardColumn.backlog.id, title: "Dated")
        #expect(store[id]?.due == CalendarDay(.now))
    }

    // MARK: Where a new task goes

    @Test func theInboxSettingOverridesWhatIsOnScreen() {
        let store = TestBoard.store()
        store.selectSurface(.board)
        store.beginAddingWhereVisible(to: .inbox)
        #expect(store.addingPlacement == .inbox)
        #expect(store.isInboxOpen, "the panel that draws the composer is shut")

        let byDefault = TestBoard.store()
        byDefault.selectSurface(.board)
        byDefault.beginAddingWhereVisible(to: .board)
        #expect(byDefault.addingPlacement != .inbox, "the default stopped using the board")
    }

    // MARK: What happens to finished work

    /// The sweep is defined on `updatedAt`, which is when the card last moved —
    /// so a finished card still being edited is not archived out from under the
    /// person editing it.
    @Test func doneCardsAreArchivedOnlyOnceTheyHaveSettled() {
        let store = TestBoard.store()
        let id = store.addTask(to: BoardColumn.done.id, title: "Shipped")
        store.sweepDone(after: .week)
        #expect(store[id]?.isArchived == false, "a card finished today was archived")

        // Eight days later it has settled.
        store.sweepDone(now: Date.now.addingTimeInterval(8 * 86_400), after: .week)
        #expect(store[id]?.isArchived == true, "a card a week old was left in Done")
    }

    @Test func nothingIsArchivedByDefault() {
        let store = TestBoard.store()
        let id = store.addTask(to: BoardColumn.done.id, title: "Shipped")
        store.sweepDone(now: Date.now.addingTimeInterval(400 * 86_400))
        #expect(store[id]?.isArchived == false)
        #expect(Preferences.autoArchive == .never, "the default started archiving")
    }

    /// The sweep is a promise being kept, not something the user did: it must
    /// not land on the undo stack, where a ⌘Z would be undoing the passage of
    /// time. The same rule `sweepTrash` follows.
    @Test func theSweepIsNotUndoable() {
        let (store, undo) = TestBoard.undoing()
        // Through `step`, because this harness groups by hand — see
        // `TestSupport`. The sweep below deliberately does not, which is the
        // claim: it is a promise being kept rather than something the user did,
        // and a ⌘Z that reached it would be undoing the passage of time.
        step(undo) { store.addTask(to: BoardColumn.done.id, title: "Shipped") }
        let before = undo.actionNames
        store.sweepDone(now: Date.now.addingTimeInterval(8 * 86_400), after: .week)
        #expect(undo.actionNames == before,
                "the sweep named an undo step: \(undo.actionNames.dropFirst(before.count))")
    }

    // MARK: How long things are kept

    @Test func theTrashKeepsThingsForAsLongAsTheSettingSays() {
        let item = TrashedItem(trashedAt: .now, contents: .task(TestBoard.tasks[0]))
        let elevenDays = Date.now.addingTimeInterval(11 * 86_400)
        #expect(item.isExpired(at: elevenDays, days: TrashRetention.week.days))
        #expect(item.isExpired(at: elevenDays, days: TrashRetention.month.days) == false)
        #expect(item.isExpired(at: elevenDays, days: TrashRetention.quarter.days) == false)
    }

    @Test func theTrashDefaultIsStillThirtyDays() {
        let item = TrashedItem(trashedAt: .now, contents: .task(TestBoard.tasks[0]))
        #expect(item.daysLeft() == TrashedItem.retentionDays)
        #expect(TrashRetention.fallback.days == TrashedItem.retentionDays)
    }

    // MARK: Where the user was

    /// Which *board* was on screen is board data and always came back. What was
    /// lost at every quit is the view standing in front of it.
    @Test func theViewIsWrittenDownWhicheverWayTheSettingIsSet() {
        let store = TestBoard.store()
        store.selectSurface(.view(.upcoming))
        #expect(store.lastSurfaceName == "upcoming",
                "the view was not written down, so turning the setting on would resume nothing")
    }

    @Test func returningToTheBoardForgetsTheView() {
        let store = TestBoard.store()
        store.selectSurface(.view(.archive))
        store.selectSurface(.board)
        #expect(store.lastSurfaceName == nil)
    }
}
