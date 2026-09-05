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

/// A board column in flight, dragged by its name to be re-ordered.
///
/// Carries its board for `SubtaskTransfer`'s reason: `moveColumn` is defined
/// over the *active* board, and on macOS a second window can be showing another
/// one. A column dropped across that gap would name an index in a list it is
/// not in.
struct ColumnTransfer: Codable, Transferable, Sendable {
    var boardID: Board.ID
    var columnID: BoardColumn.ID
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .simpleKanbanColumn)
        ProxyRepresentation(exporting: \.name)
    }
}

extension ColumnTransfer {
    init(_ column: BoardColumn, on boardID: Board.ID) {
        self.init(boardID: boardID, columnID: column.id, name: column.name)
    }
}

/// A label row in flight, dragged inside the manager to re-order the
/// vocabulary. The key is the identity every task stores; the name is what a
/// row dropped into a text editor leaves behind.
struct LabelTransfer: Codable, Transferable, Sendable {
    var key: String
    var name: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .simpleKanbanLabel)
        ProxyRepresentation(exporting: \.name)
    }
}

extension LabelTransfer {
    init(_ label: LabelDef) {
        self.init(key: label.key, name: label.name)
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
        exportedAs: "com.n14395.Cardstock.task", conformingTo: .data
    )
    static let simpleKanbanSubtask = UTType(
        exportedAs: "com.n14395.Cardstock.subtask", conformingTo: .data
    )
    static let simpleKanbanColumn = UTType(
        exportedAs: "com.n14395.Cardstock.column", conformingTo: .data
    )
    static let simpleKanbanLabel = UTType(
        exportedAs: "com.n14395.Cardstock.label", conformingTo: .data
    )
}
