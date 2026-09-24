// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

@Suite struct CalendarDayTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .gmt
        return calendar
    }

    private func instant(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in zone: String) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return try #require(calendar(zone).date(from: components))
    }

    // MARK: Components

    @Test func componentsThatNameNoRealDayResolveToOne() {
        #expect(CalendarDay(year: 2025, month: 2, day: 31) == CalendarDay(year: 2025, month: 3, day: 3))
        #expect(CalendarDay(year: 2026, month: 2, day: 29) == CalendarDay(year: 2026, month: 3, day: 1))
        #expect(CalendarDay(year: 2026, month: 13, day: 1) == CalendarDay(year: 2027, month: 1, day: 1))
    }

    @Test func aRealDayIsLeftAlone() {
        let day = CalendarDay(year: 2024, month: 2, day: 29)
        #expect((day.year, day.month, day.day) == (2024, 2, 29))
    }

    @Test func theDayIsResolvedAtMiddaySoNoTimeZoneCanSlideIt() throws {
        // 8 March 2026 is the spring-forward Sunday in New York: the day starts
        // at 00:00 and 02:00 does not exist.
        let newYork = calendar("America/New_York")
        let date = CalendarDay(year: 2026, month: 3, day: 8).date(in: newYork)
        let components = newYork.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 8)
        #expect(components.hour == 12)
    }

    // MARK: Day arithmetic

    @Test func addingOneDayCrossesEveryKindOfBoundary() {
        let boundaries = [
            ((2026, 1, 31), (2026, 2, 1)),      // month end
            ((2026, 2, 28), (2026, 3, 1)),      // February in a common year
            ((2024, 2, 28), (2024, 2, 29)),     // February in a leap year
            ((2024, 2, 29), (2024, 3, 1)),
            ((2026, 12, 31), (2027, 1, 1)),     // year end
            ((2026, 3, 7), (2026, 3, 8)),       // into a 23-hour day (US spring forward)
            ((2026, 11, 1), (2026, 11, 2)),     // out of a 25-hour day (US fall back)
        ]
        for (from, to) in boundaries {
            let start = CalendarDay(year: from.0, month: from.1, day: from.2)
            let expected = CalendarDay(year: to.0, month: to.1, day: to.2)
            #expect(start.adding(days: 1) == expected, "\(start) + 1")
            #expect(start.adding(days: 1, in: calendar("America/New_York")) == expected, "\(start) + 1 in New York")
            #expect(expected - start == 1, "\(expected) - \(start)")
            #expect(start - expected == -1, "\(start) - \(expected)")
            #expect(expected.adding(days: -1) == start, "\(expected) - 1")
        }
    }

    @Test func dstDoesNotCostOrAddADay() {
        // Two calendar days apart, but 47 and 49 wall-clock hours respectively.
        #expect(CalendarDay(year: 2026, month: 3, day: 9) - CalendarDay(year: 2026, month: 3, day: 7) == 2)
        #expect(CalendarDay(year: 2026, month: 11, day: 3) - CalendarDay(year: 2026, month: 11, day: 1) == 2)
    }

    @Test func distanceIsWholeDaysInBothDirections() {
        let day = CalendarDay(year: 2026, month: 8, day: 20)
        #expect(day - day == 0)
        #expect(day.adding(days: 365) - day == 365)
        #expect(day.adding(days: -365) - day == -365)
    }

    @Test func orderingIsChronological() {
        let days = [
            CalendarDay(year: 2026, month: 1, day: 2),
            CalendarDay(year: 2025, month: 12, day: 31),
            CalendarDay(year: 2026, month: 1, day: 1),
            CalendarDay(year: 2026, month: 2, day: 1),
        ]
        #expect(days.sorted().map(\.description) == ["2025-12-31", "2026-01-01", "2026-01-02", "2026-02-01"])
    }

    // MARK: Time zones

    @Test func theDayBoundaryIsWhereverTheCalendarSaysItIs() throws {
        // 23:30 UTC is the small hours of the next day in Tokyo and still the
        // evening of the same day in New York.
        let evening = try instant(2026, 8, 20, 23, 30, in: "UTC")
        #expect(CalendarDay(evening, calendar: calendar("Asia/Tokyo")) == CalendarDay(year: 2026, month: 8, day: 21))
        #expect(CalendarDay(evening, calendar: calendar("America/New_York")) == CalendarDay(year: 2026, month: 8, day: 20))
        #expect(CalendarDay(evening, calendar: calendar("UTC")) == CalendarDay(year: 2026, month: 8, day: 20))
    }

    @Test func aDayInHandMeansTheSameDayWhereverItIsRead() throws {
        // The point of storing a day rather than an instant: crossing a time
        // zone must not move a task due "today" onto another date.
        let day = CalendarDay(year: 2026, month: 8, day: 20)
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "Asia/Kolkata", "UTC"] {
            let roundTripped = CalendarDay(day.date(in: calendar(zone)), calendar: calendar(zone))
            #expect(roundTripped == day, "\(zone)")
        }
        // And the distance between two days does not depend on who is asking.
        #expect(day.adding(days: 1, in: calendar("Pacific/Kiritimati")) - day == 1)
        #expect(day.adding(days: 1, in: calendar("Pacific/Pago_Pago")) - day == 1)
    }

    @Test func todayReadsTheInstantItIsGiven() throws {
        let noon = try instant(2026, 8, 20, 12, 0, in: "UTC")
        #expect(CalendarDay.today(noon, calendar: calendar("UTC")) == CalendarDay(year: 2026, month: 8, day: 20))
    }

    // MARK: Codable

    @Test func theOnDiskFormIsAZeroPaddedDay() throws {
        let encoder = JSONEncoder()
        let json = String(decoding: try encoder.encode([CalendarDay(year: 26, month: 1, day: 5)]), as: UTF8.self)
        #expect(json == #"["0026-01-05"]"#)
        #expect(CalendarDay(year: 2026, month: 8, day: 20).description == "2026-08-20")
    }

    @Test func roundTripsThroughJSON() throws {
        let days = [
            CalendarDay(year: 2024, month: 2, day: 29),
            CalendarDay(year: 2026, month: 12, day: 31),
            CalendarDay(year: 1900, month: 1, day: 1),
            CalendarDay(year: 2100, month: 12, day: 31),
        ]
        let data = try JSONEncoder().encode(days)
        #expect(try JSONDecoder().decode([CalendarDay].self, from: data) == days)
    }

    @Test(arguments: ["2026-02-29", "2025-02-31", "2026-13-01", "2026-00-10", "2026-01-00"])
    func decodingRejectsADayThatDoesNotExist(_ text: String) {
        // Not resolved quietly: the file said a day, and a value that renders as
        // one date and computes as another is worse than a loud failure.
        #expect(CalendarDay(exactly: text) == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([CalendarDay].self, from: Data(#"["\#(text)"]"#.utf8))
        }
    }

    @Test(arguments: ["26-1-5", "2026-1-5", "2026-01-5", "2026/01/05", "2026-08-20T00:00:00Z", "", "today", "-2026-01-05"])
    func decodingRejectsAnythingButFourTwoTwo(_ text: String) {
        #expect(CalendarDay(exactly: text) == nil)
    }

    @Test func decodingAcceptsALeapDay() throws {
        let decoded = try JSONDecoder().decode([CalendarDay].self, from: Data(#"["2024-02-29"]"#.utf8))
        #expect(decoded == [CalendarDay(year: 2024, month: 2, day: 29)])
    }
}
