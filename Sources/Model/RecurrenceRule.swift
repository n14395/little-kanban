import Foundation

/// How a task comes back. A recurring card completes like any other; what the
/// rule governs is the *spawn* — the fresh card minted into the board's first
/// column with its due date advanced to the next occurrence this rule names.
///
/// The rule is pure data plus pure arithmetic. `nextOccurrence` runs on
/// `CalendarDay`'s integer day math for `CalendarDay`'s reasons: it sits on the
/// completion path, and a day plus a week is not really calendar work.
struct RecurrenceRule: Hashable, Codable, Sendable {
    enum Unit: String, Codable, CaseIterable, Sendable { case day, week, month, year }

    /// What the next occurrence counts from. `.schedule` keeps the cadence the
    /// due dates already spell out — a Monday task completed on Wednesday is
    /// still due next Monday. `.completion` counts from the day the work was
    /// actually done — water the plants a week after they were last watered,
    /// not a week after they were supposed to be.
    enum Basis: String, Codable, Sendable { case schedule, completion }

    /// Every N units. Held to `1...99` by `normalized` and again inside the
    /// arithmetic, so a rule that arrives damaged cannot divide by zero.
    var interval: Int = 1
    var unit: Unit = .week
    /// Which weekdays a `.week` rule lands on, in `Calendar.component(.weekday)`
    /// numbering — 1 is Sunday. Empty means the anchor day's own weekday, which
    /// is the plain every-N-weeks stride. Ignored by every other unit.
    var weekdays: Set<Int> = []
    var basis: Basis = .schedule
    /// The last day an occurrence may land on, inclusive. `nil` repeats forever.
    var until: CalendarDay?
    /// The day-of-month the rule is trying to hit, for `.month` and `.year`
    /// rules whose day can be clamped away. Kept separately from the due date
    /// so "the 31st" survives a trip through February — Jan 31 → Feb 28 →
    /// Mar 31 rather than drifting down to the 28th forever. `nil` means the
    /// anchor day's own day-of-month.
    var anchorDay: Int?

    /// Written out for one field: **`weekdays` is a `Set`, and a `Set` has no
    /// order to serialise.**
    ///
    /// Swift iterates one in whatever order its storage happens to give, and a
    /// set rebuilt by decoding does not inherit the order of the one that was
    /// encoded — so the same rule, written twice, produces different bytes. The
    /// board file is what that lands on: every save rewrites a card that has not
    /// changed, and every rolling backup differs from the one before it for no
    /// reason anybody could find. Sorted here, the bytes are a function of the
    /// value.
    ///
    /// Only the encoder is written; the decoder stays synthesised, reading an
    /// array into the `Set` as it always did.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(interval, forKey: .interval)
        try container.encode(unit, forKey: .unit)
        try container.encode(weekdays.sorted(), forKey: .weekdays)
        try container.encode(basis, forKey: .basis)
        try container.encodeIfPresent(until, forKey: .until)
        try container.encodeIfPresent(anchorDay, forKey: .anchorDay)
    }

    /// The rule with everything indefensible repaired, anchored to the due
    /// date it will run against. `setRecurrence` puts every rule through this
    /// on the way in, so the stored form is the one the arithmetic assumes.
    func normalized(anchoredTo due: CalendarDay?) -> RecurrenceRule {
        var rule = self
        rule.interval = min(max(interval, 1), 99)
        rule.weekdays = unit == .week ? Set(weekdays.filter { (1...7).contains($0) }) : []
        rule.anchorDay = switch unit {
        case .month, .year: anchorDay.map { min(max($0, 1), 31) } ?? due?.day
        case .day, .week: nil
        }
        return rule
    }

    // MARK: The next occurrence

    /// The day the spawned card is due, or `nil` when the rule has run out —
    /// the next hit would land past `until`.
    ///
    /// `completed` is the day the card was ticked off, which is always "today"
    /// at the moment this runs; `due` is the card's due date, the anchor the
    /// pattern is counted from. The answer is strictly after both, so an
    /// overdue daily task catches up in one tick — five days late does not
    /// mean five spawns due in the past — and completing early does not spawn
    /// a card already due.
    func nextOccurrence(after completed: CalendarDay, due: CalendarDay?) -> CalendarDay? {
        let step = min(max(interval, 1), 99)
        let anchor = basis == .completion ? completed : (due ?? completed)
        let floor = basis == .completion ? completed : max(anchor, completed)
        // After completion, the day being aimed for is the completion day's
        // own — `anchorDay` holds the *scheduled* day-of-month, which is the
        // one thing this basis is choosing not to count from.
        let target = basis == .completion ? nil : anchorDay
        let next = switch unit {
        case .day: Self.aligned(to: anchor, stride: step, after: floor)
        case .week: nextWeekly(anchor: anchor, step: step, after: floor)
        case .month: Self.byMonths(anchor: anchor, months: step, day: target, after: floor)
        case .year: Self.byMonths(anchor: anchor, months: step * 12, day: target, after: floor)
        }
        if let until, next > until { return nil }
        return next
    }

    /// The first `anchor + k·stride` strictly after `floor`, closed-form: the
    /// pattern stays aligned to the anchor however late the completion is.
    private static func aligned(to anchor: CalendarDay, stride: Int, after floor: CalendarDay) -> CalendarDay {
        let gap = floor - anchor
        let k = gap < 0 ? 1 : gap / stride + 1
        return anchor.adding(days: k * stride)
    }

    private func nextWeekly(anchor: CalendarDay, step: Int, after floor: CalendarDay) -> CalendarDay {
        let chips = weekdays.filter { (1...7).contains($0) }
        guard !chips.isEmpty else { return Self.aligned(to: anchor, stride: step * 7, after: floor) }
        // After completion, the count restarts: the balance of the interval,
        // then the first chipped weekday. On schedule, the chips live in weeks
        // aligned to the anchor's — every candidate day is checked against
        // both, and the scan is bounded by one full interval of weeks.
        let start = basis == .completion ? floor.adding(days: (step - 1) * 7) : floor
        var candidate = start.adding(days: 1)
        for _ in 0..<(step * 7 + 7) {
            if chips.contains(candidate.weekday),
               basis == .completion || (Self.weekIndex(of: candidate) - Self.weekIndex(of: anchor)) % step == 0 {
                return candidate
            }
            candidate = candidate.adding(days: 1)
        }
        return candidate
    }

    /// Months and years share one shape: advance the anchor's month in whole
    /// intervals until the hit lands strictly after `floor`, aiming for
    /// `day` (or the anchor's own) and clamping to the month that is there.
    private static func byMonths(anchor: CalendarDay, months: Int, day: Int?, after floor: CalendarDay) -> CalendarDay {
        let target = min(max(day ?? anchor.day, 1), 31)
        let base = anchor.year * 12 + anchor.month - 1
        let gap = (floor.year * 12 + floor.month - 1) - base
        var k = max(1, gap / months)
        while true {
            let index = base + k * months
            let candidate = CalendarDay(
                year: index / 12, month: index % 12 + 1,
                day: min(target, daysIn(month: index % 12 + 1, year: index / 12))
            )
            if candidate > floor { return candidate }
            k += 1
        }
    }

    /// Sunday-started weeks counted from a fixed epoch Sunday, so "every
    /// second week" means the same weeks on every device. Which day starts the
    /// week is presentation; alignment only needs the fortnights to agree.
    private static let epochSunday = CalendarDay(year: 1970, month: 1, day: 4)

    private static func weekIndex(of day: CalendarDay) -> Int {
        let days = day - epochSunday
        return days >= 0 ? days / 7 : (days - 6) / 7
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // MARK: Summary

    /// "Every 2 weeks on Mon, Fri" — the row under the toggle and the activity
    /// feed both read this. The weekday names come off the calendar so they
    /// are translated for free, ordered from the calendar's own first weekday.
    ///
    /// The singular is the catalogue's, not a ternary's: each key carries a
    /// `plural` variation whose `one` reads "Every day", which is where English
    /// grows its plural rules everywhere else in this app — see
    /// `LocalizationTests.everyCountNounCarriesItsSingular`.
    func summaryText(calendar: Calendar = .current) -> String {
        let step = min(max(interval, 1), 99)
        let cadence = switch unit {
        case .day:
            String(localized: "Every \(step) days", comment: "Repeat rule summary cadence; the singular reads 'Every day'")
        case .week:
            String(localized: "Every \(step) weeks", comment: "Repeat rule summary cadence; the singular reads 'Every week'")
        case .month:
            String(localized: "Every \(step) months", comment: "Repeat rule summary cadence; the singular reads 'Every month'")
        case .year:
            String(localized: "Every \(step) years", comment: "Repeat rule summary cadence; the singular reads 'Every year'")
        }
        let chips = weekdays.filter { (1...7).contains($0) }
        guard unit == .week, !chips.isEmpty else { return cadence }
        let names = chips
            .sorted { (($0 - calendar.firstWeekday + 7) % 7) < (($1 - calendar.firstWeekday + 7) % 7) }
            .map { calendar.shortWeekdaySymbols[$0 - 1] }
            .joined(separator: ", ")
        return String(localized: "\(cadence) on \(names)",
                      comment: "Repeat rule summary: cadence plus the weekday names it lands on")
    }
}

// MARK: - Reading an older rule

/// **In an extension, not in the body**, for `Board.init(from:)`'s reason: an
/// initialiser inside the struct takes the memberwise one with it.
extension RecurrenceRule {
    enum CodingKeys: String, CodingKey {
        case interval, unit, weekdays, basis, until, anchorDay
    }

    /// Lenient on every key, unlike the models around it, because a rule also
    /// travels through sync as an encoded blob: a future build that adds a
    /// field — or a unit this build has no case for — must read here as a
    /// near-enough rule rather than a decoding failure that drops the rule
    /// and writes the loss back. A rule has no key whose absence changes what
    /// kind of thing it is, so every default is safe to land on.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            interval: (try? container.decodeIfPresent(Int.self, forKey: .interval)) ?? 1,
            unit: (try? container.decodeIfPresent(Unit.self, forKey: .unit)) ?? .week,
            weekdays: (try? container.decodeIfPresent(Set<Int>.self, forKey: .weekdays)) ?? [],
            basis: (try? container.decodeIfPresent(Basis.self, forKey: .basis)) ?? .schedule,
            until: (try? container.decodeIfPresent(CalendarDay.self, forKey: .until)) ?? nil,
            anchorDay: (try? container.decodeIfPresent(Int.self, forKey: .anchorDay)) ?? nil
        )
    }
}
