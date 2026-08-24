import Foundation

/// What a criterion asks about a task.
///
/// One flat list rather than a sum type per field, because the editor is three
/// pickers in a row — field, comparator, value — and a shape that could only be
/// built by switching on the field would need a bespoke row per case. What keeps
/// it honest instead is ``comparators``: a field declares which tests it
/// answers, so a `(field, comparator)` pair the editor cannot offer is one the
/// evaluator never has to have an opinion about.
enum ViewField: String, CaseIterable, Codable, Sendable, Identifiable {
    case due, priority, done, archived, board, column, label, title, note, updated, created, subtasks

    var id: String { rawValue }

    var label: String {
        switch self {
        case .due: String(localized: "Due date", comment: "View criterion field")
        case .priority: String(localized: "Priority", comment: "View criterion field")
        case .done: String(localized: "Completed", comment: "View criterion field")
        case .archived: String(localized: "Archived", comment: "View criterion field")
        case .board: String(localized: "Board", comment: "View criterion field")
        case .column: String(localized: "Column", comment: "View criterion field")
        case .label: String(localized: "Label", comment: "View criterion field")
        case .title: String(localized: "Title", comment: "View criterion field")
        case .note: String(localized: "Description", comment: "View criterion field")
        case .updated: String(localized: "Last updated", comment: "View criterion field")
        case .created: String(localized: "Created", comment: "View criterion field")
        case .subtasks: String(localized: "Sub-tasks", comment: "View criterion field")
        }
    }

    /// The tests this field answers, in the order the picker draws them. The
    /// first is what a criterion falls back to when its field changes under it.
    var comparators: [ViewComparator] {
        switch self {
        case .due: [.onOrBefore, .after, .withinNext, .thisWeek, .isEmpty, .isNotEmpty]
        case .priority: [.atLeast, .atMost, .is, .isNot]
        case .done, .archived: [.isTrue, .isFalse]
        case .board: [.isInbox, .isNotInbox, .is, .isNot]
        case .column: [.is, .isNot]
        case .label: [.has, .hasNot, .isEmpty, .isNotEmpty]
        case .title: [.contains, .doesNotContain]
        case .note: [.contains, .doesNotContain, .isEmpty, .isNotEmpty]
        case .updated, .created: [.withinLast, .notWithinLast]
        case .subtasks: [.hasOutstanding, .allDone, .isEmpty, .isNotEmpty]
        }
    }
}

/// The test itself. Spellings are file tokens rather than words, for
/// ``Priority``'s reason: a board whose stored values *are* its UI text cannot
/// be translated without rewriting everybody's views.
enum ViewComparator: String, CaseIterable, Codable, Sendable, Identifiable {
    case `is`, isNot
    case atLeast, atMost
    case onOrBefore, after, withinNext, thisWeek
    case isEmpty, isNotEmpty
    case has, hasNot
    case contains, doesNotContain
    case withinLast, notWithinLast
    case isTrue, isFalse
    case isInbox, isNotInbox
    case hasOutstanding, allDone

    var id: String { rawValue }

    /// What the third picker has to be, which is also what the evaluator may
    /// read off the criterion. A comparator that needs nothing draws no third
    /// picker at all.
    enum ValueKind: Sendable { case none, days, priority, board, column, label, text }

    var valueKind: ValueKind {
        switch self {
        case .thisWeek, .isEmpty, .isNotEmpty, .isTrue, .isFalse,
             .isInbox, .isNotInbox, .hasOutstanding, .allDone:
            .none
        case .onOrBefore, .after, .withinNext, .withinLast, .notWithinLast:
            .days
        case .atLeast, .atMost:
            .priority
        case .contains, .doesNotContain:
            .text
        case .has, .hasNot:
            .label
        case .is, .isNot:
            // The one comparator whose value depends on the field it is under —
            // priority, board and column all say "is". Resolved by
            // ``ViewCriterion/valueKind``, which has the field to hand.
            .text
        }
    }

    var label: String {
        switch self {
        case .is: String(localized: "is", comment: "View criterion comparator")
        case .isNot: String(localized: "is not", comment: "View criterion comparator")
        case .atLeast: String(localized: "is at least", comment: "View criterion comparator")
        case .atMost: String(localized: "is at most", comment: "View criterion comparator")
        case .onOrBefore: String(localized: "is on or before", comment: "View criterion comparator")
        case .after: String(localized: "is after", comment: "View criterion comparator")
        case .withinNext: String(localized: "is within the next", comment: "View criterion comparator")
        case .thisWeek: String(localized: "is this week", comment: "View criterion comparator")
        case .isEmpty: String(localized: "is empty", comment: "View criterion comparator")
        case .isNotEmpty: String(localized: "is not empty", comment: "View criterion comparator")
        case .has: String(localized: "includes", comment: "View criterion comparator")
        case .hasNot: String(localized: "does not include", comment: "View criterion comparator")
        case .contains: String(localized: "contains", comment: "View criterion comparator")
        case .doesNotContain: String(localized: "does not contain", comment: "View criterion comparator")
        case .withinLast: String(localized: "was within the last", comment: "View criterion comparator")
        case .notWithinLast: String(localized: "was not within the last", comment: "View criterion comparator")
        case .isTrue: String(localized: "yes", comment: "View criterion comparator")
        case .isFalse: String(localized: "no", comment: "View criterion comparator")
        case .isInbox: String(localized: "is the Inbox", comment: "View criterion comparator")
        case .isNotInbox: String(localized: "is any board", comment: "View criterion comparator")
        case .hasOutstanding: String(localized: "has some left", comment: "View criterion comparator")
        case .allDone: String(localized: "are all done", comment: "View criterion comparator")
        }
    }
}

/// The right-hand side, when there is one.
///
/// A single enum rather than a bag of optional fields, so a criterion cannot
/// carry a day count *and* a priority and leave the evaluator to guess which
/// one it meant. Changing the comparator resets it to that comparator's kind —
/// see ``ViewCriterion/comparator``.
enum ViewValue: Hashable, Codable, Sendable {
    case none
    case days(Int)
    case priority(Priority)
    case id(UUID)
    case text(String)

    var days: Int? { if case .days(let d) = self { d } else { nil } }
    var priority: Priority? { if case .priority(let p) = self { p } else { nil } }
    var id: UUID? { if case .id(let id) = self { id } else { nil } }
    var text: String? { if case .text(let t) = self { t } else { nil } }
}

/// One leaf test: a field, a comparator, and the value it compares against.
///
/// **Equality ignores the id**, and it has to. The id is a row's identity for
/// `ForEach` and nothing else — two criteria asking the same question are the
/// same criterion, and `SavedView.seeded(_:)` mints a fresh tree on every call.
/// With the synthesised `==` the seeded seven were never equal to themselves,
/// so `BoardMutation`'s before/after comparison read every no-op as a change and
/// every undo-step count in the suite came out one too high.
struct ViewCriterion: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var field: ViewField = .due
    /// Kept consistent with the field by ``field(_:)`` rather than by an
    /// invariant the editor has to remember: a comparator the field does not
    /// answer is a criterion nothing can evaluate, and a picker is perfectly
    /// capable of leaving one behind when the field changes.
    private(set) var comparator: ViewComparator = .onOrBefore
    private(set) var value: ViewValue = .days(0)

    init(field: ViewField = .due, comparator: ViewComparator? = nil, value: ViewValue? = nil) {
        self.field = field
        self.comparator = comparator ?? field.comparators[0]
        self.value = value ?? Self.emptyValue(for: field, comparator: self.comparator)
    }

    /// Which picker the value gets. `is` and `isNot` are shared across three
    /// fields that mean different things by them, so the field decides.
    var valueKind: ViewComparator.ValueKind {
        Self.valueKind(field: field, comparator: comparator)
    }

    /// **Static, and it has to be.** `init` asks what kind of value the pair
    /// wants so it can start with an empty one, and an instance property here
    /// meant building a probe `ViewCriterion()` to ask — whose own `init` built
    /// another. It recursed until the stack ran out, which is not a test
    /// failure: the host process dies before the suite is even enumerated, and
    /// what `xcodebuild` reports is *the test runner crashed before establishing
    /// connection*.
    static func valueKind(
        field: ViewField, comparator: ViewComparator
    ) -> ViewComparator.ValueKind {
        switch (field, comparator) {
        case (.priority, .is), (.priority, .isNot): return .priority
        case (.board, .is), (.board, .isNot): return .board
        case (.column, .is), (.column, .isNot): return .column
        default: return comparator.valueKind
        }
    }

    /// Moving the field takes the comparator and the value with it, because a
    /// half-changed criterion is one that reads as a sentence and means nothing.
    mutating func field(_ next: ViewField) {
        field = next
        comparator(next.comparators[0])
    }

    mutating func comparator(_ next: ViewComparator) {
        comparator = next
        value = Self.emptyValue(for: field, comparator: next)
    }

    mutating func value(_ next: ViewValue) { value = next }

    static func == (lhs: ViewCriterion, rhs: ViewCriterion) -> Bool {
        lhs.field == rhs.field && lhs.comparator == rhs.comparator && lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(field)
        hasher.combine(comparator)
        hasher.combine(value)
    }

    private static func emptyValue(for field: ViewField, comparator: ViewComparator) -> ViewValue {
        switch valueKind(field: field, comparator: comparator) {
        case .none: return .none
        // Zero for the two that name a *day* — "on or before today" is what
        // Today means — and a week for the three that name a span, which is the
        // one the app already has an opinion about.
        case .days: return .days(comparator == .onOrBefore || comparator == .after ? 0 : 7)
        case .priority: return .priority(.high)
        case .board, .column, .label, .text: return .text("")
        }
    }
}

/// A criterion, or a bracket full of them.
///
/// **Groups rather than an operator per row**, which is the whole reason this is
/// a tree. A flat list carrying AND on one row and OR on the next cannot tell
/// `(A and B) or C` from `A and (B or C)` — it has to pick a precedence and then
/// the rule reads one way and means another. A bracket is the one notation where
/// what is on screen and what is evaluated are the same thing.
///
/// A struct wrapping an enum rather than a bare `indirect enum`: `ForEach` wants
/// `Identifiable`, and a rule that is only identified by its contents loses its
/// row the moment two criteria are made equal by an edit in progress.
struct ViewRule: Identifiable, Hashable, Codable, Sendable {
    enum Joiner: String, CaseIterable, Codable, Sendable, Identifiable {
        case all, any
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: String(localized: "all", comment: "Joins view criteria: every one must match")
            case .any: String(localized: "any", comment: "Joins view criteria: one is enough")
            }
        }
    }

    /// No `indirect` needed: the recursion goes through an `Array`, which is a
    /// reference to a buffer, so the case has a finite size already.
    enum Kind: Hashable, Codable, Sendable {
        case group(Joiner, [ViewRule])
        case criterion(ViewCriterion)
    }

    var id: UUID = UUID()
    var kind: Kind

    /// Equality ignores the id, for ``ViewCriterion``'s reason and with the same
    /// consequence if it did not.
    static func == (lhs: ViewRule, rhs: ViewRule) -> Bool { lhs.kind == rhs.kind }

    func hash(into hasher: inout Hasher) { hasher.combine(kind) }

    static func group(_ joiner: Joiner, _ rules: [ViewRule]) -> ViewRule {
        ViewRule(kind: .group(joiner, rules))
    }

    static func criterion(_ criterion: ViewCriterion) -> ViewRule {
        ViewRule(kind: .criterion(criterion))
    }

    /// An empty **all** group, which is what a new view starts as and what
    /// ``matches(_:in:)`` reads as *everything*. See that method for why the
    /// empty case is not "nothing".
    static var empty: ViewRule { .group(.all, []) }

    var joiner: Joiner? { if case .group(let joiner, _) = kind { joiner } else { nil } }
    var children: [ViewRule] { if case .group(_, let rules) = kind { rules } else { [] } }
    var criterion: ViewCriterion? { if case .criterion(let c) = kind { c } else { nil } }

    /// How many leaves are under here, at any depth — what the sidebar row and
    /// the editor's summary count, and what tells an untouched new view from one
    /// somebody has actually written.
    var criterionCount: Int {
        switch kind {
        case .criterion: 1
        case .group(_, let rules): rules.reduce(0) { $0 + $1.criterionCount }
        }
    }

    // MARK: Editing

    /// Replaces the rule with the given `id` anywhere in the tree, or removes it
    /// when `transform` returns `nil`.
    ///
    /// Recursive rather than a path, because the editor's rows are handed a rule
    /// and not a route to it: a path would have to be rebuilt on every change and
    /// would be wrong for exactly one frame after a deletion above it.
    func replacing(_ target: UUID, with transform: (ViewRule) -> ViewRule?) -> ViewRule? {
        if id == target { return transform(self) }
        guard case .group(let joiner, let rules) = kind else { return self }
        return ViewRule(id: id, kind: .group(joiner, rules.compactMap { $0.replacing(target, with: transform) }))
    }

    /// Appends to the group with the given `id`. A no-op against a criterion's
    /// id, which the editor never asks for — only groups draw an add button.
    func appending(_ rule: ViewRule, to target: UUID) -> ViewRule {
        replacing(target) { found in
            guard case .group(let joiner, let rules) = found.kind else { return found }
            return ViewRule(id: found.id, kind: .group(joiner, rules + [rule]))
        } ?? self
    }

    // MARK: Evaluation

    /// What a task is tested against. Three of the twelve fields cannot be
    /// answered by the task alone: **done** is the board's answer rather than
    /// the task's — see ``Board/doneColumn`` — **due this week** depends on what
    /// the user has said a week is, and every day comparison needs to know what
    /// day it is.
    struct Context: Sendable {
        var today: CalendarDay
        var week: WeekMeaning = .fallback
        var now: Date = .now
        /// Whether this task sits in its board's Done column.
        var isDone: Bool = false
    }

    /// **An empty group matches everything, and that is deliberate.** A view
    /// with no criteria is one being written, and the alternative — an empty
    /// rule matching nothing — means every new view opens on an empty state that
    /// looks like a bug and clears the moment the first criterion lands. `all`
    /// over an empty set is *true* in every other language that has the
    /// question, and `any` over an empty set is likewise false — so an empty
    /// **any** group genuinely does exclude everything, which is why the editor
    /// never creates one.
    func matches(_ task: TaskItem, in context: Context) -> Bool {
        switch kind {
        case .criterion(let criterion):
            return criterion.matches(task, in: context)
        case .group(.all, let rules):
            return rules.allSatisfy { $0.matches(task, in: context) }
        case .group(.any, let rules):
            return rules.contains { $0.matches(task, in: context) }
        }
    }
}

extension ViewCriterion {
    /// One leaf, evaluated.
    ///
    /// A `(field, comparator)` pair the field does not offer falls through to
    /// `true` rather than to `false`: an unreachable combination can only arrive
    /// from a hand-edited file or a future version's spelling, and a view that
    /// silently emptied itself is a worse answer to that than one that ignores a
    /// clause it does not understand.
    func matches(_ task: TaskItem, in context: ViewRule.Context) -> Bool {
        switch field {
        case .due: return matchesDue(task, in: context)
        case .priority: return matchesPriority(task)
        case .done: return comparator == .isTrue ? context.isDone : !context.isDone
        case .archived: return comparator == .isTrue ? task.isArchived : !task.isArchived
        case .board: return matchesBoard(task)
        case .column: return matchesColumn(task)
        case .label: return matchesLabel(task)
        case .title: return matchesText(task.title)
        case .note: return matchesText(task.note)
        case .updated: return matchesAge(task.updatedAt, in: context)
        case .created: return matchesAge(task.createdAt, in: context)
        case .subtasks: return matchesSubtasks(task)
        }
    }

    private func matchesDue(_ task: TaskItem, in context: ViewRule.Context) -> Bool {
        switch comparator {
        case .isEmpty: return task.due == nil
        case .isNotEmpty: return task.due != nil
        default: break
        }
        guard let due = task.due else { return false }
        let away = due - context.today
        switch comparator {
        // `<=` and not `<`: "on or before today" is what Today means, and it is
        // overdue *and* today in one clause rather than two joined by an or.
        case .onOrBefore: return away <= (value.days ?? 0)
        case .after: return away > (value.days ?? 0)
        case .withinNext: return away >= 0 && away <= (value.days ?? 7)
        case .thisWeek: return context.week.containsAhead(due, from: context.today)
        default: return true
        }
    }

    private func matchesPriority(_ task: TaskItem) -> Bool {
        guard let against = value.priority else { return true }
        switch comparator {
        case .atLeast: return task.priority >= against
        case .atMost: return task.priority <= against
        case .is: return task.priority == against
        case .isNot: return task.priority != against
        default: return true
        }
    }

    private func matchesBoard(_ task: TaskItem) -> Bool {
        switch comparator {
        case .isInbox: return task.isUnfiled
        case .isNotInbox: return !task.isUnfiled
        case .is: return task.boardID?.uuidString == value.text
        case .isNot: return task.boardID?.uuidString != value.text
        default: return true
        }
    }

    private func matchesColumn(_ task: TaskItem) -> Bool {
        switch comparator {
        case .is: return task.columnID?.uuidString == value.text
        case .isNot: return task.columnID?.uuidString != value.text
        default: return true
        }
    }

    private func matchesLabel(_ task: TaskItem) -> Bool {
        switch comparator {
        case .isEmpty: return task.labelKeys.isEmpty
        case .isNotEmpty: return !task.labelKeys.isEmpty
        case .has: return task.labelKeys.contains(value.text ?? "")
        case .hasNot: return !task.labelKeys.contains(value.text ?? "")
        default: return true
        }
    }

    /// Case- and diacritic-insensitive, the way the search is: a rule the user
    /// typed in lower case must not stop matching a title they capitalised.
    private func matchesText(_ subject: String) -> Bool {
        let needle = (value.text ?? "").trimmingCharacters(in: .whitespaces)
        switch comparator {
        case .isEmpty: return subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .isNotEmpty: return !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .contains, .doesNotContain:
            // An empty needle is a criterion still being typed, and every task
            // contains the empty string — so it would silently invert a
            // "does not contain" into a view holding nothing.
            guard !needle.isEmpty else { return true }
            let found = subject.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            return comparator == .contains ? found : !found
        default: return true
        }
    }

    private func matchesAge(_ stamp: Date, in context: ViewRule.Context) -> Bool {
        let days = value.days ?? 7
        let cutoff = context.now.addingTimeInterval(-Double(days) * 86_400)
        switch comparator {
        case .withinLast: return stamp >= cutoff
        case .notWithinLast: return stamp < cutoff
        default: return true
        }
    }

    private func matchesSubtasks(_ task: TaskItem) -> Bool {
        switch comparator {
        case .isEmpty: return task.subtasks.isEmpty
        case .isNotEmpty: return !task.subtasks.isEmpty
        case .hasOutstanding: return task.subtasks.contains { !$0.done }
        case .allDone: return !task.subtasks.isEmpty && task.subtasks.allSatisfy(\.done)
        default: return true
        }
    }
}
