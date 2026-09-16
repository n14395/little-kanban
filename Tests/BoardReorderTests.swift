import Foundation
import Testing
@testable import LittleKanban

/// Re-ordering the board list by drag — the sidebar's rows on the desk and the
/// iPad, the drawer's on the phone.
///
/// A drag cannot be driven from here, so what is pinned is the seam every drop
/// closure calls: `dropBoard(_:at:)` with the caret the zone under the pointer
/// names — `ColumnReorderTests` for the list of boards, and both directions
/// asserted for its reason: `move(fromOffsets:toOffset:)` counts in the
/// pre-move array, so a board travelling *down* lands one past the gap's index
/// and one travelling *up* lands exactly on it. A rule that got that backwards
/// would still look right in half the drags anybody tried.
///
/// What the column suite pins that this one cannot: there is no Done row here.
/// A board list has no pinned last row, so the gap below the bottom board is a
/// real destination — the one drop the column list refuses that this list
/// takes, and it has a test of its own.
@MainActor
@Suite struct BoardReorderTests {
    /// Three boards: the seeded one, the empty support board, and one made
    /// here — the two fixtures plus the minimum a reorder needs to tell a
    /// board's two gaps from its neighbours'.
    private func store() -> BoardStore {
        let store = TestBoard.store(boards: TestBoard.boards)
        store.createBoard(named: "Gamma")
        return store
    }

    private func order(_ store: BoardStore) -> [Board.ID] {
        store.boards.map(\.id)
    }

    private func ids(_ store: BoardStore) -> (a: Board.ID, b: Board.ID, c: Board.ID) {
        (store.boards[0].id, store.boards[1].id, store.boards[2].id)
    }

    private func payload(_ index: Int, in store: BoardStore) -> BoardRowTransfer {
        BoardRowTransfer(store.boards[index])
    }

    @Test func aBoardDraggedDownLandsInTheGapItWasAimedAt() {
        let store = store()
        let (a, b, c) = ids(store)

        // The first board into the gap below the second: from 0, anchor 1, so
        // it lands second.
        #expect(store.dropBoard(payload(0, in: store), at: .below(b)))
        #expect(order(store) == [b, a, c])
    }

    @Test func aBoardDraggedUpLandsInTheGapItWasAimedAt() {
        let store = store()
        let (a, b, c) = ids(store)

        // The last board into the gap above the second: from 2, anchor 1, so
        // it lands second.
        #expect(store.dropBoard(payload(2, in: store), at: .above(b)))
        #expect(order(store) == [a, c, b])
    }

    /// **The head of the list is reachable**: nothing sits above the first row
    /// to aim at, which is the whole reason the drop takes a caret rather than
    /// the row under the pointer.
    @Test func aBoardCanLandInFrontOfTheFirstOne() {
        let store = store()
        let (a, b, c) = ids(store)

        #expect(store.dropBoard(payload(2, in: store), at: .above(a)))
        #expect(order(store) == [c, a, b])
    }

    /// **And the foot is too**, which is where this list parts from the
    /// columns': there is no Done row pinned to the end of it, so the gap
    /// below the bottom board is a destination like any other.
    @Test func aBoardCanLandBelowTheLastOne() {
        let store = store()
        let (a, b, c) = ids(store)

        #expect(store.dropBoard(payload(0, in: store), at: .below(c)))
        #expect(order(store) == [b, c, a])
    }

    /// A board let go over itself is a drag somebody thought better of, not an
    /// instruction. `false` says the drop was not taken, and nothing moved.
    @Test func aBoardDroppedOnItselfIsRefused() {
        let store = store()
        let (a, b, c) = ids(store)

        #expect(store.dropBoard(payload(1, in: store), at: .above(b)) == false)
        #expect(store.dropBoard(payload(1, in: store), at: .below(b)) == false)
        #expect(order(store) == [a, b, c])
    }

    /// **The two gaps a board already sits between are refused**, which is the
    /// other half of the same rule: the caret is drawn only where a release
    /// would move something, and a drop that reached the store anyway must not
    /// cost a ⌘Z for a board that did not move.
    @Test func theGapsEitherSideOfTheDraggedBoardAreRefused() {
        let store = store()
        let (a, b, c) = ids(store)
        let middle = payload(1, in: store)

        #expect(store.dropBoard(middle, at: .below(a)) == false)
        #expect(store.dropBoard(middle, at: .above(c)) == false)
        #expect(order(store) == [a, b, c])
    }

    /// A payload naming no board this store holds — a stale drag landing after
    /// the board was trashed — is refused rather than crashed on.
    @Test func aDropCarryingAnUnknownBoardIsRefused() {
        let store = store()
        let (a, b, c) = ids(store)
        let ghost = BoardRowTransfer(boardID: UUID(), name: "Ghost")

        #expect(store.dropBoard(ghost, at: .above(a)) == false)
        #expect(order(store) == [a, b, c])
    }
}
