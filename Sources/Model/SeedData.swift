import Foundation

/// The board contents the design ships with.
///
/// The spec wrote due dates as literals ("Today", "Thu", "Next week") because
/// its urgency colours switched on those exact strings. They are day offsets
/// here — the values the mockup's Wednesday implied — so the chips keep the
/// design's colours on whatever day the app is actually run.
///
/// The copy is translated *here*, at seed time, and nowhere afterwards: the
/// moment a fresh install writes this board it is the user's, and a card whose
/// title changed itself because the phone's language did would be the app
/// editing somebody's work. `defaultBoard.name` is the exception — a made-up
/// product name is a proper noun in every language.
enum SeedData {
    /// Seed ids are fixed rather than fresh so DEBUG launch hooks and tests can
    /// address a seed task by name across relaunches.
    private static func seedID(_ n: UInt8) -> UUID {
        UUID(uuid: (0x5E, 0xED, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    static let widgetTaskID = seedID(1)
    static let cardsJumpTaskID = seedID(2)
    static let illustrationTaskID = seedID(3)
    static let dragAndDropTaskID = seedID(4)
    static let inspectorTaskID = seedID(5)
    static let offlineQueueTaskID = seedID(6)
    static let swipePagingTaskID = seedID(7)
    static let dueChipsTaskID = seedID(8)
    static let templatesTaskID = seedID(9)
    static let sharedBoardsTaskID = seedID(10)
    static let menuBarTaskID = seedID(11)
    static let countBadgeTaskID = seedID(12)
    static let syncEngineTaskID = seedID(13)
    static let paletteTaskID = seedID(14)
    static let shortcutsTaskID = seedID(15)

    /// The day `days` from today. Negative is past.
    private static func due(_ days: Int) -> CalendarDay { DueDate.offset(days, from: .today()) }

    /// A past timestamp for the activity feed.
    private static func ago(minutes: Int = 0, hours: Int = 0, days: Int = 0) -> Date {
        Date.now.addingTimeInterval(-Double(minutes * 60 + hours * 3_600 + days * 86_400))
    }

    private static func moved(to column: BoardColumn) -> ActivityEntry.Kind {
        .moved(columnID: column.id.uuidString, columnName: column.name)
    }

    /// The board the design's cards are on. Fixed id, like the task ids above
    /// and for the same reason: the seed, the tests and the DEBUG launch hooks
    /// all have to be able to name it.
    ///
    /// This is one of the two places the product name is written down — the
    /// other is the v4 → v5 migration, which has to name the board it makes for
    /// a file that predates boards. Nothing else may spell it.
    static let defaultBoard = Board(
        id: UUID(uuid: (0xB0, 0xA4, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1)),
        name: "Northwind iOS 3.0",
        dot: .accent,
        createdAt: ago(days: 30),
        columns: BoardColumn.workflow,
        codePrefix: "NW"
    )

    static let boards: [Board] = [defaultBoard]

    /// Timestamps come from the history rather than from `.now`, so a seeded
    /// board looks like one that was worked on rather than one minted whole.
    ///
    /// The three cards with no board and no column are the design's Inbox. It
    /// is global now rather than the board's first column, so they are unfiled
    /// rather than filed somewhere.
    static let tasks: [TaskItem] = seeds.map { seed in
        var task = seed
        task.createdAt = seed.activity.map(\.when).min() ?? .now
        task.updatedAt = seed.activity.map(\.when).max() ?? .now
        return task
    }

    private static let seeds: [TaskItem] = [
        TaskItem(
            id: widgetTaskID, code: "NW-136",
            title: String(localized: "Widget on the iOS home screen", comment: "Seed board: task title"),
            note: String(
                localized: "Captured from the menu bar. Needs scoping — probably one column at a glance.",
                comment: "Seed board: task description"
            ),
            priority: .medium,
            activity: [ActivityEntry(.captured, when: ago(minutes: 20))]
        ),
        TaskItem(
            id: cardsJumpTaskID, code: "NW-137",
            title: String(localized: "Cards jump 1px on drop", comment: "Seed board: task title"),
            labelKeys: ["bug"], priority: .low,
            activity: [ActivityEntry(.captured, when: ago(hours: 2))]
        ),
        TaskItem(
            id: illustrationTaskID, code: "NW-138",
            title: String(
                localized: "Ask Riya about the empty-board illustration",
                comment: "Seed board: task title"
            ),
            labelKeys: ["design"], priority: .low,
            activity: [ActivityEntry(.captured, when: ago(days: 1))]
        ),
        TaskItem(
            id: dragAndDropTaskID, code: "NW-118", boardID: defaultBoard.id, columnID: BoardColumn.inProgress.id,
            title: String(localized: "Drag-and-drop between columns", comment: "Seed board: task title"),
            note: String(
                localized: "Card follows the pointer with a lifted shadow; columns highlight on hover. Keyboard: ⌥←/→ moves a focused card.",
                comment: "Seed board: task description"
            ),
            labelKeys: ["ios", "design"], due: due(0), priority: .high,
            subtasks: [
                SubTask(text: String(localized: "Lift + shadow states", comment: "Seed board: sub-task"), done: true),
                SubTask(text: String(localized: "Column drop targets", comment: "Seed board: sub-task"), done: true),
                SubTask(text: String(localized: "Keyboard fallback", comment: "Seed board: sub-task"), done: false),
            ],
            activity: [ActivityEntry(moved(to: .inProgress), when: ago(hours: 2))]
        ),
        TaskItem(
            id: inspectorTaskID, code: "NW-121", boardID: defaultBoard.id, columnID: BoardColumn.inProgress.id,
            title: String(localized: "Task detail inspector", comment: "Seed board: task title"),
            note: String(
                localized: "Right-hand panel on macOS, bottom sheet on iOS. Same content, different container.",
                comment: "Seed board: task description"
            ),
            labelKeys: ["design"], due: due(1), priority: .high,
            subtasks: [
                SubTask(text: String(localized: "Field layout", comment: "Seed board: sub-task"), done: true),
                SubTask(text: String(localized: "Sheet gestures", comment: "Seed board: sub-task"), done: false),
            ],
            activity: [ActivityEntry(.created, when: ago(days: 3))]
        ),
        TaskItem(
            id: offlineQueueTaskID, code: "NW-104", boardID: defaultBoard.id, columnID: BoardColumn.upNext.id,
            title: String(localized: "Offline queue for edits", comment: "Seed board: task title"),
            note: String(
                localized: "Buffer mutations locally and replay on reconnect. Conflict rule: last write wins per field.",
                comment: "Seed board: task description"
            ),
            labelKeys: ["api"], due: due(2), priority: .high,
            subtasks: [
                SubTask(text: String(localized: "Mutation log", comment: "Seed board: sub-task"), done: false),
                SubTask(text: String(localized: "Replay + retry", comment: "Seed board: sub-task"), done: false),
                SubTask(text: String(localized: "Conflict tests", comment: "Seed board: sub-task"), done: false),
            ],
            activity: [ActivityEntry(.created, when: ago(days: 1))]
        ),
        TaskItem(
            id: swipePagingTaskID, code: "NW-127", boardID: defaultBoard.id, columnID: BoardColumn.upNext.id,
            title: String(localized: "Column swipe paging on iPhone", comment: "Seed board: task title"),
            note: String(
                localized: "One column per screen, rubber-band at the ends, dots reflect position.",
                comment: "Seed board: task description"
            ),
            labelKeys: ["ios"], due: due(5), priority: .medium,
            subtasks: [
                SubTask(text: String(localized: "Paging scroll view", comment: "Seed board: sub-task"), done: false),
                SubTask(text: String(localized: "Dots indicator", comment: "Seed board: sub-task"), done: false),
            ],
            activity: [ActivityEntry(.created, when: ago(days: 2))]
        ),
        TaskItem(
            id: dueChipsTaskID, code: "NW-131", boardID: defaultBoard.id, columnID: BoardColumn.upNext.id,
            title: String(localized: "Due-date chips turn red when overdue", comment: "Seed board: task title"),
            labelKeys: ["polish"], due: due(8), priority: .low,
            activity: [ActivityEntry(.created, when: ago(days: 4))]
        ),
        TaskItem(
            id: templatesTaskID, code: "NW-96", boardID: defaultBoard.id, columnID: BoardColumn.backlog.id,
            title: String(localized: "Board templates", comment: "Seed board: task title"),
            note: String(
                localized: "Ship three starters: Personal, Sprint, Content calendar.",
                comment: "Seed board: task description"
            ),
            labelKeys: ["design"], priority: .medium,
            subtasks: [
                SubTask(text: String(localized: "Pick the three", comment: "Seed board: sub-task"), done: false),
                SubTask(text: String(localized: "Template picker", comment: "Seed board: sub-task"), done: false),
            ],
            activity: [ActivityEntry(.created, when: ago(days: 7))]
        ),
        TaskItem(
            id: sharedBoardsTaskID, code: "NW-99", boardID: defaultBoard.id, columnID: BoardColumn.backlog.id,
            title: String(localized: "Shared boards with roles", comment: "Seed board: task title"),
            note: String(
                localized: "Owner, editor, viewer. Invites by link with expiry.",
                comment: "Seed board: task description"
            ),
            labelKeys: ["api"], priority: .medium,
            activity: [ActivityEntry(.created, when: ago(days: 7))]
        ),
        TaskItem(
            id: menuBarTaskID, code: "NW-108", boardID: defaultBoard.id, columnID: BoardColumn.backlog.id,
            title: String(localized: "Menu bar quick-add on macOS", comment: "Seed board: task title"),
            note: String(
                localized: "⌃⌘N from anywhere drops a task into Up Next.",
                comment: "Seed board: task description"
            ),
            labelKeys: ["polish"], priority: .low,
            activity: [ActivityEntry(.created, when: ago(days: 14))]
        ),
        TaskItem(
            id: countBadgeTaskID, code: "NW-113", boardID: defaultBoard.id, columnID: BoardColumn.backlog.id,
            title: String(localized: "Card count badge misaligns at 3 digits", comment: "Seed board: task title"),
            labelKeys: ["bug"], priority: .low,
            activity: [ActivityEntry(.created, when: ago(days: 5))]
        ),
        TaskItem(
            id: syncEngineTaskID, code: "NW-84", boardID: defaultBoard.id, columnID: BoardColumn.done.id,
            title: String(localized: "Sync engine v2", comment: "Seed board: task title"),
            note: String(
                localized: "Per-field CRDT with a 200ms debounce. Cut sync conflicts to near zero.",
                comment: "Seed board: task description"
            ),
            labelKeys: ["api"], due: due(5), priority: .high,
            subtasks: [
                SubTask(text: String(localized: "Schema", comment: "Seed board: sub-task"), done: true),
                SubTask(text: String(localized: "Migration", comment: "Seed board: sub-task"), done: true),
            ],
            activity: [ActivityEntry(moved(to: .done), when: ago(days: 3))]
        ),
        TaskItem(
            id: paletteTaskID, code: "NW-90", boardID: defaultBoard.id, columnID: BoardColumn.done.id,
            title: String(localized: "Warm neutral palette + type scale", comment: "Seed board: task title"),
            labelKeys: ["design"], due: due(-8), priority: .medium,
            subtasks: [
                SubTask(text: String(localized: "Palette", comment: "Seed board: sub-task"), done: true),
                SubTask(text: String(localized: "Type scale", comment: "Seed board: sub-task"), done: true),
            ],
            activity: [ActivityEntry(moved(to: .done), when: ago(days: 6))]
        ),
        TaskItem(
            id: shortcutsTaskID, code: "NW-92", boardID: defaultBoard.id, columnID: BoardColumn.done.id,
            title: String(localized: "Keyboard shortcuts sheet", comment: "Seed board: task title"),
            labelKeys: ["polish"], priority: .low,
            activity: [ActivityEntry(moved(to: .done), when: ago(days: 7))]
        ),
    ]
}

/// A board offered on first launch, and what picking it puts on the board.
///
/// Fifteen cards about building this app is a good demo and somebody else's
/// todo list. `FirstRunView` asks instead, and these are the three starters
/// seed task `t6` asks for — plus the sample, which is still worth having, and
/// an empty board for people who would rather type their own.
///
/// A template is a `BoardSnapshot` because that is what `BoardStore` already
/// knows how to take on: a first launch starts with nothing at all, and folding
/// a template into nothing is exactly what `importBoard` does.
struct BoardTemplate: Identifiable, Sendable {
    var id: String
    /// What the picker calls it.
    var name: String
    /// One line under the name. Says what the board is *for*, not what is on it.
    var blurb: String
    var symbol: String
    var boards: [Board]
    var labels: [LabelDef]
    var tasks: [TaskItem]
    var nextSerial: Int

    /// The columns the picker draws as a row of dots. Nothing else needs them.
    var columns: [BoardColumn] { boards.first?.columns ?? [] }

    var snapshot: BoardSnapshot {
        BoardSnapshot(
            tasks: tasks, boards: boards, labels: labels, nextSerial: nextSerial,
            accentTheme: .ember, activeBoardID: boards.first?.id
        )
    }
}

extension BoardTemplate {
    /// One card of a template, before it has an id, a code or a board.
    struct Card: Sendable {
        /// Which of the board's columns it lands in.
        var column: Int
        var title: String
        var note: String = ""
        var labels: [String] = []
        /// Days from today, so a template is due relative to the day it is
        /// chosen rather than to the day it was written.
        var due: Int?
        var priority: Priority = .medium
        var subtasks: [SubTask] = []
    }

    /// Mints the codes `addTask` would have minted, in order, under the board's
    /// own prefix — so a chosen template arrives numbered like a board somebody
    /// has been working on rather than like a fixture.
    static func make(
        id: String, name: String, blurb: String, symbol: String,
        board: Board, labels: [LabelDef], cards: [Card]
    ) -> BoardTemplate {
        var serial = BoardSnapshot.baseSerial
        let tasks = cards.map { card -> TaskItem in
            defer { serial += 1 }
            let column = board.columns.indices.contains(card.column) ? board.columns[card.column] : nil
            return TaskItem(
                code: BoardSnapshot.code(prefix: board.codePrefix, forSerial: serial),
                boardID: column == nil ? nil : board.id, columnID: column?.id,
                title: card.title, note: card.note, labelKeys: card.labels,
                due: card.due.map { DueDate.offset($0, from: .today()) },
                priority: card.priority, subtasks: card.subtasks,
                activity: [ActivityEntry(.created)]
            )
        }
        return BoardTemplate(
            id: id, name: name, blurb: blurb, symbol: symbol,
            boards: [board], labels: labels, tasks: tasks, nextSerial: serial
        )
    }

    /// A column with the seed's name and a fresh id. The statics on
    /// ``BoardColumn`` carry fixed ids that the migration and the sample board
    /// both name, and two boards may not share a column id — the store resolves
    /// a card's board *from* its column.
    static func column(like seed: BoardColumn) -> BoardColumn {
        BoardColumn(name: seed.name, short: seed.short, dot: seed.dot, role: seed.role)
    }

    static func column(_ name: String, short: String? = nil, _ dot: SwatchColor, _ role: ColumnRole) -> BoardColumn {
        BoardColumn(name: name, short: short ?? name, dot: dot, role: role)
    }
}

extension SeedData {
    /// The starters offered on first launch, in the order they are offered.
    /// The sample sits fourth because it is the one that is about this app
    /// rather than about the person choosing.
    static let starters: [BoardTemplate] = [personal, sprint, contentCalendar, sample, blank]

    static let personal: BoardTemplate = {
        let columns = [
            BoardTemplate.column(
                String(localized: "Someday", comment: "Personal template column: no date on it yet"),
                .hex(0xA8A29A), .backlog
            ),
            BoardTemplate.column(
                String(localized: "This Week", comment: "Personal template column: work with a day on it"),
                .hex(0xC98A16), .backlog
            ),
            BoardTemplate.column(
                String(localized: "Doing", comment: "Personal template column: in flight"),
                .hex(0xC2532F), .active
            ),
            BoardTemplate.column(
                String(localized: "Done", comment: "Personal template column: finished"),
                .hex(0x1F6F63), .done
            ),
        ]
        let board = Board(
            name: String(localized: "Personal", comment: "Name of the Personal starter board"),
            dot: .hex(0x3B5BA9), columns: columns, codePrefix: "ME"
        )
        return .make(
            id: "personal",
            name: String(localized: "Personal", comment: "Starter template name"),
            blurb: String(localized: "Errands, appointments and the things you keep meaning to do.",
                          comment: "One-line description of the Personal starter"),
            symbol: "house",
            board: board,
            labels: [
                LabelDef(key: "home", name: String(localized: "Home", comment: "Personal template label"),
                         light: .tinted(0xC2532F, 0.12, on: 0x9E3E1F),
                         dark: .tinted(0xE87C58, 0.20, on: 0xF1B49B)),
                LabelDef(key: "errand", name: String(localized: "Errand", comment: "Personal template label"),
                         light: .tinted(0xC98A16, 0.15, on: 0x8A5D06),
                         dark: .tinted(0xE6AF3C, 0.18, on: 0xEFCB84)),
                LabelDef(key: "health", name: String(localized: "Health", comment: "Personal template label"),
                         light: .tinted(0x1F6F63, 0.13, on: 0x175A50),
                         dark: .tinted(0x50BEAA, 0.18, on: 0x87DBC9)),
                LabelDef(key: "money", name: String(localized: "Money", comment: "Personal template label"),
                         light: .tinted(0x3B5BA9, 0.12, on: 0x2C4581),
                         dark: .tinted(0x7E9BE0, 0.18, on: 0xB3C4EE)),
            ],
            cards: [
                .init(column: 0, title: String(localized: "Repaint the hallway", comment: "Starter template: task title"), labels: ["home"], priority: .low),
                .init(column: 0, title: String(localized: "Learn to make bread properly", comment: "Starter template: task title"),
                      note: String(localized: "Start with something forgiving. The good tin is in the loft.", comment: "Starter template: task note"), priority: .low),
                .init(column: 1, title: String(localized: "Book the dentist", comment: "Starter template: task title"), labels: ["health"], due: 2, priority: .high),
                .init(column: 1, title: String(localized: "Renew the car insurance", comment: "Starter template: task title"),
                      note: String(localized: "The renewal quote is always worse than the one you get by ringing them.", comment: "Starter template: task note"),
                      labels: ["money"], due: 4, priority: .high),
                .init(column: 1, title: String(localized: "Reply to Sam about the weekend", comment: "Starter template: task title"), labels: ["errand"], due: 1),
                .init(column: 2, title: String(localized: "Clear out the loft", comment: "Starter template: task title"), labels: ["home"], subtasks: [
                    SubTask(text: String(localized: "Bin the boxes from the last move", comment: "Starter template: sub-task"), done: true),
                    SubTask(text: String(localized: "Charity shop run", comment: "Starter template: sub-task"), done: false),
                ]),
                .init(column: 3, title: String(localized: "Cancel the subscription nobody uses", comment: "Starter template: task title"),
                      labels: ["money"], priority: .low),
            ]
        )
    }()

    static let sprint: BoardTemplate = {
        let columns = [
            BoardTemplate.column(like: .backlog),
            BoardTemplate.column(like: .upNext),
            BoardTemplate.column(like: .inProgress),
            BoardTemplate.column(
                String(localized: "In Review", comment: "Sprint template column: waiting on a reviewer"),
                short: String(localized: "Review", comment: "Sprint template column, abbreviated"),
                .hex(0x3B5BA9), .active
            ),
            BoardTemplate.column(like: .done),
        ]
        let board = Board(
            name: String(localized: "Sprint", comment: "Name of the Sprint starter board"),
            dot: .accent, columns: columns, codePrefix: "SP"
        )
        return .make(
            id: "sprint",
            name: String(localized: "Sprint", comment: "Starter template name"),
            blurb: String(localized: "A two-week cycle, with a review column before Done.",
                          comment: "One-line description of the Sprint starter"),
            symbol: "chart.bar",
            board: board,
            labels: [
                LabelDef(key: "feature", name: String(localized: "Feature", comment: "Sprint template label"),
                         light: .tinted(0x1F6F63, 0.13, on: 0x175A50),
                         dark: .tinted(0x50BEAA, 0.18, on: 0x87DBC9)),
                LabelDef(key: "bug", name: String(localized: "Bug", comment: "Sprint template label"),
                         light: .tinted(0xBE2828, 0.12, on: 0xA32222),
                         dark: .tinted(0xF05A5A, 0.18, on: 0xF5A0A0)),
                LabelDef(key: "chore", name: String(localized: "Chore", comment: "Sprint template label"),
                         light: LabelTone(background: .ink(opacity: 0.08), foreground: .ink(opacity: 0.6)),
                         dark: LabelTone(background: .ink(opacity: 0.10), foreground: .ink(opacity: 0.65))),
                LabelDef(key: "spike", name: String(localized: "Spike", comment: "Sprint template label"),
                         light: .tinted(0xC98A16, 0.15, on: 0x8A5D06),
                         dark: .tinted(0xE6AF3C, 0.18, on: 0xEFCB84)),
            ],
            cards: [
                .init(column: 0, title: String(localized: "Search across every board", comment: "Starter template: task title"), labels: ["feature"]),
                .init(column: 0, title: String(localized: "Rate-limit the export endpoint", comment: "Starter template: task title"), labels: ["chore"], priority: .low),
                .init(column: 0, title: String(localized: "Is the queue worth replacing?", comment: "Starter template: task title"),
                      note: String(localized: "Timebox to a day. Write up what we find either way.", comment: "Starter template: task note"),
                      labels: ["spike"], priority: .low),
                .init(column: 1, title: String(localized: "An empty state for every list", comment: "Starter template: task title"), labels: ["feature"], due: 5),
                .init(column: 1, title: String(localized: "Session expires with no warning", comment: "Starter template: task title"),
                      note: String(localized: "Reported twice this week. Reproduces after about an hour idle.", comment: "Starter template: task note"),
                      labels: ["bug"], due: 3, priority: .high),
                .init(column: 2, title: String(localized: "Two-factor sign-in", comment: "Starter template: task title"), labels: ["feature"], due: 2, priority: .high,
                      subtasks: [
                          SubTask(text: String(localized: "Enrolment flow", comment: "Starter template: sub-task"), done: true),
                          SubTask(text: String(localized: "Recovery codes", comment: "Starter template: sub-task"), done: false),
                          SubTask(text: String(localized: "Rate-limit the verify step", comment: "Starter template: sub-task"), done: false),
                      ]),
                .init(column: 3, title: String(localized: "Move the build to the new toolchain", comment: "Starter template: task title"), labels: ["chore"], subtasks: [
                    SubTask(text: String(localized: "CI green on both platforms", comment: "Starter template: sub-task"), done: true),
                    SubTask(text: String(localized: "Release notes", comment: "Starter template: sub-task"), done: false),
                ]),
                .init(column: 4, title: String(localized: "Cut the 0.9 release", comment: "Starter template: task title")),
            ]
        )
    }()

    static let contentCalendar: BoardTemplate = {
        let columns = [
            BoardTemplate.column(
                String(localized: "Ideas", comment: "Content template column: not written yet"),
                .hex(0xA8A29A), .backlog
            ),
            BoardTemplate.column(
                String(localized: "Drafting", comment: "Content template column: being written"),
                .hex(0xC98A16), .active
            ),
            BoardTemplate.column(
                String(localized: "Editing", comment: "Content template column: written, being cut"),
                .hex(0xC2532F), .active
            ),
            BoardTemplate.column(
                String(localized: "Scheduled", comment: "Content template column: has a publication date"),
                .hex(0x3B5BA9), .active
            ),
            BoardTemplate.column(
                String(localized: "Published", comment: "Content template column: out in the world"),
                .hex(0x1F6F63), .done
            ),
        ]
        let board = Board(
            name: String(localized: "Content Calendar", comment: "Name of the Content Calendar starter board"),
            dot: .hex(0x1F6F63), columns: columns, codePrefix: "CC"
        )
        return .make(
            id: "content",
            name: String(localized: "Content Calendar", comment: "Starter template name"),
            blurb: String(localized: "Posts and issues from idea to published, with dates that matter.",
                          comment: "One-line description of the Content Calendar starter"),
            symbol: "calendar",
            board: board,
            labels: [
                LabelDef(key: "blog", name: String(localized: "Blog", comment: "Content template label"),
                         light: .tinted(0xC2532F, 0.12, on: 0x9E3E1F),
                         dark: .tinted(0xE87C58, 0.20, on: 0xF1B49B)),
                LabelDef(key: "newsletter", name: String(localized: "Newsletter", comment: "Content template label"),
                         light: .tinted(0xC98A16, 0.15, on: 0x8A5D06),
                         dark: .tinted(0xE6AF3C, 0.18, on: 0xEFCB84)),
                LabelDef(key: "video", name: String(localized: "Video", comment: "Content template label"),
                         light: .tinted(0x3B5BA9, 0.12, on: 0x2C4581),
                         dark: .tinted(0x7E9BE0, 0.18, on: 0xB3C4EE)),
                LabelDef(key: "social", name: String(localized: "Social", comment: "Content template label"),
                         light: LabelTone(background: .ink(opacity: 0.08), foreground: .ink(opacity: 0.6)),
                         dark: LabelTone(background: .ink(opacity: 0.10), foreground: .ink(opacity: 0.65))),
            ],
            cards: [
                .init(column: 0, title: String(localized: "What nobody tells you about shipping a 1.0", comment: "Starter template: task title"),
                      labels: ["blog"], priority: .low),
                .init(column: 0, title: String(localized: "Three tools we stopped paying for", comment: "Starter template: task title"),
                      labels: ["newsletter"], priority: .low),
                .init(column: 0, title: String(localized: "Short: the fastest way to a first draft", comment: "Starter template: task title"),
                      labels: ["video"], priority: .low),
                .init(column: 1, title: String(localized: "How the design team plans a week", comment: "Starter template: task title"),
                      note: String(localized: "Interview. Keep it to twenty minutes of tape.", comment: "Starter template: task note"),
                      labels: ["blog"], due: 6, subtasks: [
                          SubTask(text: String(localized: "Questions", comment: "Starter template: sub-task"), done: true),
                          SubTask(text: String(localized: "Record", comment: "Starter template: sub-task"), done: false),
                          SubTask(text: String(localized: "Transcribe", comment: "Starter template: sub-task"), done: false),
                      ]),
                .init(column: 1, title: String(localized: "This month's newsletter", comment: "Starter template: task title"), labels: ["newsletter"], due: 3, priority: .high),
                .init(column: 2, title: String(localized: "Teardown: five onboarding flows", comment: "Starter template: task title"),
                      labels: ["blog"], due: 2, priority: .high),
                .init(column: 3, title: String(localized: "Launch thread", comment: "Starter template: task title"), labels: ["social"], due: 1),
                .init(column: 4, title: String(localized: "Last month's newsletter", comment: "Starter template: task title"), labels: ["newsletter"], priority: .low),
            ]
        )
    }()

    /// The board this app has always shipped with. Kept as a *choice* rather
    /// than as the default: it is the design's demo, and it is genuinely the
    /// best way to see what a full board looks like before making one.
    static let sample = BoardTemplate(
        id: "sample",
        name: String(localized: "Sample Board", comment: "Starter template name"),
        blurb: String(localized: "The demo board this app was designed around. Good for a look round.",
                      comment: "One-line description of the sample starter"),
        symbol: "sparkles",
        boards: boards,
        labels: LabelDef.seed,
        tasks: tasks,
        nextSerial: BoardSnapshot.baseSerial
    )

    static let blank: BoardTemplate = {
        let board = Board(
            name: String(localized: "My Board", comment: "Name of the empty starter board"),
            dot: .accent, columns: BoardColumn.workflow.map(BoardTemplate.column(like:)),
            codePrefix: "MB"
        )
        return BoardTemplate(
            id: "blank",
            name: String(localized: "Empty Board", comment: "Starter template name"),
            blurb: String(localized: "Four columns and nothing in them. Bring your own work.",
                          comment: "One-line description of the empty starter"),
            symbol: "square.dashed",
            boards: [board], labels: LabelDef.seed, tasks: [],
            nextSerial: BoardSnapshot.baseSerial
        )
    }()
}
