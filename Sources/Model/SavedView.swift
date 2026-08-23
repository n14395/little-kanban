import Foundation

/// A standing filter over the whole board, shown as a flat list in place of the
/// columns.
///
/// Two of the seven are *places* rather than filters — the Inbox and the
/// Archive — and they are here anyway because what a person does with them is
/// identical: pick the row, read the list. The predicate that names each is
/// simply exact rather than approximate. The Inbox also has a second face, the
/// panel beside the board; see ``BoardStore/isInboxOpen``. The two are the same
/// cards in the same order, which is why `sort` leaves the Inbox alone.
///
/// The predicates are a product decision rather than a derivation, so they are
/// written out here in one place instead of being assembled at each call site.
/// Two of them are worth saying out loud:
///
/// - **Today includes overdue.** Work that slipped past its date must not
///   vanish from the one list a person checks every day — that is precisely the
///   list where it still needs doing.
/// - **Recently updated does not exclude Done.** It answers "what has been
///   happening", and finishing something is the most interesting thing that can
///   happen to it.
///
/// `Codable` because a later phase may remember the last view across launches
/// as a *preference*; the current selection is session state and stays out of
/// `BoardSnapshot`.
enum SavedView: String, CaseIterable, Identifiable, Codable, Sendable {
    // Inbox leads: it is where work arrives, and the rest of the list is what
    // has happened to it since. The raw values are what a `Codable` preference
    // would be written as, so the *order* is free to change and the spellings
    // are not.
    case inbox, today, upcoming, highPriority, dueThisWeek, recentlyUpdated, archive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inbox:
            Board.inboxName
        case .today:
            String(localized: "Today", comment: "Saved view: tasks due today or overdue")
        case .upcoming:
            String(localized: "Upcoming", comment: "Saved view: tasks due in the future")
        case .highPriority:
            String(localized: "High priority", comment: "Saved view: high-priority tasks")
        case .dueThisWeek:
            String(localized: "Due this week", comment: "Saved view: tasks due in the next seven days")
        case .recentlyUpdated:
            String(localized: "Recently updated", comment: "Saved view: the most recently changed tasks")
        case .archive:
            String(localized: "Archive", comment: "Saved view: tasks that have been filed away")
        }
    }

    /// The SF Symbol for the row, the empty state and the iOS "…" menu.
    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .highPriority: "exclamationmark.triangle"
        case .dueThisWeek: "calendar.badge.clock"
        case .recentlyUpdated: "clock.arrow.circlepath"
        case .archive: "archivebox"
        }
    }

    /// The views a person picks from to narrow the board. The Archive is
    /// reached from the same list but is a place things go rather than a filter
    /// over the board, so a surface that wants to draw it apart can.
    static var filters: [SavedView] { allCases.filter { $0 != .archive } }

    /// What the **phone** offers, which is everything but the Inbox: it has a
    /// tab for that and a drawer row above the boards already, and a third
    /// route to one place on the smallest screen is noise rather than
    /// convenience. The desk and the iPad list all seven, because there the
    /// Inbox row and the panel are genuinely different things — one replaces
    /// the board, the other stands beside it.
    static var phone: [SavedView] { allCases.filter { $0 != .inbox } }

    /// The phone's list without the Archive, which it draws a little apart for
    /// the reason `filters` gives.
    static var phoneFilters: [SavedView] { phone.filter { $0 != .archive } }

    /// Whether a task belongs in this view on `today`.
    ///
    /// Two exclusions are common to the table and applied before it: an archived
    /// task is only ever in the Archive, and Done is left out of everything
    /// except the Archive and Recently updated.
    ///
    /// `isDone` is asked of the caller rather than read off the task: which
    /// column counts as Done is the board's answer, not a fact about a task —
    /// see `ColumnRole`.
    /// `week` is what "due this week" is measured against — see
    /// ``WeekMeaning``. Defaulted to the rolling seven days this view has always
    /// meant, so a caller with no opinion, and every test, reads as before.
    func matches(
        _ task: TaskItem, today: CalendarDay, isDone: Bool, week: WeekMeaning = .fallback
    ) -> Bool {
        guard task.isArchived == (self == .archive) else { return false }
        guard !excludesDone || !isDone else { return false }

        switch self {
        case .inbox:
            // A place rather than a predicate over a board — the same way the
            // Archive is — and the predicate that names it is exact: a card is
            // *in* the Inbox by being on no board at all.
            return task.isUnfiled
        case .today:
            guard let due = task.due else { return false }
            switch DueDate.urgency(due, from: today) {
            case .today, .overdue: return true
            case .soon, .later: return false
            }
        case .upcoming:
            guard let due = task.due else { return false }
            return DueDate.daysAway(due, from: today) > 0
        case .highPriority:
            // **At least** High, not exactly High. The view is named for its
            // floor rather than for one case, so a priority added above it
            // belongs here by arriving rather than by an edit — which is the
            // whole reason `Priority` is `Comparable`.
            return task.priority >= .high
        case .dueThisWeek:
            guard let due = task.due else { return false }
            return week.containsAhead(due, from: today)
        case .recentlyUpdated, .archive:
            // Both are defined entirely by their ordering and their cap.
            return true
        }
    }

    /// Ordering that overrides the board's manual card order, or `nil` to keep it.
    ///
    /// Only the two time-ordered views have one. Everywhere else the order the
    /// user dragged their cards into is the order they expect to read them in,
    /// and re-sorting a filtered board would throw that away for nothing.
    var sort: ((TaskItem, TaskItem) -> Bool)? {
        switch self {
        case .recentlyUpdated:
            { $0.updatedAt > $1.updatedAt }
        case .archive:
            // Newest filing first. `archivedAt` is what the view is selected on,
            // so it is never nil here; `.distantPast` is only a total-order
            // fallback rather than a case that can arise.
            { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
        case .inbox, .today, .upcoming, .highPriority, .dueThisWeek:
            // The Inbox keeps the order cards were dragged into, which is the
            // order the panel draws them in. Two lists of the same cards that
            // disagreed about their order would be a bug people could see.
            nil
        }
    }

    /// How many rows the view shows at most. "Recently updated" is a glance at
    /// what is moving, not a second copy of the board.
    var limit: Int? { self == .recentlyUpdated ? 20 : nil }

    /// Whether the Done column is left out. Recently updated keeps it because
    /// completing something is a change worth seeing; the Archive keeps it
    /// because most of what is filed away was finished first.
    private var excludesDone: Bool {
        switch self {
        case .inbox, .today, .upcoming, .highPriority, .dueThisWeek: true
        case .recentlyUpdated, .archive: false
        }
    }
}
