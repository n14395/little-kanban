import AppIntents
import CoreSpotlight
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Deep links

/// How a task is named from outside the app: `simplekanban://task/<uuid>`.
///
/// The uuid is `TaskItem.id` and not `code`. A code is a label — it is minted
/// from a board's prefix, it is not unique across installs, and it is the half
/// of the pair a user retypes; the id is the key, which is the whole reason
/// item 3.7 moved ids to UUIDs before anything could link to one.
enum TaskLink {
    static let scheme = "simplekanban"
    static let host = "task"

    /// The activity type Handoff and Spotlight both carry. Declared in
    /// `project.yml` under `NSUserActivityTypes`.
    static let activityType = "com.n14395.SimpleKanban.task"

    /// Where every incoming link lands, whichever door it came through — a
    /// pasted URL, a tapped notification, a Handoff, a Spotlight result.
    @MainActor static let router = DeepLinkRouter()

    static func url(for id: TaskItem.ID) -> URL {
        URL(string: "\(scheme)://\(host)/\(id.uuidString.lowercased())")
            ?? URL(filePath: "/")
    }

    /// Puts a task's link on the pasteboard, which is the only thing the app
    /// can do with a `simplekanban://` URL that helps: the link is for pasting
    /// into a note, a commit message or another app, and nothing else here
    /// consumes one. ⌘C already copies the card itself, so this is a separate
    /// verb rather than a second representation on the same copy.
    @MainActor static func copyToPasteboard(_ id: TaskItem.ID) {
        let text = url(for: id).absoluteString
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// The task a URL names, or `nil` when it names nothing this app knows how
    /// to open. Deliberately strict about the shape: a link that is not one of
    /// ours is not silently treated as a task that has gone away.
    static func taskID(in url: URL) -> TaskItem.ID? {
        guard url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame,
              url.host()?.caseInsensitiveCompare(host) == .orderedSame
        else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}

/// Why a link could not be opened, in the two sentences the alert shows.
///
/// A link that names nothing has to *say so*. Doing nothing is the worst
/// available answer: from the outside it is indistinguishable from the app
/// having failed to launch, and the user is left re-clicking it.
struct DeepLinkFailure: Identifiable, Hashable, Sendable {
    let id = UUID()
    var title: String
    var message: String
}

/// Holds an incoming link until there is a board to resolve it against, then
/// puts the task on screen.
///
/// A queue of one rather than a call, because the link can arrive before the
/// scene exists: a notification tapped from the lock screen launches the app,
/// and the delegate runs while the window is still being built.
@MainActor
@Observable
final class DeepLinkRouter {
    /// Bumped by every arrival. Watched rather than `pending` itself, so the
    /// same link twice is still two openings.
    private(set) var arrivals = 0
    private(set) var failure: DeepLinkFailure?

    /// What an opened *file* did, which is a different sentence from a link
    /// that went nowhere: the board has changed, and an import that changed
    /// nothing has to say so or it is indistinguishable from a bug. Shares the
    /// vocabulary Settings ▸ Import already reports in.
    private(set) var notice: SettingsNotice?

    @ObservationIgnored private var pending: URL?

    func open(_ url: URL) {
        pending = url
        arrivals &+= 1
    }

    func dismissFailure() { failure = nil }

    func dismissNotice() { notice = nil }

    /// Takes whatever is waiting and shows it. Safe to call at any time — with
    /// nothing waiting it does nothing, which is what lets the view call it both
    /// on arrival and once when it appears.
    func resolve(in store: BoardStore) {
        guard let url = pending else { return }
        pending = nil
        // The bundle claims `.simplekanban` as its own document type, so the
        // system will hand one over from the Finder or from Files whether or
        // not anything here is ready for it. Without this branch the user's own
        // board file arrives at the code below and is told it is not a task
        // link, which is the worst of both answers.
        if url.isFileURL {
            importFile(at: url, in: store)
            return
        }
        guard let id = TaskLink.taskID(in: url) else {
            failure = DeepLinkFailure(
                title: String(localized: "That link is not a Simple Kanban task.",
                              comment: "Alert title for a URL the app cannot interpret"),
                message: String(localized: "Task links look like simplekanban://task/ followed by the task's identifier.",
                                comment: "Alert body explaining the shape of a task link")
            )
            return
        }
        guard let task = store[id] else {
            failure = DeepLinkFailure(
                title: String(localized: "That task no longer exists.",
                              comment: "Alert title for a link to a task that has been deleted"),
                message: String(localized: "It may have been deleted, or it may be on a copy of the board this device does not have.",
                                comment: "Alert body for a link to a task that has been deleted")
            )
            return
        }
        reveal(task, in: store)
    }

    /// Merges an opened board file, which is the same act as Settings ▸ Import
    /// and reports the same way. Merged rather than adopted: "open" must not
    /// mean "replace everything you have", and one ⌘Z takes it back.
    private func importFile(at url: URL, in store: BoardStore) {
        notice = .importing(url, into: store)
    }

    /// Puts a task in front of the user on whichever surface is showing. The
    /// search is cleared first: a link that lands on a board filtered to
    /// something the task does not match would open onto an empty column, which
    /// reads as the link having failed.
    ///
    /// Every detail surface the app has is raised, rather than the one this
    /// platform was assumed to have. The `#if os(iOS)` here used to set only the
    /// phone's — its column, its tab, its sheet — so a `simplekanban://` link, a
    /// notification tap, a Handoff or a Spotlight hit selected the task on an
    /// iPad and then showed nothing at all whenever the inspector was closed.
    /// The two do not collide: the phone has no inspector to open, the iPad
    /// presents no sheet, and each surface reads the one piece of state it has.
    private func reveal(_ task: TaskItem, in store: BoardStore) {
        store.clearQuery()
        if task.isArchived {
            store.activeView = .archive
        } else if let boardID = task.boardID {
            store.selectBoard(boardID)
        } else {
            store.selectSurface(.inbox)
        }
        store.select(task.id)
        // The desk and the iPad: the panel beside the board.
        store.isInspectorOpen = true
        #if os(iOS)
        // And the phone: the column the pager is on, the tab under it, and the
        // sheet. `selectTab` also sets `surface`, which is what the iPad's
        // detail pane reads, so the two agree about where the user is.
        if let columnID = task.columnID, !task.isArchived { store.mobileColumnID = columnID }
        if !task.isArchived { store.selectTab(task.isUnfiled ? .inbox : .board) }
        store.isNavDrawerOpen = false
        store.sheetID = task.id
        #endif
    }
}

extension View {
    /// Every way into the app from outside it: a `simplekanban://` URL, a
    /// notification the user tapped, a Handoff from the other platform, and a
    /// Spotlight result. One modifier because they all mean the same thing —
    /// open this task — and a link that names nothing must say so on all four.
    func systemEntryPoints() -> some View {
        modifier(SystemEntryPoints())
    }

    /// Publishes the open task for Handoff and Spotlight. Attach it to whatever
    /// is showing a task: the macOS inspector and the iOS detail sheet.
    func taskUserActivity(_ task: TaskItem, isActive: Bool = true) -> some View {
        userActivity(TaskLink.activityType, isActive: isActive) { activity in
            activity.title = task.displayTitle
            activity.userInfo = ["taskID": task.id.uuidString]
            activity.webpageURL = nil
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.targetContentIdentifier = TaskLink.url(for: task.id).absoluteString
        }
    }
}

private struct SystemEntryPoints: ViewModifier {
    @Environment(BoardStore.self) private var store

    private var router: DeepLinkRouter { TaskLink.router }

    func body(content: Content) -> some View {
        content
            .onOpenURL { router.open($0) }
            .onContinueUserActivity(TaskLink.activityType) { activity in
                guard let raw = activity.userInfo?["taskID"] as? String,
                      let id = UUID(uuidString: raw) else { return }
                router.open(TaskLink.url(for: id))
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let id = UUID(uuidString: raw) else { return }
                router.open(TaskLink.url(for: id))
            }
            .onChange(of: router.arrivals) { _, _ in router.resolve(in: store) }
            // A link that launched the app arrived before this view existed.
            .task { router.resolve(in: store) }
            .alert(
                router.failure?.title ?? "",
                isPresented: Binding(
                    get: { router.failure != nil },
                    set: { if !$0 { router.dismissFailure() } }
                ),
                presenting: router.failure
            ) { _ in
                Button { router.dismissFailure() } label: {
                    Text("OK", comment: "Dismisses the alert about a link that could not be opened")
                }
            } message: { failure in
                Text(failure.message)
            }
            // A second alert rather than one channel: the two are mutually
            // exclusive by construction — a URL is either a link or a file —
            // and folding "Board imported." into a type called
            // `DeepLinkFailure` would be the kind of tidy that reads as a bug.
            .alert(
                router.notice?.title ?? "",
                isPresented: Binding(
                    get: { router.notice != nil },
                    set: { if !$0 { router.dismissNotice() } }
                ),
                presenting: router.notice
            ) { _ in
                Button { router.dismissNotice() } label: {
                    Text("OK", comment: "Dismisses the alert confirming an imported board")
                }
            } message: { notice in
                Text(notice.message)
            }
    }
}

// MARK: - Spotlight

/// Keeps the system's index in step with the board, so a task is findable from
/// Spotlight without the app being open.
///
/// Driven by `updatedAt` (item 3.3): an item is re-indexed when its stamp moves
/// and left alone otherwise, which is what keeps a per-keystroke reconcile from
/// pushing the whole board at the index on every character typed.
@MainActor
@Observable
final class TaskSpotlightIndex {
    static let shared = TaskSpotlightIndex()

    @ObservationIgnored private var indexed: [UUID: Date] = [:]
    /// Whether this launch has published anything yet. The map above does not
    /// survive a quit but the system's index does, so the first reconcile of a
    /// session cannot know what is already in there — an item left behind by a
    /// build that crashed, or by a board file that changed while the app was
    /// not running, would sit in Spotlight forever with nothing able to name
    /// it. Clearing once and writing the whole board back costs one pass a
    /// launch and makes the index exactly the board.
    @ObservationIgnored private var hasPublished = false

    /// The whole board, every time. The diff is this object's job — see
    /// `NotificationScheduler.reconcile` for why the caller does not do it.
    func reconcile(_ tasks: [TaskItem]) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        if !hasPublished {
            hasPublished = true
            CSSearchableIndex.default().deleteAllSearchableItems()
        }
        var next: [UUID: Date] = [:]
        var changed: [CSSearchableItem] = []
        for task in tasks where !task.isArchived {
            next[task.id] = task.updatedAt
            guard indexed[task.id] != task.updatedAt else { continue }
            changed.append(item(for: task))
        }
        let gone = indexed.keys.filter { next[$0] == nil }
        indexed = next

        let index = CSSearchableIndex.default()
        if !gone.isEmpty {
            index.deleteSearchableItems(withIdentifiers: gone.map(\.uuidString))
        }
        if !changed.isEmpty {
            index.indexSearchableItems(changed)
        }
    }

    private func item(for task: TaskItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = task.displayTitle
        attributes.contentDescription = task.note.isEmpty ? task.code : "\(task.code) — \(task.note)"
        attributes.keywords = [task.code] + task.labelKeys
        attributes.dueDate = task.due?.date()
        attributes.contentURL = TaskLink.url(for: task.id)
        return CSSearchableItem(
            uniqueIdentifier: task.id.uuidString,
            domainIdentifier: TaskLink.host,
            attributeSet: attributes
        )
    }
}

// MARK: - App Intents

/// How an intent reaches the board.
///
/// An intent can run in a process the user never brought to the front, so it
/// cannot wait for a view to hand it anything: the app registers its store as
/// it is built, before any scene exists. There is exactly one store in this app
/// — see `SimpleKanbanApp` — and making a second one here would give the
/// intent a board of its own to write over the real one with.
@MainActor
enum TaskIntentBridge {
    private(set) static var store: BoardStore?

    static func adopt(_ store: BoardStore) { Self.store = store }

    static func require() throws -> BoardStore {
        guard let store else { throw TaskIntentError.notReady }
        return store
    }
}

enum TaskIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case noSuchColumn

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady:
            LocalizedStringResource("Simple Kanban is still starting up. Try again in a moment.",
                                    comment: "Shortcuts error: the app has not finished launching")
        case .noSuchColumn:
            LocalizedStringResource("That column is not on this board any more.",
                                    comment: "Shortcuts error: the named column has been deleted")
        }
    }
}

/// A board, as Shortcuts sees it.
struct BoardEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Board", comment: "What a board is called in the Shortcuts editor")
    )
    static let defaultQuery = BoardEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct BoardEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [BoardEntity] {
        let wanted = Set(identifiers)
        return await MainActor.run {
            (TaskIntentBridge.store?.boards ?? [])
                .filter { wanted.contains($0.id) }
                .map { BoardEntity(id: $0.id, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [BoardEntity] {
        await MainActor.run {
            (TaskIntentBridge.store?.boards ?? []).map { BoardEntity(id: $0.id, name: $0.name) }
        }
    }
}

/// A column, named with its board so two "Done"s are told apart in a picker
/// that shows nothing else about them.
struct ColumnEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Column", comment: "What a board column is called in the Shortcuts editor")
    )
    static let defaultQuery = ColumnEntityQuery()

    var id: UUID
    var name: String
    var boardName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(boardName)")
    }
}

struct ColumnEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ColumnEntity] {
        let wanted = Set(identifiers)
        return await MainActor.run { Self.all().filter { wanted.contains($0.id) } }
    }

    func suggestedEntities() async throws -> [ColumnEntity] {
        await MainActor.run { Self.all() }
    }

    @MainActor
    private static func all() -> [ColumnEntity] {
        (TaskIntentBridge.store?.boards ?? []).flatMap { board in
            board.columns.map { ColumnEntity(id: $0.id, name: $0.name, boardName: board.name) }
        }
    }
}

/// Shortcuts, Siri and the Spotlight action row, from one implementation.
///
/// With no destination given the task lands in the Inbox, which is what the
/// app's own quick capture does: a capture that had to pick a board first would
/// not be a capture.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription(
        "Adds a task to Simple Kanban. With no column given it goes to the Inbox."
    )
    /// The board is written whether or not anything is on screen, so there is
    /// no reason to take the user out of what they were doing.
    static let openAppWhenRun = false

    @Parameter(title: "Title", requestValueDialog: "What is the task?")
    var taskTitle: String

    @Parameter(title: "Board")
    var board: BoardEntity?

    @Parameter(title: "Column")
    var column: ColumnEntity?

    @Parameter(title: "Due")
    var due: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$taskTitle) to Simple Kanban") {
            \.$board
            \.$column
            \.$due
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = try TaskIntentBridge.require()
        let id = store.addTask(to: try placement(in: store), title: taskTitle)
        if let due, let task = store[id] {
            store.setDue(CalendarDay(due), on: task.id)
        }
        let code = store[id]?.code ?? ""
        return .result(value: code, dialog: "Added \(code).")
    }

    /// Where the task goes: the column if one was named, else the board's
    /// landing column, else the Inbox.
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

/// Opens the Today view — the saved view item 4.1 built, which is the answer to
/// "what am I meant to be doing".
struct ShowTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Today"
    static let description = IntentDescription("Opens the Today view in Simple Kanban.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = try TaskIntentBridge.require()
        store.clearQuery()
        store.activeView = .today
        #if os(iOS)
        store.isNavDrawerOpen = false
        store.sheetID = nil
        #endif
        return .result()
    }
}

struct SimpleKanbanShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppIntents.AppShortcut] {
        AppIntents.AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "New \(.applicationName) task"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.rectangle.on.rectangle"
        )
        AppIntents.AppShortcut(
            intent: ShowTodayIntent(),
            phrases: [
                "Show today in \(.applicationName)",
                "What is due today in \(.applicationName)"
            ],
            shortTitle: "Show Today",
            systemImageName: "sun.max"
        )
    }
}
