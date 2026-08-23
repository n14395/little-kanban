import Foundation
import Testing
@testable import Simple_Kanban

/// Dropping one column on another, which is what dragging a column by its name
/// does — see `BoardColumnView.name`.
///
/// A drag cannot be driven from here, so what is pinned is the seam the drop
/// closure calls: `dropColumn(_:onto:)` with the payload it would have been
/// handed. Both directions are asserted, because the off-by-one only shows in
/// one of them — `move(fromOffsets:toOffset:)` counts in the pre-move array, so
/// a column travelling *right* lands one past its target and one travelling
/// *left* lands exactly on it. A rule that got that backwards would still look
/// right in half the drags anybody tried.
@MainActor
@Suite struct ColumnReorderTests {
    private func store() -> BoardStore {
        TestBoard.store(boards: TestBoard.boards)
    }

    private func order(_ store: BoardStore) -> [BoardColumn.ID] {
        store.columns.map(\.id)
    }

    private func payload(_ column: BoardColumn, in store: BoardStore) -> ColumnTransfer {
        ColumnTransfer(column, on: store.activeBoardID ?? column.id)
    }

    /// Backlog, Up Next, In Progress, Done — the order the seed board starts in
    /// and the one every case here is measured against.
    private var seeded: [BoardColumn.ID] { BoardColumn.workflow.map(\.id) }

    @Test func aColumnDraggedRightTakesTheTargetsPlace() {
        let store = store()
        #expect(order(store) == seeded)

        // Backlog onto In Progress: from 0, to 2, so it lands third.
        #expect(store.dropColumn(payload(BoardColumn.backlog, in: store), onto: BoardColumn.inProgress.id))
        #expect(order(store) == [
            BoardColumn.upNext.id, BoardColumn.inProgress.id,
            BoardColumn.backlog.id, BoardColumn.done.id,
        ])
    }

    @Test func aColumnDraggedLeftTakesTheTargetsPlace() {
        let store = store()

        // Done onto Up Next: from 3, to 1, so it lands second.
        #expect(store.dropColumn(payload(BoardColumn.done, in: store), onto: BoardColumn.upNext.id))
        #expect(order(store) == [
            BoardColumn.backlog.id, BoardColumn.done.id,
            BoardColumn.upNext.id, BoardColumn.inProgress.id,
        ])
    }

    /// A column let go over itself is a drag somebody thought better of, not an
    /// instruction. `false` says the drop was not taken, and nothing moved.
    @Test func aColumnDroppedOnItselfIsRefused() {
        let store = store()

        #expect(store.dropColumn(payload(BoardColumn.upNext, in: store), onto: BoardColumn.upNext.id) == false)
        #expect(order(store) == seeded)
    }

    /// `moveColumn` is defined over the *active* board, so an index from
    /// another one names a place in a list this column is not in. Two macOS
    /// windows on two boards is how that becomes reachable rather than
    /// hypothetical.
    @Test func aColumnFromAnotherBoardIsRefused() {
        let store = store()
        #expect(store.activeBoardID != TestBoard.support.id)

        let elsewhere = ColumnTransfer(TestBoard.queue, on: TestBoard.support.id)
        #expect(store.dropColumn(elsewhere, onto: BoardColumn.upNext.id) == false)
        #expect(order(store) == seeded)
        // And the board it actually belongs to is untouched.
        #expect(store.boards.first { $0.id == TestBoard.support.id }?.columns.map(\.id)
                == [TestBoard.queue.id, TestBoard.closed.id])
    }

    /// A drop that names a column the board does not have — the payload
    /// outliving a delete on another window — is refused rather than resolving
    /// to whatever `firstIndex` happens to return.
    @Test func aColumnThatIsNoLongerThereIsRefused() {
        let store = store()
        let ghost = ColumnTransfer(
            boardID: store.activeBoardID ?? TestBoard.support.id,
            columnID: TestBoard.queue.id,
            name: "Queue"
        )

        #expect(store.dropColumn(ghost, onto: BoardColumn.upNext.id) == false)
        #expect(order(store) == seeded)
    }

    /// One ⌘Z puts the whole order back — `moveColumn` is `undoable`, and the
    /// drop goes through it rather than writing `columns` itself.
    @Test func aDroppedColumnIsOneUndoStep() {
        let (store, undo) = TestBoard.undoing(boards: TestBoard.boards)

        #expect(store.dropColumn(payload(BoardColumn.backlog, in: store), onto: BoardColumn.done.id))
        #expect(order(store) != seeded)

        undo.undo()
        #expect(order(store) == seeded)
    }
}
