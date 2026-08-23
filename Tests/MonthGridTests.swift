import Foundation
import Testing
@testable import Simple_Kanban

/// The calendar's arithmetic, which is the half of a hand-rolled month grid
/// that can be wrong without looking wrong.
///
/// A drawn calendar is checked by reading it; what a test is for is the cases
/// nobody scrolls to — a month that starts exactly on the first column, a leap
/// February, a step from a 31-day month, and the year rolling over at both
/// ends. All of it against a *fixed* calendar and locale, so a suite run in
/// another region does not report a different month.
@MainActor
@Suite struct MonthGridTests {
    /// Gregorian, weeks starting on Monday, English — the shape the screenshots
    /// in the README were taken at. The view itself asks `Calendar.current`.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private func grid(_ year: Int, _ month: Int) -> [CalendarDay] {
        MonthGrid.days(inMonthOf: CalendarDay(year: year, month: month, day: 1), calendar: calendar)
    }

    // MARK: The grid

    @Test func aGridIsAlwaysSixWholeWeeks() {
        // Six, whatever the month — a grid that grew and shrank would move the
        // rows under a pointer already on its way to one.
        for month in 1...12 {
            #expect(grid(2026, month).count == 42, "\(month) is not six weeks")
        }
        #expect(grid(2028, 2).count == 42)      // a leap February, 29 days
        #expect(grid(2026, 2).count == 42)      // and a plain one, 28
    }

    @Test func everyRowStartsOnTheCalendarsFirstDayOfTheWeek() {
        let days = grid(2026, 8)
        for week in 0..<6 {
            let first = days[week * 7].date(in: calendar)
            #expect(calendar.component(.weekday, from: first) == calendar.firstWeekday)
        }
    }

    @Test func theMonthItselfIsAllThereInOrderAndOnce() {
        let days = grid(2026, 8)
        let august = days.filter { $0.month == 8 && $0.year == 2026 }
        #expect(august.count == 31)
        #expect(august.first == CalendarDay(year: 2026, month: 8, day: 1))
        #expect(august.last == CalendarDay(year: 2026, month: 8, day: 31))
        #expect(august == august.sorted())
        #expect(Set(days).count == 42, "a day is drawn twice")
    }

    @Test func theEdgesAreTheNeighbouringMonths() {
        // August 2026 starts on a Saturday, so the first row carries five days
        // of July and the last rows carry September's.
        let days = grid(2026, 8)
        #expect(days.first == CalendarDay(year: 2026, month: 7, day: 27))
        #expect(days.last == CalendarDay(year: 2026, month: 9, day: 6))
        // Consecutive, end to end: the grid is one run of days, not three
        // stitched together.
        for (earlier, later) in zip(days, days.dropFirst()) {
            #expect(later == earlier.adding(days: 1, in: calendar))
        }
    }

    @Test func aMonthStartingOnTheFirstColumnHasNoSpillAboveIt() {
        // June 2026 starts on a Monday, which is this calendar's first day — so
        // the grid starts on the 1st rather than on a week of May.
        #expect(grid(2026, 6).first == CalendarDay(year: 2026, month: 6, day: 1))
    }

    @Test func theYearRollsOverAtBothEndsOfTheGrid() {
        #expect(grid(2026, 1).first == CalendarDay(year: 2025, month: 12, day: 29))
        #expect(grid(2026, 12).last == CalendarDay(year: 2027, month: 1, day: 10))
    }

    // MARK: The headings

    @Test func theColumnsAreNamedFromTheCalendarsOwnFirstWeekday() {
        #expect(MonthGrid.weekdayTitles(calendar: calendar).first == "Mon")
        #expect(MonthGrid.weekdayTitles(calendar: calendar).last == "Sun")

        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        #expect(MonthGrid.weekdayTitles(calendar: sundayFirst).first == "Sun")
        #expect(MonthGrid.weekdayTitles(calendar: sundayFirst).count == 7)
    }

    @Test func theTitleNamesTheMonthAndTheYear() {
        let title = MonthGrid.monthTitle(
            CalendarDay(year: 2026, month: 8, day: 23), locale: Locale(identifier: "en_GB")
        )
        #expect(title.contains("August"))
        #expect(title.contains("2026"))
    }

    // MARK: Stepping

    /// The arrows. The day of the month is dropped on purpose: the 31st is not a
    /// day of every month, and a step that resolved it forward would land on the
    /// 1st of the month *after* and skip one every time it was pressed from a
    /// long month.
    @Test func aStepMovesOneMonthFromAnyDayOfIt() {
        let longMonth = CalendarDay(year: 2026, month: 1, day: 31)
        #expect(DueDateField.month(longMonth, by: 1) == CalendarDay(year: 2026, month: 2, day: 1))
        #expect(DueDateField.month(longMonth, by: -1) == CalendarDay(year: 2025, month: 12, day: 1))
    }

    @Test func aStepRollsTheYearAtBothEnds() {
        let december = CalendarDay(year: 2026, month: 12, day: 9)
        #expect(DueDateField.month(december, by: 1) == CalendarDay(year: 2027, month: 1, day: 1))
        let january = CalendarDay(year: 2026, month: 1, day: 9)
        #expect(DueDateField.month(january, by: -1) == CalendarDay(year: 2025, month: 12, day: 1))
    }

    @Test func twelveStepsIsAYear() {
        var day = CalendarDay(year: 2026, month: 5, day: 20)
        for _ in 0..<12 { day = DueDateField.month(day, by: 1) }
        #expect(day == CalendarDay(year: 2027, month: 5, day: 1))
        for _ in 0..<12 { day = DueDateField.month(day, by: -1) }
        #expect(day == CalendarDay(year: 2026, month: 5, day: 1))
    }
}
