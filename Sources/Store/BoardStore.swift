import Observation
import SwiftUI

/// The three tabs in the iOS tab bar.
enum PhoneTab: String, CaseIterable, Identifiable, Sendable {
    case board, inbox, search

    var id: String { rawValue }

    var label: String {
        switch self {
        case .board: "Board"
        case .inbox: "Inbox"
        case .search: "Search"
        }
    }
}

/// Which detail surface a piece of transient editing state belongs to. The
/// macOS inspector and the iOS sheet can both be open at once, so their
/// sub-task drafts and label pickers are tracked separately.
enum DetailScope: Hashable, Sendable { case desk, sheet }

/// Board state and every mutation the design defines.
///
/// This is a port of the `Component extends DCLogic` class in
/// the design spec (see `simple-kanban design spec.zip`): same state fields,
/// same transition rules.
@MainActor
@Observable
final class BoardStore {
    // MARK: Content

    var tasks: [TaskItem]
    /// Ordered — the label picker lists them in creation order, and new labels
    /// take their colour from the palette by current count.
    var labels: [LabelDef]

    // MARK: Selection

    var selectedID: TaskItem.ID?
    var sheetID: TaskItem.ID?

    // MARK: Board interaction

    var draggingID: TaskItem.ID?
    var dropTargetColumnID: BoardColumn.ID?
    var query: String = ""
    var addingColumnID: BoardColumn.ID?
    var draft: String = ""

    // MARK: Surfaces

    var isInspectorOpen: Bool = true
    var isNavDrawerOpen: Bool = false
    var tab: PhoneTab = .board
    var mobileColumnID: BoardColumn.ID = BoardColumn.inProgress.id

    // MARK: Detail editing

    var subtaskDrafts: [DetailScope: String] = [.desk: "", .sheet: ""]
    var labelPickerScope: DetailScope?
    var labelDraft: String = ""

    private var nextSerial: Int = 100

    init(tasks: [TaskItem] = SeedData.tasks, labels: [LabelDef] = LabelDef.seed) {
        self.tasks = tasks
        self.labels = labels
        self.selectedID = tasks.first { $0.id == "t1" }?.id ?? tasks.first?.id
        #if DEBUG
        applyLaunchOverrides()
        #endif
    }

    #if DEBUG
    /// Opens a surface straight from a launch argument, so the sheet, drawer and
    /// individual tabs can be driven from `simctl launch` or a UI test without
    /// scripting taps:
    ///
    ///     xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanOpenSheet t1
    ///     xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanOpenDrawer YES
    ///     xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanTab search
    private func applyLaunchOverrides() {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "SimpleKanbanOpenSheet"), self[id] != nil {
            sheetID = id
        }
        if defaults.bool(forKey: "SimpleKanbanOpenDrawer") {
            isNavDrawerOpen = true
        }
        if let raw = defaults.string(forKey: "SimpleKanbanTab"), let parsed = PhoneTab(rawValue: raw) {
            tab = parsed
        }
    }
    #endif

    // MARK: - Lookup

    subscript(id: TaskItem.ID?) -> TaskItem? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    var selectedTask: TaskItem? { self[selectedID] }
    var sheetTask: TaskItem? { self[sheetID] }

    func label(forKey key: String) -> LabelDef? { labels.first { $0.key == key } }

    /// The label definitions for a task, skipping any key without a definition.
    func labels(for task: TaskItem) -> [LabelDef] {
        task.labelKeys.compactMap { label(forKey: $0) }
    }

    // MARK: - Filtering

    /// Tasks matching the current search query. An empty query matches everything.
    var visibleTasks: [TaskItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return tasks }
        return tasks.filter { $0.searchHaystack.contains(needle) }
    }

    func visibleTasks(in columnID: BoardColumn.ID) -> [TaskItem] {
        visibleTasks.filter { $0.columnID == columnID }
    }

    // MARK: - Counts

    var totalCount: Int { tasks.count }

    var todayCount: Int {
        tasks.filter { $0.due == "Today" && $0.columnID != BoardColumn.done.id }.count
    }

    var doneCount: Int {
        tasks.filter { $0.columnID == BoardColumn.done.id }.count
    }

    /// Fraction of the board that has shipped, for the "This week" meter.
    var doneFraction: Double {
        tasks.isEmpty ? 0 : Double(doneCount) / Double(tasks.count)
    }

    // MARK: - Moving

    /// Moves a task to `columnID`. When `beforeID` is given the task is inserted
    /// ahead of that task, which is how card-to-card drops reorder a column;
    /// otherwise it lands at the end of the board order.
    ///
    /// Moving into Done ticks off any outstanding sub-tasks, matching the spec.
    func move(_ id: TaskItem.ID, to columnID: BoardColumn.ID, before beforeID: TaskItem.ID? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        var moved = tasks.remove(at: index)
        let wasElsewhere = moved.columnID != columnID
        moved.columnID = columnID
        if columnID == BoardColumn.done.id, wasElsewhere {
            moved.subtasks = moved.subtasks.map { var s = $0; s.done = true; return s }
        }

        if let beforeID, let target = tasks.firstIndex(where: { $0.id == beforeID }) {
            tasks.insert(moved, at: target)
        } else {
            tasks.append(moved)
        }

        draggingID = nil
        dropTargetColumnID = nil
    }

    // MARK: - Creating

    /// Adds a task and focuses it: the macOS build selects it in the inspector,
    /// the iOS build opens its detail sheet.
    @discardableResult
    func addTask(to columnID: BoardColumn.ID, title: String, fromPhone: Bool = false) -> TaskItem.ID {
        let id = "n\(nextSerial)"
        let task = TaskItem(
            id: id,
            code: "NW-\(140 + nextSerial - 100)",
            columnID: columnID,
            title: title,
            priority: .medium,
            activity: [ActivityEntry(text: "Created", when: "just now")]
        )
        nextSerial += 1
        tasks.append(task)

        draft = ""
        addingColumnID = nil
        if fromPhone {
            sheetID = id
        } else {
            selectedID = id
        }
        return id
    }

    /// Commits the inline "Task title, then ⏎" composer at the top of a column.
    func commitDraft() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let columnID = addingColumnID, !title.isEmpty else { return }
        addTask(to: columnID, title: title)
    }

    func cancelDraft() {
        addingColumnID = nil
        draft = ""
    }

    func beginAdding(in columnID: BoardColumn.ID) {
        addingColumnID = columnID
        draft = ""
    }

    // MARK: - Sub-tasks

    func addSubtask(to taskID: TaskItem.ID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].subtasks.append(SubTask(text: trimmed))
        subtaskDrafts = [.desk: "", .sheet: ""]
    }

    func toggleSubtask(_ subtaskID: SubTask.ID, on taskID: TaskItem.ID) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              let subIndex = tasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID })
        else { return }
        tasks[taskIndex].subtasks[subIndex].done.toggle()
    }

    func subtaskDraft(for scope: DetailScope) -> String { subtaskDrafts[scope] ?? "" }

    func setSubtaskDraft(_ value: String, for scope: DetailScope) { subtaskDrafts[scope] = value }

    // MARK: - Labels

    func toggleLabel(_ key: String, on taskID: TaskItem.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if let existing = tasks[index].labelKeys.firstIndex(of: key) {
            tasks[index].labelKeys.remove(at: existing)
        } else {
            tasks[index].labelKeys.append(key)
        }
    }

    /// Creates a label from the picker's text field and applies it to the task.
    /// A name that slugs to an existing key just applies that label.
    func createLabel(named name: String, on taskID: TaskItem.ID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = LabelDef.key(from: trimmed)

        if label(forKey: key) == nil {
            let tone = LabelDef.palette[labels.count % LabelDef.palette.count]
            labels.append(LabelDef(key: key, name: trimmed, light: tone.light, dark: tone.dark))
        }
        if let index = tasks.firstIndex(where: { $0.id == taskID }), !tasks[index].labelKeys.contains(key) {
            tasks[index].labelKeys.append(key)
        }
        labelDraft = ""
    }

    func toggleLabelPicker(_ scope: DetailScope) {
        labelPickerScope = labelPickerScope == scope ? nil : scope
        labelDraft = ""
    }

    func closeLabelPicker() {
        labelPickerScope = nil
        labelDraft = ""
    }

    // MARK: - iOS navigation

    /// The columns the pager steps through — the workflow, without Inbox.
    var pagerColumns: [BoardColumn] { BoardColumn.workflow }

    private var mobileColumnIndex: Int {
        BoardColumn.workflow.firstIndex { $0.id == mobileColumnID } ?? 0
    }

    var mobileColumn: BoardColumn { BoardColumn.workflow[mobileColumnIndex] }

    /// The name the "+ Add task to …" row shows.
    var mobileColumnName: String {
        tab == .inbox ? BoardColumn.inbox.name : mobileColumn.name
    }

    /// The column a phone-side add lands in.
    var mobileAddColumnID: BoardColumn.ID {
        tab == .inbox ? BoardColumn.inbox.id : mobileColumnID
    }

    /// Wraps around at both ends, matching the spec's modulo step.
    func stepMobileColumn(by delta: Int) {
        let count = BoardColumn.workflow.count
        let next = (mobileColumnIndex + delta + count) % count
        mobileColumnID = BoardColumn.workflow[next].id
    }

    /// What the phone list shows for the current tab.
    var mobileTasks: [TaskItem] {
        switch tab {
        case .board: visibleTasks.filter { $0.columnID == mobileColumnID }
        case .inbox: visibleTasks.filter { $0.columnID == BoardColumn.inbox.id }
        case .search: visibleTasks
        }
    }

    /// The dashed "add here" row is hidden while searching.
    var showsMobileAddRow: Bool { tab != .search }

    /// The floating "+" button: jump to Inbox and start a new capture there.
    func quickCapture() {
        tab = .inbox
        addTask(to: BoardColumn.inbox.id, title: "New task", fromPhone: true)
    }

    func addTaskToCurrentMobileColumn() {
        addTask(to: mobileAddColumnID, title: "New task", fromPhone: true)
    }
}
