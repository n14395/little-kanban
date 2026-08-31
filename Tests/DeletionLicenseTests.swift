import Foundation
import SwiftData
import Testing
@testable import Simple_Kanban

/// Deletion needs a deletion — the licence, after the third data loss.
///
/// The record store used to treat *"the diff base names it and the snapshot
/// does not"* as permission to delete. Necessary, never sufficient: any skew
/// between the two — a launch race, a read taken mid-import, a store holding
/// the same board twice under different ids — read as a deletion nobody made,
/// travelled, and took another device's board with it. The afternoon this
/// suite answers to, the same three boards lived in the cloud under two
/// id-sets, and every reconciliation deleted one set and re-minted the other
/// as fresh CloudKit records: 476,096 transactions, a 149 MB store, and
/// "sync deleted all my boards" on whichever device was standing on the set
/// that lost.
///
/// Now the licence is ``SyncIDs``: `BoardStore` keeps the ids the records
/// last agreed to hold, and what has left the board since — verbs, trash,
/// undo, start-over, nothing else takes ids out — is the only thing a push
/// may delete. Skew still happens; it now duplicates at worst, and a
/// duplicate resurfaces where a deletion is forever.
@MainActor
@Suite struct DeletionLicenseTests {
    /// Two full copies of a board's worth of content under disjoint ids —
    /// what the two-id-set cloud actually delivered.
    private static func otherSet() -> BoardSnapshot {
        var board = Board(id: UUID(), name: "Personal",
                          columns: [BoardColumn(id: UUID(), name: "Someday", short: "Some", dot: .accent),
                                    BoardColumn(id: UUID(), name: "Done", short: "Done", dot: .accent)],
                          codePrefix: "PE")
        board.createdAt = TestBoard.at(900)
        var task = TaskItem(id: UUID(), code: "PE-1", title: "The same card, other identity")
        task.placement = .column(board: board.id, column: board.columns[0].id)
        task.updatedAt = TestBoard.at(900)
        return BoardSnapshot(tasks: [task], boards: [board],
                             labels: [LabelDef(key: "twin", name: "Twin",
                                               light: LabelDef.seed[0].light, dark: LabelDef.seed[0].dark)],
                             nextSerial: 210)
    }

    private func ids<Model: PersistentModel>(_ type: Model.Type, _ sync: BoardSyncStore,
                                             _ id: (Model) -> UUID) throws -> Set<UUID> {
        Set(try sync.container.mainContext.fetch(FetchDescriptor<Model>()).map(id))
    }

    /// The wipe itself: base names one id-set, the snapshot carries the other,
    /// nobody deleted anything. The old sweep deleted the base's set whole —
    /// boards, columns, tasks — and re-inserted the snapshot's as brand-new
    /// CloudKit records, every save, forever.
    @Test func idSetSkewDeletesNothing() throws {
        let sync = try BoardSyncStore.inMemory()
        let mine = BoardSnapshot(tasks: TestBoard.tasks(on: SeedData.defaultBoard),
                                 boards: SeedData.boards, labels: LabelDef.seed, nextSerial: 100)
        try sync.apply(mine)               // base now names mine
        try sync.apply(Self.otherSet())    // entirely different ids, no tombstones

        let boards = try ids(StoredBoard.self, sync, \.id)
        #expect(boards.isSuperset(of: mine.boards.map(\.id)),
                "a push with no deletions behind it deleted the boards the base named")
        let tasks = try ids(StoredTask.self, sync, \.id)
        #expect(tasks.isSuperset(of: mine.tasks.map(\.id)),
                "a push with no deletions behind it deleted the tasks the base named")
    }

    /// The stronger half: a tombstone reaches a record the base never named.
    /// A deletion made here is licensed to land even on a record this device
    /// never read — otherwise the deleted thing resurfaces on the next read
    /// and the user deletes it forever.
    @Test func aTombstoneReachesARecordTheBaseNeverNamed() throws {
        let sync = try BoardSyncStore.inMemory()
        let mine = BoardSnapshot(tasks: [], boards: SeedData.boards, labels: [], nextSerial: 100)
        try sync.apply(mine)

        // Arrives behind the base's back, the way an import does.
        let stray = Self.otherSet()
        try BoardSyncStore(container: sync.container, isSyncing: false).apply(stray)
        sync.invalidateDiff()
        _ = try sync.load()  // base: whole store
        try sync.apply(mine, deleting: SyncIDs(boards: Set(stray.boards.map(\.id)),
                                               tasks: Set(stray.tasks.map(\.id))))

        #expect(try ids(StoredBoard.self, sync, \.id).contains(stray.boards[0].id) == false,
                "the tombstoned board survived")
        #expect(try ids(StoredBoard.self, sync, \.id).isSuperset(of: SeedData.boards.map(\.id)))
    }

    /// Through the store: deleting one of two twin boards kills exactly that
    /// one — the kept twin and everything else stand.
    @Test func deletingOneTwinLeavesTheOther() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let mine = BoardSnapshot(tasks: TestBoard.tasks(on: SeedData.defaultBoard),
                                 boards: SeedData.boards, labels: LabelDef.seed, nextSerial: 100)
        try temp.file.write(mine, generation: temp.file.nextWriteGeneration())
        try sync.apply(mine)
        let twin = Self.otherSet()
        try BoardSyncStore(container: sync.container, isSyncing: false).apply(twin)
        sync.invalidateDiff()

        let store = BoardStore.restored(file: temp.file, sync: sync)
        #expect(store.boards.count == SeedData.boards.count + 1, "the twin was not adopted")

        _ = store.deleteBoard(twin.boards[0].id)
        store.saveNow()

        let boards = try ids(StoredBoard.self, sync, \.id)
        #expect(boards.contains(twin.boards[0].id) == false, "the deleted twin survived")
        #expect(boards.isSuperset(of: SeedData.boards.map(\.id)), "the kept boards went with it")
    }

    /// Undo is a deletion with no verb: taking back a creation removes the
    /// board by restoring a snapshot from before it existed. The baseline
    /// diff is what catches it — a verb-by-verb tombstone list never would.
    @Test func undoingACreationDeletesItsRecord() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let mine = BoardSnapshot(tasks: [], boards: SeedData.boards, labels: [], nextSerial: 100)
        try temp.file.write(mine, generation: temp.file.nextWriteGeneration())
        try sync.apply(mine)
        let store = BoardStore.restored(file: temp.file, sync: sync)
        let undo = RecordingUndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo

        var made: Board.ID?
        step(undo) { made = store.createBoard(named: "Oops") }
        store.saveNow()
        let id = try #require(made)
        #expect(try ids(StoredBoard.self, sync, \.id).contains(id))

        undo.undo()
        store.saveNow()
        #expect(try ids(StoredBoard.self, sync, \.id).contains(id) == false,
                "the undone board's record survived to resurface on every device")
    }

    /// Start-over replaces the whole board, and the replacement must travel
    /// as the deletion it is — the licence has to say yes to the real thing.
    @Test func startingOverTombstonesTheOldBoard() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let mine = BoardSnapshot(tasks: TestBoard.tasks(on: SeedData.defaultBoard),
                                 boards: SeedData.boards, labels: LabelDef.seed, nextSerial: 100)
        try temp.file.write(mine, generation: temp.file.nextWriteGeneration())
        try sync.apply(mine)
        let store = BoardStore.restored(file: temp.file, sync: sync)

        store.startOver(with: SeedData.starters[0].snapshot)
        store.saveNow()

        let boards = try ids(StoredBoard.self, sync, \.id)
        #expect(boards.contains(SeedData.defaultBoard.id) == false,
                "the board start-over replaced is still in the records")
        #expect(boards.isEmpty == false, "the template never reached the records")
    }
}
