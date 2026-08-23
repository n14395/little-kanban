import Foundation
import Testing
@testable import Simple_Kanban

/// The final Phase B undo harness: the six questions the contract's §1 makes
/// claims about, asked directly rather than inferred from the mutation suites.
///
/// Everything here drives `BoardStore` through its public surface and reads the
/// stack the way a user does — press ⌘Z until nothing changes, and see where the
/// board lands.
@MainActor
@Suite struct UndoHarnessTests {
    private let doing = BoardColumn.inProgress.id

    /// The whole board, for an assertion that says "exactly as it was".
    ///
    /// The boards — and, inside them, their columns — are read off the store
    /// rather than left to `BoardMutation`'s default. Without that, every board
    /// and column mutation below would be comparing the seed against itself and
    /// would be incapable of failing.
    private func board(_ store: BoardStore) -> BoardMutation {
        BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash)
    }

    // MARK: 1 — text typed before an interleaved step is recoverable

    @Test func drainingTheStackRecoversTextTypedBeforeAnInterleavedStep() {
        let (store, undo) = TestBoard.undoing()
        let original = board(store)

        store.beginEditing(.note, on: TestBoard.dragDrop, scope: .desk)
        store.setText("First half", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.toggleSubtask(TestBoard.dropTargets, on: TestBoard.dragDrop) }
        store.setText("First half, second half", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.endEditing(.note, on: TestBoard.dragDrop, scope: .desk) }

        _ = undoEverything(undo, on: store)
        #expect(board(store) == original)
    }

    // MARK: 2 — a ⌘Z aimed at an older step leaves in-flight keystrokes alone

    @Test func anUndoAimedAtAnOlderStepKeepsInFlightTextAndRedoRestoresIt() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.setPriority(.high, on: TestBoard.cafe, scope: .desk) }
        step(undo) { store.move(TestBoard.cafe, to: doing) }

        store.beginEditing(.note, on: TestBoard.cafe, scope: .desk)
        store.setText("Half a sentence", field: .note, on: TestBoard.cafe)

        // Two presses, both aimed at steps taken before a key was pressed.
        undo.undo()
        #expect(store[TestBoard.cafe]?.columnID == BoardColumn.backlog.id)
        #expect(store[TestBoard.cafe]?.note == "Half a sentence")
        undo.undo()
        #expect(store[TestBoard.cafe]?.priority == .low)
        #expect(store[TestBoard.cafe]?.note == "Half a sentence")

        // ⇧⌘Z twice replays both, and the keystrokes are still there.
        undo.redo()
        undo.redo()
        #expect(store[TestBoard.cafe]?.priority == .high)
        #expect(store[TestBoard.cafe]?.columnID == doing)
        #expect(store[TestBoard.cafe]?.note == "Half a sentence")

        // The session still owns the text, so the blur files it as its own step.
        step(undo) { store.endEditing(.note, on: TestBoard.cafe, scope: .desk) }
        #expect(undo.undoActionName == "Edit Description")
        undo.undo()
        #expect(store[TestBoard.cafe]?.note == "")
        #expect(store[TestBoard.cafe]?.priority == .high)
    }

    // MARK: 3 — the ordering

    @Test func theInterruptionComesOffFirstAndTheTypingSecond() {
        let (store, undo) = TestBoard.undoing()
        store.beginEditing(.note, on: TestBoard.dragDrop, scope: .desk)
        store.setText("Typed first", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.setPriority(.low, on: TestBoard.dragDrop) }
        step(undo) { store.endEditing(.note, on: TestBoard.dragDrop, scope: .desk) }

        // Three steps, not two: the typing was filed when the picker
        // interrupted it, so all the blur has left to register is the activity
        // entry it logs — board data, and its own step like any other.
        #expect(undo.actionNames == ["Edit Description", "Set Priority", "Edit Description"])

        undo.undo()                                     // the entry the blur logged
        #expect(store[TestBoard.dragDrop]?.note == "Typed first")
        #expect(store[TestBoard.dragDrop]?.activity.contains { $0.kind == .descriptionUpdated } == false)
        undo.undo()                                     // …then the interruption…
        #expect(store[TestBoard.dragDrop]?.priority == .high)
        #expect(store[TestBoard.dragDrop]?.note == "Typed first")
        undo.undo()                                     // …then the typing.
        #expect(store[TestBoard.dragDrop]?.note == "Card follows the pointer with a lifted shadow.")
    }

    // MARK: 4 — a session spanning three intervening mutations

    @Test func aSessionSpanningThreeInterveningMutationsDrainsInOrder() {
        let (store, undo) = TestBoard.undoing()
        let original = board(store)
        let note = store[TestBoard.dragDrop]?.note

        store.beginEditing(.note, on: TestBoard.dragDrop, scope: .desk)
        store.setText("one", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.toggleSubtask(TestBoard.dropTargets, on: TestBoard.dragDrop) }
        store.setText("one two", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.setPriority(.low, on: TestBoard.dragDrop) }
        store.setText("one two three", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.addSubtask(to: TestBoard.dragDrop, text: "A fourth") }
        store.setText("one two three four", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.endEditing(.note, on: TestBoard.dragDrop, scope: .desk) }

        // Seven steps: each mutation, and the run of typing that preceded it.
        #expect(undo.actionNames == [
            "Edit Description", "Complete Sub-task",
            "Edit Description", "Set Priority",
            "Edit Description", "Add Sub-task",
            "Edit Description",
        ])

        undo.undo()                                        // the last run of typing
        #expect(store[TestBoard.dragDrop]?.note == "one two three")
        undo.undo()                                        // the sub-task
        #expect(store[TestBoard.dragDrop]?.subtasks.count == 3)
        #expect(store[TestBoard.dragDrop]?.note == "one two three")
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.note == "one two")
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.priority == .high)
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.note == "one")
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.subtasks[1].done == false)
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.note == note)
        #expect(board(store) == original)

        while undo.canRedo { undo.redo() }
        #expect(store[TestBoard.dragDrop]?.note == "one two three four")
        #expect(store[TestBoard.dragDrop]?.subtasks.count == 4)
        #expect(store[TestBoard.dragDrop]?.priority == .low)
    }

    // MARK: 5 — nothing already undone comes back

    @Test func aSessionsStepCannotResurrectAnyOfThreeUndoneMutations() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.toggleSubtask(TestBoard.dropTargets, on: TestBoard.dragDrop) }
        step(undo) { store.setPriority(.low, on: TestBoard.dragDrop) }
        step(undo) { store.move(TestBoard.dragDrop, to: doing) }

        store.beginEditing(.note, on: TestBoard.dragDrop, scope: .desk)
        undo.undo()
        undo.undo()
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.columnID == BoardColumn.backlog.id)
        #expect(store[TestBoard.dragDrop]?.priority == .high)
        #expect(store[TestBoard.dragDrop]?.subtasks[1].done == false)

        store.setText("Typed after three undos", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.endEditing(.note, on: TestBoard.dragDrop, scope: .desk) }
        undo.undo()

        #expect(store[TestBoard.dragDrop]?.note == "Card follows the pointer with a lifted shadow.")
        #expect(store[TestBoard.dragDrop]?.columnID == BoardColumn.backlog.id)
        #expect(store[TestBoard.dragDrop]?.priority == .high)
        #expect(store[TestBoard.dragDrop]?.subtasks[1].done == false)
    }

    /// A picker session opens while a text field still holds unfiled keystrokes
    /// — the due popover and the priority menu both do exactly that, and neither
    /// ends the text session first. The text session then ends against a
    /// before-state *older* than the picker session's, so the flush must not
    /// try to file the picker's "prefix": there is none, and the state it would
    /// file is downstream of the one being registered, which puts a step on the
    /// undo stack that replays the typing rather than taking it back.
    @Test func aSessionOpenedMidTypingDoesNotPutARedoOnTheUndoStack() {
        let (store, undo) = TestBoard.undoing()
        let original = board(store)

        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("Renamed while the picker opens", field: .title, on: TestBoard.cafe)
        store.beginEditing(.due, on: TestBoard.cafe, scope: .desk)   // the popover opens
        step(undo) { store.endEditing(.title, on: TestBoard.cafe, scope: .desk) }

        #expect(undo.actionNames == ["Edit Title"])
        _ = undoEverything(undo, on: store)
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
        #expect(board(store) == original)
    }

    /// The other half of the carry rule: where the step being undone *is* the
    /// session's own earlier one, its value is exactly what the ⌘Z asked for, so
    /// the in-flight text goes back with it rather than being carried over.
    @Test func undoingTheSessionsOwnEarlierStepTakesTheTypingWithIt() {
        let (store, undo) = TestBoard.undoing()
        let original = store[TestBoard.cafe]?.note

        store.beginEditing(.note, on: TestBoard.cafe, scope: .desk)
        store.setText("A", field: .note, on: TestBoard.cafe)
        step(undo) { store.toggleLabel("design", on: TestBoard.cafe) }   // files "A" underneath
        store.setText("AB", field: .note, on: TestBoard.cafe)

        // The label step does not set the description, so the keystrokes ride
        // across it…
        undo.undo()
        #expect(store[TestBoard.cafe]?.labelKeys == ["polish"])
        #expect(store[TestBoard.cafe]?.note == "AB")

        // …and the step below it is the session's own, so they go with it.
        undo.undo()
        #expect(store[TestBoard.cafe]?.note == original)
    }

    /// The younger of two open sessions ends first — the description field is
    /// blurred while the title's prefix is still unfiled. The older prefix has
    /// to be filed underneath, which is the case the `openedBefore` gate must
    /// not swallow.
    @Test func theOlderSessionsPrefixIsStillFiledWhenTheYoungerEndsFirst() {
        let (store, undo) = TestBoard.undoing()
        let title = store[TestBoard.dragDrop]?.title
        let note = store[TestBoard.dragDrop]?.note

        store.beginEditing(.title, on: TestBoard.dragDrop, scope: .desk)
        store.setText("Renamed", field: .title, on: TestBoard.dragDrop)
        store.beginEditing(.note, on: TestBoard.dragDrop, scope: .desk)
        store.setText("Rewritten", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.endEditing(.note, on: TestBoard.dragDrop, scope: .desk) }

        #expect(undo.actionNames == ["Edit Title", "Edit Description"])
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.note == note)
        #expect(store[TestBoard.dragDrop]?.title == "Renamed")
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.title == title)
    }

    // MARK: 6 — every public mutating method

    /// Every public method that changes board data files a step. Read through
    /// `undoActionName` immediately, which is the only way to tell "registered
    /// nothing" from "registered a step that restores an identical board".
    @Test func everyPublicBoardMutationRegistersAStep() throws {
        var named: [String: String] = [:]

        func check(
            _ label: String, tasks: [TaskItem] = TestBoard.tasks,
            boards: [Board] = SeedData.boards, _ body: (BoardStore) -> Void
        ) {
            let (store, undo) = TestBoard.undoing(tasks: tasks, boards: boards)
            let before = board(store)
            step(undo) { body(store) }
            #expect(board(store) != before, "\(label) changed nothing — the probe is wrong")
            named[label] = undo.undoActionName
            #expect(undo.undoActionName != "", "\(label) registered no undo step")
            undo.undo()
            #expect(board(store) == before, "\(label) did not undo cleanly")
        }

        check("move") { $0.move(TestBoard.dragDrop, to: self.doing) }
        check("complete") { $0.complete(TestBoard.sync) }
        check("reopen") { $0.reopen(TestBoard.palette) }
        check("deleteTask") { $0.deleteTask(TestBoard.cafe) }
        check("addTask") { $0.addTask(to: .inbox, title: "Added") }
        check("commitDraft") { store in
            store.beginAdding(in: .inbox)
            store.draft = "Composed"
            store.commitDraft()
        }
        check("quickCapture") { $0.quickCapture() }
        check("addTaskToCurrentMobileColumn") { $0.addTaskToCurrentMobileColumn() }
        check("setPriority") { $0.setPriority(.low, on: TestBoard.dragDrop) }
        check("setDue") { $0.setDue(TestBoard.laterDay, on: TestBoard.cafe) }
        check("addSubtask") { $0.addSubtask(to: TestBoard.cafe, text: "New row") }
        check("commitSubtaskDraft") { store in
            store.setSubtaskDraft("Drafted", for: .desk, task: TestBoard.cafe)
            store.commitSubtaskDraft(for: .desk, task: TestBoard.cafe)
        }
        check("toggleSubtask") { $0.toggleSubtask(TestBoard.dropTargets, on: TestBoard.dragDrop) }
        check("deleteSubtask") { $0.deleteSubtask(TestBoard.dropTargets, from: TestBoard.dragDrop) }
        check("moveSubtask") { $0.moveSubtask(fromOffsets: [0], toOffset: 3, on: TestBoard.dragDrop) }
        check("toggleLabel") { $0.toggleLabel("design", on: TestBoard.cafe) }
        check("createLabel") { $0.createLabel(named: "Brand new", on: TestBoard.cafe) }
        check("commitLabelDraft") { store in
            store.setLabelDraft("Another one", for: .desk, task: TestBoard.cafe)
            store.commitLabelDraft(for: .desk, task: TestBoard.cafe)
        }
        check("renameLabel") { $0.renameLabel("design", to: "Visual design") }
        check("recolorLabel") { $0.recolorLabel("design", to: LabelDef.palette[3]) }
        check("deleteLabel") { $0.deleteLabel("design") }
        check("archive") { $0.archive(TestBoard.palette) }
        check("archiveCompleted") { $0.archiveCompleted() }
        // Started from a board that already has something filed away: archiving
        // inside the same step would collapse the pair into one, and the undo
        // would then be measuring the archive rather than the restore.
        check("unarchive", tasks: TestBoard.tasks(archiving: [TestBoard.palette: 300])) {
            $0.unarchive(TestBoard.palette)
        }
        // A session's text: `setText` and `updateSubtask` register nothing
        // themselves, and `endEditing` is what files the step.
        check("setText + endEditing") { store in
            store.beginEditing(.note, on: TestBoard.cafe, scope: .desk)
            store.setText("A description", field: .note, on: TestBoard.cafe)
            store.endEditing(.note, on: TestBoard.cafe, scope: .desk)
        }
        check("updateSubtask + endEditing") { store in
            store.beginEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.lift)
            store.updateSubtask(TestBoard.lift, text: "Renamed row", on: TestBoard.dragDrop)
            store.endEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.lift)
        }

        // Phase D made columns and boards board data. Each of these changes the
        // board, so each owes the Edit menu a step — and `board(_:)` above is
        // what makes that assertion capable of failing.
        check("addColumn") { $0.addColumn(named: "Blocked") }
        check("renameColumn") { $0.renameColumn(BoardColumn.upNext.id, to: "Later") }
        check("recolorColumn") { $0.recolorColumn(BoardColumn.backlog.id, to: .accent) }
        check("moveColumn") { $0.moveColumn(fromOffsets: [1], toOffset: 0) }
        check("deleteColumn") { $0.deleteColumn(BoardColumn.upNext.id) }
        // The placement pair. `file` needs somewhere else to file it to.
        check("file", boards: TestBoard.boards) {
            $0.file(TestBoard.widget, onto: TestBoard.support.id, column: TestBoard.queue.id)
        }
        check("unfile") { $0.unfile(TestBoard.dragDrop) }
        check("createBoard") { $0.createBoard(named: "Website refresh") }
        check("renameBoard") { $0.renameBoard(SeedData.defaultBoard.id, to: "Northwind iOS 4.0") }
        check("recolorBoard") { $0.recolorBoard(SeedData.defaultBoard.id, to: .hex(0x1F6F63)) }
        check("moveBoard", boards: TestBoard.boards) { $0.moveBoard(fromOffsets: [1], toOffset: 0) }
        check("deleteBoard", boards: TestBoard.boards) { $0.deleteBoard(SeedData.defaultBoard.id) }

        // The bulk commands. Each acts on two cards and owes the Edit menu one
        // step for the pair — the whole point of multi-select, and the thing a
        // loop of singular calls outside an `undoable` would get wrong.
        check("move (several)") { $0.move([TestBoard.dragDrop, TestBoard.cafe], to: self.doing) }
        check("complete (several)") { $0.complete([TestBoard.sync, TestBoard.offline]) }
        check("archive (several)") { $0.archive([TestBoard.palette, TestBoard.cafe]) }
        check("deleteTasks") { $0.deleteTasks([TestBoard.cafe, TestBoard.offline]) }
        check("toggleLabel (several)") { $0.toggleLabel("design", on: [TestBoard.cafe, TestBoard.sync]) }
        check("setPriority (several)") { $0.setPriority(.low, on: [TestBoard.dragDrop, TestBoard.sync]) }
        check("setDue (several)") { $0.setDue(TestBoard.laterDay, on: [TestBoard.cafe, TestBoard.sync]) }

        // Phase F's whole-board mutations: each replaces the board rather than
        // editing one card, and each is still one ⌘Z.
        check("importBoard") { $0.importBoard(ForeignBoard.snapshot(includingCollision: true)) }
        check("startOver") { $0.startOver(with: SeedData.blank.snapshot) }

        // A restore needs a file to restore *from*, so it cannot go through the
        // probe above, which keeps every store in memory on purpose.
        let temp = TempBoard()
        let (filed, fileUndo) = TestBoard.undoing(file: temp.file)
        try FileManager.default.createDirectory(
            at: temp.file.backupsDirectory, withIntermediateDirectories: true
        )
        try BoardSnapshot(tasks: [], boards: [], labels: [], nextSerial: 100, accentTheme: .ember)
            .encoded()
            .write(to: temp.file.backupsDirectory.appending(path: "board-20260814T090000Z.json"))
        let backup = try #require(temp.file.backups().first)
        let beforeRestore = board(filed)
        step(fileUndo) { try? filed.restore(fromBackup: backup) }
        #expect(board(filed) != beforeRestore, "the restore changed nothing — the probe is wrong")
        named["restore(fromBackup:)"] = fileUndo.undoActionName
        #expect(fileUndo.undoActionName == "Restore Backup")
        fileUndo.undo()
        #expect(board(filed) == beforeRestore, "restore(fromBackup:) did not undo cleanly")

        // The capture and its discard cancel out on the board, so they cannot be
        // probed in one step — the discard gets its own.
        let (store, undo) = TestBoard.undoing()
        var captured: TaskItem.ID?
        step(undo) { captured = store.addTask(to: .inbox, title: "") }
        let withCapture = board(store)
        let id = try #require(captured)
        step(undo) { store.discardIfBlank(id) }
        #expect(board(store) != withCapture)
        #expect(undo.undoActionName == "Discard Capture")
        undo.undo()
        #expect(board(store) == withCapture)
        named["discardIfBlank"] = "Discard Capture"

        // Every one of them named itself, which is what the Edit menu shows.
        #expect(named.values.allSatisfy { !$0.isEmpty })
        #expect(named["archive"] == "Archive Task")
        #expect(named["unarchive"] == "Restore Task")
        #expect(named["archiveCompleted"] == "Archive Completed")
        #expect(named["unfile"] == "Move to Inbox")
        #expect(named["deleteBoard"] == "Delete Board")
        // A bulk command names itself in the plural, so the Edit menu says how
        // much a ⌘Z is about to take back.
        #expect(named["deleteTasks"] == "Delete Tasks")
        #expect(named["move (several)"] == "Move Tasks")
        #expect(named["archive (several)"] == "Archive Tasks")
        #expect(named["importBoard"] == "Import Board")
        #expect(named["restore(fromBackup:)"] == "Restore Backup")
        #expect(named["startOver"] == "Start Over")
        #expect(named.count == 49)
    }

    /// The mutating methods that deliberately register nothing, each for a
    /// stated reason. A method that stops being on this list without being on
    /// the one above is a mutation that has fallen out of undo.
    @Test func theMutationsThatDeliberatelyRegisterNothing() {
        let (store, undo) = TestBoard.undoing(boards: TestBoard.boards)
        let before = board(store)

        // The accent is a preference, not board data: it is not in
        // `BoardMutation`, so there is nothing for a step to restore.
        step(undo) { store.setAccentTheme(.pine) }
        #expect(store.accentTheme == .pine)
        #expect(undo.undoActionName == "")
        #expect(board(store) == before)

        // Session state, all of it: none of this reaches `BoardMutation`.
        step(undo) {
            store.beginAdding(in: .inbox)
            store.cancelDraft()
            store.setSubtaskDraft("half typed", for: .desk, task: TestBoard.cafe)
            store.setLabelDraft("half typed", for: .desk, task: TestBoard.cafe)
            store.toggleLabelPicker(.desk, task: TestBoard.cafe)
            store.closeLabelPicker(.desk, task: TestBoard.cafe)
            store.stepMobileColumn(by: 1)
            // Navigation, like the selection: it is saved, because which board
            // you are on is where your work is, but a ⌘Z that moved somebody to
            // another board would be undoing their attention.
            store.selectBoard(TestBoard.support.id)
            store.showInbox()
            store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
            store.endEditing(.title, on: TestBoard.cafe, scope: .desk)
            store.clearDrafts(for: TestBoard.cafe)
            store.dismissError()
            // The selection, and the two requests a menu makes of a surface.
            // None of it is board data.
            store.select(TestBoard.cafe)
            store.toggleSelection(of: TestBoard.dragDrop)
            store.extendSelection(to: TestBoard.offline, through: store.tasks.map(\.id))
            store.selectAll(store.tasks.map(\.id))
            store.clearSelection()
            store.focusSearch()
            store.beginAddingWhereVisible()
            store.cancelDraft()
        }
        #expect(undo.undoActionName == "")
        #expect(board(store) == before)
    }
}
