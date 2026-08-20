import Foundation

// The board as version 1 wrote it. These types describe bytes already on disk,
// so they are frozen: when the current model changes they stay exactly as they
// are and a `…V2` shape is added beside them. Reusing `TaskItem` here instead
// would mean every future field silently rewrote the past.
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
    static func migrate(v1: BoardSnapshotV1) -> BoardSnapshot {
        BoardSnapshot(
            version: BoardSnapshot.currentVersion,
            tasks: v1.tasks.map(TaskItem.init(v1:)),
            labels: v1.labels,
            nextSerial: max(v1.nextSerial, serialFloor(for: v1.tasks)),
            accentTheme: v1.accentTheme
        )
    }

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

private extension TaskItem {
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
            priority: Priority(rawValue: v1.priority) ?? .medium,
            subtasks: v1.subtasks.map { SubTask(id: $0.id, text: $0.text, done: $0.done) },
            activity: v1.activity.map { ActivityEntry(id: $0.id, .legacy($0.text), when: $0.when) },
            createdAt: stamps.min() ?? .now,
            updatedAt: stamps.max() ?? .now
        )
    }
}
