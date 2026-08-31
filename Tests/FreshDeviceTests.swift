import Foundation
import SwiftData
import Testing
@testable import Simple_Kanban

/// The launch that has never seen the records.
///
/// A device installing the app for the first time opens a store CloudKit has
/// not finished filling: for the first seconds — minutes, on a board of any
/// size — the records hold somebody's whole board and this device has read
/// none of it. Every question `BoardSyncStore` asks itself in that window has
/// the same wrong answer available, and it is the destructive one: *the
/// snapshot does not name this record, so the person must have deleted it.*
///
/// They did not. It has not arrived yet. And a deletion written down here is
/// replayed by CloudKit onto every device the account owns, which is how a
/// fresh install came to empty two other machines. The rule that closes it is
/// on ``BoardSyncStore/apply(_:)``: what the diff base does not name is not
/// this device's to delete or to overwrite.
///
/// Every test here is that window. The import is delivered the way CloudKit
/// delivers one — records appearing in the store that this device's sync store
/// never wrote and has never read back — rather than through `apply`, which
/// would set the diff base and dissolve the whole problem.
@MainActor
@Suite struct FreshDeviceTests {
    private static let boardID = UUID()
    private static let columnID = UUID()
    private static let taskID = UUID()
    private static let labelKey = "shipping"

    /// The other device's board, arriving.
    @discardableResult
    private func deliverTheOtherDevicesBoard(
        into sync: BoardSyncStore, taskUpdatedAt: Date = .now, nextSerial: Int = 812
    ) throws -> ThemeSettings {
        let context = sync.container.mainContext
        let board = StoredBoard(id: Self.boardID)
        board.name = "Work"
        board.createdAt = .now
        context.insert(board)
        let column = StoredColumn(id: Self.columnID)
        column.name = "Doing"
        column.board = board
        context.insert(column)
        let task = StoredTask(id: Self.taskID)
        task.title = "Two years of it"
        task.boardID = Self.boardID
        task.columnID = Self.columnID
        task.position = 0
        task.updatedAt = taskUpdatedAt
        context.insert(task)
        let label = StoredLabel(key: Self.labelKey)
        label.name = "Shipping"
        context.insert(label)
        let meta = StoredMeta()
        meta.nextSerial = nextSerial
        meta.themesJSON = BoardSyncStore.encoded(TestBoard.otherThemes)
        meta.activeBoardID = Self.boardID
        meta.updatedAt = .now
        context.insert(meta)
        try context.save()
        return TestBoard.otherThemes
    }

    private func board(in sync: BoardSyncStore) throws -> StoredBoard? {
        try sync.container.mainContext.fetch(FetchDescriptor<StoredBoard>())
            .first { $0.id == Self.boardID }
    }

    private func task(in sync: BoardSyncStore) throws -> StoredTask? {
        try sync.container.mainContext.fetch(FetchDescriptor<StoredTask>())
            .first { $0.id == Self.taskID }
    }

    private func label(in sync: BoardSyncStore) throws -> StoredLabel? {
        try sync.container.mainContext.fetch(FetchDescriptor<StoredLabel>())
            .first { $0.key == Self.labelKey }
    }

    private func meta(in sync: BoardSyncStore) throws -> StoredMeta? {
        try sync.container.mainContext.fetch(FetchDescriptor<StoredMeta>()).first
    }

    // MARK: The window itself

    /// The launch race, and the whole bug in four lines. `restored(file:sync:)`
    /// reads the store, is told there is nothing there, and pushes the board it
    /// found in the file — and between those two moments the import commits its
    /// first batch.
    @Test func aPushWithNoDiffBaseDeletesNothingThatHasArrived() throws {
        let sync = try BoardSyncStore.inMemory()
        try deliverTheOtherDevicesBoard(into: sync)

        try sync.apply(BoardSnapshot(tasks: [], boards: [], labels: [], nextSerial: 100))

        #expect(try board(in: sync) != nil, "the other device's board was deleted")
        #expect(try task(in: sync) != nil, "the other device's task was deleted")
        #expect(try label(in: sync) != nil, "the other device's label was deleted")
    }

    /// And it must not quietly rewrite them either: with no base there is
    /// nothing this device can be said to know about a record it has never read.
    @Test func aPushWithNoDiffBaseOverwritesNothingThatHasArrived() throws {
        let sync = try BoardSyncStore.inMemory()
        let theirThemes = try deliverTheOtherDevicesBoard(into: sync)

        // A board of ours that happens to carry their id — which is exactly
        // what two devices seeding the same starter template produces.
        let mine = Board(id: Self.boardID, name: "Sample",
                         columns: [BoardColumn.backlog], codePrefix: "SA")
        try sync.apply(BoardSnapshot(tasks: [], boards: [mine], labels: [], nextSerial: 100))

        #expect(try board(in: sync)?.name == "Work", "an unread board record was renamed")
        #expect(try board(in: sync)?.columns?.count == 1)
        #expect(try board(in: sync)?.columns?.first?.name == "Doing",
                "an unread board's column was rewritten")
        let settings: ThemeSettings? = BoardSyncStore.decoded(try meta(in: sync)?.themesJSON)
        #expect(settings == theirThemes, "an unread settings record had this device's themes put on it")
    }

    /// The one thing that does move, because the disagreement it prevents is
    /// the one no later merge can undo: two devices handing out one task code.
    @Test func aPushWithNoDiffBaseStillCarriesTheSerialForward() throws {
        let ahead = try BoardSyncStore.inMemory()
        try deliverTheOtherDevicesBoard(into: ahead, nextSerial: 812)
        try ahead.apply(BoardSnapshot(tasks: [], boards: [], labels: [], nextSerial: 900))
        #expect(try meta(in: ahead)?.nextSerial == 900, "the serial did not climb")

        let behind = try BoardSyncStore.inMemory()
        try deliverTheOtherDevicesBoard(into: behind, nextSerial: 812)
        try behind.apply(BoardSnapshot(tasks: [], boards: [], labels: [], nextSerial: 400))
        #expect(try meta(in: behind)?.nextSerial == 812,
                "a device that has read nothing pulled the serial back")
    }

    /// A task carries the clock a board and a label do not, so an unread record
    /// older than the value in hand is one this device is genuinely ahead of.
    /// That is the last-writer-wins the schema promises everywhere else.
    @Test func aNewerTaskStillWinsOverAnUnreadRecord() throws {
        let sync = try BoardSyncStore.inMemory()
        try deliverTheOtherDevicesBoard(into: sync, taskUpdatedAt: TestBoard.at(500))

        var mine = TaskItem(id: Self.taskID, code: "NW-1", title: "Edited here, later")
        mine.placement = .column(board: Self.boardID, column: Self.columnID)
        mine.updatedAt = TestBoard.at(0)
        try sync.apply(BoardSnapshot(tasks: [mine], boards: [], labels: [], nextSerial: 100))

        #expect(try task(in: sync)?.title == "Edited here, later")
    }

    // MARK: The window, through the store

    /// The board the person makes while their own is still coming down. The
    /// snapshot changes, so `applyBoards` runs — and it used to take every
    /// board record it could not account for with it.
    @Test func aBoardMadeDuringTheImportDoesNotDeleteWhatIsArriving() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = BoardStore.restored(file: temp.file, sync: sync)
        try deliverTheOtherDevicesBoard(into: sync)

        _ = store.createBoard(named: "Mine")
        store.saveNow()

        #expect(try board(in: sync) != nil, "making a board deleted the one that was arriving")
        #expect(try task(in: sync) != nil)
        #expect(try label(in: sync) != nil)
    }

    /// The same for the labels, which have their own sweep.
    @Test func aLabelMadeDuringTheImportDoesNotDeleteWhatIsArriving() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = BoardStore.restored(file: temp.file, sync: sync)
        try deliverTheOtherDevicesBoard(into: sync)

        _ = store.createLabel(named: "Mine")
        store.saveNow()

        #expect(try label(in: sync) != nil, "making a label deleted the one that was arriving")
        #expect(try board(in: sync) != nil)
        #expect(try task(in: sync) != nil)
    }

    /// And once it has arrived and been adopted, the board is this device's to
    /// speak for again — a deletion made here is a deletion, and still travels.
    @Test func aDeletionAfterTheImportHasBeenReadStillTravels() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = BoardStore.restored(file: temp.file, sync: sync)
        try deliverTheOtherDevicesBoard(into: sync)

        #expect(store.mergeRemoteChanges(), "the arriving board was not adopted")
        #expect(store.boards.contains { $0.id == Self.boardID })

        _ = store.deleteBoard(Self.boardID)
        store.saveNow()
        #expect(try board(in: sync) == nil, "a board deleted after it was read was not deleted")
    }

    // MARK: The first session

    /// What the picker folds in has to reach the records, or the launch after
    /// it — where the records win outright — throws the whole first session
    /// away. On a device that already has a board in iCloud, that is every
    /// first launch.
    @Test func theFirstRunSessionWritesToTheRecords() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = FirstRun.emptyStore(file: temp.file, sync: sync)
        #expect(store.boards.isEmpty)

        store.importBoard(SeedData.starters[0].snapshot)
        store.saveNow()

        let records = try #require(try sync.load())
        #expect(records.boards.map(\.name) == store.boards.map(\.name),
                "the board chosen on the first launch never reached the records")
        #expect(Set(records.tasks.map(\.id)) == Set(store.tasks.map(\.id)))
    }

    /// And the empty board it starts on says nothing at all, which is what
    /// makes handing it the records safe: there is a whole board in them and
    /// this session has read none of it.
    @Test func theEmptyBoardTheFirstRunStartsOnDisturbsNothing() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let theirThemes = try deliverTheOtherDevicesBoard(into: sync)
        let store = FirstRun.emptyStore(file: temp.file, sync: sync)

        store.saveNow()

        #expect(try board(in: sync) != nil, "the empty first-run board deleted what was in iCloud")
        #expect(try task(in: sync) != nil)
        #expect(try label(in: sync) != nil)
        let settings: ThemeSettings? = BoardSyncStore.decoded(try meta(in: sync)?.themesJSON)
        #expect(settings == theirThemes)
    }
}
