import Foundation
import Testing
@testable import Simple_Kanban

/// One user action's worth of registrations, by name and in order.
///
/// `undoActionName` reports one name per group, so a bulk command that filed
/// three steps inside a single group is indistinguishable from one that filed
/// one: same last name, same board after ⌘Z, same empty stack. The *count* is
/// what tells them apart, which is why every assertion here is on the list
/// rather than on where the board landed.
@MainActor
private func registrations(_ undo: RecordingUndoManager, _ body: () -> Void) -> [String] {
    let before = undo.actionNames.count
    step(undo) { body() }
    return Array(undo.actionNames[before...])
}

/// Picking cards out: the range, the toggle, Select All and the anchor all three
/// of them measure from.
@MainActor
@Suite struct SelectionTests {
    // MARK: The selection follows the keyboard

    /// A plain click, and the mouse *down* half of it. Focus arrives on the
    /// pressed card before its `Button` fires, so the selection has to arrive
    /// with it or the two rings sit on two different cards for the length of
    /// the press — and for good, on a drag, which never fires that `Button`.
    @Test func focusArrivingOnACardTakesTheSelectionWithIt() {
        #expect(BoardKeyboard.selectionFollows(
            focusOnto: column[1], selection: [column[0]], held: .none
        ))
        // Nothing picked at all is the same answer: the card focus landed on.
        #expect(BoardKeyboard.selectionFollows(focusOnto: column[1], selection: [], held: .none))
    }

    /// ⌘ and ⇧ mean "as well as what is already picked". Collapsing onto the
    /// pressed card on mouse down would throw the rest away before the click
    /// meaning to add to it had been delivered.
    @Test func aHeldModifierLeavesTheSelectionForTheClickToSettle() {
        for held in [CardClick.extend, .range] {
            #expect(!BoardKeyboard.selectionFollows(
                focusOnto: column[1], selection: [column[0]], held: held
            ))
            #expect(!BoardKeyboard.selectionFollows(
                focusOnto: column[1], selection: [], held: held
            ))
        }
    }

    /// Reaching a card that is already picked — arrowing through a multi-
    /// selection, or picking one of them up to drag — is not a decision to drop
    /// the others.
    @Test func focusLandingInsideAMultiSelectionDoesNotCollapseIt() {
        let picked: Set<TaskItem.ID> = [column[0], column[1], column[2]]
        #expect(!BoardKeyboard.selectionFollows(focusOnto: column[1], selection: picked, held: .none))
        // And the card outside it still takes the lot.
        #expect(BoardKeyboard.selectionFollows(focusOnto: column[3], selection: picked, held: .none))
    }

    /// A column as a surface draws it — the order a ⇧-click means, which is
    /// neither the board array's nor a set's.
    private let column = [TestBoard.palette, TestBoard.cafe, TestBoard.dragDrop, TestBoard.offline]

    /// Both ends of the sweep are in it. Written as a downward sweep and a
    /// one-card sweep as well as the ordinary case: a half-open range looks
    /// right in the common direction and drops a card in the other.
    @Test func aRangeIncludesBothOfItsEnds() {
        let store = TestBoard.store()

        store.select(column[1])
        store.extendSelection(to: column[3], through: column)
        #expect(store.selection == [column[1], column[2], column[3]])

        // Downwards, over two adjacent cards.
        store.select(column[2])
        store.extendSelection(to: column[1], through: column)
        #expect(store.selection == [column[1], column[2]])

        // And onto the anchor itself, which is a range of one.
        store.select(column[2])
        store.extendSelection(to: column[2], through: column)
        #expect(store.selection == [column[2]])

        // The whole list, from either end.
        store.select(column[0])
        store.extendSelection(to: column[3], through: column)
        #expect(store.selection == Set(column))
    }

    /// A ⇧-click sweeps out from the card that was clicked outright, so a run of
    /// them grows and shrinks around that one card rather than ratcheting
    /// outwards from wherever the last one landed.
    @Test func aRunOfShiftClicksSweepsFromTheOneAnchor() {
        let store = TestBoard.store()
        store.select(column[2])
        store.extendSelection(to: column[3], through: column)
        store.extendSelection(to: column[1], through: column)
        #expect(store.selection == [column[1], column[2]])
        store.extendSelection(to: column[2], through: column)
        #expect(store.selection == [column[2]])
    }

    /// ⌘-click moves the anchor, because the card just clicked is the one a
    /// following ⇧-click means to measure from.
    @Test func aCommandClickMovesTheAnchorAndAPlainClickReplacesEverything() {
        let store = TestBoard.store()
        store.select(column[0])
        store.toggleSelection(of: column[2])
        #expect(store.selection == [column[0], column[2]])

        store.extendSelection(to: column[3], through: column)
        #expect(store.selection == [column[2], column[3]])

        store.select(column[1])
        #expect(store.selection == [column[1]])
    }

    /// And ⌘-clicking a card *out* of the selection has to take the anchor with
    /// it. Left behind, the anchor names a card that is no longer picked, and
    /// the next ⇧-click sweeps from somewhere the user has no way of seeing is
    /// the start of a range — the one failure of this control that looks like
    /// the app choosing cards at random.
    @Test func takingTheAnchorCardOutOfTheSelectionMovesTheAnchor() {
        let store = TestBoard.store()
        store.select(column[0])
        store.toggleSelection(of: column[2])     // the anchor is column[2] now
        store.toggleSelection(of: column[2])     // and it has just left the selection
        #expect(store.selection == [column[0]])

        // So the sweep runs from the one card still picked, not from the one
        // that was clicked last.
        store.extendSelection(to: column[3], through: column)
        #expect(store.selection == Set(column))
    }

    /// Clearing takes the anchor with it. Leaving it behind would have the next
    /// ⇧-click sweep from a card the user can no longer see is picked.
    @Test func clearingTakesTheAnchorWithIt() {
        let store = TestBoard.store()
        store.select(column[0])
        store.extendSelection(to: column[2], through: column)
        #expect(store.selectionCount == 3)

        store.clearSelection()
        #expect(store.selection.isEmpty)
        #expect(store.hasSelection == false)
        #expect(store.selectedID == nil)
        #expect(store.selectedTask == nil)

        // With nothing to measure from, a ⇧-click is a plain one.
        store.extendSelection(to: column[3], through: column)
        #expect(store.selection == [column[3]])
    }

    /// A ⇧-click whose anchor has left the list — the card was deleted, or the
    /// user has paged to another column — lands as a plain click rather than
    /// selecting some arbitrary run.
    @Test func aRangeMeasuredFromACardTheSurfaceIsNoLongerDrawingLandsAsAPlainClick() {
        let store = TestBoard.store()
        store.select(TestBoard.sync)                    // in a different column
        store.extendSelection(to: column[2], through: column)
        #expect(store.selection == [column[2]])
    }

    /// ⌘A takes what is on screen, and an archived card is not on screen: it is
    /// filed away, and a Delete aimed at the selection would take it with the
    /// rest.
    @Test func selectAllLeavesTheArchiveOutOfIt() {
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.palette: 100]))
        store.selectAllVisible(today: TestBoard.dueDay)
        #expect(store.isSelected(TestBoard.palette) == false)
        #expect(store.selection == [TestBoard.dragDrop, TestBoard.cafe,
                                    TestBoard.offline, TestBoard.sync])
    }

    /// ⌘A leaves the anchor on the first row, so the ⇧-click after it sweeps
    /// from the top of the surface rather than from an arbitrary member of a set.
    @Test func selectAllLeavesTheAnchorOnTheFirstRow() {
        let store = TestBoard.store()
        let visible = store.visibleTaskIDs(today: TestBoard.dueDay)
        store.selectAllVisible(today: TestBoard.dueDay)
        #expect(store.selection == Set(visible))

        store.extendSelection(to: visible[2], through: visible)
        #expect(store.selection == Set(visible[0...2]))
    }

    /// The rule every multi-select list follows: a command aimed at a card
    /// inside the selection means the selection, and one aimed at a card
    /// outside it means that card — never both, and never the selection
    /// somewhere else on the board.
    @Test func aCommandAimedOutsideTheSelectionActsOnThatCardAlone() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        store.toggleSelection(of: TestBoard.dragDrop)
        #expect(store.commandTargets(TestBoard.dragDrop) == [TestBoard.cafe, TestBoard.dragDrop])
        #expect(store.commandTargets(TestBoard.sync) == [TestBoard.sync])

        store.clearSelection()
        #expect(store.commandTargets(TestBoard.sync) == [TestBoard.sync])
    }

    /// `selectedTasks` is what a bulk command walks, and it walks it in board
    /// order — a set has no order to offer, and cards moved together should
    /// arrive in the order they were in.
    @Test func theSelectedTasksComeBackInBoardOrder() {
        let store = TestBoard.store()
        store.selectAll([TestBoard.palette, TestBoard.dragDrop, TestBoard.sync])
        #expect(store.selectedTasks.map(\.id) == [TestBoard.dragDrop, TestBoard.sync, TestBoard.palette])
    }
}

/// Multi-select's whole point: several cards changed as **one** ⌘Z.
@MainActor
@Suite struct BulkCommandTests {
    private let doing = BoardColumn.inProgress.id

    /// The ids whose card is not exactly what it was: what a command *did*, as
    /// against what it was aimed at.
    private func changed(_ before: [TaskItem], _ after: [TaskItem]) -> [TaskItem.ID] {
        after.filter { task in before.first { $0.id == task.id } != task }.map(\.id)
    }

    /// Every bulk command acts in board order, and a move is where that order
    /// becomes visible: the cards arrive in the order the board had them, not
    /// the order the `Set` handed them over in.
    ///
    /// Four cards rather than two on purpose. `Set` iteration is seeded per
    /// process, so a two-card assertion passes about half the time against an
    /// order-blind `ordered(_:)`: a coin toss dressed as a test, green on three
    /// runs in five. Four cards leave one arrangement in twenty-four, and every
    /// position is pinned rather than the ends — a rotation would satisfy
    /// "first is first, last is last".
    @Test func aBulkMoveArrivesInTheOrderTheBoardHadThem() {
        let (store, undo) = TestBoard.undoing()
        // The order they are in now, which is the order they should arrive in.
        #expect(store.tasks.map(\.id) == [TestBoard.widget, TestBoard.dragDrop, TestBoard.cafe,
                                          TestBoard.offline, TestBoard.sync, TestBoard.palette])
        let group: Set<TaskItem.ID> = [TestBoard.palette, TestBoard.offline,
                                       TestBoard.cafe, TestBoard.dragDrop]

        let filed = registrations(undo) { store.move(group, to: doing) }
        #expect(filed == ["Move Tasks"])
        #expect(store.visibleTasks(in: doing).map(\.id)
                == [TestBoard.sync, TestBoard.dragDrop, TestBoard.cafe,
                    TestBoard.offline, TestBoard.palette])
    }

    /// Three cards deleted, one step filed — and the ⌘Z puts all three back
    /// where they were, not on the end of the array.
    ///
    /// The three are at indices 1, 3 and 5 of six, so an undo that appended the
    /// restored cards, or restored them in the order they were removed, lands
    /// on a different board than the one it started from.
    @Test func deletingThreeCardsIsOneStepAndUndoesToTheirOwnIndices() {
        let (store, undo) = TestBoard.undoing()
        let before = store.tasks
        let doomed: Set<TaskItem.ID> = [TestBoard.dragDrop, TestBoard.offline, TestBoard.palette]

        let filed = registrations(undo) { store.deleteTasks(doomed) }
        #expect(filed == ["Delete Tasks"])
        #expect(store.tasks.map(\.id) == [TestBoard.widget, TestBoard.cafe, TestBoard.sync])

        undo.undo()
        #expect(store.tasks == before)
        #expect(store.tasks.firstIndex { $0.id == TestBoard.dragDrop } == 1)
        #expect(store.tasks.firstIndex { $0.id == TestBoard.offline } == 3)
        #expect(store.tasks.firstIndex { $0.id == TestBoard.palette } == 5)
        // One press, not three: the stack is empty afterwards.
        #expect(undo.canUndo == false)
    }

    /// Every bulk command, asked the same question. One registration each —
    /// the nested single-card mutation collapses into the outer step, and a
    /// build where it does not files one ⌘Z per card.
    @Test func everyBulkCommandFilesExactlyOneStep() {
        let pair: Set<TaskItem.ID> = [TestBoard.cafe, TestBoard.offline]

        func filings(_ body: @escaping (BoardStore) -> Void) -> [String] {
            let (store, undo) = TestBoard.undoing()
            return registrations(undo) { body(store) }
        }

        #expect(filings { $0.move(pair, to: self.doing) } == ["Move Tasks"])
        #expect(filings { $0.move(pair, to: .inbox) } == ["Move to Inbox"])
        #expect(filings { $0.complete(pair) } == ["Complete Tasks"])
        #expect(filings { $0.archive(pair) } == ["Archive Tasks"])
        #expect(filings { $0.deleteTasks(pair) } == ["Delete Tasks"])
        #expect(filings { $0.toggleLabel("design", on: pair) } == ["Add Label"])
        #expect(filings { $0.setPriority(.high, on: pair) } == ["Set Priority"])
        #expect(filings { $0.setDue(TestBoard.laterDay, on: pair) } == ["Set Due Date"])
        #expect(filings { $0.setDue(nil, on: [TestBoard.dragDrop, TestBoard.offline]) } == ["Clear Due Date"])
    }

    /// Six cards is not six steps either — the count of registrations does not
    /// grow with the size of the selection.
    @Test func theStepCountDoesNotGrowWithTheSelection() {
        let (store, undo) = TestBoard.undoing()
        store.selectAll(store.tasks.map(\.id))
        #expect(store.selectionCount == 6)

        let filed = registrations(undo) { store.setPriority(.low, on: store.selection) }
        #expect(filed == ["Set Priority"])
        #expect(store.tasks.allSatisfy { $0.priority == .low })

        undo.undo()
        #expect(store[TestBoard.sync]?.priority == .high)
        #expect(store[TestBoard.cafe]?.priority == .low)
        #expect(undo.canUndo == false)
    }

    /// Undo lands the whole selection back at once, including the columns each
    /// card came from — which differ, so a restore that put them all in one
    /// place would show.
    @Test func undoingABulkMoveReturnsEachCardToItsOwnColumn() {
        let (store, undo) = TestBoard.undoing()
        let group: Set<TaskItem.ID> = [TestBoard.dragDrop, TestBoard.offline, TestBoard.palette]

        let filed = registrations(undo) { store.move(group, to: doing) }
        #expect(filed == ["Move Tasks"])
        // Behind the card already there, in the order the board had them.
        #expect(store.visibleTasks(in: doing).map(\.id)
                == [TestBoard.sync, TestBoard.dragDrop, TestBoard.offline, TestBoard.palette])

        undo.undo()
        #expect(store[TestBoard.dragDrop]?.columnID == BoardColumn.backlog.id)
        #expect(store[TestBoard.offline]?.columnID == BoardColumn.upNext.id)
        #expect(store[TestBoard.palette]?.columnID == BoardColumn.done.id)
        #expect(undo.canUndo == false)
    }

    /// Nothing selected, nothing to do, nothing on the Edit menu. A command
    /// that quietly registers an empty step leaves the user pressing ⌘Z to no
    /// effect, which reads as a broken undo rather than as a no-op.
    @Test func everyBulkCommandOnAnEmptySelectionDoesNothingAndRegistersNothing() {
        let (store, undo) = TestBoard.undoing()
        let before = store.tasks
        let none: Set<TaskItem.ID> = []

        let filed = registrations(undo) {
            store.move(none, to: doing)
            store.move(none, to: .inbox)
            store.complete(none)
            store.archive(none)
            store.deleteTasks(none)
            store.toggleLabel("design", on: none)
            store.setPriority(.low, on: none)
            store.setDue(TestBoard.laterDay, on: none)
        }
        #expect(filed.isEmpty)
        #expect(undo.undoActionName == "")
        #expect(store.tasks == before)
    }

    /// The same for a selection of cards that no longer exist — a menu aimed at
    /// a stale selection is the shape this arrives in.
    @Test func aBulkCommandAimedAtCardsThatAreGoneRegistersNothing() {
        let (store, undo) = TestBoard.undoing()
        let ghosts: Set<TaskItem.ID> = [TestBoard.taskID(200), TestBoard.taskID(201)]
        let before = store.tasks

        let filed = registrations(undo) {
            store.deleteTasks(ghosts)
            store.complete(ghosts)
            store.archive(ghosts)
            store.setPriority(.low, on: ghosts)
        }
        #expect(filed.isEmpty)
        #expect(store.tasks == before)
    }

    /// And for a selection where the command has nothing left to change: the
    /// cards already say what it would set. Same rule as a drop on the column a
    /// card is already in.
    @Test func aBulkCommandWithNothingLeftToChangeRegistersNothing() {
        let (store, undo) = TestBoard.undoing()
        // Both already high.
        let high: Set<TaskItem.ID> = [TestBoard.dragDrop, TestBoard.sync]
        #expect(registrations(undo) { store.setPriority(.high, on: high) }.isEmpty)

        // Already in Done.
        #expect(registrations(undo) { store.complete([TestBoard.palette]) }.isEmpty)

        // Already filed away.
        let (filed, filedUndo) = TestBoard.undoing(tasks: TestBoard.tasks(archiving: [TestBoard.palette: 100]))
        #expect(registrations(filedUndo) { filed.archive([TestBoard.palette]) }.isEmpty)
    }

    /// The everyday shape after ⌘A: a selection the command applies to *some*
    /// of. Nothing above asks this — the suite has selections where everything
    /// applies and selections where nothing does, and the middle is where the
    /// filters actually earn their keep.
    ///
    /// Two claims, because dropping either half of `canComplete` passes the
    /// other. The step is named for what changed rather than for what was
    /// aimed at — a menu that says "Complete 3 Tasks" and files one ⌘Z called
    /// "Complete Task" has lied about what it was going to do — and the cards
    /// the command cannot touch come out of it untouched, not merely
    /// unmoved: an already-complete card sent to Done again would be resorted
    /// to the bottom of it and restamped.
    @Test func completingAPartlyApplicableSelectionActsOnItsApplicableHalfAlone() {
        let (store, undo) = TestBoard.undoing(tasks: TestBoard.tasks(archiving: [TestBoard.cafe: 300]))
        // Three cards, three answers: one to complete, one already in Done, one
        // filed away — where the verb is Restore and only Restore.
        let mixed: Set<TaskItem.ID> = [TestBoard.dragDrop, TestBoard.palette, TestBoard.cafe]
        store.selectAll(store.tasks.filter { mixed.contains($0.id) }.map(\.id))
        #expect(store.selectionCount == 3)
        #expect(store.completeTargets(mixed) == [TestBoard.dragDrop])

        let before = store.tasks
        let filed = registrations(undo) { store.complete(store.selection) }
        #expect(filed == ["Complete Task"], "one card changed and the step said three")
        #expect(changed(before, store.tasks) == [TestBoard.dragDrop])
        #expect(store[TestBoard.dragDrop]?.columnID == BoardColumn.done.id)
        // The one already there kept its place at the head of Done.
        #expect(store.visibleTasks(in: BoardColumn.done.id).map(\.id)
                == [TestBoard.palette, TestBoard.dragDrop])
    }

    /// The archive half of the same claim. The card already filed keeps the
    /// instant it was filed on, so a bulk archive that swept it up again would
    /// show as a restamp rather than as nothing at all.
    @Test func archivingAPartlyApplicableSelectionActsOnItsApplicableHalfAlone() {
        let (store, undo) = TestBoard.undoing(tasks: TestBoard.tasks(archiving: [TestBoard.palette: 300]))
        let mixed: Set<TaskItem.ID> = [TestBoard.dragDrop, TestBoard.palette]
        store.selectAll([TestBoard.dragDrop, TestBoard.palette])
        #expect(store.archiveTargets(mixed) == [TestBoard.dragDrop])

        let before = store.tasks
        let filed = registrations(undo) { store.archive(store.selection) }
        #expect(filed == ["Archive Task"])
        #expect(changed(before, store.tasks) == [TestBoard.dragDrop])
        #expect(store[TestBoard.palette]?.archivedAt == TestBoard.at(300))
    }

    /// And the menu item titles itself from the same two calls, so what it
    /// promises and what it does are one number rather than two.
    @Test func theMenuItemIsTitledFromWhatTheCommandWillActuallyChange() {
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.cafe: 300]))
        store.selectAll([TestBoard.dragDrop, TestBoard.offline, TestBoard.palette, TestBoard.cafe])
        #expect(store.selectionCount == 4)

        #expect(store.completableCount == 2)
        #expect(AppCommand.completeTask.title(selectionCount: store.completableCount)
                == "Complete 2 Tasks")
        #expect(store.archivableCount == 3)
        #expect(AppCommand.archiveTask.title(selectionCount: store.archivableCount)
                == "Archive 3 Tasks")

        // Nothing to complete is a count of nought, which is what an item that
        // must disable rather than no-op silently needs to be able to read.
        store.selectAll([TestBoard.palette])
        #expect(store.hasSelection)
        #expect(store.completableCount == 0)
    }

    /// A label goes on until every card has it, and only then comes off, so the
    /// second press undoes the first. Toggling each card on its own would leave
    /// a mixed selection exactly as mixed as it started, the other way round.
    @Test func aLabelOnAMixedSelectionGoesOnBeforeItComesOff() {
        let (store, undo) = TestBoard.undoing()
        // dragDrop carries "design"; cafe does not.
        let mixed: Set<TaskItem.ID> = [TestBoard.dragDrop, TestBoard.cafe]

        #expect(registrations(undo) { store.toggleLabel("design", on: mixed) } == ["Add Label"])
        #expect(store[TestBoard.cafe]?.labelKeys.contains("design") == true)
        // And the card that already had it is not given it twice.
        #expect(store[TestBoard.dragDrop]?.labelKeys.filter { $0 == "design" }.count == 1)

        #expect(registrations(undo) { store.toggleLabel("design", on: mixed) } == ["Remove Label"])
        #expect(store[TestBoard.cafe]?.labelKeys.contains("design") == false)
        #expect(store[TestBoard.dragDrop]?.labelKeys.contains("design") == false)

        undo.undo()
        #expect(store[TestBoard.dragDrop]?.labelKeys.contains("design") == true)
        #expect(store[TestBoard.cafe]?.labelKeys.contains("design") == true)
    }

    /// Deleting part of a selection leaves the rest of it selected: a user who
    /// picked four cards and deleted one still means the other three.
    @Test func deletingPartOfASelectionLeavesTheRestSelected() {
        let store = TestBoard.store()
        store.selectAll([TestBoard.dragDrop, TestBoard.cafe, TestBoard.offline])

        store.deleteTasks([TestBoard.cafe])
        #expect(store.selection == [TestBoard.dragDrop, TestBoard.offline])

        store.deleteTasks([TestBoard.offline])
        #expect(store.selection == [TestBoard.dragDrop])

        // Only once it has run out does it fall to a neighbour — and Backlog is
        // empty now, so it falls exactly where a single delete would leave it.
        store.deleteTasks([TestBoard.dragDrop])
        #expect(store.selection.isEmpty)
    }

    /// Archiving a selection files it on one instant, so the Archive's
    /// newest-first order then falls back on the order the board had them in
    /// rather than on how long each `Date.now` took to read.
    @Test func archivingASelectionStampsThemAllTheSame() {
        let (store, undo) = TestBoard.undoing()
        let group: Set<TaskItem.ID> = [TestBoard.dragDrop, TestBoard.cafe, TestBoard.offline]

        #expect(registrations(undo) { store.archive(group) } == ["Archive Tasks"])
        let stamps = Set(group.compactMap { store[$0]?.archivedAt })
        #expect(stamps.count == 1)

        undo.undo()
        #expect(group.allSatisfy { store[$0]?.isArchived == false })
        #expect(undo.canUndo == false)
    }
}

/// The defect `endSessions(in:awayFrom:)` exists to prevent, asked of the set.
///
/// A surface that has moved to another task cannot end the editing sessions it
/// left open on the old one, and a session nobody ends silences that task's
/// logging for good — the rename never reaches the activity feed, and the
/// keystrokes belong to no undo step. The selection's `didSet` is what closes
/// them, so every way of changing the selection has to go through it.
@MainActor
@Suite struct SelectionSessionTests {
    private let column = [TestBoard.palette, TestBoard.cafe, TestBoard.dragDrop, TestBoard.offline]

    /// Renames `cafe` with a session open on it, as the inspector does.
    private func typing(into store: BoardStore) {
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("Renamed with the panel on it", field: .title, on: TestBoard.cafe)
    }

    private func sessionClosed(_ store: BoardStore) -> Bool {
        store.isEditing(.title, on: TestBoard.cafe, scope: .desk) == false
            && store[TestBoard.cafe]?.title == "Renamed with the panel on it"
            && store[TestBoard.cafe]?.activity.contains { $0.kind == .renamed } == true
    }

    @Test func aPlainClickOnAnotherCardEndsTheSession() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        typing(into: store)
        store.select(TestBoard.dragDrop)
        #expect(sessionClosed(store))
    }

    /// The case the set introduced: the card the inspector was on **stays
    /// selected** while another joins it. The panel still leaves — it shows one
    /// task or none — so the session has to end even though nothing was
    /// deselected.
    @Test func aCardKeepsNoSessionWhileOthersAreAddedAndRemovedAroundIt() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        typing(into: store)

        store.toggleSelection(of: TestBoard.dragDrop)
        #expect(store.isSelected(TestBoard.cafe))
        #expect(store.selectedID == nil)
        #expect(sessionClosed(store))

        // Taking the other card back out leaves `cafe` alone again, and does
        // not resurrect the session or log the rename a second time.
        store.toggleSelection(of: TestBoard.dragDrop)
        #expect(store.selectedID == TestBoard.cafe)
        #expect(store.isEditing(.title, on: TestBoard.cafe, scope: .desk) == false)
        #expect(store[TestBoard.cafe]?.activity.filter { $0.kind == .renamed }.count == 1)
    }

    @Test func extendingARangeOverTheEditedCardEndsItsSession() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        typing(into: store)
        store.extendSelection(to: TestBoard.offline, through: column)
        #expect(store.isSelected(TestBoard.cafe))
        #expect(sessionClosed(store))
    }

    @Test func selectAllEndsTheSession() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        typing(into: store)
        store.selectAllVisible(today: TestBoard.dueDay)
        #expect(sessionClosed(store))
    }

    /// ⎋ deselects, which is also the panel leaving.
    @Test func clearingTheSelectionEndsTheSession() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        typing(into: store)
        store.clearSelection()
        #expect(sessionClosed(store))
    }

    /// A view re-asserting the selection it already has must not interrupt
    /// typing: the session survives an assignment that changes nothing.
    @Test func reAssertingTheSameSelectionLeavesTheSessionAlone() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        typing(into: store)

        store.selectedID = TestBoard.cafe
        store.select(TestBoard.cafe)
        #expect(store.isEditing(.title, on: TestBoard.cafe, scope: .desk))
        #expect(store[TestBoard.cafe]?.activity.contains { $0.kind == .renamed } == false)
    }

    /// Sessions are keyed by surface, and only the desk's move off the card.
    /// The sheet is a second detail surface that can be up at the same time —
    /// on iPad, from Phase E onwards — and ending its session from the board's
    /// selection would file its half-typed text as somebody else's edit.
    @Test func theSheetsSessionOnTheSameCardSurvivesTheBoardsSelectionMoving() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        store.sheetID = TestBoard.cafe
        store.beginEditing(.note, on: TestBoard.cafe, scope: .sheet)
        store.setText("Typed on the sheet", field: .note, on: TestBoard.cafe)

        store.toggleSelection(of: TestBoard.dragDrop)
        #expect(store.isEditing(.note, on: TestBoard.cafe, scope: .sheet))
        #expect(store[TestBoard.cafe]?.activity.contains { $0.kind == .descriptionAdded } == false)
    }

    /// The session that ends files its own step, and it files it *outside* the
    /// selection change — so the typing is one ⌘Z, recoverable on its own.
    @Test func theEndedSessionFilesTheTypingAsAStepOfItsOwn() {
        let (store, undo) = TestBoard.undoing()
        store.select(TestBoard.cafe)
        typing(into: store)

        let filed = registrations(undo) { store.toggleSelection(of: TestBoard.dragDrop) }
        #expect(filed == ["Edit Title"])

        undo.undo()
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
        #expect(store[TestBoard.cafe]?.activity.contains { $0.kind == .renamed } == false)
    }
}

/// The store's half of the two commands that have to put a surface up before
/// they can do anything — ⌘N and ⌘F. Both used to live on toolbar buttons,
/// where the surface was already on screen by definition.
@MainActor
@Suite struct CommandSurfaceTests {
    /// Item 1.9: ⌘N used to open the composer on the Inbox, which is leftmost
    /// on a horizontally scrolling board — so on a board scrolled right it
    /// focused a text field nobody could see.
    @Test func newTaskOpensTheComposerOnTheSurfaceTheUserIsLookingAt() {
        let store = TestBoard.store()
        store.selectSurface(.board)
        store.beginAddingWhereVisible()
        #expect(store.surface == .board)
        #expect(store.addingColumnID == store.activeBoard?.landingColumn?.id)
        #expect(store.addingColumnID != nil)
        #expect(store.draft.isEmpty)

        // The Inbox panel being out does not change where ⌘N lands: the panel
        // stands beside the board rather than instead of it, and the board is
        // still what the user is working on. Its own "+" is how you capture
        // into it.
        store.cancelDraft()
        store.toggleInbox()
        store.beginAddingWhereVisible()
        #expect(store.surface == .board)
        #expect(store.addingColumnID == store.activeBoard?.landingColumn?.id)
    }

    /// A saved view has no composer on it, so ⌘N there has to put the board
    /// back up rather than open a field on a surface that cannot draw one.
    @Test func newTaskFromASavedViewReturnsToTheBoard() {
        let store = TestBoard.store()
        store.selectSurface(.view(.today))
        store.beginAddingWhereVisible()
        #expect(store.surface == .board)
        #expect(store.addingColumnID == store.activeBoard?.landingColumn?.id)
    }

    /// With every board deleted there is nowhere on a board to land, and the
    /// Inbox is still there — so the panel that draws it has to come out, or
    /// ⌘N focuses a field nobody can see.
    @Test func newTaskWithNoBoardLeftFallsToTheInbox() {
        let store = TestBoard.store(boards: [])
        store.selectSurface(.board)
        store.beginAddingWhereVisible()
        #expect(store.addingPlacement == .inbox)
        #expect(store.isInboxShowing, "the composer opened on a panel that is not out")
    }

    /// ⌘F travels as a counter rather than a flag: with the field already
    /// focused a flag is already true, so the second press would be no change
    /// at all and the toolbar would never hear about it.
    @Test func findBumpsATokenEveryTimeItIsPressed() {
        let store = TestBoard.store()
        let start = store.searchFocusToken
        store.focusSearch()
        store.focusSearch()
        #expect(store.searchFocusToken == start &+ 2)
    }

    /// Neither is board data: they change nothing a ⌘Z could take back, and
    /// nothing that belongs in the file.
    @Test func theSessionCommandsRegisterNothing() {
        let (store, undo) = TestBoard.undoing()
        let before = store.tasks
        let filed = registrations(undo) {
            store.focusSearch()
            store.isShowingShortcuts = true
            store.beginAddingWhereVisible()
        }
        #expect(filed.isEmpty)
        #expect(store.tasks == before)
    }
}
