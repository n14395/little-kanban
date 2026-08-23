import Foundation
import Testing
@testable import Simple_Kanban

/// What the board settings sheet promises before it changes a board.
///
/// **The sheet's two destructive halves are the ones with numbers in them**, and
/// the numbers are the store's: how many cards a column holds, where they would
/// go, and which column completed work lands in after a reorder. A warning that
/// counted differently from the mutation it stands in front of would be worse
/// than none — it would be a promise the app then breaks.
@MainActor
@Suite struct BoardSettingsTests {
    private let backlog = BoardColumn.backlog.id
    private let upNext = BoardColumn.upNext.id
    private let inProgress = BoardColumn.inProgress.id
    private let done = BoardColumn.done.id

    // MARK: What a trash would cost

    /// The refuge is the first column left standing, which is exactly where
    /// `deleteColumn` puts the cards — asked of the same function, so the two
    /// cannot answer differently.
    @Test func theRefugeIsTheFirstColumnLeftStanding() throws {
        let store = TestBoard.store()

        #expect(store.refuge(ifTrashing: upNext)?.id == backlog)
        // Trashing the first column leaves the second one first.
        #expect(store.refuge(ifTrashing: backlog)?.id == upNext)
    }

    /// And it is where they actually land, which is the half a warning cannot
    /// check for itself.
    @Test func theCardsLandInTheColumnTheWarningNamed() throws {
        let store = TestBoard.store()
        let refuge = try #require(store.refuge(ifTrashing: upNext))
        let carried = store.visibleTasks(in: upNext).map(\.id)
        #expect(!carried.isEmpty)

        #expect(store.trashColumn(upNext) == nil)

        for card in carried {
            #expect(store[card]?.columnID == refuge.id, "a card did not land where the warning said")
        }
        // And the column itself is in the trash rather than gone.
        #expect(store.trashedItems.contains { $0.kind == .column })
    }

    /// The count includes archived cards, because the move does. A warning that
    /// left them out would promise to move fewer cards than it moves.
    @Test func theCountIncludesArchivedCards() throws {
        let store = TestBoard.store()
        let card = try #require(store.visibleTasks(in: backlog).first)
        let before = store.cardCount(inColumn: backlog)

        store.archive(card.id)

        #expect(store.visibleTasks(in: backlog).count == before - 1, "the board stopped drawing it")
        #expect(store.cardCount(inColumn: backlog) == before, "but the delete would still move it")
    }

    /// An empty column has nothing to say about cards, so the alert says only
    /// the thing that is still true: the column can be fetched back.
    @Test func theWarningForAnEmptyColumnMentionsNoCards() throws {
        let store = TestBoard.store()
        let empty = try #require(store.addColumn(named: "Parked"))
        let warning = ColumnTrashWarning(
            column: empty, name: "Parked",
            cards: store.cardCount(inColumn: empty),
            refuge: store.refuge(ifTrashing: empty)?.name
        )

        #expect(warning.cards == 0)
        #expect(warning.detail.contains("restored"))
        #expect(warning.detail.contains("cards move") == false)
    }

    // MARK: What a reorder would change

    /// The ordinary case: one Done column, and moving anything anywhere leaves
    /// completed work landing exactly where it did. A warning here would be a
    /// lie, and the sheet asks nothing.
    @Test func reorderingABoardWithOneDoneColumnChangesNothing() {
        let store = TestBoard.store()
        let landing = store.doneColumnID

        for from in store.columns.indices {
            for to in 0...store.columns.count where to != from && to != from + 1 {
                #expect(
                    store.doneColumnID(afterMoving: IndexSet(integer: from), toOffset: to) == landing,
                    "moving \(from) to \(to) claimed to change where completed tasks land"
                )
            }
        }
    }

    /// The case that earns the warning: a second Done column, moved past the
    /// first. Nothing on the board says which of the two a tick sends a card to,
    /// and the sheet is the only place it is written down.
    @Test func movingASecondDoneColumnPastTheFirstChangesWhereCompletedWorkLands() throws {
        let store = TestBoard.store()
        let second = try #require(store.addColumn(named: "Shipped", role: .done))
        #expect(store.doneColumnID == done, "the seeded Done is still the one")
        let last = store.columns.count - 1
        let first = try #require(store.columns.firstIndex { $0.id == done })

        // Read before it moves…
        let predicted = store.doneColumnID(afterMoving: IndexSet(integer: last), toOffset: first)
        #expect(predicted == second, "the warning would have named the wrong column")

        // …and the move keeps the promise.
        store.moveColumn(fromOffsets: IndexSet(integer: last), toOffset: first)
        #expect(store.doneColumnID == second)
    }

    /// And the same board, moved somewhere that does not cross the two: still
    /// nothing to ask about.
    @Test func movingAColumnThatIsNotDonePastAnotherAsksNothing() throws {
        let store = TestBoard.store()
        _ = try #require(store.addColumn(named: "Shipped", role: .done))
        let landing = store.doneColumnID
        let index = try #require(store.columns.firstIndex { $0.id == upNext })

        #expect(store.doneColumnID(afterMoving: IndexSet(integer: index), toOffset: 0) == landing)
    }

    /// The warning carries the move in `moveColumn`'s own spelling, so
    /// confirming performs the move that was described rather than one worked
    /// out a second time.
    @Test func confirmingAMoveWarningPerformsTheMoveItDescribed() throws {
        let store = TestBoard.store()
        let second = try #require(store.addColumn(named: "Shipped", role: .done))
        let last = store.columns.count - 1
        let first = try #require(store.columns.firstIndex { $0.id == done })
        let warning = ColumnMoveWarning(from: last, to: first, landing: "Shipped", leaving: "Done")

        store.moveColumn(fromOffsets: IndexSet(integer: warning.from), toOffset: warning.to)

        #expect(store.doneColumnID == second)
        #expect(store.columns[first].id == second, "the column did not land where the warning said")
    }
}
