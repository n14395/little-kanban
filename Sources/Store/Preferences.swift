// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

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

// MARK: - What a new task is due

/// The due date a card arrives with.
///
/// `none` is the default and stays it: a date nobody chose is a date that goes
/// red on its own, and an overdue card that was never meant to have a deadline
/// teaches people to ignore the colour.
enum DefaultDueDate: String, CaseIterable, Identifiable, Sendable {
    case none, today, tomorrow

    var id: String { rawValue }
    static let storageKey = "LittleKanbanDefaultDueDate"
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
    static let storageKey = "LittleKanbanAutoArchiveDone"
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
    static let storageKey = "LittleKanbanTrashRetention"
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
/// Ten was the number `backupNow(keeping:)` defaulted to; twenty-five is the
/// one the app starts on, because a backup is cheap next to losing a board. The
/// cost of the high end is still real disk on a big board — which is the reason
/// to let the person paying it choose.
enum BackupsKept: String, CaseIterable, Identifiable, Sendable {
    case few, ten, many, fifty, hundred

    var id: String { rawValue }
    static let storageKey = "LittleKanbanBackupsKept"
    static let fallback = BackupsKept.many

    var count: Int {
        switch self {
        case .few: 5
        case .ten: 10
        case .many: 25
        case .fifty: 50
        case .hundred: 100
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
    static let storageKey = "LittleKanbanCardDensity"
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

/// The chime a card makes on its way into Done — and, chosen separately, the
/// one a ticked sub-task makes.
///
/// **One vocabulary, two choices.** A sub-task could have had a list of its own
/// and there is nothing to put on it: the fifteen here are already every
/// "something small was struck" this app has, and a second set would either
/// repeat them or be worse ones. What the two settings own is which of the
/// fifteen each plays, and the defaults are picked to be told apart — the card's
/// two rising wooden notes against the sub-task's one round tine — because the
/// point of the sub-task sound is that it is *not* the card's.
///
/// Bundled sounds rather than the system's: the system has no cross-platform
/// "completion" sound to name — the Mac's fourteen alert sounds are AppKit's
/// and macOS-only, the phone's `UISounds` are undocumented numeric IDs — so
/// naming either would mean a different picker on each platform. A bundled
/// file is the same chime on the Mac and the phone. Each case names a file in
/// the bundle's `Sounds/` folder, and `CompletionFeedbackTests` holds the two
/// lists together.
///
/// **They are all one thing being struck**, which is why they are synthesised
/// (`Tools/make-chimes`) rather than collected: a set assembled from fifteen
/// sources is fifteen recording chains, and the picker becomes a comparison of
/// room tone. Here every sound is a partial series with a mallet on the front —
/// a bar at roughly 1 : 3.98 : 10.65, a bell at 1 : 2.76 : 5.4, glass between
/// them — levelled against the others by RMS rather than by peak, so choosing
/// one is a choice about character and not about which is loudest.
///
/// **The order is the order the picker shows**, and it runs by material rather
/// than alphabetically: wood, then glass and bell, then tine, then plucked,
/// then the two short dry ones. Somebody scrolling for "warmer" is scrolling in
/// one direction, which an alphabetical list cannot offer.
enum CompletionSound: String, CaseIterable, Identifiable, Sendable {
    case barThird, barLow, kalimba, wood, woodKnock
    case glassTriad, bellSoft, bowl, chordDone
    case tineWarm, tineSixth
    case pluckNylon, pluckPair
    case pop, popSoft

    var id: String { rawValue }
    static let storageKey = "LittleKanbanCompletionSound"
    /// Where the sub-task's choice is kept. A key of its own rather than a
    /// shared one: the two are set from two rows and a person who wants the
    /// bell for a card and the tine for a sub-task is asking the ordinary
    /// question of a pair of pickers.
    static let subtaskStorageKey = "LittleKanbanSubtaskSound"

    /// The two rising wooden notes, which is what the old default `chime` was
    /// and what an unreadable stored value should still land on. `choice` reads
    /// a name this enum no longer has as no answer at all, so anyone who had
    /// `chime`, `ding` or `glass` set when those went away arrives here — which
    /// is the nearest of the fifteen to what they had chosen.
    static let fallback = CompletionSound.barThird

    /// What a ticked sub-task sounds like out of the box: one round
    /// electric-piano note. Shorter and plainer than ``fallback``'s pair, and
    /// far enough from it that the two are told apart without being read — a
    /// sub-task is a step and a card is the thing the steps were for, and the
    /// sounds should say which just happened.
    static let subtaskFallback = CompletionSound.tineWarm

    /// `completion-barThird`, under `Sounds/` with a `.caf` extension.
    var resourceName: String { "completion-\(rawValue)" }

    var label: String {
        switch self {
        case .barThird: String(localized: "Marimba", comment: "Completion sound: two wooden notes rising a third")
        case .barLow: String(localized: "Low Bar", comment: "Completion sound: one low wooden bar with its octave")
        case .kalimba: String(localized: "Kalimba", comment: "Completion sound: two thumb-piano notes")
        case .wood: String(localized: "Wood", comment: "Completion sound: a soft marimba knock")
        case .woodKnock: String(localized: "Knock", comment: "Completion sound: a dry woodblock knock")
        case .glassTriad: String(localized: "Glass", comment: "Completion sound: three delicate high notes")
        case .bellSoft: String(localized: "Bell", comment: "Completion sound: a small bell with a slow tail")
        case .bowl: String(localized: "Bowl", comment: "Completion sound: a struck bowl with shimmer")
        case .chordDone: String(localized: "Chord", comment: "Completion sound: a major triad struck at once")
        case .tineWarm: String(localized: "Tine", comment: "Completion sound: one round electric-piano note")
        case .tineSixth: String(localized: "Tine Pair", comment: "Completion sound: two electric-piano notes rising a sixth")
        case .pluckNylon: String(localized: "Pluck", comment: "Completion sound: one nylon-string pluck")
        case .pluckPair: String(localized: "Pluck Pair", comment: "Completion sound: two plucks rising a fifth")
        case .pop: String(localized: "Pop", comment: "Completion sound: a short low pluck")
        case .popSoft: String(localized: "Blip", comment: "Completion sound: a falling blip")
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
    static let storageKey = "LittleKanbanWeekMeaning"
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
    static let resumeKey = "LittleKanbanResumeLastPlace"
    /// What was on screen, written on change and read once at launch.
    static let lastSurfaceKey = "LittleKanbanLastSurface"
    /// Bring the Inbox panel up with the board.
    static let inboxAtLaunchKey = "LittleKanbanOpenInboxAtLaunch"
    /// Draw the tick in a card's trailing gutter.
    ///
    /// **Off by default.** The circle is the fastest way to finish something
    /// and the easiest thing to hit by accident on a board being dragged
    /// around, and which of those matters more is not a question this app can
    /// answer for somebody — which is why it is a preference rather than a
    /// decision. It arrives closed because the accident is the expensive half:
    /// a card ticked by a thumb that meant to pick it up is a state change with
    /// a chime and an auto-archive behind it, where a card that cannot be
    /// ticked from the board costs one press of the switch below. Off, the
    /// gutter closes up and the card's text starts at its own margin;
    /// completing a card is the context menu, ⌘↩, and the tick beside the title
    /// in the detail panel, which is drawn whatever this says.
    static let cardTickKey = "LittleKanbanShowsCardTick"
    /// Play the completion chime when a card reaches Done. On by default: the
    /// sound is the point of the feature, and the switch is for the person it
    /// grates on — see ``CompletionSound`` for which chime.
    static let completionSoundKey = "LittleKanbanPlaysCompletionSound"
    /// Play a chime when a sub-task is ticked. On by default for the reason
    /// above, and it is the louder half of that bargain: a checklist is ticked
    /// far more often than a card is finished, so this is the switch more
    /// likely to be reached for. It arrives open anyway, because a sound
    /// nobody hears is a setting nobody knows to look for — and the sub-task
    /// tick already had a haptic, which is the same feedback said quietly.
    /// Only the edge *into* done makes it; un-ticking is silent.
    static let subtaskSoundKey = "LittleKanbanPlaysSubtaskSound"
    /// Read `#bug`, `!high` and a trailing "next friday" out of a title as it is
    /// typed. On by default, and the switch exists for one specific person: the
    /// one whose cards are called things like "#3 rewrite" and who would rather
    /// the field left their words alone. Everyone else has the preview strip,
    /// which hands any single token back without a trip to Settings — see
    /// ``CaptureParse``.
    static let interpretsCaptureKey = "LittleKanbanInterpretsCapture"
    /// Keep the ⌃⌘N status item in the menu bar. On by default, because it is
    /// the app's one route in from another app.
    static let menuBarExtraKey = "LittleKanbanShowsMenuBarExtra"
    /// Start the app when the Mac is logged in to.
    static let launchAtLoginKey = "LittleKanbanLaunchAtLogin"
    /// Which subject the desk's Settings window was last left on.
    ///
    /// macOS only, and stored rather than held in `@State` because that is what
    /// the native `TabView` used to do for free: the Settings scene is torn down
    /// when its window closes, so somebody who opens Settings, changes a backup
    /// setting, closes it and opens it again to change another would otherwise
    /// land back on General every time. The sheet on iOS deliberately does not —
    /// see ``SettingsTab`` — because it is raised from a row that has just named
    /// the subject.
    static let settingsTabKey = "LittleKanbanSettingsTab"

    /// Which of the ten grounds the app wears — the design document's own
    /// reference, `4a` through `4j`. See ``AppIcon``.
    static let appIconKey = "LittleKanbanAppIcon"
    /// Wear the icon that matches the theme instead, whichever theme that turns
    /// out to be. Off by default: the icon is the app's face in a Dock full of
    /// other apps' faces, and one that changed the first time the system went
    /// dark would be a surprise nobody asked for.
    static let appIconFollowsThemeKey = "LittleKanbanAppIconFollowsTheme"
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
    static var subtaskSound: CompletionSound {
        choice(CompletionSound.self, key: CompletionSound.subtaskStorageKey, fallback: .subtaskFallback)
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
    static var showsCardTick: Bool { flag(cardTickKey) }
    static var playsCompletionSound: Bool { flag(completionSoundKey, fallback: true) }
    static var playsSubtaskSound: Bool { flag(subtaskSoundKey, fallback: true) }
    static var interpretsCapture: Bool { flag(interpretsCaptureKey, fallback: true) }
    static var showsMenuBarExtra: Bool { flag(menuBarExtraKey, fallback: true) }
    static var launchesAtLogin: Bool { flag(launchAtLoginKey) }
    static var appIconFollowsTheme: Bool { flag(appIconFollowsThemeKey) }

    /// The light/dark override. Read here as well as through `@AppStorage`
    /// because the widgets need it and a widget cannot see the app's
    /// environment: it travels to them inside ``WidgetDigest``, and what puts
    /// it there is a plain read rather than a view.
    static var appearance: AppAppearance {
        choice(AppAppearance.self, key: AppAppearance.storageKey, fallback: .system)
    }

    /// The stored ground, or the one the app ships wearing. Not ``choice(_:key:fallback:)``
    /// — the ten are data rather than an enum, so the lookup is
    /// ``AppIcon/gradient(_:)`` and an id this build has never heard of falls
    /// back the same way a stale theme id does.
    static var appIcon: AppIconGradient {
        AppIcon.gradient(defaults.string(forKey: appIconKey) ?? "") ?? AppIcon.fallback
    }

    /// Both switches as the one value the resolver takes.
    static var appIconSelection: AppIconSelection {
        AppIconSelection(gradientID: appIcon.id, followsTheme: appIconFollowsTheme)
    }
}
