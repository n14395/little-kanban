import Foundation
import Testing
@testable import Cardstock

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

    // MARK: Making a board

    /// **Every route that makes a board opens this sheet on it**, with the name
    /// field focused and empty.
    ///
    /// The desk's sidebar row used to become a text field where it stood and the
    /// phone put up an alert, both on the argument that a board *is* a name. It
    /// is not: it is a name and the columns work moves through, and a board
    /// arrives holding only its Done column — so the next thing after naming one
    /// is always to say what its columns are, which is here.
    ///
    /// Source-level because the claim is that three surfaces agree, and two of
    /// them are on a platform the third cannot be driven from.
    @Test func everyRouteThatMakesABoardOpensItsSettingsOnTheEmptyName() {
        guard SourceTree.isReachable else { return }
        for path in ["Shared/BoardSidebar.swift", "Shared/BoardScrollView.swift", "IOS/PhoneNavDrawer.swift"] {
            guard let file = SourceTree.files().first(where: { $0.path == path }) else {
                Issue.record("\(path) has moved")
                continue
            }
            #expect(file.source.contains("namesNewBoard: true"),
                    "\(path) makes a board without opening its settings on the name")
            #expect(file.source.contains("Board.defaultName"),
                    "\(path) names a new board something of its own")
        }
        // And the row that used to become a field does not any more — the whole
        // inline-edit machinery went with it.
        guard let sidebar = SourceTree.files().first(where: { $0.path == "Shared/BoardSidebar.swift" })
        else { return }
        #expect(sidebar.source.contains("BoardField") == false,
                "the sidebar still has a row that turns into a text field")
    }

    /// **The composer and a column's own editor draw the same three controls in
    /// the same arrangement**, because they are the same column a moment apart.
    ///
    /// The editor used to stack Name over Short over Colour while the composer
    /// put the fields side by side — two layouts for one thing, and this file
    /// has been through that kind of drift once already: `renameColumn(_:to:short:)`
    /// exists because the phone could rename a column and nothing could rename
    /// its abbreviation. They share `columnShape` now, and this asserts that
    /// neither has grown a second arrangement of its own.
    @Test func theComposerAndTheColumnEditorDrawOneShape() throws {
        guard SourceTree.isReachable else { return }
        let file = try #require(
            SourceTree.files().first { $0.path == "Shared/BoardSettingsView.swift" },
            "the board settings sheet has moved"
        )
        let source = file.source
        #expect(source.contains("private func columnShape("), "the shared arrangement has gone")
        // Both callers, and nothing else laying the three out for itself.
        #expect(source.components(separatedBy: "columnShape(").count - 1 == 3,
                "columnShape has grown a third caller, or lost one")
        for block in ["private func columnEditor(", "private var addColumnComposer:"] {
            let head = try #require(source.range(of: block), "\(block) has been renamed")
            let body = file.block(after: source.distance(from: source.startIndex, to: head.lowerBound))
            #expect(body.contains("columnShape("), "\(block) lays the three out for itself")
            #expect(body.contains("ColorWell(") == false, "\(block) draws its own colour control again")
            #expect(body.contains("columnField(") == false, "\(block) draws its own fields again")
        }
    }

    // MARK: What the composer offers

    /// **No role.** Since v9 there are two things to say about a column when it
    /// is made — its name and its abbreviation, which are the two fields the
    /// composer draws — and a role is not one of them.
    ///
    /// Both surfaces used to carry a row of role segments under the name field.
    /// `.backlog` and `.active` never did anything, and `.done` is now the
    /// board's last column rather than a role, so a picker on either would be
    /// offering a choice the model cannot hold. Read off the source because the
    /// claim is about what is *absent*, which no rendering can show.
    ///
    /// It covers `BoardColumnView` too even though the board's dashed
    /// add-column tile has gone with it — if a composer ever comes back to that
    /// file, it must not come back with the picker.
    @Test func neitherSurfaceOffersARoleWhenAColumnIsMade() {
        guard SourceTree.isReachable else { return }
        for path in ["Shared/BoardSettingsView.swift", "Shared/BoardColumnView.swift"] {
            guard let file = SourceTree.files().first(where: { $0.path == path }) else {
                Issue.record("\(path) has moved")
                continue
            }
            #expect(file.source.contains("rolePicker") == false,
                    "\(path) has a role picker under its add-column field again")
            #expect(file.source.contains("ColumnRole") == false,
                    "\(path) still knows what a ColumnRole is")
        }
    }

    /// **The composer sits between the working columns and Done**, because that
    /// is where the column it makes will appear: `addColumn` inserts in front of
    /// Done, which stays last. On the end of the list it read as "add a column
    /// after Done", which is the one place a column cannot go.
    ///
    /// Read off the order of the source rather than off a rendering, because
    /// what is being asserted is the order of three things in one `VStack` and a
    /// rendered sheet would have to be driven to a board with columns first.
    @Test func theComposerSitsBetweenTheWorkingColumnsAndDone() throws {
        guard SourceTree.isReachable else { return }
        let file = try #require(
            SourceTree.files().first { $0.path == "Shared/BoardSettingsView.swift" },
            "the board settings sheet has moved"
        )
        let source = file.source
        let head = try #require(source.range(of: "private func columns(_ board: Board)"),
                                "the column list has been renamed")
        let body = file.block(after: source.distance(from: source.startIndex, to: head.lowerBound))

        let working = try #require(body.range(of: "board.workingColumns"), "the list is not split at Done")
        let composer = try #require(body.range(of: "addColumnRow"), "the list has no composer in it")
        let done = try #require(body.range(of: "board.doneColumn"), "Done is not drawn on its own")
        #expect(working.lowerBound < composer.lowerBound, "the composer is above the working columns")
        #expect(composer.lowerBound < done.lowerBound, "the composer is below Done")
    }

    /// **The rows are draggable, and the Done row is not.**
    ///
    /// A drag is not a control — it cannot be reached by keyboard, VoiceOver
    /// cannot offer it and Switch Control cannot perform it — so the Move Up /
    /// Move Down pair in the open editor stays beside it rather than being
    /// replaced by it. Both are asserted here: the wiring, and the pair that
    /// makes the wiring optional.
    @Test func theColumnRowsCanBeDraggedAndTheDoneRowCannot() throws {
        guard SourceTree.isReachable else { return }
        let file = try #require(
            SourceTree.files().first { $0.path == "Shared/BoardSettingsView.swift" },
            "the board settings sheet has moved"
        )
        let source = file.source
        #expect(source.contains("ColumnRowGrip"), "a column row cannot be picked up")
        #expect(source.contains("dropZones(for:"), "a dragged column has nowhere to land")
        // The lift is refused on the Done row and on a row being typed into.
        #expect(source.contains("isEnabled: !isOpen && !isDoneColumn(column)"),
                "the Done row or an open row can be picked up")
        // And the Done row draws one landing zone rather than two: nothing goes
        // after it, so the whole of it means *in front of Done*. The store
        // refuses the other direction as well — see `ColumnReorderTests`.
        #expect(source.contains("if !isDoneColumn(column) { dropZone(.below(column.id)) }"),
                "a column can be dropped after the Done column")
        // And the reachable half is still there.
        #expect(source.contains("\"Move Up\""), "the keyboard-reachable move is gone")
        #expect(source.contains("\"Move Down\""), "the keyboard-reachable move is gone")
    }

    /// And the board itself no longer offers one at all: the strip's trailing
    /// dashed tile spent 38pt of every board for ever on a button most people
    /// press once, and columns are managed in this sheet now.
    @Test func theBoardStripNoLongerEndsInAnAddColumnTile() {
        guard SourceTree.isReachable else { return }
        let names = Set(SourceTree.files().map(\.path))
        #expect(names.contains("Shared/VerticalText.swift") == false,
                "the tile's sideways label outlived the tile")
        guard let strip = SourceTree.files().first(where: { $0.path == "Shared/BoardScrollView.swift" })
        else {
            Issue.record("BoardScrollView has moved")
            return
        }
        #expect(strip.source.contains("AddColumnTile") == false, "the strip still ends in a tile")
        // The way in that replaced it, which an empty board is the only thing
        // on the board that still draws.
        #expect(strip.source.contains("addsColumn: true"),
                "nothing on the board opens the settings sheet's column composer")
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
