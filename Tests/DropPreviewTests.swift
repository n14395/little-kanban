import Foundation
import Testing
@testable import Simple_Kanban

/// The card-shaped hole that opens where a dragged card would land.
///
/// **What it adds to the caret.** `DropCaretTests` pins the insertion *point* —
/// which gap a release resolves to. A line on a card's edge says that much and
/// no more: not how much room the card will take when it lands, and not which
/// card is in the hand. The stand-in answers both by being a copy of the card,
/// sitting in the row it is about to occupy.
///
/// **What it must never do** is promise a move the drop would then refuse, and
/// most of what follows is that claim from one side or another. The caret is
/// free to mark the gap a card already sits in — a line there costs nothing —
/// but a card-shaped hole opening beside the very card that would fill it reads
/// as the board being about to change, and `drop(_:at:)` treats that release as
/// a no-op rather than spend a ⌘Z on a card that has not moved.
@MainActor
@Suite struct DropPreviewTests {
    private let backlog = BoardColumn.backlog.id
    private let upNext = BoardColumn.upNext.id

    private func place(_ store: BoardStore, _ column: BoardColumn.ID) -> TaskPlacement {
        store.placement(forColumn: column)
    }

    /// A card in the air, and the pointer in a gap that names a card.
    private func carrying(_ id: TaskItem.ID, over caret: DropCaret) -> BoardStore {
        let store = TestBoard.store()
        store.draggingID = id
        store.dropTargetCaret = caret
        return store
    }

    /// A card in the air, and the pointer on a list's own ground.
    private func carrying(_ id: TaskItem.ID, overGroundOf column: BoardColumn.ID,
                          tasks: [TaskItem] = TestBoard.tasks) -> BoardStore {
        let store = TestBoard.store(tasks: tasks)
        store.draggingID = id
        store.dropTargetColumnID = column
        return store
    }

    // MARK: Where it stands

    /// Backlog draws `[dragDrop, cafe]`, so the gap above `cafe` is row 1 and
    /// the gap below it is row 2 — the row after the last card, which is what
    /// "at the end" is as an index.
    @Test func theStandInSitsInTheGapTheCaretNames() {
        let above = carrying(TestBoard.widget, over: .above(TestBoard.cafe))
        #expect(above.dropPreview(in: place(above, backlog))?.index == 1)

        let below = carrying(TestBoard.widget, over: .below(TestBoard.cafe))
        #expect(below.dropPreview(in: place(below, backlog))?.index == 2)
    }

    @Test func theStandInIsTheCardInTheAir() throws {
        let store = carrying(TestBoard.widget, over: .above(TestBoard.cafe))
        let preview = try #require(store.dropPreview(in: place(store, backlog)))

        #expect(preview.task.id == TestBoard.widget)
        #expect(preview.caret == .above(TestBoard.cafe))
        #expect(preview.placement == place(store, backlog))
    }

    /// Every list on screen asks; at most one of them gets an answer.
    @Test func onlyTheListTheDropIsAimedAtGetsOne() {
        let store = carrying(TestBoard.widget, over: .above(TestBoard.cafe))

        #expect(store.dropPreview(in: place(store, backlog)) != nil)
        #expect(store.dropPreview(in: place(store, upNext)) == nil)
        #expect(store.dropPreview(in: .inbox) == nil)
    }

    @Test func nothingInTheAirMeansNoStandIn() {
        let store = TestBoard.store()
        store.dropTargetCaret = .above(TestBoard.cafe)

        #expect(store.dropCaret == .above(TestBoard.cafe), "the caret is a fact about the pointer")
        #expect(store.dropPreview(in: place(store, backlog)) == nil,
                "a stand-in was drawn for a card nobody is carrying")
    }

    @Test func noStandInWhileTheBoardIsNotInItsOwnOrder() {
        let store = carrying(TestBoard.widget, over: .above(TestBoard.cafe))
        store.sortOrder = .dueDate

        #expect(store.allowsCardDrag == false)
        #expect(store.dropPreview(in: place(store, backlog)) == nil)
    }

    // MARK: It must not promise a move that will not happen

    /// `dragDrop` sits directly above `cafe` in Backlog, so both names for the
    /// gap between them name the gap `dragDrop` is already in.
    @Test func noStandInWhereTheDropWouldMoveNothing() {
        for caret in [DropCaret.above(TestBoard.cafe), .below(TestBoard.dragDrop)] {
            let store = carrying(TestBoard.dragDrop, over: caret)

            #expect(store.dropCaret == caret, "the caret still marks the gap")
            #expect(store.dropPreview(in: store.placement(forColumn: backlog)) == nil,
                    "\(caret): a hole opened for a card that would not move")
        }
    }

    /// The other half of that: the row the stand-in claims is the row the drop
    /// actually puts the card in. Asserted over every gap in a column, from a
    /// card that starts outside it — so the rows it is counting are the rows
    /// the drop shifts.
    @Test func theStandInSitsWhereTheDropPutsTheCard() throws {
        let gaps: [DropCaret] = [
            .above(TestBoard.dragDrop), .below(TestBoard.dragDrop),
            .above(TestBoard.cafe), .below(TestBoard.cafe),
        ]
        for caret in gaps {
            let store = carrying(TestBoard.widget, over: caret)
            let rowsBefore = store.visibleTasks(in: backlog).count
            let promised = try #require(
                store.dropPreview(in: store.placement(forColumn: backlog))?.index, "\(caret)"
            )

            store.drop(TestBoard.widget, at: caret)

            let rows = store.visibleTasks(in: backlog).map(\.id)
            #expect(rows.firstIndex(of: TestBoard.widget) == promised,
                    "\(caret): promised row \(promised), landed in \(rows)")
            #expect(rows.count == rowsBefore + 1)
        }
    }

    // MARK: A list's own ground

    @Test func aDropOnAListsGroundStandsAtItsFoot() throws {
        let store = carrying(TestBoard.widget, overGroundOf: backlog)
        let preview = try #require(store.dropPreview(in: place(store, backlog)))

        #expect(preview.index == store.visibleTasks(in: backlog).count)
        #expect(preview.caret == .below(TestBoard.cafe))
    }

    /// **The one the caret could not draw.** A line needs a card to hang off,
    /// so an empty column got no mark at all and the column highlight was the
    /// whole of the feedback — on precisely the drop with least else on screen
    /// to explain it. A row needs no anchor.
    @Test func anEmptyColumnGetsTheStandInTheCaretCouldNotDraw() throws {
        let store = carrying(
            TestBoard.widget, overGroundOf: backlog,
            tasks: TestBoard.tasks.filter { $0.id == TestBoard.widget }
        )
        #expect(store.visibleTasks(in: backlog).isEmpty)
        #expect(store.dropCaret == nil, "a caret was drawn against a card that is not there")

        let preview = try #require(store.dropPreview(in: place(store, backlog)))
        #expect(preview.index == 0)
        #expect(preview.caret == nil, "an empty list names no gap to land in")
    }

    @Test func noStandInOnTheGroundOfTheListTheCardIsAlreadyIn() {
        let store = carrying(TestBoard.dragDrop, overGroundOf: backlog)

        #expect(store.dropPreview(in: store.placement(forColumn: backlog)) == nil)
    }

    // MARK: The rule that keeps it still

    /// **Read out of the source, because it is a rule about a callback nothing
    /// can call from here.** Opening a gap moves the card under it down, so the
    /// pointer that was in that card's upper half ends up over the new row: a
    /// zone that cleared the caret on the way out would shut the gap that moved
    /// the pointer off it, and the stand-in would flicker in and out for the
    /// length of the drag. A card's half therefore claims on entry and says
    /// nothing on exit — see `BoardStore.dropTargetCaret` — and the lists' own
    /// grounds are what retire a caret, since a nested zone takes the hover from
    /// its parent and so `isTargeted` there means "in no gap at all".
    @Test func onlyAListsGroundRetiresACaret() {
        guard SourceTree.isReachable else { return }
        let halves = ["Shared/BoardTaskCard.swift", "IOS/PhoneTaskCard.swift"]
        let grounds = [
            "Shared/BoardColumnView.swift", "IOS/PhoneColumnPage.swift",
            "Shared/InboxPanel.swift", "IOS/PhoneInboxSheet.swift",
        ]
        var seen: Set<String> = []
        for file in SourceTree.files() {
            let code = String(file.code)
            if halves.contains(file.path) {
                #expect(!code.contains("store.dropTargetCaret = nil"),
                        "\(file.path) clears the caret as the pointer leaves a card's half")
                #expect(code.contains("store.dropTargetCaret = caret"),
                        "\(file.path) no longer claims the gap its half names")
                seen.insert(file.path)
            }
            if grounds.contains(file.path) {
                #expect(code.contains("store.dropTargetCaret = nil"),
                        "\(file.path)'s ground does not retire the gap a card's half named")
                seen.insert(file.path)
            }
        }
        #expect(seen == Set(halves + grounds), "a drop zone has moved file: found \(seen)")
    }
}
