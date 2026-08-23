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

    // MARK: What a reorder cannot change

    /// **The warning this section used to be about is gone.** Up to v8 a column
    /// carried a `ColumnRole`, the board's Done column was the first one whose
    /// role said so, and a board with two of them changed where every future
    /// tick sent a card the moment they were dragged past each other — invisibly,
    /// with no undo step announcing it. The sheet had to ask first.
    ///
    /// Done is the board's last column now and does not move, so there is
    /// nothing left to ask about. What is asserted here is the *absence*: no
    /// reorder, from anywhere to anywhere, changes where completed work lands.
    @Test func noReorderChangesWhereCompletedWorkLands() {
        let store = TestBoard.store()
        let landing = store.doneColumnID

        for from in store.columns.indices {
            for to in 0...store.columns.count where to != from && to != from + 1 {
                store.moveColumn(fromOffsets: IndexSet(integer: from), toOffset: to)
                #expect(store.doneColumnID == landing,
                        "moving \(from) to \(to) changed where completed tasks land")
                #expect(store.columns.last?.id == landing, "Done stopped being last")
            }
        }
    }

    /// Adding a column is the other way the end of the board could have moved,
    /// and the one that would happen constantly: `addColumn` appends nowhere
    /// near Done, it inserts in front of it.
    @Test func addingAColumnLeavesTheDoneColumnWhereItIs() throws {
        let store = TestBoard.store()
        let landing = store.doneColumnID

        let added = try #require(store.addColumn(named: "Shipped"))
        #expect(store.doneColumnID == landing, "the new column took the finished work")
        #expect(store.columns.last?.id == landing)
        #expect(store.columns.dropLast().last?.id == added, "the new column did not land in front of Done")
    }

    /// And the Done column cannot be dragged out of the way either, which is
    /// what makes reading it off the position safe.
    @Test func theDoneColumnRefusesToMove() {
        let store = TestBoard.store()
        let order = store.columns.map(\.id)
        let last = store.columns.count - 1

        for to in 0..<last {
            store.moveColumn(fromOffsets: IndexSet(integer: last), toOffset: to)
            #expect(store.columns.map(\.id) == order, "the Done column moved to \(to)")
        }
    }
}
