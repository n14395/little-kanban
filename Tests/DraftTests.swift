import Foundation
import Testing
@testable import LittleKanban

/// Half-typed text belongs to the task it was typed against, not just to the
/// surface it was typed on: the inspector and the sheet can be open on
/// different tasks at once, and a draft that follows the surface lands on the
/// wrong task.
@MainActor
@Suite struct DraftTests {
    @Test func aSubTaskDraftIsPerSurfaceAndPerTask() {
        let store = TestBoard.store()
        store.setSubtaskDraft("desk on cafe", for: .desk, task: TestBoard.cafe)
        #expect(store.subtaskDraft(for: .desk, task: TestBoard.cafe) == "desk on cafe")
        #expect(store.subtaskDraft(for: .sheet, task: TestBoard.cafe).isEmpty)
        #expect(store.subtaskDraft(for: .desk, task: TestBoard.dragDrop).isEmpty)
    }

    @Test func aLabelDraftIsPerSurfaceAndPerTask() {
        let store = TestBoard.store()
        store.setLabelDraft("infra", for: .sheet, task: TestBoard.cafe)
        #expect(store.labelDraft(for: .sheet, task: TestBoard.cafe) == "infra")
        #expect(store.labelDraft(for: .desk, task: TestBoard.cafe).isEmpty)
        #expect(store.labelDraft(for: .sheet, task: TestBoard.dragDrop).isEmpty)
    }

    @Test func committingASubTaskClearsOnlyTheSurfaceThatTypedIt() {
        let store = TestBoard.store()
        store.setSubtaskDraft("From the desk", for: .desk, task: TestBoard.cafe)
        store.setSubtaskDraft("mid-sen", for: .sheet, task: TestBoard.cafe)
        store.commitSubtaskDraft(for: .desk, task: TestBoard.cafe)

        #expect(store[TestBoard.cafe]?.subtasks.map(\.text) == ["From the desk"])
        #expect(store.subtaskDraft(for: .desk, task: TestBoard.cafe).isEmpty)
        #expect(store.subtaskDraft(for: .sheet, task: TestBoard.cafe) == "mid-sen")
    }

    @Test func committingALabelClearsOnlyTheSurfaceThatTypedIt() {
        let store = TestBoard.store()
        store.setLabelDraft("Infra Work", for: .desk, task: TestBoard.cafe)
        store.setLabelDraft("half", for: .sheet, task: TestBoard.cafe)
        store.commitLabelDraft(for: .desk, task: TestBoard.cafe)

        #expect(store[TestBoard.cafe]?.labelKeys == ["polish", "infra-work"])
        #expect(store.labelDraft(for: .desk, task: TestBoard.cafe).isEmpty)
        #expect(store.labelDraft(for: .sheet, task: TestBoard.cafe) == "half")
    }

    /// **A draft that loses the field is committed, and Return does both.**
    ///
    /// The checklist's draft field commits when it stops holding the keyboard as
    /// well as when Return is pressed — a row somebody typed and then tapped away
    /// from was being abandoned to a draft nobody could see was still there. See
    /// `theChecklistDraftIsCommittedWhenItLosesTheField` for the wiring.
    ///
    /// What that makes the store answerable for is *this*: Return commits and
    /// then the field resigns, so the commit arrives twice for one sub-task. The
    /// second has to add nothing, which it does by finding the draft the first
    /// one emptied. A commit that re-added its text would put every sub-task
    /// typed on the list twice, and nothing else in here would notice.
    @Test func committingADraftTwiceAddsOneSubTask() {
        let store = TestBoard.store()
        store.setSubtaskDraft("Ring the printer", for: .sheet, task: TestBoard.cafe)
        store.commitSubtaskDraft(for: .sheet, task: TestBoard.cafe)
        store.commitSubtaskDraft(for: .sheet, task: TestBoard.cafe)

        #expect(store[TestBoard.cafe]?.subtasks.map(\.text) == ["Ring the printer"])
        #expect(store.subtaskDraft(for: .sheet, task: TestBoard.cafe).isEmpty)
    }

    /// **The wiring**, which only the source can say: a `@FocusState` cannot be
    /// driven from here, and `commitSubtaskDraft` answers the same whether or
    /// not anything is calling it when the field goes.
    ///
    /// Read off the *masked* source — comments and string literals are blanked —
    /// so the note above the watcher explaining itself cannot satisfy it.
    ///
    /// Two commits in the file and no more: Return's and the field's. A third
    /// would be the draft being committed somewhere it has not been emptied
    /// first, which is how one typed line becomes two rows.
    @Test func theChecklistDraftIsCommittedWhenItLosesTheField() {
        guard SourceTree.isReachable else { return }
        guard let file = SourceTree.files().first(where: { $0.path == "Shared/ChecklistView.swift" })
        else {
            Issue.record("the checklist has moved file")
            return
        }
        let code = file.source
        #expect(code.contains("onChange(of: isDraftFocused)"),
                "the checklist's draft field is not watched for losing focus")
        #expect(code.contains("guard !isFocused"),
                "the draft is committed on *gaining* the field as well as on losing it")

        let commits = code.components(separatedBy: "commitSubtaskDraft").count - 1
        #expect(commits == 2,
                "the checklist commits its draft from \(commits) places; there are two")
    }

    @Test func anEmptyDraftCommitsNothing() {
        let store = TestBoard.store()
        store.setSubtaskDraft("   ", for: .desk, task: TestBoard.cafe)
        store.commitSubtaskDraft(for: .desk, task: TestBoard.cafe)
        #expect(store[TestBoard.cafe]?.subtasks.isEmpty == true)

        store.setLabelDraft("  ", for: .desk, task: TestBoard.cafe)
        store.commitLabelDraft(for: .desk, task: TestBoard.cafe)
        #expect(store[TestBoard.cafe]?.labelKeys == ["polish"])
        #expect(store.labels.count == LabelDef.seed.count)
    }

    @Test func deletingATaskTakesItsDraftsWithIt() {
        let store = TestBoard.store()
        store.setSubtaskDraft("half typed", for: .desk, task: TestBoard.cafe)
        store.setLabelDraft("half typed", for: .sheet, task: TestBoard.cafe)
        store.setSubtaskDraft("untouched", for: .desk, task: TestBoard.dragDrop)

        store.deleteTask(TestBoard.cafe)
        #expect(store.subtaskDraft(for: .desk, task: TestBoard.cafe).isEmpty)
        #expect(store.labelDraft(for: .sheet, task: TestBoard.cafe).isEmpty)
        #expect(store.subtaskDraft(for: .desk, task: TestBoard.dragDrop) == "untouched")
    }

    @Test func openingAndClosingTheLabelPickerResetsThatSurfacesDraft() {
        let store = TestBoard.store()
        store.setLabelDraft("stale", for: .desk, task: TestBoard.cafe)
        store.setLabelDraft("kept", for: .sheet, task: TestBoard.cafe)

        store.toggleLabelPicker(.desk, task: TestBoard.cafe)
        #expect(store.labelPickerScope == .desk)
        #expect(store.labelDraft(for: .desk, task: TestBoard.cafe).isEmpty)
        #expect(store.labelDraft(for: .sheet, task: TestBoard.cafe) == "kept")

        store.setLabelDraft("typed again", for: .desk, task: TestBoard.cafe)
        store.closeLabelPicker(.desk, task: TestBoard.cafe)
        #expect(store.labelPickerScope == nil)
        #expect(store.labelDraft(for: .desk, task: TestBoard.cafe).isEmpty)
    }

    @Test func togglingThePickerASecondTimeClosesIt() {
        let store = TestBoard.store()
        store.toggleLabelPicker(.sheet, task: TestBoard.cafe)
        store.toggleLabelPicker(.sheet, task: TestBoard.cafe)
        #expect(store.labelPickerScope == nil)
    }
}
