// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

/// When a card stops looking as though it is being carried.
///
/// The reported bug: a card dragged from one column to another appeared back in
/// the column it had left — at full strength, in its old place — and only then
/// moved. A frame-by-frame read of the recording puts the two events a tenth of
/// a second apart, which is long enough to read as the drag having failed and
/// then changed its mind.
///
/// The cause is an ordering one. On macOS a drop is not one moment but four:
/// the mouse comes up, the drag image flies into place, the session reports
/// `ended`, and *then* SwiftUI finishes loading the payload off the pasteboard
/// and calls the `dropDestination` handler that actually moves the card. The
/// lift used to end at the third of those and the move happened at the fourth,
/// so the card was drawn undimmed in its old column in between.
///
/// None of that can be driven from a unit test — there is no drag session to
/// start. What can be pinned is the pair of facts the fix rests on: the store
/// has one call that ends a lift and every route uses it, and the view ends the
/// lift on the phase that means "the payload has landed" rather than the one
/// that means "the mouse is up".
@MainActor
@Suite struct DragLiftTests {
    private let backlog = BoardColumn.backlog.id
    private let doing = BoardColumn.inProgress.id

    // MARK: The store's end of it

    @Test func endingALiftTakesTheHighlightOffEverywhereItCouldBe() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.dragDrop
        store.dropTargetColumnID = backlog
        store.dropTargetCaret = .above(TestBoard.cafe)
        store.isInboxDropTarget = true

        store.endDrag()

        #expect(store.draggingID == nil)
        #expect(store.dropTargetColumnID == nil)
        #expect(store.dropTargetCaret == nil)
        #expect(store.isInboxDropTarget == false)
    }

    /// The Inbox panel's highlight is read as `isInboxDropTarget && draggingID
    /// != nil`, so clearing the card alone would hide it. It is cleared anyway:
    /// a stale `true` sitting in the store is a highlight that comes back by
    /// itself the moment the next card is lifted.
    @Test func aMoveEndsTheLiftItCameFrom() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.dragDrop
        store.dropTargetColumnID = doing
        store.dropTargetCaret = .above(TestBoard.cafe)
        store.isInboxDropTarget = true

        store.move(TestBoard.dragDrop, to: doing)

        #expect(store.draggingID == nil)
        #expect(store.dropTargetColumnID == nil)
        #expect(store.dropTargetCaret == nil)
        #expect(store.isInboxDropTarget == false)
    }

    /// The drop that lands where the card already is moves nothing, and still
    /// has to put the card back to full strength: it is the one route through
    /// `performMove` that returns before doing any work.
    @Test func aDropThatMovesNothingStillEndsTheLift() {
        let store = TestBoard.store()
        let before = store.tasks
        store.draggingID = TestBoard.dragDrop
        store.dropTargetColumnID = backlog
        store.dropTargetCaret = .above(TestBoard.cafe)
        store.isInboxDropTarget = true

        store.move(TestBoard.dragDrop, to: backlog)

        #expect(store.tasks == before)
        #expect(store.draggingID == nil)
        #expect(store.dropTargetColumnID == nil)
        #expect(store.dropTargetCaret == nil)
        #expect(store.isInboxDropTarget == false)
    }

    // MARK: The view's end of it

    /// The claim is about *which phase* the view listens to, and a phase cannot
    /// be delivered from here — so this reads the source, the way
    /// `DragReorderTests` reads the drop closures. What it pins is the shape
    /// the fix has: nothing in the session handler clears the lift by hand, the
    /// `ended` arm lets a carrying drop through untouched, and the arm that
    /// ends the lift is the one that fires when the payload has been handed
    /// over.
    @Test func theLiftEndsWhenThePayloadLandsRatherThanWhenTheMouseComesUp() {
        guard SourceTree.isReachable else { return }
        guard let file = SourceTree.files().first(where: { $0.path == "Shared/BoardTaskCard.swift" })
        else {
            Issue.record("the board card has moved file")
            return
        }
        let source = file.source
        guard let head = source.range(of: "onDragSessionUpdated") else {
            Issue.record("the board card no longer follows a drag session")
            return
        }
        let body = file.block(after: source.distance(from: source.startIndex, to: head.lowerBound))

        #expect(body.contains("case .initial:"), "nothing starts the lift")
        #expect(body.contains("store.draggingID = id"), "the lift does not name the card")
        #expect(body.contains("case .dataTransferCompleted:"),
                "the lift does not end on the payload landing")

        // Every end goes through the store's one call, so a second copy of
        // "put the card back" cannot drift out of step with the first.
        #expect(body.contains("draggingID = nil") == false,
                "the session handler ends a lift by hand: \(body)")
        #expect(body.contains("dropTargetColumnID = nil") == false,
                "the session handler drops a highlight by hand: \(body)")

        // The `ended` arm fires while the payload is still in the air. A drop
        // that carries something must fall through it, or the card is drawn
        // back in the column it is leaving until the move lands.
        guard let ended = body.range(of: "case .ended"),
              let landed = body.range(of: "case .dataTransferCompleted")
        else { return }
        #expect(ended.lowerBound < landed.lowerBound, "the arms are in an order this cannot read")
        let arm = body[ended.upperBound..<landed.lowerBound]
        #expect(arm.contains("case .copy, .move: break"),
                "a drop that carries a card ends its lift before the card has moved: \(arm)")
        #expect(arm.contains("store.endDrag()"),
                "a refused drop leaves the card looking lifted: \(arm)")
    }
}
