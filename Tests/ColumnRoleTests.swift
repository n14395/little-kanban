import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

/// The three Done behaviours, asked of a column that has been edited.
///
/// `ColumnTests` shows they follow the *role* on a board built with one. This
/// suite is the harder question: they must go on following it after the column
/// has been renamed, recoloured and moved, and they must follow it onto a column
/// the user made through `addColumn` rather than one handed to the store whole.
/// A build that resolved Done once at launch, or that kept a cached id, or that
/// matched on the name instead of the id, passes `ColumnTests` and fails here.
///
/// Every board here also carries a `.backlog` column *called* "Done", which is
/// the trap: nothing may behave off that word.
@MainActor
@Suite struct ColumnRoleTests {
    private static func columnID(_ n: UInt8) -> BoardColumn.ID {
        UUID(uuid: (0xC0, 0x1E, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    private static let inFlight = BoardColumn(
        id: columnID(1), name: "In flight", short: "Flight", dot: .hex(0xC2532F), role: .active
    )
    /// Named "Done" and complete in no sense at all. It is here so that a build
    /// matching on the word rather than on the role fails, and it is not a
    /// contrivance: "Done thinking about it" abbreviates to exactly this.
    private static let calledDone = BoardColumn(
        id: columnID(2), name: "Done", short: "Done", dot: .hex(0xA8A29A), role: .backlog
    )
    private static let landed = BoardColumn(
        id: columnID(3), name: "Landed", short: "Land", dot: .hex(0x1F6F63), role: .done
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

    /// The whole of what `.done` is worth, asked at once: the tick, the chip,
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
        #expect(store.role(of: completed) == .done, "\(label): the role stopped answering")
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
        #expect(palette.dueTone(urgency: .overdue, role: store.role(of: completed))
                == palette.dueTone(urgency: .overdue, role: .done),
                "\(label): the due chip is not reading green")
    }

    // MARK: Nothing behaves off the word

    @Test func aColumnCalledDoneThatIsNotDoneBehavesLikeAnyOtherColumn() {
        let store = Self.store()
        store.move(Self.work, to: Self.calledDone.id)

        let moved = store[Self.work]!
        #expect(store.isDone(moved) == false)
        #expect(store.role(of: moved) == .backlog)
        #expect(moved.subtasks.contains { !$0.done })      // no auto-tick
        #expect(store.completedTasks.isEmpty)
        #expect(store.weeklyShippedCount(today: CalendarDay(Date.now)) == 0)

        let palette = Palette(colorScheme: .light)
        #expect(palette.dueTone(urgency: .overdue, role: store.role(of: moved))
                != palette.dueTone(urgency: .overdue, role: .done))

        // And `complete` goes past it to the column that actually has the role.
        store.complete(Self.work)
        #expect(store[Self.work]?.columnID == Self.landed.id)
    }

    // MARK: The Done column, edited

    @Test func renamingTheDoneColumnLeavesEveryDoneBehaviourWorking() throws {
        let store = Self.store()
        store.renameColumn(Self.landed.id, to: "Shipped", short: "Ship")
        #expect(store.column(id: Self.landed.id)?.name == "Shipped")
        #expect(store.column(id: Self.landed.id)?.role == .done)
        try expectDoneBehaviours(store, done: Self.landed.id, task: Self.work, "after a rename")
    }

    @Test func recolouringTheDoneColumnLeavesEveryDoneBehaviourWorking() throws {
        let store = Self.store()
        store.recolorColumn(Self.landed.id, to: .accent)
        #expect(store.column(id: Self.landed.id)?.dot == .accent)
        #expect(store.column(id: Self.landed.id)?.role == .done)
        try expectDoneBehaviours(store, done: Self.landed.id, task: Self.work, "after a recolour")
    }

    @Test func movingTheDoneColumnToTheFrontLeavesEveryDoneBehaviourWorking() throws {
        let store = Self.store()
        store.moveColumn(fromOffsets: [2], toOffset: 0)
        #expect(store.columns.map(\.name) == ["Landed", "In flight", "Done"])
        try expectDoneBehaviours(store, done: Self.landed.id, task: Self.work, "after a reorder")
    }

    @Test func aDoneColumnRenamedRecolouredAndMovedIsStillDoneAfterARelaunch() throws {
        let temp = TempBoard()
        let store = Self.store(file: temp.file)
        store.renameColumn(Self.landed.id, to: "Shipped", short: "Ship")
        store.recolorColumn(Self.landed.id, to: .accent)
        store.moveColumn(fromOffsets: [2], toOffset: 0)
        store.saveNow()

        let relaunched = BoardStore.restored(file: temp.file)
        #expect(relaunched.columns.map(\.name) == ["Shipped", "In flight", "Done"])
        #expect(relaunched.columns.map(\.role) == [.done, .active, .backlog])
        try expectDoneBehaviours(relaunched, done: Self.landed.id, task: Self.work, "after a relaunch")
    }

    // MARK: A Done column the user made

    /// The whole point of the role, taken end to end through the public API: a
    /// board created in the app, a column added to it with `.done`, the seeded
    /// Done deleted, and every Done behaviour following the new one.
    @Test func aColumnTheUserAddsWithTheDoneRoleCarriesEveryDoneBehaviour() throws {
        let store = Self.store()
        let boardID = try #require(store.createBoard(named: "Gamma", codePrefix: "GA"))
        let seeded = try #require(store.columns.first { $0.role == .done })

        // The seeded Done cannot go while it is the only one — that refusal is
        // what makes the order here the only order.
        #expect(store.deleteColumn(seeded.id) == .lastDoneColumn)
        let landedID = try #require(
            store.addColumn(named: "Landed", short: "Land", dot: .hex(0x1F6F63), role: .done)
        )
        #expect(store.deleteColumn(seeded.id) == nil)
        #expect(store.columns.count(where: { $0.role == .done }) == 1)

        let first = try #require(store.columns.first)
        let task = store.addTask(to: first.id, title: "Ship the thing")
        store.addSubtask(to: task, text: "Write it")
        store.addSubtask(to: task, text: "Test it")
        #expect(store[task]?.boardID == boardID)

        try expectDoneBehaviours(store, done: landedID, task: task, "on a board built in the app")
    }

    @Test func aBoardsLastDoneColumnIsItsOwnEvenWhenAnotherBoardHasOne() throws {
        let store = Self.store()
        let other = try #require(store.createBoard(named: "Gamma"))
        #expect(store.activeBoardID == other)
        // Gamma has a Done of its own, so the refusal on Gamma's cannot be
        // explained by "some board somewhere still has one".
        let gammaDone = try #require(store.columns.first { $0.role == .done })
        #expect(store.deleteColumn(gammaDone.id) == .lastDoneColumn)
        // And the first board's Done is refused just the same, from over here.
        #expect(store.deleteColumn(Self.landed.id) == .lastDoneColumn)
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
    /// where: the first column work can *start* in. The board here has been
    /// reordered so that its first column is Done, which is the only
    /// arrangement in which this can fail.
    @Test func filingOntoABoardLandsWhereWorkCanStartRatherThanInDone() throws {
        let store = Self.store()
        store.moveColumn(fromOffsets: [2], toOffset: 0)
        #expect(store.columns.first?.role == .done)

        let captured = store.addTask(to: .inbox, title: "Captured")
        store.addSubtask(to: captured, text: "Still to do")
        store.file(captured, onto: try #require(store.activeBoardID))

        #expect(store[captured]?.columnID == Self.inFlight.id, "a filed card landed in Done")
        #expect(store.isDone(store[captured]!) == false)
        // And nothing was ticked off on the way in, which is what would have
        // happened had it landed in Done.
        #expect(store[captured]?.subtasks.allSatisfy { !$0.done } == true)
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
        // It went to the first column, not to the one with the Done role, and
        // arriving there did not tick anything off.
        #expect(store.isDone(store[Self.work]!) == false)
        #expect(store[Self.work]?.subtasks.contains(where: { !$0.done }) == true)
        let moved = store[Self.work]?.activity.first
        #expect(moved?.kind == .moved(columnID: Self.calledDone.id.uuidString, columnName: "Done"))
    }

    @Test func deletingTheDoneColumnIsRefusedAndChangesNothingAtAll() throws {
        let store = Self.store()
        let before = store.boards
        let tasks = store.tasks
        #expect(store.deleteColumn(Self.landed.id) == .lastDoneColumn)
        #expect(store.boards == before)
        #expect(store.tasks == tasks)
        // The column called "Done" is not the one being protected: it goes.
        #expect(store.deleteColumn(Self.calledDone.id) == nil)
        #expect(store.columns.map(\.name) == ["In flight", "Landed"])
    }
}
