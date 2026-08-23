import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

/// The Done behaviours, asked of a column that has been edited.
///
/// `ColumnTests` shows they follow the board's **last** column on a board built
/// with one. This suite is the harder question: they must go on following it
/// after that column has been renamed and recoloured, after the columns around
/// it have been shuffled, and on a board the user built by hand through
/// `addColumn` rather than one handed to the store whole. A build that resolved
/// Done once at launch, or kept a cached id, or matched on the *name*, passes
/// `ColumnTests` and fails here.
///
/// Every board here also carries a middle column *called* "Done", which is the
/// trap: nothing may behave off that word. It matters more now than it did when
/// a column carried a `ColumnRole` — the rule is position, and position is
/// exactly what a name gives no clue about.
@MainActor
@Suite struct DoneColumnTests {
    private static func columnID(_ n: UInt8) -> BoardColumn.ID {
        UUID(uuid: (0xC0, 0x1E, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    private static let inFlight = BoardColumn(
        id: columnID(1), name: "In flight", short: "Flight", dot: .hex(0xC2532F)
    )
    /// Named "Done" and complete in no sense at all. It is here so that a build
    /// matching on the word rather than on the position fails, and it is not a
    /// contrivance: "Done thinking about it" abbreviates to exactly this.
    private static let calledDone = BoardColumn(
        id: columnID(2), name: "Done", short: "Done", dot: .hex(0xA8A29A)
    )
    /// Last, and therefore the board's Done column — see ``Board/doneColumn``.
    /// Called something else, so the two facts cannot be confused.
    private static let landed = BoardColumn(
        id: columnID(3), name: "Landed", short: "Land", dot: .hex(0x1F6F63)
    )

    private static let columns = [inFlight, calledDone, landed]

    private static func taskID(_ n: UInt8) -> TaskItem.ID {
        UUID(uuid: (0x7A, 0x51, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    private static let work = taskID(1)
    private static let spare = taskID(2)

    private static func tasks() -> [TaskItem] {
        [
            TaskItem(
                id: work, code: "NW-300", columnID: inFlight.id, title: "Ship the thing",
                due: TestBoard.dueDay, priority: .high,
                subtasks: [SubTask(text: "Write it", done: true), SubTask(text: "Test it")],
                activity: [ActivityEntry(.created, when: TestBoard.at(10_000))],
                createdAt: TestBoard.at(10_000), updatedAt: TestBoard.at(10_000)
            ),
            TaskItem(
                id: spare, code: "NW-301", columnID: calledDone.id, title: "Something else",
                activity: [ActivityEntry(.created, when: TestBoard.at(9_000))],
                createdAt: TestBoard.at(9_000), updatedAt: TestBoard.at(9_000)
            ),
        ]
    }

    private static func store(file: BoardFile? = nil) -> BoardStore {
        BoardStore(tasks: tasks(), columns: columns, labels: LabelDef.seed,
                   accentTheme: .ember, nextSerial: BoardSnapshot.baseSerial, file: file)
    }

    /// The whole of what being Done is worth, asked at once: the tick, the chip,
    /// the two counts, and where `complete` sends a card.
    ///
    /// `task` must be a card that is *not* complete and has an outstanding
    /// sub-task, so every clause is capable of changing.
    private func expectDoneBehaviours(
        _ store: BoardStore, done: BoardColumn.ID, task: TaskItem.ID, _ label: String
    ) throws {
        let palette = Palette(colorScheme: .light)
        #expect(store.isDone(store[task]!) == false, "\(label): the probe started from Done")
        #expect(store[task]?.subtasks.contains(where: { !$0.done }) == true, "\(label): nothing left to tick")

        #expect(store.doneColumnID == done, "\(label): the board lost track of its Done column")
        store.complete(task)

        let completed = try #require(store[task])
        #expect(completed.columnID == done, "\(label): complete sent the card somewhere else")
        #expect(store.isDone(completed), "\(label): the card does not read as complete")
        #expect(store.isDone(column: done), "\(label): the column stopped answering")
        let allTicked = completed.subtasks.allSatisfy(\.done)
        #expect(allTicked, "\(label): the sub-tasks were not ticked")
        let recorded = completed.activity.contains {
            if case .subtasksCompletedOnDone = $0.kind { return true }
            return false
        }
        #expect(recorded, "\(label): the tick was not recorded")

        #expect(store.completedTasks.map(\.id) == [task], "\(label): the Done count is wrong")
        #expect(store.weeklyShippedCount(today: CalendarDay(Date.now)) == 1,
                "\(label): the weekly meter did not see it")
        #expect(palette.dueTone(urgency: .overdue, isDone: store.isDone(completed))
                == palette.dueTone(urgency: .overdue, isDone: true),
                "\(label): the due chip is not reading green")
    }

    // MARK: Nothing behaves off the word

    @Test func aColumnCalledDoneThatIsNotLastBehavesLikeAnyOtherColumn() {
        let store = Self.store()
        store.move(Self.work, to: Self.calledDone.id)

        let moved = store[Self.work]!
        #expect(store.isDone(moved) == false)
        #expect(store.isDone(column: Self.calledDone.id) == false)
        #expect(moved.subtasks.contains { !$0.done })      // no auto-tick
        #expect(store.completedTasks.isEmpty)
        #expect(store.weeklyShippedCount(today: CalendarDay(Date.now)) == 0)

        let palette = Palette(colorScheme: .light)
        #expect(palette.dueTone(urgency: .overdue, isDone: store.isDone(moved))
                != palette.dueTone(urgency: .overdue, isDone: true))

        // And `complete` goes past it to the column that is actually last.
        store.complete(Self.work)
        #expect(store[Self.work]?.columnID == Self.landed.id)
    }

    // MARK: The Done column, edited

    /// Renaming is allowed on purpose. Real boards call it Shipped, Live and
    /// Published — `SeedData.contentCalendar` ships one called Published — and
    /// the only thing pinned about this column is where it sits.
    @Test func renamingTheDoneColumnLeavesEveryDoneBehaviourWorking() throws {
        let store = Self.store()
        store.renameColumn(Self.landed.id, to: "Shipped", short: "Ship")
        #expect(store.column(id: Self.landed.id)?.name == "Shipped")
        #expect(store.isDone(column: Self.landed.id))
        try expectDoneBehaviours(store, done: Self.landed.id, task: Self.work, "after a rename")
    }

    @Test func recolouringTheDoneColumnLeavesEveryDoneBehaviourWorking() throws {
        let store = Self.store()
        store.recolorColumn(Self.landed.id, to: .accent)
        #expect(store.column(id: Self.landed.id)?.dot == .accent)
        #expect(store.isDone(column: Self.landed.id))
        try expectDoneBehaviours(store, done: Self.landed.id, task: Self.work, "after a recolour")
    }

    /// Shuffling the columns *in front of* Done changes nothing about it, which
    /// is the point of pinning it: up to v8 a reorder could change where every
    /// future tick sent a card, and the settings sheet had to ask before it
    /// moved anything.
    @Test func reorderingTheOtherColumnsLeavesEveryDoneBehaviourWorking() throws {
        let store = Self.store()
        store.moveColumn(fromOffsets: [1], toOffset: 0)
        #expect(store.columns.map(\.name) == ["Done", "In flight", "Landed"])
        try expectDoneBehaviours(store, done: Self.landed.id, task: Self.work, "after a reorder")
    }

    // MARK: Done stays last

    @Test func theDoneColumnCannotBeDraggedOffTheEnd() {
        let store = Self.store()
        store.moveColumn(fromOffsets: [2], toOffset: 0)
        #expect(store.columns.map(\.name) == ["In flight", "Done", "Landed"],
                "the Done column moved")
        #expect(store.doneColumnID == Self.landed.id)
    }

    /// A move *past* Done lands in front of it rather than being refused: the
    /// drop was heading for the end of the board, and the end of the working
    /// columns is the nearest thing to it that exists.
    @Test func aColumnDraggedPastDoneLandsInFrontOfIt() {
        let store = Self.store()
        store.moveColumn(fromOffsets: [0], toOffset: 3)
        #expect(store.columns.map(\.name) == ["Done", "In flight", "Landed"])
        #expect(store.doneColumnID == Self.landed.id)
    }

    @Test func aDropCannotCarryTheDoneColumnEither() throws {
        let store = Self.store()
        let boardID = try #require(store.activeBoardID)
        let payload = ColumnTransfer(Self.landed, on: boardID)
        #expect(store.dropColumn(payload, onto: Self.inFlight.id) == false)
        #expect(store.columns.map(\.name) == ["In flight", "Done", "Landed"])
    }

    @Test func aNewColumnGoesInFrontOfDoneRatherThanTakingItsPlace() throws {
        let store = Self.store()
        let added = try #require(store.addColumn(named: "Review", short: "Rev"))
        #expect(store.columns.map(\.name) == ["In flight", "Done", "Review", "Landed"],
                "the new column went on the end and took the finished work")
        #expect(store.doneColumnID == Self.landed.id, "the new column took the finished work")
        #expect(store.isDone(column: added) == false)
    }

    @Test func theOrderAndTheDoneColumnBothSurviveARelaunch() throws {
        let temp = TempBoard()
        let store = Self.store(file: temp.file)
        store.renameColumn(Self.landed.id, to: "Shipped", short: "Ship")
        store.recolorColumn(Self.landed.id, to: .accent)
        store.moveColumn(fromOffsets: [1], toOffset: 0)
        store.saveNow()

        let relaunched = BoardStore.restored(file: temp.file)
        #expect(relaunched.columns.map(\.name) == ["Done", "In flight", "Shipped"])
        #expect(relaunched.doneColumnID == Self.landed.id)
        try expectDoneBehaviours(relaunched, done: Self.landed.id, task: Self.work, "after a relaunch")
    }

    // MARK: A board the user builds

    /// The rule taken end to end through the public API: a board created in the
    /// app, columns added to it by hand, and every Done behaviour following the
    /// last one.
    ///
    /// **A new board arrives blank** — see `BoardStore.createBoard` — and gains
    /// its Done column along with the first column the user adds, so there is
    /// never a board holding nothing but somewhere to finish.
    @Test func aBoardBuiltByHandGetsItsDoneColumnWithItsFirstColumn() throws {
        let store = Self.store()
        let boardID = try #require(store.createBoard(named: "Gamma", codePrefix: "GA"))
        #expect(store.columns.isEmpty)

        let queueID = try #require(store.addColumn(named: "Queue", short: "Queue"))
        #expect(store.columns.count == 2, "the first column did not bring a Done column with it")
        let doneID = try #require(store.doneColumnID)
        #expect(doneID != queueID)
        #expect(store.columns.first?.id == queueID)

        // And the second goes in front of it rather than after.
        let landedID = try #require(store.addColumn(named: "Landed", short: "Land"))
        #expect(store.columns.map(\.id) == [queueID, landedID, doneID])

        // Neither the Done column nor the last working one can go.
        #expect(store.deleteColumn(doneID) == .doneColumn)
        #expect(store.deleteColumn(landedID) == nil)
        #expect(store.deleteColumn(queueID) == .lastWorkingColumn)

        let first = try #require(store.columns.first)
        let task = store.addTask(to: first.id, title: "Ship the thing")
        store.addSubtask(to: task, text: "Write it")
        store.addSubtask(to: task, text: "Test it")
        #expect(store[task]?.boardID == boardID)

        try expectDoneBehaviours(store, done: doneID, task: task, "on a board built in the app")
    }

    @Test func aBoardsDoneColumnIsItsOwnEvenWhenAnotherBoardHasOne() throws {
        let store = Self.store()
        let other = try #require(store.createBoard(named: "Gamma"))
        #expect(store.activeBoardID == other)
        store.addColumn(named: "Queue")
        let gammaDone = try #require(store.doneColumnID)
        #expect(store.deleteColumn(gammaDone) == .doneColumn)
        // And the first board's Done is refused just the same, from over here.
        #expect(store.deleteColumn(Self.landed.id) == .doneColumn)
        #expect(store.board(ofColumn: Self.landed.id)?.columns.count == 3)
    }

    /// The Done count, and the tidy-up standing next to it, belong to the board
    /// on screen. A count that spanned every board would have the meter climb
    /// when work landed somewhere the user is not looking, and "Archive
    /// completed" would file away a board they never opened.
    @Test func theDoneCountAndTheTidyUpAreTheBoardOnScreensOwn() throws {
        let store = Self.store()
        let first = try #require(store.activeBoardID)
        store.complete(Self.work)
        #expect(store.completedTasks.map(\.id) == [Self.work])

        let gamma = try #require(store.createBoard(named: "Gamma"))
        #expect(store.activeBoardID == gamma)
        store.addColumn(named: "Queue")
        let column = try #require(store.columns.first?.id)
        let onGamma = store.addTask(to: column, title: "Ship this too")
        store.complete(onGamma)
        #expect(store.completedTasks.map(\.id) == [onGamma], "the Done count is spanning boards")

        store.archiveCompleted()
        #expect(store[onGamma]?.isArchived == true)
        #expect(store[Self.work]?.isArchived == false,
                "tidying one board's Done column filed another board's away")

        store.selectBoard(first)
        #expect(store.completedTasks.map(\.id) == [Self.work])
    }

    /// Where a card lands when it is filed onto a board without being told
    /// where: the first column work can *start* in, which is never Done.
    @Test func filingOntoABoardLandsWhereWorkCanStartRatherThanInDone() throws {
        let store = Self.store()

        let captured = store.addTask(to: .inbox, title: "Captured")
        store.addSubtask(to: captured, text: "Still to do")
        store.file(captured, onto: try #require(store.activeBoardID))

        #expect(store[captured]?.columnID == Self.inFlight.id, "a filed card landed in Done")
        #expect(store.isDone(store[captured]!) == false)
        // And nothing was ticked off on the way in, which is what would have
        // happened had it landed in Done.
        #expect(store[captured]?.subtasks.allSatisfy { !$0.done } == true)
    }

    /// **A board with one column has nowhere to finish, not nothing to do.**
    ///
    /// The rule is "the last column", and a single column is trivially the last
    /// one — so the naive reading has every card on such a board arrive already
    /// complete. It is the work column, and the board has no Done column at all
    /// until it has a second. `BoardStore` will not build one of these — see
    /// `addColumn`, which mints the pair, and `deleteColumn`, which refuses the
    /// second-to-last — so this is about a board arriving in an import or a
    /// hand-edited file.
    @Test func aBoardWithASingleColumnHasNowhereToFinishRatherThanNowhereToWork() {
        let only = BoardColumn(name: "Only", short: "ON", dot: .accent)
        let bare = Board(name: "Bare", dot: .accent, columns: [only], codePrefix: "BA")
        #expect(bare.doneColumn == nil, "the only column read as Done")
        #expect(bare.workingColumns.map(\.id) == [only.id])
        #expect(bare.landingColumn?.id == only.id)

        // And an empty board has neither.
        let empty = Board(name: "Empty", dot: .accent, columns: [], codePrefix: "EM")
        #expect(empty.doneColumn == nil)
        #expect(empty.workingColumns.isEmpty)
        #expect(empty.landingColumn == nil)
    }

    // MARK: What the "move to" control offers

    /// The segments are the working columns — Done is not among them, because
    /// the completion button on the same surface already sends a card there and
    /// a segment for it is a second way to do the one thing here that is not
    /// really a move.
    @Test func theColumnsOfferedForAMoveStopBeforeDone() throws {
        let store = Self.store()
        let board = try #require(store.activeBoard)
        #expect(board.workingColumns.map(\.name) == ["In flight", "Done"])
        #expect(board.workingColumns.contains { $0.id == Self.landed.id } == false)
        #expect(board.columns.count == board.workingColumns.count + 1)
    }

    // MARK: Deleting a column

    @Test func deletingAColumnMovesItsCardsToWhicheverColumnIsFirstNow() throws {
        let store = Self.store()
        // Reorder first, so "the first column" is not the column that was first
        // when the board was built.
        store.moveColumn(fromOffsets: [1], toOffset: 0)
        #expect(store.columns.map(\.name) == ["Done", "In flight", "Landed"])

        #expect(store.deleteColumn(Self.inFlight.id) == nil)
        #expect(store[Self.work]?.columnID == Self.calledDone.id)
        #expect(store[Self.work]?.boardID == store.activeBoardID)
        // It went to the first column, not to the last one, and arriving there
        // did not tick anything off.
        #expect(store.isDone(store[Self.work]!) == false)
        #expect(store[Self.work]?.subtasks.contains(where: { !$0.done }) == true)
        let moved = store[Self.work]?.activity.first
        #expect(moved?.kind == .moved(columnID: Self.calledDone.id.uuidString, columnName: "Done"))
    }

    @Test func deletingTheDoneColumnIsRefusedAndChangesNothingAtAll() throws {
        let store = Self.store()
        let before = store.boards
        let tasks = store.tasks
        #expect(store.deleteColumn(Self.landed.id) == .doneColumn)
        #expect(store.boards == before)
        #expect(store.tasks == tasks)
        // The column called "Done" is not the one being protected: it goes.
        #expect(store.deleteColumn(Self.calledDone.id) == nil)
        #expect(store.columns.map(\.name) == ["In flight", "Landed"])
    }
}
