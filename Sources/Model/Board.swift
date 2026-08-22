import Foundation

/// Where a task sits: unfiled in the global Inbox, or on a board in one of its
/// columns.
///
/// One value rather than two nullable fields, because the pair `boardID` /
/// `columnID` has exactly two legal shapes and every other combination — "on a
/// board, in no column", "in a column, on no board" — is a bug that would only
/// show up as a card nobody can find. There is no way to spell those here, and
/// `TaskItem.placement` is the only thing that writes the two fields, so they
/// cannot drift apart.
enum TaskPlacement: Hashable, Sendable {
    /// The global Inbox. Global rather than per board because a quick capture
    /// must never have to pick a board first.
    case inbox
    case column(board: Board.ID, column: BoardColumn.ID)

    var boardID: Board.ID? {
        switch self {
        case .inbox: nil
        case .column(let board, _): board
        }
    }

    var columnID: BoardColumn.ID? {
        switch self {
        case .inbox: nil
        case .column(_, let column): column
        }
    }

    var isInbox: Bool { self == .inbox }
}

/// One board: a name, a colour, and the columns work moves through.
///
/// The columns live here rather than on the store because they are the board's
/// own — switching boards changes them, and two boards may share neither names
/// nor count nor roles.
struct Board: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var dot: SwatchColor
    var createdAt: Date = .now
    var columns: [BoardColumn]
    /// The prefix on task codes, e.g. "NW" in "NW-118". A label, not a key: it
    /// is stamped onto a task's code when the task is created and never read
    /// back, so changing it renumbers nothing.
    var codePrefix: String

    func column(id: BoardColumn.ID) -> BoardColumn? { columns.first { $0.id == id } }

    /// Where a card lands when it is filed onto this board without being told
    /// where: the first column work can start in. A board whose every column is
    /// Done — which column management refuses to make, but a hand-edited file
    /// can still arrive as — falls back to the first one it has.
    var landingColumn: BoardColumn? {
        columns.first { $0.role != .done } ?? columns.first
    }
}

extension Board {
    /// The prefix a task minted in the Inbox carries. Constant because the
    /// Inbox is not a board and has no prefix of its own to take, and because a
    /// code never changes once minted — filing an "IN-141" onto a board leaves
    /// it called IN-141, since by then it may be in someone's commit message.
    static let inboxCodePrefix = "IN"

    /// What a board mints with when it is given nothing better.
    static let defaultCodePrefix = "NW"

    /// The Inbox's name and dot. It stopped being a `BoardColumn` when it
    /// became global, so there is nowhere else for a surface to read them from.
    static var inboxName: String {
        String(localized: "Inbox", comment: "The global capture list, shown above the boards")
    }

    static let inboxDot: SwatchColor = .ink(opacity: 0.35)

    /// A board name as it is stored: one line, trimmed, and capped where a
    /// sidebar row stops being able to show it.
    static func name(_ raw: String) -> String {
        String(
            raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
                .prefix(nameLimit)
        ).trimmingCharacters(in: .whitespaces)
    }

    /// A code prefix as it is stored: letters and digits, upper-cased, and
    /// short enough to leave room for the number beside it on a card.
    ///
    /// An empty one falls back to initials from the board's name, and then to
    /// `defaultCodePrefix`, because a board that cannot mint a code is a board
    /// no task can be added to.
    static func codePrefix(_ raw: String, fallingBackTo name: String) -> String {
        let cleaned = String(raw.uppercased().filter(\.isLetterOrDigit).prefix(codePrefixLimit))
        if !cleaned.isEmpty { return cleaned }
        let initials = name
            .split(whereSeparator: \.isWhitespace)
            .compactMap { $0.first(where: \.isLetterOrDigit) }
            .prefix(codePrefixLimit)
        let derived = String(initials).uppercased()
        return derived.isEmpty ? defaultCodePrefix : derived
    }

    /// One dot on offer, and what it is called.
    ///
    /// A colour picked by eye is picked by index to anyone who cannot see it,
    /// and "Colour 4" says nothing about what choosing it does. The name is the
    /// swatch's only description on either surface, so it lives beside the
    /// colour rather than in whichever view happens to draw it.
    struct Dot: Identifiable, Hashable, Sendable {
        var swatch: SwatchColor
        var name: String

        var id: SwatchColor { swatch }
    }

    /// The dots a board or a column can be given.
    ///
    /// `LabelDef.palette`'s counterpart for the two things that carry a single
    /// dot rather than a background/foreground pair. One list on the model
    /// rather than one per surface, because the two surfaces recolour the same
    /// property: a board coloured on the phone has to be recolourable back to
    /// the same colour on the desk.
    ///
    /// Six, because that is a row of 44pt targets on the narrowest phone with
    /// no spacing left to give away — and the six are chosen so every dot the
    /// seed workflow ships with is among them, so a column can always be put
    /// back the way it arrived. `inboxDot` is deliberately not offered: a board
    /// wearing the Inbox's grey in the same sidebar list is a puzzle, not a
    /// choice.
    ///
    /// The last three are the accent themes' own hexes, so they take the accent
    /// themes' names: one vocabulary for one colour, whichever control is
    /// offering it. The first is `.accent` itself — the one dot that follows the
    /// theme instead of naming a colour, which is why it is the one called
    /// "Accent" rather than whatever it currently resolves to.
    static var dots: [Dot] {
        [
            Dot(swatch: .accent,
                name: String(localized: "Accent", comment: "Board dot colour that follows the accent theme")),
            Dot(swatch: .hex(0xA8A29A),
                name: String(localized: "Stone", comment: "Board dot colour: warm grey")),
            Dot(swatch: .hex(0xC98A16),
                name: String(localized: "Amber", comment: "Board dot colour: golden yellow")),
            Dot(swatch: .hex(0xC2532F),
                name: String(localized: "Ember", comment: "Board dot colour: burnt orange")),
            Dot(swatch: .hex(0x1F6F63),
                name: String(localized: "Pine", comment: "Board dot colour: deep green")),
            Dot(swatch: .hex(0x3B5BA9),
                name: String(localized: "Indigo", comment: "Board dot colour: deep blue")),
        ]
    }

    static var dotPalette: [SwatchColor] { dots.map(\.swatch) }

    /// The columns a new board starts with: the seed workflow, with ids of its
    /// own.
    ///
    /// Fresh ids rather than the seed's, because a column id is what places a
    /// card — two boards sharing one would draw each other's cards, and
    /// deleting the column on either would move both boards' cards.
    static func startingColumns() -> [BoardColumn] {
        BoardColumn.workflow.map { column in
            var column = column
            column.id = UUID()
            return column
        }
    }

    static let nameLimit = 60
    static let codePrefixLimit = 4
}

private extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}
