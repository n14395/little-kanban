import Foundation
import Testing
@testable import LittleKanban

/// A field edited on a surface is one *session*: focus, any amount of change,
/// blur. What is asserted here is that a session leaves exactly one line in the
/// activity feed — not one per keystroke, and not none.
@MainActor
@Suite struct EditingSessionTests {
    private func kinds(_ store: BoardStore, _ id: TaskItem.ID) -> [ActivityEntry.Kind] {
        store[id]?.activity.map(\.kind) ?? []
    }

    private func renames(_ store: BoardStore, _ id: TaskItem.ID) -> Int {
        kinds(store, id).count { $0 == .renamed }
    }

    // MARK: Titles

    @Test func aWholeTypingSessionIsOneEntry() {
        let store = TestBoard.store()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        for text in ["C", "Ca", "Caf", "Café", "Café m"] {
            store.setText(text, field: .title, on: TestBoard.cafe)
        }
        store.endEditing(.title, on: TestBoard.cafe, scope: .desk)
        #expect(store[TestBoard.cafe]?.title == "Café m")
        #expect(renames(store, TestBoard.cafe) == 1)
    }

    @Test func aSessionThatChangedNothingLeavesNothingBehind() {
        let store = TestBoard.store()
        let before = store.tasks
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.endEditing(.title, on: TestBoard.cafe, scope: .desk)
        #expect(store.tasks == before)

        // Typing and typing back is also no change.
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("Something else", field: .title, on: TestBoard.cafe)
        store.setText("Café menu polish", field: .title, on: TestBoard.cafe)
        store.endEditing(.title, on: TestBoard.cafe, scope: .desk)
        #expect(renames(store, TestBoard.cafe) == 0)
    }

    @Test func aTitleEmptiedToNothingComesBack() {
        let store = TestBoard.store()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("", field: .title, on: TestBoard.cafe)
        store.endEditing(.title, on: TestBoard.cafe, scope: .desk)
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
        #expect(renames(store, TestBoard.cafe) == 0)

        // Whitespace only is empty too.
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("   ", field: .title, on: TestBoard.cafe)
        store.endEditing(.title, on: TestBoard.cafe, scope: .desk)
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
    }

    /// The same restore when the session never gets to end — the card is
    /// trashed under it. The blank has to be put back *before* the step's
    /// snapshot is taken, or ⌘Z restores an untitled card and the title is
    /// only reachable through redo and Restore from Trash. `deleteTask` has
    /// always done this; `trashTask` wraps it in a step of its own, whose
    /// snapshot is the one ⌘Z actually restores.
    @Test func trashingACardWhoseSessionEmptiedTheTitleKeepsTheTitleForUndo() {
        let (store, undo) = TestBoard.undoing()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("", field: .title, on: TestBoard.cafe)

        step(undo) { store.trashTask(TestBoard.cafe) }
        undo.undo()

        #expect(store[TestBoard.cafe]?.title == "Café menu polish",
                "⌘Z restored the blank the open session had left in the title")
    }

    /// And the selection path, which restored inside the step — after the
    /// snapshot — for as long as the single-card path restored before it.
    @Test func trashingASelectionWhoseSessionEmptiedATitleKeepsTheTitleForUndo() {
        let (store, undo) = TestBoard.undoing()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("", field: .title, on: TestBoard.cafe)

        step(undo) { store.trashTasks([TestBoard.cafe, TestBoard.dragDrop]) }
        undo.undo()

        #expect(store[TestBoard.cafe]?.title == "Café menu polish",
                "⌘Z restored the blank the open session had left in the title")
    }

    @Test func namingATaskThatNeverHadATitleIsNotARename() {
        let store = TestBoard.store()
        let id = store.addTask(to: BoardColumn.inbox.id, title: "", fromPhone: true, log: .captured)
        store.beginEditing(.title, on: id, scope: .sheet)
        store.setText("Finally named", field: .title, on: id)
        store.endEditing(.title, on: id, scope: .sheet)
        #expect(store[id]?.title == "Finally named")
        #expect(kinds(store, id) == [.captured])
    }

    @Test func aPastedParagraphBecomesOneLine() {
        let store = TestBoard.store()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("  Ship\n\tthe   menu \n", field: .title, on: TestBoard.cafe)
        // Folded as it is typed, so a card never renders a newline…
        #expect(store[TestBoard.cafe]?.title == " Ship the menu ")
        store.endEditing(.title, on: TestBoard.cafe, scope: .desk)
        // …and trimmed at the ends only on commit, so a trailing space can still
        // be the space before the next word.
        #expect(store[TestBoard.cafe]?.title == "Ship the menu")
        #expect(renames(store, TestBoard.cafe) == 1)
    }

    // MARK: Descriptions

    @Test func aDescriptionSaysWhetherItWasWrittenOrRewritten() {
        let store = TestBoard.store()
        store.beginEditing(.note, on: TestBoard.cafe, scope: .desk)     // cafe has no note
        store.setText("First words", field: .note, on: TestBoard.cafe)
        store.endEditing(.note, on: TestBoard.cafe, scope: .desk)
        #expect(kinds(store, TestBoard.cafe).first == .descriptionAdded)

        store.beginEditing(.note, on: TestBoard.cafe, scope: .desk)
        store.setText("Second thoughts", field: .note, on: TestBoard.cafe)
        store.endEditing(.note, on: TestBoard.cafe, scope: .desk)
        #expect(kinds(store, TestBoard.cafe).first == .descriptionUpdated)
    }

    @Test func aDescriptionKeepsItsLineBreaks() {
        let store = TestBoard.store()
        store.setText("One\n\nTwo", field: .note, on: TestBoard.cafe)
        #expect(store[TestBoard.cafe]?.note == "One\n\nTwo")
    }

    // MARK: Pickers

    @Test func fourDatesTriedLeaveOneLine() {
        let store = TestBoard.store()
        let final = CalendarDay(year: 2026, month: 12, day: 25)
        store.beginEditing(.due, on: TestBoard.cafe, scope: .desk)
        for day in [CalendarDay(year: 2026, month: 9, day: 1),
                    CalendarDay(year: 2026, month: 10, day: 1),
                    CalendarDay(year: 2026, month: 11, day: 1),
                    final] {
            store.setDue(day, on: TestBoard.cafe, scope: .desk)
        }
        store.endEditing(.due, on: TestBoard.cafe, scope: .desk)
        #expect(store[TestBoard.cafe]?.due == final)
        #expect(kinds(store, TestBoard.cafe) == [.dueSet(final), .created])
    }

    @Test func aPickerThatWandersAndComesHomeTakesItsLineBack() {
        let store = TestBoard.store()
        let original = TestBoard.dueDay
        store.beginEditing(.due, on: TestBoard.dragDrop, scope: .desk)
        store.setDue(CalendarDay(year: 2026, month: 9, day: 9), on: TestBoard.dragDrop, scope: .desk)
        store.setDue(original, on: TestBoard.dragDrop, scope: .desk)
        store.endEditing(.due, on: TestBoard.dragDrop, scope: .desk)
        #expect(store[TestBoard.dragDrop]?.due == original)
        #expect(kinds(store, TestBoard.dragDrop) == [.created])
    }

    @Test func aChangeUnderAnOpenSessionIsStillRecordedIfTheSessionIsAbandoned() {
        // "A session is open" must never mean "this change is not worth
        // remembering": the surface can walk away without ever ending it.
        let store = TestBoard.store()
        store.beginEditing(.priority, on: TestBoard.cafe, scope: .desk)
        store.setPriority(.high, on: TestBoard.cafe, scope: .desk)
        #expect(kinds(store, TestBoard.cafe).first == .prioritySet(.high))
    }

    @Test func aPickerSessionRewritesItsOwnLineRatherThanAddingOne() {
        let store = TestBoard.store()
        store.beginEditing(.priority, on: TestBoard.cafe, scope: .desk)
        store.setPriority(.high, on: TestBoard.cafe, scope: .desk)
        let entryID = store[TestBoard.cafe]?.activity.first?.id
        store.setPriority(.medium, on: TestBoard.cafe, scope: .desk)
        #expect(kinds(store, TestBoard.cafe) == [.prioritySet(.medium), .created])
        #expect(store[TestBoard.cafe]?.activity.first?.id == entryID)
    }

    // MARK: Scoping

    @Test func oneSurfacesSessionNeverSilencesTheOther() {
        // The inspector has the due picker open; the sheet changes the same
        // task's date. The sheet's change is its own line.
        let store = TestBoard.store()
        store.beginEditing(.due, on: TestBoard.dragDrop, scope: .desk)
        store.setDue(CalendarDay(year: 2026, month: 9, day: 9), on: TestBoard.dragDrop, scope: .sheet)
        #expect(kinds(store, TestBoard.dragDrop).first == .dueSet(CalendarDay(year: 2026, month: 9, day: 9)))
        store.endEditing(.due, on: TestBoard.dragDrop, scope: .desk)
        // …and ending the inspector's session does not add a second one.
        #expect(kinds(store, TestBoard.dragDrop).count == 2)
    }

    @Test func endingASessionTheOtherSurfaceNeverOpenedDoesNothing() {
        let store = TestBoard.store()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("Renamed on the desk", field: .title, on: TestBoard.cafe)
        store.endEditing(.title, on: TestBoard.cafe, scope: .sheet)
        #expect(renames(store, TestBoard.cafe) == 0)
        store.endEditing(.title, on: TestBoard.cafe, scope: .desk)
        #expect(renames(store, TestBoard.cafe) == 1)
    }

    @Test func sessionsAreKeyedPerTask() {
        let store = TestBoard.store()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        #expect(store.isEditing(.title, on: TestBoard.cafe, scope: .desk))
        #expect(store.isEditing(.title, on: TestBoard.dragDrop, scope: .desk) == false)
        #expect(store.isEditing(.title, on: TestBoard.cafe, scope: .sheet) == false)
        #expect(store.isEditing(.note, on: TestBoard.cafe, scope: .desk) == false)

        // A change to another task under this session is logged at once.
        store.setPriority(.low, on: TestBoard.dragDrop, scope: .desk)
        #expect(kinds(store, TestBoard.dragDrop).first == .prioritySet(.low))
    }

    @Test func movingTheSelectionEndsWhatTheSurfaceLeftOpen() {
        let store = TestBoard.store()
        store.selectedID = TestBoard.cafe
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("Left half typed", field: .title, on: TestBoard.cafe)
        store.selectedID = TestBoard.dragDrop
        #expect(store.isEditing(.title, on: TestBoard.cafe, scope: .desk) == false)
        #expect(renames(store, TestBoard.cafe) == 1)
    }

    @Test func dismissingTheSheetEndsWhatTheSheetLeftOpen() {
        let store = TestBoard.store()
        store.sheetID = TestBoard.cafe
        store.beginEditing(.title, on: TestBoard.cafe, scope: .sheet)
        store.setText("", field: .title, on: TestBoard.cafe)
        store.sheetID = nil
        // An abandoned empty title still has to come back.
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
        #expect(store.isEditing(.title, on: TestBoard.cafe, scope: .sheet) == false)
    }

    @Test func movingOneSurfaceLeavesTheOtherSurfacesSessionOpen() {
        // The sessions are keyed by surface so both can be open at once, and a
        // selection change has to end only the ones its own surface left
        // behind. Existing coverage calls `endEditing` directly; this is the
        // path a `didSet` takes, which is the one that can reach too far.
        let store = TestBoard.store()
        store.sheetID = TestBoard.cafe
        store.beginEditing(.title, on: TestBoard.cafe, scope: .sheet)
        store.setText("Half typed on the phone", field: .title, on: TestBoard.cafe)

        store.selectedID = TestBoard.dragDrop        // the inspector moves; the sheet has not
        #expect(store.isEditing(.title, on: TestBoard.cafe, scope: .sheet))
        #expect(renames(store, TestBoard.cafe) == 0)

        // The phone finishes its own sentence, and that is the one line logged.
        store.endEditing(.title, on: TestBoard.cafe, scope: .sheet)
        #expect(store[TestBoard.cafe]?.title == "Half typed on the phone")
        #expect(renames(store, TestBoard.cafe) == 1)
    }

    @Test func dismissingTheSheetLeavesTheInspectorsSessionOpen() {
        // The same rule the other way round, so neither surface is the one that
        // happens to be spelled first in the filter.
        let store = TestBoard.store()
        store.selectedID = TestBoard.cafe
        store.beginEditing(.note, on: TestBoard.cafe, scope: .desk)
        store.setText("Written at the desk", field: .note, on: TestBoard.cafe)

        store.sheetID = TestBoard.dragDrop
        store.sheetID = nil
        #expect(store.isEditing(.note, on: TestBoard.cafe, scope: .desk))
        #expect(kinds(store, TestBoard.cafe).contains(.descriptionAdded) == false)
    }

    @Test func beginningATwiceOpenSessionKeepsTheFirstBeforeValue() {
        let store = TestBoard.store()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("Halfway", field: .title, on: TestBoard.cafe)
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)     // refocus, same session
        store.setText("", field: .title, on: TestBoard.cafe)
        store.endEditing(.title, on: TestBoard.cafe, scope: .desk)
        // Restored to where the *session* started, not to the second begin.
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
    }

    // MARK: Sub-tasks

    @Test func aSubTaskRenameIsOneEntryPerSession() {
        let store = TestBoard.store()
        store.beginEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard)
        for text in ["K", "Ke", "Keyboard route"] {
            store.updateSubtask(TestBoard.keyboard, text: text, on: TestBoard.dragDrop)
        }
        store.endEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard)
        #expect(store.subtaskText(TestBoard.keyboard, on: TestBoard.dragDrop) == "Keyboard route")
        #expect(kinds(store, TestBoard.dragDrop).count { $0 == .subtaskRenamed } == 1)
    }

    @Test func aSubTaskEmptiedToNothingIsRestoredRatherThanDeleted() {
        let store = TestBoard.store()
        store.beginEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard)
        store.updateSubtask(TestBoard.keyboard, text: "   ", on: TestBoard.dragDrop)
        store.endEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard)
        #expect(store.subtaskText(TestBoard.keyboard, on: TestBoard.dragDrop) == "Keyboard fallback")
        #expect(store[TestBoard.dragDrop]?.subtasks.count == 3)
    }

    @Test func sessionsOnTwoSubTasksOfOneTaskAreIndependent() {
        let store = TestBoard.store()
        store.beginEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard)
        #expect(store.isEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard))
        #expect(store.isEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.lift) == false)
        #expect(store.isEditing(.subtask, on: TestBoard.dragDrop, scope: .desk) == false)
    }

    @Test func deletingASubTaskUnderAnOpenSessionLogsNoRename() {
        // The row's `TextField` is still focused when the delete lands, and the
        // blur that follows ends the session. Ended against a sub-task that is
        // no longer there it reads an empty string, calls that a change, and
        // files a rename for a row the user has just thrown away.
        let store = TestBoard.store()
        store.beginEditing(.subtask, on: TestBoard.dragDrop, scope: .sheet, subtask: TestBoard.lift)
        store.updateSubtask(TestBoard.lift, text: "Lift and shadow states, redone", on: TestBoard.dragDrop)
        store.deleteSubtask(TestBoard.lift, from: TestBoard.dragDrop)
        #expect(store.isEditing(.subtask, on: TestBoard.dragDrop, scope: .sheet, subtask: TestBoard.lift) == false)

        store.endEditing(.subtask, on: TestBoard.dragDrop, scope: .sheet, subtask: TestBoard.lift)
        #expect(kinds(store, TestBoard.dragDrop).count { $0 == .subtaskRenamed } == 0)
        #expect(kinds(store, TestBoard.dragDrop).first == .subtaskRemoved)
        #expect(store[TestBoard.dragDrop]?.subtasks.count == 2)
    }

    @Test func deletingOneSubTaskLeavesTheSessionOnAnother() {
        // The cleanup is keyed on the row, not on the task: a checklist with two
        // fields open must not lose the other one's session to a delete.
        let store = TestBoard.store()
        store.beginEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard)
        store.deleteSubtask(TestBoard.lift, from: TestBoard.dragDrop)
        #expect(store.isEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard))

        store.updateSubtask(TestBoard.keyboard, text: "Keyboard route", on: TestBoard.dragDrop)
        store.endEditing(.subtask, on: TestBoard.dragDrop, scope: .desk, subtask: TestBoard.keyboard)
        #expect(kinds(store, TestBoard.dragDrop).count { $0 == .subtaskRenamed } == 1)
    }

    @Test func textReadsWhicheverFieldItIsAsked() {
        let store = TestBoard.store()
        #expect(store.text(.title, on: TestBoard.cafe) == "Café menu polish")
        #expect(store.text(.note, on: TestBoard.dragDrop) == "Card follows the pointer with a lifted shadow.")
        #expect(store.text(.subtask, on: TestBoard.dragDrop, subtask: TestBoard.lift) == "Lift and shadow states")
        #expect(store.text(.due, on: TestBoard.dragDrop) == "")
        #expect(store.text(.title, on: UUID()) == "")
    }
}
