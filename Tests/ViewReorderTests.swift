// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

/// Re-ordering the saved views by drag — the rows under **Views** in the
/// sidebar and the phone's drawer, lifted the way the boards above them are.
///
/// `BoardReorderTests` for the other list, and the same seam pinned for the
/// same reason: a drag cannot be driven from here, so what is asserted is
/// `dropView(_:at:)` with the caret the zone under the pointer names, in both
/// directions — `move(fromOffsets:toOffset:)` counts in the pre-move array,
/// so a row travelling *down* lands one past the gap's index and one
/// travelling *up* lands exactly on it, and a rule that got that backwards
/// would still look right in half the drags anybody tried.
@MainActor
@Suite struct ViewReorderTests {
    /// A fresh store's list is the seeded seven — more than the three rows a
    /// reorder needs to tell a view's own two gaps from its neighbours'.
    private func store() -> BoardStore {
        TestBoard.store()
    }

    private func order(_ store: BoardStore) -> [SavedView.ID] {
        store.views.map(\.id)
    }

    private func ids(_ store: BoardStore) -> (a: SavedView.ID, b: SavedView.ID, c: SavedView.ID) {
        (store.views[0].id, store.views[1].id, store.views[2].id)
    }

    private func payload(_ index: Int, in store: BoardStore) -> SavedViewTransfer {
        SavedViewTransfer(store.views[index])
    }

    @Test func aViewDraggedDownLandsInTheGapItWasAimedAt() {
        let store = store()
        let before = order(store)
        let (a, b, _) = ids(store)

        // The first view into the gap below the second: from 0, anchor 1, so
        // it lands second.
        #expect(store.dropView(payload(0, in: store), at: .below(b)))
        #expect(order(store) == [b, a] + before.dropFirst(2))
    }

    @Test func aViewDraggedUpLandsInTheGapItWasAimedAt() {
        let store = store()
        let before = order(store)
        let (a, b, c) = ids(store)

        // The third view into the gap above the second: from 2, anchor 1, so
        // it lands second.
        #expect(store.dropView(payload(2, in: store), at: .above(b)))
        #expect(order(store) == [a, c, b] + before.dropFirst(3))
    }

    /// **The head of the list is reachable**: nothing sits above the first row
    /// to aim at, which is the whole reason the drop takes a caret rather than
    /// the row under the pointer.
    @Test func aViewCanLandInFrontOfTheFirstOne() {
        let store = store()
        let before = order(store)
        let (a, b, c) = ids(store)

        #expect(store.dropView(payload(2, in: store), at: .above(a)))
        #expect(order(store) == [c, a, b] + before.dropFirst(3))
    }

    /// **And the foot is too** — like the boards' list and unlike the
    /// columns', nothing is pinned to the end of it, so the gap below the
    /// bottom row is a destination like any other.
    @Test func aViewCanLandBelowTheLastOne() throws {
        let store = store()
        let before = order(store)
        let last = try #require(store.views.last).id

        #expect(store.dropView(payload(0, in: store), at: .below(last)))
        #expect(order(store) == Array(before.dropFirst()) + [before[0]])
    }

    /// A view let go over itself is a drag somebody thought better of, not an
    /// instruction. `false` says the drop was not taken, and nothing moved.
    @Test func aViewDroppedOnItselfIsRefused() {
        let store = store()
        let before = order(store)
        let (_, b, _) = ids(store)

        #expect(store.dropView(payload(1, in: store), at: .above(b)) == false)
        #expect(store.dropView(payload(1, in: store), at: .below(b)) == false)
        #expect(order(store) == before)
    }

    /// **The two gaps a view already sits between are refused**, which is the
    /// other half of the same rule: the caret is drawn only where a release
    /// would move something, and a drop that reached the store anyway must not
    /// cost a ⌘Z for a view that did not move.
    @Test func theGapsEitherSideOfTheDraggedViewAreRefused() {
        let store = store()
        let before = order(store)
        let (a, _, c) = ids(store)
        let middle = payload(1, in: store)

        #expect(store.dropView(middle, at: .below(a)) == false)
        #expect(store.dropView(middle, at: .above(c)) == false)
        #expect(order(store) == before)
    }

    /// A payload naming no view this store holds — a stale drag landing after
    /// the view was deleted — is refused rather than crashed on.
    @Test func aDropCarryingAnUnknownViewIsRefused() {
        let store = store()
        let before = order(store)
        let ghost = SavedViewTransfer(viewID: UUID(), label: "Ghost")

        #expect(store.dropView(ghost, at: .above(before[0])) == false)
        #expect(order(store) == before)
    }
}
