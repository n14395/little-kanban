// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI
@testable import LittleKanban

// The module name comes from the app's PRODUCT_NAME, "LittleKanban".

/// Anchors `Bundle(for:)` on the test bundle, which is where the fixtures are.
private final class TestBundleAnchor {}

/// A board file in a directory of its own, thrown away with the test.
///
/// Every file-backed test goes through this. `BoardFile.default` is the user's
/// real board: a test that writes there destroys their work, and one that only
/// *reads* it is a test whose result depends on whose machine it runs on.
final class TempBoard: Sendable {
    let directory: URL
    let file: BoardFile

    init(named name: String = "board.json") {
        directory = URL.temporaryDirectory.appending(path: "LittleKanbanTests/\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = BoardFile(url: directory.appending(path: name))
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    var exists: Bool { FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)) }

    func put(_ text: String) throws { try Data(text.utf8).write(to: file.url) }
    func put(_ data: Data) throws { try data.write(to: file.url) }
    func bytes() throws -> Data { try Data(contentsOf: file.url) }
    func text() throws -> String { String(decoding: try bytes(), as: UTF8.self) }
    func snapshot() throws -> BoardSnapshot { try BoardFile.decode(try bytes()).snapshot }

    func modifiedAt() -> Date? {
        try? file.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// What is sitting beside the board — a quarantined copy lands here.
    func siblings() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []).sorted()
    }
}

enum Fixture {
    enum Failure: Error { case missing(String) }

    static func url(_ name: String) throws -> URL {
        guard let url = Bundle(for: TestBundleAnchor.self).url(forResource: name, withExtension: "json") else {
            throw Failure.missing(name)
        }
        return url
    }

    static func data(_ name: String) throws -> Data { try Data(contentsOf: url(name)) }

    /// Every board fixture in the bundle, by name.
    ///
    /// Read off the disk rather than listed in a literal, so a fixture added
    /// for a future version is covered by the chain tests the moment it lands
    /// rather than when somebody remembers to add it to an array.
    static func names() -> [String] {
        let urls = Bundle(for: TestBundleAnchor.self)
            .urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return urls
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0.hasPrefix("board-") }
            .sorted()
    }
}

/// A board written out in literals.
///
/// `SeedData` is derived from `Date.now` and `CalendarDay.today()`, so an
/// assertion about it means something different tomorrow. Nothing here moves.
enum TestBoard {
    /// 2026-08-20 in UTC, give or take — only its fixedness matters.
    static let epoch = Date(timeIntervalSinceReferenceDate: 777_000_000)

    static func at(_ secondsBefore: Int) -> Date { epoch.addingTimeInterval(-Double(secondsBefore)) }

    static func taskID(_ n: UInt8) -> TaskItem.ID {
        UUID(uuid: (0x7E, 0x57, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    static func subtaskID(_ n: UInt8) -> SubTask.ID {
        UUID(uuid: (0x5B, 0x7A, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    static func entryID(_ n: UInt8) -> ActivityEntry.ID {
        UUID(uuid: (0xAC, 0x71, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    static let widget = taskID(1)     // inbox
    static let dragDrop = taskID(2)   // backlog, has sub-tasks and a due date
    static let cafe = taskID(3)       // backlog, for diacritic folding
    static let offline = taskID(4)    // next
    static let sync = taskID(5)       // doing, has been moved once
    static let palette = taskID(6)    // done, was in Up Next before that

    static let lift = subtaskID(1)
    static let dropTargets = subtaskID(2)
    static let keyboard = subtaskID(3)
    static let mutationLog = subtaskID(4)

    static let dueDay = CalendarDay(year: 2026, month: 8, day: 20)
    static let laterDay = CalendarDay(year: 2026, month: 9, day: 1)

    static let tasks: [TaskItem] = [
        TaskItem(
            id: widget, code: "NW-120", columnID: BoardColumn.inbox.id,
            title: "Widget on the home screen",
            note: "Captured from the menu bar.",
            // **Said rather than defaulted**, here and on NW-123 and NW-125.
            // These tasks are the expected side of the migration suites, and
            // the fixtures they are compared against are frozen bytes that
            // carry `Medium` — which is what a card minted before v8 started
            // on. Leaving it to `Priority.default` made the expectation move
            // with today's default and the fixtures stay where they were.
            priority: .medium,
            activity: [ActivityEntry(id: entryID(1), .captured, when: at(600))],
            createdAt: at(600), updatedAt: at(600)
        ),
        TaskItem(
            id: dragDrop, code: "NW-121", columnID: BoardColumn.backlog.id,
            title: "Drag and drop between columns",
            note: "Card follows the pointer with a lifted shadow.",
            labelKeys: ["design", "ios"], due: dueDay, priority: .high,
            subtasks: [
                SubTask(id: lift, text: "Lift and shadow states", done: true),
                SubTask(id: dropTargets, text: "Column drop targets", done: false),
                SubTask(id: keyboard, text: "Keyboard fallback", done: false),
            ],
            activity: [ActivityEntry(id: entryID(2), .created, when: at(7_200))],
            createdAt: at(7_200), updatedAt: at(7_200)
        ),
        TaskItem(
            id: cafe, code: "NW-122", columnID: BoardColumn.backlog.id,
            title: "Café menu polish",
            labelKeys: ["polish"], priority: .low,
            activity: [ActivityEntry(id: entryID(3), .created, when: at(9_000))],
            createdAt: at(9_000), updatedAt: at(9_000)
        ),
        TaskItem(
            id: offline, code: "NW-123", columnID: BoardColumn.upNext.id,
            title: "Offline queue for edits",
            note: "Buffer mutations locally and replay on reconnect.",
            labelKeys: ["api"], due: laterDay, priority: .medium,
            subtasks: [SubTask(id: mutationLog, text: "Mutation log", done: false)],
            activity: [ActivityEntry(id: entryID(4), .created, when: at(12_000))],
            createdAt: at(12_000), updatedAt: at(12_000)
        ),
        TaskItem(
            id: sync, code: "NW-124", columnID: BoardColumn.inProgress.id,
            title: "Sync engine",
            labelKeys: ["api", "bug"], priority: .high,
            activity: [
                ActivityEntry(id: entryID(5), .moved(columnID: BoardColumn.inProgress.id.uuidString, columnName: "In Progress"), when: at(20_000)),
                ActivityEntry(id: entryID(6), .created, when: at(30_000)),
            ],
            createdAt: at(30_000), updatedAt: at(20_000)
        ),
        TaskItem(
            id: palette, code: "NW-125", columnID: BoardColumn.done.id,
            title: "Warm neutral palette",
            labelKeys: ["design"], priority: .medium,
            subtasks: [SubTask(id: subtaskID(5), text: "Palette", done: true)],
            activity: [
                ActivityEntry(id: entryID(7), .moved(columnID: BoardColumn.done.id.uuidString, columnName: "Done"), when: at(40_000)),
                ActivityEntry(id: entryID(8), .moved(columnID: BoardColumn.upNext.id.uuidString, columnName: "Up Next"), when: at(50_000)),
                ActivityEntry(id: entryID(9), .created, when: at(60_000)),
            ],
            createdAt: at(60_000), updatedAt: at(40_000)
        ),
    ]

    /// One activity entry of every kind, for the persistence round-trip. A
    /// `Kind` that stops decoding takes a task's whole history with it.
    static let everyActivityKind: [ActivityEntry.Kind] = [
        .created,
        .captured,
        .moved(columnID: BoardColumn.inProgress.id.uuidString, columnName: "In Progress"),
        .renamed,
        .descriptionAdded,
        .descriptionUpdated,
        .prioritySet(.high),
        .dueSet(CalendarDay(year: 2026, month: 2, day: 28)),
        .dueCleared,
        .labelAdded(key: "design", name: "Design"),
        .labelRemoved(key: "ios", name: "iOS"),
        .subtaskAdded,
        .subtaskRenamed,
        .subtaskRemoved,
        .subtasksCompletedOnDone(count: 3),
        .archived,
        .unarchived,
        .legacy("Estimated at 3 days"),
        .repeatSet(RecurrenceRule(interval: 2, unit: .week, weekdays: [2, 6])),
        .repeatCleared,
        .repeatEnded,
        .repeatedAs(code: "NW-231"),
        .repeatOf(code: "NW-121"),
    ]

    /// The board with some of its tasks already filed away, for a probe that
    /// needs an archive it did not have to build first — `unarchive` on a board
    /// where nothing is archived changes nothing, and a probe that starts by
    /// archiving cannot tell the restore's own step from the pair.
    ///
    /// The stamps are seconds before `epoch`, so a later filing has the *smaller*
    /// offset, exactly as `at(_:)` reads elsewhere.
    static func tasks(archiving stamps: [TaskItem.ID: Int]) -> [TaskItem] {
        tasks.map { task in
            guard let offset = stamps[task.id] else { return task }
            var filed = task
            filed.archivedAt = at(offset)
            return filed
        }
    }

    /// The same board filed onto `board`: every card whose column that board
    /// has joins it, and the one in the old Inbox column is unfiled — which is
    /// exactly what the v5 migration does to a file written before boards.
    static func tasks(on board: Board, archiving stamps: [TaskItem.ID: Int] = [:]) -> [TaskItem] {
        tasks(archiving: stamps).map { task in
            var filed = task
            if let columnID = task.columnID, board.column(id: columnID) != nil {
                filed.placement = .column(board: board.id, column: columnID)
            } else {
                filed.placement = .inbox
            }
            return filed
        }
    }

    static func columnID(_ n: UInt8) -> BoardColumn.ID {
        UUID(uuid: (0xC0, 0x15, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    static let queue = BoardColumn(
        id: columnID(1), name: "Queue", short: "Queue", dot: .hex(0xA8A29A)
    )
    static let closed = BoardColumn(
        id: columnID(2), name: "Closed", short: "Closed", dot: .hex(0x1F6F63)
    )

    /// A second board, holding nothing. The mutations that reorder the board
    /// list, move a card across or delete a board and leave somewhere to be are
    /// all incapable of failing against a single board, so the probes that
    /// cover them ask for this one as well.
    ///
    /// Its columns are its own — a shared id would have each board drawing the
    /// other's cards.
    static let support = Board(
        id: UUID(uuid: (0xB0, 0xA4, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x5E)),
        name: "Support triage", symbol: "lifepreserver", createdAt: at(200_000),
        columns: [queue, closed], codePrefix: "ST"
    )

    /// The seeded board and an empty second one.
    static let boards: [Board] = SeedData.boards + [support]

    /// A theme that is not the default in its slot, for the tests whose subject
    /// is "the appearance was changed" rather than which appearance it was
    /// changed to. Ember is dark where Aurora is, Daybreak is light where
    /// Porcelain is, so selecting either moves exactly one of the two slots.
    ///
    /// **It has to not be the default**, or the tests that watch for a *change*
    /// watch a no-op: `selectTheme` writes nothing when the slot already names
    /// that theme, and the two suites that assert a write then fail for a
    /// reason that has nothing to do with what they are testing. This was
    /// Aurora until Aurora became the default dark theme.
    static let otherDarkTheme = ThemePresets.theme(ThemePresets.emberID)!
    static let otherLightTheme = ThemePresets.theme("1c")!

    /// Both slots moved off their defaults, for a snapshot that has to differ
    /// from a fresh one.
    static let otherThemes = ThemeSettings(
        lightID: otherLightTheme.id, darkID: otherDarkTheme.id
    )

    @MainActor
    static func store(
        tasks: [TaskItem] = TestBoard.tasks,
        boards: [Board] = SeedData.boards,
        file: BoardFile? = nil,
        nextSerial: Int = BoardSnapshot.baseSerial
    ) -> BoardStore {
        BoardStore(tasks: tasks, boards: boards, activeBoardID: boards.first?.id, labels: LabelDef.seed,
                    nextSerial: nextSerial, file: file)
    }

    /// A store and the undo manager driving it. The store holds the manager
    /// weakly, so the caller has to keep hold of both halves.
    @MainActor
    static func undoing(
        tasks: [TaskItem] = TestBoard.tasks, boards: [Board] = SeedData.boards, file: BoardFile? = nil
    ) -> (store: BoardStore, undo: RecordingUndoManager) {
        let undo = RecordingUndoManager()
        // Grouping is done by `step` rather than by the run loop — see there.
        undo.groupsByEvent = false
        let store = store(tasks: tasks, boards: boards, file: file)
        store.undoManager = undo
        return (store, undo)
    }
}

/// An `UndoManager` that keeps every action name that has been set on it, in
/// order.
///
/// `undoActionName` reports one name per group — the last one set — so inside a
/// group it cannot distinguish one registration from three: a step that should
/// have collapsed into an outer one is overwritten by that outer one, and the
/// board a grouped undo lands on is identical either way. The *sequence* is
/// what tells them apart, and `setActionName` is the one hook the class offers
/// (the block form of `registerUndo` lives in an extension and cannot be
/// overridden).
final class RecordingUndoManager: UndoManager {
    /// One entry per `registerUndo` the store followed with a name, including
    /// the ones an undo files to make redo work.
    private(set) var actionNames: [String] = []

    override func setActionName(_ actionName: String) {
        actionNames.append(actionName)
        super.setActionName(actionName)
    }
}

/// One user action, in an undo group of its own.
///
/// In the app that grouping is automatic: `UndoManager.groupsByEvent` opens a
/// group for the event being handled and the run loop closes it on the way back
/// round, which is what makes one user action cost one ⌘Z. Under
/// `xcodebuild test` nothing pumps the host app's event loop, so that group
/// never closes and every registration in a test would collapse into one
/// step — a state in which no undo test is capable of failing. Grouping by hand
/// is the same shape, minus the run loop.
@MainActor
func step(_ undo: UndoManager, _ body: () -> Void) {
    undo.beginUndoGrouping()
    body()
    undo.endUndoGrouping()
}

/// Undoes to the bottom of the stack, counting the steps that changed the
/// board.
///
/// `UndoManager` keeps a group it was handed even when nothing registered into
/// it, and `step` hands it one per action whether or not the action was worth
/// undoing. What a user counts is ⌘Z presses that change something, so that is
/// what is counted here.
///
/// It cannot answer "was anything registered?": a step that restores a board
/// identical to the one it found and a step that was never registered at all
/// both leave this count alone. For that question read `undo.undoActionName`
/// immediately after the action and *before* the stack is drained — an empty
/// group reports an empty name, and anything registered has named itself.
@MainActor
func undoEverything(_ undo: UndoManager, on store: BoardStore, limit: Int = 32) -> Int {
    var changed = 0
    var attempts = 0
    while undo.canUndo, attempts < limit {
        let tasks = store.tasks
        let labels = store.labels
        undo.undo()
        if store.tasks != tasks || store.labels != labels { changed += 1 }
        attempts += 1
    }
    return changed
}

/// A board built to stand on the edges of the saved-view predicates.
///
/// `TestBoard` has two due dates between six tasks, which is enough to show a
/// predicate works and nowhere near enough to show where it stops. Every task
/// here exists to pin one bound — the day either side of it — plus a task with
/// no due date at all and a Done task in each view that is meant to leave Done
/// out.
///
/// `updatedAt` is scrambled against board order on purpose: a "sorted by
/// `updatedAt`" assertion that happens to match the array it was given cannot
/// fail on a build that never sorted anything.
enum ViewBoard {
    /// Mid-month and mid-year, so ±8 days cannot leave the month and an
    /// expectation here is not quietly testing calendar arithmetic instead.
    static let today = CalendarDay(year: 2026, month: 6, day: 15)

    /// The instant `updatedAt` and `archivedAt` are measured back from.
    static let stamp = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func at(_ secondsBefore: Int) -> Date { stamp.addingTimeInterval(-Double(secondsBefore)) }

    static func taskID(_ n: UInt8) -> TaskItem.ID {
        UUID(uuid: (0x71, 0xE7, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    static let overdueYesterday = taskID(1)   // due -1
    static let dueToday = taskID(2)           // due 0
    static let dueTomorrow = taskID(3)        // due +1
    static let dueInSix = taskID(4)           // due +6
    static let dueInSeven = taskID(5)         // due +7
    static let longOverdue = taskID(6)        // due -8, high priority
    static let noDueHigh = taskID(7)          // no due, high priority
    static let noDueLow = taskID(8)           // no due, low priority
    static let doneDueToday = taskID(9)       // Done, due 0, high priority
    static let doneUpcoming = taskID(10)      // Done, due +3

    static let tasks: [TaskItem] = [
        task(overdueYesterday, "NW-201", column: BoardColumn.backlog.id, due: -1, updated: 500),
        task(dueToday, "NW-202", column: BoardColumn.upNext.id, due: 0, updated: 100),
        task(dueTomorrow, "NW-203", column: BoardColumn.upNext.id, due: 1, updated: 900),
        task(dueInSix, "NW-204", column: BoardColumn.backlog.id, due: 6, updated: 300),
        task(dueInSeven, "NW-205", column: BoardColumn.backlog.id, due: 7, updated: 700),
        task(longOverdue, "NW-206", column: BoardColumn.inbox.id, due: -8, priority: .high, updated: 200),
        task(noDueHigh, "NW-207", column: BoardColumn.inProgress.id, due: nil, priority: .high, updated: 800),
        task(noDueLow, "NW-208", column: BoardColumn.inbox.id, due: nil, priority: .low, updated: 400),
        task(doneDueToday, "NW-209", column: BoardColumn.done.id, due: 0, priority: .high, updated: 600),
        task(doneUpcoming, "NW-210", column: BoardColumn.done.id, due: 3, updated: 1_000),
    ]

    /// The same board with some tasks filed away, keyed by how long before
    /// `stamp` each was filed — so a *smaller* number is a *later* filing, and
    /// the Archive's newest-first order is not the order they are written in.
    static func tasks(archiving stamps: [TaskItem.ID: Int]) -> [TaskItem] {
        tasks.map { task in
            guard let offset = stamps[task.id] else { return task }
            var filed = task
            filed.archivedAt = at(offset)
            return filed
        }
    }

    /// Twenty-five tasks for the cap, written oldest-first so that "the twenty
    /// most recent" is the reverse of the array and cannot be the array.
    ///
    /// `NW-301` is the newest and `NW-325` the oldest, so the cap keeps
    /// NW-301…NW-320 and drops the last five — which is also what makes the
    /// order the query and the cap are applied in observable.
    static let deepTasks: [TaskItem] = (1...25).reversed().map { n in
        task(taskID(UInt8(100 + n)), String(format: "NW-3%02d", n),
             column: BoardColumn.backlog.id, due: nil, updated: n * 60)
    }

    @MainActor
    static func store(tasks: [TaskItem] = ViewBoard.tasks, file: BoardFile? = nil) -> BoardStore {
        BoardStore(tasks: tasks, labels: LabelDef.seed,
                   nextSerial: BoardSnapshot.baseSerial, file: file)
    }

    /// `due` is a whole-day offset from `today`; `updated` and `archived` are
    /// seconds before `stamp`.
    private static func task(
        _ id: TaskItem.ID, _ code: String, column: BoardColumn.ID, due: Int?,
        priority: Priority = .medium, updated: Int
    ) -> TaskItem {
        TaskItem(
            id: id, code: code, columnID: column,
            title: "Bound \(code)",
            due: due.map { today.adding(days: $0) },
            priority: priority,
            createdAt: at(updated), updatedAt: at(updated)
        )
    }
}

/// A board document as it arrives from somewhere else — the other machine, the
/// old laptop, a colleague's export.
///
/// Everything here is deliberately unlike the board it will be imported into:
/// its own board with its own columns and code prefix, labels that reuse one of
/// the importing board's keys under a different name, and a higher serial. The
/// one thing it shares is `colliding`, a task carrying an id the importing board
/// already has — the case 3.7 moved ids to UUIDs for, and the one where a merge
/// bug destroys work silently rather than loudly.
enum ForeignBoard {
    /// Well after `TestBoard.epoch`, so "which document did this come from" is
    /// answerable from a timestamp as well as from a title.
    static let stamp = Date(timeIntervalSinceReferenceDate: 790_000_000)

    static func at(_ secondsBefore: Int) -> Date { stamp.addingTimeInterval(-Double(secondsBefore)) }

    static func taskID(_ n: UInt8) -> TaskItem.ID {
        UUID(uuid: (0xF0, 0x2E, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    static func columnID(_ n: UInt8) -> BoardColumn.ID {
        UUID(uuid: (0xF0, 0x1D, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    static let brief = taskID(1)
    static let hero = taskID(2)
    static let unfiled = taskID(3)

    /// The collision, spelled as the identity it clashes with rather than as a
    /// literal: `TestBoard.cafe` is a real card on the importing board, and this
    /// one is a different card that happens to carry its id.
    static let colliding = TestBoard.cafe

    static let triage = BoardColumn(
        id: columnID(1), name: "Triage", short: "Triage", dot: .hex(0x3B5BA9)
    )
    static let shipped = BoardColumn(
        id: columnID(2), name: "Shipped", short: "Shipped", dot: .hex(0x1F6F63)
    )

    static let board = Board(
        id: UUID(uuid: (0xF0, 0xB0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0x01)),
        name: "Website refresh", symbol: "globe", createdAt: at(500_000),
        columns: [triage, shipped], codePrefix: "WR"
    )

    /// One key the importing board already has, under a different name and
    /// colour, and one it has never seen. A merge that takes the incoming
    /// definition for `design` renames the importing board's own chips.
    static let labels: [LabelDef] = [
        LabelDef(key: "design", name: "Visual design",
                 light: LabelTone.pair(from: 0x3B5BA9).light, dark: LabelTone.pair(from: 0x3B5BA9).dark),
        LabelDef(key: "seo", name: "SEO",
                 light: LabelTone.pair(from: 0x783CA0).light, dark: LabelTone.pair(from: 0x783CA0).dark),
    ]

    /// Two cards on the foreign board and one in its Inbox, so an import has to
    /// carry an unfiled card as well as a placed one.
    static let tasks: [TaskItem] = [
        TaskItem(
            id: brief, code: "WR-140", columnID: triage.id,
            title: "Rewrite the brief", note: "Half of it is about the old logo.",
            labelKeys: ["seo"], due: CalendarDay(year: 2026, month: 10, day: 2), priority: .high,
            subtasks: [SubTask(id: TestBoard.subtaskID(90), text: "Audit the old copy", done: true)],
            activity: [ActivityEntry(id: TestBoard.entryID(90), .created, when: at(4_000))],
            createdAt: at(4_000), updatedAt: at(3_000)
        ),
        TaskItem(
            id: hero, code: "WR-141", columnID: shipped.id,
            title: "Hero image", labelKeys: ["design"],
            activity: [ActivityEntry(id: TestBoard.entryID(91), .created, when: at(9_000))],
            createdAt: at(9_000), updatedAt: at(8_000)
        ),
        TaskItem(
            id: unfiled, code: "WR-142", title: "Somebody's stray thought",
            activity: [ActivityEntry(id: TestBoard.entryID(92), .captured, when: at(1_000))],
            createdAt: at(1_000), updatedAt: at(1_000)
        ),
    ]

    /// The card wearing an id the importing board is already using. Nothing
    /// about it matches the card it collides with, so "both survived" and
    /// "one overwrote the other" cannot be confused.
    static let collidingTask = TaskItem(
        id: colliding, code: "WR-143", columnID: triage.id,
        title: "A different card entirely", note: "Nothing to do with a café.",
        labelKeys: ["seo"], priority: .high,
        activity: [ActivityEntry(id: TestBoard.entryID(93), .created, when: at(2_000))],
        createdAt: at(2_000), updatedAt: at(2_000)
    )

    /// A card with an id nobody here has and a *code* somebody does. Codes are
    /// minted per board from a per-file counter, so two installs hand out the
    /// same ones as a matter of course — `NW-122` names a different card on
    /// every machine that has ever seeded a board.
    static let collidingCodeTask = TaskItem(
        id: taskID(4), code: "NW-122", columnID: triage.id,
        title: "Their NW-122",
        activity: [ActivityEntry(id: TestBoard.entryID(94), .created, when: at(1_500))],
        createdAt: at(1_500), updatedAt: at(1_500)
    )

    /// The document as exported. `including` adds the colliding card.
    static func snapshot(
        includingCollision: Bool = false, includingCodeCollision: Bool = false
    ) -> BoardSnapshot {
        BoardSnapshot(
            tasks: tasks
                + (includingCollision ? [collidingTask] : [])
                + (includingCodeCollision ? [collidingCodeTask] : []),
            boards: [board], labels: labels, nextSerial: 344,
            activeBoardID: board.id,
            // Deliberately not this machine's pair, so that "an import does not
            // repaint the app" is a claim with something behind it.
            themes: TestBoard.otherThemes
        )
    }
}

/// The seeded seven, by name, for the suites written while they were an enum.
///
/// **Test-only, and deliberately not on the model.** A production call site
/// saying `SavedView.today` would get a *fresh copy* of the seeded rule rather
/// than the user's Today — which since v11 they may have renamed, re-ruled or
/// deleted — and that is exactly the bug the surface carrying an id instead of a
/// view exists to prevent. Here there is no user, the store is built from
/// `seededAll`, and the copy and the row are the same thing.
extension SavedView {
    static var allCases: [SavedView] { seededAll }
    /// The five that narrow the board, which is what the sidebar used to draw
    /// above the Archive.
    static var filters: [SavedView] { seededAll.filter { $0.preset != .archive } }

    static var inbox: SavedView { seeded(.inbox) }
    static var today: SavedView { seeded(.today) }
    static var upcoming: SavedView { seeded(.upcoming) }
    static var highPriority: SavedView { seeded(.highPriority) }
    static var dueThisWeek: SavedView { seeded(.dueThisWeek) }
    static var recentlyUpdated: SavedView { seeded(.recentlyUpdated) }
    static var archive: SavedView { seeded(.archive) }

    /// What `lastSurfaceName` writes down, which since v11 is the id rather
    /// than an enum case's spelling.
    var rawValue: String { id.uuidString }
}

// MARK: - Reading pixels back

/// A rendered view as raw RGBA rows — for the handful of claims that are about
/// what was *drawn* rather than what the model says: which edge a caret is on
/// (`DropCaretTests`), whether a button parked behind a row shows through it
/// (`ChecklistSwipeTests`). `ImageRenderer` draws only what SwiftUI itself
/// draws — a platform-backed field comes out blank — which is enough for both.
struct Raster {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    @MainActor
    init?(rendering view: some View) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage, image.width > 0, image.height > 0 else { return nil }
        // Locals rather than the properties: the closure below would
        // otherwise capture a `self` that is not finished being built.
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w
        height = h
        bytes = buffer
    }

    func row(_ index: Int) -> ArraySlice<UInt8> {
        bytes[(index * width * 4)..<((index + 1) * width * 4)]
    }

    /// One pixel's red, green and blue, 0...255 each.
    func pixel(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let at = (y * width + x) * 4
        return (Int(bytes[at]), Int(bytes[at + 1]), Int(bytes[at + 2]))
    }

    /// How many pixels in the whole picture are within `tolerance` of a colour
    /// on every channel.
    func count(near colour: (r: Int, g: Int, b: Int), tolerance: Int = 12) -> Int {
        var hits = 0
        for at in stride(from: 0, to: bytes.count, by: 4)
        where abs(Int(bytes[at]) - colour.r) <= tolerance
            && abs(Int(bytes[at + 1]) - colour.g) <= tolerance
            && abs(Int(bytes[at + 2]) - colour.b) <= tolerance {
            hits += 1
        }
        return hits
    }

    /// How much of a row is within a rounding step of one colour.
    func fraction(ofRow index: Int, near colour: (Float, Float, Float)) -> Double {
        let target = [colour.0, colour.1, colour.2].map { UInt8(max(0, min(255, $0 * 255))) }
        let start = index * width * 4
        var hits = 0
        for x in 0..<width {
            let pixel = start + x * 4
            let close = (0..<3).allSatisfy { channel in
                let value = Int(bytes[pixel + channel]), want = Int(target[channel])
                return abs(value - want) <= 12
            }
            if close { hits += 1 }
        }
        return Double(hits) / Double(width)
    }
}
