import Foundation
import Testing
@testable import LittleKanban

@MainActor
@Suite struct BoardStoreMutationTests {
    private let backlog = BoardColumn.backlog.id
    private let upNext = BoardColumn.upNext.id
    private let doing = BoardColumn.inProgress.id
    private let done = BoardColumn.done.id

    private func column(of store: BoardStore, _ id: TaskItem.ID) -> BoardColumn.ID? { store[id]?.columnID }

    private func kinds(_ store: BoardStore, _ id: TaskItem.ID) -> [ActivityEntry.Kind] {
        store[id]?.activity.map(\.kind) ?? []
    }

    private func isDoneTick(_ kind: ActivityEntry.Kind) -> Bool {
        if case .subtasksCompletedOnDone = kind { return true }
        return false
    }

    private func isDueSet(_ kind: ActivityEntry.Kind) -> Bool {
        if case .dueSet = kind { return true }
        return false
    }

    // MARK: Moving

    @Test func movingToAnotherColumnRecordsWhereItWent() {
        let store = TestBoard.store()
        store.move(TestBoard.dragDrop, to: doing)
        #expect(column(of: store, TestBoard.dragDrop) == doing)
        #expect(kinds(store, TestBoard.dragDrop).first == .moved(columnID: BoardColumn.inProgress.id.uuidString, columnName: "In Progress"))
    }

    @Test func aDropOnTheColumnACardIsAlreadyInDoesNothing() {
        let store = TestBoard.store()
        let before = store.tasks
        store.draggingID = TestBoard.dragDrop
        store.dropTargetColumnID = backlog
        store.move(TestBoard.dragDrop, to: backlog)
        #expect(store.tasks == before)
        #expect(store.draggingID == nil)
        #expect(store.dropTargetColumnID == nil)
    }

    @Test func aDropOnACardsOwnSelfDoesNothing() {
        let store = TestBoard.store()
        let before = store.tasks
        store.move(TestBoard.dragDrop, to: backlog, before: TestBoard.dragDrop)
        #expect(store.tasks == before)
    }

    @Test func droppingOnACardInsertsAheadOfIt() throws {
        let store = TestBoard.store()
        store.move(TestBoard.sync, to: backlog, before: TestBoard.dragDrop)
        let order = store.tasks.map(\.id)
        let moved = try #require(order.firstIndex(of: TestBoard.sync))
        let target = try #require(order.firstIndex(of: TestBoard.dragDrop))
        #expect(moved + 1 == target)
        #expect(store.visibleTasks(in: backlog).map(\.id) == [TestBoard.sync, TestBoard.dragDrop, TestBoard.cafe])
    }

    @Test func aMoveWithNoTargetLandsAtTheEndOfTheBoard() {
        let store = TestBoard.store()
        store.move(TestBoard.dragDrop, to: doing)
        #expect(store.tasks.last?.id == TestBoard.dragDrop)
    }

    @Test func reorderingWithinAColumnKeepsTheColumnAndLogsNoMove() {
        let store = TestBoard.store()
        let historyBefore = kinds(store, TestBoard.cafe).count
        store.move(TestBoard.cafe, to: backlog, before: TestBoard.dragDrop)
        #expect(store.visibleTasks(in: backlog).map(\.id) == [TestBoard.cafe, TestBoard.dragDrop])
        #expect(kinds(store, TestBoard.cafe).count == historyBefore)
    }

    // MARK: Dropping onto a card

    /// A drop says "put me here", but `before:` can only say "put me ahead of
    /// that one" — so a card dragged *downwards* onto its neighbour was taken
    /// out and put back exactly where it started. Measured on an iPad as "no
    /// move, no error, no visual change", while the identical gesture upwards
    /// reordered correctly. Same off-by-one as `moveSubtask`'s, one direction
    /// only, which is where it hides.
    @Test func droppingACardOnTheOneBelowItLandsBelowIt() {
        let store = TestBoard.store()
        #expect(store.visibleTasks(in: backlog).map(\.id) == [TestBoard.dragDrop, TestBoard.cafe])

        store.move(TestBoard.dragDrop, onto: TestBoard.cafe)
        #expect(store.visibleTasks(in: backlog).map(\.id) == [TestBoard.cafe, TestBoard.dragDrop])
    }

    @Test func droppingACardOnTheOneAboveItLandsAboveIt() {
        let store = TestBoard.store()
        store.move(TestBoard.cafe, onto: TestBoard.dragDrop)
        #expect(store.visibleTasks(in: backlog).map(\.id) == [TestBoard.cafe, TestBoard.dragDrop])
    }

    /// The downward drop with nothing after it has no card to sit in front of,
    /// which is the same shape as "dropped on the column, nowhere in
    /// particular" — a deliberate no-op since item 1.17. They must not be
    /// confused, or the last position in a column becomes unreachable by drag.
    @Test func droppingACardPastTheLastOneIsAMoveAndNotANoOp() {
        let store = TestBoard.store()
        store.move(TestBoard.dragDrop, to: doing)   // three cards in one column
        store.move(TestBoard.cafe, to: doing)
        let column = store.visibleTasks(in: doing).map(\.id)
        let first = column[0]
        let last = column[column.count - 1]
        #expect(first != last)

        store.move(first, onto: last)
        #expect(store.visibleTasks(in: doing).last?.id == first)
    }

    @Test func droppingACardOnItselfChangesNothing() {
        let store = TestBoard.store()
        let before = store.tasks
        store.move(TestBoard.cafe, onto: TestBoard.cafe)
        #expect(store.tasks == before)
    }

    // MARK: The Done tick

    @Test func movingIntoDoneTicksOffWhatIsOutstanding() {
        let store = TestBoard.store()
        store.move(TestBoard.dragDrop, to: done)
        let task = store[TestBoard.dragDrop]
        #expect(task?.subtasks.allSatisfy(\.done) == true)
        #expect(kinds(store, TestBoard.dragDrop).contains(.subtasksCompletedOnDone(count: 2)))
    }

    @Test func movingIntoDoneWithNothingOutstandingLogsNoTick() {
        let store = TestBoard.store()
        store.move(TestBoard.widget, to: done)      // no sub-tasks at all
        #expect(kinds(store, TestBoard.widget).contains(where: isDoneTick) == false)
    }

    @Test func aMoveWithinDoneDoesNotReTick() {
        let store = TestBoard.store()
        store.move(TestBoard.dragDrop, to: done)
        // The user un-ticks one afterwards; shuffling the card inside Done must
        // leave that alone.
        store.toggleSubtask(TestBoard.keyboard, on: TestBoard.dragDrop)
        store.move(TestBoard.dragDrop, to: done, before: TestBoard.palette)
        let subtask = store[TestBoard.dragDrop]?.subtasks.first { $0.id == TestBoard.keyboard }
        #expect(subtask?.done == false)
        #expect(kinds(store, TestBoard.dragDrop).count(where: isDoneTick) == 1)
    }

    // MARK: Completing and reopening

    @Test func completingSendsATaskToDone() {
        let store = TestBoard.store()
        store.complete(TestBoard.sync)
        #expect(column(of: store, TestBoard.sync) == done)
        #expect(kinds(store, TestBoard.sync).first == .moved(columnID: BoardColumn.done.id.uuidString, columnName: "Done"))
    }

    @Test func completingSomethingAlreadyDoneDoesNothing() {
        let store = TestBoard.store()
        let before = store.tasks
        store.complete(TestBoard.palette)
        #expect(store.tasks == before)
    }

    @Test func reopeningGoesBackToWhereTheTaskWasWorking() {
        let store = TestBoard.store()
        store.reopen(TestBoard.palette)          // its history names Up Next under Done
        #expect(column(of: store, TestBoard.palette) == upNext)
    }

    @Test func reopeningAfterCompletingReturnsToTheColumnItLeft() {
        let store = TestBoard.store()
        store.complete(TestBoard.sync)
        store.reopen(TestBoard.sync)
        #expect(column(of: store, TestBoard.sync) == doing)
    }

    @Test func aTaskThatReachedDoneWithoutEverMovingReopensIntoBacklog() {
        let store = TestBoard.store()
        let id = store.addTask(to: done, title: "Straight to Done")
        store.reopen(id)
        #expect(column(of: store, id) == BoardColumn.backlog.id)
    }

    @Test func reopeningSomethingNotDoneDoesNothing() {
        let store = TestBoard.store()
        let before = store.tasks
        store.reopen(TestBoard.dragDrop)
        #expect(store.tasks == before)
    }

    // MARK: The tick, whichever tick it is

    /// `toggleCompletion` is what the tick on a card, the tick in the detail
    /// panel and the phone sheet's tick all call. Each used to spell out
    /// `isDone ? reopen : complete` for itself, which is two chances for one
    /// surface to answer a different question from the one beside it.
    @Test func theTickGoesBothWays() {
        let store = TestBoard.store()

        store.toggleCompletion(TestBoard.sync)
        #expect(column(of: store, TestBoard.sync) == done)

        store.toggleCompletion(TestBoard.sync)
        #expect(column(of: store, TestBoard.sync) == doing, "the tick would not come back off")
    }

    /// **The two directions do not have the same condition**, which is why the
    /// panel asks this rather than `canComplete`: reopening needs only that the
    /// card is in Done, so on a completed card `canComplete` is false and the
    /// tick is still live.
    @Test func aCompletedCardCanStillBeTickedEvenThoughItCannotBeCompleted() {
        let store = TestBoard.store()
        #expect(store.canComplete(TestBoard.palette) == false)
        #expect(store.canToggleCompletion(TestBoard.palette))
    }

    /// **A board of one column, which is the state every board is made in.**
    ///
    /// That column is the board's last and so its Done one, and there is nowhere
    /// to work — so the card is already complete and cannot be completed, and
    /// reopening it has no column to go back to. Neither direction of the tick
    /// can act, and the panel draws it as unable rather than live and swallowing
    /// the press. See `DoneColumnTests` for the same claim through the store's
    /// own `createBoard`.
    @Test func aCardWithNoDoneColumnToReachCannotBeTicked() {
        let onlyColumn = BoardColumn(name: "Only", short: "ON", dot: .ink(opacity: 0.35))
        let board = Board(name: "No finish line",
                          columns: [onlyColumn], codePrefix: "NF")
        let card = TaskItem(id: TestBoard.taskID(90), code: "NF-1", columnID: onlyColumn.id,
                            title: "Nowhere to finish",
                            createdAt: TestBoard.at(10), updatedAt: TestBoard.at(10))
        let store = TestBoard.store(tasks: [card], boards: [board])

        #expect(store.canComplete(card.id) == false)
        #expect(store.canToggleCompletion(card.id) == false)

        let before = store.tasks
        store.toggleCompletion(card.id)
        #expect(store.tasks == before, "a tick that says it cannot act moved a card")
    }

    /// In the Archive the verb is Restore and only Restore — `complete` and
    /// `reopen` both refuse a filed card — so there is nothing for a tick to do
    /// and the panel does not draw one.
    @Test func anArchivedCardOffersNoTick() {
        let store = TestBoard.store()
        store.archive(TestBoard.sync)
        #expect(store.canToggleCompletion(TestBoard.sync) == false)

        let before = store.tasks
        store.toggleCompletion(TestBoard.sync)
        #expect(store.tasks == before, "the tick moved a card out of the Archive")
    }

    @Test func aCardThatIsNotThereCannotBeTicked() {
        let store = TestBoard.store()
        #expect(store.canToggleCompletion(TestBoard.taskID(200)) == false)
    }

    // MARK: Adding

    @Test func addedTasksMintSequentialCodes() {
        let store = TestBoard.store()
        let first = store.addTask(to: backlog, title: "One")
        let second = store.addTask(to: backlog, title: "Two")
        #expect(store[first]?.code == "NW-140")
        #expect(store[second]?.code == "NW-141")
        #expect(store[first]?.activity.map(\.kind) == [.created])
    }

    /// **Every door mints the same card.** A quick capture, the inline
    /// composer, the board menu and a bulk add all go through `mintTask`, which
    /// is the only place a priority is chosen — and it chooses `Priority.default`
    /// rather than a case of its own, so the two spellings of "what a card
    /// starts on" cannot drift apart. `PriorityTests` holds what that constant
    /// is; this holds that the store uses it.
    @Test func anAddedTaskStartsAtTheDefaultPriority() {
        let store = TestBoard.store()
        #expect(store[store.addTask(to: backlog, title: "Typed")]?.priority == Priority.default)
        #expect(store[store.captureToInbox()]?.priority == Priority.default)
        #expect(store.addTasks(to: backlog, titles: ["A", "B"])
            .allSatisfy { store[$0]?.priority == Priority.default })
    }

    @Test func addingSelectsOnTheDeskAndOpensTheSheetOnThePhone() {
        let store = TestBoard.store()
        let desk = store.addTask(to: backlog, title: "Desk")
        #expect(store.selectedID == desk)
        #expect(store.sheetID == nil)

        let phone = store.addTask(to: backlog, title: "", fromPhone: true, log: .captured)
        #expect(store.sheetID == phone)
        #expect(store.pendingTitleFocusID == phone)
        #expect(store[phone]?.activity.map(\.kind) == [.captured])
    }

    @Test func aNamedTaskDoesNotAskForTitleFocus() {
        let store = TestBoard.store()
        let id = store.addTask(to: backlog, title: "Named already")
        #expect(store.pendingTitleFocusID == nil)
        #expect(store[id]?.title == "Named already")
    }

    /// **The iPad, and only the iPad, opens its editor on the card it just
    /// made.** `commitDraft` says why at length: there the editor is a panel the
    /// *app* puts away when three of them will not fit, so a card can be made
    /// into an editor that is not on screen — selected, and nowhere to be seen.
    /// The desk's inspector is one the *user* shuts, and the phone answers with
    /// its sheet.
    ///
    /// Written as "matches the platform" rather than as two tests behind an
    /// `#if`, because the claim is exactly that the rule reads the platform: a
    /// build where the branch was deleted passes one half and fails the other
    /// whichever destination the suite is run on.
    @Test func aCardMadeOnTheIPadOpensInTheEditorAndNowhereElse() throws {
        let store = TestBoard.store()
        store.isInspectorOpen = false
        store.beginAdding(in: .inbox)
        store.draft = "Ring the framer back"

        let made = try #require(store.commitDraft())
        #expect(store.selectedID == made, "the editor would have nothing to show")
        #expect(store.isInspectorOpen == BoardStore.isPad,
                "the editor opened where it should not, or did not where it should")
    }

    /// And it does not open one for a draft that committed nothing, on any
    /// platform: a blank composer dismissed is not a card made.
    @Test func aBlankDraftOpensNoEditor() {
        let store = TestBoard.store()
        store.isInspectorOpen = false
        store.beginAdding(in: .inbox)
        store.draft = "   "

        #expect(store.commitDraft() == nil)
        #expect(store.isInspectorOpen == false)
    }

    @Test func theInlineComposerTrimsAndRefusesBlanks() {
        let store = TestBoard.store()
        store.beginAdding(in: upNext)
        store.draft = "   "
        store.commitDraft()
        #expect(store.tasks.count == TestBoard.tasks.count)

        store.draft = "  Trim me  "
        store.commitDraft()
        #expect(store.tasks.last?.title == "Trim me")
        #expect(store.addingColumnID == nil)
        #expect(store.draft.isEmpty)
    }

    // MARK: Deleting

    @Test func deletingReturnsTheTaskAndTakesItOffTheBoard() {
        let store = TestBoard.store()
        let removed = store.deleteTask(TestBoard.cafe)
        #expect(removed?.code == "NW-122")
        #expect(store[TestBoard.cafe] == nil)
        #expect(store.tasks.count == TestBoard.tasks.count - 1)
        #expect(store.deleteTask(TestBoard.cafe) == nil)
    }

    @Test func theSelectionFallsToTheNeighbourInTheSameColumn() {
        let store = TestBoard.store()
        store.selectedID = TestBoard.dragDrop
        store.deleteTask(TestBoard.dragDrop)
        #expect(store.selectedID == TestBoard.cafe)          // the next one down in Backlog

        store.selectedID = TestBoard.cafe
        store.deleteTask(TestBoard.cafe)
        #expect(store.selectedID == nil)                     // Backlog is empty now

        store.selectedID = TestBoard.widget
        store.deleteTask(TestBoard.widget)
        #expect(store.selectedID == nil)                     // Inbox held only that one
    }

    @Test func theSelectionFallsDownwardsBeforeItFallsUpwards() {
        // Backlog holds two cards, so "next, else previous" and "previous, else
        // next" land on the same one either way. A third makes the order
        // visible, and the order is the point: falling upwards out of the middle
        // of a column reads as the board having moved under the pointer.
        let store = TestBoard.store()
        let third = store.addTask(to: backlog, title: "Third in backlog")
        #expect(store.visibleTasks(in: backlog).map(\.id) == [TestBoard.dragDrop, TestBoard.cafe, third])

        store.selectedID = TestBoard.cafe
        store.deleteTask(TestBoard.cafe)
        #expect(store.selectedID == third)
    }

    @Test func theSelectionFallsUpwardsWhenThereIsNothingBelow() {
        let store = TestBoard.store()
        store.selectedID = TestBoard.cafe
        store.deleteTask(TestBoard.cafe)
        #expect(store.selectedID == TestBoard.dragDrop)
    }

    @Test func deletingClearsEverySessionThingNamingTheTask() {
        let store = TestBoard.store()
        store.sheetID = TestBoard.cafe
        store.draggingID = TestBoard.cafe
        store.pendingTitleFocusID = TestBoard.cafe
        store.setSubtaskDraft("half typed", for: .sheet, task: TestBoard.cafe)
        store.beginEditing(.title, on: TestBoard.cafe, scope: .sheet)

        store.deleteTask(TestBoard.cafe)
        #expect(store.sheetID == nil)
        #expect(store.draggingID == nil)
        #expect(store.pendingTitleFocusID == nil)
        #expect(store.subtaskDraft(for: .sheet, task: TestBoard.cafe).isEmpty)
        #expect(store.isEditing(.title, on: TestBoard.cafe, scope: .sheet) == false)
    }

    // MARK: Discarding a capture nothing was filled into

    @Test func aBlankCaptureIsDiscardedAndHandsItsCodeBack() {
        let store = TestBoard.store()
        let id = store.addTask(to: .inbox, title: "", fromPhone: true, log: .captured)
        #expect(store[id]?.code == "IN-140")
        store.discardIfBlank(id)
        #expect(store[id] == nil)
        #expect(store.sheetID == nil)
        // The next capture takes the number back rather than leaving a gap.
        let next = store.addTask(to: .inbox, title: "", fromPhone: true, log: .captured)
        #expect(store[next]?.code == "IN-140")
    }

    /// The rule the old one had backwards: what matters is what the editor was
    /// closed with, not whether anything was ever typed in it. Every one of
    /// these was *touched*, and every one of them is empty again by the end.
    @Test func aCaptureTypedIntoAndEmptiedAgainIsDiscarded() {
        let store = TestBoard.store()
        let id = store.addTask(to: BoardColumn.inbox.id, title: "", fromPhone: true, log: .captured)
        store.setText("Something", field: .title, on: id)
        store.setText("", field: .title, on: id)
        store.discardIfBlank(id)
        #expect(store[id] == nil)
    }

    @Test func aCaptureWhosePickersCameHomeAgainIsDiscarded() {
        let store = TestBoard.store()
        let id = store.addTask(to: .inbox, title: "", fromPhone: true, log: .captured)
        let made = store[id]
        store.setPriority(.high, on: id)
        store.setPriority(made?.priority ?? .medium, on: id)
        store.setDue(TestBoard.dueDay, on: id)
        store.setDue(made?.due, on: id)
        store.toggleLabel("design", on: id)
        store.toggleLabel("design", on: id)
        store.discardIfBlank(id)
        #expect(store[id] == nil)
    }

    /// A title of spaces is a title nobody typed — and it is what the field
    /// holds until the editing session ends and trims it, which is after the
    /// dismissal has already asked this question.
    @Test func aCaptureHoldingOnlyWhitespaceIsDiscarded() {
        let store = TestBoard.store()
        let id = store.addTask(to: .inbox, title: "", fromPhone: true, log: .captured)
        store.setText("   ", field: .title, on: id)
        store.discardIfBlank(id)
        #expect(store[id] == nil)
    }

    @Test func aCaptureWithAnythingInItIsKept() {
        let fills: [(BoardStore, TaskItem.ID) -> Void] = [
            { store, id in store.setText("Real", field: .title, on: id) },
            { store, id in store.setText("A note", field: .note, on: id) },
            { store, id in store.setPriority(.high, on: id) },
            { store, id in store.setDue(TestBoard.laterDay, on: id) },
            { store, id in store.toggleLabel("design", on: id) },
            { store, id in _ = store.addSubtask(to: id, text: "One thing") },
            // The editor's own board menu: filed from the Inbox onto a board,
            // with every other control still exactly as capture left it.
            { store, id in store.move(id, to: BoardColumn.backlog.id) },
        ]
        for fill in fills {
            let store = TestBoard.store()
            let id = store.addTask(to: .inbox, title: "", fromPhone: true, log: .captured)
            fill(store, id)
            store.discardIfBlank(id)
            #expect(store[id] != nil)
        }
    }

    /// A card born with a due date because of the preference is still a card
    /// nobody filled anything into: the empty state is what capture made, not a
    /// row of nils.
    @Test func aCaptureIsMeasuredAgainstWhatCaptureMadeRatherThanAgainstNothing() {
        let store = TestBoard.store()
        store.defaultDueDate = .tomorrow
        let id = store.addTask(to: .inbox, title: "", fromPhone: true, log: .captured)
        #expect(store[id]?.due != nil)
        store.discardIfBlank(id)
        #expect(store[id] == nil)
    }

    /// Asked once. Whatever the card is after the editor closes, it is one the
    /// user kept — reopening and closing it again must not take it away.
    @Test func aCaptureThatSurvivedItsDismissalIsNeverAskedAgain() {
        let store = TestBoard.store()
        let id = store.addTask(to: .inbox, title: "", fromPhone: true, log: .captured)
        store.setText("Real", field: .title, on: id)
        store.discardIfBlank(id)
        store.setText("", field: .title, on: id)
        store.discardIfBlank(id)
        #expect(store[id] != nil)
    }

    @Test func discardingLeavesAnOrdinaryTaskAlone() {
        let store = TestBoard.store()
        store.discardIfBlank(TestBoard.cafe)
        #expect(store[TestBoard.cafe] != nil)
    }

    // MARK: Sub-tasks

    @Test func reorderingCountsTheOffsetInThePreMoveArray() throws {
        // `ChecklistView.move(from:to:)` — the row's Move Up / Move Down —
        // computes `to > from ? to + 1 : to` precisely because
        // `move(fromOffsets:toOffset:)` reads the offset in the array as it
        // still stands, so landing *after* the target is one past it. Downwards
        // is the direction an off-by-one hides in. The *drag* names a gap
        // instead now and does its own arithmetic; `SubtaskReorderTests` is
        // where that half is pinned.
        let store = TestBoard.store()
        let ids = try #require(store[TestBoard.dragDrop]?.subtasks.map(\.id))
        #expect(ids == [TestBoard.lift, TestBoard.dropTargets, TestBoard.keyboard])

        // The first row dragged onto the last: from 0, target 2, so offset 3.
        store.moveSubtask(fromOffsets: IndexSet(integer: 0), toOffset: 3, on: TestBoard.dragDrop)
        #expect(store[TestBoard.dragDrop]?.subtasks.map(\.id)
                == [TestBoard.dropTargets, TestBoard.keyboard, TestBoard.lift])
        // The ticks travel with the rows they belong to.
        #expect(store[TestBoard.dragDrop]?.subtasks.map(\.done) == [false, false, true])

        // …and back up: from 2, target 0, so offset 0.
        store.moveSubtask(fromOffsets: IndexSet(integer: 2), toOffset: 0, on: TestBoard.dragDrop)
        #expect(store[TestBoard.dragDrop]?.subtasks.map(\.id) == ids)
        #expect(kinds(store, TestBoard.dragDrop) == [.created])          // reordering logs nothing
    }

    @Test func aRowMovedDownLandsPastTheRowItWasMovedOver() {
        // `dropOffset` reads its offset in the array as it still stands, so a
        // row moved downwards lands one *past* the row it stepped over. Driving
        // `moveSubtask` with a hand-written offset cannot see that expression at
        // all — replacing it with a bare `to` leaves the reorder test above
        // green — so the arithmetic is asserted, and then asserted again through
        // the store so the order it produces is a real one.
        #expect(BoardStore.dropOffset(from: 0, to: 1) == 2)
        #expect(BoardStore.dropOffset(from: 0, to: 2) == 3)
        #expect(BoardStore.dropOffset(from: 1, to: 2) == 3)

        let store = TestBoard.store()
        store.moveSubtask(
            fromOffsets: IndexSet(integer: 0),
            toOffset: BoardStore.dropOffset(from: 0, to: 2),
            on: TestBoard.dragDrop
        )
        #expect(store[TestBoard.dragDrop]?.subtasks.map(\.id)
                == [TestBoard.dropTargets, TestBoard.keyboard, TestBoard.lift])
    }

    @Test func aRowMovedUpLandsOnTheRowItWasMovedOver() throws {
        // Upwards there is nothing to step over: the target's own index is where
        // the row goes, and adding one there would overshoot by a row.
        #expect(BoardStore.dropOffset(from: 1, to: 0) == 0)
        #expect(BoardStore.dropOffset(from: 2, to: 0) == 0)
        #expect(BoardStore.dropOffset(from: 2, to: 1) == 1)

        let store = TestBoard.store()
        let ids = try #require(store[TestBoard.dragDrop]?.subtasks.map(\.id))
        #expect(ids == [TestBoard.lift, TestBoard.dropTargets, TestBoard.keyboard])
        store.moveSubtask(
            fromOffsets: IndexSet(integer: 2),
            toOffset: BoardStore.dropOffset(from: 2, to: 0),
            on: TestBoard.dragDrop
        )
        #expect(store[TestBoard.dragDrop]?.subtasks.map(\.id)
                == [TestBoard.keyboard, TestBoard.lift, TestBoard.dropTargets])
    }

    // MARK: The phone's column

    @Test func aBoardWithColumnsOfItsOwnOpensOnOneOfThem() {
        // `mobileColumnID` is session state — not saved — so every launch starts
        // at the property's default, which is a *seed* column's id. A board made
        // in the app carries ids of its own, so a store opened straight onto one
        // named a column that is on no board: every chip in the phone's strip
        // unlit, while the list and the add row showed the first column through
        // `mobileColumnIndex`'s `?? 0`. Switching boards and undoing already
        // reconciled; a launch is the third way onto a board.
        let store = TestBoard.store(boards: [TestBoard.support])
        #expect(store.mobileColumnID == TestBoard.queue.id)
        #expect(store.mobileColumn.id == store.mobileColumnID)
    }

    @Test func aBoardThatHasTheDefaultColumnOpensOnIt() {
        // The other half: the fallback is for an id that is *not there*, and a
        // board that has the default keeps it. Without this, moving every launch
        // to the first column would pass the test above and change where the
        // seed board opens.
        let store = TestBoard.store()
        #expect(store.mobileColumnID == BoardColumn.inProgress.id)
    }

    @Test func steppingBackFromTheFirstColumnWrapsToTheLast() {
        // Swift's `%` takes the sign of the dividend, so `(0 - 1) % 4` is -1 and
        // indexing `workflow` with it traps. Adding `count` before the modulo is
        // what makes a backward step arithmetic instead of a crash, and the
        // first column is the only place the difference shows.
        let store = TestBoard.store()
        store.mobileColumnID = BoardColumn.workflow[0].id
        store.stepMobileColumn(by: -1)
        #expect(store.mobileColumnID == BoardColumn.workflow.last?.id)

        store.stepMobileColumn(by: 1)
        #expect(store.mobileColumnID == BoardColumn.workflow[0].id)
    }

    @Test func steppingOnPastTheLastColumnWrapsToTheFirst() {
        let store = TestBoard.store()
        store.mobileColumnID = BoardColumn.done.id
        store.stepMobileColumn(by: 1)
        #expect(store.mobileColumnID == BoardColumn.workflow[0].id)
        #expect(store.mobileColumn.id == BoardColumn.workflow[0].id)
    }

    @Test func thePagerWalksTheWorkflowAndComesHome() {
        let store = TestBoard.store()
        store.mobileColumnID = BoardColumn.workflow[0].id
        var seen: [BoardColumn.ID] = [store.mobileColumnID]
        for _ in 1..<BoardColumn.workflow.count {
            store.stepMobileColumn(by: 1)
            seen.append(store.mobileColumnID)
        }
        #expect(seen == BoardColumn.workflow.map(\.id))
        store.stepMobileColumn(by: 1)
        #expect(store.mobileColumnID == BoardColumn.workflow[0].id)
        // Inbox is not in the pager, so a step out of it starts at the top.
        store.mobileColumnID = BoardColumn.inbox.id
        store.stepMobileColumn(by: -1)
        #expect(store.mobileColumnID == BoardColumn.workflow.last?.id)
    }

    // MARK: Labels, priority, due

    @Test func togglingALabelPutsItOnAndTakesItOff() {
        let store = TestBoard.store()
        store.toggleLabel("bug", on: TestBoard.cafe)
        #expect(store[TestBoard.cafe]?.labelKeys == ["polish", "bug"])
        #expect(kinds(store, TestBoard.cafe).first == .labelAdded(key: "bug", name: "Bug"))

        store.toggleLabel("bug", on: TestBoard.cafe)
        #expect(store[TestBoard.cafe]?.labelKeys == ["polish"])
        #expect(kinds(store, TestBoard.cafe).first == .labelRemoved(key: "bug", name: "Bug"))
    }

    @Test func settingThePriorityItAlreadyHasIsNotAnEvent() {
        let store = TestBoard.store()
        let before = store.tasks
        store.setPriority(.high, on: TestBoard.dragDrop)
        #expect(store.tasks == before)

        store.setPriority(.low, on: TestBoard.dragDrop)
        #expect(store[TestBoard.dragDrop]?.priority == .low)
        #expect(kinds(store, TestBoard.dragDrop).first == .prioritySet(.low))
    }

    @Test func theDueDateIsSetClearedAndLoggedEachWay() {
        let store = TestBoard.store()
        let day = CalendarDay(year: 2026, month: 12, day: 25)
        store.setDue(day, on: TestBoard.cafe)
        #expect(store[TestBoard.cafe]?.due == day)
        #expect(kinds(store, TestBoard.cafe).first == .dueSet(day))

        store.setDue(day, on: TestBoard.cafe)                 // the same day again
        #expect(kinds(store, TestBoard.cafe).count(where: isDueSet) == 1)

        store.setDue(nil, on: TestBoard.cafe)
        #expect(store[TestBoard.cafe]?.due == nil)
        #expect(kinds(store, TestBoard.cafe).first == .dueCleared)
    }

    // MARK: Timestamps and counts

    @Test func everyMutationBumpsUpdatedAt() throws {
        let store = TestBoard.store()
        let original = try #require(store[TestBoard.cafe]?.updatedAt)
        store.move(TestBoard.cafe, to: doing)
        let afterMove = try #require(store[TestBoard.cafe]?.updatedAt)
        #expect(afterMove > original)

        store.toggleLabel("bug", on: TestBoard.cafe)
        let afterLabel = try #require(store[TestBoard.cafe]?.updatedAt)
        #expect(afterLabel >= afterMove)

        store.addSubtask(to: TestBoard.cafe, text: "A step")
        #expect(try #require(store[TestBoard.cafe]?.updatedAt) >= afterLabel)

        store.setText("Renamed", field: .title, on: TestBoard.cafe)
        #expect(try #require(store[TestBoard.cafe]?.updatedAt) >= afterLabel)
    }

    @Test func countsFollowTheBoard() {
        let store = TestBoard.store()
        // The fixture's stamps sit a day either side of `TestBoard.epoch`, and
        // its due dates a year later, so the weekly meter is read from the epoch
        // and the due counts from the days the dues name.
        let epochDay = CalendarDay(TestBoard.epoch)
        #expect(store.totalCount == 6)
        #expect(store.weeklyShippedCount(today: epochDay) == 1)
        #expect(store.count(of: .today, today: TestBoard.dueDay) == 1)          // only NW-121 is due that day
        // Today carries overdue work: NW-123 is due, and NW-121 is eleven days past.
        #expect(store.count(of: .today, today: TestBoard.laterDay) == 2)
        #expect(store.count(of: .today, today: CalendarDay(year: 2030, month: 1, day: 1)) == 2)

        // A task in Done does not count as due today, however overdue it is.
        store.move(TestBoard.dragDrop, to: done)
        #expect(store.count(of: .today, today: TestBoard.dueDay) == 0)

        // Filing a card away takes it out of the board's counts. The weekly
        // meter is the one that keeps it, and `ArchiveTests` says why.
        store.archive(TestBoard.cafe)
        #expect(store.totalCount == 5)
    }
}
