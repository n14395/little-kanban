import Foundation

/// How a view orders what it gathered.
///
/// `manual` is the board's own order — the one the user dragged their cards
/// into — and is what five of the seven seeded views use, because re-sorting a
/// filtered board throws that away for nothing. The rest are here because a view
/// that gathers from everywhere has no manual order to inherit: *Recently
/// updated* is defined entirely by its ordering and its cap.
enum ViewSort: String, CaseIterable, Codable, Sendable, Identifiable {
    case manual, dueSoonest, priorityHighest, recentlyUpdated, recentlyCreated, recentlyArchived, title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: String(localized: "Board order", comment: "How a view sorts its cards")
        case .dueSoonest: String(localized: "Due soonest", comment: "How a view sorts its cards")
        case .priorityHighest: String(localized: "Priority", comment: "How a view sorts its cards")
        case .recentlyUpdated: String(localized: "Recently updated", comment: "How a view sorts its cards")
        case .recentlyCreated: String(localized: "Recently created", comment: "How a view sorts its cards")
        case .recentlyArchived: String(localized: "Recently archived", comment: "How a view sorts its cards")
        case .title: String(localized: "Title", comment: "How a view sorts its cards")
        }
    }

    /// `nil` keeps the board's order — the comparator is what
    /// `BoardStore.stableSorted` is handed, and handing it one that always
    /// returned false would still cost a sort.
    ///
    /// Written with explicit `return`s and a named type rather than as an
    /// expression switch: seven closure literals in one implicit-return switch
    /// is where the type checker gives up and asks for a bug report instead of
    /// a diagnostic.
    typealias Comparator = (TaskItem, TaskItem) -> Bool

    var comparator: Comparator? {
        switch self {
        case .manual:
            return nil
        case .dueSoonest:
            // **No due date sorts last**, and it takes a switch to say so:
            // `CalendarDay` has no `.distantFuture` to stand in for the absence,
            // and a card with no date is not the most urgent thing on the board
            // — which is what the earliest possible day would make it.
            return { (lhs: TaskItem, rhs: TaskItem) in
                switch (lhs.due, rhs.due) {
                case (let left?, let right?): return left < right
                case (nil, .some): return false
                case (.some, nil): return true
                case (nil, nil): return false
                }
            }
        case .priorityHighest:
            // `Priority.allCases` runs loudest first and `Comparable` follows
            // it, so "highest" is simply greater-than.
            return { (lhs: TaskItem, rhs: TaskItem) in lhs.priority > rhs.priority }
        case .recentlyUpdated:
            return { (lhs: TaskItem, rhs: TaskItem) in lhs.updatedAt > rhs.updatedAt }
        case .recentlyCreated:
            return { (lhs: TaskItem, rhs: TaskItem) in lhs.createdAt > rhs.createdAt }
        case .recentlyArchived:
            // `.distantPast` is a total-order fallback rather than a case that
            // arises: a view sorted this way is one selecting archived cards.
            return { (lhs: TaskItem, rhs: TaskItem) in
                (lhs.archivedAt ?? .distantPast) > (rhs.archivedAt ?? .distantPast)
            }
        case .title:
            return { (lhs: TaskItem, rhs: TaskItem) in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

/// A standing filter over the whole board, shown in place of the columns.
///
/// **It used to be an enum of seven, and the seven are now data.** Everything a
/// view is — its name, its glyph, the rule it gathers by, how it sorts and how
/// much it shows — is editable, and the built-ins are seeded rows in the same
/// list rather than a separate kind of thing. What that buys is one code path:
/// the sidebar, the counts, the empty states and the surface all work on a
/// `SavedView` without asking whether anybody wrote it.
///
/// Two of the seeded seven are *places* rather than filters — the Inbox and the
/// Archive — and they are here anyway because what a person does with them is
/// identical: pick the row, read the list. Their rules are simply exact. The
/// Inbox also has a second face, the panel beside the board; see
/// ``BoardStore/isInboxOpen``.
///
/// **The two implicit exclusions became explicit.** The old enum quietly dropped
/// archived cards from everything but the Archive, and Done from everything but
/// two — rules nothing on screen stated. A seeded view now carries them as
/// criteria the user can see and delete, which is the whole point of the change:
/// a view does what it says it does.
struct SavedView: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// The SF Symbol for the row, the empty state and the iOS "…" menu.
    var symbol: String = SavedView.defaultSymbol
    var rule: ViewRule = .empty
    var sort: ViewSort = .manual
    /// How many rows the view shows at most, or `nil` for all of them. *Recently
    /// updated* is a glance at what is moving, not a second copy of the board.
    var limit: Int?
    /// Which built-in this was seeded from, if any.
    ///
    /// Not a licence — a seeded view is editable and deletable like any other —
    /// but the empty states were written one per view and a hand-written
    /// sentence beats a generated one. A view the user made, or a seeded one
    /// they renamed past recognition, gets the generic copy.
    var preset: Preset?

    /// The seven the app has always had. Raw values are the old enum's, so a v9
    /// file's `lastSurface` string still resolves after migration.
    enum Preset: String, CaseIterable, Codable, Sendable {
        case inbox, today, upcoming, highPriority, dueThisWeek, recentlyUpdated, archive
    }

    /// What the row and the header say.
    var label: String { name }

    /// Whether this view still is what it was seeded as. The empty-state copy
    /// leans on it: "Nothing due today" under a view somebody has rewritten to
    /// gather next month is a sentence about a view that no longer exists.
    var isUnchangedPreset: Bool {
        guard let preset else { return false }
        let seeded = SavedView.seeded(preset)
        return seeded.rule.isEquivalent(to: rule) && seeded.sort == sort && seeded.limit == limit
    }

    // MARK: Membership

    /// Whether a task belongs in this view.
    ///
    /// `isDone` is asked of the caller rather than read off the task: which
    /// column counts as Done is the board's answer, not a fact about a task —
    /// see ``Board/doneColumn``.
    func matches(
        _ task: TaskItem, today: CalendarDay, isDone: Bool, week: WeekMeaning = .fallback,
        now: Date = .now
    ) -> Bool {
        rule.matches(task, in: ViewRule.Context(today: today, week: week, now: now, isDone: isDone))
    }

    // MARK: The seeded seven

    /// Fixed ids, because a seeded view is referred to from outside the file:
    /// `Preferences` remembers the last surface, and a migration that minted a
    /// fresh id every time it ran would lose that on every launch.
    static func id(of preset: Preset) -> UUID {
        switch preset {
        case .inbox: UUID(uuidString: "5A7E0001-0000-4000-8000-000000000001")!
        case .today: UUID(uuidString: "5A7E0001-0000-4000-8000-000000000002")!
        case .upcoming: UUID(uuidString: "5A7E0001-0000-4000-8000-000000000003")!
        case .highPriority: UUID(uuidString: "5A7E0001-0000-4000-8000-000000000004")!
        case .dueThisWeek: UUID(uuidString: "5A7E0001-0000-4000-8000-000000000005")!
        case .recentlyUpdated: UUID(uuidString: "5A7E0001-0000-4000-8000-000000000006")!
        case .archive: UUID(uuidString: "5A7E0001-0000-4000-8000-000000000007")!
        }
    }

    /// **The seven, written as rules — which is the proof the vocabulary is
    /// complete.** Every one of them is expressible in criteria the editor
    /// offers, and `SavedViewSeedTests` checks each against the enum's old
    /// predicate over a board built to exercise it.
    static func seeded(_ preset: Preset) -> SavedView {
        switch preset {
        case .inbox:
            SavedView(
                id: id(of: .inbox),
                name: Board.inboxName,
                symbol: "tray",
                rule: .group(.all, [live, .criterion(ViewCriterion(field: .board, comparator: .isInbox))]),
                preset: .inbox
            )
        case .today:
            SavedView(
                id: id(of: .today),
                name: String(localized: "Today", comment: "Saved view: tasks due today or overdue"),
                symbol: "sun.max",
                // On or before today, which is overdue *and* today in one
                // clause: work that slipped past its date must not vanish from
                // the one list a person checks every day.
                rule: .group(.all, [
                    live,
                    .criterion(ViewCriterion(field: .due, comparator: .onOrBefore, value: .days(0))),
                ]),
                preset: .today
            )
        case .upcoming:
            SavedView(
                id: id(of: .upcoming),
                name: String(localized: "Upcoming", comment: "Saved view: tasks due in the future"),
                symbol: "calendar",
                rule: .group(.all, [
                    live,
                    .criterion(ViewCriterion(field: .due, comparator: .after, value: .days(0))),
                ]),
                preset: .upcoming
            )
        case .highPriority:
            SavedView(
                id: id(of: .highPriority),
                name: String(localized: "High priority", comment: "Saved view: high-priority tasks"),
                symbol: "exclamationmark.triangle",
                // **At least** High, not exactly High: the view is named for its
                // floor, so a priority added above it belongs here by arriving
                // rather than by an edit.
                rule: .group(.all, [
                    live,
                    .criterion(ViewCriterion(field: .priority, comparator: .atLeast, value: .priority(.high))),
                ]),
                preset: .highPriority
            )
        case .dueThisWeek:
            SavedView(
                id: id(of: .dueThisWeek),
                name: String(localized: "Due this week", comment: "Saved view: tasks due in the next seven days"),
                symbol: "calendar.badge.clock",
                rule: .group(.all, [
                    live,
                    .criterion(ViewCriterion(field: .due, comparator: .thisWeek)),
                ]),
                preset: .dueThisWeek
            )
        case .recentlyUpdated:
            SavedView(
                id: id(of: .recentlyUpdated),
                name: String(localized: "Recently updated", comment: "Saved view: the most recently changed tasks"),
                symbol: "clock.arrow.circlepath",
                // Done is *not* excluded here: this answers "what has been
                // happening", and finishing something is the most interesting
                // thing that can happen to it.
                rule: .group(.all, [onTheBoard]),
                sort: .recentlyUpdated,
                limit: 20,
                preset: .recentlyUpdated
            )
        case .archive:
            SavedView(
                id: id(of: .archive),
                name: String(localized: "Archive", comment: "Saved view: tasks that have been filed away"),
                symbol: "archivebox",
                rule: .group(.all, [
                    .criterion(ViewCriterion(field: .archived, comparator: .isTrue)),
                ]),
                sort: .recentlyArchived,
                preset: .archive
            )
        }
    }

    /// The default list a file gains when it is migrated, and what a board with
    /// no views at all falls back to.
    static var seededAll: [SavedView] { Preset.allCases.map(seeded) }

    // MARK: The glyph

    /// What a view wears before anybody picks: the filter mark, because a view
    /// with no rule written yet is a filter that has not been narrowed.
    static let defaultSymbol = "line.3.horizontal.decrease.circle"

    /// The glyphs the icon picker *opens* on — ``Board/startingSymbols`` for
    /// views, and the same bargain: the whole of ``SymbolCatalog`` is one menu
    /// away, and opening a picker on seven thousand names sorted alphabetically
    /// means opening it on `0.circle`.
    ///
    /// These eighteen were the whole of what the editor could offer until the
    /// browser arrived. They lead with the seeded seven's own marks, so a view
    /// somebody has rewritten can be put back to looking like what it was, and
    /// every one of them reads at the 14pt a sidebar row draws it at — which is
    /// what a picker over all of SF Symbols cannot promise and why the short
    /// list is still the one in front.
    static let startingSymbols = [
        defaultSymbol, "tray", "sun.max", "calendar",
        "calendar.badge.clock", "exclamationmark.triangle", "clock.arrow.circlepath",
        "archivebox", "flag", "star", "bolt", "person", "tag", "checkmark.circle",
        "magnifyingglass", "flame", "leaf", "bookmark",
    ]

    /// "On the board" — not filed away. The exclusion the old enum applied
    /// before its table and nothing on screen ever said.
    private static var onTheBoard: ViewRule {
        .criterion(ViewCriterion(field: .archived, comparator: .isFalse))
    }

    /// "Still to do" — on the board and not in its Done column. Five of the
    /// seven start here.
    private static var live: ViewRule {
        .group(.all, [onTheBoard, .criterion(ViewCriterion(field: .done, comparator: .isFalse))])
    }

    /// What **New view** starts from: everything still on the board, which is
    /// the honest empty rule — a view showing nothing at all is one that looks
    /// broken before the first criterion lands.
    static func blank(named name: String) -> SavedView {
        SavedView(name: name, rule: .group(.all, [onTheBoard]))
    }
}

extension ViewRule {
    /// Kept as a name for what it says, now that `==` says it: ``ViewRule``
    /// compares by structure rather than by id precisely so that a rule rebuilt
    /// from ``SavedView/seeded(_:)`` equals the one already in the file.
    func isEquivalent(to other: ViewRule) -> Bool { self == other }
}
