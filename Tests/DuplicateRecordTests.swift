import Foundation
import SwiftData
import Testing
@testable import Simple_Kanban

/// Two records under one id, and the three places nothing was settling them.
///
/// CloudKit enforces no uniqueness, so two devices that each create the same
/// logical row leave two records behind — a fact `BoardSyncStore.load()` has
/// always known about tasks, boards and labels, and settled by keeping one.
/// The rows that hang off a parent record were not settled by anything: a
/// board's columns, a task's sub-tasks, its activity.
///
/// It showed as a column drawn twice, and it grew: the board that was read
/// carried both copies, the save that followed wrote the board that was read,
/// and the writer, keyed by id, found nothing for the second copy of an id it
/// had already written — so it inserted another record. Every save doubled the
/// board again.
///
/// See ``BoardSnapshot/settlingDuplicates()``.
@MainActor
@Suite struct DuplicateRecordTests {
    /// A board record carrying every column twice, which is what two devices
    /// creating the same board from the same starter leaves behind.
    private func boardWithEveryColumnTwice(in sync: BoardSyncStore) throws -> StoredBoard {
        let context = sync.container.mainContext
        let board = StoredBoard(id: SeedData.defaultBoard.id)
        board.name = SeedData.defaultBoard.name
        board.createdAt = SeedData.defaultBoard.createdAt
        context.insert(board)
        for _ in 0..<2 {
            for (index, column) in SeedData.defaultBoard.columns.enumerated() {
                let row = StoredColumn(id: column.id)
                row.name = column.name
                row.short = column.short
                row.position = index
                row.board = board
                context.insert(row)
            }
        }
        try context.save()
        return board
    }

    private func columnRows(in sync: BoardSyncStore) throws -> Int {
        try sync.container.mainContext.fetch(FetchDescriptor<StoredColumn>()).count
    }

    // MARK: Reading

    @Test func aColumnWithTwoRecordsIsReadOnce() throws {
        let sync = try BoardSyncStore.inMemory()
        _ = try boardWithEveryColumnTwice(in: sync)

        let columns = try #require(try sync.load()).boards.first?.columns ?? []
        let ids = SeedData.defaultBoard.columns.count
        #expect(columns.map(\.id) == SeedData.defaultBoard.columns.map(\.id),
                "the board came back with \(columns.count) columns for \(ids) ids")
    }

    @Test func aSubTaskAndAnActivityEntryWithTwoRecordsAreReadOnce() throws {
        let sync = try BoardSyncStore.inMemory()
        let context = sync.container.mainContext
        var task = TaskItem(code: "NW-1", title: "Twice over")
        let subtask = SubTask(text: "Check it")
        let entry = ActivityEntry(.created, when: TestBoard.at(10))
        task.subtasks = [subtask]
        task.activity = [entry]
        try sync.apply(BoardSnapshot(tasks: [task], boards: [], labels: [], nextSerial: 100))

        let record = try #require(
            context.fetch(FetchDescriptor<StoredTask>()).first { $0.id == task.id }
        )
        let extraSubtask = StoredSubtask(id: subtask.id)
        extraSubtask.text = subtask.text
        extraSubtask.task = record
        context.insert(extraSubtask)
        let extraEntry = StoredActivity(id: entry.id)
        extraEntry.kind = try JSONEncoder().encode(entry.kind)
        extraEntry.when = entry.when
        extraEntry.task = record
        context.insert(extraEntry)
        try context.save()

        let loaded = try #require(try sync.load())
        let read = try #require(loaded.tasks.first { $0.id == task.id })
        #expect(read.subtasks.count == 1, "the checklist came back with \(read.subtasks.count) rows")
        #expect(read.activity.count == 1, "the feed came back with \(read.activity.count) entries")
    }

    // MARK: Writing

    /// The growth, which is what made this urgent rather than merely untidy.
    @Test func savingADuplicatedBoardDoesNotDoubleItAgain() throws {
        let sync = try BoardSyncStore.inMemory()
        _ = try boardWithEveryColumnTwice(in: sync)
        let doubled = try columnRows(in: sync)

        var board = try #require(try sync.load())
        board.boards[0].name = "Renamed"
        try sync.apply(board)

        let after = try columnRows(in: sync)
        #expect(after <= doubled,
                "one save took the store from \(doubled) column records to \(after)")
    }

    /// And the write is safe on its own, against a snapshot that arrives
    /// doubled from anywhere else — an older build's `board.json`, say.
    @Test func aSnapshotThatArrivesDoubledIsWrittenOnce() throws {
        let sync = try BoardSyncStore.inMemory()
        var board = SeedData.defaultBoard
        board.columns += board.columns
        try sync.apply(BoardSnapshot(tasks: [], boards: [board], labels: [], nextSerial: 100))

        let rows = try columnRows(in: sync)
        #expect(rows == SeedData.defaultBoard.columns.count)
    }

    // MARK: The file

    /// The file is the other door, and by now it is the poisoned one: it is
    /// written from whatever the last read handed over.
    @Test func aFileThatCarriesDuplicatesIsHealedWhenItIsRead() throws {
        let temp = TempBoard()
        var board = SeedData.defaultBoard
        board.columns += board.columns
        var doubled = BoardSnapshot(tasks: TestBoard.tasks(on: SeedData.defaultBoard),
                                    boards: [board], labels: LabelDef.seed, nextSerial: 100)
        doubled.tasks[0].subtasks += doubled.tasks[0].subtasks
        try temp.file.write(doubled, generation: temp.file.nextWriteGeneration())

        let read = try #require(temp.file.load().snapshot)
        #expect(read.boards[0].columns.map(\.id) == SeedData.defaultBoard.columns.map(\.id))
        #expect(read.tasks[0].subtasks.count == doubled.tasks[0].subtasks.count / 2)
    }
}
