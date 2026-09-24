// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

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

/// How a task is named from outside the app: `littlekanban://task/<uuid>`.
///
/// The uuid is `TaskItem.id` and not `code`. A code is a label — it is minted
/// from a board's prefix, it is not unique across installs, and it is the half
/// of the pair a user retypes; the id is the key, which is the whole reason
/// item 3.7 moved ids to UUIDs before anything could link to one.
enum TaskLink {
    /// The vocabulary itself lives in ``AppLink``, which the widget extension
    /// shares: a task link is one of six shapes now, and the process that
    /// *writes* four of them is not this one. These two are kept because the
    /// Spotlight index names a domain with the second and a good deal of the
    /// app names the first.
    static let scheme = AppLink.scheme
    static let host = "task"

    /// The activity type Handoff and Spotlight both carry. Declared in
    /// `project.yml` under `NSUserActivityTypes`.
    static let activityType = "com.n14395.LittleKanban.task"

    /// Where every incoming link lands, whichever door it came through — a
    /// pasted URL, a tapped notification, a Handoff, a Spotlight result.
    @MainActor static let router = DeepLinkRouter()

    static func url(for id: TaskItem.ID) -> URL { AppLink.url(.task(id)) }

    /// Puts a task's link on the pasteboard, which is the only thing the app
    /// can do with a `littlekanban://` URL that helps: the link is for pasting
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
        guard case .task(let id)? = AppLink.destination(of: url) else { return nil }
        return id
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
        // The bundle claims `.littlekanban` as its own document type, so the
        // system will hand one over from the Finder or from Files whether or
        // not anything here is ready for it. Without this branch the user's own
        // board file arrives at the code below and is told it is not a task
        // link, which is the worst of both answers.
        if url.isFileURL {
            importFile(at: url, in: store)
            return
        }
        guard let destination = AppLink.destination(of: url) else {
            failure = DeepLinkFailure(
                title: String(localized: "Little Kanban cannot open that link.",
                              comment: "Alert title for a URL the app cannot interpret"),
                message: String(localized: "Its links name a task, a board, a column, a view or the Inbox — a task link looks like littlekanban://task/ followed by the task's identifier.",
                                comment: "Alert body explaining the shapes of link the app understands")
            )
            return
        }
        open(destination, in: store)
    }

    /// One arm per shape of link. Each either puts something on screen or says
    /// why it cannot — there is no third answer, for ``DeepLinkFailure``'s
    /// reason: a link that silently does nothing is indistinguishable from an
    /// app that failed to launch.
    ///
    /// The four that a widget writes name things the user can rename, move and
    /// delete while the widget goes on naming them, so each has its own "that
    /// is gone" sentence rather than a shared one. "That view no longer exists"
    /// tells somebody which widget to fix; "something went wrong" does not.
    private func open(_ destination: AppLink.Destination, in store: BoardStore) {
        switch destination {
        case .task(let id):
            guard let task = store[id] else {
                failure = DeepLinkFailure(
                    title: String(localized: "That task no longer exists.",
                                  comment: "Alert title for a link to a task that has been deleted"),
                    message: String(localized: "It may have been deleted, or it may be on a copy of the board this device does not have.",
                                    comment: "Alert body for a link to a task that has been deleted")
                )
                return
            }
            store.reveal(task.id)

        case .board(let id):
            guard store.board(id: id) != nil else {
                failure = DeepLinkFailure(
                    title: String(localized: "That board no longer exists.",
                                  comment: "Alert title for a link to a board that has been deleted"),
                    message: String(localized: "It may have been deleted, or it may be on a copy of the board file this device does not have.",
                                    comment: "Alert body for a link to a board that has been deleted")
                )
                return
            }
            store.clearQuery()
            store.selectBoard(id)

        case .column(let id):
            // Resolved to its board rather than taken on trust, because a
            // column is what a widget was configured with and a column can be
            // moved to another board after the fact. Landing on the board it is
            // on *now* is the answer that stays right.
            guard let owner = store.board(ofColumn: id) else {
                failure = DeepLinkFailure(
                    title: String(localized: "That column no longer exists.",
                                  comment: "Alert title for a link to a column that has been deleted"),
                    message: String(localized: "It may have been deleted, or the board it was on may have been.",
                                    comment: "Alert body for a link to a column that has been deleted")
                )
                return
            }
            store.clearQuery()
            store.selectBoard(owner.id)

        case .view(let id):
            guard store.views.contains(where: { $0.id == id }) else {
                failure = DeepLinkFailure(
                    title: String(localized: "That view no longer exists.",
                                  comment: "Alert title for a link to a saved view that has been deleted"),
                    message: String(localized: "Saved views can be deleted, and a widget goes on naming the one it was set up with.",
                                    comment: "Alert body for a link to a saved view that has been deleted")
                )
                return
            }
            store.clearQuery()
            store.surface = .view(id)
            #if os(iOS)
            store.isNavDrawerOpen = false
            #endif

        case .inbox:
            store.clearQuery()
            store.showInbox()
            #if os(iOS)
            store.isNavDrawerOpen = false
            #endif

        case .newTask:
            // **The widget's `+` is the app's own `+`**, and the app's own `+`
            // is a different control on each platform: a one-line composer in
            // the Inbox panel where the Inbox is a panel, and the card's whole
            // editor in a sheet on the phone, where there is no panel to put a
            // composer in. Both put a field on screen with the keyboard in it,
            // which is the entire errand.
            //
            // **Reaching for a third thing is what did not work.** This used to
            // make the card itself and open it in the task editor, which is
            // right on the phone — a presented sheet — and is not a thing the
            // iPad's editor can do: it is a column of the split view, and a
            // `@FocusState` assignment aimed into it is refused outright.
            // Measured on an iPad Pro 11": twenty attempts over a second and a
            // half, the field reporting `nil` focus after every one. The panel
            // came up on the right card with its title empty and no caret, and
            // the first thing typed went nowhere — which is exactly what was
            // reported. Nothing here is clever about it any more; it calls what
            // the toolbar's `+` calls.
            store.clearQuery()
            #if os(iOS)
            store.isNavDrawerOpen = false
            #endif
            if BoardStore.inboxOpensBesideTheBoard {
                store.beginCapturingInInbox()
            } else {
                store.quickCapture()
            }
        }
    }

    /// Merges an opened board file, which is the same act as Settings ▸ Import
    /// and reports the same way. Merged rather than adopted: "open" must not
    /// mean "replace everything you have", and one ⌘Z takes it back.
    private func importFile(at url: URL, in store: BoardStore) {
        notice = .importing(url, into: store)
    }

}

extension View {
    /// Every way into the app from outside it: a `littlekanban://` URL, a
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
/// — see `LittleKanbanApp` — and making a second one here would give the
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
    case noSuchTask
    case noSuchView
    case noSuchLabel
    case cannotComplete

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady:
            LocalizedStringResource("Little Kanban is still starting up. Try again in a moment.",
                                    comment: "Shortcuts error: the app has not finished launching")
        case .noSuchColumn:
            LocalizedStringResource("That column is not on this board any more.",
                                    comment: "Shortcuts error: the named column has been deleted")
        // Each of these names one kind of thing rather than sharing a sentence,
        // for `DeepLinkFailure`'s reason: "that view no longer exists" tells
        // somebody which shortcut to fix, and "something went wrong" does not.
        case .noSuchTask:
            LocalizedStringResource("That task no longer exists.",
                                    comment: "Shortcuts error: the named task has been deleted")
        case .noSuchView:
            LocalizedStringResource("That view no longer exists.",
                                    comment: "Shortcuts error: the named saved view has been deleted")
        case .noSuchLabel:
            LocalizedStringResource("That label no longer exists.",
                                    comment: "Shortcuts error: the named label has been deleted")
        case .cannotComplete:
            LocalizedStringResource("That task cannot be completed — the board it is on has no Done column.",
                                    comment: "Shortcuts error: there is nowhere to complete the task to")
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
        "Adds a task to Little Kanban. With no column given it goes to the Inbox."
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
        Summary("Add \(\.$taskTitle) to Little Kanban") {
            \.$board
            \.$column
            \.$due
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = try TaskIntentBridge.require()
        // Through the non-interactive door — see `addTaskFromIntent` for what
        // the interactive one moves that a background Shortcut must not.
        let id = store.addTaskFromIntent(
            to: try placement(in: store), title: taskTitle, due: due.map { CalendarDay($0) }
        )
        let code = store[id]?.code ?? ""
        // Written before the result is spoken, not on the 500 ms debounce: a
        // Shortcut can run against an app the system background-launched and
        // jetsam-kills moments after the dialog — inside the debounce window,
        // which is the one save an intent has no scene phase to flush. "Added
        // NW-231" followed by no NW-231 at the next launch is the worst
        // sentence this file can produce, and the synchronous write carries
        // the CloudKit push and the reminder/Spotlight followers with it.
        store.saveNow()
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
    static let description = IntentDescription("Opens the Today view in Little Kanban.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = try TaskIntentBridge.require()
        store.clearQuery()
        // By id rather than by case: since v11 the views are rows in the file,
        // and Today is one of them. Somebody who deleted it gets the board,
        // which is the answer that is always available — the intent opens the
        // app either way, which is what "Show Today" mostly means to a user
        // saying it to Siri. Asked, not assumed: a surface parked on a
        // missing id is a window the Mac and the iPad draw nothing at all
        // for, and only the phone happened to fall back.
        let today = SavedView.id(of: .today)
        store.surface = store.view(id: today) != nil ? .view(today) : .board
        #if os(iOS)
        store.isNavDrawerOpen = false
        store.sheetID = nil
        #endif
        return .result()
    }
}

struct LittleKanbanShortcuts: AppShortcutsProvider {
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
        // **Only Complete joins the two above.** Every intent in
        // `TaskActionIntents.swift` is reachable from the Shortcuts editor
        // whether or not it is registered here; what registration buys is a
        // *spoken* phrase, and Move, Find, the setters and the rest all need a
        // card named first, which is not a thing anybody says to Siri. A
        // provider crowded with phrases nobody can complete is a worse Siri
        // than a short one.
        AppIntents.AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "Complete a task in \(.applicationName)",
                "Tick off a \(.applicationName) task"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle"
        )
    }
}
