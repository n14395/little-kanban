import Foundation
import Testing
@testable import Cardstock

/// Dropping a column into the gap a caret names, which is what dragging a
/// column row up or down the board settings sheet does — see `ColumnRowGrip`
/// and `dropZones(for:)` in `BoardSettingsView`.
///
/// **The board's own strip no longer offers this.** A column header was a
/// grip, and on a horizontal `ScrollView` full of cards that is a gesture
/// competing with two others for the same touch; the order of the columns is
/// now the settings sheet's list and *Move Left* / *Move Right* on the column's
/// menu, both of which say where a column is going without asking anyone to aim.
/// `theBoardStripOffersNoColumnDrag` is what keeps the grip from coming back.
///
/// A drag cannot be driven from here, so what is pinned is the seam the drop
/// closure calls: `dropColumn(_:at:)` with the caret the zone under the pointer
/// names. Both directions are asserted, because the off-by-one shows in only one
/// of them — `move(fromOffsets:toOffset:)` counts in the pre-move array, so a
/// column travelling *down* lands one past the gap's index and one travelling
/// *up* lands exactly on it. A rule that got that backwards would still look
/// right in half the drags anybody tried.
///
/// **It used to be `dropColumn(_:onto:)`**, which took the row under the
/// pointer and worked out the gap from the direction of travel. That is what
/// made the sheet light up a row the column was not going to land in, and it
/// left the top of the list unnameable: there is no row you can aim at from
/// above to get in front of the first one.
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

        // Backlog into the gap below In Progress: from 0, anchor 2, so it
        // lands third.
        #expect(store.dropColumn(payload(BoardColumn.backlog, in: store), at: .below(BoardColumn.inProgress.id)))
        #expect(order(store) == [
            BoardColumn.upNext.id, BoardColumn.inProgress.id,
            BoardColumn.backlog.id, BoardColumn.done.id,
        ])
    }

    @Test func aColumnDraggedLeftTakesTheTargetsPlace() {
        let store = store()

        // In Progress into the gap above Up Next: from 2, anchor 1, so it
        // lands second.
        #expect(store.dropColumn(payload(BoardColumn.inProgress, in: store), at: .above(BoardColumn.upNext.id)))
        #expect(order(store) == [
            BoardColumn.backlog.id, BoardColumn.inProgress.id,
            BoardColumn.upNext.id, BoardColumn.done.id,
        ])
    }

    /// **The Done column is not a payload.** Nothing offers it as a drag — see
    /// `ColumnRowGrip`, which is disabled on the Done row — so a drop carrying
    /// it came from somewhere the interface does not go, and `false` is the
    /// answer to it. Done is the board's last column and that is what makes it
    /// the one a tick sends cards to.
    @Test func aDropCarryingTheDoneColumnIsRefused() {
        let store = store()
        #expect(store.dropColumn(payload(BoardColumn.done, in: store), at: .above(BoardColumn.upNext.id)) == false)
        #expect(order(store) == seeded)
    }

    /// **The gap above Done is the end of the board**, and it is the last one
    /// the sheet offers: the Done row draws one zone rather than two, so there
    /// is no caret below it to aim at.
    @Test func theGapAboveDoneIsTheEndOfTheBoard() {
        let store = store()
        #expect(store.dropColumn(payload(BoardColumn.backlog, in: store), at: .above(BoardColumn.done.id)))
        #expect(order(store) == [
            BoardColumn.upNext.id, BoardColumn.inProgress.id,
            BoardColumn.backlog.id, BoardColumn.done.id,
        ])
    }

    /// And nothing lands *after* it, whatever a payload asks for: being last is
    /// what makes Done the column a tick sends cards to.
    @Test func nothingLandsAfterDone() {
        let store = store()
        #expect(store.dropColumn(payload(BoardColumn.backlog, in: store), at: .below(BoardColumn.done.id)) == false)
        #expect(order(store) == seeded)
    }

    /// A column let go over itself is a drag somebody thought better of, not an
    /// instruction. `false` says the drop was not taken, and nothing moved.
    @Test func aColumnDroppedOnItselfIsRefused() {
        let store = store()

        #expect(store.dropColumn(payload(BoardColumn.upNext, in: store), at: .above(BoardColumn.upNext.id)) == false)
        #expect(store.dropColumn(payload(BoardColumn.upNext, in: store), at: .below(BoardColumn.upNext.id)) == false)
        #expect(order(store) == seeded)
    }

    /// **The two gaps a column already sits between are refused**, which is the
    /// other half of the same rule: the caret is drawn only where a release
    /// would move something, so neither of these is ever offered — and a drop
    /// that reached the store anyway must not cost a ⌘Z for a column that did
    /// not move.
    @Test func theGapsEitherSideOfTheDraggedColumnAreRefused() {
        let store = store()
        let upNext = payload(BoardColumn.upNext, in: store)

        #expect(store.dropColumn(upNext, at: .below(BoardColumn.backlog.id)) == false)
        #expect(store.dropColumn(upNext, at: .above(BoardColumn.inProgress.id)) == false)
        #expect(order(store) == seeded)
    }

    /// **The head of the list is reachable**, which under `dropColumn(_:onto:)`
    /// it was not: nothing sits above the first row to aim at, so a column could
    /// only be made first by dropping it on the row that was.
    @Test func aColumnCanLandInFrontOfTheFirstOne() {
        let store = store()
        #expect(store.dropColumn(payload(BoardColumn.inProgress, in: store), at: .above(BoardColumn.backlog.id)))
        #expect(order(store) == [
            BoardColumn.inProgress.id, BoardColumn.backlog.id,
            BoardColumn.upNext.id, BoardColumn.done.id,
        ])
    }

    /// `moveColumn` is defined over the *active* board, so an index from
    /// another one names a place in a list this column is not in. Two macOS
    /// windows on two boards is how that becomes reachable rather than
    /// hypothetical.
    @Test func aColumnFromAnotherBoardIsRefused() {
        let store = store()
        #expect(store.activeBoardID != TestBoard.support.id)

        let elsewhere = ColumnTransfer(TestBoard.queue, on: TestBoard.support.id)
        #expect(store.dropColumn(elsewhere, at: .above(BoardColumn.upNext.id)) == false)
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

        #expect(store.dropColumn(ghost, at: .above(BoardColumn.upNext.id)) == false)
        #expect(order(store) == seeded)
    }

    /// One ⌘Z puts the whole order back — `moveColumn` is `undoable`, and the
    /// drop goes through it rather than writing `columns` itself.
    @Test func aDroppedColumnIsOneUndoStep() {
        let (store, undo) = TestBoard.undoing(boards: TestBoard.boards)

        // Grouped by hand, for the reason `step` documents: `undoing` turns
        // `groupsByEvent` off, and registering an undo outside a group throws
        // rather than failing an expectation.
        var landed = false
        step(undo) {
            landed = store.dropColumn(payload(BoardColumn.backlog, in: store), at: .above(BoardColumn.done.id))
        }
        #expect(landed)
        #expect(order(store) != seeded)

        undo.undo()
        #expect(order(store) == seeded)
    }

    /// **The board's column strip carries no column drag**, which is a claim
    /// about the code rather than about the store: `dropColumn` answers the same
    /// whether or not anything on screen is wired to it, and the thing that was
    /// removed was the wiring. `UITests/ColumnDragTests` used to press it; there
    /// is no gesture left to press, and a UI test that drags and asserts nothing
    /// moved passes just as readily when the drag was simply lost.
    ///
    /// Read off the source the way `DragLiftTests` reads the card's session
    /// handler, and against the *masked* text so the prose above explaining why
    /// the grip is gone cannot satisfy it.
    @Test func theBoardStripOffersNoColumnDrag() {
        guard SourceTree.isReachable else { return }
        guard let file = SourceTree.files().first(where: { $0.path == "Shared/BoardColumnView.swift" })
        else {
            Issue.record("the board column has moved file")
            return
        }

        #expect(file.source.contains("ColumnTransfer") == false,
                "the board's column strip is lifting or landing a column again")
        #expect(file.source.contains("draggable") == false,
                "something on the board's column strip is draggable again")
    }
}
