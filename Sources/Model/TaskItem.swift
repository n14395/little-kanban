import Foundation

struct SubTask: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var text: String
    var done: Bool = false
}

struct ActivityEntry: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var text: String
    var when: String
}

struct TaskItem: Identifiable, Hashable, Codable, Sendable {
    var id: String
    /// The human-facing ticket reference, e.g. `NW-118`.
    var code: String
    var columnID: BoardColumn.ID
    var title: String
    var note: String = ""
    var labelKeys: [String] = []
    /// Kept as the spec's free-text relative day ("Today", "Thu", "Next week").
    /// See README — this is the first thing to swap for a real `Date`.
    var due: String = ""
    var priority: Priority = .medium
    var subtasks: [SubTask] = []
    var activity: [ActivityEntry] = []

    var completedSubtaskCount: Int { subtasks.filter(\.done).count }
    var hasSubtasks: Bool { !subtasks.isEmpty }
    var subtaskProgressText: String { "\(completedSubtaskCount)/\(subtasks.count)" }
    var subtaskFraction: Double {
        subtasks.isEmpty ? 0 : Double(completedSubtaskCount) / Double(subtasks.count)
    }

    /// Fields the board search matches against, mirroring the spec's filter.
    var searchHaystack: String {
        "\(title) \(note) \(code) \(labelKeys.joined(separator: " "))".lowercased()
    }
}
