import Foundation

/// One column of the board. `short` is the abbreviated name used by the
/// "move to" segmented control, where horizontal room is tight.
struct BoardColumn: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let short: String
    let dot: SwatchColor
}

extension BoardColumn {
    /// The capture column. It sits outside the workflow: it is shown on the
    /// macOS board and the iOS Inbox tab, but never in the column pager or the
    /// "move to" control.
    static let inbox = BoardColumn(id: "inbox", name: "Inbox", short: "Inbox", dot: .ink(opacity: 0.35))

    static let backlog = BoardColumn(id: "backlog", name: "Backlog", short: "Backlog", dot: .hex(0xA8A29A))
    static let upNext = BoardColumn(id: "next", name: "Up Next", short: "Up Next", dot: .hex(0xC98A16))
    static let inProgress = BoardColumn(id: "doing", name: "In Progress", short: "Doing", dot: .hex(0xC2532F))
    static let done = BoardColumn(id: "done", name: "Done", short: "Done", dot: .hex(0x1F6F63))

    /// The four workflow columns, in board order.
    static let workflow: [BoardColumn] = [backlog, upNext, inProgress, done]

    /// Every column the macOS board renders, Inbox first.
    static let all: [BoardColumn] = [inbox] + workflow

    static func column(id: String) -> BoardColumn? { all.first { $0.id == id } }
}
