import Foundation
import Testing
@testable import Simple_Kanban

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
