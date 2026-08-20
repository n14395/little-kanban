import Foundation

/// The board contents the design ships with.
///
/// The spec wrote due dates as literals ("Today", "Thu", "Next week") because
/// its urgency colours switched on those exact strings. They are day offsets
/// here — the values the mockup's Wednesday implied — so the chips keep the
/// design's colours on whatever day the app is actually run.
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
        .moved(columnID: column.id, columnName: column.name)
    }

    /// Timestamps come from the history rather than from `.now`, so a seeded
    /// board looks like one that was worked on rather than one minted whole.
    static let tasks: [TaskItem] = seeds.map { seed in
        var task = seed
        task.createdAt = seed.activity.map(\.when).min() ?? .now
        task.updatedAt = seed.activity.map(\.when).max() ?? .now
        return task
    }

    private static let seeds: [TaskItem] = [
        TaskItem(
            id: widgetTaskID, code: "NW-136", columnID: "inbox",
            title: "Widget on the iOS home screen",
            note: "Captured from the menu bar. Needs scoping — probably one column at a glance.",
            priority: .medium,
            activity: [ActivityEntry(.captured, when: ago(minutes: 20))]
        ),
        TaskItem(
            id: cardsJumpTaskID, code: "NW-137", columnID: "inbox",
            title: "Cards jump 1px on drop",
            labelKeys: ["bug"], priority: .low,
            activity: [ActivityEntry(.captured, when: ago(hours: 2))]
        ),
        TaskItem(
            id: illustrationTaskID, code: "NW-138", columnID: "inbox",
            title: "Ask Riya about the empty-board illustration",
            labelKeys: ["design"], priority: .low,
            activity: [ActivityEntry(.captured, when: ago(days: 1))]
        ),
        TaskItem(
            id: dragAndDropTaskID, code: "NW-118", columnID: "doing",
            title: "Drag-and-drop between columns",
            note: "Card follows the pointer with a lifted shadow; columns highlight on hover. Keyboard: ⌥←/→ moves a focused card.",
            labelKeys: ["ios", "design"], due: due(0), priority: .high,
            subtasks: [
                SubTask(text: "Lift + shadow states", done: true),
                SubTask(text: "Column drop targets", done: true),
                SubTask(text: "Keyboard fallback", done: false),
            ],
            activity: [ActivityEntry(moved(to: .inProgress), when: ago(hours: 2))]
        ),
        TaskItem(
            id: inspectorTaskID, code: "NW-121", columnID: "doing",
            title: "Task detail inspector",
            note: "Right-hand panel on macOS, bottom sheet on iOS. Same content, different container.",
            labelKeys: ["design"], due: due(1), priority: .high,
            subtasks: [
                SubTask(text: "Field layout", done: true),
                SubTask(text: "Sheet gestures", done: false),
            ],
            activity: [ActivityEntry(.created, when: ago(days: 3))]
        ),
        TaskItem(
            id: offlineQueueTaskID, code: "NW-104", columnID: "next",
            title: "Offline queue for edits",
            note: "Buffer mutations locally and replay on reconnect. Conflict rule: last write wins per field.",
            labelKeys: ["api"], due: due(2), priority: .high,
            subtasks: [
                SubTask(text: "Mutation log", done: false),
                SubTask(text: "Replay + retry", done: false),
                SubTask(text: "Conflict tests", done: false),
            ],
            activity: [ActivityEntry(.created, when: ago(days: 1))]
        ),
        TaskItem(
            id: swipePagingTaskID, code: "NW-127", columnID: "next",
            title: "Column swipe paging on iPhone",
            note: "One column per screen, rubber-band at the ends, dots reflect position.",
            labelKeys: ["ios"], due: due(5), priority: .medium,
            subtasks: [
                SubTask(text: "Paging scroll view", done: false),
                SubTask(text: "Dots indicator", done: false),
            ],
            activity: [ActivityEntry(.created, when: ago(days: 2))]
        ),
        TaskItem(
            id: dueChipsTaskID, code: "NW-131", columnID: "next",
            title: "Due-date chips turn red when overdue",
            labelKeys: ["polish"], due: due(8), priority: .low,
            activity: [ActivityEntry(.created, when: ago(days: 4))]
        ),
        TaskItem(
            id: templatesTaskID, code: "NW-96", columnID: "backlog",
            title: "Board templates",
            note: "Ship three starters: Personal, Sprint, Content calendar.",
            labelKeys: ["design"], priority: .medium,
            subtasks: [
                SubTask(text: "Pick the three", done: false),
                SubTask(text: "Template picker", done: false),
            ],
            activity: [ActivityEntry(.created, when: ago(days: 7))]
        ),
        TaskItem(
            id: sharedBoardsTaskID, code: "NW-99", columnID: "backlog",
            title: "Shared boards with roles",
            note: "Owner, editor, viewer. Invites by link with expiry.",
            labelKeys: ["api"], priority: .medium,
            activity: [ActivityEntry(.created, when: ago(days: 7))]
        ),
        TaskItem(
            id: menuBarTaskID, code: "NW-108", columnID: "backlog",
            title: "Menu bar quick-add on macOS",
            note: "⌃⌘N from anywhere drops a task into Up Next.",
            labelKeys: ["polish"], priority: .low,
            activity: [ActivityEntry(.created, when: ago(days: 14))]
        ),
        TaskItem(
            id: countBadgeTaskID, code: "NW-113", columnID: "backlog",
            title: "Card count badge misaligns at 3 digits",
            labelKeys: ["bug"], priority: .low,
            activity: [ActivityEntry(.created, when: ago(days: 5))]
        ),
        TaskItem(
            id: syncEngineTaskID, code: "NW-84", columnID: "done",
            title: "Sync engine v2",
            note: "Per-field CRDT with a 200ms debounce. Cut sync conflicts to near zero.",
            labelKeys: ["api"], due: due(5), priority: .high,
            subtasks: [
                SubTask(text: "Schema", done: true),
                SubTask(text: "Migration", done: true),
            ],
            activity: [ActivityEntry(moved(to: .done), when: ago(days: 3))]
        ),
        TaskItem(
            id: paletteTaskID, code: "NW-90", columnID: "done",
            title: "Warm neutral palette + type scale",
            labelKeys: ["design"], due: due(-8), priority: .medium,
            subtasks: [
                SubTask(text: "Palette", done: true),
                SubTask(text: "Type scale", done: true),
            ],
            activity: [ActivityEntry(moved(to: .done), when: ago(days: 6))]
        ),
        TaskItem(
            id: shortcutsTaskID, code: "NW-92", columnID: "done",
            title: "Keyboard shortcuts sheet",
            labelKeys: ["polish"], priority: .low,
            activity: [ActivityEntry(moved(to: .done), when: ago(days: 7))]
        ),
    ]
}
