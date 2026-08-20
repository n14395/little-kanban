import Foundation

/// The board contents the design ships with.
enum SeedData {
    static let tasks: [TaskItem] = [
        TaskItem(
            id: "i1", code: "NW-136", columnID: "inbox",
            title: "Widget on the iOS home screen",
            note: "Captured from the menu bar. Needs scoping — probably one column at a glance.",
            priority: .medium,
            activity: [ActivityEntry(text: "Captured from quick-add", when: "20m ago")]
        ),
        TaskItem(
            id: "i2", code: "NW-137", columnID: "inbox",
            title: "Cards jump 1px on drop",
            labelKeys: ["bug"], priority: .low,
            activity: [ActivityEntry(text: "Captured from quick-add", when: "2h ago")]
        ),
        TaskItem(
            id: "i3", code: "NW-138", columnID: "inbox",
            title: "Ask Riya about the empty-board illustration",
            labelKeys: ["design"], priority: .low,
            activity: [ActivityEntry(text: "Captured from quick-add", when: "yesterday")]
        ),
        TaskItem(
            id: "t1", code: "NW-118", columnID: "doing",
            title: "Drag-and-drop between columns",
            note: "Card follows the pointer with a lifted shadow; columns highlight on hover. Keyboard: ⌥←/→ moves a focused card.",
            labelKeys: ["ios", "design"], due: "Today", priority: .high,
            subtasks: [
                SubTask(text: "Lift + shadow states", done: true),
                SubTask(text: "Column drop targets", done: true),
                SubTask(text: "Keyboard fallback", done: false),
            ],
            activity: [
                ActivityEntry(text: "Moved to In Progress", when: "2h ago"),
                ActivityEntry(text: "Comment added on spacing", when: "yesterday"),
            ]
        ),
        TaskItem(
            id: "t2", code: "NW-121", columnID: "doing",
            title: "Task detail inspector",
            note: "Right-hand panel on macOS, bottom sheet on iOS. Same content, different container.",
            labelKeys: ["design"], due: "Thu", priority: .high,
            subtasks: [
                SubTask(text: "Field layout", done: true),
                SubTask(text: "Sheet gestures", done: false),
            ],
            activity: [ActivityEntry(text: "Created", when: "3d ago")]
        ),
        TaskItem(
            id: "t3", code: "NW-104", columnID: "next",
            title: "Offline queue for edits",
            note: "Buffer mutations locally and replay on reconnect. Conflict rule: last write wins per field.",
            labelKeys: ["api"], due: "Fri", priority: .high,
            subtasks: [
                SubTask(text: "Mutation log", done: false),
                SubTask(text: "Replay + retry", done: false),
                SubTask(text: "Conflict tests", done: false),
            ],
            activity: [ActivityEntry(text: "Estimated at 3 days", when: "1d ago")]
        ),
        TaskItem(
            id: "t4", code: "NW-127", columnID: "next",
            title: "Column swipe paging on iPhone",
            note: "One column per screen, rubber-band at the ends, dots reflect position.",
            labelKeys: ["ios"], due: "Mon", priority: .medium,
            subtasks: [
                SubTask(text: "Paging scroll view", done: false),
                SubTask(text: "Dots indicator", done: false),
            ],
            activity: [ActivityEntry(text: "Spec link added", when: "2d ago")]
        ),
        TaskItem(
            id: "t5", code: "NW-131", columnID: "next",
            title: "Due-date chips turn red when overdue",
            labelKeys: ["polish"], due: "Next week", priority: .low,
            activity: [ActivityEntry(text: "Created", when: "4d ago")]
        ),
        TaskItem(
            id: "t6", code: "NW-96", columnID: "backlog",
            title: "Board templates",
            note: "Ship three starters: Personal, Sprint, Content calendar.",
            labelKeys: ["design"], priority: .medium,
            subtasks: [
                SubTask(text: "Pick the three", done: false),
                SubTask(text: "Template picker", done: false),
            ],
            activity: [ActivityEntry(text: "Created", when: "1w ago")]
        ),
        TaskItem(
            id: "t7", code: "NW-99", columnID: "backlog",
            title: "Shared boards with roles",
            note: "Owner, editor, viewer. Invites by link with expiry.",
            labelKeys: ["api"], priority: .medium,
            activity: [ActivityEntry(text: "Created", when: "1w ago")]
        ),
        TaskItem(
            id: "t8", code: "NW-108", columnID: "backlog",
            title: "Menu bar quick-add on macOS",
            note: "⌃⌘N from anywhere drops a task into Up Next.",
            labelKeys: ["polish"], priority: .low,
            activity: [ActivityEntry(text: "Created", when: "2w ago")]
        ),
        TaskItem(
            id: "t9", code: "NW-113", columnID: "backlog",
            title: "Card count badge misaligns at 3 digits",
            labelKeys: ["bug"], priority: .low,
            activity: [ActivityEntry(text: "Reported", when: "5d ago")]
        ),
        TaskItem(
            id: "t10", code: "NW-84", columnID: "done",
            title: "Sync engine v2",
            note: "Per-field CRDT with a 200ms debounce. Cut sync conflicts to near zero.",
            labelKeys: ["api"], due: "Mon", priority: .high,
            subtasks: [
                SubTask(text: "Schema", done: true),
                SubTask(text: "Migration", done: true),
            ],
            activity: [ActivityEntry(text: "Marked done", when: "3d ago")]
        ),
        TaskItem(
            id: "t11", code: "NW-90", columnID: "done",
            title: "Warm neutral palette + type scale",
            labelKeys: ["design"], due: "Last week", priority: .medium,
            subtasks: [
                SubTask(text: "Palette", done: true),
                SubTask(text: "Type scale", done: true),
            ],
            activity: [ActivityEntry(text: "Marked done", when: "6d ago")]
        ),
        TaskItem(
            id: "t12", code: "NW-92", columnID: "done",
            title: "Keyboard shortcuts sheet",
            labelKeys: ["polish"], priority: .low,
            activity: [ActivityEntry(text: "Marked done", when: "1w ago")]
        ),
    ]
}
