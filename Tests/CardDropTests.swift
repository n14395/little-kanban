import Foundation
import Testing
@testable import Simple_Kanban

/// What a card dropped on another card is allowed to do.
///
/// A long-press drag aimed at reordering inside a column was reported to move
/// the card to **Done** and tick it: the column's count fell, the week's
/// completed meter moved, and the card's outstanding sub-tasks were closed on
/// the way — an act with no visible cause, dressed up as a reorder. `move`
/// carries every one of those consequences, and the two drop closures on the
/// board (`BoardTaskCard` and `BoardColumnView`) are the only callers a drag
/// reaches, so this is the seam where a mis-resolved drop turns into lost work.
///
/// A drop cannot be driven from here, so what is pinned is what each drop
/// closure calls with the arguments it would have: `move(_:to:before:)` with
/// the *target card's* placement for a card-to-card drop, and `move(_:to:)`
/// with the column's id for a drop on the column. Both directions are asserted
/// — the reorder must not complete anything, and the cross-column drop must
/// still complete — so neither can be made to pass by deleting the other's
/// behaviour.
@MainActor
@Suite struct CardDropTests {
    private static let third = TestBoard.taskID(40)
    private static let fourth = TestBoard.taskID(41)
    private static let fourthSubtask = TestBoard.subtaskID(40)

    /// Four cards in Backlog, the last of them carrying an outstanding
    /// sub-task: the shape the report was made against, where a move into Done
    /// has something to silently tick off.
    private func store() -> BoardStore {
        var extras: [TaskItem] = []
        extras.append(TaskItem(
            id: Self.third, code: "NW-140", columnID: BoardColumn.backlog.id,
            title: "Menu bar quick-add",
            activity: [ActivityEntry(.created, when: TestBoard.at(3_000))]
        ))
        extras.append(TaskItem(
            id: Self.fourth, code: "NW-141", columnID: BoardColumn.backlog.id,
            title: "Board templates",
            subtasks: [SubTask(id: Self.fourthSubtask, text: "Three starters", done: false)],
            activity: [ActivityEntry(.created, when: TestBoard.at(2_000))]
        ))
        return TestBoard.store(tasks: TestBoard.tasks + extras)
    }

    private func backlog(_ store: BoardStore) -> [TaskItem.ID] {
        store.boardTasks(in: BoardColumn.backlog.id).map(\.id)
    }

    private func kinds(_ store: BoardStore, _ id: TaskItem.ID) -> [ActivityEntry.Kind] {
        store[id]?.activity.map(\.kind) ?? []
    }

    private func movedOrTicked(_ kind: ActivityEntry.Kind) -> Bool {
        switch kind {
        case .moved, .subtasksCompletedOnDone: true
        default: false
        }
    }

    /// The reported failure, stated as the thing that must not happen.
    @Test func aCardDroppedOnASiblingReordersAndDoesNothingElse() throws {
        let store = store()
        let doneBefore = store.completedTasks.count
        #expect(backlog(store) == [TestBoard.dragDrop, TestBoard.cafe, Self.third, Self.fourth])

        // What `BoardTaskCard`'s drop closure calls when the last card in
        // Backlog is dropped on the first.
        let target = try #require(store[TestBoard.dragDrop])
        store.move(Self.fourth, to: target.placement, before: target.id)

        let moved = try #require(store[Self.fourth])
        #expect(backlog(store) == [Self.fourth, TestBoard.dragDrop, TestBoard.cafe, Self.third])
        #expect(moved.columnID == BoardColumn.backlog.id, "the card left the column it was reordered in")
        #expect(store.isDone(moved) == false, "a reorder completed the card")
        #expect(store.completedTasks.count == doneBefore, "the week's completed count moved")
        // The half that is silent: a card sent to Done has its outstanding
        // sub-tasks closed, and nothing on the board says so.
        #expect(moved.subtasks.map(\.done) == [false], "a reorder ticked off the card's sub-tasks")
        #expect(!kinds(store, Self.fourth).contains(where: movedOrTicked),
                "a reorder wrote a move into the card's history")
    }

    /// The other direction, so the assertion above cannot pass by the Done
    /// behaviour having been removed: a drop resolved onto a card *in* Done is
    /// a completion, and it does close the sub-tasks.
    @Test func aCardDroppedOnADoneCardIsACompletion() throws {
        let store = store()
        let target = try #require(store[TestBoard.palette])
        #expect(store.isDone(target))

        store.move(Self.fourth, to: target.placement, before: target.id)

        let moved = try #require(store[Self.fourth])
        #expect(store.isDone(moved))
        #expect(moved.subtasks.map(\.done) == [true])
        #expect(kinds(store, Self.fourth).contains { if case .subtasksCompletedOnDone = $0 { true } else { false } })
        #expect(backlog(store).count == 3)
    }

    /// What `BoardColumnView`'s drop closure calls: a card let go over the
    /// column it is already in, aimed at no card in particular, is aimed at
    /// where it already is.
    @Test func aCardDroppedOnItsOwnColumnStaysWhereItIs() throws {
        let store = store()
        let before = backlog(store)

        store.move(Self.fourth, to: BoardColumn.backlog.id)

        #expect(backlog(store) == before, "a drop on the column sent the card to the bottom of it")
        #expect(store.isDone(try #require(store[Self.fourth])) == false)
    }

    /// Reordering inside a column, which is now the drag's alone: Move Up /
    /// Move Down are gone from the card menu, and what replaced them names a
    /// *column* rather than a neighbour — see `ColumnDestinationItems`.
    ///
    /// Kept because the arithmetic is the drop caret's as well as the deleted
    /// menu's: `move` refuses a `before: nil` into the place a card already is,
    /// which is what stops a drop on a column sending a card to the bottom of
    /// its own, so walking a card *down* has to be said as the card below it
    /// moving above it. `DropCaretTests` names the gaps; this says the two
    /// spellings still land where they claim.
    @Test func aCardWalksUpAndDownItsColumnOneGapAtATime() throws {
        let store = store()
        let siblings = store.boardTasks(in: BoardColumn.backlog.id)
        let index = try #require(siblings.firstIndex { $0.id == Self.fourth })

        // Up: before the card above it.
        let above = siblings[index - 1]
        store.move(Self.fourth, to: try #require(store[Self.fourth]).placement, before: above.id)
        #expect(backlog(store) == [TestBoard.dragDrop, TestBoard.cafe, Self.fourth, Self.third])

        // Down: said backwards, as the card below moving above this one.
        let below = try #require(store[Self.third])
        store.move(below.id, to: below.placement, before: Self.fourth)
        #expect(backlog(store) == [TestBoard.dragDrop, TestBoard.cafe, Self.third, Self.fourth])
        #expect(store.isDone(try #require(store[Self.fourth])) == false)
    }

    /// The checklist's two menu items go through the same arithmetic the drop
    /// closure does, which is the whole reason `dropOffset` is a named
    /// expression: `move(fromOffsets:toOffset:)` counts in the pre-move array.
    @Test func theChecklistMenuMovesARowOneRowAtATime() throws {
        let store = TestBoard.store()
        let ids = try #require(store[TestBoard.dragDrop]?.subtasks.map(\.id))

        // Move Down on the first row: to = 1, which is one past it.
        #expect(ChecklistView.dropOffset(from: 0, to: 1) == 2)
        store.moveSubtask(
            fromOffsets: IndexSet(integer: 0),
            toOffset: ChecklistView.dropOffset(from: 0, to: 1), on: TestBoard.dragDrop
        )
        #expect(store[TestBoard.dragDrop]?.subtasks.map(\.id) == [ids[1], ids[0], ids[2]])

        // Move Up on the row it became: to = 0, which is exactly where it goes.
        #expect(ChecklistView.dropOffset(from: 1, to: 0) == 0)
        store.moveSubtask(
            fromOffsets: IndexSet(integer: 1),
            toOffset: ChecklistView.dropOffset(from: 1, to: 0), on: TestBoard.dragDrop
        )
        #expect(store[TestBoard.dragDrop]?.subtasks.map(\.id) == ids)
    }
}
