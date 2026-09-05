import Foundation
import Testing
@testable import Cardstock

/// A lift is not a drag, and what is drawn over a card must not confuse them.
///
/// A card offers its two insertion halves as clear, hit-testable panes laid
/// *over* it — `BoardTaskCard.dropZones` — so while they are on screen they are
/// what a tap on that card lands on. They were mounted on
/// ``BoardStore/draggingID``, which without `onDragSessionUpdated` is set by the
/// lift and cleared by the drop: a long press released in place is a lift with
/// no drop, so the panes went up over every card in the list and stayed there
/// for ``BoardStore/liftExpiry`` — twenty seconds in which nothing in that list
/// would open.
///
/// The panes ask ``BoardStore/isCardTravelling`` instead, which no lift sets and
/// only a destination can. What that buys was measured rather than argued: on
/// the simulator a press-and-hold released in place reports no drop targeting
/// anywhere, while a drag of a few points has the list's ground reporting almost
/// at once. `UITests/HeldCardTests` is the finger; this is the bookkeeping.
@MainActor
@Suite struct CardLiftTests {
    @Test func aCardThatHasOnlyBeenPickedUpIsNotTravellingYet() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.widget
        #expect(store.isCardTravelling == false, "a hold put the panes over the cards")
    }

    @Test func theFirstDestinationToSeeTheDragIsWhatPutsThePanesUp() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.widget
        store.dragTargeting(true)
        #expect(store.isCardTravelling)
    }

    /// A drag from somewhere else — another app's payload crossing a column —
    /// is not this app carrying a card, and must not put panes over its cards.
    @Test func aTargetingReportWithNothingInTheAirIsNotADrag() {
        let store = TestBoard.store()
        store.dragTargeting(true)
        #expect(store.isCardTravelling == false)
    }

    @Test func endingTheDragTakesThePanesWithIt() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.widget
        store.dragTargeting(true)
        store.endDrag()
        #expect(store.isCardTravelling == false)
    }

    /// And a card that leaves the board while it is in the air takes the panes
    /// with it. `draggingID` is cleared from several places that are not
    /// `endDrag` — a task discarded, archived, or taken away wholesale by a
    /// restore — and a pane outliving the card it was laid over is a list that
    /// will not open for a reason nothing on screen can explain.
    @Test func aCardTakenAwayMidDragLeavesNothingOverItsList() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.widget
        store.dragTargeting(true)
        #expect(store.isCardTravelling)

        store.archive(TestBoard.widget)
        #expect(store.draggingID == nil)
        #expect(store.isCardTravelling == false)
    }

    /// Every destination letting go at once is the end of a drag nothing else
    /// will announce.
    ///
    /// Off where the session says so itself: `CardDragSession` reads
    /// `onDragSessionUpdated`, and a guess standing beside a fact is a second
    /// opinion nobody asked for. That is macOS, and iOS 27 when it arrives.
    @Test func aDragEveryDestinationHasLetGoOfIsOver() async throws {
        guard !BoardStore.announcesDragEnd else { return }
        let store = TestBoard.store()
        store.draggingID = TestBoard.widget
        store.dragTargeting(true)
        store.dragTargeting(false)
        #expect(store.draggingID != nil, "the drag was called off before the settle")

        try await Task.sleep(for: .seconds(BoardStore.dragSettle + 0.3))
        #expect(store.draggingID == nil, "the lift outlived every destination that saw it")
        #expect(store.isCardTravelling == false)
    }

    /// And a finger crossing out of a pane into the ground behind it has not
    /// let go of anything — which is why what is counted is destinations and
    /// not a flag: a nested zone takes the hover from its parent, and the
    /// `false` and the `true` come in an order SwiftUI does not promise.
    @Test func aDragHandedFromOneDestinationToTheNextIsNotOver() async throws {
        guard !BoardStore.announcesDragEnd else { return }
        let store = TestBoard.store()
        store.draggingID = TestBoard.widget
        store.dragTargeting(true)   // the list's ground
        store.dragTargeting(true)   // a card's half, inside it
        store.dragTargeting(false)  // the ground, handing it to its own child

        try await Task.sleep(for: .seconds(BoardStore.dragSettle + 0.3))
        #expect(store.draggingID != nil, "the drag was called off while a pane still had it")
    }

    /// Nothing counts the drag unless every destination reports it, so this is
    /// read out of the source the way `DragReorderTests` reads the drop
    /// closures: a destination that kept quiet would look like nobody holding
    /// the drag, and the store would call it over under the finger.
    @Test func everyCardDestinationReportsWhatItIsTargetedBy() {
        guard SourceTree.isReachable else { return }
        let expected: Set<String> = [
            // The two cards and the stand-in drawn in the gap.
            "Shared/BoardTaskCard.swift", "IOS/PhoneTaskCard.swift",
            "Shared/DropPreviewCard.swift",
            // The grounds: a column on each surface, and the Inbox's two faces.
            "Shared/BoardColumnView.swift", "IOS/PhoneColumnPage.swift",
            "Shared/InboxPanel.swift", "IOS/PhoneInboxSheet.swift",
            // And the two that are places rather than lists — the source list's
            // board row and the toolbar's Inbox button.
            "Shared/BoardSidebar.swift", "Shared/BoardToolbar.swift",
        ]
        var seen: Set<String> = []
        for file in SourceTree.files() where expected.contains(file.path) {
            let targeted = file.source.components(separatedBy: "isTargeted: {").count - 1
            let reports = file.source.components(separatedBy: "store.dragTargeting(targeted)").count - 1
            #expect(targeted > 0, "\(file.path) no longer reports being targeted at all")
            #expect(reports == targeted,
                    "\(file.path) has \(targeted) targeting closures and \(reports) report it")
            seen.insert(file.path)
        }
        #expect(seen == expected, "a card destination has moved file: found \(seen)")
    }
}
