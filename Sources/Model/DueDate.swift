import Foundation
import Synchronization

/// How close a due date is. This is what the due chip's colour encodes, and it
/// is the native replacement for the design's string matching: the spec tinted
/// on the literals "Today" and "Thu"/"Fri", which are simply day distances of
/// 0 and 1–2 from the Wednesday its mockup was drawn on.
enum DueUrgency: Hashable, Sendable {
    case overdue, today, soon, later
}

/// Derives a due date's display text and urgency from how far away it is.
///
/// Everything is a whole-day distance, and today is always passed in rather
/// than read from the clock: views take it from `DayClock` so they re-render
/// when the day rolls over, and tests can name any day they like.
enum DueDate {
    /// Whole calendar days from `today` to `day`. Negative is past.
    static func daysAway(_ day: CalendarDay, from today: CalendarDay) -> Int {
        day - today
    }

    static func urgency(_ day: CalendarDay, from today: CalendarDay) -> DueUrgency {
        switch daysAway(day, from: today) {
        case ..<0: .overdue
        case 0: .today
        case 1...2: .soon
        default: .later
        }
    }

    /// The chip's text. Inside the surrounding fortnight this is relative
    /// ("Today", "Thu", "Next week"); beyond it, an absolute short date, because
    /// "in 3 weeks" stops being easier to read than the day itself.
    ///
    /// Memoised on the pair, both labels alike: every dated card builds both on
    /// every render — the spoken one is assembled whether or not VoiceOver is
    /// running — and each was a calendar conversion, an ICU format and a bundle
    /// lookup for an answer that cannot change until the day does.
    static func label(_ day: CalendarDay, from today: CalendarDay) -> String {
        cached(day, today, in: labels) {
            let date = day.date()
            switch daysAway(day, from: today) {
            case ...(-14): return date.formatted(.dateTime.day().month(.abbreviated))
            case (-13)...(-7): return String(localized: "Last week", comment: "Due chip, 1–2 weeks overdue")
            case (-6)...(-2): return weekday(date)
            case -1: return String(localized: "Yesterday", comment: "Due chip, one day overdue")
            case 0: return String(localized: "Today", comment: "Due chip, due today")
            case 1...6: return weekday(date)
            case 7...13: return String(localized: "Next week", comment: "Due chip, due 1–2 weeks out")
            default: return date.formatted(.dateTime.day().month(.abbreviated))
            }
        }
    }

    /// The compact label is ambiguous by design — "Mon" is last Monday or next
    /// Monday depending on a colour VoiceOver cannot see — so the spoken form
    /// spells the day out and says which side of today it falls on.
    static func accessibilityLabel(_ day: CalendarDay, from today: CalendarDay) -> String {
        cached(day, today, in: spoken) {
            let date = day.date().formatted(.dateTime.weekday(.wide).day().month(.wide))
            switch urgency(day, from: today) {
            case .overdue:
                return String(localized: "Overdue, \(date)", comment: "VoiceOver label for a past due date")
            case .today:
                return String(localized: "Due today, \(date)", comment: "VoiceOver label for a due date today")
            case .soon, .later:
                return String(localized: "Due \(date)", comment: "VoiceOver label for a future due date")
            }
        }
    }

    private struct LabelKey: Hashable {
        var day: CalendarDay
        var today: CalendarDay
    }

    private static let labels = Mutex<[LabelKey: String]>([:])
    private static let spoken = Mutex<[LabelKey: String]>([:])

    private static func cached(
        _ day: CalendarDay, _ today: CalendarDay,
        in store: borrowing Mutex<[LabelKey: String]>, or make: () -> String
    ) -> String {
        let key = LabelKey(day: day, today: today)
        if let hit = store.withLock({ $0[key] }) { return hit }
        let made = make()
        store.withLock {
            // The keys change once a day; the cap only exists so a session
            // left running for months cannot grow the map without bound.
            if $0.count > 512 { $0.removeAll(keepingCapacity: true) }
            $0[key] = made
        }
        return made
    }

    private static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    // MARK: Editing presets

    /// The quick options the due-date pickers offer beside the calendar.
    enum Preset: String, CaseIterable, Identifiable, Sendable {
        case today, tomorrow, nextWeek

        var id: String { rawValue }

        var label: String {
            switch self {
            case .today: String(localized: "Today", comment: "Due date preset")
            case .tomorrow: String(localized: "Tomorrow", comment: "Due date preset")
            case .nextWeek: String(localized: "Next week", comment: "Due date preset")
            }
        }

        func day(from today: CalendarDay) -> CalendarDay {
            switch self {
            case .today: today
            case .tomorrow: today.adding(days: 1)
            case .nextWeek: today.adding(days: 7)
            }
        }
    }

    /// `days` from `today`. Negative is past — how `SeedData` is written.
    static func offset(_ days: Int, from today: CalendarDay) -> CalendarDay {
        today.adding(days: days)
    }
}
