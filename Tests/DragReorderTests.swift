import Foundation
import Testing
@testable import Simple_Kanban

/// Where a dragged card is allowed to land, asked of every pair on the board.
///
/// `CardDropTests` pins the reported failure — a long-press reorder inside a
/// column that moved the card to **Done** and ticked its sub-tasks off — on the
/// four cards it takes to reproduce it. This is the same claim as a property:
/// for *every* ordered pair of cards sharing a column, on every column of every
/// board and in the Inbox, the drop the card-to-card closure makes must resolve
/// to the column the pair is already in.
///
/// It matters most on the iPad, which is the surface that has both a
/// long-press drag and a full multi-column board: on the phone a reorder is
/// inside one column at a time because that is all the pager shows, and on the
/// Mac a drag is a pointer drag with a visible drop target. The iPad has the
/// desk's board under a finger, and a mis-resolved drop there is a card
/// silently completed in a column that is scrolled off screen.
///
/// A drop cannot be driven from a unit test, so what is exercised is what each
/// `dropDestination` closure calls, with the arguments it has to hand:
/// `BoardTaskCard` and `PhoneTaskCard` both call
/// `move(dropped, to: target.placement, before: target.id)`, and
/// `BoardColumnView` and `PhoneColumnPage` — the column's ground on each
/// surface — call `drop(dropped, onGroundOf: the column's placement)`. Both
/// directions are asserted, so neither can be made to pass by deleting the
/// other's behaviour.
@MainActor
@Suite struct DragReorderTests {
    // MARK: A board with room to get it wrong

    private static func uuid(_ tag: UInt8, _ n: Int) -> UUID {
        UUID(uuid: (0xD2, 0xA6, tag, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0,
                    UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)))
    }

    private static let columnsPerBoard = 4
    private static let cardsPerColumn = 4

    /// Two boards of four columns each, the last of every board being Done —
    /// so a mis-resolved drop has somewhere with *behaviour* to land, and so a
    /// drop that leaked across boards would be visible as well as one that
    /// leaked across columns.
    private static let boards: [Board] = (0..<2).map { b in
        Board(
            id: uuid(0xB0, b), name: "Board \(b)", dot: .hex(0xA8A29A),
            createdAt: TestBoard.at(300_000 - b * 100),
            columns: (0..<columnsPerBoard).map { c in
                BoardColumn(
                    id: uuid(0xC0, b * columnsPerBoard + c),
                    name: "Column \(b).\(c)", short: "C\(b).\(c)", dot: .hex(0xA8A29A),
                    role: c == columnsPerBoard - 1 ? .done : (c == 0 ? .backlog : .active)
                )
            },
            codePrefix: "D\(b)"
        )
    }

    private static let allColumns: [BoardColumn] = boards.flatMap(\.columns)

    /// Every card carries an outstanding sub-task, because that is the damage a
    /// drop into Done does silently: a reorder that resolved to Done would tick
    /// them, and nothing on the card would say why.
    private static let tasks: [TaskItem] = {
        var built: [TaskItem] = []
        for (index, column) in allColumns.enumerated() {
            for card in 0..<cardsPerColumn {
                let n = index * cardsPerColumn + card
                built.append(TaskItem(
                    id: uuid(0x7A, n), code: "D-\(400 + n)", columnID: column.id,
                    title: "Card \(n)",
                    subtasks: [SubTask(id: uuid(0x5B, n), text: "Outstanding \(n)", done: false)],
                    activity: [ActivityEntry(id: uuid(0xAC, n), .created, when: TestBoard.at(9_000 - n))],
                    createdAt: TestBoard.at(9_000 - n), updatedAt: TestBoard.at(9_000 - n)
                ))
            }
        }
        // Four unfiled cards, so the Inbox is a place a reorder happens too —
        // it has no column id, which is the one placement a drop closure cannot
        // spell as a column and the shape a `columnID`-shaped fix would drop.
        for card in 0..<cardsPerColumn {
            let n = 1_000 + card
            built.append(TaskItem(
                id: uuid(0x7A, n), code: "IN-\(400 + card)",
                title: "Inbox card \(card)",
                subtasks: [SubTask(id: uuid(0x5B, n), text: "Outstanding \(n)", done: false)],
                activity: [ActivityEntry(id: uuid(0xAC, n), .captured, when: TestBoard.at(8_000 - card))],
                createdAt: TestBoard.at(8_000 - card), updatedAt: TestBoard.at(8_000 - card)
            ))
        }
        return built
    }()

    private func store() -> BoardStore {
        BoardStore(tasks: Self.tasks, boards: Self.boards, activeBoardID: Self.boards[0].id,
                   labels: LabelDef.seed, accentTheme: .ember, nextSerial: BoardSnapshot.baseSerial)
    }

    /// The cards sharing a placement, in board order — which is the order the
    /// column draws under `.manual`, and so the order a drag reorders.
    private func siblings(_ store: BoardStore, _ placement: TaskPlacement) -> [TaskItem.ID] {
        store.tasks.filter { $0.placement == placement }.map(\.id)
    }

    /// Every placement a card can be dragged inside: each column of each board,
    /// and the Inbox.
    private static let placements: [TaskPlacement] =
        boards.flatMap { board in board.columns.map { .column(board: board.id, column: $0.id) } }
        + [.inbox]

    // MARK: The property

    /// The blocker, as a property over the whole board.
    ///
    /// For every ordered pair of cards in one place, dropping the first onto the
    /// second must leave the first exactly where it was — same board, same
    /// column, not completed, sub-tasks untouched — and must leave the place
    /// holding the same set of cards it held before.
    @Test func everyReorderWithinAPlaceStaysInThatPlace() throws {
        for placement in Self.placements {
            let reference = store()
            let members = siblings(reference, placement)
            #expect(members.count == Self.cardsPerColumn)

            for dropped in members {
                for target in members where target != dropped {
                    let store = store()
                    let before = Set(siblings(store, placement))
                    let doneBefore = store.tasks.count { store.isDone($0) }
                    let subtasksBefore = try #require(store[dropped]).subtasks
                    let wasDone = store.isDone(try #require(store[dropped]))

                    let targetTask = try #require(store[target])
                    // Exactly what `BoardTaskCard` and `PhoneTaskCard` call.
                    store.move(dropped, to: targetTask.placement, before: targetTask.id)

                    let moved = try #require(store[dropped])
                    let label = "\(moved.code) onto \(targetTask.code)"
                    #expect(moved.placement == placement, "\(label): the reorder left the place")
                    #expect(moved.boardID == placement.boardID, "\(label): the reorder changed board")
                    #expect(moved.columnID == placement.columnID, "\(label): the reorder changed column")
                    // Reordering inside Done leaves a Done card done and its
                    // sub-tasks as they were; reordering anywhere else must not
                    // reach the Done behaviour at all.
                    #expect(moved.subtasks == subtasksBefore,
                            "\(label): the reorder changed the card's sub-tasks")
                    #expect(store.isDone(moved) == wasDone, "\(label): the reorder changed completion")
                    #expect(store.tasks.count { store.isDone($0) } == doneBefore,
                            "\(label): the completed count moved")
                    #expect(Set(siblings(store, placement)) == before,
                            "\(label): the place gained or lost a card")
                    #expect(store.tasks.count == Self.tasks.count, "\(label): a card went missing")
                }
            }
        }
    }

    /// And the reorder actually reorders: the dropped card lands immediately
    /// ahead of the card it was dropped on, in every pair.
    ///
    /// Without this the suite above is satisfied by a `move` that does nothing
    /// at all, which is the other way to break a drag.
    @Test func everyReorderPutsTheCardAheadOfTheOneItLandedOn() throws {
        for placement in Self.placements {
            let members = siblings(store(), placement)
            for dropped in members {
                for target in members where target != dropped {
                    let store = store()
                    let targetTask = try #require(store[target])
                    store.move(dropped, to: targetTask.placement, before: targetTask.id)

                    let after = siblings(store, placement)
                    let droppedAt = try #require(after.firstIndex(of: dropped))
                    let targetAt = try #require(after.firstIndex(of: target))
                    #expect(droppedAt + 1 == targetAt,
                            "\(dropped) did not land immediately ahead of \(target): \(after)")
                }
            }
        }
    }

    /// The other direction, so the property above cannot be satisfied by a
    /// `move` that refuses every drop: a card dropped on a *different* column
    /// goes there, and a card dropped on a Done column is completed with its
    /// sub-tasks ticked — which is the behaviour a reorder must not borrow.
    @Test func aCardDroppedOnAnotherColumnsCardGoesThere() throws {
        for source in Self.placements {
            for destination in Self.placements where destination != source {
                let store = store()
                let dropped = try #require(siblings(store, source).first)
                let target = try #require(siblings(store, destination).first)
                let targetTask = try #require(store[target])

                store.move(dropped, to: targetTask.placement, before: targetTask.id)

                let moved = try #require(store[dropped])
                #expect(moved.placement == destination,
                        "a cross-place drop did not land: \(moved.code) is \(moved.placement)")
                if let columnID = destination.columnID, store.role(ofColumn: columnID) == .done {
                    #expect(moved.subtasks.allSatisfy { $0.done },
                            "a card moved into Done kept an outstanding sub-task")
                    #expect(store.isDone(moved))
                }
            }
        }
    }

    // MARK: The column's own drop closure

    /// `BoardColumnView` drops onto a column rather than onto a card. Every
    /// card dropped on every column must land in that column and nowhere else —
    /// including the column it is already in, where the drop is a no-op rather
    /// than a trip to the bottom of the list.
    ///
    /// *Where* in the column it lands is `DropCaretTests`': the ground keeps the
    /// row the card was on. This is the claim underneath that one — that the
    /// column resolved is the column dropped on — and it holds whichever row the
    /// card ends up in.
    @Test func aDropOnAColumnResolvesToThatColumn() throws {
        for column in Self.allColumns {
            for card in Self.tasks.map(\.id) {
                let store = store()
                let was = try #require(store[card]).placement
                let orderBefore = siblings(store, was)

                store.drop(card, onGroundOf: store.placement(forColumn: column.id))

                let moved = try #require(store[card])
                #expect(moved.columnID == column.id,
                        "\(moved.code) dropped on \(column.name) landed in \(moved.columnID?.uuidString ?? "the Inbox")")
                #expect(store.board(ofColumn: column.id)?.id == moved.boardID,
                        "\(moved.code) is on a board that does not hold \(column.name)")
                if was == moved.placement {
                    #expect(siblings(store, was) == orderBefore,
                            "a drop on the card's own column reordered it")
                }
            }
        }
    }

    // MARK: What the drop closures actually call

    /// Everything above drives `BoardStore.move` directly, because a drop
    /// cannot be performed from a unit test. That leaves one gap the property
    /// cannot see: a closure that resolves the *wrong* placement — the active
    /// board's landing column, say, or the card being dragged rather than the
    /// card it was dropped on — would satisfy every assertion above while
    /// putting cards somewhere nobody is looking.
    ///
    /// So the closures are read out of the source, the way `MenuDeclarationTests`
    /// reads the menu bar and `SystemWiringTests` reads the scene: a
    /// `dropDestination` body has nothing to enumerate at runtime, and the one
    /// thing worth asserting about it is the single call it makes.
    @Test func everyCardDropClosureResolvesToTheCardItLandedOn() {
        guard SourceTree.isReachable else { return }
        let expected = [
            // The desk and iPad board card, and the phone's list row: both drop
            // into the **gap the caret named**, which is the half of the card
            // the pointer was in. It used to be `move(_:onto:)` — a drop that
            // names a card, with the side worked out from the direction of
            // travel — and that could not express the head of a list at all.
            // See `DropCaretTests`.
            "Shared/BoardTaskCard.swift": "store.drop(dropped.id, at: caret)",
            "IOS/PhoneTaskCard.swift": "store.drop(dropped.id, at: caret)",
            // A column — the desk's strip and the phone's page are both one —
            // and the Inbox panel take the drops that landed on a list's
            // *ground* rather than in a gap between two of its cards.
            // Those name no gap, so the card keeps the row it was on — see
            // `BoardStore.drop(_:onGroundOf:)` — and neither may go back to
            // `move(_:to:)`, which appends.
            "Shared/BoardColumnView.swift":
                "store.drop(dropped.id, onGroundOf: store.placement(forColumn: column.id))",
            "IOS/PhoneColumnPage.swift":
                "store.drop(dropped.id, onGroundOf: store.placement(forColumn: column.id))",
            "Shared/InboxPanel.swift": "store.drop(dropped.id, onGroundOf: .inbox)",
        ]
        // The phone's *card* asks `allowsCardDrag` outside its closure — the
        // whole destination is behind the guard — so the question is put to the
        // four that ask it inside, which is where a copy-paste would lose it.
        let guardedInside: Set<String> = [
            "Shared/BoardTaskCard.swift", "Shared/BoardColumnView.swift",
            "IOS/PhoneColumnPage.swift", "Shared/InboxPanel.swift",
        ]
        var seen: Set<String> = []
        for file in SourceTree.files() {
            guard let call = expected[file.path] else { continue }
            let drops = file.calls(headed: #"dropDestination\(for: TaskTransfer\.self\)"#)
            #expect(drops.count == 1, "\(file.path) has \(drops.count) card drop destinations")
            guard let drop = drops.first else { continue }
            let body = file.block(after: drop.offset + drop.text.count)
            #expect(body.contains(call), "\(file.path)'s drop does not call \(call): \(body)")
            if guardedInside.contains(file.path) {
                #expect(body.contains("store.allowsCardDrag"),
                        "\(file.path) accepts a card while the board is not in its own order")
            }
            seen.insert(file.path)
        }
        #expect(seen == Set(expected.keys), "a card drop closure has moved file: found \(seen)")
    }

    /// And the drops that legitimately resolve somewhere other than where the
    /// pointer is, because a destination is a *place* rather than a list with
    /// rows in it: the source list's board row files onto that board's landing
    /// column, and the toolbar's Inbox button takes a card back out of whatever
    /// board it was on.
    ///
    /// Two closures that both mean "put it there" and neither of which may
    /// quietly become "put it next to that", which a copy-paste between them
    /// would do. The toolbar's button is here and the Inbox *panel* is with the
    /// ground drops above, which is the difference between the Inbox's two
    /// faces: the panel is a list on screen with rows to land between, and the
    /// button — the only way back by pointer while the panel is shut — is a
    /// target with no list behind it at all.
    @Test func everyDestinationDropNamesThePlaceRatherThanTheCard() {
        guard SourceTree.isReachable else { return }
        let expected = [
            "Shared/BoardSidebar.swift": "store.file(dropped.id, onto: board.id)",
            "Shared/BoardToolbar.swift": "store.unfile(dropped.id)",
        ]
        var seen: Set<String> = []
        for file in SourceTree.files() {
            guard let call = expected[file.path] else { continue }
            let drops = file.calls(headed: #"dropDestination\(for: TaskTransfer\.self\)"#)
            #expect(drops.count == 1, "\(file.path) has \(drops.count) card drop destinations")
            guard let drop = drops.first else { continue }
            let body = file.block(after: drop.offset + drop.text.count)
            #expect(body.contains(call), "\(file.path)'s drop does not call \(call): \(body)")
            #expect(body.contains("store.allowsCardDrag"),
                    "\(file.path) accepts a card while the board is not in its own order")
            seen.insert(file.path)
        }
        #expect(seen == Set(expected.keys), "a destination drop has moved file: found \(seen)")
    }

    // MARK: When a drag is not allowed at all

    /// A drop resolves against the board's own array, so both closures refuse
    /// to run at all when what is on screen is not that order. All three of the
    /// conditions are asked, because each one alone leaves the other two able
    /// to put a card somewhere nobody can see.
    @Test func dragIsRefusedWheneverTheRowsOnScreenAreNotTheBoardsOrder() {
        let store = store()
        #expect(store.allowsCardDrag)

        store.query = "Card"
        #expect(store.isFiltering)
        #expect(store.allowsCardDrag == false, "a filtered board still allows a drag")
        store.query = ""

        store.sortOrder = .dueDate
        #expect(store.allowsCardDrag == false, "a sorted board still allows a drag")
        store.sortOrder = .manual

        store.selectSurface(.view(.upcoming))
        #expect(store.allowsCardDrag == false, "a saved view still allows a drag")
        store.selectSurface(.board)
        #expect(store.allowsCardDrag)
    }

    /// An archived card is not on the board, so no drop may move it — the drag
    /// modifiers are off in the Archive, and `performMove` refuses as well so a
    /// route that forgets cannot file a card out of it sideways.
    @Test func anArchivedCardCannotBeReorderedOntoTheBoard() throws {
        let store = store()
        let card = try #require(siblings(store, Self.placements[0]).first)
        let target = try #require(siblings(store, Self.placements[1]).first)
        store.archive(card)

        let targetTask = try #require(store[target])
        store.move(card, to: targetTask.placement, before: targetTask.id)

        let moved = try #require(store[card])
        #expect(moved.isArchived, "a drop restored a filed card")
        #expect(moved.placement == Self.placements[0], "a drop moved a filed card")
    }
}
