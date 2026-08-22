import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// What a card carries while it is being dragged, and what ⌘C will put on the
/// pasteboard.
///
/// A typed payload rather than the id as a bare `String`: a column that accepts
/// `String` lights up for a URL dragged out of Safari and for any word dragged
/// out of a text field, and then has to decide at drop time that it did not mean
/// it. The board's own type simply is not offered by anything else.
struct TaskTransfer: Codable, Transferable, Sendable {
    var id: TaskItem.ID
    var title: String
    var code: String

    /// `NW-118 Drag-and-drop between columns` — what a card dropped into a text
    /// editor leaves behind.
    var plainText: String { "\(code) \(title)" }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .simpleKanbanTask)
        ProxyRepresentation(exporting: \.plainText)
    }
}

extension TaskTransfer {
    /// `displayTitle` rather than `title`, so a card dragged out before it was
    /// named leaves a line that says something.
    init(_ task: TaskItem) {
        self.init(id: task.id, title: task.displayTitle, code: task.code)
    }
}

/// A checklist row in flight. Carries its task so a row dragged out of the
/// inspector cannot land in the sheet's checklist for a different task.
struct SubtaskTransfer: Codable, Transferable, Sendable {
    var taskID: TaskItem.ID
    var subtaskID: SubTask.ID
    var text: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .simpleKanbanSubtask)
        ProxyRepresentation(exporting: \.text)
    }
}

extension SubtaskTransfer {
    init(_ subtask: SubTask, on taskID: TaskItem.ID) {
        self.init(taskID: taskID, subtaskID: subtask.id, text: subtask.text)
    }
}

extension UTType {
    /// Both state their conformance twice: here, and in the app's Info.plist
    /// (`project.yml` → `UTExportedTypeDeclarations`).
    ///
    /// The plist declaration is the one the system reads, but it is not the one
    /// that can be relied on in isolation — an exported type the running bundle
    /// has not declared resolves to one that conforms to nothing at all, which
    /// is not a shape to leave a drag payload in. Saying it here as well means
    /// the payload keeps working whatever the bundle around it is doing.
    ///
    /// Note that `conforms(to:)` cannot be used to check the two agree:
    /// `UTType` resolves an exported identifier through LaunchServices, which
    /// remembers every build of this app that ever ran, so it answers yes long
    /// after the declaration has gone. `TransferTests` reads the bundle's plist
    /// directly instead.
    static let simpleKanbanTask = UTType(
        exportedAs: "com.n14395.SimpleKanban.task", conformingTo: .data
    )
    static let simpleKanbanSubtask = UTType(
        exportedAs: "com.n14395.SimpleKanban.subtask", conformingTo: .data
    )
}
