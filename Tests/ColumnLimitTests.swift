import Foundation
import Testing
@testable import Cardstock

/// Per-column WIP limits — ``BoardColumn/limit`` and ``BoardStore/load(ofColumn:)``.
///
/// Two things here are worth more than the rest. The first is
/// ``archivedCardsAreNotWorkInProgress``: the obvious-looking API for "how many
/// cards are in this column" is `cardCount(inColumn:)`, it counts archived ones
/// deliberately — it exists for the delete-a-column warning — and a limit built
/// on it would climb for as long as the board is used until every column sat
/// permanently over one. The second is ``nothingIsRefusedByALimit``: a limit
/// here is advisory, that is a promise rather than an omission, and the only
/// way to keep a promise about something not happening is to ask.
@MainActor
@Suite struct ColumnLimitTests {
    private static func columnID(_ n: UInt8) -> BoardColumn.ID {
        UUID(uuid: (0x11, 0xB1, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    private static let queue = BoardColumn(
        id: columnID(1), name: "Queue", short: "Queue", dot: .hex(0xA8A29A)
    )
    private static let doing = BoardColumn(
        id: columnID(2), name: "Doing", short: "Doing", dot: .hex(0xC2532F)
    )
    private static let shipped = BoardColumn(
        id: columnID(3), name: "Shipped", short: "Ship", dot: .hex(0x1F6F63)
    )

    private static let columns = [queue, doing, shipped]

    private static func taskID(_ n: UInt8) -> TaskItem.ID {
        UUID(uuid: (0x11, 0xB2, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    /// `n` cards in Doing and one in Queue, so there is always something to
    /// move *into* a full column.
    private static func tasks(inDoing n: Int) -> [TaskItem] {
        var made = [
            TaskItem(
                id: taskID(0), code: "NW-400", columnID: queue.id, title: "Waiting",
                activity: [ActivityEntry(.created, when: TestBoard.at(9_000))],
                createdAt: TestBoard.at(9_000), updatedAt: TestBoard.at(9_000)
            )
        ]
        for index in 0..<n {
            made.append(
                TaskItem(
                    id: taskID(UInt8(index + 1)), code: "NW-4\(10 + index)",
                    columnID: doing.id, title: "In flight \(index)",
                    activity: [ActivityEntry(.created, when: TestBoard.at(8_000 - index))],
                    createdAt: TestBoard.at(8_000 - index), updatedAt: TestBoard.at(8_000 - index)
                )
            )
        }
        return made
    }

    private static func store(inDoing n: Int = 3, file: BoardFile? = nil) -> BoardStore {
        BoardStore(tasks: tasks(inDoing: n), columns: columns, labels: LabelDef.seed,
                   nextSerial: BoardSnapshot.baseSerial, file: file)
    }

    // MARK: The load

    @Test func aColumnWithNoLimitIsUnlimitedHoweverFullItIs() {
        let store = Self.store(inDoing: 40)
        #expect(store.load(ofColumn: Self.doing.id) == .unlimited)
        #expect(store.column(id: Self.doing.id)?.limit == nil)
    }

    @Test func theLoadFollowsTheCountAgainstTheLimit() {
        let store = Self.store(inDoing: 3)

        store.setColumnLimit(5, on: Self.doing.id)
        #expect(store.load(ofColumn: Self.doing.id) == .under)

        store.setColumnLimit(3, on: Self.doing.id)
        #expect(store.load(ofColumn: Self.doing.id) == .at)

        store.setColumnLimit(2, on: Self.doing.id)
        #expect(store.load(ofColumn: Self.doing.id) == .over)
    }

    /// The one that pins the choice of count. An archived card keeps its
    /// `columnID` — `performArchive` only stamps `archivedAt` — so
    /// `cardCount(inColumn:)` goes on counting it, correctly, for the warning
    /// it was written for. A limit must not: archived is off the board, and off
    /// the board is not work in progress.
    @Test func archivedCardsAreNotWorkInProgress() throws {
        let store = Self.store(inDoing: 3)
        store.setColumnLimit(3, on: Self.doing.id)
        #expect(store.load(ofColumn: Self.doing.id) == .at)

        store.archive(Self.taskID(1))

        // The card is still in the column by every other measure.
        #expect(store[Self.taskID(1)]?.columnID == Self.doing.id)
        #expect(store.cardCount(inColumn: Self.doing.id) == 3,
                "the delete warning's count must still see the archived card")
        // …and the limit has stopped counting it.
        #expect(store.load(ofColumn: Self.doing.id) == .under)
        #expect(store.visibleTasks(in: Self.doing.id).count == 2)
    }

    /// The board is not drawn from the search query — see
    /// `BoardStore.searchResults` — so there is no state in which the pill's
    /// count and the limit's count are different numbers. Written down because
    /// the alternative was very nearly built: a rule hiding the limit while
    /// filtering, for a filter this app does not have.
    @Test func theSearchQueryDoesNotChangeTheLoad() {
        let store = Self.store(inDoing: 3)
        store.setColumnLimit(2, on: Self.doing.id)
        #expect(store.load(ofColumn: Self.doing.id) == .over)

        store.query = "nothing on this board matches this"
        #expect(store.load(ofColumn: Self.doing.id) == .over,
                "a query narrowed the column's load, so the pill and the limit now disagree")
        #expect(store.visibleTasks(in: Self.doing.id).count == 3)
    }

    @Test func theLoadOfAColumnNoBoardHasIsUnlimited() {
        #expect(Self.store().load(ofColumn: UUID()) == .unlimited)
    }

    /// The type on its own, at the edges the store cannot easily be put into.
    @Test func theLoadTypeMapsCountsToStates() {
        #expect(ColumnLoad(count: 0, limit: nil) == .unlimited)
        #expect(ColumnLoad(count: 9, limit: 0) == .unlimited)
        #expect(ColumnLoad(count: 9, limit: -3) == .unlimited)
        #expect(ColumnLoad(count: 0, limit: 1) == .under)
        #expect(ColumnLoad(count: 1, limit: 1) == .at)
        #expect(ColumnLoad(count: 2, limit: 1) == .over)
        #expect(ColumnLoad(count: 0, limit: 1).isWarning == false)
        #expect(ColumnLoad(count: 1, limit: 1).isWarning)
        #expect(ColumnLoad(count: 2, limit: 1).isWarning)
    }

    // MARK: Setting one

    @Test func aLimitIsClampedRatherThanRefused() throws {
        let store = Self.store()

        store.setColumnLimit(500, on: Self.doing.id)
        #expect(store.column(id: Self.doing.id)?.limit == BoardStore.columnLimitRange.upperBound)

        store.setColumnLimit(1, on: Self.doing.id)
        #expect(store.column(id: Self.doing.id)?.limit == 1)
    }

    /// Zero clears, and so does `nil`. A number field passes through `0` on the
    /// way to every other number, and a column nothing may ever be in is not a
    /// thing anybody means — see ``BoardStore/setColumnLimit(_:on:)``.
    @Test func zeroAndNilBothClearTheLimit() {
        let store = Self.store()

        store.setColumnLimit(4, on: Self.doing.id)
        store.setColumnLimit(0, on: Self.doing.id)
        #expect(store.column(id: Self.doing.id)?.limit == nil)

        store.setColumnLimit(4, on: Self.doing.id)
        store.setColumnLimit(nil, on: Self.doing.id)
        #expect(store.column(id: Self.doing.id)?.limit == nil)
    }

    @Test func aLimitIsSetOnOneColumnOnly() {
        let store = Self.store()
        store.setColumnLimit(2, on: Self.doing.id)
        #expect(store.column(id: Self.queue.id)?.limit == nil)
        #expect(store.column(id: Self.shipped.id)?.limit == nil)
    }

    @Test func settingALimitIsOneUndoableStep() {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let store = Self.store()
        store.undoManager = undo

        step(undo) { store.setColumnLimit(3, on: Self.doing.id) }
        #expect(undo.undoActionName != "", "setting a limit registered no undo step")
        undo.undo()
        #expect(store.column(id: Self.doing.id)?.limit == nil)
    }

    /// Setting the limit a column already has changes nothing and registers
    /// nothing — the way `recolorColumn` does not re-register a colour it is
    /// already wearing. A no-op that costs a ⌘Z is a ⌘Z that appears to do
    /// nothing when it is pressed.
    @Test func settingTheLimitAColumnAlreadyHasRegistersNothing() {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let store = Self.store()
        store.undoManager = undo

        // `undoActionName`, not `canUndo`: `step` hands the manager a group per
        // action whether or not anything registered into it, so an empty group
        // still leaves `canUndo` true. The *name* is what only a registration
        // sets — the same reading `aRefusedDeleteRegistersNothingAndSavesNothing`
        // takes.
        step(undo) { store.setColumnLimit(nil, on: Self.doing.id) }
        #expect(undo.undoActionName == "", "clearing a limit that was never set registered a step")

        step(undo) { store.setColumnLimit(3, on: Self.doing.id) }
        undo.removeAllActions()
        step(undo) { store.setColumnLimit(3, on: Self.doing.id) }
        #expect(undo.undoActionName == "", "setting the limit a column already has registered a step")
    }

    @Test func aLimitSurvivesTheFileRoundTrip() async throws {
        let temp = TempBoard()
        let store = Self.store(file: temp.file)
        store.setColumnLimit(4, on: Self.doing.id)
        store.saveNow()

        let reloaded = try #require(temp.file.load().snapshot, "the board did not load back")
        let board = try #require(reloaded.boards.first)
        #expect(board.columns.first { $0.id == Self.doing.id }?.limit == 4)
        #expect(board.columns.first { $0.id == Self.queue.id }?.limit == nil)
        // The file is written at the version that knows about limits, so a
        // build that does not will refuse it rather than drop them. The floor
        // rather than the exact number: limits landed in v14 and every version
        // after it still carries them, so pinning the equality made the next
        // bump — v15's dated lists — look like a limits regression.
        #expect(reloaded.version == BoardSnapshot.currentVersion)
        #expect(BoardSnapshot.currentVersion >= 14)
    }

    /// A column with no limit encodes no key at all, which is what makes a v14
    /// file readable as one by everything that does not care.
    @Test func anUnlimitedColumnWritesNoKey() throws {
        let store = Self.store()

        // The board's columns alone, not the whole snapshot: a saved view has a
        // `limit` of its own — its card cap — and searching the file for the
        // word would find that instead and pass for the wrong reason.
        func columnBytes() throws -> String {
            let board = try #require(store.exportedSnapshot.boards.first)
            return try #require(String(data: try JSONEncoder().encode(board.columns), encoding: .utf8))
        }

        #expect(try columnBytes().contains("\"limit\"") == false,
                "an unlimited column wrote a limit key into the file")

        store.setColumnLimit(3, on: Self.doing.id)
        #expect(try columnBytes().contains("\"limit\""),
                "a column with a limit wrote no limit key")
    }

    // MARK: The promise

    /// **A limit refuses nothing.** Every way a card can arrive in a column,
    /// aimed at one that is already over its limit.
    ///
    /// This is the whole of the advisory bargain: refusing a drop would punish
    /// the exact moment somebody is trying to reorganise a full column, which
    /// is the moment a full column most needs it. If a future change ever does
    /// want to enforce a limit, this test is the one that has to be deleted on
    /// purpose rather than quietly stop being true.
    @Test func nothingIsRefusedByALimit() throws {
        let store = Self.store(inDoing: 3)
        store.setColumnLimit(1, on: Self.doing.id)
        #expect(store.load(ofColumn: Self.doing.id) == .over)

        // Moved in.
        store.move(Self.taskID(0), to: Self.doing.id)
        #expect(store[Self.taskID(0)]?.columnID == Self.doing.id, "a move into a full column was refused")

        // Added by the composer.
        let added = store.addTask(to: Self.doing.id, title: "One more")
        #expect(store[added]?.columnID == Self.doing.id, "an add into a full column was refused")

        // Pasted as a batch.
        let pasted = store.addTasks(to: Self.doing.id, titles: ["A", "B", "C"])
        #expect(pasted.count == 3, "a paste into a full column was refused")
        #expect(pasted.allSatisfy { store[$0]?.columnID == Self.doing.id })

        // Dropped on the column's ground.
        let dropped = store.addTask(to: Self.queue.id, title: "Dragged")
        store.drop(dropped, onGroundOf: store.placement(forColumn: Self.doing.id))
        #expect(store[dropped]?.columnID == Self.doing.id, "a drop into a full column was refused")

        // Three to begin with, plus the move, the add, the three pasted and the drop.
        #expect(store.visibleTasks(in: Self.doing.id).count == 9)
        #expect(store.load(ofColumn: Self.doing.id) == .over)
    }

    /// A limited column takes a card completed into it, too — the Done column
    /// is a column like any other and may carry a limit, and a tick that
    /// silently did nothing would be the worst failure of the lot.
    @Test func tickingACardIntoAFullDoneColumnStillCompletesIt() throws {
        let store = Self.store(inDoing: 1)
        store.setColumnLimit(1, on: Self.shipped.id)
        let first = store.addTask(to: Self.shipped.id, title: "Already shipped")
        #expect(store.load(ofColumn: Self.shipped.id) == .at)

        store.complete(Self.taskID(1))
        #expect(store[Self.taskID(1)]?.columnID == Self.shipped.id, "a tick into a full Done column was refused")
        #expect(store.isDone(try #require(store[Self.taskID(1)])))
        #expect(store.load(ofColumn: Self.shipped.id) == .over)
        #expect(store[first] != nil)
    }
}
