import Foundation

/// What one typed line of capture turns out to have said.
///
/// "Ship the beta next friday !high #bug" is a title, a day, a priority and a
/// label, and typing it as four separate controls is four decisions in the
/// moment somebody is trying to write one thing down. This is the reading of
/// that line — and it is a *reading*, not a rewriting: nothing here touches the
/// store, and every token it claims comes back in ``taken`` so the surface that
/// asked can show what it is about to do and be told no.
///
/// **Two rules keep it from eating text nobody offered it.**
///
/// - **A sigil is consent.** `#` and `!` are the user reaching for the grammar,
///   so those are read anywhere in the line.
/// - **A date has to be at the end.** "Call Friday about the invoice" keeps its
///   Friday; "Call about the invoice friday" does not. Nearly every false
///   positive a date grammar produces is a day name used as a noun in the
///   middle of a sentence, and a trailing-only rule costs one word order to
///   remove the lot of them.
///
/// Pure, and everything it could read from the world is a parameter: the labels
/// to match against, the day "tomorrow" is measured from, the calendar the week
/// is shaped by. That is what lets the suite name a Wednesday and ask what
/// "next friday" meant on it.
struct CaptureParse: Equatable, Sendable {
    /// The line with every claimed token removed. Never empty: see ``parse``.
    var title: String
    var due: CalendarDay?
    var priority: Priority?
    var labelKeys: [String] = []
    /// Everything this parse claimed, in the order it was written, so a preview
    /// reads left to right the way the line does.
    var taken: [Token] = []

    var isPlain: Bool { taken.isEmpty }

    /// One claimed token: what it means, and what it looked like.
    struct Token: Equatable, Hashable, Sendable, Identifiable {
        enum Meaning: Equatable, Hashable, Sendable {
            case due(CalendarDay)
            case priority(Priority)
            /// The name as well as the key, because the chip explaining this
            /// token says "Bug" and the store needs `bug`.
            case label(key: String, name: String)
        }

        var meaning: Meaning
        /// Exactly as typed. This is both what a preview quotes back and the
        /// key a refusal is remembered under — see ``CaptureParse/parse``.
        var text: String

        var id: String { text }
    }

    /// The line taken at face value: no tokens, nothing claimed.
    static func plain(_ input: String) -> CaptureParse {
        CaptureParse(title: input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Reads `input`.
    ///
    /// `rejected` holds tokens the user has already handed back — keyed by the
    /// folded text, so refusing `#Bug` keeps refusing it when they retype it as
    /// `#bug`. A refusal means the words stay in the title, which is the whole
    /// escape hatch: there is no backslash to learn.
    ///
    /// **A line that is nothing but tokens is left alone.** "#bug !high" would
    /// otherwise mint an untitled card wearing a label, and an untitled card is
    /// quick capture's own thing — it arrives with its title field waiting. A
    /// card whose title the grammar ate is just a card the user has to name
    /// twice.
    static func parse(
        _ input: String,
        labels: [LabelDef],
        today: CalendarDay,
        calendar: Calendar = .current,
        rejecting rejected: Set<String> = []
    ) -> CaptureParse {
        let words = input.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return .plain(input) }

        var claimed = [Bool](repeating: false, count: words.count)
        var found: [(at: Int, token: Token)] = []

        // Pass one: the sigils, anywhere in the line.
        for (index, word) in words.enumerated() {
            guard let meaning = sigil(word, labels: labels) else { continue }
            guard !rejected.contains(fold(word)) else { continue }
            claimed[index] = true
            found.append((index, Token(meaning: meaning, text: String(word))))
        }

        // Pass two: the date, and only where the line runs out.
        let open = words.indices.filter { !claimed[$0] }
        if let match = trailingDate(open.map { words[$0] }, today: today, calendar: calendar),
           !rejected.contains(fold(match.text)) {
            let claimedIndices = open.suffix(match.words)
            for index in claimedIndices { claimed[index] = true }
            found.append((claimedIndices.first ?? 0, Token(meaning: .due(match.day), text: match.text)))
        }

        guard !found.isEmpty else { return .plain(input) }

        let title = words.indices.filter { !claimed[$0] }.map { String(words[$0]) }.joined(separator: " ")
        guard !title.isEmpty else { return .plain(input) }

        // Written order, so the strip of chips reads like the line did.
        found.sort { $0.at < $1.at }
        var parse = CaptureParse(title: title, taken: found.map(\.token))
        for token in parse.taken {
            switch token.meaning {
            case .due(let day): parse.due = day
            case .priority(let priority): parse.priority = priority
            // Deduped, because `#bug #bug` is one label and `toggleLabel`
            // applied twice is none.
            case .label(let key, _): if !parse.labelKeys.contains(key) { parse.labelKeys.append(key) }
            }
        }
        return parse
    }

    // MARK: - The sigils

    /// `!high` and `#bug`, or `nil` for a word that only starts like one.
    ///
    /// Trailing punctuation is dropped before matching — people write "fix the
    /// crash #bug." and mean the label. A hyphen survives, because it is what
    /// `LabelDef.key(from:)` puts *inside* a slug: `#infra-work` is one label,
    /// not a label and a subtraction.
    private static func sigil(_ word: Substring, labels: [LabelDef]) -> Token.Meaning? {
        guard let first = word.first, first == "!" || first == "#" else { return nil }
        var payload = word.dropFirst()
        while let last = payload.last, last.isPunctuation || last.isSymbol, last != "-" {
            payload = payload.dropLast()
        }
        guard let lead = payload.first else { return nil }

        if first == "!" {
            let folded = fold(payload)
            guard let priority = Priority.allCases.first(where: {
                fold($0.rawValue) == folded || fold($0.displayName) == folded
            }) else { return nil }
            return .priority(priority)
        }

        // `#1 priority` is a rank somebody wrote, not a label called "1". A
        // digit after the hash is the one shape that is never worth guessing at.
        guard !lead.isNumber else { return nil }

        // **Only labels the board already has.** An unmatched `#thing` stays in
        // the title rather than minting a label: a typo would otherwise become
        // a permanent entry in the board's vocabulary, spelled wrong, and the
        // user would find out about it in the label manager weeks later. The
        // preview showing nothing taken is the feedback that the name is off.
        let slug = LabelDef.key(from: String(payload))
        guard let match = labels.first(where: { $0.key == slug || LabelDef.key(from: $0.name) == slug })
        else { return nil }
        return .label(key: match.key, name: match.name)
    }

    // MARK: - The date

    /// The longest date phrase the line *ends* on, and how many words it took.
    private static func trailingDate(
        _ words: [Substring], today: CalendarDay, calendar: Calendar
    ) -> (day: CalendarDay, text: String, words: Int)? {
        // Longest first: "next friday" must win over the "friday" inside it.
        for length in stride(from: min(Self.longestPhrase, words.count), through: 1, by: -1) {
            let phrase = Array(words.suffix(length))
            guard let day = date(phrase, today: today, calendar: calendar) else { continue }
            return (day, phrase.joined(separator: " "), length)
        }
        return nil
    }

    /// The longest phrase worth trying — "in 3 weeks" is the wordiest thing the
    /// grammar knows.
    private static let longestPhrase = 3

    private static func date(
        _ phrase: [Substring], today: CalendarDay, calendar: Calendar
    ) -> CalendarDay? {
        let words = phrase.map(fold)
        let vocabulary = CaptureVocabulary.self

        switch words.count {
        case 1:
            let word = words[0]
            if vocabulary.today.contains(word) { return today }
            if vocabulary.tomorrow.contains(word) { return today.adding(days: 1) }
            if let weekday = weekday(word, calendar: calendar) {
                return next(weekday, after: today, calendar: calendar)
            }
            return iso(phrase[0])
        case 2:
            // "next week", and the two ways of writing a day and a month.
            if vocabulary.next.contains(words[0]), vocabulary.week.contains(words[1]) {
                return today.adding(days: 7)
            }
            if let weekday = weekday(words[1], calendar: calendar) {
                let occurrence = next(weekday, after: today, calendar: calendar)
                // **"next friday" is the Friday after this one.** English does
                // not agree with itself here and no rule will satisfy everyone,
                // so the grammar picks the reading that makes "next" mean
                // something — and the preview names the day it landed on, which
                // is what actually settles it for the person typing.
                if vocabulary.next.contains(words[0]) { return occurrence.adding(days: 7) }
                if vocabulary.this.contains(words[0]) || vocabulary.on.contains(words[0]) {
                    return occurrence
                }
                return nil
            }
            if let day = Int(words[0]), let month = month(words[1], calendar: calendar) {
                return calendarDate(day: day, month: month, onOrAfter: today)
            }
            if let month = month(words[0], calendar: calendar), let day = Int(words[1]) {
                return calendarDate(day: day, month: month, onOrAfter: today)
            }
            return nil
        case 3:
            // "in 3 days", "in 2 weeks".
            guard vocabulary.in.contains(words[0]), let count = Int(words[1]), count > 0 else {
                return nil
            }
            if vocabulary.day.contains(words[2]) { return today.adding(days: count) }
            if vocabulary.week.contains(words[2]) { return today.adding(days: count * 7) }
            return nil
        default:
            return nil
        }
    }

    /// The next `weekday` strictly after today, so asking for "friday" *on* a
    /// Friday means the one coming rather than the one you are standing in.
    private static func next(
        _ weekday: Int, after today: CalendarDay, calendar: Calendar
    ) -> CalendarDay {
        let current = calendar.component(.weekday, from: today.date(in: calendar))
        let delta = (weekday - current + 7) % 7
        return today.adding(days: delta == 0 ? 7 : delta)
    }

    /// A day and a month, in whichever of this year or next has not gone past.
    /// Returns `nil` for a day that month does not have — "31 feb" is a typo,
    /// and `CalendarDay` would otherwise resolve it helpfully to 3 March.
    private static func calendarDate(day: Int, month: Int, onOrAfter today: CalendarDay) -> CalendarDay? {
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        let candidate = CalendarDay(year: today.year, month: month, day: day)
        guard candidate.day == day, candidate.month == month else { return nil }
        guard candidate < today else { return candidate }
        let nextYear = CalendarDay(year: today.year + 1, month: month, day: day)
        return nextYear.day == day && nextYear.month == month ? nextYear : nil
    }

    /// `2026-03-12`, the one numeric form that means the same thing in every
    /// country. `12/03` deliberately does not parse: it is March in half the
    /// world and December in the other half, and a due date silently nine
    /// months out is worse than one the grammar declined to guess at.
    private static func iso(_ word: Substring) -> CalendarDay? {
        let parts = word.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        let made = CalendarDay(year: year, month: month, day: day)
        return made.day == day && made.month == month ? made : nil
    }

    /// The calendar's own weekday number (1 is Sunday) for a name it knows.
    ///
    /// Read off `Calendar` rather than written out, which is what makes the day
    /// names work in every language the app is ever translated into without a
    /// translator supplying seven more strings. English is checked as well so a
    /// build running under another locale still understands "friday".
    private static func weekday(_ word: String, calendar: Calendar) -> Int? {
        number(word, in: [calendar.weekdaySymbols, calendar.shortWeekdaySymbols], wrappingAt: 7)
            ?? number(word, in: [CaptureVocabulary.englishWeekdays], wrappingAt: 7)
    }

    private static func month(_ word: String, calendar: Calendar) -> Int? {
        number(word, in: [calendar.monthSymbols, calendar.shortMonthSymbols], wrappingAt: 12)
            ?? number(word, in: [CaptureVocabulary.englishMonths], wrappingAt: 12)
    }

    /// The 1-based position of `word` in any of `symbols`.
    ///
    /// The wrap is what makes the English fallbacks work: those lists hold the
    /// long names and then the short ones, so "Fri" is found at index 12 and
    /// has to come back round to 6.
    private static func number(_ word: String, in symbols: [[String]], wrappingAt period: Int) -> Int? {
        for list in symbols {
            if let index = list.firstIndex(where: { fold($0) == word }) { return index % period + 1 }
        }
        return nil
    }

    // MARK: - Folding

    /// Case and accents removed, so "Friday", "friday" and a French "Février"
    /// typed without its accent all land on the same word.
    ///
    /// Fixed to `en_US_POSIX` for the same reason `LabelDef.key(from:)` folds
    /// with `lowercased()`: a Turkish device folding "I" to "ı" would stop
    /// recognising a word every other device reads fine.
    static func fold(_ text: some StringProtocol) -> String {
        String(text).folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

/// The handful of words the date grammar knows by name.
///
/// Day and month names are not here: those come off `Calendar`, already
/// translated. These eight are the connective tissue, and each is offered in
/// English *and* in whatever the running language calls it, so a build with no
/// translation still reads "tomorrow" and a translated one reads both. A
/// language needing several spellings of a word gets one here; the rest is what
/// the preview strip is for.
enum CaptureVocabulary {
    static let today = both("today", String(localized: "today", comment: "Quick-capture date word, lowercase"))
    static let tomorrow = both("tomorrow", String(localized: "tomorrow", comment: "Quick-capture date word, lowercase"))
    static let next = both("next", String(localized: "next", comment: "Quick-capture date word, as in 'next friday'"))
    static let this = both("this", String(localized: "this", comment: "Quick-capture date word, as in 'this friday'"))
    static let on = both("on", String(localized: "on", comment: "Quick-capture date word, as in 'on friday'"))
    static let week = both("week", String(localized: "week", comment: "Quick-capture date word, as in 'next week'"),
                           "weeks", String(localized: "weeks", comment: "Quick-capture date word, as in 'in 3 weeks'"))
    static let day = both("day", String(localized: "day", comment: "Quick-capture date word, as in 'in 1 day'"),
                          "days", String(localized: "days", comment: "Quick-capture date word, as in 'in 3 days'"))
    /// Swift's own `in`, hence the backticks; it is the word in "in 3 days".
    static let `in` = both("in", String(localized: "in", comment: "Quick-capture date word, as in 'in 3 days'"))

    /// The fallback day and month names, for a device whose locale is not the
    /// one the person at the keyboard is typing in.
    static let englishWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
                                  "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let englishMonths = ["January", "February", "March", "April", "May", "June", "July",
                                "August", "September", "October", "November", "December",
                                "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul",
                                "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func both(_ words: String...) -> Set<String> {
        Set(words.map(CaptureParse.fold))
    }
}
