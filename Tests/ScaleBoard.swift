import Foundation
@testable import Simple_Kanban

/// A board the size nothing here has ever been run at.
///
/// `SeedData` is fifteen tasks on one board and `TestBoard` is six, which is
/// the size at which every linear scan in the store is free. 7.4 asks what
/// happens at five hundred, and a number measured on a board that fits in a
/// cache line is not an answer — so this one is deliberately awkward: six
/// boards, thirty columns, twenty-four labels, five hundred cards with real
/// prose in their titles and notes, and roughly twenty activity entries each.
///
/// Everything is derived from a fixed seed, so two runs build byte-identical
/// boards and a timing that moves is the code moving rather than the data. The
/// dates are all offsets from a fixed epoch for the same reason `TestBoard`
/// avoids `Date.now`.
enum ScaleBoard {
    static let taskCount = 500
    static let boardCount = 6
    static let columnsPerBoard = 5
    static let labelCount = 24

    /// Well after `TestBoard.epoch`, so a store built from both cannot have its
    /// halves confused by a timestamp.
    static let epoch = Date(timeIntervalSinceReferenceDate: 810_000_000)

    static func at(_ secondsBefore: Int) -> Date { epoch.addingTimeInterval(-Double(secondsBefore)) }

    /// Mid-month and mid-year, the same way `ViewBoard.today` is, so ±30 days
    /// of due dates cannot leave the year.
    static let today = CalendarDay(year: 2026, month: 7, day: 15)

    // MARK: Identity

    private static func uuid(_ tag: UInt8, _ n: Int) -> UUID {
        UUID(uuid: (
            0x5C, 0xA1, tag, 0, 0, 0, 0x40, 0, 0x80, 0,
            UInt8(truncatingIfNeeded: n >> 24), UInt8(truncatingIfNeeded: n >> 16),
            UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n), 0, 0
        ))
    }

    static func taskID(_ n: Int) -> TaskItem.ID { uuid(0x7A, n) }
    static func boardID(_ n: Int) -> Board.ID { uuid(0xB0, n) }
    static func columnID(_ n: Int) -> BoardColumn.ID { uuid(0xC0, n) }
    static func subtaskID(_ n: Int) -> SubTask.ID { uuid(0x5B, n) }
    static func entryID(_ n: Int) -> ActivityEntry.ID { uuid(0xAC, n) }

    // MARK: Shape

    static let labels: [LabelDef] = (0..<labelCount).map { n in
        let swatch = PaletteSwatch.seed[n % PaletteSwatch.seed.count].swatch
        let tone = if case .rgb(let value, _) = swatch { LabelTone.pair(from: value) } else { LabelTone.inkPair }
        return LabelDef(key: "scale-\(n)", name: "Scale \(n)", light: tone.light, dark: tone.dark)
    }

    static let boards: [Board] = (0..<boardCount).map { b in
        Board(
            id: boardID(b), name: "Board \(b)", dot: .hex(0xA8A29A), createdAt: at(1_000_000 - b * 1_000),
            columns: (0..<columnsPerBoard).map { c in
                let n = b * columnsPerBoard + c
                return BoardColumn(
                    id: columnID(n), name: "Column \(b).\(c)", short: "C\(b).\(c)",
                    dot: .hex(0xA8A29A)
                )
            },
            codePrefix: "B\(b)"
        )
    }

    /// Every column on every board, in board order — what a card is filed into.
    static let allColumns: [BoardColumn] = boards.flatMap(\.columns)

    /// The five hundred cards.
    ///
    /// One card in ten is left unfiled so the Inbox is not empty, one in
    /// twenty-five is archived so the Archive has depth, and the rest are dealt
    /// round-robin across the thirty columns — round-robin rather than random so
    /// column sizes are equal and a per-column timing is not measuring one
    /// column that happened to get most of the board.
    static let tasks: [TaskItem] = {
        var rng = Splitmix64(seed: 0x5CA1AB1E)
        var built: [TaskItem] = []
        built.reserveCapacity(taskCount)
        for n in 0..<taskCount {
            let unfiled = n % 10 == 9
            let column = allColumns[n % allColumns.count]
            let noun = nouns[Int(rng.next() % UInt64(nouns.count))]
            let verb = verbs[Int(rng.next() % UInt64(verbs.count))]
            let qualifier = qualifiers[Int(rng.next() % UInt64(qualifiers.count))]

            let labelSpan = Int(rng.next() % 5)
            let firstLabel = Int(rng.next() % UInt64(labelCount))
            let keys = (0..<labelSpan).map { labels[(firstLabel + $0) % labelCount].key }

            let subtaskSpan = Int(rng.next() % 7)
            let subtasks = (0..<subtaskSpan).map { s in
                SubTask(id: subtaskID(n * 8 + s), text: "\(verb) the \(nouns[(n + s) % nouns.count])",
                        done: (n + s) % 3 == 0)
            }

            // Four to forty entries, so the histories are uneven and a card's
            // decode cost is not a constant multiple of the card count.
            let entrySpan = 4 + Int(rng.next() % 37)
            let entries = (0..<entrySpan).map { e in
                ActivityEntry(id: entryID(n * 64 + e), kind(e, in: column), when: at(e * 900 + n))
            }

            let dueOffset = Int(rng.next() % 61) - 30
            var task = TaskItem(
                id: taskID(n),
                code: "\(unfiled ? Board.inboxCodePrefix : "B\(n % boardCount)")-\(400 + n)",
                columnID: unfiled ? nil : column.id,
                title: "\(verb.capitalized) the \(qualifier) \(noun)",
                note: n % 3 == 0
                    ? "\(verb.capitalized) the \(qualifier) \(noun) before the \(nouns[(n + 3) % nouns.count]) lands. \(qualifiers[(n + 1) % qualifiers.count].capitalized) throughout."
                    : "",
                labelKeys: keys,
                due: n % 4 == 0 ? today.adding(days: dueOffset) : nil,
                priority: Priority.allCases[n % Priority.allCases.count],
                subtasks: subtasks,
                activity: entries,
                createdAt: at(200_000 - n * 100),
                updatedAt: at(100_000 - n * 100)
            )
            if n % 25 == 24 { task.archivedAt = at(50_000 - n) }
            built.append(task)
        }
        return built
    }()

    private static func kind(_ e: Int, in column: BoardColumn) -> ActivityEntry.Kind {
        switch e % 6 {
        case 0: .created
        case 1: .moved(columnID: column.id.uuidString, columnName: column.name)
        case 2: .renamed
        case 3: .labelAdded(key: labels[e % labelCount].key, name: labels[e % labelCount].name)
        case 4: .prioritySet(.high)
        default: .subtaskAdded
        }
    }

    @MainActor
    static func store(file: BoardFile? = nil) -> BoardStore {
        store(taskCount: taskCount, file: file)
    }

    /// The same board truncated to its first `taskCount` cards, for the pair of
    /// measurements that answer "how does this grow" rather than "how long does
    /// this take". The boards, columns and labels are unchanged, so the only
    /// thing moving between the two sizes is the array being scanned.
    @MainActor
    static func store(taskCount: Int, file: BoardFile? = nil, sync: BoardSyncStore? = nil) -> BoardStore {
        BoardStore(tasks: Array(tasks.prefix(taskCount)), boards: boards, activeBoardID: boards[0].id,
                   labels: labels, nextSerial: 900 + taskCount, file: file, sync: sync)
    }

    /// The board as it is written to disk — what the debounced save re-encodes.
    static func snapshot(taskCount: Int = ScaleBoard.taskCount) -> BoardSnapshot {
        BoardSnapshot(tasks: Array(tasks.prefix(taskCount)), boards: boards, labels: labels,
                      nextSerial: 900 + taskCount, activeBoardID: boards[0].id)
    }

    /// How many activity entries the whole board carries — the number the save
    /// path re-encodes on every debounce.
    static var activityCount: Int { tasks.reduce(0) { $0 + $1.activity.count } }

    // MARK: Prose

    /// Real words rather than "Task 41", because search folds and scans the
    /// text: a board of identical short titles would make every haystack the
    /// same length and every token match at the same offset.
    private static let nouns = [
        "scroller", "inspector", "sidebar", "composer", "column", "checklist", "palette",
        "migration", "snapshot", "reminder", "shortcut", "drag session", "empty state",
        "activity feed", "saved view", "archive", "backup", "deep link", "quick-add", "label chip",
    ]

    private static let verbs = [
        "rebuild", "measure", "fold", "debounce", "memoise", "reconcile", "quarantine",
        "extract", "mirror", "pin", "unwind", "coalesce",
    ]

    private static let qualifiers = [
        "warm neutral", "left-hand", "debounced", "off-main-actor", "diacritic-folded",
        "undoable", "atomic", "round-tripped", "locale-safe", "pointer-only",
    ]
}

/// SplitMix64 — four lines, no dependencies, and identical on both platforms.
/// `SystemRandomNumberGenerator` would build a different board every run, which
/// is the one thing a fixture measured for timing must not do.
struct Splitmix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
