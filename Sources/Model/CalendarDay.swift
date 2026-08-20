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

    func adding(days: Int, in calendar: Calendar = .current) -> CalendarDay {
        let calendar = CalendarDay.gregorian(calendar)
        guard let shifted = calendar.date(byAdding: .day, value: days, to: date(in: calendar)) else {
            return self
        }
        return CalendarDay(shifted, calendar: calendar)
    }

    /// Whole days between two days. Time-zone independent: both sides are
    /// resolved in the same fixed calendar.
    static func - (lhs: CalendarDay, rhs: CalendarDay) -> Int {
        let calendar = utc
        return calendar.dateComponents(
            [.day], from: rhs.date(in: calendar), to: lhs.date(in: calendar)
        ).day ?? 0
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
