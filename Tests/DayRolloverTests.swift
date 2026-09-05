import Foundation
import Testing
@testable import LittleKanban

/// Midnight, under a running app.
///
/// Every count and predicate that depends on "today" takes a `CalendarDay`
/// rather than reading the clock, and `DayClock` is what supplies it. That is
/// only worth anything if the answers actually move when the day does, so this
/// suite builds the clock from an instant either side of a boundary and asks
/// the store the same questions twice.
@MainActor
@Suite struct DayRolloverTests {
    /// Pinned to UTC so that "one second to midnight" is one second to midnight
    /// wherever this runs, rather than in whichever zone the machine is in.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }()

    /// A zone that actually observes DST, for the wake arithmetic below. UTC
    /// never has a short or a long day, so it cannot show the bug.
    private static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? calendar.timeZone
        return calendar
    }()

    private func instant(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int,
        in calendar: Calendar? = nil
    ) -> Date {
        var components = DateComponents()
        (components.year, components.month, components.day) = (year, month, day)
        (components.hour, components.minute, components.second) = (hour, minute, second)
        return (calendar ?? Self.utc).date(from: components) ?? .distantPast
    }

    private func clock(at date: Date) -> DayClock {
        DayClock(today: CalendarDay(date, calendar: Self.utc))
    }

    private func codes(_ view: SavedView, _ store: BoardStore, _ clock: DayClock) -> [String] {
        store.tasks(in: view, today: clock.today).map(\.code)
    }

    // MARK: The boundary itself

    @Test func twoSecondsApartAcrossMidnightIsANewDay() {
        let eve = clock(at: instant(2026, 6, 14, 23, 59, 59))
        let past = clock(at: instant(2026, 6, 15, 0, 0, 1))
        #expect(eve.today == CalendarDay(year: 2026, month: 6, day: 14))
        #expect(past.today == CalendarDay(year: 2026, month: 6, day: 15))
        #expect(eve.today.adding(days: 1) == past.today)
        #expect(past.today - eve.today == 1)

        // …and an hour either side of it is the same day twice.
        #expect(clock(at: instant(2026, 6, 15, 0, 0, 1)).today
                == clock(at: instant(2026, 6, 15, 23, 0, 0)).today)
    }

    // MARK: What the rollover moves

    @Test func everyDatedViewShiftsWhenTheDayDoes() {
        let store = ViewBoard.store()
        let eve = clock(at: instant(2026, 6, 14, 23, 59, 59))
        let past = clock(at: instant(2026, 6, 15, 0, 0, 1))
        #expect(past.today == ViewBoard.today)

        // NW-201 is due on the 14th and NW-202 on the 15th, so the boundary
        // moves one of them into Today and leaves the other there, overdue.
        #expect(codes(.today, store, eve) == ["NW-201", "NW-206"])
        #expect(codes(.today, store, past) == ["NW-201", "NW-202", "NW-206"])

        // NW-202 stops being ahead of the user…
        #expect(codes(.upcoming, store, eve) == ["NW-202", "NW-203", "NW-204", "NW-205"])
        #expect(codes(.upcoming, store, past) == ["NW-203", "NW-204", "NW-205"])

        // …and the seven-day window drops the 14th and picks up the 21st.
        #expect(codes(.dueThisWeek, store, eve) == ["NW-201", "NW-202", "NW-203"])
        #expect(codes(.dueThisWeek, store, past) == ["NW-202", "NW-203", "NW-204"])
    }

    @Test func theUndatedViewsReadTheSameOnEitherSideOfMidnight() {
        // Not an accident worth leaving untested: these three answer questions
        // the calendar has no part in, and a rollover must not disturb them.
        let store = ViewBoard.store(tasks: ViewBoard.tasks(archiving: [ViewBoard.dueTomorrow: 400]))
        let eve = clock(at: instant(2026, 6, 14, 23, 59, 59))
        let past = clock(at: instant(2026, 6, 15, 0, 0, 1))
        for view in [SavedView.highPriority, .recentlyUpdated, .archive] {
            #expect(codes(view, store, eve) == codes(view, store, past),
                    "\(view.rawValue) moved with the day")
        }
        #expect(codes(.highPriority, store, past) == ["NW-206", "NW-207"])
        #expect(codes(.archive, store, past) == ["NW-203"])
    }

    @Test func theTodayCountFollowsTheClockAndAgreesWithItsOwnList() {
        let store = ViewBoard.store()
        let eve = clock(at: instant(2026, 6, 14, 23, 59, 59))
        let past = clock(at: instant(2026, 6, 15, 0, 0, 1))
        #expect(store.count(of: .today, today: eve.today) == 2)
        #expect(store.count(of: .today, today: past.today) == 3)
        // The badge and the list it labels are the same question asked twice.
        for day in [eve, past] {
            #expect(store.count(of: .today, today: day.today)
                    == store.tasks(in: .today, today: day.today).count)
        }
    }

    // MARK: Boundaries the calendar cares about

    @Test func theRolloverWorksOverAYearEnd() {
        let newYear = CalendarDay(year: 2027, month: 1, day: 1)
        let tasks = [
            TaskItem(code: "NW-501", columnID: BoardColumn.backlog.id, title: "On the day",
                     due: newYear),
            TaskItem(code: "NW-502", columnID: BoardColumn.backlog.id, title: "A week after",
                     due: CalendarDay(year: 2027, month: 1, day: 7)),
        ]
        let store = TestBoard.store(tasks: tasks)
        let eve = clock(at: instant(2026, 12, 31, 23, 59, 59))
        let day = clock(at: instant(2027, 1, 1, 0, 0, 30))

        #expect(eve.today == CalendarDay(year: 2026, month: 12, day: 31))
        #expect(day.today == newYear)
        #expect(codes(.today, store, eve) == [])
        #expect(codes(.upcoming, store, eve) == ["NW-501", "NW-502"])
        #expect(codes(.dueThisWeek, store, eve) == ["NW-501"])            // the 7th is still 7 away
        #expect(codes(.today, store, day) == ["NW-501"])
        #expect(codes(.upcoming, store, day) == ["NW-502"])
        #expect(codes(.dueThisWeek, store, day) == ["NW-501", "NW-502"])
    }

    // MARK: The wake that gets the clock there

    /// `refresh()` only ever reads the wall clock, so what a test can actually
    /// hold still is the arithmetic that decides *when* to refresh. Sleeping
    /// too long leaves every due chip in the app reading yesterday.
    @Test func theWakeLandsJustPastTheNextMidnight() {
        let clock = DayClock(today: CalendarDay(year: 2026, month: 6, day: 14))

        // A second before the boundary, plus the second of overshoot.
        #expect(clock.secondsUntilNextMidnight(instant(2026, 6, 14, 23, 59, 59), calendar: Self.utc) == 2)
        // A second after it, which is a whole day short of the next one.
        #expect(clock.secondsUntilNextMidnight(instant(2026, 6, 15, 0, 0, 1), calendar: Self.utc) == 86_400)
        // Standing exactly on a boundary counts the next one, not this one: a
        // zero-second sleep here would spin.
        #expect(clock.secondsUntilNextMidnight(instant(2026, 6, 15, 0, 0, 0), calendar: Self.utc) == 86_401)
    }

    /// The reason the boundary is `date(byAdding: .day)` rather than
    /// `now + 86_400`. On a spring-forward day the next midnight is 23 hours
    /// away, and a wake that slept a flat day would read the old day for an
    /// hour after the app had already crossed into the new one.
    @Test func theWakeFollowsTheZoneAcrossADaylightSavingBoundary() {
        let clock = DayClock(today: CalendarDay(year: 2026, month: 3, day: 8))
        let short = instant(2026, 3, 8, 0, 0, 0, in: Self.newYork)     // clocks go forward
        let long = instant(2026, 11, 1, 0, 0, 0, in: Self.newYork)     // and back
        #expect(clock.secondsUntilNextMidnight(short, calendar: Self.newYork) == 23 * 3_600 + 1)
        #expect(clock.secondsUntilNextMidnight(long, calendar: Self.newYork) == 25 * 3_600 + 1)
    }

    @Test func theWakeIsNeverZeroOrNegative() {
        let clock = DayClock(today: CalendarDay(year: 2026, month: 6, day: 14))
        for hour in 0..<24 {
            for minute in [0, 59] {
                let seconds = clock.secondsUntilNextMidnight(
                    instant(2026, 6, 14, hour, minute, 59), calendar: Self.utc
                )
                #expect(seconds >= 1, "\(hour):\(minute)")
                #expect(seconds <= 86_401, "\(hour):\(minute)")
            }
        }
    }

    @Test func theWeeklyMeterRollsOverWithTheDayToo() {
        // The meter's window is `updatedAt`-based rather than due-based, so it
        // is the other half of the same question: does midnight move it.
        let anchor = CalendarDay(year: 2026, month: 6, day: 15)
        let shipped = TaskItem(code: "NW-601", columnID: BoardColumn.done.id, title: "Shipped",
                               createdAt: anchor.adding(days: -6).date(),
                               updatedAt: anchor.adding(days: -6).date())
        let touched = TaskItem(code: "NW-602", columnID: BoardColumn.backlog.id, title: "Touched",
                               createdAt: anchor.date(), updatedAt: anchor.date())
        let store = TestBoard.store(tasks: [shipped, touched])

        let eve = clock(at: instant(2026, 6, 14, 23, 59, 59))
        let past = clock(at: instant(2026, 6, 15, 0, 0, 1))
        let after = clock(at: instant(2026, 6, 16, 0, 0, 1))
        // Five days back on the eve, six on the day itself — the last day it is
        // inside the window — and seven the morning after, when it drops out.
        #expect(store.weeklyShippedCount(today: eve.today) == 1)
        #expect(store.weeklyShippedCount(today: past.today) == 1)
        #expect(store.weeklyShippedCount(today: after.today) == 0)
    }
}
