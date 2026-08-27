import Foundation

/// The preferences added in one go, in one place.
///
/// The rule they follow is `PreferenceTests`': **`BoardSnapshot` is the board —
/// what a second machine restoring from an export would need. Everything else
/// belongs in `UserDefaults`.** None of these is board data: they describe the
/// sitting rather than the work, and a board carried to another machine should
/// arrive without them.
///
/// Gathered rather than scattered, which is a departure from the four that came
/// before — the appearance, the sort order, the reminders and the sync switch
/// each own their key beside the thing they configure. That is the better shape
/// for *one* preference: the key sits where a reader is already looking. It is
/// the worse shape for a dozen arriving together, where the question a reader
/// has is "what can be set, and what is the default" and the answer would be
/// spread over eight files. The four that act on their own changes stay where
/// they are — `NotificationScheduler` has to reschedule when its keys move, and
/// a copy here would set the preference and reschedule nothing.
///
/// Each one is an enum rather than a raw number so the default is written down
/// once, the settings row has a label to draw, and a value that has gone out of
/// range cannot be stored. `nil`-able "off" states are spelled as cases —
/// `AutoArchive.never`, `WeekMeaning.rollingSevenDays` — because a preference
/// whose off state is an absent key reads differently on a fresh install than
/// after it has been turned off and on again.
enum Preferences {}

// MARK: - Where a new task lands

/// Where ⌘N, the toolbar's New Task button and the "+" put a card when nothing
/// on screen says otherwise.
///
/// The board's landing column is the default because the board is what is in
/// front of you; the Inbox is the choice for a capture habit, where a new
/// thought is filed later rather than placed now.
enum NewTaskDestination: String, CaseIterable, Identifiable, Sendable {
    /// The landing column of the board on screen, falling back to the Inbox
    /// when there is no board left to land on.
    case board
    /// Always the Inbox, whatever is on screen.
    case inbox

    var id: String { rawValue }
    static let storageKey = "SimpleKanbanNewTaskDestination"
    static let fallback = NewTaskDestination.board

    var label: String {
        switch self {
        case .board:
            String(localized: "The board I'm on", comment: "Setting: new tasks go to the current board")
        case .inbox:
            Board.inboxName
        }
    }
}

// MARK: - What a new task is due

/// The due date a card arrives with.
///
/// `none` is the default and stays it: a date nobody chose is a date that goes
/// red on its own, and an overdue card that was never meant to have a deadline
/// teaches people to ignore the colour.
enum DefaultDueDate: String, CaseIterable, Identifiable, Sendable {
    case none, today, tomorrow

    var id: String { rawValue }
    static let storageKey = "SimpleKanbanDefaultDueDate"
    static let fallback = DefaultDueDate.none

    var label: String {
        switch self {
        case .none: String(localized: "No date", comment: "Setting: new tasks have no due date")
        case .today: String(localized: "Today", comment: "Setting: new tasks are due today")
        case .tomorrow: String(localized: "Tomorrow", comment: "Setting: new tasks are due tomorrow")
        }
    }

    /// The day a card made on `today` starts with, or `nil` for no date.
    /// Asked of the caller rather than read off the clock, for the reason
    /// `DayClock` exists: nothing on the due-date path reads the time itself.
    func day(from today: CalendarDay) -> CalendarDay? {
        switch self {
        case .none: nil
        case .today: today
        case .tomorrow: today.adding(days: 1)
        }
    }
}

// MARK: - What happens to finished work

/// How long a card sits in Done before the Archive takes it.
///
/// Done is the one column that only grows. Everything that reaches it stays
/// until somebody archives it by hand, and the column that is meant to show
/// what shipped ends up showing what shipped since the board was made.
enum AutoArchive: String, CaseIterable, Identifiable, Sendable {
    case never, week, fortnight, month

    var id: String { rawValue }
    static let storageKey = "SimpleKanbanAutoArchiveDone"
    static let fallback = AutoArchive.never

    /// How long a card may sit in Done, or `nil` for "as long as it likes".
    var days: Int? {
        switch self {
        case .never: nil
        case .week: 7
        case .fortnight: 14
        case .month: 30
        }
    }

    var label: String {
        switch self {
        case .never: String(localized: "Never", comment: "Setting: finished cards are never archived")
        case .week: String(localized: "After a week", comment: "Setting: archive finished cards after 7 days")
        case .fortnight: String(localized: "After two weeks", comment: "Setting: archive finished cards after 14 days")
        case .month: String(localized: "After a month", comment: "Setting: archive finished cards after 30 days")
        }
    }
}

/// How long the Trash keeps what is thrown into it.
///
/// Thirty days was the number written into `TrashedItem` and is still the
/// default. It is a preference because the two ends of the range want different
/// things: a shared board wants a long rope, a private one wants the disk back.
enum TrashRetention: String, CaseIterable, Identifiable, Sendable {
    case week, month, quarter

    var id: String { rawValue }
    static let storageKey = "SimpleKanbanTrashRetention"
    static let fallback = TrashRetention.month

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    var label: String {
        switch self {
        case .week: String(localized: "A week", comment: "Setting: the trash keeps items for 7 days")
        case .month: String(localized: "A month", comment: "Setting: the trash keeps items for 30 days")
        case .quarter: String(localized: "Three months", comment: "Setting: the trash keeps items for 90 days")
        }
    }
}

/// How many copies of the board file to keep beside it.
///
/// Ten was the number `backupNow(keeping:)` defaulted to. A backup is a whole
/// board document, so the cost of the high end is real disk on a big board —
/// which is the reason to let the person paying it choose.
enum BackupsKept: String, CaseIterable, Identifiable, Sendable {
    case few, ten, many

    var id: String { rawValue }
    static let storageKey = "SimpleKanbanBackupsKept"
    static let fallback = BackupsKept.ten

    var count: Int {
        switch self {
        case .few: 5
        case .ten: 10
        case .many: 25
        }
    }

    var label: String { String(count.formatted()) }
}

// MARK: - How much a card shows

/// How much of a card the board draws.
///
/// Compact drops the description snippet and the meta chips, which is most of a
/// card's height. It is not a smaller card: the type stays the size it is, so
/// the row is still readable and still a 44pt target under a finger.
enum CardDensity: String, CaseIterable, Identifiable, Sendable {
    case comfortable, compact

    var id: String { rawValue }
    static let storageKey = "SimpleKanbanCardDensity"
    static let fallback = CardDensity.comfortable

    var showsDetail: Bool { self == .comfortable }

    var label: String {
        switch self {
        case .comfortable: String(localized: "Comfortable", comment: "Setting: cards show their description and chips")
        case .compact: String(localized: "Compact", comment: "Setting: cards show their title only")
        }
    }
}

// MARK: - What finishing sounds like

/// The chime a card makes on its way into Done.
///
/// Five bundled sounds rather than the system's: the system has no
/// cross-platform "completion" sound to name, and a bundled file is the same
/// chime on the Mac and the phone. Each case names a file in the bundle's
/// `Sounds/` folder — `PackagingTests` holds the two lists together.
enum CompletionSound: String, CaseIterable, Identifiable, Sendable {
    case chime, ding, pop, wood, glass

    var id: String { rawValue }
    static let storageKey = "SimpleKanbanCompletionSound"
    static let fallback = CompletionSound.chime

    /// `completion-chime`, under `Sounds/` with a `.caf` extension.
    var resourceName: String { "completion-\(rawValue)" }

    var label: String {
        switch self {
        case .chime: String(localized: "Chime", comment: "Completion sound: two soft rising notes")
        case .ding: String(localized: "Ding", comment: "Completion sound: a single bell")
        case .pop: String(localized: "Pop", comment: "Completion sound: a short low pluck")
        case .wood: String(localized: "Wood", comment: "Completion sound: a soft marimba knock")
        case .glass: String(localized: "Glass", comment: "Completion sound: three delicate high notes")
        }
    }
}

// MARK: - What "this week" means

/// What the app means by a week.
///
/// The app has always counted a rolling seven days — "due this week" is *within
/// seven days*, not *before Sunday* — and that is still the default, because it
/// is the reading that never changes meaning halfway through a Friday. The two
/// calendar options are for people who plan in weeks: with one of them chosen,
/// "Due this week" ends when the week does, and a card due next Monday drops
/// out of it on Sunday night rather than staying for seven more days.
enum WeekMeaning: String, CaseIterable, Identifiable, Sendable {
    case rollingSevenDays, monday, sunday

    var id: String { rawValue }
    static let storageKey = "SimpleKanbanWeekMeaning"
    static let fallback = WeekMeaning.rollingSevenDays

    /// `Calendar`'s numbering, where Sunday is 1 — `nil` when a week is not a
    /// calendar week at all.
    var firstWeekday: Int? {
        switch self {
        case .rollingSevenDays: nil
        case .monday: 2
        case .sunday: 1
        }
    }

    var label: String {
        switch self {
        case .rollingSevenDays:
            String(localized: "The next seven days", comment: "Setting: a week is a rolling seven days")
        case .monday:
            String(localized: "Monday to Sunday", comment: "Setting: a week starts on Monday")
        case .sunday:
            String(localized: "Sunday to Saturday", comment: "Setting: a week starts on Sunday")
        }
    }

    /// Whether `day` falls in the week `today` is in, looking **forwards** —
    /// what "due this week" asks.
    ///
    /// Rolling counts days: today through the sixth day after it, which is what
    /// the app has always meant and what never changes meaning halfway through
    /// a Friday. A calendar week ends when the week ends, so a card due next
    /// Monday leaves the view on Sunday night rather than sitting in it for
    /// another seven days.
    func containsAhead(_ day: CalendarDay, from today: CalendarDay, in calendar: Calendar = .current) -> Bool {
        let away = day - today
        guard let first = firstWeekday else { return (0...6).contains(away) }
        guard away >= 0 else { return false }
        return away <= Self.daysLeftInWeek(from: today, firstWeekday: first, in: calendar)
    }

    /// The same week looking **backwards**, which is what the weekly meter
    /// counts: the last seven days, or everything since the week began.
    func containsBehind(_ day: CalendarDay, from today: CalendarDay, in calendar: Calendar = .current) -> Bool {
        let ago = today - day
        guard let first = firstWeekday else { return (0...6).contains(ago) }
        guard ago >= 0 else { return false }
        let elapsed = 6 - Self.daysLeftInWeek(from: today, firstWeekday: first, in: calendar)
        return ago <= elapsed
    }

    /// How many days after `today` the week still has in it, 0 on its last day.
    private static func daysLeftInWeek(
        from today: CalendarDay, firstWeekday: Int, in calendar: Calendar
    ) -> Int {
        var week = calendar
        week.firstWeekday = firstWeekday
        let weekday = week.component(.weekday, from: today.date(in: week))
        // `weekday` is 1...7 with Sunday 1; how far into the week that is
        // depends on which day the week is said to start on.
        let into = (weekday - firstWeekday + 7) % 7
        return 6 - into
    }
}

// MARK: - Switches

extension Preferences {
    /// Reopen on the board or view that was on screen at the last quit.
    ///
    /// Off by default: the first board is a stable place to land, and a saved
    /// view restored without warning looks like a board that has lost its
    /// cards. `SavedView` has been `Codable` since it was written, for this.
    static let resumeKey = "SimpleKanbanResumeLastPlace"
    /// What was on screen, written on change and read once at launch.
    static let lastSurfaceKey = "SimpleKanbanLastSurface"
    /// Bring the Inbox panel up with the board.
    static let inboxAtLaunchKey = "SimpleKanbanOpenInboxAtLaunch"
    /// Draw the tick in a card's leading gutter.
    ///
    /// **On by default, and the only one of these switches whose off state
    /// takes a verb off a surface** — which is why it is a preference rather
    /// than a decision. The circle is the fastest way to finish something and
    /// the easiest thing to hit by accident on a board being dragged around,
    /// and which of those matters more is not a question this app can answer
    /// for somebody. Turned off, the gutter closes up and the card's text
    /// starts at its own margin; completing a card is then the context menu,
    /// ⌘↩, and the tick beside the title in the detail panel, which is drawn
    /// whatever this says.
    static let cardTickKey = "SimpleKanbanShowsCardTick"
    /// Play the completion chime when a card reaches Done. On by default: the
    /// sound is the point of the feature, and the switch is for the person it
    /// grates on — see ``CompletionSound`` for which chime.
    static let completionSoundKey = "SimpleKanbanPlaysCompletionSound"
    /// Keep the ⌃⌘N status item in the menu bar. On by default, because it is
    /// the app's one route in from another app.
    static let menuBarExtraKey = "SimpleKanbanShowsMenuBarExtra"
    /// Start the app when the Mac is logged in to.
    static let launchAtLoginKey = "SimpleKanbanLaunchAtLogin"
}

// MARK: - Reading them

extension Preferences {
    /// The defaults these are read from.
    ///
    /// **Read at launch and when a switch is flipped, not at every use.** What
    /// a preference *changes* is carried on `BoardStore` — `trashRetention`,
    /// `defaultDueDate`, `weekMeaning` — so the hot paths never come back here
    /// and, more to the point, a test can set one without reaching into state
    /// every other suite is reading at the same moment. Swift Testing runs
    /// suites in parallel; a global swapped for the length of one test is a
    /// global the rest of them read mid-swap.
    nonisolated(unsafe) private(set) static var defaults: UserDefaults = .standard

    /// Reads these from `defaults` for the length of `body`, for a test that is
    /// checking the reading itself rather than what it changes.
    ///
    /// `@MainActor` and nothing else: the swap is only safe because everything
    /// that reads a preference does so on the main actor, so a main-actor
    /// function cannot be interleaved with one.
    @MainActor
    static func reading<Result>(_ suite: UserDefaults, _ body: () throws -> Result) rethrows -> Result {
        let previous = defaults
        defaults = suite
        defer { defaults = previous }
        return try body()
    }

    /// A stored case, or the fallback — which covers both "never set" and "set
    /// to something this build no longer has a case for", the second of which
    /// is what a downgrade looks like.
    static func choice<Value: RawRepresentable & Sendable>(
        _ type: Value.Type, key: String, fallback: Value
    ) -> Value where Value.RawValue == String {
        guard let raw = defaults.string(forKey: key) else { return fallback }
        return Value(rawValue: raw) ?? fallback
    }

    /// A switch. `object(forKey:)` first, because `bool(forKey:)` cannot tell
    /// "off" from "never set" and two of these default to on.
    static func flag(_ key: String, fallback: Bool = false) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    static var newTaskDestination: NewTaskDestination {
        choice(NewTaskDestination.self, key: NewTaskDestination.storageKey, fallback: .fallback)
    }
    static var defaultDueDate: DefaultDueDate {
        choice(DefaultDueDate.self, key: DefaultDueDate.storageKey, fallback: .fallback)
    }
    static var autoArchive: AutoArchive {
        choice(AutoArchive.self, key: AutoArchive.storageKey, fallback: .fallback)
    }
    static var trashRetention: TrashRetention {
        choice(TrashRetention.self, key: TrashRetention.storageKey, fallback: .fallback)
    }
    static var backupsKept: BackupsKept {
        choice(BackupsKept.self, key: BackupsKept.storageKey, fallback: .fallback)
    }
    static var cardDensity: CardDensity {
        choice(CardDensity.self, key: CardDensity.storageKey, fallback: .fallback)
    }
    static var weekMeaning: WeekMeaning {
        choice(WeekMeaning.self, key: WeekMeaning.storageKey, fallback: .fallback)
    }
    static var completionSound: CompletionSound {
        choice(CompletionSound.self, key: CompletionSound.storageKey, fallback: .fallback)
    }

    /// Writes down the view on screen, for ``resumesLastPlace`` to read at the
    /// next launch. Written whatever the setting says: turning it on should
    /// resume where you were, not where you were when you turned it on.
    @MainActor
    static func remember(surface name: String?) {
        if let name {
            defaults.set(name, forKey: lastSurfaceKey)
        } else {
            defaults.removeObject(forKey: lastSurfaceKey)
        }
    }

    static var resumesLastPlace: Bool { flag(resumeKey) }
    static var opensInboxAtLaunch: Bool { flag(inboxAtLaunchKey) }
    static var showsCardTick: Bool { flag(cardTickKey, fallback: true) }
    static var playsCompletionSound: Bool { flag(completionSoundKey, fallback: true) }
    static var showsMenuBarExtra: Bool { flag(menuBarExtraKey, fallback: true) }
    static var launchesAtLogin: Bool { flag(launchAtLoginKey) }
}
