import Foundation

// The board as each older version wrote it. These types describe bytes already
// on disk, so they are frozen: when the current model changes they stay exactly
// as they are and a shape for the version that has just been superseded is
// added beside them. Reusing `TaskItem` here instead would mean every future
// field silently rewrote the past.
//
// The migrations form a chain — v1 → v2 → v3 → v4 → v5 → v6 → v7, one function
// per step — so a v1 file and a v6 file reach the present through the same code,
// and adding v8 costs one shape and one function rather than an edit to every
// decoder. v6 and v7 are the two steps with no shape of their own; see
// `migrate(v5:)` and `migrate(v6:)`.
//
// Decoding is deliberately forgiving about fields v1 gave a default and strict
// about the four it always required. A board with an unrecognised priority is
// still a board; a task with no column is not.

struct BoardSnapshotV1: Decodable {
    var version: Int
    var tasks: [TaskItemV1]
    var labels: [LabelDef]
    var nextSerial: Int
    var accentTheme: AccentTheme

    enum CodingKeys: String, CodingKey { case version, tasks, labels, nextSerial, accentTheme }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        tasks = try container.decode([TaskItemV1].self, forKey: .tasks)
        labels = try container.decodeIfPresent([LabelDef].self, forKey: .labels) ?? LabelDef.seed
        // The store's own baseline, not 1: a serial below it mints codes *under*
        // the ones already on the board. `migrate` raises it further if the
        // board's own codes have climbed past it.
        nextSerial = try container.decodeIfPresent(Int.self, forKey: .nextSerial) ?? BoardSnapshot.baseSerial
        let accent = try container.decodeIfPresent(String.self, forKey: .accentTheme) ?? ""
        accentTheme = AccentTheme(rawValue: accent) ?? .ember
    }
}

struct TaskItemV1: Decodable {
    var id: String
    var code: String
    var columnID: String
    var title: String
    var note: String
    var labelKeys: [String]
    /// v1 stored an instant, written as seconds since the reference date.
    var due: Date?
    var priority: String
    var subtasks: [SubTaskV1]
    var activity: [ActivityEntryV1]

    enum CodingKeys: String, CodingKey {
        case id, code, columnID, title, note, labelKeys, due, priority, subtasks, activity
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        columnID = try container.decode(String.self, forKey: .columnID)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        labelKeys = try container.decodeIfPresent([String].self, forKey: .labelKeys) ?? []
        due = try container.decodeIfPresent(Date.self, forKey: .due)
        priority = try container.decodeIfPresent(String.self, forKey: .priority) ?? Priority.medium.rawValue
        subtasks = try container.decodeIfPresent([SubTaskV1].self, forKey: .subtasks) ?? []
        activity = try container.decodeIfPresent([ActivityEntryV1].self, forKey: .activity) ?? []
    }
}

struct SubTaskV1: Decodable {
    var id: UUID
    var text: String
    var done: Bool

    enum CodingKeys: String, CodingKey { case id, text, done }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}

/// v1 activity was a pre-rendered English sentence with no structure to it.
struct ActivityEntryV1: Decodable {
    var id: UUID
    var text: String
    var when: Date

    enum CodingKeys: String, CodingKey { case id, text, when }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decode(String.self, forKey: .text)
        when = try container.decode(Date.self, forKey: .when)
    }
}

/// The board as version 2 wrote it: UUID task ids, `due` as a calendar day,
/// structured activity, and the `createdAt`/`updatedAt` stamps — everything the
/// current shape has except `archivedAt`.
///
/// Its leaves are the live `SubTask`, `ActivityEntry` and `LabelDef`, which is
/// the one place this file reuses a current type. Those three did not change
/// between v2 and v3, and a `Kind` a v2 file cannot contain costs a v2 decoder
/// nothing. The moment any of them does change, it is frozen here as the v1
/// leaves are.
struct BoardSnapshotV2: Decodable {
    var tasks: [TaskItemV2]
    var labels: [LabelDef]
    var nextSerial: Int
    var accentTheme: AccentTheme

    enum CodingKeys: String, CodingKey { case tasks, labels, nextSerial, accentTheme }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decode([TaskItemV2].self, forKey: .tasks)
        labels = try container.decodeIfPresent([LabelDef].self, forKey: .labels) ?? LabelDef.seed
        nextSerial = try container.decodeIfPresent(Int.self, forKey: .nextSerial) ?? BoardSnapshot.baseSerial
        accentTheme = try container.decodeIfPresent(AccentTheme.self, forKey: .accentTheme) ?? .ember
    }

    init(tasks: [TaskItemV2], labels: [LabelDef], nextSerial: Int, accentTheme: AccentTheme) {
        self.tasks = tasks
        self.labels = labels
        self.nextSerial = nextSerial
        self.accentTheme = accentTheme
    }
}

struct TaskItemV2: Decodable {
    var id: UUID
    var code: String
    var columnID: String
    var title: String
    var note: String
    var labelKeys: [String]
    var due: CalendarDay?
    var priority: Priority
    var subtasks: [SubTask]
    var activity: [ActivityEntry]
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, code, columnID, title, note, labelKeys, due, priority, subtasks, activity,
             createdAt, updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        columnID = try container.decode(String.self, forKey: .columnID)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        labelKeys = try container.decodeIfPresent([String].self, forKey: .labelKeys) ?? []
        due = try container.decodeIfPresent(CalendarDay.self, forKey: .due)
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .medium
        subtasks = try container.decodeIfPresent([SubTask].self, forKey: .subtasks) ?? []
        activity = try container.decodeIfPresent([ActivityEntry].self, forKey: .activity) ?? []
        // v2 always wrote both, but a board hand-edited between the two is
        // still a board: an absent stamp reads as "now" rather than failing.
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    init(
        id: UUID, code: String, columnID: String, title: String, note: String,
        labelKeys: [String], due: CalendarDay?, priority: Priority, subtasks: [SubTask],
        activity: [ActivityEntry], createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.code = code
        self.columnID = columnID
        self.title = title
        self.note = note
        self.labelKeys = labelKeys
        self.due = due
        self.priority = priority
        self.subtasks = subtasks
        self.activity = activity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The board as version 3 wrote it: everything v2 had, plus `archivedAt`. Its
/// column ids are still the five compiled-in strings — "inbox", "backlog",
/// "next", "doing", "done" — which is what v4 replaces with per-board columns
/// carrying UUIDs.
///
/// Its leaves are the live `SubTask`, `ActivityEntry` and `LabelDef`, which is
/// the one place this file reuses a current type. None of the three changed
/// between v3 and v4: `ActivityEntry.moved` carries its column id as a *string*
/// precisely so a historical record can outlive the column it names, so the v4
/// step rewrites the value rather than the shape. The moment any of them does
/// change, it is frozen here as the v1 leaves are.
struct BoardSnapshotV3: Decodable {
    var version: Int
    var tasks: [TaskItemV3]
    var labels: [LabelDef]
    var nextSerial: Int
    var accentTheme: AccentTheme

    enum CodingKeys: String, CodingKey { case version, tasks, labels, nextSerial, accentTheme }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 3
        tasks = try container.decode([TaskItemV3].self, forKey: .tasks)
        labels = try container.decodeIfPresent([LabelDef].self, forKey: .labels) ?? LabelDef.seed
        nextSerial = try container.decodeIfPresent(Int.self, forKey: .nextSerial) ?? BoardSnapshot.baseSerial
        accentTheme = try container.decodeIfPresent(AccentTheme.self, forKey: .accentTheme) ?? .ember
    }

    init(tasks: [TaskItemV3], labels: [LabelDef], nextSerial: Int, accentTheme: AccentTheme) {
        self.version = 3
        self.tasks = tasks
        self.labels = labels
        self.nextSerial = nextSerial
        self.accentTheme = accentTheme
    }
}

struct TaskItemV3: Decodable {
    var id: UUID
    var code: String
    var columnID: String
    var title: String
    var note: String
    var labelKeys: [String]
    var due: CalendarDay?
    var priority: Priority
    var subtasks: [SubTask]
    var activity: [ActivityEntry]
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, code, columnID, title, note, labelKeys, due, priority, subtasks, activity,
             createdAt, updatedAt, archivedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        columnID = try container.decode(String.self, forKey: .columnID)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        labelKeys = try container.decodeIfPresent([String].self, forKey: .labelKeys) ?? []
        due = try container.decodeIfPresent(CalendarDay.self, forKey: .due)
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .medium
        subtasks = try container.decodeIfPresent([SubTask].self, forKey: .subtasks) ?? []
        activity = try container.decodeIfPresent([ActivityEntry].self, forKey: .activity) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }

    init(
        id: UUID, code: String, columnID: String, title: String, note: String,
        labelKeys: [String], due: CalendarDay?, priority: Priority, subtasks: [SubTask],
        activity: [ActivityEntry], createdAt: Date, updatedAt: Date, archivedAt: Date?
    ) {
        self.id = id
        self.code = code
        self.columnID = columnID
        self.title = title
        self.note = note
        self.labelKeys = labelKeys
        self.due = due
        self.priority = priority
        self.subtasks = subtasks
        self.activity = activity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }
}

/// The board as version 4 wrote it: per-board columns with UUID ids, and one
/// flat `columns` array for the single board that was all there was. Its tasks
/// carry a `columnID` that is always present, and the Inbox is one of those
/// column ids rather than the absence of one — which is what v5 changes.
///
/// `BoardColumn`, `SubTask`, `ActivityEntry` and `LabelDef` are the live types
/// here, the one place this file reuses current shapes. None of the four
/// changed between v4 and v5. The moment any of them does, it is frozen here as
/// the v1 leaves are.
struct BoardSnapshotV4: Decodable {
    var version: Int
    var tasks: [TaskItemV4]
    var columns: [BoardColumn]
    var labels: [LabelDef]
    var nextSerial: Int
    var accentTheme: AccentTheme

    enum CodingKeys: String, CodingKey { case version, tasks, columns, labels, nextSerial, accentTheme }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 4
        tasks = try container.decode([TaskItemV4].self, forKey: .tasks)
        columns = try container.decodeIfPresent([BoardColumn].self, forKey: .columns) ?? BoardColumn.workflow
        labels = try container.decodeIfPresent([LabelDef].self, forKey: .labels) ?? LabelDef.seed
        nextSerial = try container.decodeIfPresent(Int.self, forKey: .nextSerial) ?? BoardSnapshot.baseSerial
        accentTheme = try container.decodeIfPresent(AccentTheme.self, forKey: .accentTheme) ?? .ember
    }

    init(tasks: [TaskItemV4], columns: [BoardColumn], labels: [LabelDef], nextSerial: Int, accentTheme: AccentTheme) {
        self.version = 4
        self.tasks = tasks
        self.columns = columns
        self.labels = labels
        self.nextSerial = nextSerial
        self.accentTheme = accentTheme
    }
}

struct TaskItemV4: Decodable {
    var id: UUID
    var code: String
    var columnID: UUID
    var title: String
    var note: String
    var labelKeys: [String]
    var due: CalendarDay?
    var priority: Priority
    var subtasks: [SubTask]
    var activity: [ActivityEntry]
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, code, columnID, title, note, labelKeys, due, priority, subtasks, activity,
             createdAt, updatedAt, archivedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        columnID = try container.decode(UUID.self, forKey: .columnID)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        labelKeys = try container.decodeIfPresent([String].self, forKey: .labelKeys) ?? []
        due = try container.decodeIfPresent(CalendarDay.self, forKey: .due)
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .medium
        subtasks = try container.decodeIfPresent([SubTask].self, forKey: .subtasks) ?? []
        activity = try container.decodeIfPresent([ActivityEntry].self, forKey: .activity) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }

    init(
        id: UUID, code: String, columnID: UUID, title: String, note: String,
        labelKeys: [String], due: CalendarDay?, priority: Priority, subtasks: [SubTask],
        activity: [ActivityEntry], createdAt: Date, updatedAt: Date, archivedAt: Date?
    ) {
        self.id = id
        self.code = code
        self.columnID = columnID
        self.title = title
        self.note = note
        self.labelKeys = labelKeys
        self.due = due
        self.priority = priority
        self.subtasks = subtasks
        self.activity = activity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }
}

extension BoardSnapshot {
    /// Version 1 → 2.
    ///
    /// Task ids become UUIDs (nothing in a v1 file referred to them, so there
    /// is nothing to keep stable), `due` becomes the calendar day it always
    /// meant, and each rendered activity sentence is kept verbatim as
    /// `.legacy` — it is a historical record and re-deriving it would be a
    /// guess. Sub-task and activity ids are carried across: a migration whose
    /// v2 save never lands would otherwise re-identify the whole feed on the
    /// next launch. The timestamps 3.3 added are backfilled from the feed, which is
    /// the only evidence a v1 board carries about when anything happened.
    ///
    /// It stops at v2 rather than at the present. The step after it is the one
    /// a v2 file on disk takes too, and a board arriving from either direction
    /// has to come out the same.
    static func migrate(v1: BoardSnapshotV1) -> BoardSnapshotV2 {
        BoardSnapshotV2(
            tasks: v1.tasks.map(TaskItemV2.init(v1:)),
            labels: v1.labels,
            nextSerial: max(v1.nextSerial, serialFloor(for: v1.tasks)),
            accentTheme: v1.accentTheme
        )
    }

    /// Version 2 → 3.
    ///
    /// v3 adds the archive. Nothing written before it was ever archived, so
    /// every task arrives on the board rather than in the Archive view — which
    /// is what `archivedAt` being absent already means, and is stated here
    /// rather than left to a property default so the step is a real link in the
    /// chain and not a gap in it.
    static func migrate(v2: BoardSnapshotV2) -> BoardSnapshotV3 {
        BoardSnapshotV3(
            tasks: v2.tasks.map(TaskItemV3.init(v2:)),
            labels: v2.labels,
            nextSerial: v2.nextSerial,
            accentTheme: v2.accentTheme
        )
    }

    /// Version 3 → 4.
    ///
    /// v4 makes the columns board data. The five that used to be compiled in
    /// keep their name, short name, dot and order; the board's own list is the
    /// four workflow columns, because the Inbox sits outside the workflow and is
    /// not something a person may rename or delete. They gained a `ColumnRole`
    /// here too, which v9 removed again — Done is the last column, and the four
    /// are already in that order.
    ///
    /// Every string id a v3 file holds is mapped onto the matching column's
    /// UUID — on the task itself and inside each `.moved` activity entry, which
    /// is what `reopen` reads to send a completed task back where it was
    /// working. A task naming a column that never existed goes to the Inbox
    /// rather than being dropped: an unplaceable card is still the user's — and
    /// the v5 step, which reads "not one of this board's columns" as unfiled,
    /// picks it up from there.
    static func migrate(v3: BoardSnapshotV3) -> BoardSnapshotV4 {
        BoardSnapshotV4(
            tasks: v3.tasks.map(TaskItemV4.init(v3:)),
            columns: BoardColumn.workflow,
            labels: v3.labels,
            nextSerial: v3.nextSerial,
            accentTheme: v3.accentTheme
        )
    }

    /// Version 4 → 5.
    ///
    /// v5 makes the columns a *board's* columns and the Inbox global. The one
    /// board a v4 file describes is made here, adopting its columns whole —
    /// same ids, so nothing a task or an activity entry names has to be
    /// rewritten — and it becomes the active board.
    ///
    /// The task split is the whole point of the step: a card in the old Inbox
    /// column becomes unfiled, because the Inbox is not a column any more, and
    /// every other card joins the board. "The old Inbox column" is spelled as
    /// "a column this board does not have", which also catches a card left
    /// pointing at a column a hand-edited file deleted — an unplaceable card is
    /// still the user's, and the Inbox is where it can be found again.
    ///
    /// Codes are left exactly as they are. A code is a label a person may have
    /// pasted into a commit message; a migration that renumbered NW-118 to
    /// IN-118 because the card happened to be in the Inbox would break it.
    static func migrate(v4: BoardSnapshotV4) -> BoardSnapshot {
        // A file hand-edited down to no columns would leave every card homeless.
        let columns = v4.columns.isEmpty ? BoardColumn.workflow : v4.columns
        let board = Board(
            id: migratedBoardID,
            name: "Northwind iOS 3.0",
            dot: .accent,
            // The board is at least as old as the oldest thing on it.
            createdAt: v4.tasks.map(\.createdAt).min() ?? .now,
            columns: columns,
            codePrefix: Board.defaultCodePrefix
        )
        let known = Set(columns.map(\.id))
        return BoardSnapshot(
            version: BoardSnapshot.currentVersion,
            tasks: v4.tasks.map { task in
                TaskItem(
                    v4: task,
                    placement: known.contains(task.columnID)
                        ? .column(board: board.id, column: task.columnID)
                        : .inbox
                )
            },
            boards: [board],
            labels: v4.labels,
            nextSerial: v4.nextSerial,
            accentTheme: v4.accentTheme,
            activeBoardID: board.id
        )
    }

    /// Version 5 → 6.
    ///
    /// v6 stops the file storing its own UI text. `Priority`'s raw values were
    /// "High", "Medium" and "Low" — the very strings the pickers drew — and are
    /// now `high`, `medium` and `low`, so a board can be read in one language
    /// and shown in another.
    ///
    /// Nothing else about the shape moved, which is why there is no
    /// `BoardSnapshotV5` to decode through: `Priority.init(stored:)` answers to
    /// either spelling, so the current decoder reads a v5 file whole and this
    /// step has only the stamp left to do. It is still a step. Without the bump
    /// a v5 build handed a v6 file would decode no priority at all and set the
    /// user's board aside as corrupt; with it, it refuses the file and says why.
    ///
    /// Stamps **6** rather than `currentVersion`: this is one step of a chain,
    /// and a step that jumps to whatever the present happens to be is a step
    /// that silently absorbs the next one. `migrate(v6:)` carries it the rest of
    /// the way.
    static func migrate(v5: BoardSnapshot) -> BoardSnapshot {
        var snapshot = v5
        snapshot.version = 6
        return snapshot
    }

    /// Version 6 → 7.
    ///
    /// v7 adds the trash — the tasks, columns and boards the user has thrown
    /// away and can still get back, which is `BoardSnapshot.trash`. Purely
    /// additive, and defaulted, so the current decoder reads a v6 file whole and
    /// this step is another bare stamp: a v6 file simply has an empty trash,
    /// which is the truth about it.
    ///
    /// The bump is the point, and it is the same argument `migrate(v5:)` makes
    /// from the other side. Swift's `Codable` ignores keys it does not know, so
    /// a v6 build handed a v7 file would read the board *perfectly*, notice
    /// nothing, and write it back with the trash silently dropped — the user's
    /// deleted work thrown away for good by a downgrade. With the bump that
    /// build refuses the file and says why.
    /// Stamps **7** rather than `currentVersion`, for `migrate(v5:)`'s reason:
    /// a step that jumps to whatever the present happens to be is a step that
    /// silently absorbs the next one. `migrate(v7:)` carries it the rest of the
    /// way.
    static func migrate(v6: BoardSnapshot) -> BoardSnapshot {
        var snapshot = v6
        snapshot.version = 7
        return snapshot
    }

    /// Version 7 → 8.
    ///
    /// v8 adds a fourth priority above High — `Priority.max`, spelled `max` on
    /// disk — and changes what a card minted without one starts on, from
    /// `medium` to `low`. Neither touches the shape: a v7 file has no `max` in
    /// it and every card in it already carries a priority of its own, so the
    /// current decoder reads one whole and this step is another bare stamp.
    ///
    /// The bump is for the other direction, and it is the sharper version of
    /// the argument `migrate(v5:)` makes. `Priority.init(from:)` throws on a
    /// token it does not know, and a `Codable` throw is not local: a v7 build
    /// handed a board with a single Max card on it fails to decode the *whole
    /// file* and quarantines the user's board as corrupt. With the bump it
    /// refuses the file up front and says why.
    ///
    /// Stamps **8** rather than `currentVersion`, for `migrate(v5:)`'s reason:
    /// this is one step of a chain and `migrate(v8:legacyDoneColumns:)` carries
    /// it the rest of the way.
    static func migrate(v7: BoardSnapshot) -> BoardSnapshot {
        var snapshot = v7
        snapshot.version = 8
        return snapshot
    }

    /// Version 8 → 9.
    ///
    /// v9 removes `ColumnRole`. Up to v8 each column stored one of `backlog`,
    /// `active` or `done`, and the board's Done column was the *first* one whose
    /// role said `done`. Two of the three roles never did anything — nothing in
    /// the app ever branched on `backlog` or `active` — and the third is now
    /// answered by position: **the Done column is the board's last one**. See
    /// ``Board/doneColumn``.
    ///
    /// So this step is a reorder, and only for boards that were not already in
    /// that shape: whichever column v8 would have sent a tick to is moved to the
    /// end of its board. Every column the board has, it keeps, and no card
    /// moves — a card sits in a column, and the column has come with it.
    ///
    /// `legacyDoneColumns` carries the ids that v8's rule picks out, read from
    /// the bytes by `BoardSnapshot.legacyDoneColumns(in:)`, because the decoded
    /// snapshot has no roles left in it to read. Empty is the honest answer for
    /// a v1–v4 file: those are rebuilt by the steps above out of
    /// `BoardColumn.workflow`, which already ends in Done.
    ///
    /// **The one board this changes the meaning of** is one with more than one
    /// `done` column. v8 treated a card in *any* of them as complete while
    /// sending new ticks only to the first; v9 has one Done column, so cards
    /// left in the others read as unfinished again. Nothing is lost — the cards,
    /// the columns and the order are all still there — and the state it gives up
    /// is one the app never had a way to show.
    static func migrate(v8: BoardSnapshot, legacyDoneColumns: [BoardColumn.ID] = []) -> BoardSnapshot {
        var snapshot = v8
        let done = Set(legacyDoneColumns)
        for index in snapshot.boards.indices {
            let columns = snapshot.boards[index].columns
            guard let landing = columns.firstIndex(where: { done.contains($0.id) }),
                  landing != columns.count - 1
            else { continue }
            var reordered = columns
            reordered.append(reordered.remove(at: landing))
            snapshot.boards[index].columns = reordered
        }
        snapshot.version = BoardSnapshot.currentVersion
        return snapshot
    }

    /// Fixed rather than fresh so migrating the same bytes twice — a file
    /// restored from the copy `preserveBeforeMigration` keeps, say — names the
    /// same board both times.
    private static let migratedBoardID = UUID(
        uuid: (0xB0, 0xA4, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 4)
    )

    /// The lowest serial that still mints a code above every code the board
    /// already carries.
    ///
    /// A hand-edited or truncated file can arrive with a serial well behind its
    /// own tasks, and minting NW-41 onto a board that has reached NW-136 hands
    /// the user two tickets with one number.
    private static func serialFloor(for tasks: [TaskItemV1]) -> Int {
        let highest = tasks.compactMap(codeNumber).max() ?? 0
        // One serial is one code, so the gap between the baseline's code and the
        // highest code on the board is the number of serials to skip.
        let baseline = codeNumber(BoardSnapshot.code(forSerial: BoardSnapshot.baseSerial)) ?? 0
        return BoardSnapshot.baseSerial + max(0, highest - baseline + 1)
    }

    private static func codeNumber(_ code: String) -> Int? {
        code.hasPrefix("NW-") ? Int(code.dropFirst(3)) : nil
    }

    private static func codeNumber(_ task: TaskItemV1) -> Int? { codeNumber(task.code) }
}

private extension TaskItemV2 {
    init(v1: TaskItemV1) {
        let stamps = v1.activity.map(\.when)
        self.init(
            id: UUID(),
            code: v1.code,
            columnID: v1.columnID,
            title: v1.title,
            note: v1.note,
            labelKeys: v1.labelKeys,
            due: v1.due.map { CalendarDay($0) },
            priority: Priority(stored: v1.priority) ?? .medium,
            subtasks: v1.subtasks.map { SubTask(id: $0.id, text: $0.text, done: $0.done) },
            activity: v1.activity.map { ActivityEntry(id: $0.id, .legacy($0.text), when: $0.when) },
            createdAt: stamps.min() ?? .now,
            updatedAt: stamps.max() ?? .now
        )
    }
}

private extension TaskItemV3 {
    init(v2: TaskItemV2) {
        self.init(
            id: v2.id,
            code: v2.code,
            columnID: v2.columnID,
            title: v2.title,
            note: v2.note,
            labelKeys: v2.labelKeys,
            due: v2.due,
            priority: v2.priority,
            subtasks: v2.subtasks,
            activity: v2.activity,
            createdAt: v2.createdAt,
            updatedAt: v2.updatedAt,
            archivedAt: nil
        )
    }
}

private extension TaskItemV4 {
    init(v3: TaskItemV3) {
        self.init(
            id: v3.id,
            code: v3.code,
            columnID: BoardColumn.legacyIDs[v3.columnID] ?? BoardColumn.inbox.id,
            title: v3.title,
            note: v3.note,
            labelKeys: v3.labelKeys,
            due: v3.due,
            priority: v3.priority,
            subtasks: v3.subtasks,
            activity: v3.activity.map(ActivityEntry.mappingLegacyColumnIDs),
            createdAt: v3.createdAt,
            updatedAt: v3.updatedAt,
            archivedAt: v3.archivedAt
        )
    }
}

private extension TaskItem {
    init(v4: TaskItemV4, placement: TaskPlacement) {
        self.init(
            id: v4.id,
            code: v4.code,
            boardID: placement.boardID,
            columnID: placement.columnID,
            title: v4.title,
            note: v4.note,
            labelKeys: v4.labelKeys,
            due: v4.due,
            priority: v4.priority,
            subtasks: v4.subtasks,
            activity: v4.activity,
            createdAt: v4.createdAt,
            updatedAt: v4.updatedAt,
            archivedAt: v4.archivedAt
        )
    }
}

private extension ActivityEntry {
    /// Rewrites the column id inside a `.moved` entry, leaving the name it
    /// carries alone — the name is what the feed shows, and it was already
    /// written for a column that may since have been renamed. An entry naming a
    /// column v4 has no id for keeps the string it had: it is history, and the
    /// only code that reads it treats an unresolvable id as no id at all.
    static func mappingLegacyColumnIDs(_ entry: ActivityEntry) -> ActivityEntry {
        guard case .moved(let columnID, let columnName) = entry.kind,
              let mapped = BoardColumn.legacyIDs[columnID]
        else { return entry }
        var entry = entry
        entry.kind = .moved(columnID: mapped.uuidString, columnName: columnName)
        return entry
    }
}
