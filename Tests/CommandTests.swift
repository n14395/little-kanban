import Foundation
import Testing
@testable import Simple_Kanban

/// The selection as a set, and the bulk commands it exists for.
@MainActor
@Suite struct MultiSelectTests {
    private let doing = BoardColumn.inProgress.id

    @Test func selectedIDIsTheOneSelectionAndNothingAtAllForSeveral() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        #expect(store.selectedID == TestBoard.cafe)
        #expect(store.selectedTask?.id == TestBoard.cafe)

        store.toggleSelection(of: TestBoard.dragDrop)
        #expect(store.selection == [TestBoard.cafe, TestBoard.dragDrop])
        // Which is what keeps the inspector working unchanged: it shows a task
        // when exactly one is picked and its empty state otherwise.
        #expect(store.selectedID == nil)
        #expect(store.selectedTask == nil)

        store.toggleSelection(of: TestBoard.dragDrop)
        #expect(store.selectedID == TestBoard.cafe)
    }

    /// The defect `endSessions(in:awayFrom:)` exists to prevent, asked of the
    /// set: the inspector cannot end a session on a card it has moved off, and
    /// a session nobody ends silences that card's picker logging for good.
    @Test func pickingASecondCardEndsTheSessionTheInspectorLeftOnTheFirst() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("Renamed while the panel was on it", field: .title, on: TestBoard.cafe)

        store.toggleSelection(of: TestBoard.dragDrop)
        #expect(store.isEditing(.title, on: TestBoard.cafe, scope: .desk) == false)
        #expect(store[TestBoard.cafe]?.activity.contains { $0.kind == .renamed } == true)
    }

    @Test func aRangeCoversTheOrderTheSurfaceIsDrawing() {
        let store = TestBoard.store()
        // A column's rows, not the board's array: the range a user means is the
        // one they can see.
        let column = [TestBoard.palette, TestBoard.cafe, TestBoard.dragDrop, TestBoard.offline]
        store.select(TestBoard.cafe)
        store.extendSelection(to: TestBoard.offline, through: column)
        #expect(store.selection == [TestBoard.cafe, TestBoard.dragDrop, TestBoard.offline])

        // The anchor stays where it was put, so a second ⇧-click sweeps from
        // the same card rather than growing from the last one.
        store.extendSelection(to: TestBoard.palette, through: column)
        #expect(store.selection == [TestBoard.palette, TestBoard.cafe])
    }

    @Test func aRangeWithNothingToMeasureFromLandsAsAPlainClick() {
        let store = TestBoard.store()
        store.clearSelection()
        store.extendSelection(to: TestBoard.sync, through: store.tasks.map(\.id))
        #expect(store.selection == [TestBoard.sync])
    }

    @Test func selectAllTakesWhatTheSurfaceIsShowing() {
        let store = TestBoard.store()
        store.selectAllVisible(today: TestBoard.dueDay)
        // The Inbox card is on no board, and the board is what is on screen.
        #expect(store.selection == [TestBoard.dragDrop, TestBoard.cafe, TestBoard.offline,
                                    TestBoard.sync, TestBoard.palette])

        // With the panel out the Inbox is *beside* the board rather than
        // instead of it, so ⌘A means both — a Select All that skipped cards the
        // user can see would be lying about what it selected.
        store.toggleInbox()
        store.selectAllVisible(today: TestBoard.dueDay)
        #expect(store.selection == [TestBoard.widget, TestBoard.dragDrop, TestBoard.cafe,
                                    TestBoard.offline, TestBoard.sync, TestBoard.palette])

        // And a query does not narrow it. It used to — the board was drawn
        // from the search's answer, so ⌘A took what was left of it — but the
        // search is a panel over the board now and the board underneath is
        // still every card. "What the surface is showing" is unchanged by
        // typing.
        store.toggleInbox()
        store.query = "café"
        store.selectAllVisible(today: TestBoard.dueDay)
        #expect(store.selection == [TestBoard.dragDrop, TestBoard.cafe,
                                    TestBoard.offline, TestBoard.sync, TestBoard.palette])
    }

    @Test func aCommandAimedAtACardOutsideTheSelectionActsOnThatCardAlone() {
        let store = TestBoard.store()
        store.select(TestBoard.cafe)
        store.toggleSelection(of: TestBoard.dragDrop)
        #expect(store.commandTargets(TestBoard.cafe) == store.selection)
        #expect(store.commandTargets(TestBoard.sync) == [TestBoard.sync])
    }

    @Test func deletingPartOfASelectionLeavesTheRestOfItSelected() {
        let store = TestBoard.store()
        store.select(TestBoard.dragDrop)
        store.toggleSelection(of: TestBoard.cafe)

        store.deleteTasks([TestBoard.cafe])
        #expect(store.selection == [TestBoard.dragDrop])

        // Backlog is empty now, so it falls exactly where a single delete would
        // have left it.
        store.deleteTasks([TestBoard.dragDrop])
        #expect(store.selection.isEmpty)
    }

    @Test func deletingSeveralCardsIsOneStep() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.deleteTasks([TestBoard.cafe, TestBoard.offline]) }
        #expect(store[TestBoard.cafe] == nil)
        #expect(store[TestBoard.offline] == nil)
        #expect(undo.undoActionName == "Delete Tasks")

        undo.undo()
        #expect(store[TestBoard.cafe] != nil)
        #expect(store[TestBoard.offline] != nil)
        #expect(undo.canUndo == false)
    }

    @Test func movingSeveralCardsIsOneStepAndKeepsTheOrderTheyWereIn() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.move([TestBoard.palette, TestBoard.cafe], to: doing) }
        // Sync was already there; the pair arrive behind it in board order.
        #expect(store.visibleTasks(in: doing).map(\.id) == [TestBoard.sync, TestBoard.cafe, TestBoard.palette])
        #expect(undo.undoActionName == "Move Tasks")

        undo.undo()
        #expect(store.visibleTasks(in: doing).map(\.id) == [TestBoard.sync])
        #expect(undo.canUndo == false)
    }

    @Test func completingSeveralCardsIsOneStep() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.complete([TestBoard.cafe, TestBoard.offline]) }
        #expect(store[TestBoard.cafe]?.columnID == BoardColumn.done.id)
        #expect(store[TestBoard.offline]?.columnID == BoardColumn.done.id)
        #expect(undo.undoActionName == "Complete Tasks")

        undo.undo()
        #expect(store[TestBoard.cafe]?.columnID == BoardColumn.backlog.id)
        #expect(store[TestBoard.offline]?.columnID == BoardColumn.upNext.id)
        #expect(undo.canUndo == false)
    }

    @Test func archivingSeveralCardsFilesThemOnOneInstantAndOneStep() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.archive([TestBoard.palette, TestBoard.cafe]) }
        #expect(store[TestBoard.palette]?.archivedAt == store[TestBoard.cafe]?.archivedAt)
        #expect(undo.undoActionName == "Archive Tasks")

        undo.undo()
        #expect(store[TestBoard.palette]?.isArchived == false)
        #expect(store[TestBoard.cafe]?.isArchived == false)
    }

    /// A label the whole selection already carries comes off; anything else
    /// goes on. Toggling each card on its own would leave a mixed selection as
    /// mixed as it started, only the other way round.
    @Test func labellingSeveralCardsGoesOnUntilAllOfThemHaveIt() {
        let (store, undo) = TestBoard.undoing()
        // dragDrop already carries "design"; cafe does not.
        let mixed: Set<TaskItem.ID> = [TestBoard.dragDrop, TestBoard.cafe]

        step(undo) { store.toggleLabel("design", on: mixed) }
        #expect(store[TestBoard.cafe]?.labelKeys.contains("design") == true)
        #expect(store[TestBoard.dragDrop]?.labelKeys.filter { $0 == "design" }.count == 1)
        #expect(undo.undoActionName == "Add Label")

        step(undo) { store.toggleLabel("design", on: mixed) }
        #expect(store[TestBoard.cafe]?.labelKeys.contains("design") == false)
        #expect(store[TestBoard.dragDrop]?.labelKeys.contains("design") == false)
        #expect(undo.undoActionName == "Remove Label")
    }

    @Test func aPriorityOrADueDateSetOnSeveralCardsIsOneStep() {
        let (store, undo) = TestBoard.undoing()
        let pair: Set<TaskItem.ID> = [TestBoard.cafe, TestBoard.sync]

        step(undo) { store.setPriority(.low, on: pair) }
        #expect(store[TestBoard.sync]?.priority == .low)
        #expect(undo.undoActionName == "Set Priority")
        undo.undo()
        #expect(store[TestBoard.sync]?.priority == .high)

        step(undo) { store.setDue(TestBoard.laterDay, on: pair) }
        #expect(store[TestBoard.cafe]?.due == TestBoard.laterDay)
        #expect(store[TestBoard.sync]?.due == TestBoard.laterDay)
        #expect(undo.undoActionName == "Set Due Date")
        undo.undo()
        #expect(store[TestBoard.cafe]?.due == nil)
    }

    /// A bulk command that would change nothing registers nothing, the same way
    /// a drop on the card's own column does.
    @Test func aBulkCommandWithNothingToDoStaysOffTheEditMenu() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.setPriority(.high, on: [TestBoard.dragDrop, TestBoard.sync]) }
        #expect(undo.undoActionName == "")
        step(undo) { store.deleteTasks([]) }
        #expect(undo.undoActionName == "")
    }
}

/// The one shortcut vocabulary. The menu bar, the board's key handlers and the
/// shortcuts sheet all read this, so what it says has to be internally
/// consistent — a sheet claiming a key the menu does not have is worse than no
/// sheet at all.
@Suite struct AppCommandTests {
    @Test func everyCommandNamesItselfAndBelongsSomewhere() {
        for command in AppCommand.allCases {
            #expect(!command.title.isEmpty, "\(command.rawValue) has no title")
            #expect(AppCommand.commands(in: command.group).contains(command))
        }
        #expect(AppCommand.groups == AppCommandGroup.allCases)
    }

    /// One window, one set of keys: two commands claiming the same press means
    /// one of them silently never fires.
    @Test func noTwoCommandsClaimTheSamePress() {
        var owner: [AppShortcut: AppCommand] = [:]
        for command in AppCommand.allCases {
            for shortcut in command.shortcuts {
                #expect(owner[shortcut] == nil,
                        "\(command.rawValue) and \(owner[shortcut]?.rawValue ?? "") both claim \(shortcut.display)")
                owner[shortcut] = command
            }
        }
    }

    /// Item 1.9, settled: ⌘N used to sit on a toolbar button while the default
    /// File menu still advertised it as New Window.
    @Test func theNewKeysSayWhatTheMenuSays() {
        #expect(AppCommand.newTask.shortcuts.first?.display == "⌘N")
        #expect(AppCommand.newBoard.shortcuts.first?.display == "⇧⌘N")
        #expect(AppCommand.newTask.group == .file)
        #expect(AppCommand.newBoard.group == .file)
    }

    /// `UndoManager` already puts Undo and Redo on the Edit menu. Declaring
    /// them again would put two of each there.
    @Test func theSystemsOwnCommandsAreListedButNotDeclared() {
        #expect(AppCommand.undo.source == .system)
        #expect(AppCommand.undo.isMenuItem == false)
        #expect(AppCommand.redo.isMenuItem == false)
        // Still in the sheet, because a user pressing ⌘Z wants to find it there.
        #expect(AppCommand.commands(in: .edit).contains(.undo))
    }

    /// ⌘C and ⌘A on the Edit menu take those keys away from every text field in
    /// the app, so the board handles them where it has focus and the menu says
    /// nothing about them.
    @Test func theBoardsOwnKeysGetNoMenuItem() {
        for command in AppCommand.commands(in: .board) {
            #expect(command.isMenuItem == false, "\(command.rawValue) would shadow a text field")
        }
        #expect(AppCommandGroup.board.hasMenu == false)
    }

    @Test func aCommandThatActsOnATaskDisablesWithNothingSelected() {
        #expect(AppCommand.trashTask.needsSelection)
        #expect(AppCommand.completeTask.needsSelection)
        #expect(AppCommand.archiveTask.needsSelection)
        #expect(AppCommand.newTask.needsSelection == false)
        #expect(AppCommand.find.needsSelection == false)
    }

    @Test func aBulkCommandSaysHowManyCardsItIsAimedAt() {
        #expect(AppCommand.trashTask.title(selectionCount: 1) == "Trash Task")
        #expect(AppCommand.trashTask.title(selectionCount: 3) == "Trash 3 Tasks")
        // A submenu reads the same whatever it is aimed at.
        #expect(AppCommand.moveToColumn.title(selectionCount: 3) == AppCommand.moveToColumn.title)
        // And a command that only ever acts on one ignores the count.
        #expect(AppCommand.find.title(selectionCount: 3) == "Find")
    }

    @Test func modifiersPrintInTheOrderTheSystemWritesThem() {
        #expect(AppShortcut(.delete, .command).display == "⌘⌫")
        #expect(AppShortcut(.leftArrow, .option).display == "⌥←")
        #expect(AppShortcut("i", [.command, .option]).display == "⌥⌘I")
        #expect(AppShortcut("s", [.command, .control]).display == "⌃⌘S")
        #expect(AppShortcut(.return, .command).display == "⌘↩")
    }
}
