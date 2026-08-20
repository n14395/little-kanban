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
/// editing sessions, sub-task drafts and label pickers are tracked separately.
enum DetailScope: Hashable, Sendable { case desk, sheet }

/// A field a detail surface edits as a *session*: it takes focus (or opens a
/// picker), the value changes as often as the user likes, and finishing writes
/// one activity entry naming what they settled on.
enum TaskField: String, Hashable, Sendable, CaseIterable {
    case title, note, due, priority
}

/// Why the board's storage last failed, in terms a surface can show.
///
/// Distinct from `BoardFileError`: that one describes a file, this one
/// describes what the user needs to be told about it.
enum BoardStoreError: LocalizedError, Equatable, Sendable, Identifiable {
    /// The saved board could not be used. The payload says where the original
    /// was put — or that it could not be moved at all, which is what stops the
    /// store writing over it.
    case load(BoardLoadFailure)
    /// A write failed. It carries the message rather than the error so the
    /// value stays `Equatable`; the store only ever displays it.
    case save(message: String)

    var id: String {
        switch self {
        case .load(.unreadable): "load.unreadable"
        case .load(.newerVersion(let version, _)): "load.newerVersion.\(version)"
        case .save(let message): "save.\(message)"
        }
    }

    var errorDescription: String? {
        switch self {
        case .load(.unreadable):
            String(localized: "Your board could not be read.",
                   comment: "Alert title when the saved board is corrupt")
        case .load(.newerVersion(let version, _)):
            String(localized: "Your board was saved by a newer version of Simple Kanban (format \(version)).",
                   comment: "Alert title when the saved board is too new to read")
        case .save(let message):
            String(localized: "The board could not be saved. \(message)",
                   comment: "Status shown when writing the board file failed")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .load(.unreadable(let quarantinedAt)), .load(.newerVersion(_, let quarantinedAt)):
            if let quarantinedAt {
                String(localized: "A new board has been started. The old file has been kept as “\(quarantinedAt.lastPathComponent)”.",
                       comment: "Alert body naming the file the damaged board was moved to")
            } else {
                String(localized: "A new board has been started, and saving is paused so the old file is not written over. Continuing will replace it.",
                       comment: "Alert body when the damaged board could not be moved aside")
            }
        case .save:
            nil
        }
    }
}

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
    /// The design exposes the accent as an editable prop; this is the choice,
    /// and it is saved with the board.
    private(set) var accentTheme: AccentTheme

    // MARK: Selection

    /// A surface that moves to another task cannot end the sessions it left
    /// open there, and a session nobody will ever end would silence that task's
    /// picker logging for good — so moving off a task ends them here.
    var selectedID: TaskItem.ID? {
        didSet { if selectedID != oldValue { endSessions(in: .desk, awayFrom: selectedID) } }
    }

    var sheetID: TaskItem.ID? {
        didSet { if sheetID != oldValue { endSessions(in: .sheet, awayFrom: sheetID) } }
    }

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

    /// Which surface has its label picker open. The picker is per surface; the
    /// half-typed name in it is per surface *and* task — see `labelDrafts`.
    var labelPickerScope: DetailScope?

    /// A task that was just created without a title, so its detail surface can
    /// focus the title field. Cleared once a surface has consumed it.
    var pendingTitleFocusID: TaskItem.ID?

    /// A half-typed sub-task or label name belongs to the task it was typed
    /// against, not merely to the surface it was typed on: selecting another
    /// task used to carry the draft across and add it to the wrong task.
    private struct DraftKey: Hashable {
        var scope: DetailScope
        var task: TaskItem.ID
    }

    private var subtaskDrafts: [DraftKey: String] = [:]
    private var labelDrafts: [DraftKey: String] = [:]

    /// One open editing session. Keyed by surface as well as task and field so
    /// two surfaces editing the same title cannot share — and corrupt — one
    /// before-value.
    private struct EditKey: Hashable {
        var scope: DetailScope
        var task: TaskItem.ID
        var field: TaskField
    }

    /// What a field held when its session began, so one activity entry is
    /// logged per session instead of one per keystroke or per date tried.
    private enum FieldValue: Equatable {
        case text(String)
        case day(CalendarDay?)
        case priority(Priority)
    }

    /// An open session: the value the field started on, and the entry the
    /// session has already written. A picker records its change straight away
    /// and then keeps rewriting that one entry, so an abandoned session leaves
    /// a tidy record rather than no record at all.
    private struct Session {
        var before: FieldValue
        var entryID: ActivityEntry.ID?
    }

    private var editSessions: [EditKey: Session] = [:]

    private var nextSerial: Int

    // MARK: Persistence

    /// When the board last reached the disk, for the status bar. `nil` until
    /// this session has saved something.
    private(set) var lastSavedAt: Date?

    /// The last load or write failure, for an alert and the status bar.
    /// `OSLog` is not a user interface.
    private(set) var lastError: BoardStoreError?

    /// Set when the board on disk could not be used, so the launch alert can
    /// say what happened to it. Cleared by `acknowledgeLoadFailure()`.
    private(set) var loadFailure: BoardLoadFailure?

    /// True when the unusable file could not even be moved aside. The only
    /// copy of the user's work is still sitting at the board's URL, so every
    /// write is refused until they say otherwise.
    private(set) var isSaveBlocked: Bool = false

    /// Where the board is saved. `nil` keeps the store purely in memory, which
    /// is what previews and tests want — they must never touch the real file.
    private let file: BoardFile?
    private var saveTask: Task<Void, Never>?

    /// Bumped by every mutation. `scheduleSave()` is the one call the mutation
    /// contract requires them all to make, so bumping it there covers the lot.
    @ObservationIgnored private var boardRevision: Int = 0

    /// The app's store: the board as it was left, or a seeded one on first run.
    static func restored(file: BoardFile = .default) -> BoardStore {
        let result = file.load()
        let store: BoardStore
        if let snapshot = result.snapshot {
            store = BoardStore(
                tasks: snapshot.tasks,
                labels: snapshot.labels,
                accentTheme: snapshot.accentTheme,
                nextSerial: snapshot.nextSerial,
                file: file
            )
        } else {
            store = BoardStore(file: file)
        }
        store.adopt(result)
        return store
    }

    init(
        tasks: [TaskItem] = SeedData.tasks,
        labels: [LabelDef] = LabelDef.seed,
        accentTheme: AccentTheme = .ember,
        nextSerial: Int = BoardSnapshot.baseSerial,
        file: BoardFile? = nil
    ) {
        self.tasks = tasks
        self.labels = labels
        self.accentTheme = accentTheme
        self.nextSerial = nextSerial
        self.file = file
        self.selectedID = tasks.first { $0.id == SeedData.dragAndDropTaskID }?.id ?? tasks.first?.id
        #if DEBUG
        applyLaunchOverrides()
        #endif
    }

    // MARK: - Persistence

    private var snapshot: BoardSnapshot {
        BoardSnapshot(tasks: tasks, labels: labels, nextSerial: nextSerial, accentTheme: accentTheme)
    }

    /// Takes on what the load found: a failure to show, and whether saving has
    /// to stop to protect the file it could not read.
    private func adopt(_ result: BoardLoadResult) {
        guard let failure = result.failure else {
            // A migrated board only exists in the new shape in memory until
            // this lands. `BoardFile` has already kept the pre-migration bytes.
            if result.migratedFromVersion != nil { scheduleSave() }
            return
        }
        loadFailure = failure
        lastError = .load(failure)
        switch failure {
        case .unreadable(let quarantinedAt), .newerVersion(_, let quarantinedAt):
            isSaveBlocked = quarantinedAt == nil
        }
    }

    /// Where the unusable board file was put, when it could be moved at all.
    var quarantinedBoardURL: URL? {
        switch loadFailure {
        case .unreadable(let at), .newerVersion(_, let at): at
        case nil: nil
        }
    }

    /// Coalesces a burst of edits into a single write. Typing a title mutates
    /// the board on every keystroke, so this waits for the typing to stop.
    ///
    /// The snapshot is taken *now* and the task holds it, the file and its
    /// place in the file's write order rather than `self`: an edit made just
    /// before the store goes away must still reach the disk.
    private func scheduleSave() {
        boardRevision &+= 1
        guard let file, !isSaveBlocked else { return }
        let pending = snapshot
        let generation = file.nextWriteGeneration()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            // Off the main actor: encoding the board and writing it are the two
            // things in a keystroke's path that grow with the board's size.
            let outcome = await Task.detached(priority: .utility) { () -> SaveOutcome in
                do {
                    guard try file.write(pending, generation: generation) else { return .superseded }
                    file.backupIfDue()
                    return .wrote
                } catch {
                    return .failed(error.localizedDescription)
                }
            }.value
            self?.recordSave(outcome)
        }
    }

    /// Writes at once, for backgrounding and quit — points where the debounce
    /// would never get to fire and the last edit would be lost. Synchronous on
    /// purpose: at quit the ordering genuinely matters.
    func saveNow() {
        guard let file, !isSaveBlocked else { return }
        saveTask?.cancel()
        saveTask = nil
        do {
            let wrote = try file.write(snapshot, generation: file.nextWriteGeneration())
            recordSave(wrote ? .wrote : .superseded)
        } catch {
            recordSave(.failed(error.localizedDescription))
        }
    }

    private func recordSave(_ outcome: SaveOutcome) {
        switch outcome {
        case .wrote:
            lastSavedAt = .now
            if case .save = lastError { lastError = nil }
        case .superseded:
            // A newer save reached the disk first and stamped the time itself.
            break
        case .failed(let message):
            lastError = .save(message: message)
        }
    }

    /// Clears the last failure without changing anything else — the status bar
    /// and the alert both offer it.
    func dismissError() {
        lastError = nil
    }

    /// The user has been told their board could not be read and has chosen to
    /// carry on with the fresh one.
    ///
    /// When saving was blocked, the unreadable file is still sitting at the
    /// board's URL and is the only copy of their work, so acknowledging does
    /// not simply unblock: it tries once more to get the file out of the way —
    /// whatever stopped the move at launch may be over — and keeps saving
    /// blocked, loudly, if it still cannot.
    func acknowledgeLoadFailure() {
        defer {
            loadFailure = nil
            if case .load = lastError { lastError = nil }
        }
        guard isSaveBlocked, let file else {
            isSaveBlocked = false
            return
        }
        switch file.rescueUnreadable(reason: quarantineReason) {
        case .nothingToRescue, .preserved:
            isSaveBlocked = false
        case .failed:
            lastError = .save(message: String(
                localized: "Your board file could not be moved aside, so saving stays paused rather than writing over it.",
                comment: "Status shown when the damaged board file still cannot be protected and saving stays off"
            ))
        }
    }

    /// What to call the file being set aside, so the name says what was wrong
    /// with it — the same names `load()` uses.
    private var quarantineReason: String {
        switch loadFailure {
        case .newerVersion(let version, _): "from-newer-version-\(version)"
        case .unreadable, nil: "corrupt"
        }
    }

    func setAccentTheme(_ theme: AccentTheme) {
        guard theme != accentTheme else { return }
        accentTheme = theme
        scheduleSave()
    }

    #if DEBUG
    /// Opens a surface straight from a launch argument, so the sheet, drawer and
    /// individual tabs can be driven from `simctl launch` or a UI test without
    /// scripting taps. The sheet takes either a task's `code` or its UUID:
    ///
    ///     xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanOpenSheet NW-118
    ///     xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanOpenDrawer YES
    ///     xcrun simctl launch <device> com.simplekanban.SimpleKanban -SimpleKanbanTab search
    private func applyLaunchOverrides() {
        let defaults = UserDefaults.standard
        if let identifier = defaults.string(forKey: "SimpleKanbanOpenSheet"),
           let task = task(matching: identifier) {
            sheetID = task.id
        }
        if defaults.bool(forKey: "SimpleKanbanOpenDrawer") {
            isNavDrawerOpen = true
        }
        if let raw = defaults.string(forKey: "SimpleKanbanTab"), let parsed = PhoneTab(rawValue: raw) {
            tab = parsed
        }
    }

    /// Resolves a task from a UUID string or its human code ("NW-118"), which
    /// is the half of the pair anyone typing a launch argument will reach for.
    private func task(matching identifier: String) -> TaskItem? {
        let needle = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uuid = UUID(uuidString: needle), let task = self[uuid] { return task }
        return tasks.first { $0.code.compare(needle, options: .caseInsensitive) == .orderedSame }
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

    /// Tasks matching the current search query. An empty query matches
    /// everything; otherwise every whitespace-separated token must appear
    /// somewhere in the task, so "drag columns" finds a title that has the two
    /// words apart.
    var visibleTasks: [TaskItem] {
        let tokens = searchTokens
        guard !tokens.isEmpty else { return tasks }
        return tasks.filter { task in
            let haystack = haystack(for: task)
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    /// `visibleTasks` grouped by column.
    ///
    /// Every column asks for its own slice, so without this the board filtered
    /// itself once per column. The cache is keyed on the board's revision and
    /// the query; `tasks` is read on the cached path too, because a view that
    /// only ever hit the cache would otherwise never register a dependency on
    /// the board and would stop re-rendering.
    var visibleTasksByColumn: [BoardColumn.ID: [TaskItem]] {
        let key = GroupingKey(query: query, count: tasks.count, revision: boardRevision)
        if let cached = groupedCache, cached.key == key { return cached.groups }
        let groups = Dictionary(grouping: visibleTasks, by: \.columnID)
        groupedCache = (key, groups)
        return groups
    }

    func visibleTasks(in columnID: BoardColumn.ID) -> [TaskItem] {
        visibleTasksByColumn[columnID] ?? []
    }

    private struct GroupingKey: Hashable {
        var query: String
        var count: Int
        var revision: Int
    }

    @ObservationIgnored private var groupedCache: (key: GroupingKey, groups: [BoardColumn.ID: [TaskItem]])?

    /// The query, folded the same way the haystacks are and split into tokens.
    private var searchTokens: [String] {
        query
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    /// Folding a task's text is the expensive part of a search, and a keystroke
    /// re-filters the whole board, so the folded text is kept per task.
    ///
    /// The stamp is `markChanged`'s counter rather than `updatedAt`: `Date.now`
    /// is coarser than the gap between two consecutive mutations, so two edits
    /// can land on the same instant and a memo keyed on it would go on serving
    /// the first one's text. `updatedAt` stays what it is for — the field the
    /// detail surfaces show and saved views sort on.
    @ObservationIgnored private var haystacks: [TaskItem.ID: (stamp: Int, haystack: String)] = [:]

    private func haystack(for task: TaskItem) -> String {
        let stamp = taskRevisions[task.id] ?? 0
        if let cached = haystacks[task.id], cached.stamp == stamp { return cached.haystack }
        let folded = task.searchHaystack
        haystacks[task.id] = (stamp, folded)
        return folded
    }

    // MARK: - Counts

    var totalCount: Int { tasks.count }

    /// Today is passed in rather than read from the clock so the count changes
    /// when the day rolls over under a running app.
    func todayCount(today: CalendarDay) -> Int {
        tasks.filter { $0.isDueToday(today) && $0.columnID != BoardColumn.done.id }.count
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
    /// A drop on the column the card is already in, aimed at no particular
    /// card, is aimed at where the card already is: it does nothing rather than
    /// sending the card to the bottom of its own column.
    ///
    /// Moving into Done ticks off any outstanding sub-tasks, matching the spec.
    func move(_ id: TaskItem.ID, to columnID: BoardColumn.ID, before beforeID: TaskItem.ID? = nil) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        // A card dropped on itself has nothing to sit in front of.
        let target = beforeID == id ? nil : beforeID
        guard tasks[index].columnID != columnID || target != nil else {
            draggingID = nil
            dropTargetColumnID = nil
            return
        }

        var moved = tasks.remove(at: index)
        let wasElsewhere = moved.columnID != columnID
        moved.columnID = columnID
        if columnID == BoardColumn.done.id, wasElsewhere {
            let outstanding = moved.subtasks.count { !$0.done }
            if outstanding > 0 {
                moved.subtasks = moved.subtasks.map { var s = $0; s.done = true; return s }
                moved.activity.insert(ActivityEntry(.subtasksCompletedOnDone(count: outstanding)), at: 0)
            }
        }
        if wasElsewhere, let column = BoardColumn.column(id: columnID) {
            moved.activity.insert(
                ActivityEntry(.moved(columnID: column.id, columnName: column.name)), at: 0
            )
        }
        moved.updatedAt = .now
        markChanged(moved.id)

        if let target, let insertion = tasks.firstIndex(where: { $0.id == target }) {
            tasks.insert(moved, at: insertion)
        } else {
            tasks.append(moved)
        }

        draggingID = nil
        dropTargetColumnID = nil
        scheduleSave()
    }

    // MARK: - Creating

    /// Adds a task and focuses it: the macOS build selects it in the inspector,
    /// the iOS build opens its detail sheet.
    @discardableResult
    func addTask(
        to columnID: BoardColumn.ID,
        title: String,
        fromPhone: Bool = false,
        log kind: ActivityEntry.Kind = .created
    ) -> TaskItem.ID {
        let task = TaskItem(
            code: BoardSnapshot.code(forSerial: nextSerial),
            columnID: columnID,
            title: title,
            priority: .medium,
            activity: [ActivityEntry(kind)]
        )
        nextSerial += 1
        tasks.append(task)

        pendingTitleFocusID = title.isEmpty ? task.id : nil
        draft = ""
        addingColumnID = nil
        if fromPhone {
            sheetID = task.id
        } else {
            selectedID = task.id
        }
        scheduleSave()
        return task.id
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

    // MARK: - Editing

    /// Mutates a task in place, optionally recording an activity entry. The feed
    /// reads newest first, so entries go on the front.
    private func update(_ id: TaskItem.ID, log kind: ActivityEntry.Kind? = nil, _ mutate: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tasks[index])
        touch(index)
        if let kind {
            tasks[index].activity.insert(ActivityEntry(kind), at: 0)
        }
        scheduleSave()
    }

    /// Marks a task changed: 3.3's timestamp and the monotonic stamp the search
    /// memo keys on, together, so no mutation can bump one and forget the other.
    private func touch(_ index: Int) {
        tasks[index].updatedAt = .now
        markChanged(tasks[index].id)
    }

    private func markChanged(_ id: TaskItem.ID) {
        revisionCounter &+= 1
        taskRevisions[id] = revisionCounter
    }

    @ObservationIgnored private var taskRevisions: [TaskItem.ID: Int] = [:]
    @ObservationIgnored private var revisionCounter: Int = 0

    /// The text fields only. `due` and `priority` are edited as sessions too,
    /// but through their own pickers.
    func text(_ field: TaskField, on id: TaskItem.ID) -> String {
        guard let task = self[id] else { return "" }
        switch field {
        case .title: return task.title
        case .note: return task.note
        case .due, .priority: return ""
        }
    }

    func setText(_ value: String, field: TaskField, on id: TaskItem.ID) {
        update(id) { task in
            switch field {
            case .title: task.title = value
            case .note: task.note = value
            case .due, .priority: break
            }
        }
    }

    /// Records the value a field held when the session began. A session this
    /// surface already has open is left as it is: its before-value is the one
    /// the eventual entry has to be measured against.
    func beginEditing(_ field: TaskField, on id: TaskItem.ID, scope: DetailScope) {
        let key = EditKey(scope: scope, task: id, field: field)
        guard editSessions[key] == nil else { return }
        editSessions[key] = Session(before: value(field, on: id))
    }

    /// Ends an editing session: a title emptied to nothing is restored, and a
    /// value that actually changed gets a single activity entry naming what it
    /// finished as — one entry for a title typed a letter at a time, and one
    /// for three dates tried in the calendar before settling on the fourth.
    func endEditing(_ field: TaskField, on id: TaskItem.ID, scope: DetailScope) {
        guard let session = editSessions.removeValue(forKey: EditKey(scope: scope, task: id, field: field))
        else { return }
        let after = value(field, on: id)

        if field == .title, case .text(let title) = after,
           title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // A card with no title is unreachable on the board, so put it back.
            if case .text(let previous) = session.before, !previous.isEmpty {
                setText(previous, field: .title, on: id)
            }
            return
        }

        // A picker session wrote its entry as the value changed, so ending it is
        // only ever about that entry: keep it, or take it back when the value
        // wandered and came home to where it started.
        if let entryID = session.entryID {
            if after == session.before {
                update(id) { $0.activity.removeAll { $0.id == entryID } }
            }
            return
        }
        guard after != session.before else { return }

        switch (field, session.before) {
        case (.title, .text(let previous)):
            // Naming a task that was created untitled is what "Created" already says.
            guard !previous.isEmpty else { return }
            update(id, log: .renamed) { _ in }
        case (.note, .text(let previous)):
            update(id, log: previous.isEmpty ? .descriptionAdded : .descriptionUpdated) { _ in }
        default:
            // `due` and `priority` are recorded by the change itself.
            break
        }
    }

    /// Whether *this surface* has a session open on this field. Scoped on
    /// purpose: an inspector session must not silence the sheet's change to the
    /// same task, which is the whole reason the sessions are keyed by surface.
    func isEditing(_ field: TaskField, on id: TaskItem.ID, scope: DetailScope) -> Bool {
        editSessions[EditKey(scope: scope, task: id, field: field)] != nil
    }

    /// Ends every session a surface left behind when it moved to another task.
    /// Ending rather than dropping: an abandoned title emptied to nothing still
    /// has to be put back, and an abandoned picker entry still has to be
    /// measured against where the value started.
    private func endSessions(in scope: DetailScope, awayFrom id: TaskItem.ID?) {
        for key in Array(editSessions.keys) where key.scope == scope && key.task != id {
            endEditing(key.field, on: key.task, scope: key.scope)
        }
    }

    private func value(_ field: TaskField, on id: TaskItem.ID) -> FieldValue {
        let task = self[id]
        switch field {
        case .title: return .text(task?.title ?? "")
        case .note: return .text(task?.note ?? "")
        case .due: return .day(task?.due)
        case .priority: return .priority(task?.priority ?? .medium)
        }
    }

    /// `scope` is the surface the change came from, so its own open session can
    /// be found. `nil` means no session — log it and be done.
    func setPriority(_ priority: Priority, on id: TaskItem.ID, scope: DetailScope? = nil) {
        guard let current = self[id], current.priority != priority else { return }
        record(.prioritySet(priority), for: .priority, on: id, scope: scope) { $0.priority = priority }
    }

    /// Sets or clears the due date. A due date is a calendar day, so there is
    /// nothing to normalise: the day the user picked is the day stored.
    func setDue(_ day: CalendarDay?, on id: TaskItem.ID, scope: DetailScope? = nil) {
        guard let current = self[id], current.due != day else { return }
        record(day.map { .dueSet($0) } ?? .dueCleared, for: .due, on: id, scope: scope) { $0.due = day }
    }

    /// Applies a picker change and records it.
    ///
    /// With no session open on that surface the entry is logged at once. With
    /// one open the change is *still* recorded — the session's own entry is
    /// rewritten in place, so four dates tried leave one line, and a surface
    /// that walks away without ending its session leaves the change on the
    /// record rather than erasing it.
    private func record(
        _ kind: ActivityEntry.Kind,
        for field: TaskField,
        on id: TaskItem.ID,
        scope: DetailScope?,
        _ mutate: (inout TaskItem) -> Void
    ) {
        guard let key = scope.map({ EditKey(scope: $0, task: id, field: field) }),
              var session = editSessions[key]
        else {
            update(id, log: kind, mutate)
            return
        }
        let entryID = session.entryID ?? ActivityEntry.ID()
        session.entryID = entryID
        editSessions[key] = session
        update(id) { task in
            mutate(&task)
            if let index = task.activity.firstIndex(where: { $0.id == entryID }) {
                // The entry now records a change that just happened, so it goes
                // back to the front. Rewriting it where it sat would leave the
                // newest stamp buried under whatever landed mid-session.
                var entry = task.activity.remove(at: index)
                entry.kind = kind
                entry.when = .now
                task.activity.insert(entry, at: 0)
            } else {
                task.activity.insert(ActivityEntry(id: entryID, kind), at: 0)
            }
        }
    }

    // MARK: - Sub-tasks

    @discardableResult
    func addSubtask(to taskID: TaskItem.ID, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        tasks[index].subtasks.append(SubTask(text: trimmed))
        tasks[index].activity.insert(ActivityEntry(.subtaskAdded), at: 0)
        touch(index)
        scheduleSave()
        return true
    }

    /// Adds the sub-task one surface has typed and clears **only** that
    /// surface's draft for that task — the other surface may be mid-sentence.
    func commitSubtaskDraft(for scope: DetailScope, task taskID: TaskItem.ID) {
        let key = DraftKey(scope: scope, task: taskID)
        guard addSubtask(to: taskID, text: subtaskDrafts[key] ?? "") else { return }
        subtaskDrafts[key] = ""
    }

    func toggleSubtask(_ subtaskID: SubTask.ID, on taskID: TaskItem.ID) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskID }),
              let subIndex = tasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID })
        else { return }
        tasks[taskIndex].subtasks[subIndex].done.toggle()
        touch(taskIndex)
        scheduleSave()
    }

    func subtaskDraft(for scope: DetailScope, task: TaskItem.ID) -> String {
        subtaskDrafts[DraftKey(scope: scope, task: task)] ?? ""
    }

    func setSubtaskDraft(_ value: String, for scope: DetailScope, task: TaskItem.ID) {
        subtaskDrafts[DraftKey(scope: scope, task: task)] = value
    }

    // MARK: - Labels

    func toggleLabel(_ key: String, on taskID: TaskItem.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let name = label(forKey: key)?.name ?? key
        if let existing = tasks[index].labelKeys.firstIndex(of: key) {
            tasks[index].labelKeys.remove(at: existing)
            tasks[index].activity.insert(ActivityEntry(.labelRemoved(key: key, name: name)), at: 0)
        } else {
            tasks[index].labelKeys.append(key)
            tasks[index].activity.insert(ActivityEntry(.labelAdded(key: key, name: name)), at: 0)
        }
        touch(index)
        scheduleSave()
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
            tasks[index].activity.insert(ActivityEntry(.labelAdded(key: key, name: trimmed)), at: 0)
            touch(index)
        }
        scheduleSave()
    }

    /// Creates the label one surface has typed and clears only that surface's
    /// draft for that task.
    func commitLabelDraft(for scope: DetailScope, task taskID: TaskItem.ID) {
        let key = DraftKey(scope: scope, task: taskID)
        createLabel(named: labelDrafts[key] ?? "", on: taskID)
        labelDrafts[key] = ""
    }

    func labelDraft(for scope: DetailScope, task: TaskItem.ID) -> String {
        labelDrafts[DraftKey(scope: scope, task: task)] ?? ""
    }

    func setLabelDraft(_ value: String, for scope: DetailScope, task: TaskItem.ID) {
        labelDrafts[DraftKey(scope: scope, task: task)] = value
    }

    func toggleLabelPicker(_ scope: DetailScope, task: TaskItem.ID) {
        labelPickerScope = labelPickerScope == scope ? nil : scope
        labelDrafts[DraftKey(scope: scope, task: task)] = ""
    }

    func closeLabelPicker(_ scope: DetailScope, task: TaskItem.ID) {
        labelPickerScope = nil
        labelDrafts[DraftKey(scope: scope, task: task)] = ""
    }

    // MARK: - Drafts

    /// Everything transient a task owns. Called when the task goes away, so a
    /// half-typed sub-task cannot outlive it and land on whatever is selected
    /// next.
    func clearDrafts(for id: TaskItem.ID) {
        subtaskDrafts = subtaskDrafts.filter { $0.key.task != id }
        labelDrafts = labelDrafts.filter { $0.key.task != id }
        editSessions = editSessions.filter { $0.key.task != id }
        haystacks[id] = nil
        taskRevisions[id] = nil
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
        case .board: visibleTasks(in: mobileColumnID)
        case .inbox: visibleTasks(in: BoardColumn.inbox.id)
        case .search: visibleTasks
        }
    }

    /// The dashed "add here" row is hidden while searching.
    var showsMobileAddRow: Bool { tab != .search }

    /// The floating "+" button: jump to Inbox and start a new capture there.
    ///
    /// The task is created untitled and its sheet opens with the title field
    /// focused, so the capture is finished by typing rather than by editing a
    /// placeholder afterwards.
    func quickCapture() {
        tab = .inbox
        addTask(to: BoardColumn.inbox.id, title: "", fromPhone: true, log: .captured)
    }

    func addTaskToCurrentMobileColumn() {
        addTask(to: mobileAddColumnID, title: "", fromPhone: true)
    }
}

/// What a save did, which is not always what it was asked to do: a write that
/// was overtaken while it waited out the debounce is dropped, and the store
/// must not then tell the user their board was saved.
private enum SaveOutcome: Sendable {
    case wrote
    case superseded
    case failed(String)
}
