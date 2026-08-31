import Foundation

/// Everything the widgets draw, as the app worked it out.
///
/// **The widgets do not evaluate anything.** A saved view is a rule tree over
/// every task in the file, a column's contents depend on the board's sort order
/// and on which cards are archived, and "is this card done" is a question about
/// the board rather than about the card. All of that already exists, once, in
/// `BoardStore`, and a second implementation living in an extension would be a
/// second implementation *diverging* in an extension — where nobody would see
/// it, because a widget that quietly disagrees with the app looks exactly like a
/// widget that has not refreshed yet.
///
/// So the app answers the questions and writes the answers down. What crosses
/// the fence is a flat list of rows, already filtered, already sorted, already
/// capped at ``listLength``, next to the counts the app computed for the badges.
/// The extension's whole job is to choose a list by id and draw it.
///
/// Two things that are *not* answers come across as well:
///
/// - ``themes``, so the widget wears the theme the user chose rather than an
///   approximation of it. It is the app's own ``ThemeSettings`` verbatim, which
///   means a custom theme travels too.
/// - ``today``, so a due chip in a widget says what the same chip says on the
///   board. The widget could read the clock — but then a digest written
///   yesterday would be drawn against today's date and a card due tomorrow
///   would read "Today" for one refresh.
struct WidgetDigest: Codable, Hashable, Sendable {
    /// Bumped when the shape changes. There is no migration and there will not
    /// be one: a digest the extension cannot read is redrawn by the app within
    /// the second, so the reader simply refuses anything that is not its own
    /// version. See ``WidgetShare``.
    /// **2 since columns carry a WIP limit, 3 since a board wears a glyph
    /// rather than a dot.** A digest is a cache and a version that does not
    /// match is refused rather than migrated — see ``WidgetDigestFile/decode(_:)``
    /// — so a bump costs one placeholder render until the app writes the next
    /// digest, which is within half a second of the next edit. That is the
    /// whole price, and it buys a widget that cannot draw `4` beside a column
    /// the app is drawing `4/3` for, or a colour beside a board the app is
    /// marking with an icon.
    static let currentVersion = 3

    /// How many rows any one list carries.
    ///
    /// The tallest thing any of these widgets draws is the large family's list,
    /// and it no longer draws a fixed number of them: `WidgetRowCount` works the
    /// count out from the tile, which is thirteen rows on an SE and fifteen on a
    /// 6.7" phone. Sixteen is that plus the spare the old eight had, and it is
    /// also the ceiling the extension clamps to, so a tile can never ask for a
    /// row the app did not send.
    ///
    /// One spare row is worth the bytes; a hundred are not — the digest is
    /// decoded on the system's schedule inside an extension with a memory limit,
    /// and a board with four thousand cards must not be able to make that a
    /// problem.
    ///
    /// Raising it is not a shape change, so it costs no version bump: an old
    /// digest still decodes, and a large tile draws the eight it holds until the
    /// app writes the next one.
    static let listLength = 16

    var version: Int = WidgetDigest.currentVersion
    var writtenAt: Date
    /// The day the lists were computed against — see the type's own note.
    var today: CalendarDay
    var themes: ThemeSettings
    /// The app's light/dark override, so a widget follows the *app's* answer
    /// rather than the system's when the two differ.
    var appearance: AppAppearance

    /// The global Inbox, which is not a board and not a saved view: it has its
    /// own widget and its own `+`.
    var inbox: WidgetList
    /// Every board, in sidebar order, each carrying its columns.
    var boards: [WidgetBoard]
    /// Every saved view, in sidebar order. The Inbox's seeded view is among
    /// them — it is a row in that list like any other, and somebody who wants
    /// it as a list widget rather than as the Inbox widget should be able to
    /// pick it.
    var views: [WidgetList]

    // MARK: Lookups

    func board(id: UUID?) -> WidgetBoard? {
        guard let id else { return nil }
        return boards.first { $0.id == id }
    }

    /// A column named on its own, without the caller having to know which board
    /// it is on — which a widget's configuration deliberately does not, so that
    /// a column moved to another board keeps drawing.
    func column(id: UUID?) -> (board: WidgetBoard, column: WidgetColumn)? {
        guard let id else { return nil }
        for board in boards {
            if let column = board.columns.first(where: { $0.id == id }) { return (board, column) }
        }
        return nil
    }

    func view(id: UUID?) -> WidgetList? {
        guard let id else { return nil }
        return views.first { $0.id == id }
    }
}

/// One board, and the columns work moves through.
struct WidgetBoard: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// The board's own glyph — ``Board/symbol``, drawn through ``SymbolMark``
    /// like everywhere else, because a widget on a Mac a system version behind
    /// the phone that picked the mark is exactly the case that needs it.
    var symbol: String
    /// **Every** column, Done included. The column widget is entitled to show
    /// one — a widget of what shipped this week is a perfectly good widget —
    /// so the filtering belongs at the point of use rather than here. See
    /// ``workingColumns``.
    var columns: [WidgetColumn]

    /// Where finished work lives: the last column, always. `Board.doneColumn`
    /// is the rule and says why at length — position rather than a stored id,
    /// so there is nothing to keep in step with the array.
    var doneColumn: WidgetColumn? { columns.last }

    /// Every column before Done — the ones work actually moves through, which
    /// is what the board-overview widget draws.
    ///
    /// **Done is left off that widget deliberately.** It is the one column that
    /// only grows, so on any board more than a fortnight old it is the largest
    /// number on the tile and it is the least interesting: a glance at a board
    /// is a glance at what is left, and a Done count that climbs forever
    /// crowds out the three numbers that move. Anybody who does want to watch
    /// it can point a column widget at it.
    ///
    /// Empty on a board that holds nothing but its Done column, which is the
    /// state every freshly made board is in — the widget says so rather than
    /// drawing an empty row.
    var workingColumns: [WidgetColumn] { Array(columns.dropLast()) }
}

/// One column: what it is called at both lengths, how many cards are in it, and
/// the first few of them.
///
/// `short` is carried as well as `name` because the board-overview widget draws
/// four or five columns across a medium tile and has room for nothing else —
/// which is the same reason `BoardColumn.short` exists at all.
struct WidgetColumn: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var short: String
    var dot: SwatchColor
    /// Every card in the column, not just the ones in ``tasks``. The badge on a
    /// widget has to agree with the badge on the board.
    /// The column's WIP limit, or `nil` for none — ``BoardColumn/limit``. The
    /// widget draws the same `4/3` pill the board does, which is the only
    /// reason it crosses the fence.
    var limit: Int?
    var count: Int
    var tasks: [WidgetTask]
}

/// A list with a name and a glyph: the Inbox, or a saved view.
struct WidgetList: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// The SF Symbol the sidebar row draws, so the widget's header is the same
    /// mark the user picks the list by in the app.
    var symbol: String
    /// Which built-in this view was seeded from — `SavedView.Preset`'s raw
    /// value — or `nil` for one the user made.
    ///
    /// Carried for exactly one reason: a saved-view widget that has just been
    /// dragged out has to start on *something*, and Today is the answer
    /// everywhere else in this app. The alternative was for the extension to
    /// hold a second copy of the seeded views' fixed identifiers, which is the
    /// kind of table that is correct until the day it is not.
    var preset: String?
    var count: Int
    var tasks: [WidgetTask]

    /// `SavedView.Preset.today`'s raw value, spelled here because the extension
    /// cannot see that enum and one string is a smaller thing to keep in step
    /// than a table of UUIDs. `SavedViewSeedTests` holds the two together.
    static let todayPreset = "today"
}

/// One row.
///
/// Deliberately not a `TaskItem`. A row draws a title, a due chip and a
/// priority dot, and everything else a task carries — its note, its activity
/// feed, its sub-tasks, its labels — is bytes crossing the fence for nothing.
/// The id is here so the row can link back to the card it stands for.
struct WidgetTask: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Already through `TaskItem.displayTitle`, so an untitled capture reads as
    /// "Untitled" here exactly as it does on the board.
    var title: String
    var due: CalendarDay?
    var priority: Priority
    /// Whether the board calls this card finished — which is a question about
    /// the board's Done column, or about the Inbox's own completion, and not
    /// one the extension could answer for itself.
    var isDone: Bool
}
