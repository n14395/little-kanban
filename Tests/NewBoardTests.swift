import Foundation
import SwiftData
import Testing
@testable import Cardstock

/// A board made on another device, arriving.
///
/// It arrives in pieces — CloudKit applies records and relationships
/// independently, so the board record, its columns and the first card on it do
/// not land together. A read taken in the middle of that shows a card pointing
/// at a column nothing has yet, which is why ``BoardStore`` declines to adopt
/// it and waits for the next one.
///
/// Declining was never the problem. The problem was what the *read* had already
/// done on its way past: `load()` advanced the diff base to what it had read,
/// adopted or not, so this device came to believe the records held a board its
/// own board list had never heard of. The next save compared the two, read the
/// difference as a deletion, and deleted the board — and the cards on it —
/// from every device. Somebody made a board on their phone and watched it
/// disappear.
///
/// See ``BoardSnapshot/hasUnresolvedPlacements``.
@MainActor
@Suite struct NewBoardTests {
    private static let theirBoardID = UUID()
    private static let theirColumnID = UUID()
    private static let theirCardID = UUID()

    /// This device: a board of its own, read and adopted, like any other launch.
    private func settledDevice(_ temp: TempBoard, _ sync: BoardSyncStore) throws -> BoardStore {
        let mine = BoardSnapshot(
            tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: SeedData.boards,
            labels: LabelDef.seed, nextSerial: 100, activeBoardID: SeedData.defaultBoard.id
        )
        try temp.file.write(mine, generation: temp.file.nextWriteGeneration())
        try sync.apply(mine)
        return BoardStore.restored(file: temp.file, sync: sync)
    }

    /// The board and the first card on it, but not the column the card names.
    private func deliverTheirNewBoard(into sync: BoardSyncStore) throws {
        let context = sync.container.mainContext
        let board = StoredBoard(id: Self.theirBoardID)
        board.name = "Made on the phone"
        board.createdAt = .now
        board.position = 1
        context.insert(board)
        let card = StoredTask(id: Self.theirCardID)
        card.title = "First card on it"
        card.boardID = Self.theirBoardID
        card.columnID = Self.theirColumnID
        card.updatedAt = .now
        context.insert(card)
        try context.save()
    }

    /// And the column, a moment later.
    private func deliverTheColumn(into sync: BoardSyncStore) throws {
        let context = sync.container.mainContext
        let board = try context.fetch(FetchDescriptor<StoredBoard>())
            .first { $0.id == Self.theirBoardID }
        let column = StoredColumn(id: Self.theirColumnID)
        column.name = "Doing"
        column.short = "Doing"
        column.board = board
        context.insert(column)
        try context.save()
    }

    private func records(in sync: BoardSyncStore) throws -> (board: Bool, card: Bool) {
        let context = sync.container.mainContext
        return (
            try context.fetch(FetchDescriptor<StoredBoard>()).contains { $0.id == Self.theirBoardID },
            try context.fetch(FetchDescriptor<StoredTask>()).contains { $0.id == Self.theirCardID }
        )
    }

    @Test func aBoardArrivingBeforeItsColumnsIsNotDeletedByTheNextSave() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = try settledDevice(temp, sync)
        try deliverTheirNewBoard(into: sync)

        #expect(store.mergeRemoteChanges() == false, "a half-arrived board was adopted")
        store.addTask(to: .inbox, title: "Meanwhile, on this device")
        store.saveNow()

        let left = try records(in: sync)
        #expect(left.board, "the new board was deleted by the sync")
        #expect(left.card, "the card on the new board was deleted by the sync")
    }

    @Test func andItArrivesOnceTheColumnFollows() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = try settledDevice(temp, sync)
        try deliverTheirNewBoard(into: sync)
        _ = store.mergeRemoteChanges()
        try deliverTheColumn(into: sync)

        #expect(store.mergeRemoteChanges(), "the completed board was not adopted")
        let board = try #require(store.boards.first { $0.id == Self.theirBoardID })
        #expect(board.name == "Made on the phone")
        #expect(board.columns.map(\.id) == [Self.theirColumnID])
        let card = try #require(store[Self.theirCardID])
        #expect(card.placement == .column(board: Self.theirBoardID, column: Self.theirColumnID),
                "the card did not land on the board it was made on")
    }

    /// The other half of the rule: holding the base still must not stop a
    /// deletion this device genuinely made.
    @Test func aBoardDeletedHereDuringTheWaitStillGoes() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = try settledDevice(temp, sync)
        try deliverTheirNewBoard(into: sync)
        _ = store.mergeRemoteChanges()

        _ = store.deleteBoard(SeedData.defaultBoard.id)
        store.saveNow()

        let context = sync.container.mainContext
        let boards = try context.fetch(FetchDescriptor<StoredBoard>())
        #expect(boards.contains { $0.id == SeedData.defaultBoard.id } == false,
                "a board deleted on this device was not deleted from the records")
        #expect(boards.contains { $0.id == Self.theirBoardID },
                "deleting one board took the arriving one with it")
    }
}
