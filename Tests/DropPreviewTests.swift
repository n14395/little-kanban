import Foundation
import Testing
@testable import Cardstock

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
///
/// "Free to mark the gap a card already sits in" is about the *stand-in*, and
/// it is not a promise that a caret is drawn wherever the pointer is: a gap
/// named by the card **in the air** has no caret at all, because a line against
/// a card that is leaving says nothing about where anything lands. That rule is
/// the caret's own and is pinned by
/// ``DropCaretTests/thereIsNoCaretOnTheCardInTheAir()``; what is tested here is
/// only what the stand-in does on top of it.
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

    @Test func theInboxPreviewShowsCardsArrivingFromABoard() throws {
        let store = carrying(TestBoard.dragDrop, over: .above(TestBoard.widget))
        let preview = try #require(store.dropPreview(in: .inbox))

        #expect(preview.task.id == TestBoard.dragDrop)
        #expect(preview.index == 0)
        #expect(preview.caret == .above(TestBoard.widget))
        #expect(preview.placement == .inbox)
    }

    @Test func theInboxPreviewFollowsBothDirectionsOfAReorder() throws {
        let tail = TaskItem(id: TestBoard.taskID(90), code: "IN-190", title: "Inbox tail")

        let upward = TestBoard.store(tasks: TestBoard.tasks + [tail])
        upward.draggingID = tail.id
        upward.dropTargetCaret = .above(TestBoard.widget)
        #expect(try #require(upward.dropPreview(in: .inbox)).index == 0)
        upward.drop(tail.id, at: .above(TestBoard.widget))
        #expect(upward.inboxTasks.first?.id == tail.id)

        let downward = TestBoard.store(tasks: TestBoard.tasks + [tail])
        downward.draggingID = TestBoard.widget
        downward.dropTargetCaret = .below(tail.id)
        #expect(try #require(downward.dropPreview(in: .inbox)).index == 2)
        downward.drop(TestBoard.widget, at: .below(tail.id))
        #expect(downward.inboxTasks.last?.id == TestBoard.widget)
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

    /// **The Inbox keeps its stand-in with a saved view open behind it**, which
    /// is the other half of the Inbox keeping its drops: a drop that lands and
    /// says nothing on the way about where it will land is a drag with its
    /// answer taken away. The caret and the stand-in are drawn by the list a
    /// drop is *aimed at*, so both ask that list's rule — see
    /// ``BoardStore/allowsCardDrag(into:)``.
    @Test func theInboxKeepsItsStandInUnderASavedView() throws {
        // `widget` is the seeded board's Inbox card; `tail` joins it, so the
        // caret names a gap between two cards that are both in the Inbox —
        // which is the reorder the phone could not see itself doing.
        let tail = TaskItem(id: TestBoard.taskID(90), code: "IN-190", title: "Inbox tail")
        for view in SavedView.allCases {
            let store = TestBoard.store(tasks: TestBoard.tasks + [tail])
            store.draggingID = tail.id
            store.dropTargetCaret = .above(TestBoard.widget)
            store.activeView = view

            #expect(store.dropCaret == .above(TestBoard.widget),
                    "\(view.rawValue): the Inbox lost its caret")
            let preview = try #require(store.dropPreview(in: .inbox),
                                       "\(view.rawValue): the Inbox lost its stand-in")
            #expect(preview.task.id == tail.id)
            #expect(preview.index == 0)
            #expect(preview.placement == .inbox)
        }
    }

    /// And the board does not, under the same view — the rule it was written
    /// for is untouched, and a stand-in on a list whose rows are not the
    /// board's order would promise a move the drop cannot make.
    @Test func theBoardStillHasNoStandInUnderASavedView() {
        let store = carrying(TestBoard.dragDrop, over: .above(TestBoard.cafe))
        store.activeView = .today

        #expect(store.dropCaret == nil, "a board caret survived a saved view")
        #expect(store.dropPreview(in: place(store, backlog)) == nil)
    }

    /// A non-manual sort takes the Inbox's marks too, for the reason it takes
    /// the board's: the rows on screen are not the order a drop rearranges.
    @Test func theInboxLosesItsStandInUnderASortItDidNotChoose() {
        let tail = TaskItem(id: TestBoard.taskID(90), code: "IN-190", title: "Inbox tail")
        let store = TestBoard.store(tasks: TestBoard.tasks + [tail])
        store.draggingID = tail.id
        store.dropTargetCaret = .above(TestBoard.widget)
        store.sortOrder = .dueDate

        #expect(store.dropCaret == nil)
        #expect(store.dropPreview(in: .inbox) == nil)
    }

    @Test func bothInboxSurfacesDrawTheSharedPreviewInsteadOfAnEdgeCaret() {
        guard SourceTree.isReachable else { return }
        let expected = [
            "Shared/InboxPanel.swift": ["store.dropPreview(in: .inbox)", "DropPreviewCard(",
                                        ".environment(\\.drawsDropCaret, false)"],
            "IOS/PhoneInboxSheet.swift": ["preview: preview", ".environment(\\.drawsDropCaret, false)"],
        ]
        var seen: Set<String> = []
        for file in SourceTree.files() {
            guard let snippets = expected[file.path] else { continue }
            let code = String(file.code)
            for snippet in snippets {
                #expect(code.contains(snippet), "\(file.path) no longer draws Inbox preview feedback")
            }
            seen.insert(file.path)
        }
        #expect(seen == Set(expected.keys), "an Inbox preview surface moved: found \(seen)")
    }

    // MARK: It must not promise a move that will not happen

    /// `dragDrop` sits directly above `cafe` in Backlog, so both names for the
    /// gap between them name the gap `dragDrop` is already in.
    ///
    /// **The stand-in is the subject, and it is absent under both names.** The
    /// caret is not: `.above(cafe)` is drawn, because marking a gap a card
    /// already sits in costs nothing, and `.below(dragDrop)` is not, because
    /// `dragDrop` is the card in the air — see the note on the suite. Asserting
    /// one caret for both said the second rule did not exist.
    @Test func noStandInWhereTheDropWouldMoveNothing() {
        for caret in [DropCaret.above(TestBoard.cafe), .below(TestBoard.dragDrop)] {
            let store = carrying(TestBoard.dragDrop, over: caret)
            let namesTheCardInTheAir = caret.card == TestBoard.dragDrop

            #expect(store.dropCaret == (namesTheCardInTheAir ? nil : caret),
                    "\(caret): the caret is not what the card in the air leaves it")
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

    /// **The band that belonged to nobody**, and the other half of the rule
    /// above: what retires a caret is the ground, so nothing between two cards
    /// may be ground. A card's halves reach `dropReach` into the gap at each
    /// end and meet in the middle of it — but the stand-in opens a gap twice as
    /// wide as a spacing and used to claim only the card-shaped middle of it,
    /// which left a `dropReach`-wide strip of bare list above it and another
    /// below. A pointer held in one of those strips was on the ground: the gap
    /// shut, the rows sprang back under it, the half it landed on named the
    /// same gap again, and the stand-in flickered for as long as the pointer
    /// stayed there — the exact loop `BoardStore.dropTargetCaret` is written to
    /// avoid, coming in through the one zone that was not reaching.
    ///
    /// Read out of the source for that comment's reason: this is a fact about
    /// layout inside a `dropDestination`, and there is nothing to measure from
    /// here. Each surface's reach is its own card's, so the two meet exactly.
    @Test func theStandInReachesAsFarIntoTheGapAsTheCardsDo() {
        guard SourceTree.isReachable else { return }
        let expected = [
            "Shared/DropPreviewCard.swift": ".padding(.vertical, -reach)",
            "Shared/BoardColumnView.swift": "reach: metrics.card.dropReach",
            "Shared/InboxPanel.swift": "reach: metrics.card.dropReach",
            "IOS/PhoneCardStack.swift": "reach: TaskListMetrics.sheet.rowSpacing / 2",
        ]
        var seen: Set<String> = []
        for file in SourceTree.files() {
            guard let snippet = expected[file.path] else { continue }
            #expect(String(file.code).contains(snippet),
                    "\(file.path): the stand-in's gap no longer reaches the cards' halves")
            seen.insert(file.path)
        }
        #expect(seen == Set(expected.keys), "a stand-in moved file: found \(seen)")
    }

    /// The reach each surface passes is half its own row gap — which is what
    /// makes "meet in the middle" true rather than merely close. Asserted on
    /// the numbers rather than on the source, because these are the numbers.
    @Test func everySurfacesReachIsHalfItsOwnRowGap() {
        #expect(BoardTaskCard.Metrics.desk.dropReach == BoardColumnView.Metrics.desk.cardSpacing / 2)
        #expect(BoardTaskCard.Metrics.pad.dropReach == BoardColumnView.Metrics.pad.cardSpacing / 2)
        #expect(BoardTaskCard.Metrics.desk.dropReach == TaskListMetrics.panel.rowSpacing / 2)
        #expect(BoardTaskCard.Metrics.pad.dropReach == TaskListMetrics.panelPad.rowSpacing / 2)
    }
}
