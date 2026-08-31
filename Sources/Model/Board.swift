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

/// One board: a name, an icon, and the columns work moves through.
///
/// The columns live here rather than on the store because they are the board's
/// own — switching boards changes them, and two boards may share neither names
/// nor count nor order.
struct Board: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// The SF Symbol the sidebar row, the destination pill and the widget's
    /// heading wear — a saved view's ``SavedView/symbol`` exactly, and for the
    /// same reason it is a name rather than a case: what a board is *of* is the
    /// user's to say, and the vocabulary for that is the system's whole symbol
    /// set rather than a list this app could think of in advance.
    ///
    /// **This was a colour until v16.** Six dots said which board a row was for
    /// and nothing about what the board was, two of them were hard to tell
    /// apart at 7pt, and a reader who cannot see colour was told the board's
    /// position in a list. A glyph says both — see ``SymbolCatalog`` for what
    /// can be picked and ``SymbolMark`` for what is drawn when a synced name is
    /// one this system has never heard of.
    var symbol: String = SymbolMark.boardFallback
    var createdAt: Date = .now
    var columns: [BoardColumn]
    /// The prefix on task codes, e.g. "NW" in "NW-118". A label, not a key: it
    /// is stamped onto a task's code when the task is created and never read
    /// back, so changing it renumbers nothing.
    var codePrefix: String

    func column(id: BoardColumn.ID) -> BoardColumn? { columns.first { $0.id == id } }

    /// **Where finished work lives: the last column, always.**
    ///
    /// This is the whole of the rule. Up to v8 each column carried a
    /// `ColumnRole` and the Done column was the first one whose role said so —
    /// which allowed a board to have two of them, where only the first counted,
    /// a distinction invisible everywhere in the app except the warning that had
    /// to be put in front of a reorder.
    ///
    /// Position rather than a stored `doneColumnID` because a stored id needs a
    /// fallback for the case where it names a column that has gone, and the only
    /// sensible fallback is "the last one" — so the id would exist purely to let
    /// somebody put Done in the *middle* of their board, which is not a thing a
    /// board is for. Deriving it means there is no field to get out of step with
    /// the array, nothing to migrate forward, and nothing to keep in sync.
    ///
    /// It is not deletable and not re-orderable — see `BoardStore.deleteColumn`
    /// and `moveColumn`, which is what makes reading it off the position safe.
    /// It is still an ordinary column otherwise: renameable and recolourable,
    /// because "Done" is called Shipped, Live and Published on real boards, and
    /// `SeedData.contentCalendar` already ships one called Published.
    ///
    /// `nil` only for a board with no columns at all, which nothing in the app
    /// makes any more — a board arrives holding this column and the settings
    /// sheet is where the rest are added in front of it — but which an import or
    /// a hand-edited file can still be.
    var doneColumn: BoardColumn? { columns.last }

    /// Every column before Done — the ones work actually moves through.
    ///
    /// What the "move to" control offers, and what a card can be filed into
    /// without being finished by the act of filing it. **Empty on a board that
    /// has only just been made**, which is the state every board starts in: it
    /// has somewhere to finish and nowhere to work yet, and the board surface
    /// asks for a column rather than for a card until it has one.
    var workingColumns: [BoardColumn] { Array(columns.dropLast()) }

    /// Where a card lands when it is filed onto this board without being told
    /// where: the first column work can start in.
    ///
    /// `nil` for a board that has no working column — one that is empty, or that
    /// holds nothing but its Done column. Both mean the same thing to a caller
    /// ("this board is not set up yet"), and both must refuse the card rather
    /// than land it: a card dropped onto a bare board and landed in Done would
    /// arrive already completed.
    var landingColumn: BoardColumn? { workingColumns.first }
}

// MARK: - Reading an older board

/// **In an extension, not in the body.** An initialiser written inside the
/// struct takes the memberwise one away with it, and the memberwise one is how
/// every board in the app, the seed and the suite is made.
extension Board {
    /// Spelled out rather than synthesised, for one field.
    ///
    /// A board written before v16 carries a `dot` and no `symbol`, and a
    /// synthesised decoder throws `keyNotFound` for a key that is not there —
    /// **a property default does not save you.** `BoardSnapshot.init(from:)` is
    /// written for exactly this reason and says so at length.
    ///
    /// The default it lands on is a placeholder rather than an answer: every
    /// board in a pre-v16 file is dealt a mark of its own by
    /// ``BoardSnapshot/migrate(v15:)``, which runs straight after this and is
    /// the only thing that reads what this leaves behind.
    ///
    /// Only `symbol` is lenient, for `BoardSnapshot`'s reason: a board with no
    /// `name` and no `columns` is not a board with neither, it is not a board,
    /// and reading it as one would write that emptiness back over the user's
    /// work. The old `dot` is simply not asked for — an unknown key is not a
    /// decoding failure, so a v15 file's colours are dropped on the way in.
    enum CodingKeys: String, CodingKey {
        case id, name, symbol, createdAt, columns, codePrefix
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            symbol: try container.decodeIfPresent(String.self, forKey: .symbol)
                ?? SymbolMark.boardFallback,
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            columns: try container.decode([BoardColumn].self, forKey: .columns),
            codePrefix: try container.decode(String.self, forKey: .codePrefix)
        )
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

    /// What a board is called before its maker has said. Every route that makes
    /// one goes through it, because none of them asks for a name up front any
    /// more — the settings sheet opens on the new board with this in the field,
    /// cleared and focused, and the first keystroke names it. A board that is
    /// never named keeps this rather than ending up nameless, which `renameBoard`
    /// refuses anyway.
    static var defaultName: String {
        String(localized: "New Board", comment: "What a board is called until it is named")
    }

    /// The Inbox's name, dot and mark. It stopped being a `BoardColumn` when it
    /// became global, so there is nowhere else for a surface to read them from.
    static var inboxName: String {
        String(localized: "Inbox", comment: "The global capture list, shown above the boards")
    }

    /// Still a colour, because the two surfaces that read it draw the Inbox as
    /// though it were a *column* — see ``BoardStore/mobileColumn`` — and a
    /// column is still a coloured dot.
    static let inboxDot: SwatchColor = .ink(opacity: 0.35)

    /// What the destination pill wears when a card is on no board. The seeded
    /// Inbox view's own glyph, written here rather than read off that view: the
    /// pill is a list of *places* and the Inbox is one of them whether or not
    /// the view it shares a name with is still in the sidebar.
    static let inboxSymbol = "tray"

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

    /// A board's mark as it is stored: trimmed, and never empty.
    ///
    /// Not checked against ``SymbolCatalog``. The picker only offers names that
    /// are in it, and the one other way a name arrives — a board synced from a
    /// device a system version ahead — is precisely the case that must be kept:
    /// dropping it here would take a glyph away from the device that *can* draw
    /// it the next time this one saved. ``SymbolMark`` handles the drawing.
    static func symbol(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SymbolMark.boardFallback : trimmed
    }

    /// The marks a board is *offered* before it is browsed for one: what the
    /// icon picker opens on, and what the v15 → v16 migration deals out.
    ///
    /// The whole catalogue is one menu away — see ``SymbolCatalog`` — and
    /// opening a picker on seven thousand glyphs sorted alphabetically means
    /// opening it on `0.circle`. These are the ones a board is actually likely
    /// to want, they read at the 14pt a sidebar row draws them at, and the
    /// first is ``SymbolMark/boardFallback``, so the mark a board already has
    /// is the mark the list starts with.
    ///
    /// Deliberately not ``SavedView/startingSymbols``. Both kinds of row sit in
    /// one sidebar and both are picked from the same browser, so nothing stops
    /// a board wearing `tray` — but nothing should *offer* it either, for the
    /// same reason a board was never offered the Inbox's grey: the two lists
    /// are what each picker opens on, and opening a board's on the Inbox's mark
    /// is a suggestion to make the sidebar unreadable.
    static let startingSymbols = [
        SymbolMark.boardFallback, "house", "briefcase", "hammer", "chart.bar",
        "book", "cart", "person.2", "paintbrush", "airplane", "leaf",
        "graduationcap", "cup.and.saucer", "shippingbox", "globe", "heart",
    ]

    static let nameLimit = 60
    static let codePrefixLimit = 4
}

private extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}

/// What the board settings sheet was asked for: which board, and what it should
/// be showing when it arrives.
///
/// A value rather than three flags on the store, because the three are only ever
/// set together and only ever mean one thing between them. `Identifiable` on the
/// board's own id, which is what `.sheet(item:)` wants — asking for a second
/// board's settings while one is open replaces the sheet rather than stacking.
struct BoardSettingsRequest: Identifiable, Hashable, Sendable {
    /// The board being edited. Held as an id rather than a `Board`: a rename
    /// lands in the store, and a snapshot taken when the sheet opened would go
    /// on showing the old name under the field that had just changed it.
    var board: Board.ID
    /// A column to arrive with already unfolded — set by the routes that name
    /// one, a column chip's **Edit Column…** and the desk's column menu.
    var column: BoardColumn.ID?
    /// Whether to land the caret in the board's name field, set by the routes
    /// that say *rename* rather than *settings*.
    var focusesName: Bool = false
    /// Whether to arrive with the add-column composer already open, set by the
    /// routes that say *add a column* rather than *settings* — the board's own
    /// empty states, which are the only thing on a board that still offers one
    /// now that the strip's dashed tile has gone. Same bargain as `focusesName`:
    /// a button that promises a column should land in a field, not in a sheet
    /// with a button in it.
    var addsColumn: Bool = false
    /// Whether this board has just been made and still carries
    /// ``Board/defaultName``. The name field arrives focused and **empty**, so
    /// the first keystroke names the board rather than being appended to a name
    /// nobody chose. Implies `focusesName`; the two are never both needed.
    var namesNewBoard: Bool = false

    var id: Board.ID { board }
}
