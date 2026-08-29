import AppIntents
import Foundation

// The verbs Shortcuts can aim at a card, and the entities that let it name one.
//
// `TaskIntents.swift` holds the two intents that came first — Add Task and Show
// Today — along with `TaskIntentBridge`, `BoardEntity` and `ColumnEntity`, which
// everything here reaches through. It is split rather than extended because the
// two halves are about different things: that file is the app's *doors* — deep
// links, Handoff, Spotlight, the bridge — and this one is its automation
// vocabulary.
//
// **`TaskEntity` is what makes the rest usable.** Without it every intent below
// would take a raw UUID, which is not a thing anybody has: a Shortcut is built
// by picking a card out of a list or by finding one by name, and an entity with
// a query is how AppIntents offers both. So it comes first, and Complete, Move,
// Open and the three setters are all "do this to a `TaskEntity`".

// MARK: - Entities

/// A card, as Shortcuts sees it.
///
/// The subtitle is the code — "NW-118" — because two cards may perfectly well be
/// called "Fix the header" and the code is the half that tells them apart. It is
/// also what ``TaskEntityQuery`` matches on, so a Shortcut can name a card the
/// way a person does out loud.
struct TaskEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Task", comment: "What a card is called in the Shortcuts editor")
    )
    static let defaultQuery = TaskEntityQuery()

    var id: UUID
    var title: String
    var code: String
    var note: String
    var isDone: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(code)")
    }

    /// Built through the store rather than from the card alone: "done" is the
    /// board's answer — a card is finished by being in its board's last column —
    /// and a `TaskItem` cannot work that out on its own. See ``Board/doneColumn``.
    @MainActor
    init(_ task: TaskItem, in store: BoardStore) {
        id = task.id
        title = task.displayTitle
        code = task.code
        note = task.note
        isDone = store.isDone(task)
    }
}

struct TaskEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        let wanted = Set(identifiers)
        return await MainActor.run {
            guard let store = TaskIntentBridge.store else { return [] }
            return store.tasks.filter { wanted.contains($0.id) }.map { TaskEntity($0, in: store) }
        }
    }

    /// What "find a card called…" runs. The app's own search, through
    /// ``BoardStore/tasks(matching:)``, so a Shortcut finds what the search
    /// field would find — including by code, and including the folded,
    /// accent-insensitive matching the panel does.
    func entities(matching string: String) async throws -> [TaskEntity] {
        await MainActor.run {
            guard let store = TaskIntentBridge.store else { return [] }
            return store.tasks(matching: string).map { TaskEntity($0, in: store) }
        }
    }

    /// The Inbox and the active board, rather than every card in the file. A
    /// picker is a list somebody scrolls, and a board of four hundred cards
    /// offered whole is a picker nobody can use — the string query above is the
    /// way to reach the rest.
    func suggestedEntities() async throws -> [TaskEntity] {
        await MainActor.run {
            guard let store = TaskIntentBridge.store else { return [] }
            let onBoard = store.activeBoard?.columns.flatMap { store.visibleTasks(in: $0.id) } ?? []
            return (store.inboxTasks + onBoard).map { TaskEntity($0, in: store) }
        }
    }
}

/// A saved view — Today, Overdue, the Archive, or one the user made.
struct ViewEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("View", comment: "What a saved view is called in the Shortcuts editor")
    )
    static let defaultQuery = ViewEntityQuery()

    var id: SavedView.ID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// **Not the widget extension's `WidgetViewEntity`**, deliberately. That one is
/// configured in another process against a digest the app wrote; this one reads
/// the live store. They answer the same question from opposite sides of the App
/// Group fence, and sharing a type would mean sharing a data source neither
/// half can hold.
struct ViewEntityQuery: EntityQuery {
    func entities(for identifiers: [SavedView.ID]) async throws -> [ViewEntity] {
        let wanted = Set(identifiers)
        return await MainActor.run { Self.all().filter { wanted.contains($0.id) } }
    }

    func suggestedEntities() async throws -> [ViewEntity] {
        await MainActor.run { Self.all() }
    }

    @MainActor
    private static func all() -> [ViewEntity] {
        (TaskIntentBridge.store?.views ?? []).map { ViewEntity(id: $0.id, name: $0.name) }
    }
}

/// A label, named by its slug and shown by its name.
struct LabelEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Label", comment: "What a card's label is called in the Shortcuts editor")
    )
    static let defaultQuery = LabelEntityQuery()

    /// The label's key, which is what a card carries — see ``LabelDef``. Not the
    /// name: a label can be renamed, and a Shortcut naming one by its display
    /// name would break the day somebody did.
    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct LabelEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LabelEntity] {
        let wanted = Set(identifiers)
        return await MainActor.run { Self.all().filter { wanted.contains($0.id) } }
    }

    func suggestedEntities() async throws -> [LabelEntity] {
        await MainActor.run { Self.all() }
    }

    @MainActor
    private static func all() -> [LabelEntity] {
        (TaskIntentBridge.store?.labels ?? []).map { LabelEntity(id: $0.key, name: $0.name) }
    }
}

/// The four priorities, for the Shortcuts editor.
///
/// **A second enum rather than `Priority: AppEnum`.** `Priority` is compiled
/// into the widget extension as well as the app — see `project.yml` — and
/// conforming it there would put an automation vocabulary and a second set of
/// localised display names into a bundle that draws a coloured dot and has no
/// use for either. The mapping below is the whole cost of keeping them apart.
enum TaskPriorityAppEnum: String, AppEnum {
    case max, high, medium, low

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Priority", comment: "What a card's priority is called in the Shortcuts editor")
    )

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .max: DisplayRepresentation(title: LocalizedStringResource("Max", comment: "The loudest priority, in Shortcuts")),
        .high: DisplayRepresentation(title: LocalizedStringResource("High", comment: "A card's priority, in Shortcuts")),
        .medium: DisplayRepresentation(title: LocalizedStringResource("Medium", comment: "A card's priority, in Shortcuts")),
        .low: DisplayRepresentation(title: LocalizedStringResource("Low", comment: "A card's priority, in Shortcuts")),
    ]

    var priority: Priority {
        switch self {
        case .max: .max
        case .high: .high
        case .medium: .medium
        case .low: .low
        }
    }
}

/// Add or remove, for ``ChangeLabelIntent``.
///
/// One intent with a direction rather than two intents, because "toggle" is the
/// wrong verb for automation: a Shortcut run twice must not undo itself, and a
/// rule that says *put the Urgent label on this* has to mean that whether or not
/// the label is already there.
enum LabelChange: String, AppEnum {
    case add, remove

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Label Change", comment: "Whether a Shortcut adds or removes a label")
    )

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .add: DisplayRepresentation(title: LocalizedStringResource("Add", comment: "Puts a label on a card, in Shortcuts")),
        .remove: DisplayRepresentation(title: LocalizedStringResource("Remove", comment: "Takes a label off a card, in Shortcuts")),
    ]
}

// MARK: - Reaching a card

/// The card an intent was aimed at, or the error that says why there is none.
///
/// Every intent below starts here, and none of them silently does nothing: a
/// card that has been deleted since the Shortcut was built is the single most
/// likely failure of any of this, and a shortcut that "worked" while doing
/// nothing is indistinguishable from one that ran. It is `DeepLinkFailure`'s
/// rule — a link that names nothing must say so — spelled for Shortcuts.
@MainActor
private func resolve(_ entity: TaskEntity) throws -> (store: BoardStore, task: TaskItem) {
    let store = try TaskIntentBridge.require()
    guard let task = store[entity.id] else { throw TaskIntentError.noSuchTask }
    return (store, task)
}

// MARK: - The verbs

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription(
        "Ticks a task off. A task on a board moves to its Done column; a task in the Inbox is completed where it is."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Task")
    var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (store, item) = try resolve(task)
        // Already done is *not* an error: a Shortcut that runs nightly over
        // everything overdue would fail on its second run, and "it is finished"
        // is what the caller asked for either way.
        guard !store.isDone(item) else {
            return .result(dialog: "\(item.code) was already done.")
        }
        guard store.canComplete(item.id) else { throw TaskIntentError.cannotComplete }
        store.complete(item.id)
        return .result(dialog: "Completed \(item.code).")
    }
}

struct ReopenTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Reopen Task"
    static let description = IntentDescription(
        "Takes a finished task back out of Done, to the column it was working in."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Task")
    var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Reopen \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (store, item) = try resolve(task)
        guard store.canReopen(item.id) else {
            return .result(dialog: "\(item.code) was not finished.")
        }
        store.reopen(item.id)
        return .result(dialog: "Reopened \(item.code).")
    }
}

struct MoveTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Task"
    static let description = IntentDescription(
        "Moves a task to a column. With a board given instead, it goes to that board's first working column; with neither, it goes to the Inbox."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Task")
    var task: TaskEntity

    @Parameter(title: "Column")
    var column: ColumnEntity?

    @Parameter(title: "Board")
    var board: BoardEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Move \(\.$task)") {
            \.$column
            \.$board
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (store, item) = try resolve(task)
        let destination = try placement(in: store)
        store.move(item.id, to: destination)
        return .result(dialog: "Moved \(item.code).")
    }

    /// The column if one was named, else the board's landing column, else the
    /// Inbox — the same ladder ``AddTaskIntent`` climbs, so "where does it go"
    /// has one answer in this app rather than one per intent.
    @MainActor
    private func placement(in store: BoardStore) throws -> TaskPlacement {
        if let column {
            guard let owner = store.board(ofColumn: column.id) else { throw TaskIntentError.noSuchColumn }
            return .column(board: owner.id, column: column.id)
        }
        guard let board, let target = store.board(id: board.id)?.landingColumn else { return .inbox }
        return .column(board: board.id, column: target.id)
    }
}

/// Brings the app forward on a card. The one intent here that opens the app,
/// because it is the one whose whole purpose is to put something on screen —
/// what a Shortcut ends with rather than what it does.
struct OpenTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Task"
    static let description = IntentDescription("Opens a task in Simple Kanban.")
    static let openAppWhenRun = true

    @Parameter(title: "Task")
    var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let (store, item) = try resolve(task)
        // Through the same call a deep link and a tapped notification make, so
        // a card in a collapsed board, behind a search or on another board is
        // reached the one way that is known to work — see `BoardStore.reveal`.
        store.clearQuery()
        store.reveal(item.id)
        return .result()
    }
}

// MARK: - Reading the board

struct FindTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Tasks"
    static let description = IntentDescription(
        "Finds tasks by text, board or column. With nothing given it returns everything on the board."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Text")
    var text: String?

    @Parameter(title: "Board")
    var board: BoardEntity?

    @Parameter(title: "Column")
    var column: ColumnEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Find tasks in Simple Kanban") {
            \.$text
            \.$board
            \.$column
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TaskEntity]> {
        let store = try TaskIntentBridge.require()
        var found = store.tasks(matching: text ?? "")
        if let column {
            guard store.board(ofColumn: column.id) != nil else { throw TaskIntentError.noSuchColumn }
            found = found.filter { $0.columnID == column.id }
        } else if let board {
            found = found.filter { $0.boardID == board.id }
        }
        return .result(value: found.map { TaskEntity($0, in: store) })
    }
}

/// The cards of a saved view, evaluated by the store that owns the rule.
///
/// A view is a rule rather than a list — see **Saved views and the archive** —
/// so this asks the store rather than filtering anything itself, and gets back
/// exactly what the sidebar row's count counts.
struct TasksInViewIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Tasks in View"
    static let description = IntentDescription("Returns the tasks a saved view gathers — Today, Overdue, or one of your own.")
    static let openAppWhenRun = false

    @Parameter(title: "View")
    var view: ViewEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get tasks in \(\.$view)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[TaskEntity]> {
        let store = try TaskIntentBridge.require()
        guard let saved = store.view(id: view.id) else { throw TaskIntentError.noSuchView }
        let found = store.tasks(in: saved, today: CalendarDay(.now))
        return .result(value: found.map { TaskEntity($0, in: store) })
    }
}

// MARK: - Setting one field

struct SetDueDateIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Due Date"
    static let description = IntentDescription("Sets a task's due date. With no date given the due date is cleared.")
    static let openAppWhenRun = false

    @Parameter(title: "Task")
    var task: TaskEntity

    @Parameter(title: "Due")
    var due: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Set the due date of \(\.$task) to \(\.$due)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (store, item) = try resolve(task)
        // A day rather than an instant, which is what a due date has always
        // been here — see `CalendarDay`. An absent date clears it, so one
        // intent covers both halves and a Shortcut can take a date from
        // somewhere that may have none.
        store.setDue(due.map { CalendarDay($0) }, on: item.id)
        return .result(dialog: "Updated \(item.code).")
    }
}

struct SetPriorityIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Priority"
    static let description = IntentDescription("Sets a task's priority.")
    static let openAppWhenRun = false

    @Parameter(title: "Task")
    var task: TaskEntity

    @Parameter(title: "Priority")
    var priority: TaskPriorityAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Set the priority of \(\.$task) to \(\.$priority)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (store, item) = try resolve(task)
        store.setPriority(priority.priority, on: item.id)
        return .result(dialog: "Updated \(item.code).")
    }
}

struct ChangeLabelIntent: AppIntent {
    static let title: LocalizedStringResource = "Change Label"
    static let description = IntentDescription("Puts a label on a task or takes one off.")
    static let openAppWhenRun = false

    @Parameter(title: "Task")
    var task: TaskEntity

    @Parameter(title: "Change")
    var change: LabelChange

    @Parameter(title: "Label")
    var label: LabelEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$change) \(\.$label) on \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let (store, item) = try resolve(task)
        guard store.label(forKey: label.id) != nil else { throw TaskIntentError.noSuchLabel }
        // The store's own verb is a toggle, so the direction is enforced here:
        // asked to add a label the card already carries, this does nothing
        // rather than taking it off. See ``LabelChange``.
        let carries = item.labelKeys.contains(label.id)
        if (change == .add) != carries {
            store.toggleLabel(label.id, on: item.id)
        }
        return .result(dialog: "Updated \(item.code).")
    }
}
