import Foundation

struct SubTask: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var text: String
    var done: Bool = false
}

/// One line of a task's history. The entry stores *what happened*, not the
/// sentence describing it: the sentence is rendered at display time, so history
/// written under one language reads correctly under another.
struct ActivityEntry: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var kind: Kind
    var when: Date

    enum Kind: Hashable, Codable, Sendable {
        case created
        case captured
        case moved(columnID: String, columnName: String)
        case renamed
        case descriptionAdded
        case descriptionUpdated
        case prioritySet(Priority)
        case dueSet(CalendarDay)
        case dueCleared
        case labelAdded(key: String, name: String)
        case labelRemoved(key: String, name: String)
        case subtaskAdded
        case subtaskRenamed
        case subtaskRemoved
        case subtasksCompletedOnDone(count: Int)
        case archived
        case unarchived
        /// Taken back out of the trash. Distinct from `unarchived`: the archive
        /// is a place a card is *filed*, and the trash is a place it was on its
        /// way out of the app from.
        case restoredFromTrash
        /// Taken off a board and back into the global Inbox. Distinct from
        /// `moved`, which names a column: the Inbox is not one, and its name is
        /// the app's rather than the user's, so it is rendered rather than stored.
        case unfiled
        /// Pre-rendered English from a board written before entries were structured.
        case legacy(String)
    }

    init(id: UUID = UUID(), _ kind: Kind, when: Date = .now) {
        self.id = id
        self.kind = kind
        self.when = when
    }

    /// The sentence shown in the feed. Nothing here may be phrased relative to
    /// `today`: an entry records something that already happened, so its wording
    /// has to mean the same thing whenever it is read. That is also why the names
    /// carried by `moved`, `labelAdded` and `labelRemoved` are preferred over
    /// looking the column or label up now — the entry must still read correctly
    /// after the thing it names has been renamed or deleted. `today` decides
    /// nothing but whether a year needs saying.
    func text(today: CalendarDay) -> String {
        switch kind {
        case .created:
            String(localized: "Created", comment: "Activity feed: the task was created")
        case .captured:
            String(localized: "Captured from quick-add", comment: "Activity feed: the task came from quick-add")
        case .moved(_, let columnName):
            String(localized: "Moved to \(columnName)", comment: "Activity feed: moved to a column")
        case .renamed:
            String(localized: "Title updated", comment: "Activity feed: the title was edited")
        case .descriptionAdded:
            String(localized: "Description added", comment: "Activity feed: a note was written")
        case .descriptionUpdated:
            String(localized: "Description updated", comment: "Activity feed: the note was edited")
        case .prioritySet(let priority):
            String(localized: "Priority set to \(priority.displayName)", comment: "Activity feed: priority changed")
        case .dueSet(let day):
            String(localized: "Due set to \(Self.dayText(day, from: today))", comment: "Activity feed: due date set")
        case .dueCleared:
            String(localized: "Due date cleared", comment: "Activity feed: due date removed")
        case .labelAdded(_, let name):
            String(localized: "Label added: \(name)", comment: "Activity feed: a label was attached")
        case .labelRemoved(_, let name):
            String(localized: "Label removed: \(name)", comment: "Activity feed: a label was detached")
        case .subtaskAdded:
            String(localized: "Sub-task added", comment: "Activity feed: a sub-task was added")
        case .subtaskRenamed:
            String(localized: "Sub-task renamed", comment: "Activity feed: a sub-task was renamed")
        case .subtaskRemoved:
            String(localized: "Sub-task removed", comment: "Activity feed: a sub-task was deleted")
        case .archived:
            String(localized: "Archived", comment: "Activity feed: the task was filed away")
        case .unarchived:
            String(localized: "Restored from the archive", comment: "Activity feed: the task was taken back out of the archive")
        case .restoredFromTrash:
            String(localized: "Restored from the trash", comment: "Activity feed: the task was taken back out of the trash")
        case .unfiled:
            String(localized: "Moved to the Inbox", comment: "Activity feed: the task was taken off its board")
        case .subtasksCompletedOnDone(let count):
            count == 1
                ? String(localized: "1 sub-task completed", comment: "Activity feed: one sub-task ticked off by the move to Done")
                : String(localized: "\(count) sub-tasks completed", comment: "Activity feed: several sub-tasks ticked off by the move to Done")
        case .legacy(let text):
            text
        }
    }

    /// The day an entry names, spelled out. Deliberately not `DueDate.label`,
    /// which answers "how far away is this day *now*" — the right question for a
    /// due chip and the wrong one for a record of a past act, where it would make
    /// one stored entry read "Due set to Today", then "Due set to Last week",
    /// then "Due set to 20 Aug". The year is added only when it is not the
    /// current one, so the common case stays short.
    private static func dayText(_ day: CalendarDay, from today: CalendarDay) -> String {
        let date = day.date()
        return day.year == today.year
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// The compact stamp beside the entry — "20 min ago", "2 hr ago", "3 days ago".
    /// `Date.RelativeFormatStyle` is always anchored to the wall clock, which a
    /// test cannot pin, so the reference instant is passed in.
    func whenText(from now: Date = .now) -> String {
        // The formatter rounds to whole units, so anything under half a second
        // old — which every entry is at the moment it is written — comes back
        // as "in 0 sec", future tense for something that has already happened.
        let elapsed = now.timeIntervalSince(when)
        if elapsed > -1, elapsed < 60 {
            return String(localized: "just now",
                          comment: "Activity feed timestamp for something that happened moments ago")
        }
        return Self.relative.localizedString(for: when, relativeTo: now)
    }

    /// Shared: the formatter is an ICU object dear enough to matter when a
    /// feed of forty entries stamps every row on a minute tick. Configured
    /// once, then only ever read — which `Formatter` documents as safe.
    private nonisolated(unsafe) static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    /// The human-facing ticket reference, e.g. `NW-118`. Minted from the
    /// destination's code prefix and the board file's serial — it is a label,
    /// not a key; `id` is the key. It never changes once minted, not even when
    /// the task moves to another board: by then it may be in a commit message.
    var code: String
    /// The board the task is on, or `nil` for the global Inbox.
    ///
    /// Read-only from outside this file, along with `columnID`: the two are one
    /// fact in two fields, and `placement` is the only thing that writes them.
    /// The memberwise initialiser can still spell an illegal pair — it is what
    /// decoding and the tests build tasks with — so `BoardStore` puts every set
    /// of tasks it adopts back through `TaskPlacement` on the way in.
    private(set) var boardID: Board.ID?
    private(set) var columnID: BoardColumn.ID?
    var title: String
    var note: String = ""
    var labelKeys: [String] = []
    /// The day it is due, or `nil` for no due date. The chip's text and colour
    /// are both derived from how far away it is — see `DueDate`.
    var due: CalendarDay?
    var priority: Priority = Priority.default
    var subtasks: [SubTask] = []
    var activity: [ActivityEntry] = []
    var createdAt: Date = .now
    var updatedAt: Date = .now
    /// When an unfiled task was completed in the global Inbox. Board tasks are
    /// complete by living in their board's Done column; Inbox tasks stay put.
    /// Optional so files written before Inbox completion existed still decode.
    var inboxCompletedAt: Date?
    /// When the task was filed away, or `nil` while it is still on the board.
    /// An archived task stays in the file and keeps its column — it is simply
    /// not part of the board any more. Optional rather than a `Bool` with a
    /// default because that is the only shape a synthesised decoder tolerates
    /// the absence of, which is what lets a v2 file read as v3.
    var archivedAt: Date?

    /// Where the task sits, as the one value it really is. The setter is the
    /// only writer of `boardID` and `columnID`, so the invariant — both set, or
    /// neither — holds by construction rather than by everybody remembering.
    var placement: TaskPlacement {
        get {
            guard let boardID, let columnID else { return .inbox }
            return .column(board: boardID, column: columnID)
        }
        set {
            boardID = newValue.boardID
            columnID = newValue.columnID
        }
    }

    /// In the global Inbox: captured, and not yet on a board.
    var isUnfiled: Bool { boardID == nil }

    var isInboxCompleted: Bool { isUnfiled && inboxCompletedAt != nil }

    var isArchived: Bool { archivedAt != nil }

    /// Whether every control on this card's editor still reads the way it did
    /// on `other` — the question a dismissed quick capture is judged by.
    ///
    /// **What the controls write, and nothing else.** The code, the two
    /// timestamps and the activity feed are the card's *record* rather than
    /// anything filled into it, and a capture whose only difference from the
    /// one that was minted is that it has been looked at has had nothing filled
    /// in.
    ///
    /// **Measured against the card as it was made, not against a row of empty
    /// values**, because two of these controls do not start empty. `mintTask`
    /// gives a new card `Preferences.defaultDueDate` and the placement the `+`
    /// was pressed in, so "no due date, in the Inbox" is the empty state on one
    /// machine and a card somebody filled in on another. Asking what changed
    /// needs the before as well as the after.
    ///
    /// The two free-text fields are compared trimmed: a title of spaces is a
    /// title nobody typed, and it is exactly what a field the user clicked into
    /// holds before an editing session ends and tidies it.
    func hasSameContent(as other: TaskItem) -> Bool {
        Self.trimmed(title) == Self.trimmed(other.title)
            && Self.trimmed(note) == Self.trimmed(other.note)
            && labelKeys == other.labelKeys
            && due == other.due
            && priority == other.priority
            && subtasks == other.subtasks
            && placement == other.placement
            && inboxCompletedAt == other.inboxCompletedAt
            && archivedAt == other.archivedAt
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var completedSubtaskCount: Int { subtasks.filter(\.done).count }
    var hasSubtasks: Bool { !subtasks.isEmpty }
    /// `2/3` on a card. Localized rather than interpolated so a right-to-left
    /// translation can put the bidi marks around it that stop "2/3" being read
    /// back as three out of two.
    var subtaskProgressText: String {
        String(localized: "\(completedSubtaskCount)/\(subtasks.count)",
               comment: "Sub-task progress on a card: completed over total")
    }
    var subtaskFraction: Double {
        subtasks.isEmpty ? 0 : Double(completedSubtaskCount) / Double(subtasks.count)
    }

    /// What the board shows. A task captured with the phone's "+" starts
    /// untitled, and stays reachable until it is named.
    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "Untitled", comment: "Placeholder for a task with no title")
            : title
    }

    /// The chip text for `due`, or `nil` when there is no due date.
    func dueText(today: CalendarDay) -> String? {
        due.map { DueDate.label($0, from: today) }
    }

    func isDueToday(_ today: CalendarDay) -> Bool {
        guard let due else { return false }
        return DueDate.urgency(due, from: today) == .today
    }

}
