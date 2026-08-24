import Foundation
import Testing
@testable import Simple_Kanban

/// Undo is snapshot-based, so what matters is not that an inverse was written
/// but that the board comes back exactly as it was — and that one user action
/// costs exactly one ⌘Z.
///
/// Each action goes through `step(_:_:)`, which gives it the undo group the
/// run loop would give it in the app. `undoEverything(_:on:)` then counts the
/// ⌘Z presses that actually changed something.
@MainActor
@Suite struct UndoTests {
    private let done = BoardColumn.done.id
    private let doing = BoardColumn.inProgress.id

    // MARK: Moving

    @Test func aMoveUndoesAndRedoes() {
        let (store, undo) = TestBoard.undoing()
        let order = store.tasks.map(\.id)
        step(undo) { store.move(TestBoard.dragDrop, to: doing) }
        #expect(store[TestBoard.dragDrop]?.columnID == doing)
        #expect(undo.undoActionName == "Move Task")

        undo.undo()
        #expect(store[TestBoard.dragDrop]?.columnID == BoardColumn.backlog.id)
        #expect(store.tasks.map(\.id) == order)          // and back to where it sat
        #expect(store[TestBoard.dragDrop]?.activity.map(\.kind) == [.created])

        undo.redo()
        #expect(store[TestBoard.dragDrop]?.columnID == doing)
        #expect(store[TestBoard.dragDrop]?.activity.first?.kind == .moved(columnID: BoardColumn.inProgress.id.uuidString, columnName: "In Progress"))
    }

    @Test func aNoOpDropIsNotWorthAKeystroke() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.move(TestBoard.dragDrop, to: BoardColumn.backlog.id) }
        // Read before the stack is drained: a step that restores an identical
        // board is invisible to a count of ⌘Z presses that changed something,
        // and "an identical board was registered" is exactly the bug here.
        #expect(undo.undoActionName == "")
        #expect(undoEverything(undo, on: store) == 0)
    }

    @Test func theDoneTickIsUndoneExactly() {
        let (store, undo) = TestBoard.undoing()
        let before = store[TestBoard.dragDrop]?.subtasks
        #expect(before?.map(\.done) == [true, false, false])

        step(undo) { store.move(TestBoard.dragDrop, to: done) }
        #expect(store[TestBoard.dragDrop]?.subtasks.map(\.done) == [true, true, true])

        undo.undo()
        // The exact prior flags, not "all off": one of them was already ticked.
        #expect(store[TestBoard.dragDrop]?.subtasks == before)
        #expect(store[TestBoard.dragDrop]?.columnID == BoardColumn.backlog.id)
    }

    @Test func completingAndReopeningEachUndo() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.complete(TestBoard.sync) }
        #expect(undo.undoActionName == "Complete Task")

        undo.undo()
        #expect(store[TestBoard.sync]?.columnID == doing)
        #expect(undo.canUndo == false)

        undo.redo()
        #expect(store[TestBoard.sync]?.columnID == done)

        step(undo) { store.reopen(TestBoard.sync) }
        #expect(undo.undoActionName == "Reopen Task")
        undo.undo()
        #expect(store[TestBoard.sync]?.columnID == done)
    }

    // MARK: Deleting

    @Test func aDeletedTaskComesBackWhereItWas() {
        let (store, undo) = TestBoard.undoing()
        let before = store.tasks
        store.selectedID = TestBoard.dragDrop
        step(undo) { store.deleteTask(TestBoard.dragDrop) }
        #expect(undo.undoActionName == "Delete Task")
        #expect(store.tasks.count == before.count - 1)

        undo.undo()
        #expect(store.tasks == before)
        #expect(store.tasks.firstIndex { $0.id == TestBoard.dragDrop } == 1)   // not appended at the end
    }

    @Test func deletingATaskWhoseTitleWasEmptiedBringsTheTitleBack() {
        // Undo must not be the one path that puts an untitled card on the board:
        // the blank is a half-finished keystroke, and every other path refuses
        // it. The restore happens before the step opens, where the snapshot is.
        let (store, undo) = TestBoard.undoing()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("", field: .title, on: TestBoard.cafe)
        #expect(store[TestBoard.cafe]?.title == "")

        step(undo) { store.deleteTask(TestBoard.cafe) }
        undo.undo()
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
        #expect(store[TestBoard.cafe]?.activity.map(\.kind) == [.created])   // no rename logged
    }

    @Test func deletingASelectionWhoseTitleWasEmptiedBringsTheTitleBack() {
        // The bulk path takes the same care in the same order, and only the
        // order can go wrong: `deleteTasks` restores every doomed card's fields
        // and *then* opens the step, so moving the loop inside the step would
        // snapshot the blank it was there to prevent.
        let (store, undo) = TestBoard.undoing()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("", field: .title, on: TestBoard.cafe)
        #expect(store[TestBoard.cafe]?.title == "")

        step(undo) { store.deleteTasks([TestBoard.cafe, TestBoard.offline]) }
        #expect(undo.actionNames == ["Delete Tasks"])

        undo.undo()
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
        #expect(store[TestBoard.cafe]?.activity.map(\.kind) == [.created])   // no rename logged
        #expect(store[TestBoard.offline]?.title == "Offline queue for edits")
    }

    @Test func deletingATaskWhoseDescriptionWasClearedLeavesItCleared() {
        // The restore is for one-line fields only. A title with nothing in it is
        // unreachable by any other path, so a snapshot holding one is a bug; a
        // description with nothing in it is a state the user asked for, and
        // putting it back would make undo the one path that rewrites it.
        let (store, undo) = TestBoard.undoing()
        store.beginEditing(.note, on: TestBoard.dragDrop, scope: .desk)
        store.setText("", field: .note, on: TestBoard.dragDrop)

        step(undo) { store.deleteTask(TestBoard.dragDrop) }
        #expect(store[TestBoard.dragDrop] == nil)

        undo.undo()
        #expect(store[TestBoard.dragDrop] != nil)
        #expect(store[TestBoard.dragDrop]?.note == "")
        #expect(store[TestBoard.dragDrop]?.title == "Drag and drop between columns")
    }

    @Test func deletingATaskWhoseSubTaskWasEmptiedBringsTheRowBack() {
        // The other half of the same filter: a sub-task's text is one line, so
        // it is restored exactly as a title is.
        let (store, undo) = TestBoard.undoing()
        store.beginEditing(.subtask, on: TestBoard.dragDrop, scope: .sheet, subtask: TestBoard.keyboard)
        store.updateSubtask(TestBoard.keyboard, text: "  ", on: TestBoard.dragDrop)

        step(undo) { store.deleteTask(TestBoard.dragDrop) }
        undo.undo()
        #expect(store.subtaskText(TestBoard.keyboard, on: TestBoard.dragDrop) == "Keyboard fallback")
        #expect(store[TestBoard.dragDrop]?.activity.map(\.kind) == [.created])   // no rename logged
    }

    @Test func undoingADeleteLeavesTheSelectionOnTheNeighbour() {
        // Documented rather than accidental. There are two selections, they are
        // per surface, neither is board data, and restoring them would yank
        // focus on every ⌘Z — so `apply` only clears one that has stopped
        // naming anything. CONTRACT-B §1 names the cost this pins.
        let (store, undo) = TestBoard.undoing()
        store.selectedID = TestBoard.dragDrop
        step(undo) { store.deleteTask(TestBoard.dragDrop) }
        #expect(store.selectedID == TestBoard.cafe)          // the next card in Backlog

        undo.undo()
        #expect(store[TestBoard.dragDrop] != nil)
        #expect(store.selectedID == TestBoard.cafe)
    }

    @Test func movingTheSelectionOffADeletedTaskIsNotItsOwnStep() {
        // Deleting ends the sessions the surface left on the doomed task, and
        // none of those may file a ⌘Z for a fragment of the delete.
        let (store, undo) = TestBoard.undoing()
        store.selectedID = TestBoard.cafe
        step(undo) {
            store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
            store.setText("half typed", field: .title, on: TestBoard.cafe)
        }
        let before = store.tasks

        step(undo) { store.deleteTask(TestBoard.cafe) }
        #expect(undoEverything(undo, on: store) == 1)
        #expect(store.tasks == before)
    }

    @Test func aSessionEndedByADeleteFilesNoStepOfItsOwn() {
        // The delete moves the selection, and every other session that surface
        // left open ends with it. One that registered from in there would file a
        // ⌘Z for a fragment of one delete: named for a field, and snapshotting
        // the board with the card already half gone.
        let (store, undo) = TestBoard.undoing()
        store.selectedID = TestBoard.cafe
        store.beginEditing(.title, on: TestBoard.sync, scope: .desk)
        store.setText("Replication engine", field: .title, on: TestBoard.sync)

        step(undo) { store.deleteTask(TestBoard.cafe) }
        #expect(undo.actionNames == ["Delete Task"])
        #expect(store.isEditing(.title, on: TestBoard.sync, scope: .desk) == false)

        undo.undo()
        #expect(store[TestBoard.cafe] != nil)
        #expect(store[TestBoard.sync]?.title == "Replication engine")
        #expect(undo.canUndo == false)
    }

    @Test func discardingAnUntouchedCaptureIsItsOwnStep() throws {
        // The capture and the discard cancel out on the board but not on the
        // stack: an unregistered removal sitting on top of the capture's step
        // is what lets a later ⌘Z put the discarded card back. So each of the
        // three actions is one press, in order.
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.setPriority(.low, on: TestBoard.dragDrop) }
        var id: TaskItem.ID?
        step(undo) { id = store.addTask(to: BoardColumn.inbox.id, title: "", fromPhone: true, log: .captured) }
        let capture = try #require(id)
        #expect(undo.undoActionName == "New Task")
        step(undo) { store.discardIfBlank(capture) }
        #expect(undo.undoActionName == "Discard Capture")

        undo.undo()
        #expect(store[capture] != nil)                           // the capture is back…
        undo.undo()
        #expect(store[capture] == nil)                           // …and now it was never made
        #expect(store[TestBoard.dragDrop]?.priority == .low)     // the priority is untouched
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.priority == .high)
    }

    // MARK: Text and picker sessions

    @Test func aTypingSessionIsOneStepAndKeystrokesAreNone() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.beginEditing(.title, on: TestBoard.cafe, scope: .desk) }
        for text in ["C", "Ch", "Cha", "Chan", "Chang", "Change"] {
            step(undo) { store.setText(text, field: .title, on: TestBoard.cafe) }
        }
        step(undo) { store.endEditing(.title, on: TestBoard.cafe, scope: .desk) }
        #expect(undo.undoActionName == "Edit Title")

        // One ⌘Z, and it takes the whole session — not the last keystroke.
        #expect(undoEverything(undo, on: store) == 1)
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
    }

    @Test func aPickerSessionCoalescesTheEntryAndNotTheSteps() {
        let (store, undo) = TestBoard.undoing()
        store.beginEditing(.due, on: TestBoard.cafe, scope: .desk)
        for month in 9...12 {
            step(undo) { store.setDue(CalendarDay(year: 2026, month: month, day: 1), on: TestBoard.cafe, scope: .desk) }
        }
        // Read before the blur: `step` pushes an empty group for it, and an
        // empty group reports no name at all.
        #expect(undo.undoActionName == "Set Due Date")
        // Four dates tried, one line in the history: "Created" and the one the
        // session keeps rewriting.
        #expect(store[TestBoard.cafe]?.activity.count == 2)
        step(undo) { store.endEditing(.due, on: TestBoard.cafe, scope: .desk) }

        // …and four presses, because each change was left on the board on its
        // own. Deferring the step to the blur left them unregistered, where one
        // ⌘Z took the lot plus whatever preceded the session.
        #expect(undoEverything(undo, on: store) == 4)
        #expect(store[TestBoard.cafe]?.due == nil)
        #expect(store[TestBoard.cafe]?.activity.map(\.kind) == [.created])
    }

    @Test func aPickerChangeMidSessionDoesNotReachPastTheSession() {
        // The picker is open on the same surface as an earlier, finished action.
        // One ⌘Z must take back the date and stop there.
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.setPriority(.high, on: TestBoard.cafe, scope: .desk) }
        store.beginEditing(.due, on: TestBoard.cafe, scope: .desk)
        step(undo) { store.setDue(TestBoard.laterDay, on: TestBoard.cafe, scope: .desk) }
        #expect(undo.undoActionName == "Set Due Date")

        undo.undo()                                   // with the session still open
        #expect(store[TestBoard.cafe]?.due == nil)
        #expect(store[TestBoard.cafe]?.priority == .high)
    }

    @Test func aStepTakenMidSessionIsNotSwallowedByTheSession() {
        // Nothing on either detail surface takes focus off the description, so
        // a sub-task can be ticked with the field still live. The session's one
        // step owns the keystrokes and nothing else.
        let (store, undo) = TestBoard.undoing()
        store.beginEditing(.note, on: TestBoard.dragDrop, scope: .desk)
        store.setText("First half", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.toggleSubtask(TestBoard.dropTargets, on: TestBoard.dragDrop) }
        store.setText("First half, second half", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.endEditing(.note, on: TestBoard.dragDrop, scope: .desk) }
        #expect(undo.undoActionName == "Edit Description")

        undo.undo()
        #expect(store[TestBoard.dragDrop]?.note == "First half")
        #expect(store[TestBoard.dragDrop]?.subtasks[1].done == true)     // the tick stands

        // The next press is the tick's own, and it stops at the tick: the text
        // typed before it is a step of its own, filed underneath.
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.subtasks[1].done == false)
        #expect(store[TestBoard.dragDrop]?.note == "First half")
        #expect(undo.canUndo)
    }

    @Test func typingBeforeAnInterleavedStepIsStillOnTheStack() {
        // The prefix used to belong to no step at all: the tick's before-state
        // held it, and the session's own step began after it, so no number of
        // ⌘Z could reach the description the user started from. It is filed at
        // the boundary now, underneath the step that interrupted it.
        let (store, undo) = TestBoard.undoing()
        let original = store[TestBoard.dragDrop]?.note
        store.beginEditing(.note, on: TestBoard.dragDrop, scope: .desk)
        store.setText("First half", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.toggleSubtask(TestBoard.dropTargets, on: TestBoard.dragDrop) }
        store.setText("First half, second half", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.endEditing(.note, on: TestBoard.dragDrop, scope: .desk) }
        // Three steps, oldest first: the prefix, the tick, then the rest of the
        // typing. The prefix is named for the field it came out of.
        #expect(undo.actionNames == ["Edit Description", "Complete Sub-task", "Edit Description"])

        #expect(undoEverything(undo, on: store) == 3)
        #expect(store[TestBoard.dragDrop]?.note == original)
        #expect(store[TestBoard.dragDrop]?.subtasks[1].done == false)

        // …and the whole sequence replays forwards.
        while undo.canRedo { undo.redo() }
        #expect(store[TestBoard.dragDrop]?.note == "First half, second half")
        #expect(store[TestBoard.dragDrop]?.subtasks[1].done == true)
    }

    @Test func anUndoAimedAtAnOlderStepKeepsWhatIsStillBeingTyped() {
        // On iOS and from the Edit menu a ⌘Z can arrive while a field still has
        // focus and unfiled keystrokes in it. Both sides of the older step were
        // snapshotted before those keystrokes existed, so a plain restore threw
        // them away and ⇧⌘Z replayed a board that predated them.
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.setPriority(.high, on: TestBoard.cafe, scope: .desk) }
        store.beginEditing(.note, on: TestBoard.cafe, scope: .desk)
        store.setText("In flight", field: .note, on: TestBoard.cafe)

        undo.undo()
        #expect(store[TestBoard.cafe]?.priority == .low)          // the step it was aimed at
        #expect(store[TestBoard.cafe]?.note == "In flight")       // and only that step

        undo.redo()
        #expect(store[TestBoard.cafe]?.priority == .high)
        #expect(store[TestBoard.cafe]?.note == "In flight")

        // The session still owns those keystrokes, so finishing it files them.
        step(undo) { store.endEditing(.note, on: TestBoard.cafe, scope: .desk) }
        #expect(undo.undoActionName == "Edit Description")
        undo.undo()
        #expect(store[TestBoard.cafe]?.note == "")
        #expect(store[TestBoard.cafe]?.priority == .high)
    }

    @Test func aStepUnderTwoOpenSessionsFilesFromTheOlderOne() {
        // Two fields can be live at once — a title still focused when the
        // description takes over — and only the older session's before-state
        // covers the whole unfiled delta. Filing the younger one would orphan
        // the older prefix all over again, so the flush files one step, from the
        // oldest.
        let (store, undo) = TestBoard.undoing()
        let title = store[TestBoard.dragDrop]?.title
        let note = store[TestBoard.dragDrop]?.note
        store.beginEditing(.title, on: TestBoard.dragDrop, scope: .desk)
        store.setText("Renamed", field: .title, on: TestBoard.dragDrop)
        store.beginEditing(.note, on: TestBoard.dragDrop, scope: .desk)
        store.setText("Rewritten", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.setPriority(.low, on: TestBoard.dragDrop) }
        #expect(undo.actionNames == ["Edit Title", "Set Priority"])

        undo.undo()
        #expect(store[TestBoard.dragDrop]?.priority == .high)
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.title == title)
        #expect(store[TestBoard.dragDrop]?.note == note)
    }

    @Test func aSessionsStepCannotResurrectSomethingAlreadyUndone() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.toggleSubtask(TestBoard.dropTargets, on: TestBoard.dragDrop) }
        #expect(store[TestBoard.dragDrop]?.subtasks[1].done == true)

        store.beginEditing(.note, on: TestBoard.dragDrop, scope: .desk)
        undo.undo()                                   // the user takes the tick back…
        #expect(store[TestBoard.dragDrop]?.subtasks[1].done == false)

        store.setText("Typed afterwards", field: .note, on: TestBoard.dragDrop)
        step(undo) { store.endEditing(.note, on: TestBoard.dragDrop, scope: .desk) }
        undo.undo()

        // …and undoing the typing must not bring it back.
        #expect(store[TestBoard.dragDrop]?.subtasks[1].done == false)
        #expect(store[TestBoard.dragDrop]?.note == "Card follows the pointer with a lifted shadow.")
    }

    @Test func aPickerWithNoSessionIsItsOwnStep() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.setPriority(.low, on: TestBoard.dragDrop) }
        step(undo) { store.setDue(nil, on: TestBoard.dragDrop) }
        #expect(undo.undoActionName == "Clear Due Date")

        undo.undo()
        #expect(store[TestBoard.dragDrop]?.due == TestBoard.dueDay)
        #expect(store[TestBoard.dragDrop]?.priority == .low)

        undo.undo()
        #expect(store[TestBoard.dragDrop]?.priority == .high)
    }

    // MARK: Sub-tasks

    @Test func everySubTaskEditUndoes() {
        let (store, undo) = TestBoard.undoing()
        let before = store[TestBoard.dragDrop]?.subtasks

        step(undo) { store.addSubtask(to: TestBoard.dragDrop, text: "A fourth") }
        step(undo) { store.toggleSubtask(TestBoard.dropTargets, on: TestBoard.dragDrop) }
        step(undo) { store.moveSubtask(fromOffsets: IndexSet(integer: 0), toOffset: 3, on: TestBoard.dragDrop) }
        step(undo) { store.deleteSubtask(TestBoard.keyboard, from: TestBoard.dragDrop) }

        #expect(undo.undoActionName == "Delete Sub-task")
        #expect(undoEverything(undo, on: store) == 4)
        #expect(store[TestBoard.dragDrop]?.subtasks == before)
    }

    @Test func aSubTaskRenameSessionIsOneStep() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.beginEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard) }
        for text in ["K", "Ke", "Key"] {
            step(undo) { store.updateSubtask(TestBoard.keyboard, text: text, on: TestBoard.dragDrop) }
        }
        step(undo) { store.endEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard) }
        #expect(undo.undoActionName == "Edit Sub-task")
        #expect(undoEverything(undo, on: store) == 1)
        #expect(store.subtaskText(TestBoard.keyboard, on: TestBoard.dragDrop) == "Keyboard fallback")
    }

    @Test func reorderingSubTasksUndoesToTheOriginalOrder() {
        let (store, undo) = TestBoard.undoing()
        let before = store[TestBoard.dragDrop]?.subtasks.map(\.id)
        step(undo) { store.moveSubtask(fromOffsets: IndexSet(integer: 2), toOffset: 0, on: TestBoard.dragDrop) }
        #expect(store[TestBoard.dragDrop]?.subtasks.first?.id == TestBoard.keyboard)
        #expect(undo.undoActionName == "Reorder Sub-tasks")
        undo.undo()
        #expect(store[TestBoard.dragDrop]?.subtasks.map(\.id) == before)
    }

    @Test func aReorderThatChangesNothingRegistersNothing() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.moveSubtask(fromOffsets: IndexSet(integer: 0), toOffset: 0, on: TestBoard.dragDrop) }
        #expect(undo.undoActionName == "")
        #expect(undoEverything(undo, on: store) == 0)
    }

    // MARK: Labels

    @Test func everyLabelEditUndoes() {
        let (store, undo) = TestBoard.undoing()
        let labelsBefore = store.labels
        let keysBefore = store.tasks.map(\.labelKeys)

        step(undo) { store.toggleLabel("bug", on: TestBoard.cafe) }
        step(undo) { store.createLabel(named: "Infra Work", on: TestBoard.cafe) }
        step(undo) { store.renameLabel("design", to: "Visual design") }
        step(undo) { store.recolorLabel("design", to: .hex(0x3B5BA9)) }
        step(undo) { store.deleteLabel("design") }

        #expect(undo.undoActionName == "Delete Label")
        #expect(undoEverything(undo, on: store) == 5)
        #expect(store.labels == labelsBefore)
        #expect(store.tasks.map(\.labelKeys) == keysBefore)
    }

    @Test func deletingALabelAndUndoingItPutsTheKeyBackOnEveryTask() {
        let (store, undo) = TestBoard.undoing()
        #expect(store.tasks.count { $0.labelKeys.contains("design") } == 2)
        step(undo) { store.deleteLabel("design") }
        #expect(store.tasks.count { $0.labelKeys.contains("design") } == 0)
        #expect(store.label(forKey: "design") == nil)

        undo.undo()
        #expect(store.tasks.count { $0.labelKeys.contains("design") } == 2)
        #expect(store.label(forKey: "design")?.name == "Design")
    }

    @Test func renamingALabelIsNotWorthTouchingATask() {
        let (store, undo) = TestBoard.undoing()
        let tasksBefore = store.tasks
        step(undo) { store.renameLabel("design", to: "Visual design") }
        #expect(store.tasks == tasksBefore)          // the key is what tasks carry
        #expect(undo.undoActionName == "Rename Label")
        undo.undo()
        #expect(store.label(forKey: "design")?.name == "Design")
    }

    // MARK: Adding

    @Test func addingATaskIsItsOwnStepAndSurvivesAnEarlierOne() throws {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.setPriority(.low, on: TestBoard.dragDrop) }
        var id: TaskItem.ID?
        step(undo) { id = store.addTask(to: .inbox, title: "Fresh") }
        let fresh = try #require(id)
        #expect(undo.undoActionName == "New Task")

        undo.undo()                                   // takes back the card…
        #expect(store[fresh] == nil)
        #expect(store.tasks.count == TestBoard.tasks.count)
        #expect(store[TestBoard.dragDrop]?.priority == .low)   // …and nothing else

        undo.redo()
        #expect(store[fresh]?.title == "Fresh")
        #expect(store[fresh]?.code == BoardSnapshot.code(
            prefix: Board.inboxCodePrefix, forSerial: BoardSnapshot.baseSerial
        ))
        // The serial came back with the card: the next one is the next code,
        // not a second card wearing this one's.
        step(undo) { store.addTask(to: .inbox, title: "Fresher") }
        #expect(store.tasks.last?.code == BoardSnapshot.code(
            prefix: Board.inboxCodePrefix, forSerial: BoardSnapshot.baseSerial + 1
        ))
    }

    // MARK: Collapsing

    @Test func aMutationBuiltOutOfOthersCostsOneKeystroke() {
        let (store, undo) = TestBoard.undoing()
        let before = store.tasks
        step(undo) {
            store.undoable("Rework Card") {
                store.move(TestBoard.dragDrop, to: doing)
                store.setPriority(.low, on: TestBoard.dragDrop)
                store.addSubtask(to: TestBoard.dragDrop, text: "A fourth")
            }
        }
        // Three mutations, one registration. `undoActionName` alone cannot say
        // this: inside a group the outer name overwrites the inner ones and the
        // board a grouped undo lands on is the same either way.
        #expect(undo.actionNames == ["Rework Card"])
        #expect(undo.undoActionName == "Rework Card")

        undo.undo()
        #expect(store.tasks == before)
        #expect(undo.canUndo == false)
    }

    // MARK: What is deliberately not on the stack

    @Test func theAccentThemeIsAPreferenceNotBoardData() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.setAccentTheme(.pine) }
        #expect(undoEverything(undo, on: store) == 0)
        #expect(store.accentTheme == .pine)
    }

    // MARK: Passthroughs and the manager-less case

    @Test func canUndoAndCanRedoFollowTheManager() {
        let (store, undo) = TestBoard.undoing()
        #expect(store.canUndo == false)
        #expect(store.canRedo == false)
        step(undo) { store.move(TestBoard.dragDrop, to: doing) }
        #expect(store.canUndo)
        undo.undo()
        #expect(store.canRedo)
    }

    @Test func withNoManagerEveryMutationStillWorks() {
        let store = TestBoard.store()          // no undo manager at all
        store.move(TestBoard.dragDrop, to: doing)
        store.deleteTask(TestBoard.cafe)
        #expect(store[TestBoard.dragDrop]?.columnID == doing)
        #expect(store[TestBoard.cafe] == nil)
        #expect(store.canUndo == false)
        #expect(store.canRedo == false)
    }

    // MARK: Session state after a restore

    @Test func aRestoreStopsTheSelectionNamingATaskThatIsGone() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.deleteTask(TestBoard.cafe) }
        undo.undo()                            // the task is back…
        #expect(store[TestBoard.cafe] != nil)

        store.selectedID = TestBoard.cafe
        store.sheetID = TestBoard.cafe
        store.draggingID = TestBoard.cafe
        undo.redo()                            // …and now it is gone again
        #expect(store[TestBoard.cafe] == nil)
        #expect(store.selectedID != TestBoard.cafe)
        #expect(store.sheetID == nil)
        #expect(store.draggingID == nil)
    }

    @Test func aRestoreLeavesASelectionThatStillNamesSomethingAlone() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.deleteTask(TestBoard.cafe) }
        store.selectedID = TestBoard.sync
        undo.undo()
        #expect(store.selectedID == TestBoard.sync)
    }
}
