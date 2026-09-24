// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A due date is a *day*, not an instant. Storing the calendar day keeps a task
/// due "today" reading as today after the device crosses a time zone.
///
/// The components are Gregorian — that is what the `YYYY-MM-DD` on-disk form
/// commits to — but the day *boundary* is whatever the passed calendar's time
/// zone says it is, which is what makes the conversion from an instant local.
struct CalendarDay: Hashable, Comparable, Codable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    /// Components that do not name a real day — `2025-02-31` — are resolved the
    /// way the calendar would resolve them anyway, to 3 March, so a value in
    /// hand always names a day that exists and `description` can never disagree
    /// with what `date(in:)` and `-` compute from it. Decoding does not lean on
    /// this: it rejects text that needs resolving rather than quietly rewriting
    /// what the user's file said.
    init(year: Int, month: Int, day: Int) {
        let resolved = CalendarDay.resolve(year: year, month: month, day: day)
        self.year = resolved.year
        self.month = resolved.month
        self.day = resolved.day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let components = CalendarDay.gregorian(calendar)
            .dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1, month: components.month ?? 1, day: components.day ?? 1)
    }

    static func today(_ now: Date = .now, calendar: Calendar = .current) -> CalendarDay {
        CalendarDay(now, calendar: calendar)
    }

    /// Midday in `calendar`, so DST transitions cannot slide the day.
    func date(in calendar: Calendar = .current) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return CalendarDay.gregorian(calendar).date(from: components) ?? .now
    }

    /// The `calendar` is accepted for the call sites that have one to offer and
    /// ignored, because a day plus a day is calendar arithmetic only in name:
    /// the components are Gregorian by this type's contract, so the sum is pure
    /// integer work — see `ordinal`. Going through `Calendar` here used to cost
    /// three ICU round-trips, and both this and `-` sit inside per-task loops:
    /// every saved-view match, every reminder, every due chip.
    func adding(days: Int, in calendar: Calendar = .current) -> CalendarDay {
        _ = calendar
        return CalendarDay(ordinal: ordinal + days)
    }

    /// Whole days between two days. Time-zone independent: both sides are
    /// Gregorian components already, so the distance is a subtraction.
    static func - (lhs: CalendarDay, rhs: CalendarDay) -> Int {
        lhs.ordinal - rhs.ordinal
    }

    /// The day of the week in `Calendar.component(.weekday)`'s numbering —
    /// 1 is Sunday, 7 is Saturday — read off `ordinal` rather than through a
    /// calendar, for `adding(days:)`'s reason: day zero, 1 January 1970, was
    /// a Thursday, and the cycle has not changed since.
    var weekday: Int {
        let shifted = (ordinal + 4) % 7
        return (shifted < 0 ? shifted + 7 : shifted) + 1
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar — Howard
    /// Hinnant's `days_from_civil`, exact for every representable day. The one
    /// divergence from Foundation's hybrid calendar is dates before the 1582
    /// changeover, which no date picker in this app can produce.
    private var ordinal: Int {
        let shiftedYear = year - (month <= 2 ? 1 : 0)
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let marchMonth = (month + 9) % 12
        let dayOfYear = (153 * marchMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }

    /// `civil_from_days` — the inverse of `ordinal`, bypassing `resolve`
    /// because the components it computes always name a real day.
    private init(ordinal: Int) {
        let shifted = ordinal + 719468
        let era = (shifted >= 0 ? shifted : shifted - 146096) / 146097
        let dayOfEra = shifted - era * 146097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365
        let shiftedYear = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let marchMonth = (5 * dayOfYear + 2) / 153
        day = dayOfYear - (153 * marchMonth + 2) / 5 + 1
        month = marchMonth < 10 ? marchMonth + 3 : marchMonth - 9
        year = shiftedYear + (month <= 2 ? 1 : 0)
    }

    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Puts the components through a fixed calendar and reads them back, at
    /// midday so no time zone's DST can move the day.
    private static func resolve(year: Int, month: Int, day: Int) -> (year: Int, month: Int, day: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = utc.date(from: components) else { return (year, month, day) }
        let resolved = utc.dateComponents([.year, .month, .day], from: date)
        guard let resolvedYear = resolved.year,
              let resolvedMonth = resolved.month,
              let resolvedDay = resolved.day
        else { return (year, month, day) }
        return (resolvedYear, resolvedMonth, resolvedDay)
    }

    private static func gregorian(_ calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian, calendar.identifier != .iso8601 else { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.locale = calendar.locale
        return gregorian
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }()
}

extension CalendarDay: CustomStringConvertible {
    /// `2026-08-20` — also the on-disk form.
    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension CalendarDay {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let day = CalendarDay(exactly: text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a real YYYY-MM-DD day, got \"\(text)\""
            )
        }
        self = day
    }

    /// Parses the on-disk form, and only that. The shape has to be exactly
    /// four-two-two digits, because `"26-1-5"` would otherwise read as year 26
    /// and rewrite itself as `"0026-01-05"` on the next save. The components
    /// then have to survive the calendar unchanged, which is what rejects
    /// `"2025-02-31"` and a 29 February outside a leap year without either
    /// being special-cased.
    init?(exactly text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ part in part.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let candidate = CalendarDay(year: year, month: month, day: day)
        guard (candidate.year, candidate.month, candidate.day) == (year, month, day) else { return nil }
        self = candidate
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
