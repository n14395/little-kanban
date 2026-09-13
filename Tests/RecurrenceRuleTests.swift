import Foundation
import Testing
@testable import LittleKanban

@Suite struct RecurrenceRuleTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    private func rule(
        _ interval: Int = 1, _ unit: RecurrenceRule.Unit = .week,
        weekdays: Set<Int> = [], basis: RecurrenceRule.Basis = .schedule,
        until: CalendarDay? = nil, anchorDay: Int? = nil
    ) -> RecurrenceRule {
        RecurrenceRule(interval: interval, unit: unit, weekdays: weekdays,
                       basis: basis, until: until, anchorDay: anchorDay)
    }

    // MARK: The weekday accessor

    @Test func weekdayMatchesTheCalendarsNumbering() {
        #expect(day(1970, 1, 1).weekday == 5)    // Thursday, day zero
        #expect(day(1970, 1, 4).weekday == 1)    // Sunday
        #expect(day(1969, 12, 31).weekday == 4)  // Wednesday, before the epoch
        #expect(day(2000, 1, 1).weekday == 7)    // Saturday
        #expect(day(2024, 2, 29).weekday == 5)   // a leap Thursday
        #expect(day(2026, 9, 7).weekday == 2)    // Monday
    }

    // MARK: Daily

    @Test func aDailyTaskCompletedOnTimeIsDueTomorrow() {
        let today = day(2026, 9, 7)
        #expect(rule(1, .day).nextOccurrence(after: today, due: today) == day(2026, 9, 8))
    }

    @Test func anOverdueDailyTaskCatchesUpInOneTick() {
        // Five days late is one spawn due tomorrow, not five due in the past.
        let due = day(2026, 9, 2)
        let completed = day(2026, 9, 7)
        #expect(rule(1, .day).nextOccurrence(after: completed, due: due) == day(2026, 9, 8))
    }

    @Test func aLateEveryThreeDaysStaysAlignedToItsAnchor() {
        // Anchored at the 7th, hits fall on the 10th, 13th, 16th; completing
        // on the 14th lands the next on the 16th, not the 17th.
        let due = day(2026, 9, 7)
        let completed = day(2026, 9, 14)
        #expect(rule(3, .day).nextOccurrence(after: completed, due: due) == day(2026, 9, 16))
    }

    @Test func completingEarlyStillCountsFromTheDueDate() {
        let due = day(2026, 9, 10)
        let completed = day(2026, 9, 7)
        #expect(rule(2, .day).nextOccurrence(after: completed, due: due) == day(2026, 9, 12))
    }

    @Test func aRuleWithNoDueDateCountsFromTheCompletion() {
        let completed = day(2026, 9, 7)
        #expect(rule(1, .day).nextOccurrence(after: completed, due: nil) == day(2026, 9, 8))
    }

    // MARK: Weekly

    @Test func aPlainWeeklyRuleAdvancesSevenDays() {
        let due = day(2026, 9, 9)
        #expect(rule(1, .week).nextOccurrence(after: due, due: due) == day(2026, 9, 16))
    }

    @Test func aLateFortnightlyRuleSkipsTheOccurrenceThatWentPast() {
        // Anchored Wed 9 Sep, hits fall on 23 Sep and 7 Oct; completed on
        // 25 Sep, the 23rd has already gone.
        let due = day(2026, 9, 9)
        let completed = day(2026, 9, 25)
        #expect(rule(2, .week).nextOccurrence(after: completed, due: due) == day(2026, 10, 7))
    }

    @Test func weekdayChipsLandOnTheNextChippedDay() {
        let monday = day(2026, 9, 7)
        let chips = rule(1, .week, weekdays: [2, 6])  // Mon, Fri
        #expect(chips.nextOccurrence(after: monday, due: monday) == day(2026, 9, 11))
        let friday = day(2026, 9, 11)
        #expect(chips.nextOccurrence(after: friday, due: friday) == day(2026, 9, 14))
    }

    @Test func anOverdueChippedRuleLandsAfterTheCompletion() {
        // Due Mon 7 Sep, completed Fri 11 Sep: the next Mon-or-Fri after the
        // completion is Mon 14 Sep, not the Friday being stood in.
        let due = day(2026, 9, 7)
        let completed = day(2026, 9, 11)
        #expect(rule(1, .week, weekdays: [2, 6]).nextOccurrence(after: completed, due: due) == day(2026, 9, 14))
    }

    @Test func chipsOnAFortnightlyRuleKeepTheWeeksAligned() {
        let monday = day(2026, 9, 7)
        let fortnightlyMonday = rule(2, .week, weekdays: [2])
        // The Monday one week out belongs to the off week.
        #expect(fortnightlyMonday.nextOccurrence(after: monday, due: monday) == day(2026, 9, 21))
        // Completed late, the pattern's weeks have not moved.
        let late = day(2026, 9, 22)
        #expect(fortnightlyMonday.nextOccurrence(after: late, due: monday) == day(2026, 10, 5))
    }

    @Test func chipsOutsideTheWeekReadAsNoChips() {
        let due = day(2026, 9, 9)
        #expect(rule(1, .week, weekdays: [0, 8]).nextOccurrence(after: due, due: due) == day(2026, 9, 16))
    }

    // MARK: After completion

    @Test func completionBasisCountsFromTheDayItWasDone() {
        // Due Monday, done Wednesday: a week after Wednesday, the Monday
        // schedule forgotten.
        let due = day(2026, 9, 7)
        let completed = day(2026, 9, 9)
        let after = rule(1, .week, basis: .completion)
        #expect(after.nextOccurrence(after: completed, due: due) == day(2026, 9, 16))
    }

    @Test func completionBasisWithChipsFindsTheFirstChippedDayAfterTheInterval() {
        let completed = day(2026, 9, 9)  // a Wednesday
        let weekly = rule(1, .week, weekdays: [2, 6], basis: .completion)
        #expect(weekly.nextOccurrence(after: completed, due: nil) == day(2026, 9, 11))
        let fortnightly = rule(2, .week, weekdays: [2], basis: .completion)
        #expect(fortnightly.nextOccurrence(after: completed, due: nil) == day(2026, 9, 21))
    }

    @Test func completionBasisMonthsCountFromTheCompletionsOwnDay() {
        // anchorDay holds the scheduled day-of-month; after completion it is
        // deliberately not what the count runs from.
        let completed = day(2026, 1, 20)
        let monthly = rule(1, .month, basis: .completion, anchorDay: 31)
        #expect(monthly.nextOccurrence(after: completed, due: day(2026, 1, 31)) == day(2026, 2, 20))
    }

    // MARK: Monthly

    @Test func aMonthlyRuleClampsToShortMonthsWithoutDrifting() {
        let monthly = rule(1, .month, anchorDay: 31)
        let january = day(2026, 1, 31)
        let february = day(2026, 2, 28)
        // Jan 31 → Feb 28 → Mar 31: the 31st survives the trip through February.
        #expect(monthly.nextOccurrence(after: january, due: january) == february)
        #expect(monthly.nextOccurrence(after: february, due: february) == day(2026, 3, 31))
    }

    @Test func aMonthlyRuleWithNoAnchorUsesTheDueDatesDay() {
        let due = day(2026, 1, 31)
        #expect(rule(1, .month).nextOccurrence(after: due, due: due) == day(2026, 2, 28))
    }

    @Test func aLateEveryTwoMonthsSkipsToTheNextAlignedMonth() {
        // Anchored 15 Jan, hits fall on 15 Mar and 15 May; completed 20 Mar,
        // March's has gone.
        let due = day(2026, 1, 15)
        let completed = day(2026, 3, 20)
        #expect(rule(2, .month).nextOccurrence(after: completed, due: due) == day(2026, 5, 15))
    }

    // MARK: Yearly

    @Test func aLeapDayRuleClampsAndRecovers() {
        let yearly = rule(1, .year, anchorDay: 29)
        let leap = day(2024, 2, 29)
        #expect(yearly.nextOccurrence(after: leap, due: leap) == day(2025, 2, 28))
        // The anchor remembers the 29th across three clamped years.
        let common = day(2027, 2, 28)
        #expect(yearly.nextOccurrence(after: common, due: common) == day(2028, 2, 29))
    }

    @Test func everySecondYearAdvancesTwoYears() {
        let due = day(2026, 6, 10)
        #expect(rule(2, .year).nextOccurrence(after: due, due: due) == day(2028, 6, 10))
    }

    // MARK: The end date

    @Test func untilIsInclusive() {
        let due = day(2026, 9, 7)
        let lastDay = day(2026, 9, 8)
        #expect(rule(1, .day, until: lastDay).nextOccurrence(after: due, due: due) == lastDay)
        #expect(rule(1, .day, until: due).nextOccurrence(after: due, due: due) == nil)
    }

    // MARK: Repair

    @Test func normalizedRepairsAnIndefensibleRule() {
        let due = day(2026, 1, 31)
        let broken = rule(0, .week, weekdays: [0, 3, 9], anchorDay: 40)
        let repaired = broken.normalized(anchoredTo: due)
        #expect(repaired.interval == 1)
        #expect(repaired.weekdays == [3])
        #expect(repaired.anchorDay == nil)
        #expect(rule(500, .day).normalized(anchoredTo: nil).interval == 99)
    }

    @Test func normalizedAnchorsAMonthlyRuleToItsDueDate() {
        let monthly = rule(1, .month).normalized(anchoredTo: day(2026, 1, 31))
        #expect(monthly.anchorDay == 31)
        #expect(monthly.weekdays.isEmpty)
        let unanchored = rule(1, .month).normalized(anchoredTo: nil)
        #expect(unanchored.anchorDay == nil)
    }

    @Test func aDamagedIntervalCannotStallTheArithmetic() {
        let due = day(2026, 9, 7)
        #expect(rule(0, .day).nextOccurrence(after: due, due: due) == day(2026, 9, 8))
        #expect(rule(-3, .week).nextOccurrence(after: due, due: due) == day(2026, 9, 14))
    }

    // MARK: Reading an older rule

    @Test func anEmptyObjectDecodesToTheDefaultRule() throws {
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: Data("{}".utf8))
        #expect(decoded == RecurrenceRule())
    }

    @Test func aUnitFromTheFutureLandsOnWeeklyRatherThanFailing() throws {
        let json = #"{"interval": 3, "unit": "fortnight", "basis": "completion"}"#
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8))
        #expect(decoded.unit == .week)
        #expect(decoded.interval == 3)
        #expect(decoded.basis == .completion)
    }

    @Test func anUnknownKeySurvivesDecoding() throws {
        let json = #"{"unit": "month", "anchorDay": 15, "snoozePolicy": "gentle"}"#
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8))
        #expect(decoded.unit == .month)
        #expect(decoded.anchorDay == 15)
    }

    @Test func aRuleRoundTripsThroughItsCoding() throws {
        let original = rule(2, .week, weekdays: [2, 6], basis: .completion,
                            until: day(2027, 3, 1))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecurrenceRule.self, from: data)
        #expect(decoded == original)
    }

    // MARK: The summary

    @Test func theSummaryNamesTheIntervalAndTheChippedDays() {
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US")
        let plain = rule(1, .week).summaryText(calendar: english)
        let counted = rule(2, .week).summaryText(calendar: english)
        #expect(plain != counted)
        #expect(counted.contains("2"))
        let chipped = rule(2, .week, weekdays: [2, 6]).summaryText(calendar: english)
        #expect(chipped.contains(english.shortWeekdaySymbols[1]))  // Mon
        #expect(chipped.contains(english.shortWeekdaySymbols[5]))  // Fri
        #expect(rule(1, .month, weekdays: [2]).summaryText(calendar: english)
            == rule(1, .month).summaryText(calendar: english))
    }

    @Test func theSummaryOrdersChipsFromTheCalendarsFirstWeekday() throws {
        var mondayFirst = Calendar(identifier: .gregorian)
        mondayFirst.locale = Locale(identifier: "en_US")
        mondayFirst.firstWeekday = 2
        let text = rule(1, .week, weekdays: [1, 2]).summaryText(calendar: mondayFirst)
        let monday = try #require(text.range(of: mondayFirst.shortWeekdaySymbols[1]))
        let sunday = try #require(text.range(of: mondayFirst.shortWeekdaySymbols[0]))
        #expect(monday.lowerBound < sunday.lowerBound)
    }
}
