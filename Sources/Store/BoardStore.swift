import Observation
import SwiftUI

/// The three tabs in the iOS tab bar.
/// The two places the phone's list can be, which is what the tab bar switches
/// between.
///
/// **The Inbox used to be the third.** It is now a slide-over that comes up over
/// the board — see ``PhoneInboxSheet`` — so it is a toggle rather than a
/// destination, the same shape it has on the other two platforms, and the same
/// `isInboxOpen` drives all three. A tab is somewhere you *go*, and going to the
/// Inbox meant leaving the board to look at the cards you keep beside it.
enum PhoneTab: String, CaseIterable, Identifiable, Sendable {
    case board, search

    var id: String { rawValue }

    var label: String {
        switch self {
        case .board: String(localized: "Board", comment: "Phone tab showing the active board")
        case .search: String(localized: "Search", comment: "Phone tab showing the search results")
        }
    }

    /// The glyph beside the word on the phone's bar — and, with the phone on
    /// its side, instead of it. The Inbox slot is not one of these and takes
    /// ``SavedView/inbox``'s, which is the tray the desk's own Inbox row draws:
    /// one place, one glyph.
    var symbol: String {
        switch self {
        case .board: "square.grid.2x2"
        case .search: "magnifyingglass"
        }
    }
}

/// What the main surface is showing: the active board, or a saved view
/// standing in for it.
///
/// **The Inbox is not one of these.** It used to be — a page that took the
/// board's place — and it is now a panel that stands *beside* the board, so it
/// is a toggle (``BoardStore/isInboxOpen``) rather than a destination. Cards
/// filed nowhere are the ones you reach for while working on the board; a
/// surface that replaced the board made you leave it to see them.
///
/// **On all three platforms**, now that the phone's is a slide-over rather than
/// a tab: a panel beside the board on the desk and the iPad, a panel over it on
/// the phone, and `isInboxOpen` either way. The phone used to be the exception —
/// it shows one thing at a time and had nowhere to put a panel *beside*
/// anything — and the answer turned out to be over the top rather than instead.
///
/// Session state — where the user is looking rather than anything about the
/// board — so it is out of `BoardSnapshot` and out of `BoardMutation`.
/// `activeBoardID` is the opposite case and is saved: *which* board is where
/// their work is, while *whether they are looking at it* is not.
enum BoardSurface: Hashable, Sendable {
    case board
    /// **The view's id, not the view.** A `SavedView` is editable now, so a
    /// surface carrying a copy of one would go on drawing the rule the user had
    /// before they opened the editor — and a surface carrying a *deleted* view
    /// would draw a list nothing can reach. The id is looked up on every read;
    /// see ``BoardStore/activeView``.
    case view(SavedView.ID)
}

/// Which detail surface a piece of transient editing state belongs to. The
/// macOS inspector and the iOS sheet can both be open at once, so their
/// editing sessions, sub-task drafts and label pickers are tracked separately.
enum DetailScope: Hashable, Sendable { case desk, sheet }

/// How a column's cards are ordered on screen.
///
/// A *display* preference, not board data: it changes the order cards are
/// drawn in and nothing about where they are, which is why it lives in
/// `UserDefaults` rather than in `BoardSnapshot`. `.manual` is the board's own
/// order — the one a drag writes — and the only one a card may be dragged
/// under, because a drop is an index in the unfiltered array and means nothing
/// once something else has decided the order.
enum BoardSortOrder: String, CaseIterable, Identifiable, Sendable {
    case manual, dueDate, priority, recentlyUpdated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual:
            String(localized: "Board order", comment: "Sort order: the order cards were dragged into")
        case .dueDate:
            String(localized: "Due date", comment: "Sort order: soonest due first")
        case .priority:
            String(localized: "Priority", comment: "Sort order: high priority first")
        case .recentlyUpdated:
            String(localized: "Recently updated", comment: "Sort order: most recently changed first")
        }
    }
}

/// A field a detail surface edits as a *session*: it takes focus (or opens a
/// picker), the value changes as often as the user likes, and finishing writes
/// one activity entry naming what they settled on.
enum TaskField: String, Hashable, Sendable, CaseIterable {
    case title, note, due, priority
    /// One sub-task's text. Unlike the others it needs saying *which* sub-task,
    /// which is why an editing session is keyed by a sub-task id as well.
    case subtask

    /// Fields that are one line by definition, so a commit folds anything
    /// pasted into them flat.
    var isSingleLine: Bool { self == .title || self == .subtask }
}

/// Why the board's storage last failed, in terms a surface can show.
///
/// Distinct from `BoardFileError`: that one describes a file, this one
/// describes what the user needs to be told about it.
enum BoardStoreError: LocalizedError, Equatable, Sendable, Identifiable {
    /// The saved board could not be used. The payload says where the original
    /// was put — or that it could not be moved at all, which is what stops the
    /// store writing over it.
    case load(BoardLoadFailure)
    /// A write failed. It carries the message rather than the error so the
    /// value stays `Equatable`; the store only ever displays it.
    case save(message: String)
    /// The board is safe on this device but is not reaching the others. A
    /// different sentence from `save`, and a much less urgent one.
    case sync(message: String)

    var id: String {
        switch self {
        case .load(.unreadable): "load.unreadable"
        case .load(.newerVersion(let version, _)): "load.newerVersion.\(version)"
        case .save(let message): "save.\(message)"
        case .sync(let message): "sync.\(message)"
        }
    }

    var errorDescription: String? {
        switch self {
        case .load(.unreadable):
            String(localized: "Your board could not be read.",
                   comment: "Alert title when the saved board is corrupt")
        case .load(.newerVersion(let version, _)):
            String(localized: "Your board was saved by a newer version of Little Kanban (format \(version)).",
                   comment: "Alert title when the saved board is too new to read")
        case .save(let message):
            String(localized: "The board could not be saved. \(message)",
                   comment: "Status shown when writing the board file failed")
        case .sync(let message):
            String(localized: "This board is saved on this device but is not syncing. \(message)",
                   comment: "Status shown when the board saved locally but could not reach iCloud")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .load(.unreadable(let quarantinedAt)), .load(.newerVersion(_, let quarantinedAt)):
            if let quarantinedAt {
                String(localized: "A new board has been started. The old file has been kept as “\(quarantinedAt.lastPathComponent)”.",
                       comment: "Alert body naming the file the damaged board was moved to")
            } else {
                String(localized: "A new board has been started, and saving is paused so the old file is not written over. Continuing will replace it.",
                       comment: "Alert body when the damaged board could not be moved aside")
            }
        case .save, .sync:
            nil
        }
    }
}

/// Why a change to the board's columns was refused.
///
/// A refusal, not a crash and not a silent no-op: the caller has an explanation
/// to show, because from the outside "delete" doing nothing is indistinguishable
/// from a bug.
enum ColumnRefusal: LocalizedError, Equatable, Sendable {
    /// No column on this board has that id.
    case unknownColumn
    /// It is the board's Done column, which every board has and keeps — see
    /// ``Board/doneColumn``. Completing a task, the weekly meter and the archive
    /// all mean nothing without one, and since v9 it is the *last* column rather
    /// than a column wearing a role, so there is no second one to fall back to.
    case doneColumn
    /// Everything left would be the Done column, which is a list rather than a
    /// board: there would be nowhere for work to start.
    case lastWorkingColumn

    var errorDescription: String? {
        switch self {
        case .unknownColumn:
            String(localized: "That column is not on this board.",
                   comment: "Explanation when a column change names a column that does not exist")
        case .doneColumn:
            String(localized: "Every board keeps its Done column.",
                   comment: "Explanation when deleting a board's Done column is refused")
        case .lastWorkingColumn:
            String(localized: "A board needs at least one column that is not Done.",
                   comment: "Explanation when deleting the last column work can start in is refused")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unknownColumn:
            nil
        case .doneColumn:
            // No instructions, because there is nothing to do: this is the one
            // column that is part of what a board *is*. It can still be renamed
            // and recoloured, which is what somebody who wants rid of "Done"
            // usually actually wants.
            String(localized: "It can be renamed and recoloured, but not removed.",
                   comment: "What can be done to a board's Done column instead of deleting it")
        case .lastWorkingColumn:
            String(localized: "Add another column first, then delete this one.",
                   comment: "How to get past the refusal to delete the last column work can start in")
        }
    }
}

/// The card that says what the app has just done — something thrown away, or a
/// check with iCloud finished.
///
/// **Session state, and firmly not board state**: it is not in `BoardSnapshot`,
/// not in `BoardMutation`, and a relaunch does not bring it back. What happened
/// is already recorded — the thing is in the trash, the board is up to date —
/// and this is only the app saying so out loud for a few seconds.
///
/// **One announcement, two authors**, because there is one strip of screen for
/// it and a second parallel message would have to decide which of them wins
/// while both were up. The glyph is carried rather than assumed for the same
/// reason: the trash's little bin over "Up to date" would be the app saying two
/// different things at once.
///
/// The `id` is what makes a *repeat* land. Trashing two cards with the same
/// title in a row produces two announcements reading the same words, and a view
/// keyed on the text alone would treat the second as "no change" and leave the
/// first one's dismissal timer running — so the second card would vanish early
/// or not appear at all. Two pulls that both find nothing are the same case.
struct Announcement: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String
    /// The SF Symbol drawn beside the words.
    let symbol: String

    /// One thing, by name. The name is the card's title, the column's or the
    /// board's — see ``TrashedItem/name``.
    init(name: String) {
        text = String(localized: "Moved \(name) to the trash",
                      comment: "Confirmation shown after something is thrown away")
        symbol = "trash"
    }

    /// Several cards at once, which have no one name between them.
    init(taskCount: Int) {
        text = String(localized: "Moved \(taskCount) tasks to the trash",
                      comment: "Confirmation shown after several tasks are thrown away at once")
        symbol = "trash"
    }

    private init(text: String, symbol: String) {
        self.text = text
        self.symbol = symbol
    }

    /// A check the user asked for, finished — the pull on iPhone and iPad, the
    /// desk's button. **The two answers are different sentences**: a pull that
    /// brought a card down and a pull that found nothing both end with the
    /// spinner going away, and "nothing arrived" is the answer people are
    /// actually waiting for confirmation of.
    /// Shares drained out of the App Group as the app comes forward — see
    /// ``BoardStore/adoptPendingCaptures()``.
    ///
    /// **No count in the sentence.** The Inbox row's own badge is about to say
    /// how many arrived, and it says it in a place that stays on screen; a
    /// counted noun here would be the same number twice, and would want a
    /// plural rule for it.
    static let captured = Announcement(
        text: String(localized: "Added to the Inbox",
                     comment: "Toast after things shared from another app are taken into the Inbox"),
        symbol: "tray.and.arrow.down"
    )

    static func synced(adopted: Bool) -> Announcement {
        adopted
            ? Announcement(
                text: String(localized: "Board updated",
                             comment: "Toast after a sync the user asked for brought another device's changes in"),
                symbol: "arrow.triangle.2.circlepath"
            )
            : Announcement(
                text: String(localized: "Up to date",
                             comment: "Toast after a sync the user asked for found nothing new"),
                symbol: "checkmark"
            )
    }
}

/// Why something could not come back out of the trash.
///
/// Only three answers, and two of them mean the row is stale rather than that
/// the restore was wrong — the surface having been left open while another
/// window, or a ⌘Z, moved the ground. `nil` from `restoreFromTrash` means it
/// happened.
///
/// There is deliberately **no case for a card whose board or column has gone**.
/// A card is the user's, and refusing to hand one back over a missing column
/// would be holding it hostage to a container it never belonged to in the first
/// place; it lands in the Inbox instead, which is what happens to every other
/// card that cannot find its column. A *column* is different: it is nothing but
/// a place on a board, so a board that is not there is a genuine refusal.
enum TrashRefusal: LocalizedError, Equatable, Sendable {
    /// Nothing in the trash under that id — already restored, already deleted,
    /// or swept by the thirty days while the surface was open.
    case gone
    /// The column's board has been deleted since. Restoring the board first is
    /// a real route, which is why this says so rather than just failing.
    case boardIsGone
    /// Something with that id is on the board already, so putting this back
    /// would make two of it.
    case alreadyThere

    var errorDescription: String? {
        switch self {
        case .gone:
            String(localized: "That item is no longer in the trash.",
                   comment: "Explanation when a restore names a trashed item that has since gone")
        case .boardIsGone:
            String(localized: "The board that column was on has been deleted.",
                   comment: "Explanation when a trashed column cannot be restored")
        case .alreadyThere:
            String(localized: "That is already on the board.",
                   comment: "Explanation when a restore would make a second copy of something")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .gone, .alreadyThere:
            nil
        case .boardIsGone:
            String(localized: "Restore the board first, then the column can go back on it.",
                   comment: "How to get past the refusal to restore a column whose board is gone")
        }
    }
}

/// The part of the board an undo restores.
///
/// Session state — the selection, drafts, the query, the drag — is deliberately
/// not here: it belongs to the surfaces, not to the board, and restoring it
/// would move the user's attention somewhere they did not put it. `tasks` and
/// `labels` are arrays of value types, so holding one of these costs a retain
/// apiece rather than a copy of the board.
///
/// The selection is *not* an exception, and there is no exception: there are two
/// of them (`selection` — a set — and `sheetID`), they are per surface, and
/// neither is in `BoardSnapshot`. `apply` therefore only drops the ids that have
/// stopped naming anything — it never puts one back. The cost is real and known: undoing
/// a delete brings the card back while the inspector stays on its neighbour. The
/// fix for that belongs to whatever offers the undo, not to the board.
struct BoardMutation: Equatable, Sendable {
    var tasks: [TaskItem]
    var labels: [LabelDef]
    var nextSerial: Int
    /// The boards and, inside them, their columns — so adding, renaming,
    /// reordering or deleting either is a ⌘Z like any other.
    ///
    /// Required, with no default. It used to default to `SeedData.boards`,
    /// which made a mutation built without it quietly claim the seed board: on
    /// a store with any other boards the comparison then read as a change that
    /// had not happened, and on a store with the seed it read as no change and
    /// said nothing — which is why nobody noticed.
    ///
    /// `activeBoardID` is deliberately absent, for the same reason the selection
    /// is: it is where the user is looking. It is persisted where the selection
    /// is not — which board you are on is where your work is — but an undo that
    /// moved someone to another board would be moving their attention, and a
    /// picker session's before-state would carry a board switch made while it
    /// was open. The cost is known: undoing a board delete brings the board back
    /// without going back to it.
    var boards: [Board]
    /// What has been thrown away and not yet thrown away for good.
    ///
    /// In here so that trashing is one ⌘Z like every other mutation: without it
    /// an undone trash would put the card back on the board *and* leave a copy
    /// of it sitting in the trash, which is one card the user now has twice.
    /// Restoring and emptying are the same story from the other end.
    ///
    /// Required, with no default, for the reason `boards` is: a mutation built
    /// without it claims an empty trash, and against a store that has one that
    /// reads as a change nobody made.
    var trash: [TrashedItem]
    /// The saved views, in sidebar order.
    ///
    /// In here for `boards`' reason: since the seven stopped being an enum,
    /// making, renaming, re-ruling, reordering and deleting one are edits to the
    /// board file, and every one of them has to be a single ⌘Z. Required and
    /// undefaulted for the same reason as the two above — a mutation built
    /// without it would claim the seeded seven, which against a store the user
    /// has added a view to reads as a deletion nobody asked for.
    var views: [SavedView]
    /// The colours every picker offers.
    ///
    /// In here for the same reason the rest is: saving one and deleting one are
    /// edits to the board file, and a ⌘Z that put a deleted colour back on the
    /// palette but left the *board* as it was would be restoring half of what
    /// the user just did. Required and undefaulted like its neighbours — a
    /// mutation built without it would claim the six the app ships with, which
    /// against a store the user has added a colour to reads as a deletion
    /// nobody asked for.
    var savedColors: [PaletteSwatch]
    /// When the two above were last changed — restored with them, so undoing an
    /// edit puts back the date it was made under as well as the list. A board
    /// wound back to Tuesday's views and still claiming Thursday's date would
    /// win a merge it has no business winning. See ``BoardSnapshot/viewsChangedAt``.
    var viewsChangedAt: Date?
    var paletteChangedAt: Date?
}

/// Which edge of which card a dragged one would land against.
///
/// Two cases rather than an index, because an index is a fact about the board
/// and this is a fact about the *screen*: the caret is drawn by whichever card
/// it names, on the side it names, and no card has to know how far down the
/// column it is to draw its own edge. See ``BoardStore/dropCaret``.
enum DropCaret: Hashable, Sendable {
    case above(TaskItem.ID)
    case below(TaskItem.ID)

    /// The card the caret is drawn against.
    var card: TaskItem.ID {
        switch self {
        case .above(let id), .below(let id): id
        }
    }

    /// Which side of that card the gap is on, as an insertion offset: a gap
    /// above the card on row *n* opens at *n*, and below it at *n + 1*.
    ///
    /// The two cases are the form an *edge* needs — a card draws a line on one
    /// of its own sides and never has to know how far down the column it is. A
    /// *row* needs the offset instead, because a list opening a gap is counting
    /// its own rows. See ``BoardStore/dropPreview(in:)``.
    var isAbove: Bool {
        switch self {
        case .above: true
        case .below: false
        }
    }
}


/// The card in flight, and which row of a list it is about to become.
///
/// **A row rather than an edge**, which is the whole difference between this and
/// ``DropCaret``. A caret is a line drawn *by* a card on one of its own sides,
/// so it needs a card to hang off and it costs no space. A preview is a card
/// drawn *between* them: it needs an index, and it pushes its new neighbours
/// apart by exactly what the real card is about to take.
///
/// It carries the task rather than its id so the stand-in can show *which* card
/// is landing. A hand carrying one card across a board of forty should not have
/// to remember which one it picked up.
struct DropPreview: Hashable, Sendable {
    /// The card being carried.
    var task: TaskItem
    /// Where it goes among the rows **as they are drawn** — the card in the air
    /// is still one of them, dimmed, until the drop lands.
    var index: Int
    /// The gap it stands in, or `nil` where it stands on a list's bare ground
    /// and the drop is `drop(_:onGroundOf:)`'s. This is what the stand-in
    /// re-claims to hold the gap open under the pointer; see ``DropZone``.
    var caret: DropCaret?
    /// The list it is standing in, carried so the stand-in can keep that list
    /// lit while the pointer is on the gap rather than on one of its cards —
    /// and so the two views that draw one are handed a single value rather than
    /// a value and the place it came from.
    var placement: TaskPlacement
}

/// Which edge of which column a dragged one would land against — ``DropCaret``
/// for the settings sheet's list of columns, and the same shape for the same
/// reason: the mark is drawn by whichever row it names, on the side it names.
///
/// A separate type rather than a reuse: both ids are `UUID`, so one enum would
/// take a card's id where a column's belongs and nothing would say otherwise
/// until a drop landed somewhere absurd.
enum ColumnCaret: Hashable, Sendable {
    case above(BoardColumn.ID)
    case below(BoardColumn.ID)

    /// The column the caret is drawn against.
    var column: BoardColumn.ID {
        switch self {
        case .above(let id), .below(let id): id
        }
    }
}

/// Which edge of which checklist row a dragged sub-task would land against —
/// ``ColumnCaret``'s shape for the third and last list in the app that re-orders
/// by hand, and for the same reason: the mark is drawn by whichever row it
/// names, on the side it names, and no row has to know how far down the list it
/// is to draw its own edge.
///
/// Its own type rather than a reuse of one of the other two, for the reason
/// ``ColumnCaret`` gives: every id here is a `UUID`, so a single enum would take
/// a card's where a sub-task's belongs and nothing would say otherwise until a
/// drop landed somewhere absurd.
enum SubtaskCaret: Hashable, Sendable {
    case above(SubTask.ID)
    case below(SubTask.ID)

    /// The row the caret is drawn against.
    var row: SubTask.ID {
        switch self {
        case .above(let id), .below(let id): id
        }
    }
}

/// Board state and every mutation the design defines.
///
/// This is a port of the `Component extends DCLogic` class in
/// the design spec (see `littlekanban design spec.zip`): same state fields,
/// same transition rules.
///
/// **One file, on purpose — splitting it was tried and reverted.** The
/// obvious move at this size is `extension BoardStore` files per section, and
/// two things veto it. The memo caches (`positions`, `searchMemo`,
/// `groupedCache`, `countsMemo`, `viewCounts`, `viewMembers`, `searchTexts`,
/// `boardIndices`…) are stored properties declared beside the code whose
/// invariants they carry, and an extension cannot hold stored state. And the
/// sections that *look* stateless — themes, trash, labels, columns, palette,
/// the phone's navigation — write `tasks`, `boards`, `trash`, `themes` and
/// `savedColors` directly, whose setters are `private(set)` **because the
/// mutation contract says only this type mutates them**: moving those
/// sections out compiles only if the setters open to the whole module, at
/// which point any view can write the board without an undo step or a save.
/// The file's size is the cost of the compiler enforcing that contract, and
/// it is the cheaper of the two.
@MainActor
@Observable
final class BoardStore {
    // MARK: Content

    /// Read-only from outside: every mutation goes through a method that files
    /// an undo step and a save, and a settable array is a way round both —
    /// `store.tasks.removeAll()` would empty the board with `canUndo` still false.
    private(set) var tasks: [TaskItem]
    /// The boards, in sidebar order, each carrying its own columns.
    private(set) var boards: [Board] { didSet { columnOwners = nil; boardIndices = nil; doneColumns = nil } }
    /// The board being looked at. Persisted, unlike `surface` — which board you
    /// are on is where your work is. `nil` only on a board list emptied down to
    /// nothing; every other path keeps it naming a board that exists.
    private(set) var activeBoardID: Board.ID?

    /// What has been thrown away, newest last, still inside its thirty days —
    /// see ``TrashedItem`` and ``sweepTrash()``.
    ///
    /// **Local to this device.** It rides in `board.json`, which is written on
    /// every save whether or not CloudKit is on, but it has no record type in
    /// the sync schema: the two questions "what is on my board" and "what did I
    /// throw away here" are not the same question, and a trash that arrived from
    /// another Mac would offer to restore a card this one has never seen. What
    /// crosses devices is the board — a card trashed on one simply leaves the
    /// board on both. See `restored(file:sync:)`, which reads the file for this
    /// even when the board itself came from the records.
    private(set) var trash: [TrashedItem] = []

    /// The card on screen saying what the app has just done, or `nil`.
    ///
    /// Written by the three trash verbs and by a sync the user asked for, and
    /// cleared by whichever surface drew it once its few seconds are up — the
    /// timer is the view's, because how long a message stays on screen is a fact
    /// about the screen. Also cleared by `apply`, so a ⌘Z takes the sentence
    /// away with the act it describes; a card still reading "Moved Ship the
    /// thing to the trash" over a board that has Ship the thing back on it is
    /// the app contradicting itself.
    var announcement: Announcement?
    /// Ordered — the label picker lists them in creation order, and new labels
    /// take their colour from the palette by current count.
    private(set) var labels: [LabelDef] { didSet { labelsByKey = nil } }
    /// The saved views, in sidebar order — the seeded seven plus whatever the
    /// user has made. Board data since v10; see ``SavedView``.
    private(set) var views: [SavedView] { didSet { viewsChangedAt = .now } }
    /// **The colours every picker in the app offers**, in the order they are
    /// drawn — see ``PaletteSwatch``.
    ///
    /// One list rather than one per picker, and stored rather than constant,
    /// because that is the whole of what makes a colour saved in a column's
    /// picker appear in a board's. Deliberately not called `palette`: views
    /// already have a `palette` in the environment and it is the *theme*.
    private(set) var savedColors: [PaletteSwatch] = PaletteSwatch.seed {
        didSet { paletteChangedAt = .now }
    }
    /// **What the app looks like**: which theme fills the light slot, which
    /// fills the dark one, and the themes the user has built.
    ///
    /// Saved with the board rather than in `@AppStorage`, exactly as the accent
    /// it replaced was. A theme somebody spent an evening on is their work, and
    /// work belongs in the file that gets exported, backed up and synced — not
    /// in a preference that stays behind on the old machine. Which of the two
    /// slots is showing is *not* here: that follows the system appearance and
    /// the `AppAppearance` override, both of which belong to the machine.
    private(set) var themes: ThemeSettings { didSet { themesChangedAt = .now } }

    /// When this device last changed each of those three, or `nil` for a list
    /// nobody could date — see ``BoardSnapshot/viewsChangedAt``, which is where
    /// they are written down, and ``SharedList``, which is what they are for.
    ///
    /// Stamped by a `didSet` rather than by each mutator, so a method added to
    /// this file next year cannot forget to date what it changed. The three
    /// paths that must *not* stamp — undo, and a board arriving from a file or
    /// from the records — assign the stamp explicitly straight after the list,
    /// which lands on top of what the observer wrote. See ``apply(_:)``.
    private(set) var viewsChangedAt: Date?
    private(set) var paletteChangedAt: Date?
    private(set) var themesChangedAt: Date?

    // MARK: Selection

    /// Every task the board has picked out. A set rather than one id: the
    /// board offers a range (⇧-click), a toggle (⌘-click) and Select All, and
    /// the bulk commands those exist for.
    ///
    /// Read-only from outside so the rule below cannot be stepped around; the
    /// selection methods are the way in, and `selectedID` still assigns for the
    /// one-card case.
    private(set) var selection: Set<TaskItem.ID> = [] {
        didSet {
            guard selection != oldValue else { return }
            // A surface that moves to another task cannot end the sessions it
            // left open there, and a session nobody will ever end would silence
            // that task's picker logging for good — so moving off a task ends
            // them here. Measured against `selectedID` rather than the whole
            // set: the inspector shows one task or none, so picking a second
            // card takes the panel off the first as surely as picking another
            // one would.
            endSessions(in: .desk, awayFrom: selectedID)
        }
    }

    /// Where a ⇧-click measures its range from: the last card picked outright.
    /// A view concern in spirit, but the range and the set have to agree, and
    /// they only can if one thing owns both.
    @ObservationIgnored private var selectionAnchor: TaskItem.ID?

    /// The single selected task — `nil` for none, and `nil` for several.
    ///
    /// That is what keeps every consumer of a single selection working
    /// unchanged: the inspector shows a task when exactly one is picked and its
    /// empty state otherwise, which is the right answer for a multi-selection
    /// too. Assigning replaces the whole selection.
    var selectedID: TaskItem.ID? {
        get { selection.count == 1 ? selection.first : nil }
        set { select(newValue) }
    }

    var sheetID: TaskItem.ID? {
        didSet { if sheetID != oldValue { endSessions(in: .sheet, awayFrom: sheetID) } }
    }

    // MARK: Board interaction

    // The three drag-hover fields are computed over ignored storage so a
    // write of the value already there notifies nobody. They are written from
    // `isTargeted` callbacks that fire in bursts as the pointer crosses a
    // card's halves — several per crossing saying the same thing — and every
    // visible card reads them, so each redundant write was a full pass of
    // card re-renders for a board that looked exactly the same.

    var draggingID: TaskItem.ID? {
        get {
            access(keyPath: \.draggingID)
            return _draggingID
        }
        set {
            guard newValue != _draggingID else { return }
            withMutation(keyPath: \.draggingID) { _draggingID = newValue }
        }
    }
    @ObservationIgnored private var _draggingID: TaskItem.ID?

    var dropTargetColumnID: BoardColumn.ID? {
        get {
            access(keyPath: \.dropTargetColumnID)
            return _dropTargetColumnID
        }
        set {
            guard newValue != _dropTargetColumnID else { return }
            withMutation(keyPath: \.dropTargetColumnID) { _dropTargetColumnID = newValue }
        }
    }
    @ObservationIgnored private var _dropTargetColumnID: BoardColumn.ID?
    /// Which insertion point the pointer is over, set by the half of the card
    /// it is in — `nil` when it is over a list's own ground rather than over a
    /// card at all.
    ///
    /// **Where the pointer is, not where the card came from.** This used to be
    /// the card under the pointer, with the side worked out from the direction
    /// of travel, because that is what `move(_:onto:)` does. It cannot express
    /// the top of a list: a card dragged from anywhere earlier in board order
    /// onto the first card of a later column lands *after* it, so there was no
    /// gesture at all that put a card at the head of another column. Each card
    /// now offers its two halves separately — see `BoardTaskCard.dropZones` —
    /// and this is whichever one the pointer is in.
    ///
    /// Beside `dropTargetColumnID` rather than inside a card, because the card
    /// under the pointer and the card that has to *draw* the answer are not
    /// always the same one: a drop aimed at a column's ground is drawn against
    /// whichever of its cards holds the rank the dragged one is leaving, which
    /// is a card the pointer never touched. See ``dropCaret``.
    ///
    /// **Set by a zone the pointer enters, and never cleared by one it
    /// leaves.** A half of a card that reports the pointer gone says nothing
    /// about where it went, and the gap it was naming has by then had a
    /// ``DropPreviewCard`` opened in it — a card-shaped row that moves the card
    /// underneath it *down*, so the pointer that was in that card's upper half
    /// is now over the new row instead. Clearing on exit made that a loop: the
    /// gap shut, the cards sprang back, the pointer landed on the half again,
    /// the gap re-opened, and the stand-in flickered for as long as the drag
    /// went on. It is a loop no ordering rule can win, because the zone being
    /// entered is *created by* the claim the zone being left is about to undo.
    ///
    /// So a caret is retired by something that knows where the pointer actually
    /// went, and there are only three such facts: another zone claiming it, a
    /// list's own **ground** reporting the pointer on it — which is what
    /// `isTargeted` on a column, page or panel means, since a nested zone takes
    /// the hover from its parent — and the drag ending. The ground's report is
    /// the one that matters here: it is exactly "not in any gap any more", and
    /// it is the state whose caret is `groundCaret(in:)`'s anyway.
    var dropTargetCaret: DropCaret? {
        get {
            access(keyPath: \.dropTargetCaret)
            return _dropTargetCaret
        }
        set {
            guard newValue != _dropTargetCaret else { return }
            withMutation(keyPath: \.dropTargetCaret) { _dropTargetCaret = newValue }
        }
    }
    @ObservationIgnored private var _dropTargetCaret: DropCaret?

    var query: String = ""
    /// Where the inline "Task title, then ⏎" composer is open, or `nil` for
    /// none. A place rather than a column id, so the Inbox can have one too.
    var addingPlacement: TaskPlacement?
    /// The column the composer is open in, for a column that wants to ask
    /// whether it is the one. `nil` while it is closed, and while it is open on
    /// the Inbox — which is not a column.
    var addingColumnID: BoardColumn.ID? { addingPlacement?.columnID }
    var draft: String = ""
    /// Tokens the user has handed back out of the draft, keyed by their folded
    /// text — see ``CaptureParse/parse``. Session state and deliberately not
    /// undoable: it lives and dies with the one line being typed, and it is
    /// cleared wherever the draft is.
    var draftRejections: Set<String> = []
    /// Whether a typed title is read for `#bug`, `!high` and a trailing date.
    ///
    /// On the store rather than read from the global at each use, for the reason
    /// ``defaultDueDate`` gives: a preference read straight from `Preferences`
    /// is one a parallel test cannot change without changing what every other
    /// suite sees.
    var interpretsCapture: Bool = Preferences.interpretsCapture

    /// What the open composer's line currently says. The surface drawing the
    /// field shows this, and ``commitDraft()`` acts on it, so the chips somebody
    /// is looking at and the card they get are the same reading.
    ///
    /// `today` is read here rather than passed because the composer has no
    /// clock to hand; a draft is typed and committed inside a second or two, so
    /// the only way to see it go stale is to leave a composer open across
    /// midnight, and the card then lands on the day the ⏎ was pressed.
    var draftParse: CaptureParse {
        guard interpretsCapture else { return .plain(draft) }
        return CaptureParse.parse(
            draft, labels: labels, today: CalendarDay(.now), rejecting: draftRejections
        )
    }

    /// Hands one token back: the words stay in the title and nothing is set.
    func rejectFromDraft(_ token: CaptureParse.Token) {
        draftRejections.insert(CaptureParse.fold(token.text))
    }

    // MARK: Surfaces

    var isInspectorOpen: Bool = !BoardStore.inspectorHiddenAtLaunch

    /// `-LittleKanbanHideInspector YES`, for the same reason the Inbox has a
    /// launch argument: a UI test needs a column beside the panel, and on an
    /// iPad in portrait the inspector is holding that room.
    #if DEBUG
    static let inspectorHiddenAtLaunch = UserDefaults.standard.bool(forKey: "LittleKanbanHideInspector")
    #else
    static let inspectorHiddenAtLaunch = false
    #endif
    /// Lit while a dragged card is over the Inbox panel.
    ///
    /// A flag of its own rather than a value of `dropTargetColumnID`, because
    /// the Inbox is not a column — the same reason `TaskPlacement` has a case
    /// for it. On the store rather than in the panel so the cards *inside* the
    /// panel can set it too: a drop destination nested in another takes the
    /// hover from its parent, so without this the panel's highlight blinks off
    /// every time the pointer crosses a card in it.
    var isInboxDropTarget: Bool {
        get {
            access(keyPath: \.isInboxDropTarget)
            return _isInboxDropTarget
        }
        set {
            guard newValue != _isInboxDropTarget else { return }
            withMutation(keyPath: \.isInboxDropTarget) { _isInboxDropTarget = newValue }
        }
    }
    @ObservationIgnored private var _isInboxDropTarget: Bool = false

    /// Whether the Inbox panel is out, beside the board. Session state like the
    /// inspector, and closed to begin with unless the setting says otherwise:
    /// the sidebar row says how many cards are in there, which is enough until
    /// somebody wants them. See ``Preferences/opensInboxAtLaunch``.
    ///
    /// Decided by `applyStoredPreferences` on the restore path, which is the
    /// only one a person ever launches through — it has to run *after* the
    /// landing surface is known. A store built any other way (a test, a preview)
    /// starts with it shut.
    var isInboxOpen: Bool = false

    /// Whether the Inbox comes out with the board — the setting of the same
    /// name. On the store rather than read from `Preferences` at each use, for
    /// ``trashRetention``'s reason: a parallel test can set it here without
    /// changing what every other suite sees. Settings writes it through as well
    /// as to the defaults, so flipping the switch does not wait for a relaunch.
    var opensInboxWithTheBoard: Bool = Preferences.opensInboxAtLaunch

    /// The panel starts shut, and a harness cannot click it open: a simulator
    /// takes no synthetic taps from outside, and driving the host Mac's pointer
    /// is not a verification — it is a fight with whoever is using the machine.
    /// So there is a launch argument, the same shape as `FirstRun`'s pair:
    ///
    ///     xcrun simctl launch <device> com.n14395.LittleKanban -LittleKanbanShowInbox YES
    #if DEBUG
    static let inboxOpensAtLaunch = UserDefaults.standard.bool(forKey: "LittleKanbanShowInbox")
    #else
    static let inboxOpensAtLaunch = false
    #endif
    var isNavDrawerOpen: Bool = false
    /// Whether the keyboard-shortcuts reference is up. Session state, and on
    /// the store rather than in a view because the menu bar opens it and a
    /// surface presents it.
    var isShowingShortcuts: Bool = false
    /// Which board's settings are open, and how the sheet should arrive — see
    /// ``BoardSettingsRequest``. `nil` while it is shut.
    ///
    /// Session state, on the store for `isShowingSettings`' reason and one more:
    /// four controls on three surfaces raise this sheet — a sidebar row's menu,
    /// the phone's board menu, the drawer's board row, a column chip — and a
    /// menu can set a flag but cannot present anything. The root presents it,
    /// once, for all of them.
    var boardSettings: BoardSettingsRequest?

    /// Whether the settings surface is up. Here for the same reason the
    /// shortcuts sheet is: on macOS the `Settings` scene opens it, on iOS a
    /// drawer row does, and neither can reach the other's view tree.
    var isShowingSettings: Bool = false
    /// Whether the Trash is up.
    ///
    /// **It used to be a tab of Settings, and it was never a setting.** Every
    /// other subject in there is a preference about how the app behaves; this
    /// one is the user's own work, waiting thirty days to be either wanted again
    /// or gone. A preference can wait, and a card thrown away on Tuesday cannot
    /// wait past the thirtieth day, so it has a door of its own now: the Trash
    /// row under Views in the source list on macOS and iPad, and the board menu
    /// on the phone.
    ///
    /// On the store rather than in a view because the three doors are in three
    /// different trees — `BoardSidebar` on two platforms, `PhoneHeader` on the
    /// third — and the phone's sheet is presented by the root, which is neither.
    var isShowingTrash: Bool = false
    /// Which view the editor is open on, on the surfaces where the thing that
    /// *asks* for it is not the thing that can present it.
    ///
    /// The phone's drawer is that case, and it is `isShowingTrash`'s case
    /// exactly: a drawer row can raise a flag and not a sheet, because the
    /// drawer closes on its way out and takes any sheet it was presenting with
    /// it. `PhoneRootView` presents; the drawer only names. The two pointer
    /// surfaces keep the id in their own `@State` — the sidebar does not go
    /// anywhere when a sheet opens over it.
    var editingViewID: SavedView.ID?
    /// Whether File ▸ Export… / Import… has asked for its panel. On the store
    /// for the reason the shortcuts sheet is: the menu bar lives outside every
    /// window's view tree, and the panels are presented by a view inside one.
    /// The settings surface raises the same panels from state of its own — see
    /// `BoardTransfer` for why they are not shared.
    var isExportingBoard: Bool = false
    var isImportingBoard: Bool = false
    /// The third panel, and the last to get a menu item: exporting the board as
    /// text was a settings row and nothing else, so the one export a person
    /// pastes into a note or an issue was the one the File menu did not offer.
    var isExportingMarkdown: Bool = false
    var tab: PhoneTab = .board
    var mobileColumnID: BoardColumn.ID = BoardColumn.inProgress.id

    // MARK: Detail editing

    /// Which surface has its label picker open. The picker is per surface; the
    /// half-typed name in it is per surface *and* task — see `labelDrafts`.
    var labelPickerScope: DetailScope?

    /// A task that was just created without a title, so its detail surface can
    /// focus the title field. Cleared once a surface has consumed it.
    var pendingTitleFocusID: TaskItem.ID?

    /// A half-typed sub-task or label name belongs to the task it was typed
    /// against, not merely to the surface it was typed on: selecting another
    /// task used to carry the draft across and add it to the wrong task.
    private struct DraftKey: Hashable {
        var scope: DetailScope
        var task: TaskItem.ID
    }

    private var subtaskDrafts: [DraftKey: String] = [:]
    private var labelDrafts: [DraftKey: String] = [:]

    /// Cards a `+` made empty, each kept beside the card *as it was made*, so
    /// that closing the editor can ask whether anything in it was filled in.
    /// Membership is what keeps the question to captures: an ordinary card the
    /// user opens and closes again is not in here and is never at risk.
    ///
    /// **A capture that was typed into and emptied again is discarded too**,
    /// which is the rule this used to have the other way round. It tracked
    /// *touch* — any mutation at all took a card out of here for good — so a
    /// capture whose priority was tried and put back, or whose title was typed
    /// and deleted, or which merely started with a default due date, was left
    /// on the board as an untitled card nobody asked for. What the dismissal
    /// actually has to ask is whether the editor was closed with anything in
    /// it, and only the card itself can answer that: see
    /// ``TaskItem/hasSameContent(as:)``.
    @ObservationIgnored private var blankCaptures: [TaskItem.ID: TaskItem] = [:]

    /// One open editing session. Keyed by surface as well as task and field so
    /// two surfaces editing the same title cannot share — and corrupt — one
    /// before-value.
    private struct EditKey: Hashable {
        var scope: DetailScope
        var task: TaskItem.ID
        var field: TaskField
        /// Which sub-task the session is on; `nil` for the task's own fields.
        var subtask: SubTask.ID?
    }

    /// What a field held when its session began, so one activity entry is
    /// logged per session instead of one per keystroke or per date tried.
    private enum FieldValue: Equatable {
        case text(String)
        case day(CalendarDay?)
        case priority(Priority)
    }

    /// An open session: the value the field started on, and the entry the
    /// session has already written. A picker records its change straight away
    /// and then keeps rewriting that one entry, so an abandoned session leaves
    /// a tidy record rather than no record at all.
    private struct Session {
        var before: FieldValue
        var entryID: ActivityEntry.ID?
        /// The board as the session opened, so a session's worth of typing is
        /// one ⌘Z rather than one per keystroke.
        var undoBefore: BoardMutation
        /// When this session opened relative to the others. Two sessions can be
        /// open on different before-states, and only the oldest one's covers
        /// everything typed since the last step — see `flushSessions`.
        var openedAt: Int
    }

    private var editSessions: [EditKey: Session] = [:]

    /// Hands out `Session.openedAt`.
    @ObservationIgnored private var sessionsOpened = 0

    /// One session's unfiled keystrokes — see `textInFlight`.
    private struct InFlightText {
        var key: EditKey
        var live: String
        var floor: String
    }

    private var nextSerial: Int

    // MARK: Persistence

    /// How the board orders its cards. A preference rather than board data, so
    /// it is kept in `UserDefaults` rather than in the snapshot — and read back
    /// out only by `restored()`, so a preview or a test never picks up the
    /// developer's own setting.
    var sortOrder: BoardSortOrder = .manual {
        didSet {
            guard sortOrder != oldValue else { return }
            // The grouping memo is keyed on the board's revision, which an
            // ordering change does not bump.
            groupedCache = nil
            guard file != nil else { return }
            UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderKey)
        }
    }

    static let sortOrderKey = "LittleKanbanSortOrder"

    /// When the board last reached the disk, for the status bar. `nil` until
    /// this session has saved something.
    private(set) var lastSavedAt: Date?

    /// When the board last reached iCloud. `nil` when sync is off.
    private(set) var lastSyncedAt: Date?

    /// The last load or write failure, for an alert and the status bar.
    /// `OSLog` is not a user interface.
    private(set) var lastError: BoardStoreError?

    /// Set when the board on disk could not be used, so the launch alert can
    /// say what happened to it. Cleared by `acknowledgeLoadFailure()`.
    private(set) var loadFailure: BoardLoadFailure?

    /// True when the unusable file could not even be moved aside. The only
    /// copy of the user's work is still sitting at the board's URL, so every
    /// write is refused until they say otherwise.
    private(set) var isSaveBlocked: Bool = false

    /// True when there is a record store but its read at launch failed. The
    /// board on screen came from `board.json`; what the records hold has not
    /// been seen — so every push is withheld until a read succeeds, because
    /// `apply` with nothing to diff against rewrites every record, and
    /// rewriting records that were never read is how this device would hand
    /// another device's newer board a stale overwrite. Distinct from
    /// `isSaveBlocked`: saving to the file carries on as normal, so nothing
    /// is lost on this device either way. Every remote change, manual sync
    /// and save while blocked retries the read — see
    /// `recoverFromBlockedSync(_:)`.
    private(set) var isSyncReadBlocked = false

    /// When the block began, so recovery can tell a task this device made
    /// while blocked (kept) from one the records say was deleted (let go).
    @ObservationIgnored private var syncReadBlockedSince: Date?

    /// Where the board is saved. `nil` keeps the store purely in memory, which
    /// is what previews and tests want — they must never touch the real file.
    private let file: BoardFile?
    private var saveTask: Task<Void, Never>?

    /// The SwiftData store the board syncs through, when there is one.
    ///
    /// Both are written on every save, and they are not redundant: SwiftData
    /// holds the board as records, which is the granularity CloudKit needs to
    /// merge two devices editing different cards, and `board.json` holds it as
    /// a document, which is what backups, export and the corrupt-file rescue
    /// are built on. The read order at launch is in `restored(file:sync:)`.
    @ObservationIgnored private let sync: (any SyncStoring)?

    /// Whether the board is reaching iCloud right now. `false` when sync is
    /// off, when the entitlement is missing, and in every test.
    var isSyncing: Bool { sync?.isSyncing ?? false }

    /// A newly installed device can receive task records before the boards and
    /// columns they name. Until that import is complete, writing the temporary
    /// snapshot back would turn every unresolved task into an Inbox task.
    @ObservationIgnored private var isAwaitingCompleteSync = false

    @ObservationIgnored private var remoteChangeObserver: (any NSObjectProtocol)?

    /// The ids this device last agreed the records hold — reset by every
    /// adoption and every push. What has left the board since is the only
    /// thing a push may delete: see ``SyncIDs`` for why the diff base stopped
    /// being a deletion licence. `nil` until the records have spoken or been
    /// spoken to, which is also the state in which nothing may be deleted.
    @ObservationIgnored private var syncBaseline: SyncIDs?

    /// Bumped by every mutation. `scheduleSave()` is the one call the mutation
    /// contract requires them all to make, so bumping it there covers the lot.
    @ObservationIgnored private var boardRevision: Int = 0

    /// The app's store: the board as it was left, or a seeded one on first run.
    ///
    /// **The read order matters.** The SwiftData store is asked first, because
    /// it is the one another device can have written since this one last
    /// looked. `board.json` answers when SwiftData has nothing — a first launch
    /// after the upgrade, where the JSON board is migrated into the records —
    /// and when SwiftData cannot be opened at all, which is the failure the
    /// quarantine machinery exists for and must not look like an empty board.
    static func restored(file: BoardFile = .default, sync: (any SyncStoring)? = nil) -> BoardStore {
        // Read the records without `try?`, because `try?` makes "the store
        // opened and held nothing" and "the read failed" the same `nil` — and
        // the two must part ways at the bottom of this function, where only
        // one of them is allowed to push. See `isSyncReadBlocked`.
        var recordsUnread = false
        let records: BoardSnapshot? = {
            guard let sync else { return nil }
            do { return try sync.load() } catch { recordsUnread = true; return nil }
        }()
        if let sync, let loaded = records {
            // CloudKit applies records and relationships independently. A task
            // whose column has not arrived yet is not an Inbox task, so keep a
            // local snapshot visible, if one exists, and wait for the next
            // remote change rather than normalising and re-uploading it.
            if Self.hasUnresolvedTaskPlacements(in: loaded) {
                let local = file.load().snapshot
                let store = BoardStore(
                    tasks: local?.tasks ?? [], boards: local?.boards ?? [],
                    activeBoardID: local?.activeBoardID, labels: local?.labels ?? loaded.labels,
                    themes: local?.themes ?? loaded.themes,
                    nextSerial: local?.nextSerial ?? loaded.nextSerial,
                    trash: local?.trash ?? [], views: local?.views ?? SavedView.seededAll,
                    savedColors: local?.palette ?? PaletteSwatch.seed,
                    viewsChangedAt: local?.viewsChangedAt,
                    paletteChangedAt: local?.paletteChangedAt,
                    themesChangedAt: local?.themesChangedAt,
                    file: file, sync: sync
                )
                store.isAwaitingCompleteSync = true
                store.applyStoredPreferences()
                return store
            }

            var synced = loaded
            // `position` was added after task records had already shipped. The
            // JSON board is the local source that still knows their manual
            // order; use it only to fill ranks, never to overwrite synced task
            // content that may be newer on another device.
            if (try? sync.hasStoredTaskOrder()) == false,
               let local = file.load().snapshot {
                try? sync.backfillTaskPositions(from: local.tasks.map(\.id))
                if let positioned = try? sync.load() { synced = positioned }
            }
            // A board's mark is the same shape of problem, one version later:
            // `StoredBoard.symbol` was added at v16 and no record written
            // before it carries one, while the file beside it has been through
            // `migrate(v15:)` and carries the mark that board was *dealt*.
            // Without this the records would answer "the fallback" for every
            // board and win, and a synced install would upgrade into a sidebar
            // of identical rows — which is the one thing the step exists to
            // prevent. Fill and re-read, never overwrite a mark a record has.
            if (try? sync.hasStoredBoardSymbols()) == false,
               let local = file.load().snapshot {
                try? sync.backfillBoardSymbols(from: local.boards)
                if let marked = try? sync.load() { synced = marked }
            }
            // The board came from the records. The trash did not and never
            // does — see `BoardStore.trash` — so it is read back off the file,
            // which is written on every save whether sync is on or not.
            //
            // The other three are the ones with two possible answers: the saved
            // views, the palette and the themes are one blob apiece in one
            // record, so CloudKit cannot merge them and somebody has to choose.
            // `SharedList` is that choice, and the reason it is asked here
            // rather than assumed is the record that has *no* answer — written
            // before the attribute existed — which `load()` alone cannot tell
            // from a device reporting the defaults.
            let local = file.load().snapshot
            let shared = SharedList.resolve(
                local: local, remote: synced, carried: (try? sync.carriedLists()) ?? []
            )
            let store = BoardStore(
                tasks: synced.tasks, boards: synced.boards, activeBoardID: synced.activeBoardID,
                labels: synced.labels, themes: shared.themes,
                nextSerial: synced.nextSerial,
                trash: local?.trash ?? [],
                views: shared.views,
                savedColors: shared.palette,
                viewsChangedAt: shared.viewsChangedAt,
                paletteChangedAt: shared.paletteChangedAt,
                themesChangedAt: shared.themesChangedAt,
                file: file, sync: sync
            )
            store.applyStoredPreferences()
            // The records have spoken; what they hold is the baseline every
            // later push measures its deletions against. Before the sweeps,
            // deliberately: what a sweep archives stays a record, and a card
            // the trash sweep lets go of has genuinely left the board.
            store.syncBaseline = .of(synced)
            store.sweepTrash()
            store.sweepDone()
            return store
        }

        let result = file.load()
        let store: BoardStore
        if let snapshot = result.snapshot {
            store = BoardStore(
                tasks: snapshot.tasks,
                // No boards is adopted, not repaired. It is what `deleteBoard`
                // leaves — every card already in the global Inbox, and the
                // affordance to make another board still on screen — so seeding
                // one here would hand somebody who emptied their board list a
                // board back, with a stranger's sample cards on it. Only the
                // *absence* of a snapshot seeds.
                boards: snapshot.boards,
                activeBoardID: snapshot.activeBoardID,
                labels: snapshot.labels,
                themes: snapshot.themes,
                nextSerial: snapshot.nextSerial,
                trash: snapshot.trash,
                views: snapshot.views,
                savedColors: snapshot.palette,
                viewsChangedAt: snapshot.viewsChangedAt,
                paletteChangedAt: snapshot.paletteChangedAt,
                themesChangedAt: snapshot.themesChangedAt,
                file: file,
                sync: sync
            )
        } else {
            store = BoardStore(file: file, sync: sync)
        }
        store.adopt(result)
        store.applyStoredPreferences()
        // An app left closed for a season must not open on a trash full of
        // things it promised to have thrown away a month ago. The surface sweeps
        // again when it is looked at, for the session that stays open across the
        // boundary.
        store.sweepTrash()
        store.sweepDone()
        // Whatever the JSON said is now what the records should say — this is
        // the upgrade, or the first launch, that fills them. Unless the read
        // *failed*: an unread store is not an empty one, and pushing over it
        // is the overwrite `isSyncReadBlocked` exists to prevent, so the push
        // waits for a read to succeed instead — see `recoverFromBlockedSync`.
        if recordsUnread {
            store.isSyncReadBlocked = true
            store.syncReadBlockedSince = .now
        } else {
            store.pushToSync()
        }
        return store
    }

    /// Hands the scheduler the whole list, which is the only argument it takes.
    ///
    /// Named rather than inline because a *setting* can change what it would
    /// want from the same board — the day-before switch adds a request per card
    /// — and a switch flipped in Settings has no save behind it to ride on. The
    /// scheduler calls this back through `wantsRebuild`.
    func reconcileReminders() {
        let scheduler = NotificationScheduler.shared
        scheduler.wantsRebuild = { [weak self] in self?.reconcileReminders() }
        scheduler.reconcile(
            NotificationScheduler.reminders(
                from: tasks, isComplete: isDone, alsoTheDayBefore: scheduler.remindsTheDayBefore
            )
        )
    }

    private func applyStoredPreferences() {
        if let raw = UserDefaults.standard.string(forKey: Self.sortOrderKey),
           let order = BoardSortOrder(rawValue: raw) {
            sortOrder = order
        }
        // Which board was on screen is already board data — `activeBoardID` is
        // in the snapshot — so what this restores is the *place* standing in
        // front of it, which is session state and was lost at every quit.
        surface = Self.landingSurface
        if Preferences.resumesLastPlace,
           let raw = Preferences.defaults.string(forKey: Preferences.lastSurfaceKey) {
            // An unrecognised name is the board: it is what a downgrade leaves
            // behind, and the board is the answer that is always true.
            surface = Self.surface(named: raw, among: views)
        }
        // **After the surface, not before it.** The rule in
        // ``raiseInboxWithTheBoard()`` is about landing on the board, and a
        // launch that lands on Today has not — on the phone the Inbox is a sheet
        // drawn over whatever is there, so an unconditional raise would put the
        // panel over Today and hide the very thing the launch went to. The
        // helper reads `surface`, so it has to be told the truth about it first.
        //
        // **And after the board is loaded, because the rule asks what is in the
        // Inbox.** `restored(…)` builds the store from the file or the records
        // and calls this afterwards, so `inboxTasks` is the real Inbox by the
        // time it is read — the one exception is the awaiting-sync path, where a
        // card that arrives seconds later leaves the panel shut until the next
        // time the board is arrived at, and a panel that opened itself some
        // while after the launch would be the worse of the two.
        //
        // The `#if DEBUG` flag is not conditional: it is how a UI test asks for
        // the panel outright.
        isInboxOpen = Self.inboxOpensAtLaunch
        raiseInboxWithTheBoard()
        #if DEBUG
        // **Last, so it is the last word.** These ran at the end of `init`,
        // which was before any of the above — fine while nothing here touched
        // the surface, and wrong the moment a launch landed somewhere by
        // default: `-LittleKanbanTab board` set the board and this method put
        // Today back over it. A launch argument is a person at a terminal saying
        // where to open, and it beats what was stored.
        applyLaunchOverrides()
        #endif
    }

    /// Archives what has sat in Done longer than the setting allows.
    ///
    /// The same shape as ``sweepTrash()`` and for the same reason: it is a
    /// promise being kept rather than anything the user did, so it is not
    /// undoable and writes no activity of its own beyond the archive each card
    /// already logs. `updatedAt` is the clock it reads, which is when the card
    /// last moved — reaching Done stamps it, and so does anything done to it
    /// since, so a finished card that is still being edited is not swept out
    /// from under the person editing it.
    func sweepDone(now: Date = .now, after rule: AutoArchive = Preferences.autoArchive) {
        guard let days = rule.days else { return }
        let today = CalendarDay(now)
        let stale = tasks.filter {
            !$0.isArchived && isDone($0) && today - CalendarDay($0.updatedAt) >= days
        }
        guard !stale.isEmpty else { return }
        for task in stale { performArchive(task.id, at: now) }
        scheduleSave()
    }

    init(
        tasks: [TaskItem] = SeedData.tasks,
        boards: [Board] = SeedData.boards,
        activeBoardID: Board.ID? = nil,
        labels: [LabelDef] = LabelDef.seed,
        themes: ThemeSettings = .seed,
        nextSerial: Int = BoardSnapshot.baseSerial,
        trash: [TrashedItem] = [],
        views: [SavedView] = SavedView.seededAll,
        savedColors: [PaletteSwatch] = PaletteSwatch.seed,
        viewsChangedAt: Date? = nil,
        paletteChangedAt: Date? = nil,
        themesChangedAt: Date? = nil,
        file: BoardFile? = nil,
        sync: (any SyncStoring)? = nil
    ) {
        self.sync = sync
        self.tasks = Self.placed(tasks, on: boards)
        self.boards = boards
        // Kept exactly as handed over. An initialiser that quietly dropped rows
        // would be a value constructor with a policy in it, and the policy —
        // thirty days — belongs at the two moments that are about the trash:
        // `restored(file:sync:)` on the way in, and the surface on the way to
        // being looked at. See `sweepTrash()`.
        self.trash = trash
        self.activeBoardID = boards.contains { $0.id == activeBoardID } ? activeBoardID : boards.first?.id
        self.labels = labels
        // A file whose views have been hand-edited away gets the seven back, for
        // the palette's reason below: a sidebar with no views in it offers no
        // way to make one, since **New view** is drawn under the list it would
        // join. Deleting them one at a time is still allowed — that leaves the
        // row, and the file keeps an empty array.
        self.views = views
        // A file whose palette has been hand-edited down to nothing gets the
        // six back: a picker with no colours in it offers no way to put one
        // there, which is a corner the interface cannot climb out of.
        self.savedColors = savedColors.isEmpty ? PaletteSwatch.seed : savedColors
        self.themes = themes
        // Straight from the file, and `nil` where it had none to give: a board
        // written before v15 carries three lists nobody dated, and saying so is
        // what makes the first merge keep both sides. A `didSet` cannot fire
        // during an initialiser, so these are exactly what was handed over.
        self.viewsChangedAt = viewsChangedAt
        self.paletteChangedAt = paletteChangedAt
        self.themesChangedAt = themesChangedAt
        self.nextSerial = nextSerial
        self.file = file
        let picked = tasks.first { $0.id == SeedData.dragAndDropTaskID }?.id ?? tasks.first?.id
        self.selection = picked.map { [$0] } ?? []
        self.selectionAnchor = picked
        // Which column the phone opens on is session state, so it is not saved
        // and every launch starts at the property's default — which is a *seed*
        // column id, and a board the user made carries ids of its own
        // (`Board.startingColumns()`). Opening on one of those left
        // `mobileColumnID` naming no column on the board: every chip unlit,
        // while the list and the add row showed the first column through
        // `mobileColumnIndex`'s `?? 0`. Switching boards and undoing already
        // move the phone off a column that is not there; a launch is the third
        // way onto a board and had nowhere to do it.
        detachSurfacesFromMissingColumns()
    }

    /// A store with one board carrying `columns` — what a test or a preview
    /// that is about columns rather than about boards wants to say.
    convenience init(
        tasks: [TaskItem] = SeedData.tasks,
        columns: [BoardColumn],
        labels: [LabelDef] = LabelDef.seed,
        themes: ThemeSettings = .seed,
        nextSerial: Int = BoardSnapshot.baseSerial,
        file: BoardFile? = nil
    ) {
        var board = SeedData.defaultBoard
        board.columns = columns
        self.init(tasks: tasks, boards: [board], activeBoardID: board.id, labels: labels,
                  themes: themes, nextSerial: nextSerial, file: file)
    }

    /// Every task put back through `TaskPlacement` against the boards it is
    /// arriving with, which is what stops an illegal pair reaching the board.
    ///
    /// The column is the fact that decides, because it is the one on screen and
    /// because column ids are unique across boards: a card naming a column
    /// lands on whichever board has it, whether it arrived with that board's id,
    /// with another's, or — as fixtures and previews write them — with none. A
    /// card naming no column, or one no board has, is unfiled rather than
    /// dropped: it is still the user's, and the Inbox is where it can be found
    /// again.
    ///
    /// Ids are unique here too, first one wins, the same way the column-owner
    /// map settles two boards claiming one column. A file with two cards under
    /// one id would put both on the board, where `self[id]`, `deleteTask`,
    /// `move` and every editing session reach only the first — leaving the
    /// second visible, addressed by nothing, and un-deletable.
    ///
    /// The memberwise initialiser can spell an illegal pair — it is what
    /// decoding and the fixtures build tasks with — so this is where every set
    /// of tasks the store adopts is checked.
    private static func placed(_ tasks: [TaskItem], on boards: [Board]) -> [TaskItem] {
        let owner = Dictionary(
            boards.flatMap { board in board.columns.map { ($0.id, board.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        var seen: Set<TaskItem.ID> = []
        return tasks.compactMap { task in
            guard seen.insert(task.id).inserted else { return nil }
            var task = task
            if let columnID = task.columnID, let boardID = owner[columnID] {
                task.placement = .column(board: boardID, column: columnID)
            } else {
                task.placement = .inbox
            }
            return task
        }
    }

    /// A sync snapshot is incomplete while any task names a column that has not
    /// arrived. This is distinct from an Inbox task, which names no column at
    /// all, and from a real board deletion, whose task records are unfiled in
    /// the same remote update.
    ///
    /// The rule lives on ``BoardSnapshot/hasUnresolvedPlacements`` because the
    /// record store needs the same answer for a different question — whether a
    /// read is whole enough to become its diff base. See it for what happened
    /// when only this side asked.
    private static func hasUnresolvedTaskPlacements(in snapshot: BoardSnapshot) -> Bool {
        snapshot.hasUnresolvedPlacements
    }

    // MARK: - Persistence

    private var snapshot: BoardSnapshot {
        BoardSnapshot(tasks: tasks, boards: boards, labels: labels, nextSerial: nextSerial,
                      activeBoardID: activeBoardID, trash: trash,
                      views: views, palette: savedColors, themes: themes,
                      viewsChangedAt: viewsChangedAt, paletteChangedAt: paletteChangedAt,
                      themesChangedAt: themesChangedAt)
    }

    /// Takes on what the load found: a failure to show, and whether saving has
    /// to stop to protect the file it could not read.
    private func adopt(_ result: BoardLoadResult) {
        guard let failure = result.failure else {
            // A migrated board only exists in the new shape in memory until
            // this lands. `BoardFile` has already kept the pre-migration bytes.
            if result.migratedFromVersion != nil { scheduleSave() }
            return
        }
        loadFailure = failure
        lastError = .load(failure)
        switch failure {
        case .unreadable(let quarantinedAt), .newerVersion(_, let quarantinedAt):
            isSaveBlocked = quarantinedAt == nil
        }
    }

    /// Where the unusable board file was put, when it could be moved at all.
    var quarantinedBoardURL: URL? {
        switch loadFailure {
        case .unreadable(let at), .newerVersion(_, let at): at
        case nil: nil
        }
    }

    /// Coalesces a burst of edits into a single write. Typing a title mutates
    /// the board on every keystroke, so this waits for the typing to stop.
    ///
    /// The snapshot is taken when the debounce *fires*, not here. Taken here
    /// and held across the wait, it kept a second reference on every one of
    /// the board's arrays for the whole 500ms — so the next keystroke's
    /// in-place write into `tasks` paid a full copy-on-write of the array,
    /// per character typed, and the undo stack held a hundred distinct
    /// buffers instead of a hundred views of a few. The task captures `self`
    /// strongly instead, which costs no copy and keeps the old guarantee:
    /// an edit made just before the store goes away still reaches the disk,
    /// because the store cannot go away until its last debounce has fired —
    /// at most half a second after the reference that kept it drops.
    private func scheduleSave() {
        boardRevision &+= 1
        guard let file else { return }
        // A blocked file is only a blocked *file*. The followers still ride
        // the debounce — the records, and off the test host the reminders, the
        // Spotlight index and the widgets — because none of them is the file
        // being protected, and the session's edits are nowhere else: a blocked
        // session used to accumulate work that reached nothing at all, ended
        // by a quit that kept none of it. Only the write is withheld, by
        // claiming no generation, which also means a block lifted
        // mid-debounce writes nothing until the next edit asks it to.
        //
        // The generation is otherwise claimed *now*: the write's place in the
        // file's order is a fact about when the edit happened, and a restore
        // racing this write from another store over the same path has to see
        // it as the older one. Only the snapshot waits for the debounce.
        let generation = isSaveBlocked ? nil : file.nextWriteGeneration()
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            // Everything O(board) rides the debounce, so a burst of keystrokes
            // pays each cost once rather than per character. All of it used to
            // run inline, and on a large board the reconciles plus the record
            // diff were most of what a keystroke cost.
            let pending = self.snapshot
            self.reconcileSystemsAndSync(pending)
            guard let generation else { return }
            // Off the main actor: encoding the board and writing it are the two
            // things in a keystroke's path that grow with the board's size.
            let outcome = await Task.detached(priority: .utility) { () -> SaveOutcome in
                do {
                    guard try file.write(pending, generation: generation) else { return .superseded }
                    file.backupIfDue()
                    return .wrote
                } catch {
                    return .failed(error.localizedDescription)
                }
            }.value
            self.recordSave(outcome)
        }
    }

    /// The three followers every save carries: reminders, the Spotlight index,
    /// and the records CloudKit syncs.
    ///
    /// Reminders and the Spotlight index follow the board from here rather
    /// than from each mutation, because every mutation already comes through
    /// the save funnel — the bulk commands, a drag into Done, undo and redo
    /// included — and a per-call-site hook silently misses all of them. Both
    /// reconcile against what they last published, so a keystroke that
    /// changes no due date sends nothing.
    ///
    /// `BoardFile.isRunningTests` guards the first two for the same reason it
    /// steps `.default` aside — `xcodebuild test` launches this app as the test
    /// host under its real bundle identifier, so the suite's stores are
    /// file-backed and the Notification Centre and Spotlight index they would
    /// reach are the developer's own. A test that wants to drive the scheduler
    /// injects a fake `TaskNotificationCenter` instead of coming through here.
    ///
    /// The records go last and on this actor: SwiftData's main context is
    /// main-actor work, and `apply` only touches what changed, so the cost
    /// is one card's worth rather than the board's.
    private func reconcileSystemsAndSync(_ pending: BoardSnapshot) {
        if !BoardFile.isRunningTests {
            reconcileReminders()
            TaskSpotlightIndex.shared.reconcile(tasks)
            // The fourth follower, and here for the same three reasons: every
            // mutation comes through this funnel, it is O(board) and belongs on
            // the debounce, and it reconciles against what it last published so
            // a keystroke that changes no widget writes nothing. The day is read
            // off the clock here rather than passed down — a save is not a
            // moment anything knows the date at — and `RootView` publishes again
            // when the day rolls over under a board nobody is editing.
            WidgetPublisher.publish(self, today: .today())
        }
        if isSyncReadBlocked, let sync {
            // A save is also the retry cadence for a blocked read. Without
            // it, a device whose read failed and that then receives no
            // remote-change notification — sync local-only, or CloudKit
            // quiet — would stay blocked for the whole session.
            recoverFromBlockedSync(sync)
        } else {
            pushToSync(pending)
        }
    }

    /// Writes at once, for backgrounding and quit — points where the debounce
    /// would never get to fire and the last edit would be lost. Synchronous on
    /// purpose: at quit the ordering genuinely matters.
    func saveNow() {
        guard let file else { return }
        saveTask?.cancel()
        saveTask = nil
        // The cancelled task was carrying the followers as well as the write,
        // so they run here — at quit, an edit's reminder must not be lost with
        // the debounce. They run while saving is blocked too, and at quit that
        // is the moment it pays: the records are the only place a blocked
        // session's last edits survive to.
        reconcileSystemsAndSync(snapshot)
        guard !isSaveBlocked else { return }
        do {
            let wrote = try file.write(snapshot, generation: file.nextWriteGeneration())
            recordSave(wrote ? .wrote : .superseded)
        } catch {
            recordSave(.failed(error.localizedDescription))
        }
    }

    // MARK: - Sync

    /// Writes the board into the records CloudKit syncs.
    ///
    /// A failure here is not a failure to save: `board.json` is written on the
    /// same path and is what recovery reads, so the board is safe on this
    /// device either way. It is reported so the surface can say the board is
    /// not reaching the user's other devices, which is a different sentence.
    private func pushToSync(_ board: BoardSnapshot? = nil) {
        guard let sync, !isAwaitingCompleteSync, !isSyncReadBlocked else { return }
        let pending = board ?? snapshot
        // What left the board since the records last spoke is a deletion made
        // on this device — the verbs, the trash, an undo of a creation, all of
        // them, because nothing else takes ids out of the board. A merge does
        // not: it resets the baseline instead, in `adoptSyncedBoard`'s callers.
        let deleting = syncBaseline.map { $0.subtracting(.of(pending)) } ?? .none
        do {
            try sync.apply(pending, deleting: deleting)
            syncBaseline = .of(pending)
            if case .sync = lastError { lastError = nil }
        } catch {
            lastError = .sync(message: error.localizedDescription)
        }
    }

    /// Adopts what another device changed.
    ///
    /// The records are authoritative here — CloudKit has already merged the
    /// two sides — but they are only authoritative about what they have been
    /// *told*: the push rides the save debounce, so this device's newest edits
    /// can still be in flight when the change notification lands, and reading
    /// the records back without sending them first adopted a board from half a
    /// second ago. A board made just before a merge vanished from the sidebar
    /// with its settings sheet still open on it — that was this. So what is
    /// pending goes in first; the read then returns the union, this device's
    /// unsent edits winning the records they touched, which is the
    /// last-writer-wins the schema already promises everywhere else.
    ///
    /// What is already here is not adopted again — see `brings(somethingNew:)`
    /// for why the difference matters even though writing the same values twice
    /// would not show.
    ///
    /// The undo stack is deliberately left alone — a step that reversed
    /// somebody else's edit on their behalf would be worse than no step at
    /// all. And the diff base is *not* invalidated any more: `load()` has just
    /// set it to exactly what the records hold, which is the one thing a diff
    /// base has to be. Nil-ing it made the next apply rewrite every record —
    /// and now that a merge can write, that rewrite's own change notification
    /// would arrive back here as another merge, around forever.
    @discardableResult
    func mergeRemoteChanges() -> Bool {
        guard let sync else { return false }
        // While the records stand unread, the push-first order below is the
        // hazard itself — see `recoverFromBlockedSync`, which reads first.
        if isSyncReadBlocked { return recoverFromBlockedSync(sync) }
        pushToSync()
        guard let incoming = try? sync.load() else { return false }
        guard !Self.hasUnresolvedTaskPlacements(in: incoming) else { return false }
        isAwaitingCompleteSync = false
        let shared = resolvingSharedLists(with: incoming, in: sync)
        guard brings(somethingNew: incoming, resolvedTo: shared) else { return false }
        adoptSyncedBoard(incoming, sharing: shared)
        lastSyncedAt = .now
        return true
    }

    /// Whether the records hold anything this board does not already have.
    ///
    /// A read is not news. The notification fires for this device's own push
    /// coming back as well as for another device's, and a user on a touch
    /// platform can now ask for a read by hand, at whatever moment they like —
    /// see
    /// ``syncNow(settling:)``. Adopting what is already here is invisible in the
    /// board, because the mutation writes the same values over the same values;
    /// the *stamp* beside it is not, and `lastSyncedAt` is the sentence Settings
    /// prints as "last change from another device". A board with nothing to say
    /// would have been saying it in the present tense, once per pull.
    ///
    /// Compared against exactly what `adoptSyncedBoard` takes and nothing else:
    /// the trash and the active board stay this device's own across a merge, so
    /// a difference in one of them is not something arriving.
    ///
    /// **The two shared lists are compared after the merge rule has run, not
    /// before.** What arrives from the records is one of two answers rather
    /// than the answer — see ``SharedList`` — so the question here is whether
    /// what *stands* differs from what this board holds. Asking it of the raw
    /// read instead reported news on every single pull to anybody whose views
    /// were not the seeded seven, which is a stamp in Settings saying another
    /// device had changed something when none had.
    ///
    /// The themes are left out on purpose, as they always have been: they are
    /// resolved at launch — see `restored(file:sync:)` — because repainting the
    /// window under somebody mid-sentence is worse than showing them yesterday's
    /// palette until they next open the app.
    private func brings(somethingNew incoming: BoardSnapshot, resolvedTo shared: SharedList.Outcome) -> Bool {
        Self.placed(incoming.tasks, on: incoming.boards) != tasks
            || incoming.boards != boards
            || incoming.labels != labels
            || incoming.nextSerial != nextSerial
            || shared.views != views
            || shared.palette != savedColors
    }

    /// What the records' answer about the three shared lists comes to, against
    /// this board's own. One call for the pull and the blocked-read recovery
    /// alike; the launch asks the same question of the same function.
    private func resolvingSharedLists(
        with incoming: BoardSnapshot, in sync: any SyncStoring
    ) -> SharedList.Outcome {
        SharedList.resolve(
            local: snapshot, remote: incoming, carried: (try? sync.carriedLists()) ?? []
        )
    }

    /// The read the launch could not make, tried again.
    ///
    /// The normal merge order — push, then read back the union — is not
    /// available while the records stand unread: the push's diff base is
    /// empty, so it would rewrite every record from a board that never saw
    /// what they hold. So the read comes first, and the two sides are merged
    /// at the one granularity that carries a timestamp — per task, newer
    /// `updatedAt` wins, the same last-writer-wins the schema settles
    /// duplicate records with; see `merging(localTasks:intoRemote:...)` for
    /// the tasks only one side has. Everything coarser — boards, labels,
    /// views, the palette — has no timestamp to argue with, so the records
    /// win, exactly as they do in `mergeRemoteChanges`.
    ///
    /// The push at the end is what sends the tasks the local side won, and it
    /// is safe by then: `load()` has just set the diff base to exactly what
    /// the records hold, so it writes those tasks and nothing else. A store
    /// that reads back empty is not a failure — it is a store that has been
    /// reset, and the board on this device is all there is, so the same push
    /// seeds it the way a first launch would have.
    ///
    /// Returns what `mergeRemoteChanges` returns: whether anything was
    /// adopted, which is the sentence `syncNow` shows.
    @discardableResult
    private func recoverFromBlockedSync(_ sync: any SyncStoring) -> Bool {
        let incoming: BoardSnapshot?
        do { incoming = try sync.load() } catch { return false }
        var adopted = false
        if let incoming {
            guard !Self.hasUnresolvedTaskPlacements(in: incoming) else { return false }
            var merged = incoming
            merged.tasks = Self.merging(
                localTasks: tasks, intoRemote: incoming.tasks,
                keepingLocalOnlyTouchedSince: syncReadBlockedSince
            )
            isSyncReadBlocked = false
            syncReadBlockedSince = nil
            let shared = resolvingSharedLists(with: merged, in: sync)
            if brings(somethingNew: merged, resolvedTo: shared) {
                adoptSyncedBoard(merged, sharing: shared)
                lastSyncedAt = .now
                adopted = true
            }
        } else {
            isSyncReadBlocked = false
            syncReadBlockedSince = nil
        }
        pushToSync()
        return adopted
    }

    /// The per-task half of `recoverFromBlockedSync`'s merge — the one place
    /// the app merges by hand, because CloudKit was never shown this device's
    /// side. Value-in, value-out, for the tests.
    ///
    /// A task both sides hold goes to the newer `updatedAt`. A task only the
    /// records hold arrived from another device and is adopted. A task only
    /// this side holds is kept if it was touched while blocked — it was just
    /// made or edited here, and the records never saw it — and otherwise let
    /// go, because a task this device knows and the records no longer hold is
    /// one another device deleted. With no `blockedSince` to ask, keeping it
    /// is the answer: a resurrected card can be deleted again, a lost one is
    /// gone.
    ///
    /// Order is the records': a board unseen since launch has no manual order
    /// worth arguing for, and a kept local-only task lands at the end, which
    /// the next drag can fix and a silent loss could not.
    static func merging(
        localTasks: [TaskItem], intoRemote remote: [TaskItem],
        keepingLocalOnlyTouchedSince blockedSince: Date?
    ) -> [TaskItem] {
        let localByID = Dictionary(localTasks.map { ($0.id, $0) },
                                   uniquingKeysWith: { first, _ in first })
        let remoteIDs = Set(remote.map(\.id))
        var merged = remote.map { theirs in
            guard let ours = localByID[theirs.id], ours.updatedAt > theirs.updatedAt else {
                return theirs
            }
            return ours
        }
        merged.append(contentsOf: localTasks.filter { mine in
            guard !remoteIDs.contains(mine.id) else { return false }
            guard let blockedSince else { return true }
            return mine.updatedAt >= blockedSince
        })
        return merged
    }

    /// A pull past the top of a list of cards, which is how iPhone and iPad ask
    /// for a sync. See ``PullToSync``.
    ///
    /// **There is no fetch to call — but there is one lever, and this pulls
    /// it.** The mirroring container schedules its own trips to CloudKit and
    /// takes no instruction about when one happens, with the single exception
    /// it does not know it offers: opening the store runs its import at once,
    /// which is why relaunching the app always "synced" when this button did
    /// not. So the sync store reopens its container first — see
    /// ``BoardSyncStore/reconnect()`` — and then this does the half that
    /// belongs to this device: whatever has not been pushed goes now — the
    /// push rides the save debounce, so a card ticked a moment ago may still
    /// be sitting here — and whatever has come down is adopted, once before
    /// the settling pause for what was already here, and once after it for
    /// what the fresh mirror brought.
    ///
    /// Then it holds the spinner a beat, which is not decoration. The board is
    /// mirrored asynchronously, so a change provoked by that push lands through
    /// `mergeRemoteChanges` shortly after this returns; the beat is the
    /// difference between the other device's card appearing under the spinner
    /// and appearing a moment after the user has decided the pull did nothing.
    /// Zero for tests, which have no spinner and no patience.
    ///
    /// Returns whether the read brought anything — for the suite; nothing on
    /// screen asks, because "up to date" and "here is what arrived" are the
    /// same gesture from the user's end and the list says which it was.
    @discardableResult
    func syncNow(settling: Duration = .milliseconds(800)) async -> Bool {
        guard let sync else { return false }
        // The fetch first, such as it is: reopening the container is the one
        // way to make the mirror go to CloudKit rather than wait to be told —
        // see ``BoardSyncStore/reconnect()``. Then the merge picks up whatever
        // is already here, the settling pause gives a fast import its chance,
        // and the second merge picks up what the pause let land; anything
        // slower arrives through the remote-change notifications like always.
        sync.reconnect()
        var arrived = mergeRemoteChanges()
        try? await Task.sleep(for: settling)
        arrived = mergeRemoteChanges() || arrived
        // Raised *after* the wait, so the sentence lands as the spinner leaves
        // rather than under it — and only for a check somebody asked for. A
        // merge arriving on its own says what it has to say by changing the
        // board; a card announcing every push another device made would be a
        // notification nobody asked for, several times an hour.
        announcement = .synced(adopted: arrived)
        return arrived
    }

    /// Starts listening for another device's changes. Called by `RootView`;
    /// safe to call twice.
    func beginObservingRemoteChanges() {
        guard sync?.isSyncing == true, remoteChangeObserver == nil else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            // The `Bool` says whether anything was adopted, which is a fact for
            // whoever *asked* for a merge — a push nobody asked for has no
            // caller to tell, so it is dropped rather than returned out of the
            // closure and silently ignored.
            MainActor.assumeIsolated { _ = self?.mergeRemoteChanges() }
        }
    }

    private func recordSave(_ outcome: SaveOutcome) {
        switch outcome {
        case .wrote:
            lastSavedAt = .now
            if case .save = lastError { lastError = nil }
        case .superseded:
            // A newer save reached the disk first and stamped the time itself.
            break
        case .failed(let message):
            lastError = .save(message: message)
        }
    }

    /// Clears the last failure without changing anything else — the status bar
    /// and the alert both offer it.
    func dismissError() {
        lastError = nil
    }

    /// The user has been told their board could not be read and has chosen to
    /// carry on with the fresh one.
    ///
    /// When saving was blocked, the unreadable file is still sitting at the
    /// board's URL and is the only copy of their work, so acknowledging does
    /// not simply unblock: it tries once more to get the file out of the way —
    /// whatever stopped the move at launch may be over — and keeps saving
    /// blocked, loudly, if it still cannot.
    func acknowledgeLoadFailure() {
        defer {
            loadFailure = nil
            if case .load = lastError { lastError = nil }
        }
        guard isSaveBlocked, let file else {
            isSaveBlocked = false
            return
        }
        switch file.rescueUnreadable(reason: quarantineReason) {
        case .nothingToRescue, .preserved:
            isSaveBlocked = false
        case .failed:
            lastError = .save(message: String(
                localized: "Your board file could not be moved aside, so saving stays paused rather than writing over it.",
                comment: "Status shown when the damaged board file still cannot be protected and saving stays off"
            ))
        }
    }

    /// What to call the file being set aside, so the name says what was wrong
    /// with it — the same names `load()` uses.
    private var quarantineReason: String {
        switch loadFailure {
        case .newerVersion(let version, _): "from-newer-version-\(version)"
        case .unreadable, nil: "corrupt"
        }
    }

    // MARK: - Export, import and restore

    /// The board as it would be written to disk, for an export.
    var exportedSnapshot: BoardSnapshot { snapshot }

    /// Where the board is saved, or `nil` for an in-memory store.
    var boardFileURL: URL? { file?.url }

    /// The rolling backups, newest first. A function rather than a property
    /// because it reads a directory: the settings surface asks once, when it
    /// opens the list, rather than on every render.
    func availableBackups() -> [BoardBackup] { file?.recentBackups() ?? [] }

    /// Folds an imported board into this one, and says what it did.
    ///
    /// One undo step for the lot — see `BoardSnapshot.merging` for the merge
    /// rules. An import that changed nothing files no step, so re-importing the
    /// same file does not leave a ⌘Z that does nothing.
    @discardableResult
    func importBoard(_ incoming: BoardSnapshot) -> BoardImportSummary {
        let merged = snapshot.merging(incoming)
        guard merged.summary.changedAnything else { return merged.summary }
        undoable(String(localized: "Import Board",
                        comment: "Undo action name for merging an imported board into this one")) {
            adoptContent(merged.snapshot)
        }
        return merged.summary
    }

    /// Puts a backup back — as an edit to the board rather than a file move, so
    /// ⌘Z takes it back like anything else.
    ///
    /// The board as it stands is written and copied into `backups/` first. A
    /// restore is the one action here that leaves the current board reachable
    /// only through the undo stack, and an undo stack does not survive a quit.
    ///
    /// **First, not every time.** Finding the right backup is a hunt — restore
    /// one, look at the board, restore the next — and a safety copy taken per
    /// attempt turned the hunt against itself: every look grew the list being
    /// searched, three copies in eleven seconds on a real machine, each one
    /// pushing the history the person was hunting through towards the
    /// "backups to keep" cap. So the copy is skipped when the board as it
    /// stands *is* a backup already — untouched since the last restore, or
    /// byte-for-byte what the safety pass last copied (which is where an undo
    /// of the first attempt lands). Only the board that exists nowhere else —
    /// the one the hunt started from, or one edited since an attempt — costs
    /// the list a row. The memory is session state on purpose: after a
    /// relaunch the first restore copies again, which errs toward keeping.
    ///
    /// Nothing here defeats the file's write ordering: `scheduleSave()` claims
    /// its generation when the restore is queued, so a debounced write issued
    /// before it is by definition the older one and is dropped rather than
    /// landing on top of the restored board.
    func restore(fromBackup url: URL) throws {
        guard let file else { throw BoardFileError.unreadable }
        // Before anything is disturbed: a backup that cannot be read must leave
        // the board exactly as it was.
        let restored = try file.restore(from: url)
        let standing = snapshot
        if standing != boardAfterLastRestore && standing != boardLastCopied {
            saveNow()
            keepACopy(with: file)
            boardLastCopied = standing
        }
        undoable(String(localized: "Restore Backup",
                        comment: "Undo action name for putting a backup of the board back")) {
            adoptContent(restored)
        }
        boardAfterLastRestore = snapshot
    }

    /// What the last restore left on the board, and what the safety pass last
    /// copied into `backups/` — the two boards already in the list, which a
    /// further restore need not copy again. See ``restore(fromBackup:)``.
    @ObservationIgnored private var boardAfterLastRestore: BoardSnapshot?
    @ObservationIgnored private var boardLastCopied: BoardSnapshot?

    /// Throws the whole board away and starts again from `template`, keeping a
    /// backup of what was there.
    ///
    /// **One undoable step, and it is taken here rather than in two halves.**
    /// The obvious shape — empty the board when the warning is accepted, then
    /// fold in whatever the picker returns — costs two ⌘Z to get back from, and
    /// leaves a window where the board is gone and the picker is still up: undo
    /// in that window brings the board back underneath a modal that has no way
    /// out but to destroy it again. So nothing is thrown away until a template
    /// arrives, which is also what lets the picker have a Cancel that means
    /// something.
    ///
    /// A replacement rather than `importBoard`'s merge: that one folds a board
    /// into what is already there, which is right for a first launch, where
    /// what is already there is nothing.
    ///
    /// The accent is left alone — it is a preference the user set, not part of
    /// the board being replaced — and `apply` moves `activeBoardID` onto the
    /// new board, since the one it named has just gone.
    func startOver(with template: BoardSnapshot) {
        saveNow()
        if let file { keepACopy(with: file) }
        undoable(String(localized: "Start Over",
                        comment: "Undo action name for replacing the whole board with a starter template")) {
            adoptContent(template)
        }
    }

    /// Puts the board as it stands into `backups/` before something replaces it,
    /// and says so if it could not.
    ///
    /// Not a refusal: the user asked to replace the board and the copy is a
    /// courtesy, and a `backups/` that cannot be written to is a condition the
    /// next save will report anyway. But it may not pass unremarked — this is
    /// the copy the whole "restore is undoable" promise falls back on once the
    /// session that could undo it has ended.
    private func keepACopy(with file: BoardFile) {
        guard file.backupNow(keeping: Preferences.backupsKept.count) == nil else { return }
        lastError = .save(message: String(
            localized: "A copy of the board could not be kept before it was replaced.",
            comment: "Status shown when the safety backup taken before a restore or a reset failed"
        ))
    }

    /// Takes on a whole board at once, through the same `apply` an undo uses —
    /// so the caches, the open editing sessions and any selection naming a task
    /// that has just gone are all tidied by the one piece of code that knows how.
    ///
    /// The tasks go back through `placed` because they arrived from a file: an
    /// import or a backup can name a column no board here has, and an unplaceable
    /// card belongs in the Inbox rather than nowhere.
    ///
    /// `themes` and `activeBoardID` are deliberately not adopted. The first is
    /// how this machine has been set to look, and the second is where the user
    /// is looking — neither is the arriving file's to change. **Importing a
    /// board should not repaint the app**, which is exactly what adopting the
    /// themes would do: a board exported from a Neon Grid install would turn a
    /// Porcelain one black on the way in. Themes travel by their own door — see
    /// `ThemeDocument` and the theme editor's import.
    ///
    /// The **trash is not adopted either**, and it is the clearest case of the
    /// three. An import is somebody else's file, and their thrown-away boards
    /// are not things this user should be offered back. A backup is this user's
    /// own file from an earlier moment, which sounds like the opposite — but
    /// taking its trash would resurrect the things they have permanently deleted
    /// since, which is the one act in the app that is meant to stick. Either way
    /// what is carried across is the *board*; the trash stays this session's.
    private func adoptContent(_ content: BoardSnapshot) {
        adopt(
            content,
            views: content.views,
            // Dated now rather than carried across from the file. An import, a
            // restore and a starter template are all edits somebody is making
            // on this device at this moment, whatever date the bytes were
            // written on — and the merge rule reads the date as "when was this
            // decided", so carrying a backup's three-month-old stamp would let
            // any other device overrule a restore the moment it synced.
            viewsChangedAt: .now,
            // Somebody else's file brings their palette with it: it is board
            // content like the labels, and an import that kept this board's six
            // would leave every imported label wearing a colour the picker no
            // longer offers.
            savedColors: content.palette,
            paletteChangedAt: .now
        )
    }

    /// The same board arriving from the **records**, where two of those lists
    /// have already been through the merge rule.
    ///
    /// That is what separates this from ``adoptContent(_:)``. A *file* is a
    /// whole document, and its views and palette are the arriving work, adopted
    /// whole and dated now. A *record set* is one of two live answers, and
    /// which one stands — or whether both do, merged — is ``SharedList``'s to
    /// say; by the time it reaches here the question has been asked, so this
    /// takes the outcome rather than the read.
    private func adoptSyncedBoard(_ content: BoardSnapshot, sharing shared: SharedList.Outcome) {
        // The records have spoken again; deletions are measured from here.
        // This is what keeps a merge from ever being read back to the records
        // as this device's editing: only what leaves the board *after* this
        // moment is anybody's deletion.
        syncBaseline = .of(content)
        adopt(
            content,
            views: shared.views, viewsChangedAt: shared.viewsChangedAt,
            savedColors: shared.palette, paletteChangedAt: shared.paletteChangedAt
        )
    }

    private func adopt(
        _ content: BoardSnapshot,
        views: [SavedView], viewsChangedAt: Date?,
        savedColors: [PaletteSwatch], paletteChangedAt: Date?
    ) {
        apply(BoardMutation(
            tasks: Self.placed(content.tasks, on: content.boards),
            labels: content.labels,
            nextSerial: content.nextSerial,
            boards: content.boards,
            trash: trash,
            views: views,
            savedColors: savedColors,
            viewsChangedAt: viewsChangedAt,
            paletteChangedAt: paletteChangedAt
        ))
        scheduleSave()
    }

    // MARK: - Undo

    /// The window's undo manager, handed over by `RootView`: the store cannot
    /// reach the environment itself. Weak, because the window owns it.
    @ObservationIgnored weak var undoManager: UndoManager?

    /// Depth of `undoable` nesting, so a mutation built out of other mutations
    /// costs exactly one ⌘Z rather than one per part.
    @ObservationIgnored private var undoDepth = 0

    /// Set while an undo or redo is being applied. Restoring the board can end
    /// a session a surface left open, and a mutation registering itself in the
    /// middle of an undo would rewrite the redo stack it is standing on.
    @ObservationIgnored private var isApplyingUndo = false

    var canUndo: Bool { undoManager?.canUndo ?? false }
    var canRedo: Bool { undoManager?.canRedo ?? false }

    private var mutation: BoardMutation {
        BoardMutation(tasks: tasks, labels: labels, nextSerial: nextSerial, boards: boards,
                      trash: trash, views: views, savedColors: savedColors,
                      viewsChangedAt: viewsChangedAt, paletteChangedAt: paletteChangedAt)
    }

    /// Runs `body` as one undoable step named `name`.
    ///
    /// Snapshot-based rather than an inverse written per mutation: an inverse
    /// that does not quite match its forward operation is where undo bugs live,
    /// and the board is cheap to hold. Nested calls collapse into the outer
    /// step, so a mutation assembled from other mutations still costs one ⌘Z.
    ///
    /// The rule the whole file follows, because a snapshot step reverses
    /// *everything* the board did since its before-state and so is only safe
    /// while that state is recent:
    ///
    /// > Every board mutation registers its own undo step immediately. Editing
    /// > sessions coalesce *activity entries*, not undo steps — with one
    /// > exception: continuous text, where a session groups the keystrokes it
    /// > owns and nothing else.
    ///
    /// The exception is what `setText` and `updateSubtask` rely on: they write
    /// per keystroke and register nothing, and every call site brackets them
    /// with `beginEditing`/`endEditing`. `endEditing` is what registers, and
    /// `flushSessions` followed by `rebaseSessions` is what keeps "and nothing
    /// else" true at every other step boundary.
    func undoable(_ name: String, _ body: () -> Void) {
        guard undoDepth == 0, !isApplyingUndo else {
            body()
            return
        }
        let before = mutation
        undoDepth += 1
        body()
        undoDepth -= 1
        registerUndo(from: before, name: name)
    }

    /// Registers the step — unless the board came out the way it went in, which
    /// is what keeps a no-op drop off the Edit menu.
    ///
    /// Nothing registers from inside an open step: moving the selection off a
    /// deleted task ends the sessions that surface left behind, and each of
    /// those would otherwise file its own ⌘Z for a fragment of one delete.
    ///
    /// `limit` is the session `before` was taken from, when it came from one:
    /// `before` is then only downstream of the sessions that opened earlier, and
    /// a session that opened *later* has a before-state ahead of it rather than
    /// behind it — see `flushSessions`.
    private func registerUndo(from before: BoardMutation, name: String, openedBefore limit: Int = .max) {
        guard undoDepth == 0, !isApplyingUndo else { return }
        let after = mutation
        guard before != after else { return }
        // `before` is the board as this step opened, so it already holds
        // whatever an open session has typed. That text files first, underneath.
        flushSessions(upTo: before, openedBefore: limit)
        rebaseSessions(to: after)
        registerStep(from: before, to: after, name: name)
    }

    /// Files one step. `before` is what a ⌘Z restores; the redo is not stored,
    /// because `applyUndo` reads the board it is about to leave.
    @discardableResult
    private func registerStep(from before: BoardMutation, to after: BoardMutation, name: String) -> Bool {
        guard before != after, let undoManager else { return false }
        undoManager.registerUndo(withTarget: self) { store in
            // The undo manager only ever fires on the main run loop; the
            // handler simply is not typed that way.
            MainActor.assumeIsolated { store.applyUndo(to: before, name: name) }
        }
        undoManager.setActionName(name)
        return true
    }

    /// Files what open sessions have typed since the last step boundary as a
    /// step of its own, then leaves the re-base to the caller.
    ///
    /// **The invariant, written down because this interaction has now bitten
    /// twice: every keystroke belongs to exactly one step.** A session owns the
    /// text typed since the last boundary and nothing else, so at each boundary
    /// that text is filed *before* the step that interrupted it — putting the
    /// session's own step below the interruption, one ⌘Z for the interruption
    /// and the next for the typing. Re-basing without filing moves the boundary
    /// forward over text that then belongs to no step at all: the step above it
    /// was snapshotted before the text existed and the session's own step now
    /// starts after it, so no number of ⌘Z can reach it.
    ///
    /// Two sessions can be open on different before-states — a second field
    /// takes focus while the first still has unfiled text — and only the oldest
    /// covers the whole unfiled delta. Filing the younger one would orphan the
    /// older prefix all over again, so this files one step, from the oldest.
    ///
    /// `limit` is what keeps that step pointing backwards. A picker session
    /// opens without ending the text session it interrupted (the due popover and
    /// the priority menu both do), so its before-state is *newer* than the text
    /// session's; ending the text field then registers from the older state, and
    /// a flush that reached for the picker's would file a step restoring a board
    /// downstream of the one being registered — a redo sitting on the undo
    /// stack, where a second ⌘Z replays the typing the first had just taken back.
    /// Only sessions that opened before `limit` have a prefix to file here.
    private func flushSessions(upTo state: BoardMutation, openedBefore limit: Int) {
        guard let oldest = editSessions
            .filter({ $0.value.undoBefore != state && $0.value.openedAt < limit })
            .min(by: { $0.value.openedAt < $1.value.openedAt })
        else { return }
        guard registerStep(from: oldest.value.undoBefore, to: state,
                           name: undoName(for: oldest.key.field)) else { return }
        // The typing and the step that interrupted it happen in one event, so
        // without this they share that event's group and one ⌘Z takes back
        // both — reverting text the user typed before they clicked something
        // else. Closing here is what puts the typing *below* the interruption;
        // re-opening leaves the nesting level as the run loop (or a test's
        // explicit group) left it, for whoever closes it.
        if let undoManager, undoManager.groupingLevel == 1 {
            undoManager.endUndoGrouping()
            undoManager.beginUndoGrouping()
        }
    }

    /// Moves every open session's before-state up to the board as it stands at a
    /// step boundary — a registration, or a restore.
    ///
    /// A session's before-state is what its own ⌘Z restores. Left at the board
    /// the session opened on, it reaches back past everything registered since:
    /// tick a sub-task while a description field still has focus (nothing on
    /// either detail surface takes focus away from it) and the one step the
    /// session eventually files reverses the tick as well — and can put back a
    /// tick the user had already undone. Re-based, the session only ever owns
    /// the keystrokes typed since the last step, which is what ⌘Z means to the
    /// person pressing it. It is only ever called after `flushSessions`, which
    /// is what stops the move losing the keystrokes it steps over.
    private func rebaseSessions(to state: BoardMutation) {
        for key in Array(editSessions.keys) { editSessions[key]?.undoBefore = state }
    }

    /// Restores one side of a step and registers the other, which is what makes
    /// redo work: an undo performed inside an undo group becomes the redo.
    ///
    /// The other side is read from the board here rather than snapshotted when
    /// the step was registered, so a redo replays the board the user was
    /// actually looking at.
    ///
    /// The boundary this is also is the one `flushSessions` cannot serve: a
    /// registration made while the manager is undoing lands on the *redo* stack,
    /// in this same group, so in-flight text cannot be filed as a step here.
    /// It is carried across the restore instead — see `textInFlight`.
    private func applyUndo(to target: BoardMutation, name: String) {
        // Carried text is text no step covers, so it stays out of the snapshot
        // this restore files as well: the same keystrokes on both sides of a
        // step are keystrokes no ⌘Z can take back.
        let carried = textInFlight().filter { entry in
            value(entry.key.field, on: entry.key.task, subtask: entry.key.subtask, in: target)
                == .text(entry.floor)
        }
        let live = carried.reduce(mutation) { rolledBack(to: $1.floor, for: $1.key, in: $0) }
        isApplyingUndo = true
        apply(target)
        for entry in carried {
            write(entry.live, field: entry.key.field, on: entry.key.task, subtask: entry.key.subtask)
        }
        isApplyingUndo = false
        // To `target`, not to the board: the carried text is still the session's
        // to file, so the session has to go on owning it.
        rebaseSessions(to: target)
        undoManager?.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.applyUndo(to: live, name: name) }
        }
        undoManager?.setActionName(name)
        scheduleSave()
    }

    /// Text an open session has typed that no step covers yet: what the field
    /// says now, and what it said at the last boundary.
    ///
    /// Those keystrokes belong to the session, not to any step, which is why an
    /// undo aimed at an older step carries them across instead of taking them
    /// off the board — the step was snapshotted before they existed, so
    /// reversing them is not what that ⌘Z was for. `applyUndo` carries only the
    /// ones the restored board does not itself set: where it does set the field
    /// — undoing the session's own earlier step, say — that step's value is
    /// exactly what was asked for, and carrying would make the ⌘Z do nothing.
    private func textInFlight() -> [InFlightText] {
        editSessions.compactMap { key, session in
            guard case .text(let live) = value(key.field, on: key.task, subtask: key.subtask),
                  case .text(let floor) = value(key.field, on: key.task, subtask: key.subtask,
                                                in: session.undoBefore),
                  live != floor
            else { return nil }
            return InFlightText(key: key, live: live, floor: floor)
        }
    }

    /// A capture with one field wound back to what the last boundary left there,
    /// which is how in-flight keystrokes stay out of the undo history.
    private func rolledBack(to text: String, for key: EditKey, in state: BoardMutation) -> BoardMutation {
        var state = state
        guard let index = state.tasks.firstIndex(where: { $0.id == key.task }) else { return state }
        switch key.field {
        case .title: state.tasks[index].title = text
        case .note: state.tasks[index].note = text
        case .subtask:
            if let row = state.tasks[index].subtasks.firstIndex(where: { $0.id == key.subtask }) {
                state.tasks[index].subtasks[row].text = text
            }
        case .due, .priority: break
        }
        return state
    }

    /// Puts a captured board back. The capture holds no session state, so what
    /// is left of it here is only the tidying: anything naming a task that the
    /// restore has taken away has to stop naming it.
    private func apply(_ state: BoardMutation) {
        tasks = state.tasks
        labels = state.labels
        nextSerial = state.nextSerial
        boards = state.boards
        trash = state.trash
        views = state.views
        savedColors = state.savedColors
        // *After* the two above, deliberately: assigning a list runs its
        // `didSet`, which stamps `.now`, and this is the one path where that is
        // wrong — a restored board is dated when it was made, not when it was
        // put back.
        viewsChangedAt = state.viewsChangedAt
        paletteChangedAt = state.paletteChangedAt
        // See `announcement`: the message describes an act this is reversing,
        // so it goes with it. A sync's message is not reversed by anything, but
        // an undo landing on top of one is a good moment to take it down too.
        announcement = nil
        // The restore may have taken away the board being looked at — undoing
        // the creation of one, say — and a surface reading `activeBoard` must
        // never be shown nothing while there is still a board to show.
        if !boards.contains(where: { $0.id == activeBoardID }) { activeBoardID = boards.first?.id }
        // And it may have taken away the *view* being looked at — undoing the
        // creation of one — which leaves a surface naming nothing. The board is
        // the answer that is always available, and it is what deleting the view
        // you are standing on already does.
        if let id = activeView?.id, !views.contains(where: { $0.id == id }) { surface = .board }
        // The search memo is keyed on a per-task counter that a wholesale
        // replacement does not bump, so it is dropped rather than trusted.
        searchTexts.removeAll()
        let ids = Set(tasks.map(\.id))
        editSessions = editSessions.filter { ids.contains($0.key.task) }
        selection = selection.intersection(ids)
        if let anchor = selectionAnchor, !ids.contains(anchor) { selectionAnchor = selection.first }
        if let sheetID, !ids.contains(sheetID) { self.sheetID = nil }
        if let draggingID, !ids.contains(draggingID) { self.draggingID = nil }
        detachSurfacesFromMissingColumns()
    }

    /// What the Edit menu calls an undone field edit.
    private func undoName(for field: TaskField) -> String {
        switch field {
        case .title:
            String(localized: "Edit Title", comment: "Undo action name for editing a task's title")
        case .note:
            String(localized: "Edit Description", comment: "Undo action name for editing a task's description")
        case .due:
            String(localized: "Set Due Date", comment: "Undo action name for changing a task's due date")
        case .priority:
            String(localized: "Set Priority", comment: "Undo action name for changing a task's priority")
        case .subtask:
            String(localized: "Edit Sub-task", comment: "Undo action name for editing a sub-task's text")
        }
    }

    /// Folds a one-line field flat. Paste puts newlines and runs of spaces into
    /// a title even where the field itself is single-line, and a title with a
    /// newline in it then renders through a card layout that assumes one or two
    /// lines. Deliberately does not trim: a trailing space is how the user gets
    /// to the next word.
    private static func singleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // MARK: - Themes

    /// The theme showing under a given appearance. See ``ThemeSettings``.
    func theme(for appearance: ThemeAppearance) -> Theme { themes.theme(for: appearance) }

    /// Puts a theme in whichever of the two slots its own appearance names.
    ///
    /// **No undo step**, along with `selectBoard` and the theme methods below.
    /// How the app looks is a preference rather than board data — it is not in
    /// `BoardMutation` — and a ⌘Z aimed at a card the user had just moved should
    /// not repaint the whole window. The editor has Cancel, and deleting asks.
    func selectTheme(_ theme: Theme) {
        guard themes.id(for: theme.appearance) != theme.id else { return }
        themes.select(theme)
        scheduleSave()
    }

    /// Adds a theme the user built, or replaces the one it is a new version of.
    /// Refuses a preset — those are the reference points, and the editor makes a
    /// copy rather than offering to overwrite one.
    @discardableResult
    func saveTheme(_ theme: Theme) -> Bool {
        guard themes.save(theme) else { return false }
        scheduleSave()
        return true
    }

    /// Throws a custom theme away. Any slot wearing it falls back to the preset
    /// for that slot — see ``ThemeSettings/theme(for:)`` — so the app is never
    /// left pointing at nothing.
    @discardableResult
    func deleteTheme(_ id: Theme.ID) -> Bool {
        guard themes.delete(id) else { return false }
        scheduleSave()
        return true
    }

    /// Brings in a theme from a file, under a name that is not already taken and
    /// an identity of its own.
    ///
    /// **A fresh id rather than the one in the file.** Two people who both
    /// started from Ember and edited it would otherwise be carrying the same id
    /// on two different themes, and importing one would silently overwrite the
    /// other. An import is a new theme here even when it began as a copy of one
    /// this machine already has.
    @discardableResult
    func importTheme(_ theme: Theme) -> Theme {
        var arriving = theme.duplicated(named: themes.unusedName(basedOn: theme.name))
        arriving.appearance = theme.appearance
        saveTheme(arriving)
        return arriving
    }

    #if DEBUG
    /// Opens a surface straight from a launch argument, so the sheet, drawer and
    /// individual tabs can be driven from `simctl launch` or a UI test without
    /// scripting taps. The sheet takes either a task's `code` or its UUID:
    ///
    ///     xcrun simctl launch <device> com.n14395.LittleKanban -LittleKanbanOpenSheet NW-118
    ///     xcrun simctl launch <device> com.n14395.LittleKanban -LittleKanbanOpenDrawer YES
    ///     xcrun simctl launch <device> com.n14395.LittleKanban -LittleKanbanOpenSettings YES
    ///     xcrun simctl launch <device> com.n14395.LittleKanban -LittleKanbanOpenTrash YES
    ///     xcrun simctl launch <device> com.n14395.LittleKanban -LittleKanbanOpenBoardSettings YES
    ///     xcrun simctl launch <device> com.n14395.LittleKanban -LittleKanbanTab search
    ///     xcrun simctl launch <device> com.n14395.LittleKanban -LittleKanbanOpenLink littlekanban://new
    private func applyLaunchOverrides() {
        let defaults = UserDefaults.standard
        if let identifier = defaults.string(forKey: "LittleKanbanOpenSheet"),
           let task = task(matching: identifier) {
            sheetID = task.id
        }
        if defaults.bool(forKey: "LittleKanbanOpenDrawer") {
            isNavDrawerOpen = true
        }
        if defaults.bool(forKey: "LittleKanbanOpenSettings") {
            isShowingSettings = true
        }
        if defaults.bool(forKey: "LittleKanbanOpenTrash") {
            isShowingTrash = true
        }
        // The board's own settings, on whichever board the launch settles on.
        // The one surface here that is a *sheet on macOS too*, and so the one a
        // desk screenshot needs a way in to that is not a right-click.
        if defaults.bool(forKey: "LittleKanbanOpenBoardSettings"), let board = activeBoardID {
            boardSettings = BoardSettingsRequest(board: board)
        }
        // A `littlekanban://` link, queued exactly as an arriving one is — the
        // scene resolves it when it appears, which is the same path a cold
        // launch from a widget takes and therefore the same order of state
        // changes. The alternative, `simctl openurl`, stops to ask "Open in
        // Little Kanban?" and needs a tap of its own, which is precisely the
        // thing these arguments exist to avoid.
        if let raw = defaults.string(forKey: "LittleKanbanOpenLink"), let url = URL(string: raw) {
            TaskLink.router.open(url)
        }
        if let raw = defaults.string(forKey: "LittleKanbanTab"), let parsed = PhoneTab(rawValue: raw) {
            // `selectTab` rather than the field, because a tab names a *surface*
            // as well: asking for the Board tab and arriving on Today — which is
            // where a launch lands now — is not what the argument says. It is
            // also how the bar itself sets the tab, so the harness and the thumb
            // take the same route.
            selectTab(parsed)
        }
    }

    /// Resolves a task from a UUID string or its human code ("NW-118"), which
    /// is the half of the pair anyone typing a launch argument will reach for.
    private func task(matching identifier: String) -> TaskItem? {
        let needle = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uuid = UUID(uuidString: needle), let task = self[uuid] { return task }
        return tasks.first { $0.code.compare(needle, options: .caseInsensitive) == .orderedSame }
    }
    #endif


    // MARK: - Lookup

    subscript(id: TaskItem.ID?) -> TaskItem? {
        guard let id, let index = position(of: id) else { return nil }
        return tasks[index]
    }

    var selectedTask: TaskItem? { self[selectedID] }
    var sheetTask: TaskItem? { self[sheetID] }

    /// Where a task sits in `tasks`, in constant time.
    ///
    /// Every card body resolves itself by id, so the scan this replaces was the
    /// board's largest cost at five hundred cards: 43ms to resolve them all
    /// against 53µs through a map, and quadratic in the card count.
    ///
    /// The map is a memo and the two checks are what make it safe to be one. A
    /// recorded position is believed only while it still holds the task it was
    /// recorded against, so a mutation that reordered the array without saying
    /// so costs a rebuild rather than handing back the wrong card. An id the map
    /// does not have at all is believed absent only while the map was built at
    /// the current revision and card count — otherwise it may well be on the
    /// board, and a rebuild is the only way to find out.
    ///
    /// Nothing else has to be kept in step, which is the point: `tasks` is
    /// written from twenty places and a map maintained at each of them would be
    /// wrong the first time somebody added a twenty-first. The one thing it does
    /// assume is `scheduleSave()` — a card that arrived without the revision
    /// moving *and* without the count changing would read as absent. That is C6,
    /// and it is a weaker assumption than the one `visibleTasksByColumn` already
    /// makes about the same counter.
    ///
    /// `tasks` is read on every path, cached or not, so a view that only ever
    /// hits the memo still registers its dependency on the board.
    func position(of id: TaskItem.ID) -> Int? {
        if let cached = positions {
            if let offset = cached.byID[id] {
                if offset < tasks.count, tasks[offset].id == id { return offset }
            } else if cached.revision == boardRevision, cached.count == tasks.count {
                return nil
            }
        }
        var byID = [TaskItem.ID: Int](minimumCapacity: tasks.count)
        for (offset, task) in tasks.enumerated() { byID[task.id] = offset }
        positions = (boardRevision, tasks.count, byID)
        return byID[id]
    }

    @ObservationIgnored private var positions: (revision: Int, count: Int, byID: [TaskItem.ID: Int])?

    /// The vocabulary by key. Up to four keys a card against twenty-four
    /// definitions is a scan per chip per card per render, and the map takes
    /// 2.1ms off a five-hundred card pass.
    ///
    /// Dropped by `labels`' own `didSet` rather than verified the way
    /// `positions` is: a renamed definition is still findable at its key, so
    /// nothing about a stale entry gives it away. `tasks` cannot be given the
    /// same treatment — a property observer costs an array a copy on every
    /// in-place write, and the board writes into `tasks` in loops.
    func label(forKey key: String) -> LabelDef? {
        if let cached = labelsByKey, cached.count == labels.count { return cached.byKey[key] }
        let byKey = Dictionary(labels.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        labelsByKey = (labels.count, byKey)
        return byKey[key]
    }

    @ObservationIgnored private var labelsByKey: (count: Int, byKey: [String: LabelDef])?

    // MARK: - Selection

    /// The selected tasks in board order. Every bulk command acts in this order
    /// rather than in the set's, so cards moved together arrive in the order
    /// they were in.
    ///
    /// Memoised because it is not only the commands that ask: every selected
    /// card's ⌘C payload is built from it on every card re-render, so a
    /// multi-selection paid a filter of the whole board per card per pass.
    var selectedTasks: [TaskItem] {
        // Read unconditionally, so a memo hit still registers the caller's
        // dependency on the board — the `position(of:)` bargain.
        let tasks = self.tasks
        let selection = self.selection
        if let memo = selectedTasksMemo, memo.revision == boardRevision,
           memo.count == tasks.count, memo.selection == selection {
            return memo.members
        }
        let members = tasks.filter { selection.contains($0.id) }
        selectedTasksMemo = (boardRevision, tasks.count, selection, members)
        return members
    }

    @ObservationIgnored private var selectedTasksMemo:
        (revision: Int, count: Int, selection: Set<TaskItem.ID>, members: [TaskItem])?

    func isSelected(_ id: TaskItem.ID) -> Bool { selection.contains(id) }

    var selectionCount: Int { selection.count }
    var hasSelection: Bool { !selection.isEmpty }

    /// Picks one card and nothing else — a plain click, and what assigning to
    /// `selectedID` does.
    func select(_ id: TaskItem.ID?) {
        selectionAnchor = id
        selection = id.map { [$0] } ?? []
    }

    /// ⌘-click: adds a card to the selection or takes it out again. The card
    /// picked becomes the anchor, so a ⇧-click after it sweeps from there.
    func toggleSelection(of id: TaskItem.ID) {
        if selection.contains(id) {
            var remaining = selection
            remaining.remove(id)
            if selectionAnchor == id { selectionAnchor = remaining.first }
            selection = remaining
        } else {
            selectionAnchor = id
            selection.insert(id)
        }
    }

    /// ⇧-click: everything between the anchor and `id`.
    ///
    /// `order` is the ids the surface is drawing, in the order it is drawing
    /// them — the range a user means is the one they can see, which is neither
    /// the board's array order nor the set's. With no anchor to measure from,
    /// or one that has left the list, the click lands as a plain one.
    ///
    /// The anchor stays put, so a run of ⇧-clicks sweeps out from the one card
    /// rather than growing from wherever the last one landed.
    func extendSelection(to id: TaskItem.ID, through order: [TaskItem.ID]) {
        guard let anchor = selectionAnchor,
              let from = order.firstIndex(of: anchor),
              let to = order.firstIndex(of: id)
        else { return select(id) }
        selection = Set(order[min(from, to)...max(from, to)])
    }

    /// ⌘A. The surface passes what it is drawing, in its order, so the anchor a
    /// following ⇧-click measures from is the first row rather than an
    /// arbitrary member of a set.
    func selectAll(_ ids: [TaskItem.ID]) {
        selectionAnchor = ids.first
        selection = Set(ids)
    }

    /// ⌘A on the surface the user is looking at.
    func selectAllVisible(today: CalendarDay) {
        selectAll(visibleTaskIDs(today: today))
    }

    /// What is on screen, in the order it is drawn: the Inbox panel if it is
    /// out, then the board's columns left to right — or a saved view's own
    /// ordering. The query narrows all of them, because a card the search has
    /// hidden is not one ⌘A can have meant.
    ///
    /// The Inbox's cards count whenever it is out, because it is drawn *with*
    /// the board rather than instead of it — beside it on the desk and the iPad,
    /// over it on the phone — and a Select All that skipped what is on screen
    /// would be lying about what it selected. It used to skip them on the
    /// phone's Inbox tab, which was a tab standing in for the board; there is no
    /// such tab now.
    func visibleTaskIDs(today: CalendarDay) -> [TaskItem.ID] {
        switch surface {
        case .board:
            let onTheBoard = columns.flatMap { visibleTasks(in: $0.id).map(\.id) }
            return isInboxOpen ? inboxTasks.map(\.id) + onTheBoard : onTheBoard
        case .view(let id):
            // A surface naming a view that has since gone selects nothing, which
            // is what is on screen: `apply` puts the surface back to the board
            // on the next pass.
            guard let view = self.view(id: id) else { return [] }
            return tasks(in: view, today: today).map(\.id)
        }
    }

    func clearSelection() {
        selectionAnchor = nil
        selection = []
    }

    /// The cards a command aimed at one of them should act on: the whole
    /// selection when that card is part of it, and just that card when it is
    /// not. The rule every multi-select list follows, and the one that stops a
    /// right-click on a card outside the selection quietly acting on cards
    /// somewhere else.
    func commandTargets(_ id: TaskItem.ID) -> Set<TaskItem.ID> {
        selection.contains(id) ? selection : [id]
    }

    /// Takes a card out of the selection as it leaves the board, falling to its
    /// neighbour only once the selection has run out — deleting three of four
    /// selected cards leaves the fourth selected rather than jumping away.
    private func deselect(_ id: TaskItem.ID, fallingTo neighbour: TaskItem.ID?) {
        guard selection.contains(id) else {
            if selectionAnchor == id { selectionAnchor = nil }
            return
        }
        var remaining = selection
        remaining.remove(id)
        guard !remaining.isEmpty else { return select(neighbour) }
        if selectionAnchor == id { selectionAnchor = remaining.first }
        selection = remaining
    }

    // MARK: - Boards

    /// The board on screen. `nil` only when there are no boards at all, which
    /// is a state the user can reach by deleting the last one — the Inbox is
    /// still there, and so is the affordance to make another board.
    ///
    /// Through `board(id:)` rather than a scan of its own: it is read by the
    /// toolbar, the sidebar, `columns` and the phone header on every render,
    /// and an exception to the index memo is a trap for whoever audits it.
    var activeBoard: Board? { board(id: activeBoardID) }

    /// Through an index memo rather than a scan: this sits under `isDone`,
    /// which every saved-view filter asks once per task, so the scan here
    /// multiplied into every board-sized pass. The memo follows `position(of:)`:
    /// a cached index is believed only while it still holds the board it was
    /// recorded against, and `boards`' own `didSet` drops the map besides.
    func board(id: Board.ID?) -> Board? {
        guard let id else { return nil }
        // Read unconditionally, so a memo hit still registers the caller's
        // dependency on the board list — the `position(of:)` bargain.
        let boards = self.boards
        if let cached = boardIndices, let offset = cached[id] {
            if offset < boards.count, boards[offset].id == id { return boards[offset] }
        }
        var byID = [Board.ID: Int](minimumCapacity: boards.count)
        for (offset, board) in boards.enumerated() where byID[board.id] == nil {
            byID[board.id] = offset
        }
        boardIndices = byID
        return byID[id].map { boards[$0] }
    }

    @ObservationIgnored private var boardIndices: [Board.ID: Int]?

    func board(for task: TaskItem) -> Board? { board(id: task.boardID) }

    /// Which board a column belongs to. Column ids are unique across boards, so
    /// a move that names only a column still knows where it is going.
    ///
    /// Through the owner map rather than a scan: this is asked once per task
    /// inside every filter that asks `isDone` — the saved views, the reminders,
    /// `completedTasks` — and two or three times per card render, so a scan of
    /// every board's columns here multiplied into most of what those cost.
    func board(ofColumn id: BoardColumn.ID) -> Board? {
        board(id: columnOwnersMap()[id])
    }

    /// `[column: board]`, dropped by `boards`' own `didSet` — the same bargain
    /// `labelsByKey` makes, and safe for the same reason: nothing can change
    /// which board holds a column without writing `boards`. `boards` is read
    /// on both paths, so a caller that only ever hits the map still registers
    /// its dependency on the board list.
    private func columnOwnersMap() -> [BoardColumn.ID: Board.ID] {
        if let columnOwners { return columnOwners }
        var owners: [BoardColumn.ID: Board.ID] = [:]
        for board in boards {
            for column in board.columns where owners[column.id] == nil {
                owners[column.id] = board.id
            }
        }
        columnOwners = owners
        return owners
    }

    @ObservationIgnored private var columnOwners: [BoardColumn.ID: Board.ID]?

    // MARK: - Columns

    /// The active board's columns, in board order. The Inbox is not one of them
    /// on any board: it is global, and a card is in it by being on no board at
    /// all — see `TaskPlacement`.
    var columns: [BoardColumn] { activeBoard?.columns ?? [] }

    /// Resolves a column id against every board, not just the active one: a
    /// search result names its column whichever board it is on. `nil` for an id
    /// no column answers to, which is a real state — a deleted column outlives
    /// itself in the activity feed. Through the owner map, like `board(ofColumn:)`.
    func column(id: BoardColumn.ID?) -> BoardColumn? {
        guard let id else { return nil }
        return board(ofColumn: id)?.column(id: id)
    }

    func column(for task: TaskItem) -> BoardColumn? { column(id: task.columnID) }

    /// Where a card named by a column alone belongs: that column, on whichever
    /// board has it, or the Inbox when no board has it at all.
    func placement(forColumn id: BoardColumn.ID) -> TaskPlacement {
        guard let board = board(ofColumn: id) else { return .inbox }
        return .column(board: board.id, column: id)
    }

    /// The columns a card can be moved between: its own board's, in board order.
    ///
    /// **Its own board's, not the board on screen** — a card drawn in a saved
    /// view or a search result can belong to another one, and moving it into a
    /// column of the board somebody happens to be looking at would be filing it
    /// somewhere they never named.
    ///
    /// Empty for a card in the Inbox, which is on no board, and for an archived
    /// one, which has left the workflow — the Archive is not a column. The
    /// surfaces that offer these draw nothing at all in that case rather than a
    /// menu whose every row is inert; `ColumnDestinationItems`, `MoveActions`
    /// and the two card context menus all ask here so that one answer is drawn,
    /// offered and acted on.
    func moveDestinations(for task: TaskItem) -> [BoardColumn] {
        guard !task.isArchived else { return [] }
        return board(for: task)?.columns ?? []
    }

    /// Whether a placement names somewhere that exists: the Inbox, which always
    /// does, or a column that is actually on the board it claims.
    ///
    /// `TaskPlacement` makes "on a board, in no column" unspellable, but not
    /// "on board A, in board B's column" — the pair is two ids and a caller can
    /// hand over any two. Every entry point that takes a placement from outside
    /// asks this first, so the pairing is checked in one place rather than at
    /// whichever call site happened to remember.
    func isPlaceable(_ placement: TaskPlacement) -> Bool {
        guard case .column(let boardID, let columnID) = placement else { return true }
        return board(id: boardID)?.column(id: columnID) != nil
    }

    /// Whether a task is complete: in its board's last column, or completed in
    /// the global Inbox without being filed onto a board.
    ///
    /// The one funnel for the question, which is why removing `ColumnRole` cost
    /// its callers nothing — they all came through here. Inbox completion is its
    /// own persisted fact because the Inbox deliberately has no Done column.
    func isDone(_ task: TaskItem) -> Bool {
        if task.isInboxCompleted { return true }
        guard let columnID = task.columnID else { return false }
        return isDone(column: columnID)
    }

    /// Whether a column is the one its **own** board keeps for finished work.
    ///
    /// Asked of the board that holds the column rather than of the board on
    /// screen: a card opened out of a saved view can be on another board, and
    /// the answer has to be about the board it is actually on.
    func isDone(column id: BoardColumn.ID) -> Bool {
        doneColumnIDs().contains(id)
    }

    /// Every board's Done column, as one set — `isDone` is asked once per task
    /// inside every board-sized filter (the saved views, the counts, the
    /// reminders), and resolving the owning board per ask made each of those
    /// passes O(tasks × boards). Dropped by `boards`' own `didSet`, the
    /// `columnOwners` bargain: nothing can change which column is last on a
    /// board without writing `boards`.
    private func doneColumnIDs() -> Set<BoardColumn.ID> {
        // Read unconditionally, so a memo hit still registers the caller's
        // dependency on the board list — the `position(of:)` bargain.
        let boards = self.boards
        if let doneColumns { return doneColumns }
        let ids = Set(boards.compactMap { $0.doneColumn?.id })
        doneColumns = ids
        return ids
    }

    @ObservationIgnored private var doneColumns: Set<BoardColumn.ID>?

    /// Where `complete` sends a task, and what "Archive completed" clears.
    var doneColumnID: BoardColumn.ID? { doneColumnID(onBoard: activeBoardID) }

    /// The same, on a named board. A card is completed onto *its own* board's
    /// Done column, which is not always the one on screen.
    func doneColumnID(onBoard id: Board.ID?) -> BoardColumn.ID? {
        (board(id: id) ?? activeBoard)?.doneColumn?.id
    }

    /// Where a column's cards would go if it were trashed: **the first column
    /// left standing**. `deleteColumn` moves them there, and the warning in
    /// front of it names the same place by asking the same question.
    func refuge(ifTrashing id: BoardColumn.ID) -> BoardColumn? {
        guard let board = board(ofColumn: id) else { return nil }
        return board.columns.first { $0.id != id }
    }

    /// How many cards a column holds, **archived ones included**: a delete moves
    /// those too, and a warning that counted only what the board draws would
    /// promise to move four cards and move nine.
    func cardCount(inColumn id: BoardColumn.ID) -> Int {
        tasks.count { $0.columnID == id }
    }

    /// How many cards a board holds, **archived ones included** — the number the
    /// warning in front of Trash Board puts in front of the user, and the number
    /// that will actually go.
    ///
    /// Deliberately not ``taskCount(for:)``, which is the *sidebar's* count and
    /// leaves archived cards out because the board does not draw them. Trashing
    /// takes them all, so a warning built on that number would promise to bin
    /// four cards and bin nine — and the trash row would then offer nine back.
    func cardCount(onBoard id: Board.ID) -> Int {
        tasks.count { $0.boardID == id }
    }

    /// Tasks in the active board's Done column, unfiltered — what the archive
    /// affordances count and act on. Scoped to the board on screen: "archive
    /// completed" tidies the board the user is looking at, not every board.
    var completedTasks: [TaskItem] {
        tasks.filter { $0.boardID == activeBoardID && isDone($0) && !$0.isArchived }
    }

    /// Completed Inbox cards, unfiltered. Unlike `completedTasks`, this has no
    /// active-board scope because the Inbox itself is global.
    var inboxCompletedTasks: [TaskItem] {
        tasks.filter { $0.isInboxCompleted && !$0.isArchived }
    }

    /// `completedTasks.count` without building the list. The menus offering
    /// "Archive Completed" ask on every render — `Menu`'s content builder runs
    /// with the body it sits in, not when the menu opens.
    var completedCount: Int {
        guard let activeBoardID else { return 0 }
        return counts().completedPerBoard[activeBoardID] ?? 0
    }

    var inboxCompletedCount: Int { counts().inboxCompleted }

    /// The label definitions for a task, skipping any key without a definition.
    func labels(for task: TaskItem) -> [LabelDef] {
        task.labelKeys.compactMap { label(forKey: $0) }
    }

    // MARK: - Searching

    /// Everything the query answers to, best first, from every board and the
    /// Inbox — the one list all three platforms search. See ``TaskSearch``,
    /// which is where "best" is decided.
    ///
    /// **It is a search, not a filter.** This used to be `visibleTasks`, and
    /// the board was drawn from it: typing narrowed the columns in place, so
    /// the query's answer was "the board, with most of it missing" and finding
    /// a card on *another* board meant knowing which board to open first. The
    /// board is drawn from `visibleTasks(in:)` now, which no query touches, and
    /// this list is what the results panel and the phone's Search tab show.
    ///
    /// An empty query is every task rather than none: the panel opens on the
    /// whole of what there is and narrows as the user types, which is also why
    /// this is in board order until there is something to rank it by.
    ///
    /// An archived task is in none of it. It has left the board, so it is not
    /// something the search failed to find — it is somewhere else, and the
    /// Archive view is where it is looked for.
    var searchResults: [TaskItem] {
        // Read unconditionally, so a memo hit still registers the caller's
        // dependency on the board — the `position(of:)` bargain. Memoised
        // because the panel asks on every toolbar render and the phone's
        // Search tab is one of the surfaces that draws per frame while the
        // drawer is dragged open; the fold per task was already cached, but
        // the score and the sort were paid on every ask.
        let tasks = self.tasks
        let query = self.query
        if let memo = searchMemo, memo.revision == boardRevision,
           memo.count == tasks.count, memo.query == query {
            return memo.results
        }
        let results = searchResults(of: tasks)
        searchMemo = (boardRevision, tasks.count, query, results)
        return results
    }

    @ObservationIgnored private var searchMemo:
        (revision: Int, count: Int, query: String, results: [TaskItem])?

    private func searchResults(of tasks: [TaskItem]) -> [TaskItem] {
        let tokens = searchTokens
        guard !tokens.isEmpty else { return tasks.filter { !$0.isArchived } }
        let hits = tasks.compactMap { task -> (task: TaskItem, score: Int)? in
            guard !task.isArchived,
                  let score = TaskSearch.score(searchText(for: task), matching: tokens)
            else { return nil }
            return (task, score)
        }
        // Score first, then the card touched most recently — two cards that
        // answer equally well are ordered by which one the user was last
        // working on, which is the only tiebreak they can predict. Decorated
        // with the board index so the sort is stable under the third tie.
        return hits.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.score != rhs.element.score { return lhs.element.score > rhs.element.score }
                if lhs.element.task.updatedAt != rhs.element.task.updatedAt {
                    return lhs.element.task.updatedAt > rhs.element.task.updatedAt
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element.task)
    }

    /// Narrows a list the caller has already built — the phone's saved views,
    /// which are the one surface left that a query acts on in place.
    ///
    /// The rule is `mobileAppliesQuery`'s and the reason is the phone's: its
    /// field is on the Search tab, a saved view opened while a query is live
    /// says so through `showsMobileFilterNotice`, and both of those predate the
    /// results panel. Nothing on the desk or the iPad calls this.
    func narrowed(_ tasks: [TaskItem]) -> [TaskItem] {
        let tokens = searchTokens
        guard !tokens.isEmpty else { return tasks }
        return tasks.filter { task in
            TaskSearch.score(searchText(for: task), matching: tokens) != nil
        }
    }

    /// The board's answer to a piece of text, **without touching the session's
    /// own query** — what Shortcuts asks through `FindTasksIntent`.
    ///
    /// ``narrowed(_:)`` cannot do this: it reads `query`, which is the field
    /// the user is typing in, and an intent that ran while somebody was
    /// searching would answer their question instead of its own — or, if it set
    /// `query` first, would rewrite the search field of an app it was never
    /// meant to disturb. The scoring is the same `TaskSearch` the panel uses, so
    /// the two cannot drift into two ideas of what a match is.
    ///
    /// Archived cards are left out, as they are everywhere the board is asked
    /// what it holds.
    func tasks(matching text: String) -> [TaskItem] {
        let tokens = TaskSearch.tokens(in: text)
        guard !tokens.isEmpty else { return tasks.filter { !$0.isArchived } }
        return tasks.filter { task in
            !task.isArchived && TaskSearch.score(searchText(for: task), matching: tokens) != nil
        }
    }

    /// The global Inbox: everything on no board, in board order.
    ///
    /// Memoised because it is not only the panel that asks: `groundCaret`
    /// resolves a drop aimed at the Inbox's own ground through here, per card,
    /// per pointer move — a filter and a sort each time made a drag over the
    /// Inbox quadratic in the board.
    var inboxTasks: [TaskItem] {
        // Read unconditionally, so a memo hit still registers the caller's
        // dependency on the board — the `position(of:)` bargain.
        let tasks = self.tasks
        let order = sortOrder
        if let memo = inboxMemo, memo.revision == boardRevision,
           memo.count == tasks.count, memo.order == order {
            return memo.members
        }
        let ordered = sorted(tasks.filter { !$0.isArchived && $0.isUnfiled })
        // Completion does not move an Inbox task, but completed cards always
        // settle after open work whatever ordering preference is selected.
        let members = ordered.filter { !$0.isInboxCompleted } + ordered.filter(\.isInboxCompleted)
        inboxMemo = (boardRevision, tasks.count, order, members)
        return members
    }

    @ObservationIgnored private var inboxMemo:
        (revision: Int, count: Int, order: BoardSortOrder, members: [TaskItem])?

    /// Drops the search query. Session state, so it registers no undo step and
    /// needs no save — both clear buttons and the filtered indicator call it.
    func clearQuery() {
        query = ""
    }

    /// Bumped by ⌘F; the search field watches it and takes focus. The field
    /// lives inside the toolbar and the menu cannot reach its `FocusState`, so
    /// the request travels as board state instead.
    ///
    /// A counter rather than a flag: with the field already focused a flag is
    /// already true, so a second ⌘F would be no change at all and the toolbar
    /// would never hear about it.
    private(set) var searchFocusToken: Int = 0

    func focusSearch() {
        searchFocusToken &+= 1
    }

    /// Whether there is a query to answer. The results panel opens on the
    /// whole board without one, so this is not "something is hidden" any more —
    /// it is "the user has typed".
    var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether a card may be dragged, which is the question of whether the
    /// order on screen is the board's own order.
    ///
    /// A drop resolves against the `tasks` array — "put this card before that
    /// one" is an index in it — so it only means what it looks like where the
    /// cards on screen are that array. A saved view breaks that: it draws no
    /// columns at all, and Recently updated and the Archive impose an ordering
    /// of their own, so a drop there would move a card to a column the user
    /// cannot see, at a position bearing no relation to the row it was aimed at.
    ///
    /// **A live query no longer breaks it.** It used to, and had to: the board
    /// was drawn from the query's answer, so typing hid the cards in between and
    /// a drop landed at an index nobody could see. The board is not drawn from
    /// the query any more — see ``searchResults`` — so a card stays draggable
    /// while the results panel is open above it.
    var allowsCardDrag: Bool { activeView == nil && sortOrder == .manual }

    /// The same question for the Inbox's own list, which answers it differently
    /// — and the difference is `activeView`.
    ///
    /// A saved view is a reason not to drag *the board*, because the board is
    /// not what is on screen. It is not a reason not to drag the Inbox: the
    /// Inbox is drawn from ``inboxTasks`` whatever else is open, its order is
    /// the board's own `tasks` order, and a drop in it resolves against that
    /// array exactly as it does with no view open. The panel does not change
    /// when a view is opened beside it, so neither should what can be done in
    /// it — and on the phone, where the Inbox comes up over whichever surface
    /// you were on, the old answer meant the Inbox stopped being re-orderable
    /// depending on the screen behind it.
    ///
    /// `sortOrder` still counts, and for the reason it counts on the board: a
    /// list showing cards by date is not showing them in the order a drop would
    /// rearrange, so there is nothing a drop could mean.
    var allowsInboxCardDrag: Bool { sortOrder == .manual }

    /// The rule for the list a drop would **land in**, which is the form the
    /// marks need: a caret and a stand-in are drawn by the destination, so the
    /// question they have to ask is the destination's.
    ///
    /// The two views that draw a card ask this through the environment instead
    /// — see `\.isInboxList` — because a card knows which list it is *in*, not
    /// which list a drop is heading for. Same rule, asked from the two ends.
    func allowsCardDrag(into placement: TaskPlacement) -> Bool {
        placement.isInbox ? allowsInboxCardDrag : allowsCardDrag
    }

    /// The board's own cards, grouped by column.
    ///
    /// Every column asks for its own slice, so without this the board grouped
    /// itself once per column. The cache is keyed on the board's revision;
    /// `tasks` is read on the cached path too, because a view that only ever hit
    /// the cache would otherwise never register a dependency on the board and
    /// would stop re-rendering.
    var visibleTasksByColumn: [BoardColumn.ID: [TaskItem]] {
        let key = GroupingKey(count: tasks.count, revision: boardRevision, order: sortOrder)
        if let cached = groupedCache, cached.key == key { return cached.groups }
        // Unfiled cards are in no column, and the Inbox draws from `inboxTasks`
        // rather than from a `nil` key here: a column id is what this is keyed
        // on, and the Inbox does not have one.
        let filed = tasks.compactMap { task in
            task.isArchived ? nil : task.columnID.map { (column: $0, task: task) }
        }
        let groups = Dictionary(grouping: filed, by: \.column).mapValues { sorted($0.map(\.task)) }
        groupedCache = (key, groups)
        return groups
    }

    /// A column's cards, which no query touches — see ``searchResults`` for why
    /// that is now the only sentence there is to write about the board and the
    /// search field together.
    func visibleTasks(in columnID: BoardColumn.ID) -> [TaskItem] {
        visibleTasksByColumn[columnID] ?? []
    }

    private struct GroupingKey: Hashable {
        var count: Int
        var revision: Int
        var order: BoardSortOrder
    }

    /// Puts a column's — or the Inbox's — cards in the order the preference
    /// asks for. The board's own order is returned untouched, so `.manual`
    /// costs nothing and is the only path any existing surface ever took.
    ///
    /// Ties break on the board's order rather than on whatever `sorted(by:)`
    /// happens to do, which is unspecified: two cards with no due date must not
    /// swap places between one render and the next.
    private func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        guard sortOrder != .manual else { return tasks }
        return tasks.enumerated()
            .sorted { left, right in
                let mine = rank(left.element), theirs = rank(right.element)
                return mine == theirs ? left.offset < right.offset : mine < theirs
            }
            .map(\.element)
    }

    /// A card's place under the current ordering, as one number so all four
    /// orderings share a single sort. Ascending in every case: the orderings
    /// that read "most first" negate rather than reverse the comparison, which
    /// would reverse the tie-break with it.
    private func rank(_ task: TaskItem) -> Double {
        switch sortOrder {
        case .manual:
            0
        case .dueDate:
            // No due date sorts last: an undated card is not overdue, and a
            // column of them above the dated ones would bury the work.
            task.due.map { Double($0.year * 10_000 + $0.month * 100 + $0.day) }
                ?? .greatestFiniteMagnitude
        case .priority:
            Double(Priority.allCases.firstIndex(of: task.priority) ?? 0)
        case .recentlyUpdated:
            -task.updatedAt.timeIntervalSinceReferenceDate
        }
    }

    @ObservationIgnored private var groupedCache: (key: GroupingKey, groups: [BoardColumn.ID: [TaskItem]])?

    /// The query, folded the same way the haystacks are and split into tokens.
    private var searchTokens: [String] { TaskSearch.tokens(in: query) }

    /// Folding a task's text is the expensive part of a search, and a keystroke
    /// re-runs the whole of it, so the folded text is kept per task.
    ///
    /// The stamp is `markChanged`'s counter rather than `updatedAt`: `Date.now`
    /// is coarser than the gap between two consecutive mutations, so two edits
    /// can land on the same instant and a memo keyed on it would go on serving
    /// the first one's text. `updatedAt` stays what it is for — the field the
    /// detail surfaces show, saved views sort on, and the results panel breaks
    /// ties with.
    @ObservationIgnored private var searchTexts: [TaskItem.ID: (stamp: Int, text: TaskSearchText)] = [:]

    private func searchText(for task: TaskItem) -> TaskSearchText {
        let stamp = taskRevisions[task.id] ?? 0
        if let cached = searchTexts[task.id], cached.stamp == stamp { return cached.text }
        let folded = TaskSearchText(task: task)
        searchTexts[task.id] = (stamp, folded)
        return folded
    }

    // MARK: - Counts

    var totalCount: Int { counts().total }

    /// What the Inbox row shows: cards on no board.
    var inboxCount: Int { counts().inbox }

    /// What a board row shows: that board's cards, archived ones excluded, the
    /// same way `totalCount` excludes them.
    func taskCount(for boardID: Board.ID) -> Int {
        counts().perBoard[boardID] ?? 0
    }

    /// Every count the chrome shows, from one pass over the board.
    ///
    /// The sidebar asks for a count per board row, the toolbar for the Inbox's,
    /// the status bar for the total, and the menus for the active board's
    /// completed — each on every render, and the phone's drawer renders per
    /// frame while it is dragged open. Un-memoised, that was a full scan of
    /// `tasks` per row per render; here it is one scan per board revision,
    /// keyed the way `visibleTasksByColumn` is.
    private func counts() -> CountsMemo {
        // Both read unconditionally, so a memo hit still registers the
        // caller's dependency on the board — the `position(of:)` bargain.
        // `doneColumnIDs()` is what reads `boards`.
        let tasks = self.tasks
        let done = doneColumnIDs()
        if let memo = countsMemo, memo.revision == boardRevision, memo.count == tasks.count {
            return memo
        }
        var total = 0, inbox = 0, inboxCompleted = 0
        var perBoard: [Board.ID: Int] = [:]
        var completedPerBoard: [Board.ID: Int] = [:]
        for task in tasks where !task.isArchived {
            total += 1
            if task.isUnfiled {
                inbox += 1
                if task.isInboxCompleted { inboxCompleted += 1 }
            }
            guard let boardID = task.boardID else { continue }
            perBoard[boardID, default: 0] += 1
            if let columnID = task.columnID, done.contains(columnID) {
                completedPerBoard[boardID, default: 0] += 1
            }
        }
        let memo = CountsMemo(revision: boardRevision, count: tasks.count, total: total,
                               inbox: inbox, inboxCompleted: inboxCompleted,
                               perBoard: perBoard, completedPerBoard: completedPerBoard)
        countsMemo = memo
        return memo
    }

    private struct CountsMemo {
        var revision: Int
        var count: Int
        var total: Int
        var inbox: Int
        var inboxCompleted: Int
        var perBoard: [Board.ID: Int]
        var completedPerBoard: [Board.ID: Int]
    }

    @ObservationIgnored private var countsMemo: CountsMemo?

    /// How many tasks reached Done inside the seven days ending today — the
    /// number above the "This week" meter.
    ///
    /// It was `doneCount`, the whole Done column over all time, which only ever
    /// climbed and stopped meaning anything after the first fortnight.
    /// `updatedAt` is the evidence available: a card sitting in Done that has
    /// not been touched in a week was shipped some other week.
    ///
    /// Archived tasks are counted here, and this is the one place the archive is
    /// not subtracted. Archiving is filing, not un-shipping, and its affordance
    /// sits on the Done column header — a meter that fell to zero the moment the
    /// user tidied up would punish the action standing next to it. Filing does
    /// not move `updatedAt` either, so the reverse cannot happen: a card filed
    /// today that shipped last month stays outside the window. The button beside
    /// the meter moves it in neither direction.
    func weeklyShippedCount(today: CalendarDay) -> Int {
        tasks.count { isDone($0) && Self.isWithinWeek($0, of: today, week: weekMeaning) }
    }

    /// Shipped over touched, across that same week: how much of what the user
    /// worked on has landed. Both halves move, so the meter reads as progress
    /// rather than creeping toward full as the board grows.
    func weeklyProgressFraction(today: CalendarDay) -> Double {
        let touched = tasks.count { Self.isWithinWeek($0, of: today, week: weekMeaning) }
        guard touched > 0 else { return 0 }
        return Double(weeklyShippedCount(today: today)) / Double(touched)
    }

    /// What a week means here — see ``WeekMeaning``. On the store rather than
    /// read globally, for `trashRetention`'s reason.
    var weekMeaning: WeekMeaning = Preferences.weekMeaning

    /// The week ending today — rolling seven days, or everything since the week
    /// began, depending on ``WeekMeaning``. `updatedAt` is resolved to a
    /// calendar day first, so the window turns over at midnight rather than at
    /// whatever time of day the app was last launched.
    private static func isWithinWeek(
        _ task: TaskItem, of today: CalendarDay, week: WeekMeaning = .fallback
    ) -> Bool {
        week.containsBehind(CalendarDay(task.updatedAt), from: today)
    }

    // MARK: - Saved views

    /// Where the user is looking. Session state — see `BoardSurface` — and
    /// written down as it changes, so ``Preferences/resumesLastPlace`` has
    /// something to read at the next launch. The key is written whatever the
    /// setting says: turning it on should resume where you were, not where you
    /// were the first time you turned it on.
    var surface: BoardSurface = .board {
        didSet {
            guard surface != oldValue else { return }
            lastSurfaceName = activeView?.id.uuidString ?? Self.boardSurfaceName
            Preferences.remember(surface: lastSurfaceName)
            // Coming back to the board is arriving at the board — see
            // ``raiseInboxWithTheBoard()``. Here rather than in
            // `selectSurface(_:)` because the sidebar, the View menu, the tab
            // bar and `activeView`'s setter all reach the board through this
            // one property, and a rule about landing on the board belongs where
            // the landing is.
            raiseInboxWithTheBoard()
        }
    }

    /// What was written down for the next launch — the saved view standing in
    /// front of the board, or ``boardSurfaceName`` for the board itself.
    /// Published so a test can read the decision without reading `UserDefaults`,
    /// which every other suite is reading at the same time.
    ///
    /// **The board is written down too**, where it used to clear the key. That
    /// was sound while a launch always landed on the board: nothing stored and
    /// the board were the same answer. iOS lands on **Today** now, so they are
    /// two different answers — "resume, and I was on the board" has to be
    /// distinguishable from "nothing to resume", or somebody who asked to be put
    /// back where they were is put on Today instead.
    private(set) var lastSurfaceName: String?

    /// What the board itself is called in `lastSurfaceKey`. Not a `SavedView`
    /// raw value — those are `inbox`, `today`, `upcoming`, `highPriority`,
    /// `dueThisWeek`, `recentlyUpdated` and `archive` — so it cannot be read
    /// back as one.
    static let boardSurfaceName = "board"

    /// Where a launch lands when nothing else has anything to say.
    ///
    /// **The desk opens on the board** and always has: it draws the source list,
    /// the board and the inspector at once, so the board is not a *destination*
    /// there, it is the window.
    ///
    /// **The phone opens on Today.** It shows one place at a time, and the app is
    /// opened to answer one question — what is there to do now — which is the
    /// question Today is. Landing on a board instead answers "which column am I
    /// scrolled to", which is a question about the app rather than about the
    /// work; the board is one tap away on the bar underneath.
    ///
    /// **The iPad is not the phone here**, which is why this asks the idiom
    /// rather than `#if os(iOS)`. Its Inbox is a panel that stands *beside* the
    /// board and its sidebar, board and inspector are all on screen at once —
    /// the same window the desk has — so a saved view standing in front of the
    /// board would be hiding something rather than answering with it.
    /// `RootSurface` needs the size class as well to pick a *layout*; this is
    /// only choosing where to land, and an iPad in Slide Over is still an iPad.
    /// Resolves what was written down last time.
    ///
    /// **Two spellings, because v9 wrote the other one.** Until the views became
    /// data this key held an enum's raw value — `"today"` — and it now holds a
    /// uuid. A file being read for the first time after the migration still has
    /// the old spelling in `UserDefaults`, which is not migrated with the board,
    /// so a preset name resolves through ``SavedView/id(of:)``. Anything else,
    /// including a view since deleted, is the board.
    static func surface(named raw: String, among views: [SavedView]) -> BoardSurface {
        if let id = UUID(uuidString: raw), views.contains(where: { $0.id == id }) {
            return .view(id)
        }
        if let preset = SavedView.Preset(rawValue: raw) {
            let id = SavedView.id(of: preset)
            if views.contains(where: { $0.id == id }) { return .view(id) }
        }
        return .board
    }

    static var landingSurface: BoardSurface {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? .view(SavedView.id(of: .today)) : .board
        #else
        .board
        #endif
    }

    /// Whether "Open the Inbox with the board" is a promise this device can
    /// keep — and so whether Settings offers the switch at all.
    ///
    /// **The desk and the iPad, not the phone.** On both of those the Inbox is a
    /// panel that stands *beside* the board: opening it with the board adds a
    /// column to a window that still shows everything it showed before. The
    /// phone draws the same Inbox as a sheet over the board, so the setting
    /// would read "cover the board at launch", which is not the thing it says
    /// and not a thing anyone would ask for.
    ///
    /// The idiom rather than the size class, for ``landingSurface``'s reason: an
    /// iPad in Slide Over is still an iPad, and the setting is about what the
    /// Inbox *is* on this device rather than how wide this window happens to be.
    static var inboxOpensBesideTheBoard: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
        #else
        true
        #endif
    }

    /// The iPad, and only the iPad.
    ///
    /// ``inboxOpensBesideTheBoard`` cannot answer this: it is true on the desk
    /// as well, because the question it asks is what the Inbox *is* rather than
    /// which machine is drawing it. The one rule that genuinely belongs to the
    /// iPad alone is ``commitDraft()``'s, and it says there why.
    static var isPad: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
        #else
        false
        #endif
    }

    /// Which saved view has replaced the board, or `nil` for the board itself.
    ///
    /// A face on `surface` rather than a field of its own, so the two cannot
    /// disagree about what is on screen. Clearing it returns to the board, which
    /// is what every "close this view" affordance means; the Inbox is left
    /// through `selectSurface(_:)` or the tab bar instead.
    var activeView: SavedView? {
        get {
            guard case .view(let id) = surface else { return nil }
            return views.first { $0.id == id }
        }
        set { surface = newValue.map { BoardSurface.view($0.id) } ?? .board }
    }

    /// The view with this id, or `nil` once it has been deleted.
    func view(id: SavedView.ID) -> SavedView? { views.first { $0.id == id } }

    /// Picks what the main surface shows. On macOS this is the sidebar's
    /// destination; on iOS the tab bar drives it through `selectTab`.
    func selectSurface(_ surface: BoardSurface) {
        self.surface = surface
    }

    /// Whether the Inbox is reachable at all from where the user is standing.
    ///
    /// The panel stands beside the *board*, so on a saved view there is nothing
    /// for a toggle to open — which is why the toolbar's Inbox button is not
    /// there to be clicked on Today. One predicate for the button and the panel
    /// both, so the button cannot outlive what it opens.
    var showsInboxToggle: Bool { surface == .board }

    /// Whether the Inbox panel is on screen, which is not the same as whether
    /// it is switched on: a saved view has taken the board's place. It is
    /// hidden rather than switched off, so coming back to the board brings it
    /// back with no second click — closing it was never what picking Today
    /// meant.
    ///
    /// **The panel's question, and so not the phone's.** A panel stands beside
    /// the board and has nothing to stand beside on a saved view; the phone's
    /// slide-over is drawn *over* whatever is there and is reachable from all of
    /// it, so `PhoneInboxSheet` reads `isInboxOpen` directly.
    var isInboxShowing: Bool { isInboxOpen && showsInboxToggle }

    /// The sidebar row and the View menu, which are the same switch twice.
    func toggleInbox() { isInboxOpen.toggle() }

    /// Puts the Inbox back beside the board, if the setting asks for it and
    /// there is anything in it to stand there.
    ///
    /// **The setting is a standing rule, not a thing that happened once at
    /// launch.** "Open the Inbox with the board unless it's empty" is a sentence
    /// about arriving at the board, and picking another board or coming back
    /// from Today is arriving at the board — so shutting the panel is the
    /// answer for *this* board, now, and not a switch that quietly turns the
    /// setting off for the rest of the session. Closing it and staying put
    /// leaves it closed, which is the whole of what the button means.
    ///
    /// It only ever opens. Nothing here shuts a panel somebody has out: an
    /// empty Inbox is a reason not to raise one, never a reason to take away
    /// one already standing — a card dragged out of the Inbox onto the board
    /// would otherwise close the panel it was dragged from.
    private func raiseInboxWithTheBoard() {
        guard opensInboxWithTheBoard, surface == .board,
              Self.inboxOpensBesideTheBoard, !inboxTasks.isEmpty else { return }
        isInboxOpen = true
    }

    /// Puts the Inbox in front of somebody who asked for a card that is in it —
    /// a deep link, an intent, Spotlight. The panel stands beside the board, so
    /// this has to put the board back as well as the panel out.
    func showInbox() {
        surface = .board
        isInboxOpen = true
    }

    /// Puts the place a card lives on screen: its board, or the Inbox panel.
    ///
    /// Navigation and nothing else — it does not select the card or open a
    /// detail surface, because both callers already have one open and it is
    /// already showing this card. `reveal` adds those two on top for somebody
    /// arriving from outside the app; the board menu needs only this half,
    /// having been clicked from inside the panel it wants left standing.
    ///
    /// An archived card has no place on screen to be taken to — it is on the
    /// Archive view, which is not a board — so this leaves the user where they
    /// are rather than opening a board the card is not drawn on.
    func showPlace(of id: TaskItem.ID) {
        guard let task = self[id], !task.isArchived else { return }
        if let boardID = task.boardID {
            selectBoard(boardID)
        } else {
            // Unfiled, so the card is in the panel — which means putting the
            // board back as well, since the panel stands beside it.
            showInbox()
        }
        #if os(iOS)
        // And the phone, which shows one place at a time: the column the pager
        // is on, and the tab under it. `selectTab` also sets `surface`, which
        // is what the iPad's detail pane reads, so the two agree.
        if let columnID = task.columnID { mobileColumnID = columnID }
        // An unfiled card has had the Inbox raised for it already, by the
        // `showInbox()` above — which on the phone is the slide-over coming up
        // over the board. The tab underneath it is still the board's.
        selectTab(.board)
        #endif
    }

    /// Puts a task in front of the user on whichever surface is showing, and
    /// opens it: the card's board (or the Inbox panel), the card selected, and a
    /// detail surface up.
    ///
    /// **``showPlace(of:)`` plus the two things an arrival needs.** That one is
    /// navigation alone, for callers that already have the card's detail open
    /// and only want the board behind it put right. This is the whole errand,
    /// and it has three callers that mean exactly the same thing by it: a
    /// `littlekanban://` link, a Spotlight or notification tap, and a result
    /// chosen from the search panel.
    ///
    /// The query goes first. A result the user has chosen has ended the search
    /// that found it — and on the phone, where a query still narrows a saved
    /// view, landing on a board filtered to something the card does not match
    /// would open onto an empty column and read as the link having failed.
    ///
    /// An archived card has no board to be taken to, so it is shown where it
    /// does live: the Archive view.
    func reveal(_ id: TaskItem.ID) {
        guard let task = self[id] else { return }
        clearQuery()
        if task.isArchived {
            // The seeded Archive, by id. Somebody who deleted it has nowhere
            // archived to be shown, so the card's own place is the fallback —
            // which for an archived card is the column it was filed from.
            let archive = SavedView.id(of: .archive)
            if views.contains(where: { $0.id == archive }) {
                surface = .view(archive)
            } else {
                showPlace(of: task.id)
            }
        } else {
            showPlace(of: task.id)
        }
        select(task.id)
        // The desk and the iPad: the panel beside the board.
        isInspectorOpen = true
        #if os(iOS)
        isNavDrawerOpen = false
        sheetID = task.id
        #endif
    }

    /// A saved view's tasks: its predicate, its ordering and its cap.
    ///
    /// **The query is not one of them.** It used to be applied here, on every
    /// platform — and on the desk that meant a view quietly losing rows to a
    /// field the user had typed into to *search*, which is the same defect the
    /// board had. The phone still narrows a view it has opened, because its
    /// field is a tab rather than a panel; it does that at its own call site,
    /// through ``narrowed(_:)``, where `showsMobileFilterNotice` is already
    /// there to say so.
    func tasks(in view: SavedView, today: CalendarDay) -> [TaskItem] {
        members(of: view, today: today)
    }

    /// What the row's `CountPill` shows: how many tasks are *in* the view,
    /// unnarrowed. A badge that shrank as the user typed on another surface
    /// would be reporting the search rather than the view.
    ///
    /// A count rather than `members(of:)`: the sort and the prefix cannot
    /// change how many there are, so neither is paid for a number. Memoised
    /// the way `visibleTasksByColumn` is, because every sidebar and drawer row
    /// asks on every render — twice, counting the accessibility value — and
    /// the phone's drawer renders per frame while it is being dragged open.
    /// The memo keeps the rule and the limit rather than trusting the id: the
    /// editor asks about a *draft* that shares its id with the saved row. The
    /// name and the symbol stay out of the key, because they cannot change the
    /// answer and the name is edited a keystroke at a time.
    func count(of view: SavedView, today: CalendarDay) -> Int {
        // Read unconditionally, so a memo hit still registers the caller's
        // dependency on the board — the `position(of:)` bargain.
        let tasks = self.tasks
        let week = weekMeaning
        if let memo = viewCounts[view.id],
           memo.revision == boardRevision, memo.today == today, memo.week == week,
           memo.rule == view.rule, memo.limit == view.limit {
            return memo.count
        }
        let now = Date.now
        let matched = tasks.count {
            view.matches($0, today: today, isDone: isDone($0), week: week, now: now)
        }
        let count = view.limit.map { Swift.min(matched, $0) } ?? matched
        viewCounts[view.id] = ViewCountMemo(
            revision: boardRevision, today: today, week: week,
            rule: view.rule, limit: view.limit, count: count
        )
        return count
    }

    private struct ViewCountMemo {
        var revision: Int
        var today: CalendarDay
        var week: WeekMeaning
        var rule: ViewRule
        var limit: Int?
        var count: Int
    }

    /// One memo per view id; stale entries are overwritten on the next ask and
    /// deleted rows simply stop being asked about, so the map stays row-sized.
    @ObservationIgnored private var viewCounts: [SavedView.ID: ViewCountMemo] = [:]

    /// Memoised the way `count(of:)` is, and for the same caller: the surfaces
    /// ask on every render, and the phone's root asks per frame while the
    /// drawer is being dragged open — a filter and a sort of every task in the
    /// app, per frame, was most of what that drag cost. The key carries the
    /// rule, sort and limit for the count memo's reason: the editor asks about
    /// a draft that shares its id with the saved row.
    private func members(of view: SavedView, today: CalendarDay) -> [TaskItem] {
        // Read unconditionally, so a memo hit still registers the caller's
        // dependency on the board — the `position(of:)` bargain.
        let tasks = self.tasks
        let week = weekMeaning
        if let memo = viewMembers[view.id],
           memo.revision == boardRevision, memo.count == tasks.count,
           memo.today == today, memo.week == week,
           memo.rule == view.rule, memo.sort == view.sort, memo.limit == view.limit {
            return memo.members
        }
        // `now` is taken once for the whole pass rather than per task: the
        // "updated within the last N days" criteria measure against it, and a
        // clock read per card would put two cards either side of a cutoff that
        // moved between them.
        let now = Date.now
        var members = tasks.filter {
            view.matches($0, today: today, isDone: isDone($0), week: week, now: now)
        }
        if let sort = view.sort.comparator { members = Self.stableSorted(members, by: sort) }
        if let limit = view.limit { members = Array(members.prefix(limit)) }
        viewMembers[view.id] = ViewMembersMemo(
            revision: boardRevision, count: tasks.count, today: today, week: week,
            rule: view.rule, sort: view.sort, limit: view.limit, members: members
        )
        return members
    }

    private struct ViewMembersMemo {
        var revision: Int
        var count: Int
        var today: CalendarDay
        var week: WeekMeaning
        var rule: ViewRule
        var sort: ViewSort
        var limit: Int?
        var members: [TaskItem]
    }

    /// One memo per view id, row-sized for `viewCounts`' reason.
    @ObservationIgnored private var viewMembers: [SavedView.ID: ViewMembersMemo] = [:]

    // MARK: - Saved views

    /// Makes a view and returns it, so the caller can open the editor on it.
    ///
    /// Appended rather than inserted: the sidebar's order is the user's, and a
    /// new row landing at the top would push the one they were aiming at down
    /// under the cursor.
    @discardableResult
    func addView(named name: String = "") -> SavedView {
        let trimmed = Self.viewName(name)
        let view = SavedView.blank(
            named: trimmed.isEmpty
                ? String(localized: "New View", comment: "Default name for a newly created saved view")
                : trimmed
        )
        undoable(String(localized: "Add View", comment: "Undo action name for creating a saved view")) {
            views.append(view)
            scheduleSave()
        }
        return view
    }

    /// Writes a view back after the editor has finished with it.
    ///
    /// The whole view at once rather than a setter per field: the editor works
    /// on a copy and commits, so a rule, a name, a glyph and a sort changed in
    /// one sitting are one ⌘Z — which is what "I did not mean that" means about
    /// a session with an editor.
    ///
    /// An empty name is refused rather than accepted, the way a board's and a
    /// column's are: a row with nothing on it cannot be told from a bug.
    func updateView(_ view: SavedView) {
        guard let index = views.firstIndex(where: { $0.id == view.id }) else { return }
        var next = view
        next.name = Self.viewName(view.name)
        guard !next.name.isEmpty else { return }
        guard next != views[index] else { return }
        undoable(String(localized: "Edit View", comment: "Undo action name for editing a saved view")) {
            views[index] = next
            scheduleSave()
        }
    }

    /// A copy, named "… copy", landing directly under the one it came from —
    /// which is where somebody duplicating a row is looking.
    @discardableResult
    func duplicateView(_ id: SavedView.ID) -> SavedView? {
        guard let index = views.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = views[index]
        copy.id = UUID()
        copy.name = String(
            localized: "\(views[index].name) copy",
            comment: "Name of a duplicated saved view — the original's name followed by 'copy'"
        )
        // A duplicate is the user's own view whatever it was copied from, so it
        // loses the preset: the hand-written empty state belongs to the seeded
        // row, and two rows claiming it would both say "Nothing due today".
        copy.preset = nil
        let made = copy
        undoable(String(localized: "Duplicate View", comment: "Undo action name for duplicating a saved view")) {
            views.insert(made, at: index + 1)
            scheduleSave()
        }
        return made
    }

    /// Deletes a view. One ⌘Z, like everything else — there is no trash for a
    /// view: a `TrashedItem` holds work, and a view holds none. What is lost is
    /// a rule, and ⌘Z is the right size of net for that.
    func deleteView(_ id: SavedView.ID) {
        guard views.contains(where: { $0.id == id }) else { return }
        undoable(String(localized: "Delete View", comment: "Undo action name for deleting a saved view")) {
            views.removeAll { $0.id == id }
            scheduleSave()
        }
        // Standing on the view that just went is standing on nothing. `apply`
        // says the same thing for the undo path; this is the direct one.
        if case .view(id) = surface { surface = .board }
    }

    func moveView(fromOffsets: IndexSet, toOffset: Int) {
        var next = views
        next.move(fromOffsets: fromOffsets, toOffset: toOffset)
        guard next != views else { return }
        undoable(String(localized: "Reorder Views", comment: "Undo action name for reordering the saved views")) {
            views = next
            scheduleSave()
        }
    }

    /// Puts the seven back, alongside whatever the user has made.
    ///
    /// The way out of having deleted Today and wanting it again — and the reason
    /// deleting a seeded view needs no confirmation. Only the ones that are
    /// actually missing are restored, by id, so pressing it twice is not two
    /// copies of the Archive.
    func restoreSeededViews() {
        let present = Set(views.map(\.id))
        let missing = SavedView.seededAll.filter { !present.contains($0.id) }
        guard !missing.isEmpty else { return }
        undoable(String(localized: "Restore Views", comment: "Undo action name for restoring the built-in saved views")) {
            views.append(contentsOf: missing)
            scheduleSave()
        }
    }

    /// Whether any of the seeded seven is missing, which is the only condition
    /// under which **Restore Built-in Views** is worth offering.
    var isMissingSeededViews: Bool {
        let present = Set(views.map(\.id))
        return SavedView.Preset.allCases.contains { !present.contains(SavedView.id(of: $0)) }
    }

    static func viewName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `sorted(by:)` is not stable, and the Archive's comparator ties whenever
    /// "Archive completed" files a column's worth of cards on one instant —
    /// which would order them arbitrarily, and differently on each render.
    /// Decorating with the board index and falling back to it keeps the order
    /// the user dragged their cards into underneath the view's own.
    private static func stableSorted(
        _ items: [TaskItem], by areInOrder: (TaskItem, TaskItem) -> Bool
    ) -> [TaskItem] {
        items.enumerated().sorted { lhs, rhs in
            if areInOrder(lhs.element, rhs.element) { return true }
            if areInOrder(rhs.element, lhs.element) { return false }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    // MARK: - Dragging

    /// Puts the board back to how it looks when nothing is being carried: the
    /// card at full strength, and no highlight on wherever it was going to land.
    ///
    /// Called when the drag is *finished with*, which on macOS is a good deal
    /// later than the mouse coming up. `dropDestination` hands its closure
    /// decoded items, so SwiftUI takes the drop, plays the drag image into
    /// place, and only then loads the payload off the pasteboard and runs the
    /// handler. Clearing this at mouse-up drew the card back at full strength
    /// in the column it was leaving, where it sat for a tenth of a second
    /// before the move landed and took it away — the card flashing back to
    /// where it came from, which is what a drag is supposed to look like when
    /// it *fails*. See ``CardDragSession`` for which phase calls this.
    func endDrag() {
        draggingID = nil
        dragHasBeenSeen = false
        destinationsTargeted = 0
        dropTargetColumnID = nil
        dropTargetCaret = nil
        isInboxDropTarget = false
    }

    /// Whether the card that was picked up is actually being **carried** — a
    /// drag some destination has seen under it, rather than a finger that held
    /// a card and let go of it without going anywhere.
    ///
    /// **What the insertion zones hang on, and why ``draggingID`` cannot.** A
    /// card's two halves are clear panes laid over the card — see
    /// `BoardTaskCard.dropZones` — and a pane over a card nobody is dragging
    /// onto takes the tap that opens it. `BoardSettingsView` wrote that rule
    /// down for its column rows and the cards did not follow it far enough:
    /// they mounted their panes on `draggingID`, which on a build without
    /// `onDragSessionUpdated` is set by the lift and cleared by the drop — so a
    /// long press that lifted a card and put it straight back down left every
    /// card in the list under a pane, and untappable, for the whole of
    /// ``liftExpiry``. Which is exactly what a long press *is* to a hand that
    /// has changed its mind, and what it is to a hand that meant to tap.
    ///
    /// **A lift is not a drag, and only a destination can tell them apart.**
    /// Measured on the simulator: a press-and-hold released in place reports no
    /// targeting anywhere — not one callback, from the ground or from a pane —
    /// while a drag of even a few points has the list's ground reporting
    /// before the finger has gone half a card. So the panes wait for that
    /// report. Nothing is delayed by it that a drop could reach: the ground is
    /// mounted whether or not anything is in the air, and it is what answers
    /// first, every time, because the panes it precedes are not there yet.
    var isCardTravelling: Bool { draggingID != nil && dragHasBeenSeen }

    /// Whether any destination has reported the drag since the card was picked
    /// up. Read through ``isCardTravelling`` and never on its own, which is
    /// what makes that one *and* a card still in the air: `draggingID` is
    /// cleared from several places that are not `endDrag` — a task discarded,
    /// archived, or taken away wholesale by a restore — and a pane left over a
    /// card by one of those is the very thing this was written to end.
    private var dragHasBeenSeen: Bool {
        get {
            access(keyPath: \.dragHasBeenSeen)
            return _dragHasBeenSeen
        }
        set {
            guard newValue != _dragHasBeenSeen else { return }
            withMutation(keyPath: \.dragHasBeenSeen) { _dragHasBeenSeen = newValue }
        }
    }
    @ObservationIgnored private var _dragHasBeenSeen = false

    /// How many destinations have the drag over them at this moment.
    ///
    /// A count rather than a flag because destinations nest — a card's half
    /// sits inside its list's ground — and crossing from one into the other is
    /// a `false` and a `true` whose order SwiftUI does not promise. Clamped at
    /// zero so an unmatched report cannot take it negative and strand the drag
    /// below the floor.
    @ObservationIgnored private var destinationsTargeted = 0

    /// Bumped by every pick-up, so a settle scheduled by one drag cannot end
    /// the next one.
    @ObservationIgnored private var lifts = 0

    /// What every destination that takes a card says as the drag arrives over
    /// it and as it leaves again — the line above whatever else its
    /// `isTargeted` closure does.
    ///
    /// **Two facts come out of it.** That a lift has become a drag, which is
    /// what puts the insertion zones on screen — see ``isCardTravelling``. And
    /// that a drag is over, which is the harder one: a card let go over nothing
    /// ends its session without telling anybody, and until iOS 27 there is no
    /// `onDragSessionUpdated` to ask. Every destination letting go at once says
    /// it instead. Not instantly — a finger crossing out of a pane and into the
    /// ground behind it passes through nobody's hands — so the claim has to
    /// survive ``dragSettle`` before it is believed.
    ///
    /// Where the session *does* announce its own end this infers nothing and
    /// only keeps the count: `CardDragSession` has the answer from the system,
    /// and a guess standing beside a fact is a second opinion nobody asked for.
    func dragTargeting(_ targeted: Bool) {
        destinationsTargeted = targeted ? destinationsTargeted + 1 : max(0, destinationsTargeted - 1)
        guard draggingID != nil else { return }
        if targeted { return dragHasBeenSeen = true }
        guard !Self.announcesDragEnd, destinationsTargeted == 0 else { return }
        let lift = lifts
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.dragSettle))
            guard let self, lifts == lift, destinationsTargeted == 0, draggingID != nil
            else { return }
            endDrag()
        }
    }

    /// Whether the drag session says when it has finished — `onDragSessionUpdated`,
    /// which ``CardDragSession`` reads and which is macOS 26 but iOS **27**.
    /// Everywhere else the end of a drag is inferred from the destinations
    /// letting go of it, which is ``dragTargeting(_:)``.
    static var announcesDragEnd: Bool {
        #if os(macOS)
        true
        #else
        if #available(iOS 27.0, *) { true } else { false }
        #endif
    }

    /// How long every destination has to stay let-go of before that counts as
    /// the drag being over. Long enough to cover a finger crossing the gutter
    /// between two columns, short enough that a card put back down is tappable
    /// again before a hand can reach it.
    static let dragSettle: TimeInterval = 0.75

    /// Says a card has been picked up, from the one signal a build without
    /// `onDragSessionUpdated` has: the moment `.draggable` is asked for its
    /// payload.
    ///
    /// **Once per pick-up, which takes a latch.** SwiftUI does not ask for a
    /// payload once — it asks again for the preview, and again as the view
    /// updates under the finger, three to six times for a single lift — so the
    /// first ask is the lift and the rest are noise.
    ///
    /// **All of it deferred a turn**, because the ask can land inside a view
    /// update and this writes state the board is drawn from.
    ///
    /// **A lift, which is not yet a drag.** What this says is that a card has
    /// been picked up — the card dims on it, and nothing else does. The
    /// insertion zones wait for ``isCardTravelling``, because a hold released
    /// in place is a lift with no drag anywhere in it, and panes over a card
    /// nobody is dragging onto take the tap that opens it.
    ///
    /// The expiry is the last resort for the case that has no callback at all
    /// before `onDragSessionUpdated`: a card let go over nothing ends its
    /// session without telling anybody, and without this the board would stay
    /// dimmed until the next pick-up. Every drop clears the lift on the way
    /// through `endDrag`, and a drag that was seen and then let go of is
    /// cleared by ``dragTargeting(_:)`` a ``dragSettle`` later, so what reaches
    /// twenty seconds is a lift nothing ever saw — and that one costs a dimmed
    /// card and nothing more.
    func beginDrag(_ id: TaskItem.ID, onLift: @escaping () -> Void = {}) {
        Task { @MainActor [weak self] in
            guard let self, draggingID != id else { return }
            lifts += 1
            let lift = lifts
            destinationsTargeted = 0
            dragHasBeenSeen = false
            draggingID = id
            onLift()
            try? await Task.sleep(for: .seconds(Self.liftExpiry))
            if lifts == lift, draggingID == id { endDrag() }
        }
    }

    /// How long a lift nobody ended is believed. Long enough to cross a board
    /// with, short enough that a session lost to a gesture the OS ate does not
    /// outlive the user's patience.
    static let liftExpiry: TimeInterval = 20

    /// Where the card in flight would land if it were let go now.
    ///
    /// **Because until now nothing said.** A lifted card dimmed and the column
    /// under the pointer lit up, which answers *which list* and not *where in
    /// it* — and "where in it" is the whole of what a reorder is. Worse, the
    /// answer is not the obvious one: dropping onto a card lands **after** it
    /// when the drag came from above and **before** it when it came from below,
    /// which is `move(_:onto:)`'s off-by-one and is impossible to guess from
    /// the outside. This is that rule, read back.
    ///
    /// `nil` where a release would move nothing — over the dragged card itself,
    /// or over the ground of the column it already sits in. The Inbox is the one
    /// exception: dropping a non-final Inbox card on its ground means moving it
    /// to the foot, just as the final card's lower half does.
    var dropCaret: DropCaret? {
        if let caret = dropTargetCaret {
            // The rule for the list the caret is *in*, not for the board: the
            // Inbox keeps its marks while a saved view is open behind it, the
            // same way it keeps its drops. Asking `allowsCardDrag` flatly here
            // was why the Inbox opened no gap under a card in flight on the
            // phone — the drop worked and nothing on screen said where it
            // would land, which is the half of a drag that tells you what you
            // are about to do.
            guard let target = self[caret.card],
                  allowsCardDrag(into: target.placement)
            else { return nil }
            // Not on the card in the air: it is about to leave, and a line
            // against a card that is going says nothing about where anything
            // lands. `draggingID` is *not* required for the rest — a caret is a
            // fact about the pointer, and on a build with no drag-session
            // callback there may be nothing in `draggingID` to compare with.
            return caret.card == draggingID ? nil : caret
        }
        // The pointer is on a list's own ground rather than on a gap it has
        // named, and a drop there lands at the foot — see ``groundCaret(in:)``.
        guard let dragging = draggingID, let destination = hoveredDropPlacement,
              allowsCardDrag(into: destination), let task = self[dragging]
        else { return nil }
        let inboxReorder = destination.isInbox && task.placement == destination
            && tasks(in: destination).last?.id != dragging
        guard task.placement != destination || inboxReorder else { return nil }
        return groundCaret(in: destination)
    }

    /// Where a drop on a list's *ground* lands: **the foot of it**.
    ///
    /// The ground is the space around a list's cards — the room under the last
    /// one, most of an empty column, the strip beside the header — and it names
    /// no gap, so something has to be the default.
    ///
    /// It briefly kept the row the card came in on: a card third in Doing landed
    /// third in the Backlog it was dropped on. That reads well written down and
    /// badly under a finger. What a person aims at is the space *under* the
    /// cards, and a card that lands halfway up the list they were pointing below
    /// of has gone somewhere nothing marked — on the phone, where a column is a
    /// whole screen and the ground is everything below the last card, it jumped
    /// several rows up the list on release.
    ///
    /// So the ground is the plainest thing it can be: the bottom, which is where
    /// every other route into a list already puts a card — the move-to menu, the
    /// sidebar's board rows, a bulk move, `move(_:to:)` itself.
    ///
    /// A pointer *inside* a card is a different question, answered above this: it
    /// has named a gap, and a named gap always wins. An empty list has no card to
    /// draw a caret against at all, so it gets none — the column highlight is the
    /// whole of the feedback there, and the drop still lands.
    private func groundCaret(in destination: TaskPlacement) -> DropCaret? {
        tasks(in: destination).last.map { .below($0.id) }
    }

    /// Where the card in flight would sit in `placement`'s rows if it were let
    /// go now — the same question ``dropCaret`` answers, in the form a list
    /// needs to open a gap rather than the form a card needs to draw an edge.
    ///
    /// `nil` when the drop would not land in this list, or when nothing is in
    /// the air at all. Every list on screen asks this of itself; at most one of
    /// them gets an answer.
    ///
    /// **Stricter than the caret, in one case on purpose.** A line against the
    /// gap a card already occupies claims very little, and the caret draws it. A
    /// card-shaped hole opening beside the very card that would fill it is a
    /// promise that the board is about to change — and `drop(_:at:)` refuses
    /// exactly that drop as a no-op that would cost a ⌘Z. The mark must not
    /// promise a move the drop will not make, so this asks the same `isAlready`
    /// the drop does.
    ///
    /// **An empty column gets one, where the caret could not.** ``dropCaret``
    /// goes quiet over a list with nothing in it, and has to: a line needs a
    /// card to hang off and there is no card. That left the column highlight as
    /// the whole of the feedback for a drop into an empty column — which is
    /// precisely the drop with least else on screen to explain it. A row needs
    /// no anchor, so the empty column shows the card about to become its first.
    func dropPreview(in placement: TaskPlacement) -> DropPreview? {
        guard let dragging = draggingID, let task = self[dragging] else { return nil }
        let rows = tasks(in: placement)
        if let caret = dropCaret {
            guard let anchor = rows.firstIndex(where: { $0.id == caret.card }),
                  !isAlready(dragging, at: caret)
            else { return nil }
            return DropPreview(
                task: task, index: caret.isAbove ? anchor : anchor + 1,
                caret: caret, placement: placement
            )
        }
        // The empty-column case above. `dropCaret` is nil here for want of an
        // anchor, not because the drop would go nowhere — so the rest of what
        // it would have checked is asked again: the board is in its own order,
        // the pointer is over *this* list, and the card is not already in it.
        guard allowsCardDrag(into: placement), rows.isEmpty,
              hoveredDropPlacement == placement, task.placement != placement
        else { return nil }
        return DropPreview(task: task, index: 0, caret: nil, placement: placement)
    }

    /// Puts the dragged card exactly where the caret says, which is the one
    /// place a drop is allowed to land now that the caret has promised it.
    ///
    /// This replaced `move(_:onto:)` on the board's cards. That one resolved a
    /// drop by *direction of travel* — the only thing "dropped onto this card"
    /// can mean when the drop names a card rather than a gap — and the price
    /// was that the head of a list was unreachable from above it. A caret names
    /// a gap, so this inserts into that gap and nothing has to be inferred.
    func drop(_ id: TaskItem.ID, at caret: DropCaret) {
        guard id != caret.card, let target = self[caret.card] else { return }
        let placement = target.placement
        // A drop that puts the card back where it already is costs a ⌘Z and
        // writes "Move Task" into the history of a card that did not move.
        guard !isAlready(id, at: caret) else { return endDrag() }

        let before: TaskItem.ID?
        switch caret {
        case .above:
            before = caret.card
        case .below:
            // The next card *in the target's own list*, which is where the
            // caret was drawn — not the next card in the board array, which
            // may belong to another column entirely.
            before = neighbour(after: caret.card, in: placement)?.id
        }
        undoable(Self.moveName(for: placement)) {
            performMove(id, to: placement, before: before, toTheEnd: before == nil)
        }
    }

    /// The drop a list's own ground takes — the column around its cards, the
    /// Inbox panel around its own — which names no gap, so it lands at the foot,
    /// where ``groundCaret(in:)`` promised the caret would.
    ///
    /// **It is `move(_:to:)` with one refusal in front of it**, rather than a
    /// rule of its own: a drop on the ground of a board column the card is
    /// already in is aimed at where it already is, and `performMove` would
    /// return without moving it — but only after `undoable` had opened a step.
    /// The Inbox makes one useful exception: its non-final cards can be dropped
    /// on the ground to move them to the foot.
    ///
    /// Kept as a name of its own rather than folded into that one call, because
    /// the four surfaces that take a drop on ground say which kind of drop it is
    /// at the call site — and `DragReorderTests` reads those call sites to check
    /// that a *ground* drop has not quietly become one that names a card.
    func drop(_ id: TaskItem.ID, onGroundOf placement: TaskPlacement) {
        guard isPlaceable(placement), let task = self[id] else { return }
        if task.placement == placement {
            guard placement.isInbox, tasks(in: placement).last?.id != id else { return endDrag() }
            return undoable(Self.moveName(for: placement)) {
                performMove(id, to: placement, toTheEnd: true)
            }
        }
        move(id, to: placement)
    }

    /// Whether the card is already sitting in the gap the caret names.
    private func isAlready(_ id: TaskItem.ID, at caret: DropCaret) -> Bool {
        guard let target = self[caret.card], self[id]?.placement == target.placement else {
            return false
        }
        let list = tasks(in: target.placement).map(\.id)
        guard let dragged = list.firstIndex(of: id), let anchor = list.firstIndex(of: caret.card)
        else { return false }
        switch caret {
        case .above: return anchor == dragged + 1
        case .below: return anchor == dragged - 1
        }
    }

    /// The card after `id` in the list it is in.
    private func neighbour(after id: TaskItem.ID, in placement: TaskPlacement) -> TaskItem? {
        let list = tasks(in: placement)
        guard let index = list.firstIndex(where: { $0.id == id }), index + 1 < list.count
        else { return nil }
        return list[index + 1]
    }

    /// Which list the pointer is over, as a placement — the Inbox panel being
    /// the one that is not a column.
    private var hoveredDropPlacement: TaskPlacement? {
        if isInboxDropTarget { return .inbox }
        guard let columnID = dropTargetColumnID else { return nil }
        let placement = placement(forColumn: columnID)
        return isPlaceable(placement) ? placement : nil
    }

    /// The cards in a place, in board order.
    private func tasks(in placement: TaskPlacement) -> [TaskItem] {
        switch placement {
        case .inbox: inboxTasks
        case .column(_, let columnID): visibleTasks(in: columnID)
        }
    }

    // MARK: - Moving

    /// Moves a task to `columnID`. When `beforeID` is given the task is inserted
    /// ahead of that task, which is how card-to-card drops reorder a column;
    /// otherwise it lands at the end of the board order.
    ///
    /// A drop on the column the card is already in, aimed at no particular
    /// card, is aimed at where the card already is: it does nothing rather than
    /// sending the card to the bottom of its own column.
    ///
    /// Moving into Done ticks off any outstanding sub-tasks, matching the spec.
    func move(_ id: TaskItem.ID, to columnID: BoardColumn.ID, before beforeID: TaskItem.ID? = nil) {
        move(id, to: placement(forColumn: columnID), before: beforeID)
    }

    /// The same, to a place rather than to a column — which is how a card
    /// reaches the global Inbox, where there is no column to name.
    ///
    /// A placement pairing a board with a column that is not on it names
    /// nowhere, and the card stays where it is: it is already somewhere real.
    func move(_ id: TaskItem.ID, to placement: TaskPlacement, before beforeID: TaskItem.ID? = nil) {
        guard isPlaceable(placement) else { return }
        undoable(Self.moveName(for: placement)) {
            performMove(id, to: placement, before: beforeID)
        }
    }

    /// Files a task onto a board, in one of its columns.
    ///
    /// This and `unfile` are the whole of the placement API: `TaskPlacement`
    /// cannot spell "on a board, in no column", and `TaskItem.placement` is the
    /// only writer of the two fields, so half the invariant holds by
    /// construction. The other half — that the column is on the board it is
    /// paired with — is `isPlaceable`'s, asked by the `move` this goes through.
    func file(_ id: TaskItem.ID, onto boardID: Board.ID, column columnID: BoardColumn.ID) {
        move(id, to: .column(board: boardID, column: columnID))
    }

    /// Files a task onto a board without saying where on it — into that board's
    /// landing column, which is what a "Move to board ▸" menu means.
    func file(_ id: TaskItem.ID, onto boardID: Board.ID) {
        guard let column = board(id: boardID)?.landingColumn else { return }
        file(id, onto: boardID, column: column.id)
    }

    /// Takes a task off its board and back into the global Inbox — the return
    /// journey the "move to" control has no segment for.
    func unfile(_ id: TaskItem.ID) {
        // Already there is not a move. Dropping a card back on the Inbox it
        // came from — onto the panel, or onto the source list's row — would
        // otherwise cost a ⌘Z and leave "Moved to Inbox" in its history, for a
        // card that has not gone anywhere. `move` cannot make this judgement:
        // a move to the column a card is already in is a *reorder*, and those
        // are real.
        guard self[id]?.isUnfiled == false else { return }
        move(id, to: .inbox)
    }

    /// Moves a dragged card to where it was dropped: onto `target`.
    ///
    /// `before:` can only say "ahead of that one", so a card dragged
    /// *downwards* onto the card below it would be taken out and put back
    /// exactly where it started — the same off-by-one `dropOffset(from:to:)`
    /// solves for sub-tasks. Dropping onto a card that is already behind you
    /// means landing behind it, which is "ahead of whatever follows it", or at
    /// the end of the board order when nothing does.
    func move(_ id: TaskItem.ID, onto target: TaskItem.ID) {
        guard id != target,
              let from = position(of: id),
              let to = position(of: target),
              let placement = self[target]?.placement
        else { return }
        let landsAfter = from < to
        let before = landsAfter ? tasks[(to + 1)...].first?.id : target
        undoable(Self.moveName(for: placement)) {
            performMove(id, to: placement, before: before, toTheEnd: landsAfter && before == nil)
        }
    }

    private static func moveName(for placement: TaskPlacement, count: Int = 1) -> String {
        if placement.isInbox {
            return String(localized: "Move to Inbox", comment: "Undo action name for taking a card off its board")
        }
        return count > 1
            ? String(localized: "Move Tasks", comment: "Undo action name for moving several cards at once")
            : String(localized: "Move Task", comment: "Undo action name for moving a card")
    }

    /// The move itself. Separated from `move` so `complete` and `reopen` can
    /// name their own undo step instead of inheriting "Move Task".
    /// `toTheEnd` distinguishes "dropped on the column, nowhere in particular"
    /// — which is a no-op, see item 1.17 — from "dropped past the last card",
    /// which is a real reorder that also has no card to sit in front of.
    private func performMove(
        _ id: TaskItem.ID,
        to placement: TaskPlacement,
        before beforeID: TaskItem.ID? = nil,
        toTheEnd: Bool = false
    ) {
        guard let index = position(of: id) else { return }
        // A filed card has left the board, so it has no place on one to change.
        // The guard lives here rather than in each caller because every route —
        // the menu, the rotor, a drag, a bulk command — comes through here, and
        // the Archive is ordered by `archivedAt`, so a card moved from it would
        // not visibly move at all. `unarchive` is the way back.
        guard !tasks[index].isArchived else { return }
        // A card dropped on itself has nothing to sit in front of.
        let target = beforeID == id ? nil : beforeID
        guard tasks[index].placement != placement || target != nil || toTheEnd else {
            endDrag()
            return
        }

        var moved = tasks.remove(at: index)
        let wasElsewhere = moved.placement != placement
        moved.placement = placement
        if case .column(_, let columnID) = placement {
            // Inbox completion belongs only to the Inbox. Filing a completed
            // capture makes it active work on its destination board again.
            moved.inboxCompletedAt = nil
            if isDone(column: columnID), wasElsewhere {
                let outstanding = moved.subtasks.count { !$0.done }
                if outstanding > 0 {
                    moved.subtasks = moved.subtasks.map { var s = $0; s.done = true; return s }
                    moved.activity.insert(ActivityEntry(.subtasksCompletedOnDone(count: outstanding)), at: 0)
                }
                // The one transition that means a card was finished, on every
                // route — the tick, the menu, the keyboard, a drag onto the
                // column. Undo and a sync merge never come through here, so
                // neither can ring the bell for a board merely put back.
                CompletionFeedback.shared.taskCompleted()
            }
            if wasElsewhere, let column = column(id: columnID) {
                moved.activity.insert(
                    ActivityEntry(.moved(columnID: column.id.uuidString, columnName: column.name)), at: 0
                )
            }
        } else if wasElsewhere {
            // Not a `.moved`: the Inbox is not a column, and its name is the
            // app's rather than the user's — see `ActivityEntry.Kind.unfiled`.
            moved.activity.insert(ActivityEntry(.unfiled), at: 0)
        }
        moved.updatedAt = .now
        markChanged(moved.id)

        if let target, let insertion = position(of: target) {
            tasks.insert(moved, at: insertion)
        } else {
            tasks.append(moved)
        }

        endDrag()
        scheduleSave()
    }

    // MARK: - Completing

    /// Sends a board task to Done, or marks an Inbox task completed in place.
    ///
    /// An archived task refuses both this and `reopen`: in the Archive the verb
    /// is Restore and only Restore, and the refusal lives here so no surface can
    /// reintroduce a tick that silently picks the column a filed card would
    /// reappear in and closes its outstanding sub-tasks on the way.
    func complete(_ id: TaskItem.ID) {
        guard let task = self[id], !task.isArchived else { return }
        if task.isUnfiled {
            guard !task.isInboxCompleted else { return }
            undoable(String(localized: "Complete Task", comment: "Undo action name for completing a task")) {
                update(id) { $0.inboxCompletedAt = .now }
                CompletionFeedback.shared.taskCompleted()
            }
            return
        }
        guard let target = donePlacement(for: id) else { return }
        undoable(String(localized: "Complete Task", comment: "Undo action name for completing a task")) {
            performMove(id, to: target)
        }
    }

    /// Where completing a card would send it, or `nil` when there is nowhere:
    /// it is archived, it is already in Done, or its board has no Done column —
    /// which `deleteColumn` refuses to leave behind, but a hand-edited file can
    /// still arrive like.
    ///
    /// The one place the rule lives, so `canComplete` cannot answer a different
    /// question from the one `complete` acts on.
    private func donePlacement(for id: TaskItem.ID) -> TaskPlacement? {
        guard let task = self[id], !task.isArchived, !isDone(task) else { return nil }
        if task.isUnfiled { return .inbox }
        guard let done = doneColumnID(onBoard: task.boardID) else { return nil }
        return placement(forColumn: done)
    }

    /// Takes a task back out of Done, to wherever it was working before.
    func reopen(_ id: TaskItem.ID) {
        guard let task = self[id], !task.isArchived else { return }
        if task.isInboxCompleted {
            undoable(String(localized: "Reopen Task", comment: "Undo action name for reopening a completed task")) {
                update(id) { $0.inboxCompletedAt = nil }
            }
            return
        }
        guard let target = reopenTarget(for: id) else { return }
        undoable(String(localized: "Reopen Task", comment: "Undo action name for reopening a completed task")) {
            performMove(id, to: target)
        }
    }

    /// Where reopening would send a card, or `nil` when there is nowhere for it
    /// to go.
    ///
    /// A board whose only column is its Done one has no working column to go
    /// back to — which is what every board looks like the moment it is made —
    /// and `reopenPlacement` answers that by handing back the placement the card
    /// already has. Read here as "nothing to do", so the tick that would perform
    /// it is not drawn live: a control that can be pressed and changes nothing
    /// is indistinguishable from a bug.
    private func reopenTarget(for id: TaskItem.ID) -> TaskPlacement? {
        guard let task = self[id], !task.isArchived, isDone(task) else { return nil }
        let target = reopenPlacement(for: task)
        return target == task.placement ? nil : target
    }

    func canReopen(_ id: TaskItem.ID) -> Bool {
        self[id]?.isInboxCompleted == true || reopenTarget(for: id) != nil
    }

    /// Where a completed task goes back to: the newest column its own history
    /// names other than Done. A task that reached Done without ever being moved
    /// has nothing to go back to, so it starts the workflow again at Backlog —
    /// on its own board, or on the one on screen if it was completed out of the
    /// Inbox and has no board of its own to go back to.
    private func reopenPlacement(for task: TaskItem) -> TaskPlacement {
        // Its own board's columns, not every board's: a card that once lived on
        // another board still names that board's columns in its history, and
        // resolving one of them here would reopen the card onto a board the
        // user was not looking at and did not ask about.
        guard let board = board(for: task) ?? activeBoard else { return task.placement }
        let done = board.doneColumn?.id
        for entry in task.activity {
            guard case .moved(let columnID, _) = entry.kind,
                  let id = UUID(uuidString: columnID),
                  let column = board.column(id: id), column.id != done
            else { continue }
            return .column(board: board.id, column: column.id)
        }
        guard let column = board.landingColumn else { return task.placement }
        return .column(board: board.id, column: column.id)
    }

    // MARK: - Deleting

    /// Removes a task. There is no confirmation on purpose: the delete happens,
    /// and undo — not a dialog the user learns to dismiss — is the safety net.
    /// The task comes back so a caller can say what it was that went.
    @discardableResult
    func deleteTask(_ id: TaskItem.ID) -> TaskItem? {
        guard tasks.contains(where: { $0.id == id }) else { return nil }
        restoreEmptiedFields(on: id)
        var removed: TaskItem?
        undoable(String(localized: "Delete Task", comment: "Undo action name for deleting a task")) {
            removed = discard(id)
        }
        return removed
    }

    /// Drops a card that a `+` created and the user filled nothing into — the
    /// untitled card otherwise left behind by opening the capture editor and
    /// closing it again.
    ///
    /// "Filled nothing in" means every control is back where capture left it,
    /// which is not the same as every control being empty: a card filed onto a
    /// board from the editor's own board menu stays even with nothing else in
    /// it, and one that starts with a default due date still goes. A card typed
    /// into and emptied again goes as well — the user closed the editor with
    /// nothing in it, and how long they spent getting there is not this rule's
    /// business.
    ///
    /// It registers a step, even though nothing the user meant to keep is being
    /// lost. It used to not, on the grounds that the capture and the discard
    /// cancel out — but they only cancel out on the board, not on the stack, and
    /// an unregistered removal sitting on top of the capture's step is exactly
    /// the shape that lets a later ⌘Z put the discarded card back.
    func discardIfBlank(_ id: TaskItem.ID) {
        // The dismissal ends the capture either way: whatever the card is from
        // here on, it is one the user kept, and it is not asked again.
        guard let made = blankCaptures.removeValue(forKey: id), let task = self[id],
              task.hasSameContent(as: made)
        else { return }
        undoable(String(localized: "Discard Capture", comment: "Undo action name for dropping an unused quick capture")) {
            // Hand the code back when it was the last one minted, so a capture
            // the user thought better of leaves no gap in the numbering.
            if BoardSnapshot.serial(ofCode: task.code) == nextSerial - 1 { nextSerial -= 1 }
            discard(id)
        }
    }

    /// Takes a task off the board and every trace of it out of the session:
    /// the selection falls to its neighbour in the same column, and its
    /// half-typed drafts, open editing sessions and search memo go with it, so
    /// nothing the user typed against it is left in memory afterwards.
    @discardableResult
    private func discard(_ id: TaskItem.ID) -> TaskItem? {
        guard let index = position(of: id) else { return nil }
        let neighbour = neighbourID(of: index)
        // Before the removal, so a session on the doomed task cannot be ended
        // against it and log a rename on the way out.
        clearDrafts(for: id)
        blankCaptures[id] = nil
        let removed = tasks.remove(at: index)
        if pendingTitleFocusID == id { pendingTitleFocusID = nil }
        if draggingID == id { draggingID = nil }
        if sheetID == id { sheetID = nil }
        deselect(id, fallingTo: neighbour)
        scheduleSave()
        return removed
    }

    /// Puts back what a one-line field said before an open session emptied it.
    ///
    /// A field with nothing in it is a half-finished keystroke, not a state the
    /// board can be put back into: every other path refuses it, so leaving it in
    /// the snapshot a delete is about to capture would make ⌘Z the one way to
    /// get an untitled card onto the board. `discard` drops the sessions rather
    /// than ending them, and rightly — ending one against a task on its way out
    /// logs a rename nobody asked for — so the restore happens here instead, and
    /// *before* the step opens, which is where the snapshot is taken.
    private func restoreEmptiedFields(on id: TaskItem.ID) {
        for (key, session) in editSessions where key.task == id && key.field.isSingleLine {
            guard case .text(let previous) = session.before, !previous.isEmpty,
                  case .text(let current) = value(key.field, on: id, subtask: key.subtask),
                  Self.singleLine(current).trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }
            write(previous, field: key.field, on: id, subtask: key.subtask)
        }
    }

    /// What the selection falls to when the task it names leaves the board: the
    /// next card in the same column, else the one above it, else nothing.
    /// Staying in the column matters — jumping to another one reads as the
    /// board moving. Archived cards are skipped for the same reason they are
    /// not drawn: they are not on the board to fall onto.
    private func neighbourID(of index: Int) -> TaskItem.ID? {
        let columnID = tasks[index].columnID
        if let next = tasks[(index + 1)...].first(where: { $0.columnID == columnID && !$0.isArchived }) {
            return next.id
        }
        return tasks[..<index].last { $0.columnID == columnID && !$0.isArchived }?.id
    }

    // MARK: - The trash

    /// What the Trash shows: newest first, and never anything past its thirty
    /// days even if the app has been sitting open across the boundary.
    ///
    /// Filtered rather than swept, because reading a list must not write to the
    /// file. ``sweepTrash()`` is the write, and it happens at the two moments
    /// that are already about the trash.
    var trashedItems: [TrashedItem] {
        let now = Date.now
        let days = trashRetention.days
        return trash.filter { !$0.isExpired(at: now, days: days) }.sorted { $0.trashedAt > $1.trashedAt }
    }

    /// A count, not `trashedItems.count`: the sort there orders a list this
    /// throws away, and the badges ask on every render.
    var trashCount: Int {
        let now = Date.now
        let days = trashRetention.days
        return trash.count { !$0.isExpired(at: now, days: days) }
    }

    /// How long the Trash keeps things. Held on the store rather than read from
    /// `Preferences` at each use so a test can set it without reaching into
    /// global state that every other suite is reading at the same time — the
    /// same bargain `undoManager` and `sortOrder` make.
    var trashRetention: TrashRetention = Preferences.trashRetention

    /// Drops what the days have run out on.
    ///
    /// Deliberately **not** undoable and deliberately not an activity: it is the
    /// promise being kept rather than anything the user did, and a ⌘Z that could
    /// reach back into a bin the app has already emptied is a ⌘Z that undoes the
    /// passage of time. It still saves, so the file stops carrying what is no
    /// longer offered.
    func sweepTrash() {
        let now = Date.now
        let days = trashRetention.days
        let kept = trash.filter { !$0.isExpired(at: now, days: days) }
        guard kept.count != trash.count else { return }
        trash = kept
        scheduleSave()
    }

    /// Throws a task away — off the board, into the trash, out again in thirty
    /// days unless it is restored first.
    ///
    /// No confirmation, exactly as the delete it replaces had none: the trash
    /// *is* the safety net now, with ⌘Z still behind it, and a dialog in front
    /// of a reversible act is one the user learns to dismiss without reading.
    @discardableResult
    func trashTask(_ id: TaskItem.ID) -> TaskItem? {
        var removed: TaskItem?
        undoable(String(localized: "Trash Task", comment: "Undo action name for putting a task in the trash")) {
            removed = deleteTask(id)
            if let removed { keep(.task(removed)) }
        }
        if let removed { announce(Announcement(name: removed.displayTitle)) }
        return removed
    }

    /// The same for a selection, as one step. The order is the board's, so a
    /// trash of three cards lists them in the trash the way the board had them.
    func trashTasks(_ ids: Set<TaskItem.ID>) {
        let targets = ordered(ids)
        guard !targets.isEmpty else { return }
        let name = targets.count > 1
            ? String(localized: "Trash Tasks", comment: "Undo action name for trashing several tasks at once")
            : String(localized: "Trash Task", comment: "Undo action name for putting a task in the trash")
        var removed: [TaskItem] = []
        undoable(name) {
            for id in targets {
                restoreEmptiedFields(on: id)
                if let gone = discard(id) {
                    keep(.task(gone))
                    removed.append(gone)
                }
            }
        }
        // One card for the lot. A selection of four that announced per task
        // would draw four in a row, each replacing the last too quickly to
        // read, and the last one would name a card at random.
        guard let first = removed.first else { return }
        announce(removed.count == 1
                 ? Announcement(name: first.displayTitle)
                 : Announcement(taskCount: removed.count))
    }

    /// Throws a column away. Its cards are not thrown away with it — they move
    /// to the first column left, exactly as they always have, and each says so
    /// in its own history. What goes in the trash is the column.
    ///
    /// Refused for the same two reasons `deleteColumn` refuses, and nothing is
    /// kept when it is: a refusal means the board did not change.
    @discardableResult
    func trashColumn(_ id: BoardColumn.ID) -> ColumnRefusal? {
        guard let boardIndex = boardIndex(ofColumn: id),
              let position = boards[boardIndex].columns.firstIndex(where: { $0.id == id })
        else { return .unknownColumn }
        let boardID = boards[boardIndex].id
        let column = boards[boardIndex].columns[position]
        var refusal: ColumnRefusal?
        undoable(String(localized: "Trash Column", comment: "Undo action name for putting a column in the trash")) {
            refusal = deleteColumn(id)
            guard refusal == nil else { return }
            keep(.column(column, boardID: boardID, position: position))
        }
        // A refusal changed nothing, so there is nothing to say about it — the
        // caller shows the reason instead.
        if refusal == nil { announce(Announcement(name: column.name)) }
        return refusal
    }

    /// Throws a board away **with everything on it**: the board, its columns
    /// inside it, and every card that was on it — archived ones included — all
    /// in one trash entry, so one Restore brings back the board exactly as it
    /// was rather than an empty shell.
    ///
    /// The cards used to be left behind in the Inbox. See `deleteBoard` for why
    /// that was the wrong promise, and ``TrashedItem`` for what an entry
    /// written before this change means when it is restored today.
    @discardableResult
    func trashBoard(_ id: Board.ID) -> Board? {
        guard let position = boards.firstIndex(where: { $0.id == id }) else { return nil }
        var removed: Board?
        undoable(String(localized: "Trash Board", comment: "Undo action name for putting a board in the trash")) {
            guard let gone = deleteBoard(id) else { return }
            removed = gone.board
            keep(.board(gone.board, position: position, tasks: gone.tasks))
        }
        if let removed { announce(Announcement(name: removed.name)) }
        return removed
    }

    /// Raises the card. Outside the undo step on purpose: it is not part of what
    /// ⌘Z reverses, and a step that captured it would put the message back on
    /// screen on redo.
    private func announce(_ announcement: Announcement) {
        self.announcement = announcement
    }

    /// Files one thing in the trash. Called from inside an open step, which is
    /// what makes the removal and the keeping one ⌘Z.
    private func keep(_ contents: TrashedItem.Contents) {
        trash.append(TrashedItem(contents: contents))
        scheduleSave()
    }

    /// Puts a trashed thing back, and takes the row out of the trash.
    ///
    /// **What "back" means differs by kind, and none of it is a guess.** A card
    /// goes back to the placement it carried, unless the board or column it
    /// names has since gone, in which case it lands in the Inbox — the same
    /// answer `placed(_:on:)` gives every card whose column cannot be found, and
    /// better than refusing to give the user their card back over a column. A
    /// column and a board go back where they sat, clamped to a list that has
    /// changed length since. A **board brings its cards with it**, by the same
    /// placement rule and in the order it had them; a board trashed before the
    /// cards travelled with it carries none, and comes back alone because its
    /// cards were never taken — they are still in the Inbox where it left them.
    ///
    /// `nil` means it happened. A column whose board is gone is the one case
    /// that cannot be honoured, because there is nowhere to put it and inventing
    /// a board to hold it would be inventing a board.
    @discardableResult
    func restoreFromTrash(_ id: TrashedItem.ID) -> TrashRefusal? {
        guard let index = trash.firstIndex(where: { $0.id == id }) else { return .gone }
        let item = trash[index]
        var refusal: TrashRefusal?
        undoable(String(localized: "Restore from Trash", comment: "Undo action name for taking something back out of the trash")) {
            switch item.contents {
            case .task(let task):
                var restored = task
                if !isPlaceable(task.placement) { restored.placement = .inbox }
                restored.activity.insert(ActivityEntry(.restoredFromTrash), at: 0)
                tasks.append(restored)
                select(restored.id)
            case .column(let column, let boardID, let position):
                guard let boardIndex = boards.firstIndex(where: { $0.id == boardID }) else {
                    refusal = .boardIsGone
                    return
                }
                guard !boards[boardIndex].columns.contains(where: { $0.id == column.id }) else {
                    refusal = .alreadyThere
                    return
                }
                boards[boardIndex].columns.insert(
                    column, at: min(position, boards[boardIndex].columns.count)
                )
            case .board(let board, let position, let cards):
                guard !boards.contains(where: { $0.id == board.id }) else {
                    refusal = .alreadyThere
                    return
                }
                boards.insert(board, at: min(position, boards.count))
                // After the board is back, so `isPlaceable` is asked of a
                // sidebar that already holds the columns these cards name.
                //
                // A card whose id is somehow already on the board is skipped
                // rather than added twice: restoring must not be a way to end
                // up with one card wearing one code in two places. Nothing in
                // the app produces that — a trashed card is a removed card —
                // but a sync merge that adopted the same card from another
                // device could, and the cheap guard is better than the cure.
                for card in cards where !tasks.contains(where: { $0.id == card.id }) {
                    var restored = card
                    if !isPlaceable(restored.placement) { restored.placement = .inbox }
                    restored.activity.insert(ActivityEntry(.restoredFromTrash), at: 0)
                    tasks.append(restored)
                }
            }
            trash.remove(at: index)
            scheduleSave()
        }
        return refusal
    }

    /// Throws one trashed thing away for good, before its thirty days are up.
    /// This is the only delete in the app with a confirmation in front of it,
    /// and the only one that earns one: there is nothing behind it.
    func deleteFromTrash(_ id: TrashedItem.ID) {
        guard trash.contains(where: { $0.id == id }) else { return }
        undoable(String(localized: "Delete from Trash", comment: "Undo action name for permanently deleting one trashed item")) {
            trash.removeAll { $0.id == id }
            scheduleSave()
        }
    }

    /// The lot, in one step.
    func emptyTrash() {
        guard !trash.isEmpty else { return }
        undoable(String(localized: "Empty Trash", comment: "Undo action name for permanently deleting everything in the trash")) {
            trash.removeAll()
            scheduleSave()
        }
    }


    // MARK: - Archiving

    /// Files a task away. It leaves the board, every board count and every
    /// search, and stays in the file — the Archive saved view is where it lives
    /// afterwards, and each row there offers Restore.
    func archive(_ id: TaskItem.ID) {
        guard canArchive(id) else { return }
        undoable(String(localized: "Archive Task", comment: "Undo action name for archiving a task")) {
            performArchive(id, at: .now)
        }
    }

    /// Puts an archived task back where it was. It keeps its column, so it
    /// reappears in the one it was filed from rather than at the start of the
    /// workflow.
    func unarchive(_ id: TaskItem.ID) {
        guard let task = self[id], task.isArchived else { return }
        undoable(String(localized: "Restore Task", comment: "Undo action name for taking a task back out of the archive")) {
            update(id, log: .unarchived, stamping: false) { $0.archivedAt = nil }
        }
    }

    /// Clears the Done column in one step, which is the point of it: a user
    /// tidying up after a week's work presses ⌘Z once if they change their mind,
    /// not once per card.
    func archiveCompleted() {
        let completed = completedTasks.map(\.id)
        guard !completed.isEmpty else { return }
        // One instant for the lot: they were filed by one act, and the Archive
        // view's tie-break then keeps them in the order the board had them.
        let when = Date.now
        undoable(String(localized: "Archive Completed", comment: "Undo action name for archiving everything in the Done column")) {
            for id in completed { performArchive(id, at: when) }
        }
    }

    /// The Inbox's counterpart to `archiveCompleted()`: global and scoped only
    /// to Inbox cards that were completed in place.
    func archiveInboxCompleted() {
        let completed = inboxCompletedTasks.map(\.id)
        guard !completed.isEmpty else { return }
        let when = Date.now
        undoable(String(localized: "Archive Completed", comment: "Undo action name for archiving completed Inbox tasks")) {
            for id in completed { performArchive(id, at: when) }
        }
    }

    private func performArchive(_ id: TaskItem.ID, at when: Date) {
        update(id, log: .archived, stamping: false) { $0.archivedAt = when }
        detachSurfaces(from: id)
    }

    /// Moves the session's attention off a task that has just left the board.
    /// Unlike `discard` this keeps the task's drafts and open sessions: the task
    /// still exists, and restoring it should find them where they were.
    private func detachSurfaces(from id: TaskItem.ID) {
        if draggingID == id { draggingID = nil }
        if sheetID == id { sheetID = nil }
        if selection.contains(id), let index = position(of: id) {
            deselect(id, fallingTo: neighbourID(of: index))
        }
    }

    // MARK: - Bulk commands

    /// What multi-select is for: several cards moved, labelled, completed,
    /// filed or deleted **as one ⌘Z**, not as one per card.
    ///
    /// Each of these wraps the single-card mutation it is built from in one
    /// `undoable`, and the nested step collapses into it, so the bulk path
    /// cannot drift from the singular one — which is exactly what a
    /// hand-written second copy of each rule would eventually do. What they add
    /// is the step name, the order, and the guards that decide whether anything
    /// is going to happen at all.
    ///
    /// Two of them refuse cards the rest of the selection would carry along, so
    /// the number they will change is not the number selected. A menu titling
    /// itself "Complete 3 Tasks" and then filing one undo step called "Complete
    /// Task" has lied about what it was going to do, so the count it titles
    /// from and the list it acts on are the same call — `completeTargets` and
    /// `archiveTargets` below, which are also what the item's *enabled* state
    /// has to read: a selection of three already-completed cards is a selection
    /// with nothing to complete.
    func move(_ ids: Set<TaskItem.ID>, to columnID: BoardColumn.ID) {
        move(ids, to: placement(forColumn: columnID))
    }

    func move(_ ids: Set<TaskItem.ID>, to placement: TaskPlacement) {
        // Filed cards are dropped here as well as refused in `performMove`, so
        // the undo step is named for the number that will actually move.
        let targets = ordered(ids).filter { self[$0]?.isArchived == false }
        // This one goes straight to `performMove`, so the pairing check the
        // singular `move` makes on the way past is this guard's to make.
        guard !targets.isEmpty, isPlaceable(placement) else { return }
        undoable(Self.moveName(for: placement, count: targets.count)) {
            for id in targets { performMove(id, to: placement) }
        }
    }

    func complete(_ ids: Set<TaskItem.ID>) {
        let targets = completeTargets(ids)
        guard !targets.isEmpty else { return }
        let name = targets.count > 1
            ? String(localized: "Complete Tasks", comment: "Undo action name for completing several tasks at once")
            : String(localized: "Complete Task", comment: "Undo action name for completing a task")
        undoable(name) {
            for id in targets { complete(id) }
        }
    }

    /// Takes several cards back out of Done in one step. The mirror of
    /// `complete(_:)` above, and one undo step for the same reason: a menu item
    /// aimed at three cards is one act, however many cards it moves.
    func reopen(_ ids: Set<TaskItem.ID>) {
        let targets = reopenTargets(ids)
        guard !targets.isEmpty else { return }
        let name = targets.count > 1
            ? String(localized: "Reopen Tasks", comment: "Undo action name for reopening several tasks at once")
            : String(localized: "Reopen Task", comment: "Undo action name for reopening a task")
        undoable(name) {
            for id in targets { reopen(id) }
        }
    }

    /// And several out of the Archive, which the Archive view does a row at a
    /// time and the Task menu does to whatever it is aimed at.
    func unarchive(_ ids: Set<TaskItem.ID>) {
        let targets = unarchiveTargets(ids)
        guard !targets.isEmpty else { return }
        let name = targets.count > 1
            ? String(localized: "Restore Tasks", comment: "Undo action name for taking several tasks back out of the archive")
            : String(localized: "Restore Task", comment: "Undo action name for taking a task back out of the archive")
        undoable(name) {
            for id in targets { unarchive(id) }
        }
    }

    func archive(_ ids: Set<TaskItem.ID>) {
        let targets = archiveTargets(ids)
        guard !targets.isEmpty else { return }
        // One instant for the lot, for `archiveCompleted`'s reason: they were
        // filed by one act, and the Archive view's tie-break then keeps them in
        // the order the board had them.
        let when = Date.now
        let name = targets.count > 1
            ? String(localized: "Archive Tasks", comment: "Undo action name for archiving several tasks at once")
            : String(localized: "Archive Task", comment: "Undo action name for archiving a task")
        undoable(name) {
            for id in targets { performArchive(id, at: when) }
        }
    }

    func deleteTasks(_ ids: Set<TaskItem.ID>) {
        let targets = ordered(ids)
        guard !targets.isEmpty else { return }
        // Before the step opens, which is where its snapshot is taken — see
        // `restoreEmptiedFields`.
        for id in targets { restoreEmptiedFields(on: id) }
        let name = targets.count > 1
            ? String(localized: "Delete Tasks", comment: "Undo action name for deleting several tasks at once")
            : String(localized: "Delete Task", comment: "Undo action name for deleting a task")
        undoable(name) {
            for id in targets { discard(id) }
        }
    }

    /// Puts a label on every selected card, or takes it off all of them.
    ///
    /// A label the whole selection already carries comes off; anything else
    /// goes on. That is the answer that makes the second press undo the first —
    /// toggling each card independently would leave a mixed selection exactly
    /// as mixed as it started, only the other way round.
    func toggleLabel(_ key: String, on ids: Set<TaskItem.ID>) {
        let targets = ordered(ids)
        guard !targets.isEmpty else { return }
        let adding = !targets.allSatisfy { self[$0]?.labelKeys.contains(key) == true }
        let changing = targets.filter { (self[$0]?.labelKeys.contains(key) == true) != adding }
        guard !changing.isEmpty else { return }
        let name = adding
            ? String(localized: "Add Label", comment: "Undo action name for putting a label on a task")
            : String(localized: "Remove Label", comment: "Undo action name for taking a label off a task")
        undoable(name) {
            for id in changing { toggleLabel(key, on: id) }
        }
    }

    /// The singular refuses a value a card already has, so there is nothing to
    /// pre-filter here: a selection that is already all `.high` runs the loop,
    /// changes nothing, and registers nothing.
    func setPriority(_ priority: Priority, on ids: Set<TaskItem.ID>) {
        let targets = ordered(ids)
        guard !targets.isEmpty else { return }
        undoable(undoName(for: .priority)) {
            for id in targets { setPriority(priority, on: id) }
        }
    }

    /// No `scope`: a menu is not an editing session, so each change is logged
    /// and registered on the spot rather than coalesced into one a picker owns.
    /// Unfiltered for `setPriority`'s reason.
    func setDue(_ day: CalendarDay?, on ids: Set<TaskItem.ID>) {
        let targets = ordered(ids)
        guard !targets.isEmpty else { return }
        let name = day == nil
            ? String(localized: "Clear Due Date", comment: "Undo action name for removing a task's due date")
            : undoName(for: .due)
        undoable(name) {
            for id in targets { setDue(day, on: id) }
        }
    }

    /// Board order, because a set has none to offer and the order cards arrive
    /// in is the order they were in.
    private func ordered(_ ids: Set<TaskItem.ID>) -> [TaskItem.ID] {
        tasks.compactMap { ids.contains($0.id) ? $0.id : nil }
    }

    // MARK: What a bulk command will change

    /// Whether completing this card would do anything: `complete` asks the same
    /// question and acts on the answer.
    func canComplete(_ id: TaskItem.ID) -> Bool { donePlacement(for: id) != nil }

    /// Ticks a card off, or takes it back out of Done — the one act a tick
    /// makes, whichever tick it is.
    ///
    /// The board card's toggle, the detail panel's and the phone sheet's all
    /// mean exactly this, and each used to spell out the same `isDone ? reopen :
    /// complete` for itself. Three copies of a two-line rule is two chances for
    /// a surface to answer a different question from the one beside it.
    ///
    /// Singular on purpose, where the menu bar and the keyboard act on the whole
    /// selection: a tick is aimed at one card with a pointer or a finger, and
    /// the card it is aimed at is the one it is drawn on.
    func toggleCompletion(_ id: TaskItem.ID) {
        guard let task = self[id] else { return }
        if isDone(task) { reopen(id) } else { complete(id) }
    }

    /// Whether that tick would do anything, so a surface can draw it as unable
    /// rather than draw it live and swallow the press.
    ///
    /// The two directions do not have the same condition, which is the whole
    /// reason this is not just `canComplete`. Reopening needs only that the card
    /// is in Done; completing needs a Done column to complete *into*, which a
    /// board that has been hand-edited can be without. Neither works on an
    /// archived card — in the Archive the verb is Restore and only Restore.
    func canToggleCompletion(_ id: TaskItem.ID) -> Bool {
        guard let task = self[id], !task.isArchived else { return false }
        return canReopen(id) || canComplete(id)
    }

    /// Whether archiving this card would do anything. A card already in the
    /// Archive is the only one it would not.
    func canArchive(_ id: TaskItem.ID) -> Bool { self[id]?.isArchived == false }

    /// Whether taking this card back out of the Archive would do anything —
    /// `canArchive`'s mirror, and the question Task ▸ Restore Task asks before
    /// it draws itself live.
    func canUnarchive(_ id: TaskItem.ID) -> Bool { self[id]?.isArchived == true }

    /// The cards `complete(_:)` will move, in board order.
    func completeTargets(_ ids: Set<TaskItem.ID>) -> [TaskItem.ID] { ordered(ids).filter(canComplete) }

    /// The cards `archive(_:)` will file away, in board order.
    func archiveTargets(_ ids: Set<TaskItem.ID>) -> [TaskItem.ID] { ordered(ids).filter(canArchive) }

    /// The cards `reopen(_:)` will take back out of Done, in board order.
    func reopenTargets(_ ids: Set<TaskItem.ID>) -> [TaskItem.ID] { ordered(ids).filter(canReopen) }

    /// The cards `unarchive(_:)` will take back out of the Archive, in board
    /// order.
    func unarchiveTargets(_ ids: Set<TaskItem.ID>) -> [TaskItem.ID] { ordered(ids).filter(canUnarchive) }

    /// The same two counts over the current selection, which is what the menu
    /// bar has to hand: it names no ids, it just asks the store what the
    /// command in front of it is about to do.
    var completableCount: Int { completeTargets(selection).count }
    var archivableCount: Int { archiveTargets(selection).count }

    // MARK: - Creating

    /// Adds a task and focuses it: the macOS build selects it in the inspector,
    /// the iOS build opens its detail sheet.
    @discardableResult
    func addTask(
        to columnID: BoardColumn.ID,
        title: String,
        fromPhone: Bool = false,
        log kind: ActivityEntry.Kind = .created
    ) -> TaskItem.ID {
        addTask(to: placement(forColumn: columnID), title: title, fromPhone: fromPhone, log: kind)
    }

    /// The same, to a place rather than to a column — `.inbox` is how a quick
    /// capture makes a card without first having to pick a board.
    ///
    /// A placement naming a column that is not on the board beside it names
    /// nowhere, and the card is made in the Inbox instead — the same answer
    /// `placed` gives a decoded task whose column no board has. There is a card
    /// either way: the caller asked for one, and losing it would be worse than
    /// finding it somewhere other than where it was aimed.
    @discardableResult
    func addTask(
        to placement: TaskPlacement,
        title: String,
        fromPhone: Bool = false,
        log kind: ActivityEntry.Kind = .created,
        capture: CaptureParse? = nil
    ) -> TaskItem.ID {
        let id = mintTask(to: placement, title: title, log: kind, capture: capture)

        // Session state, and outside the step deliberately: moving the selection
        // ends the sessions the surface left on the task it came from, and those
        // must file their own text rather than collapsing into this step.
        pendingTitleFocusID = title.isEmpty ? id : nil
        if title.isEmpty { rememberCapture(id) }
        draft = ""
        addingPlacement = nil
        if fromPhone {
            sheetID = id
        } else {
            selectedID = id
        }
        return id
    }

    /// Quick capture into the Inbox for a surface that carries the card's editor
    /// itself — the source list's capture button, which opens the whole
    /// inspector in a popover rather than a one-line composer.
    ///
    /// The Inbox because capture must not begin with a decision: a card is in it
    /// by being on no board at all, and the popover's own board menu is there
    /// for filing it the moment the user knows where it goes.
    ///
    /// **The selection does not move, and that is the whole difference from
    /// `addTask`.** The popover *is* this card's editor. Selecting the card as
    /// well would open a second editor on it in the detail panel behind, and two
    /// of them on one task share a `.desk` editing session and race for
    /// `pendingTitleFocusID` — a race the panel wins, because it is already on
    /// screen when this runs. The popover would then come up with its title
    /// field unfocused, and the typing it was opened for would go nowhere.
    @discardableResult
    func captureToInbox() -> TaskItem.ID {
        let id = mintTask(to: .inbox, title: "", log: .captured)
        pendingTitleFocusID = id
        rememberCapture(id)
        return id
    }

    /// Takes everything the share extension has left in the App Group and makes
    /// Inbox cards of it. Returns how many arrived.
    ///
    /// Called as the app comes forward and once at launch — see
    /// `ScenePhaseWork`. The extension cannot write to the board itself (see
    /// ``CaptureInbox``), so this is the only path a shared item takes onto it,
    /// and it has to be safe to call at any moment, including when there is
    /// nothing waiting.
    ///
    /// **One step for the lot.** N shares cost one ⌘Z, the way a paste of N
    /// lines does — `addTasks` makes the same bargain for the same reason.
    ///
    /// **A file is deleted only once its card exists.** The order matters and
    /// it is the order below: mint first, then remove. A crash in between costs
    /// a card that arrives twice, which the user can delete; the other order
    /// costs one that never arrives at all, which they cannot get back and
    /// would have no way of even knowing about.
    @discardableResult
    func adoptPendingCaptures() -> Int {
        let (captures, unreadable) = CaptureInbox.pending()
        // Set aside rather than deleted or retried — `CaptureInbox.reject`.
        for file in unreadable { CaptureInbox.reject(file) }
        guard !captures.isEmpty else { return 0 }

        var made: [(PendingCapture.ID, TaskItem.ID)] = []
        undoable(String(localized: "Add Shared Tasks",
                        comment: "Undo action name for taking shared items into the Inbox")) {
            for capture in captures {
                // `.captured` rather than `.created`: this arrived through the
                // share sheet, which is the same errand the menu bar's quick add
                // and the widget's `+` are on.
                let id = mintTask(to: .inbox, title: capture.title, log: .captured)
                if !capture.note.isEmpty {
                    setText(capture.note, field: .note, on: id)
                }
                made.append((capture.id, id))
            }
        }
        for (captureID, taskID) in made where self[taskID] != nil {
            CaptureInbox.remove(captureID)
        }
        announce(.captured)
        return made.count
    }

    /// Files a card a `+` has just made empty, exactly as it was made, so that
    /// closing its editor can tell whether anything was filled in. See
    /// ``blankCaptures``.
    private func rememberCapture(_ id: TaskItem.ID) {
        blankCaptures[id] = self[id]
    }

    /// Adds several tasks as one step — what ⌘V of a list of lines is for, and
    /// the whole of the difference between it and a loop of `addTask`: N lines
    /// cost one ⌘Z rather than N.
    ///
    /// Blank lines are dropped rather than becoming untitled cards: an untitled
    /// card is quick capture's, and it comes with a title field waiting to be
    /// focused, which is not something N of them can each have.
    ///
    /// The selection lands on everything made, so a command aimed at the paste
    /// finds it — and it moves once, after the step closes, for the reason
    /// `addTask` gives above.
    @discardableResult
    func addTasks(to columnID: BoardColumn.ID, titles: [String]) -> [TaskItem.ID] {
        addTasks(to: placement(forColumn: columnID), titles: titles)
    }

    @discardableResult
    func addTasks(to placement: TaskPlacement, titles: [String]) -> [TaskItem.ID] {
        let titles = titles.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !titles.isEmpty else { return [] }
        var made: [TaskItem.ID] = []
        let name = titles.count > 1
            ? String(localized: "New Tasks", comment: "Undo action name for adding several tasks at once")
            : String(localized: "New Task", comment: "Undo action name for adding a task")
        undoable(name) {
            for title in titles { made.append(mintTask(to: placement, title: title, log: .created)) }
        }
        pendingTitleFocusID = nil
        draft = ""
        addingPlacement = nil
        selectAll(made)
        return made
    }

    /// The card itself: minted, filed, and registered as its own step unless a
    /// bulk add has one open. Separated from `addTask` so `addTasks` can make
    /// several inside one step and still move the session state exactly once,
    /// after it closes.
    /// What a new card's due date starts as. On the store for the reason
    /// `trashRetention` is: a preference read from a global at each use is one
    /// a parallel test cannot set without changing what every other suite sees.
    var defaultDueDate: DefaultDueDate = Preferences.defaultDueDate

    /// `today` is a parameter rather than a read of the clock so a test can
    /// mint a card on whatever day it likes — the same bargain `DayClock` makes
    /// everywhere else. It is only consulted when ``DefaultDueDate`` is set to
    /// something, which it is not by default.
    ///
    /// **A capture's readings arrive here rather than being set afterwards.**
    /// A card made and then given a due date, a priority and two labels through
    /// the ordinary mutators is one card and four undo steps — ⌘Z four times to
    /// take back one ⏎. Minting it whole makes it one step, and it also settles
    /// what the activity feed says: a card born with a due date logs `.created`
    /// and nothing else, exactly as one born with ``defaultDueDate`` already
    /// did. The feed is for things that happened *to* a card, and none of this
    /// happened to it — it is how the card arrived.
    private func mintTask(
        to placement: TaskPlacement, title: String, log kind: ActivityEntry.Kind,
        capture: CaptureParse? = nil,
        today: CalendarDay = CalendarDay(.now)
    ) -> TaskItem.ID {
        let startsDue = defaultDueDate.day(from: today)
        let placement = isPlaceable(placement) ? placement : .inbox
        var task = TaskItem(
            code: BoardSnapshot.code(prefix: codePrefix(for: placement), forSerial: nextSerial),
            title: title,
            due: capture?.due ?? startsDue,
            priority: capture?.priority ?? .default,
            activity: [ActivityEntry(kind)]
        )
        task.placement = placement
        undoable(String(localized: "New Task", comment: "Undo action name for adding a task")) {
            // Inside the step, because a `#roadmap` nobody has used before
            // mints its definition here: one ⏎ costs one ⌘Z, and it takes the
            // label back with the card rather than leaving a colour in the
            // vocabulary for a card that no longer exists.
            if let capture { task.labelKeys = landedLabelKeys(for: capture) }
            nextSerial += 1
            tasks.append(task)
            scheduleSave()
        }
        return task.id
    }

    /// The keys a capture's labels actually land on, minting the definitions
    /// the board does not have yet.
    ///
    /// **Read against the board a second time**, because the parse was made
    /// against the labels as they were: a draft can outlive the label it named
    /// if the manager is open in another window while somebody types. A key the
    /// board has answers for itself; a name the parse marked new is created
    /// here; and a key that is neither — the label was deleted mid-draft — is
    /// dropped, as it always was.
    ///
    /// The key comes back from ``createLabel(named:)`` rather than being
    /// assumed to be the parse's: the name is trimmed and capped on the way in,
    /// so a very long `#…` slugs to a shorter key than the one that was read,
    /// and taking the parse's would leave the card wearing a key no definition
    /// answers to.
    ///
    /// Called from inside the mint's own step so the definition and the card
    /// are one ⌘Z — a nested `undoable` runs its body bare.
    private func landedLabelKeys(for capture: CaptureParse) -> [String] {
        let names = Dictionary(capture.newLabels.map { ($0.key, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        var landed: [String] = []
        for key in capture.labelKeys {
            let resolved = label(forKey: key) != nil ? key : names[key].flatMap { createLabel(named: $0) }
            guard let resolved, !landed.contains(resolved) else { continue }
            landed.append(resolved)
        }
        return landed
    }

    /// The prefix a code is minted under: the destination board's, or the
    /// Inbox's constant one.
    ///
    /// Asked exactly once, when the task is made. A code never changes
    /// afterwards — it is a label a person may have pasted into a commit
    /// message — so filing an IN-141 onto a board leaves it called IN-141.
    private func codePrefix(for placement: TaskPlacement) -> String {
        guard let board = board(id: placement.boardID) else { return Board.inboxCodePrefix }
        return board.codePrefix
    }

    /// Commits the inline "Task title, then ⏎" composer.
    ///
    /// Returns the card it made, so the surface that drew the field can bring
    /// it into view: a card is appended, and the field is not always at the end
    /// of the column it is adding to — see ``BoardColumnView`` — so the card
    /// can land off the bottom of a column the user is looking at the top of.
    /// `nil` when there was nothing to commit.
    @discardableResult
    func commitDraft() -> TaskItem.ID? {
        // Read once, and the same reading the composer has been showing: asking
        // twice would let a draft typed either side of midnight commit a day the
        // preview never named.
        let capture = draftParse
        guard let placement = addingPlacement, !capture.title.isEmpty else { return nil }
        let made = addTask(to: placement, title: capture.title, capture: capture)
        // `addTask` has already emptied the draft; the refusals go with it,
        // because they were about that line and not about the next one.
        draftRejections = []
        // **The iPad opens its editor on the card that was just made**, which
        // `addTask` has already selected. The other two platforms do not, and
        // the difference is real rather than a preference:
        //
        // - **The iPad's editor is a panel the *app* puts away.** Three panels
        //   compete for one window there and `PadRootView` closes whichever is
        //   furthest from what was last asked for, so a card can perfectly well
        //   be made into an editor that is not on screen — selected, and
        //   nowhere to be seen. Opening it is what makes the creation finish
        //   somewhere the user can see it and fill in the rest of the card.
        // - **The desk's is a panel the *user* puts away.** Its window holds
        //   all three columns at nearly any size, so an inspector that is shut
        //   is one somebody shut on purpose, and re-opening it on every card
        //   made would be overruling that a dozen times an afternoon.
        // - **The phone has its own answer already**: a card made from the `+`
        //   over the tab bar opens in a sheet, and one made from a column's
        //   composer deliberately does not — you are filling in a list, and a
        //   full-screen sheet between every two cards would bury it.
        if Self.isPad { isInspectorOpen = true }
        return made
    }

    func cancelDraft() {
        addingPlacement = nil
        draft = ""
        draftRejections = []
    }

    func beginAdding(in columnID: BoardColumn.ID) {
        beginAdding(in: placement(forColumn: columnID))
    }

    func beginAdding(in placement: TaskPlacement) {
        addingPlacement = placement
        draft = ""
        draftRejections = []
    }

    /// Where ⌘N and the toolbar's New Task button open the composer.
    ///
    /// The composer is drawn by whichever surface owns the place it is adding
    /// to, so this puts that surface on screen first — otherwise it focuses a
    /// text field nobody can see and the command reads as broken. It adds to
    /// the board's landing column, falling back to the Inbox — and opening the
    /// panel that draws it — when there is no board left to land on.
    ///
    /// **The Inbox being out does not change where it lands**, on any of the
    /// three platforms: beside the board on the desk and the iPad, over it on
    /// the phone, the board is still what the user is working on. Every surface
    /// that draws the Inbox draws an add row of its own, and that row is how you
    /// capture into it. The phone's Inbox tab used to be the exception, and it
    /// was one because the tab stood *instead* of the board rather than with it.
    func beginAddingWhereVisible() {
        guard let column = activeBoard?.landingColumn else { return beginCapturingInInbox() }
        selectSurface(.board)
        beginAdding(in: column.id)
    }

    /// The ever-present "+": a capture, which lands in the Inbox whatever is on
    /// screen.
    ///
    /// **Not where you are, deliberately.** The `+` at the foot of a column adds
    /// *to that column of that board* — the destination is decided and only the
    /// title is missing. This button is the other moment: the thing is worth
    /// writing down and nothing else about it is settled, so it goes to the
    /// Inbox, which is where a card is by being nowhere. The desk and the phone
    /// have said this in their own controls for as long as they have had them —
    /// `captureToInbox()` behind the source list's `+`, `quickCapture()` behind
    /// the one floating over the tab bar — and this is the iPad's half of the
    /// same sentence.
    ///
    /// The panel comes out because it is what draws the composer: focusing a
    /// field on a surface that is not up reads as a button that did nothing.
    func beginCapturingInInbox() {
        showInbox()
        beginAdding(in: .inbox)
    }

    // MARK: - Editing

    /// Mutates a task in place, optionally recording an activity entry. The feed
    /// reads newest first, so entries go on the front.
    ///
    /// `stamping: false` is for the changes that file a task rather than work on
    /// it. `updatedAt` is what the "This week" meter is measured on, so a filing
    /// that stamped it would have "Archive completed" inflate the very number
    /// standing beside the button — the drift the meter was redefined to escape,
    /// arrived at by another route. Everything else still happens: the search
    /// memo keys on `markChanged`'s counter, and a task holding a stale haystack
    /// would go on matching text the board no longer shows.
    private func update(
        _ id: TaskItem.ID,
        log kind: ActivityEntry.Kind? = nil,
        stamping: Bool = true,
        _ mutate: (inout TaskItem) -> Void
    ) {
        guard let index = position(of: id) else { return }
        mutate(&tasks[index])
        if stamping { touch(index) } else { markChanged(tasks[index].id) }
        if let kind {
            tasks[index].activity.insert(ActivityEntry(kind), at: 0)
        }
        scheduleSave()
    }

    /// Marks a task changed: 3.3's timestamp and the monotonic stamp the search
    /// memo keys on, together, so no mutation can bump one and forget the other.
    /// Filing wants the second without the first and reaches `markChanged`
    /// directly; nothing else may.
    private func touch(_ index: Int) {
        tasks[index].updatedAt = .now
        markChanged(tasks[index].id)
    }

    private func markChanged(_ id: TaskItem.ID) {
        revisionCounter &+= 1
        taskRevisions[id] = revisionCounter
    }

    @ObservationIgnored private var taskRevisions: [TaskItem.ID: Int] = [:]
    @ObservationIgnored private var revisionCounter: Int = 0

    /// The text fields only. `due` and `priority` are edited as sessions too,
    /// but through their own pickers.
    func text(_ field: TaskField, on id: TaskItem.ID, subtask: SubTask.ID? = nil) -> String {
        guard case .text(let text) = value(field, on: id, subtask: subtask) else { return "" }
        return text
    }

    /// Writes as the user types, so it neither trims nor logs — `endEditing`
    /// does both. A title is folded to one line here rather than at the end
    /// because a newline pasted into it would otherwise be on screen, in the
    /// card layout, until the field lost focus.
    func setText(_ value: String, field: TaskField, on id: TaskItem.ID) {
        update(id) { task in
            switch field {
            case .title: task.title = Self.singleLine(value)
            case .note: task.note = value
            case .due, .priority, .subtask: break
            }
        }
    }

    /// Records the value a field held when the session began, and the board it
    /// began on — one session of typing is one activity entry and one ⌘Z. A
    /// session this surface already has open is left as it is: its before-value
    /// is the one the eventual entry has to be measured against.
    func beginEditing(_ field: TaskField, on id: TaskItem.ID, scope: DetailScope, subtask: SubTask.ID? = nil) {
        let key = EditKey(scope: scope, task: id, field: field, subtask: subtask)
        guard editSessions[key] == nil else { return }
        sessionsOpened += 1
        editSessions[key] = Session(before: value(field, on: id, subtask: subtask),
                                    undoBefore: mutation, openedAt: sessionsOpened)
    }

    /// Ends an editing session: a one-line field is tidied, one emptied to
    /// nothing is restored, and a value that actually changed gets a single
    /// activity entry and a single undo step naming what it finished as — one
    /// entry for a title typed a letter at a time, and one for three dates tried
    /// in the calendar before settling on the fourth.
    func endEditing(_ field: TaskField, on id: TaskItem.ID, scope: DetailScope, subtask: SubTask.ID? = nil) {
        let key = EditKey(scope: scope, task: id, field: field, subtask: subtask)
        guard let session = editSessions.removeValue(forKey: key) else { return }

        if field.isSingleLine, case .text(let raw) = value(field, on: id, subtask: subtask) {
            // Commit is where a pasted paragraph becomes a line: the ends are
            // trimmed and any run of whitespace inside collapses to one space.
            let tidy = Self.singleLine(raw).trimmingCharacters(in: .whitespaces)
            if tidy.isEmpty {
                // A row with no text is unreachable, so put back what it said.
                if case .text(let previous) = session.before, !previous.isEmpty {
                    write(previous, field: field, on: id, subtask: subtask)
                }
                return
            }
            if tidy != raw { write(tidy, field: field, on: id, subtask: subtask) }
        }

        let after = value(field, on: id, subtask: subtask)

        // A picker session registered each change as it happened, so ending it
        // is only ever about that entry: keep it, or take it back when the value
        // wandered and came home to where it started. Taking it back is itself a
        // board change, so it registers like any other.
        if let entryID = session.entryID {
            if after == session.before {
                undoable(undoName(for: field)) {
                    update(id) { $0.activity.removeAll { $0.id == entryID } }
                }
            }
            return
        }
        guard after != session.before else { return }

        switch (field, session.before) {
        case (.title, .text(let previous)):
            // Naming a task that was created untitled is what "Created" already says.
            if !previous.isEmpty { update(id, log: .renamed) { _ in } }
        case (.note, .text(let previous)):
            update(id, log: previous.isEmpty ? .descriptionAdded : .descriptionUpdated) { _ in }
        case (.subtask, .text):
            update(id, log: .subtaskRenamed) { _ in }
        default:
            // `due` and `priority` are recorded by the change itself.
            break
        }
        registerUndo(from: session.undoBefore, name: undoName(for: field), openedBefore: session.openedAt)
    }

    /// Sends a value the session corrected back to whichever field it was on.
    private func write(_ text: String, field: TaskField, on id: TaskItem.ID, subtask: SubTask.ID?) {
        if field == .subtask, let subtask {
            updateSubtask(subtask, text: text, on: id)
        } else {
            setText(text, field: field, on: id)
        }
    }

    /// Whether *this surface* has a session open on this field. Scoped on
    /// purpose: an inspector session must not silence the sheet's change to the
    /// same task, which is the whole reason the sessions are keyed by surface.
    func isEditing(_ field: TaskField, on id: TaskItem.ID, scope: DetailScope, subtask: SubTask.ID? = nil) -> Bool {
        editSessions[EditKey(scope: scope, task: id, field: field, subtask: subtask)] != nil
    }

    /// Ends every session a surface left behind when it moved to another task.
    /// Ending rather than dropping: an abandoned title emptied to nothing still
    /// has to be put back, and an abandoned picker entry still has to be
    /// measured against where the value started.
    private func endSessions(in scope: DetailScope, awayFrom id: TaskItem.ID?) {
        for key in Array(editSessions.keys) where key.scope == scope && key.task != id {
            endEditing(key.field, on: key.task, scope: key.scope, subtask: key.subtask)
        }
    }

    /// Straight off the live board through `self[id]` rather than through a
    /// captured `BoardMutation`: this is the getter behind every text binding,
    /// which SwiftUI reads more than once per render pass, and the capture was
    /// seven array retains plus a scan of every task — per read.
    private func value(_ field: TaskField, on id: TaskItem.ID, subtask: SubTask.ID? = nil) -> FieldValue {
        Self.value(field, of: self[id], subtask: subtask)
    }

    /// The same read against a captured board rather than the live one, so an
    /// undo can ask what a step it is about to restore says about a field.
    private func value(
        _ field: TaskField, on id: TaskItem.ID, subtask: SubTask.ID?, in state: BoardMutation
    ) -> FieldValue {
        Self.value(field, of: state.tasks.first { $0.id == id }, subtask: subtask)
    }

    private static func value(_ field: TaskField, of task: TaskItem?, subtask: SubTask.ID?) -> FieldValue {
        switch field {
        case .title: return .text(task?.title ?? "")
        case .note: return .text(task?.note ?? "")
        case .due: return .day(task?.due)
        case .priority: return .priority(task?.priority ?? .default)
        case .subtask: return .text(task?.subtasks.first { $0.id == subtask }?.text ?? "")
        }
    }

    /// `scope` is the surface the change came from, so its own open session can
    /// be found. `nil` means no session — log it and be done.
    func setPriority(_ priority: Priority, on id: TaskItem.ID, scope: DetailScope? = nil) {
        guard let current = self[id], current.priority != priority else { return }
        record(.prioritySet(priority), for: .priority, on: id, scope: scope) { $0.priority = priority }
    }

    /// Sets or clears the due date. A due date is a calendar day, so there is
    /// nothing to normalise: the day the user picked is the day stored.
    func setDue(_ day: CalendarDay?, on id: TaskItem.ID, scope: DetailScope? = nil) {
        guard let current = self[id], current.due != day else { return }
        record(day.map { .dueSet($0) } ?? .dueCleared, for: .due, on: id, scope: scope) { $0.due = day }
    }

    /// Applies a picker change and records it.
    ///
    /// With no session open on that surface the entry is logged at once. With
    /// one open the change is *still* recorded — the session's own entry is
    /// rewritten in place, so four dates tried leave one line, and a surface
    /// that walks away without ending its session leaves the change on the
    /// record rather than erasing it.
    ///
    /// Either way the change is its own undo step. What a picker session
    /// coalesces is the activity entry; deferring the *step* to `endEditing`
    /// left the change sitting on the board unregistered, where a ⌘Z would
    /// reverse it together with whatever the user did before opening the picker.
    private func record(
        _ kind: ActivityEntry.Kind,
        for field: TaskField,
        on id: TaskItem.ID,
        scope: DetailScope?,
        _ mutate: (inout TaskItem) -> Void
    ) {
        let action: String = if case .dueCleared = kind {
            String(localized: "Clear Due Date", comment: "Undo action name for removing a task's due date")
        } else {
            undoName(for: field)
        }
        guard let key = scope.map({ EditKey(scope: $0, task: id, field: field, subtask: nil) }),
              var session = editSessions[key]
        else {
            undoable(action) { update(id, log: kind, mutate) }
            return
        }
        let entryID = session.entryID ?? ActivityEntry.ID()
        session.entryID = entryID
        editSessions[key] = session
        undoable(action) {
            update(id) { task in
                mutate(&task)
                if let index = task.activity.firstIndex(where: { $0.id == entryID }) {
                    // The entry now records a change that just happened, so it
                    // goes back to the front. Rewriting it where it sat would
                    // leave the newest stamp buried under whatever landed
                    // mid-session.
                    var entry = task.activity.remove(at: index)
                    entry.kind = kind
                    entry.when = .now
                    task.activity.insert(entry, at: 0)
                } else {
                    task.activity.insert(ActivityEntry(id: entryID, kind), at: 0)
                }
            }
        }
    }

    // MARK: - Sub-tasks

    @discardableResult
    func addSubtask(to taskID: TaskItem.ID, text: String) -> Bool {
        let trimmed = Self.singleLine(text).trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, tasks.contains(where: { $0.id == taskID }) else { return false }
        undoable(String(localized: "Add Sub-task", comment: "Undo action name for adding a sub-task")) {
            update(taskID, log: .subtaskAdded) { $0.subtasks.append(SubTask(text: trimmed)) }
        }
        return true
    }

    /// Adds the sub-task one surface has typed and clears **only** that
    /// surface's draft for that task — the other surface may be mid-sentence.
    func commitSubtaskDraft(for scope: DetailScope, task taskID: TaskItem.ID) {
        let key = DraftKey(scope: scope, task: taskID)
        guard addSubtask(to: taskID, text: subtaskDrafts[key] ?? "") else { return }
        subtaskDrafts[key] = ""
    }

    func toggleSubtask(_ subtaskID: SubTask.ID, on taskID: TaskItem.ID) {
        guard let taskIndex = position(of: taskID),
              let subIndex = tasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID })
        else { return }
        let wasDone = tasks[taskIndex].subtasks[subIndex].done
        let name = wasDone
            ? String(localized: "Reopen Sub-task", comment: "Undo action name for un-ticking a sub-task")
            : String(localized: "Complete Sub-task", comment: "Undo action name for ticking a sub-task")
        undoable(name) {
            tasks[taskIndex].subtasks[subIndex].done.toggle()
            touch(taskIndex)
            scheduleSave()
            // The sub-task's chime, on the one edge that means a step was
            // finished — `performMove`'s reasoning, one size down. Undo, redo
            // and a sync merge put `done` back without coming through here, and
            // a checklist restored is not a checklist being ticked.
            if !wasDone { CompletionFeedback.shared.subtaskCompleted() }
        }
    }

    /// The text of one sub-task, for a row that edits it in place.
    func subtaskText(_ subtaskID: SubTask.ID, on taskID: TaskItem.ID) -> String {
        self[taskID]?.subtasks.first { $0.id == subtaskID }?.text ?? ""
    }

    /// Rewrites a sub-task's text. Called as the user types, like `setText`, so
    /// it neither trims nor logs: `endEditing(.subtask, …)` does both.
    func updateSubtask(_ subtaskID: SubTask.ID, text: String, on taskID: TaskItem.ID) {
        let tidy = Self.singleLine(text)
        guard let taskIndex = position(of: taskID),
              let subIndex = tasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID }),
              tasks[taskIndex].subtasks[subIndex].text != tidy
        else { return }
        tasks[taskIndex].subtasks[subIndex].text = tidy
        touch(taskIndex)
        scheduleSave()
    }

    func deleteSubtask(_ subtaskID: SubTask.ID, from taskID: TaskItem.ID) {
        guard let task = self[taskID], task.subtasks.contains(where: { $0.id == subtaskID }) else { return }
        undoable(String(localized: "Delete Sub-task", comment: "Undo action name for deleting a sub-task")) {
            // A session still open on the row would otherwise be ended against a
            // sub-task that is no longer there, and log a rename on its way out.
            editSessions = editSessions.filter { $0.key.subtask != subtaskID }
            update(taskID, log: .subtaskRemoved) { $0.subtasks.removeAll { $0.id == subtaskID } }
        }
    }

    /// Reordering logs nothing: the order is on screen, and a feed of
    /// "sub-task moved" would bury the changes that matter.
    func moveSubtask(fromOffsets: IndexSet, toOffset: Int, on taskID: TaskItem.ID) {
        guard let index = position(of: taskID) else { return }
        var reordered = tasks[index].subtasks
        reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        guard reordered != tasks[index].subtasks else { return }
        undoable(String(localized: "Reorder Sub-tasks", comment: "Undo action name for reordering sub-tasks")) {
            tasks[index].subtasks = reordered
            touch(index)
            scheduleSave()
        }
    }

    /// Puts the dragged sub-task in the gap the caret names.
    ///
    /// **This replaced `drop(_:before:)`**, and for the reason ``dropColumn(_:at:)``
    /// replaced the columns' `dropColumn(_:onto:)` and ``drop(_:at:)`` replaced the
    /// cards' `move(_:onto:)`: a drop that names a *row* can only be resolved by
    /// the direction the drag came from, so aiming at the same row from above and
    /// from below meant two different gaps, and the mark drawn on the row's top
    /// edge was a lie every time the drag was travelling downwards. A caret names
    /// the gap, so this inserts into it.
    ///
    /// The task is passed rather than read off the payload, and then the two are
    /// checked to agree: a row dragged out of the inspector must not land in a
    /// sheet showing a *different* card, where its index names a place in a list
    /// it is not in. Refused against itself and against the two gaps either side
    /// of itself, where there is nothing to do. `false` says the drop was not
    /// taken, which is what a drop handler owes its caller.
    @discardableResult
    func dropSubtask(_ payload: SubtaskTransfer, on taskID: TaskItem.ID, at caret: SubtaskCaret) -> Bool {
        guard payload.taskID == taskID, payload.subtaskID != caret.row,
              let rows = self[taskID]?.subtasks,
              let from = rows.firstIndex(where: { $0.id == payload.subtaskID }),
              let anchor = rows.firstIndex(where: { $0.id == caret.row })
        else { return false }
        let offset: Int
        switch caret {
        case .above:
            // Already sitting in that gap: the row under the caret is the one
            // immediately after the dragged sub-task.
            guard anchor != from + 1 else { return false }
            offset = anchor
        case .below:
            guard anchor != from - 1 else { return false }
            offset = anchor + 1
        }
        moveSubtask(fromOffsets: IndexSet(integer: from), toOffset: offset, on: taskID)
        return true
    }

    /// Which row of the checklist **as it is drawn** a dragged sub-task would
    /// become, or `nil` for no stand-in — ``dropPreview(in:)`` for the
    /// checklist, and the same answer in the simpler form this list needs: the
    /// row being carried and the caret are already the view's own state, so an
    /// index is the whole of what is left to work out.
    ///
    /// **As it is drawn**, which is why this is not the offset `dropSubtask`
    /// computes: the row in the air is still one of the rows, dimmed, until the
    /// drop lands — so a stand-in going in after row *n* is index *n + 1* in a
    /// list that still holds the original.
    ///
    /// **It refuses exactly what the drop refuses**, and it has to. A row-shaped
    /// hole opening beside the very row that would fill it promises a move that
    /// `dropSubtask` then declines as a no-op that would cost a ⌘Z. One rule,
    /// asked twice — which is also what lets the checklist draw the stand-in
    /// *instead of* an insertion line rather than as well as one, there being
    /// nothing left for a line to say that the gap does not.
    func subtaskDropIndex(_ subtaskID: SubTask.ID, on taskID: TaskItem.ID, at caret: SubtaskCaret) -> Int? {
        guard subtaskID != caret.row,
              let rows = self[taskID]?.subtasks,
              let from = rows.firstIndex(where: { $0.id == subtaskID }),
              let anchor = rows.firstIndex(where: { $0.id == caret.row })
        else { return nil }
        switch caret {
        case .above:
            guard anchor != from + 1 else { return nil }
            return anchor
        case .below:
            guard anchor != from - 1 else { return nil }
            return anchor + 1
        }
    }

    func subtaskDraft(for scope: DetailScope, task: TaskItem.ID) -> String {
        subtaskDrafts[DraftKey(scope: scope, task: task)] ?? ""
    }

    func setSubtaskDraft(_ value: String, for scope: DetailScope, task: TaskItem.ID) {
        subtaskDrafts[DraftKey(scope: scope, task: task)] = value
    }

    // MARK: - Labels

    func toggleLabel(_ key: String, on taskID: TaskItem.ID) {
        guard let index = position(of: taskID) else { return }
        let name = label(forKey: key)?.name ?? key
        let action = tasks[index].labelKeys.contains(key)
            ? String(localized: "Remove Label", comment: "Undo action name for taking a label off a task")
            : String(localized: "Add Label", comment: "Undo action name for putting a label on a task")
        undoable(action) {
            if let existing = tasks[index].labelKeys.firstIndex(of: key) {
                tasks[index].labelKeys.remove(at: existing)
                tasks[index].activity.insert(ActivityEntry(.labelRemoved(key: key, name: name)), at: 0)
            } else {
                tasks[index].labelKeys.append(key)
                tasks[index].activity.insert(ActivityEntry(.labelAdded(key: key, name: name)), at: 0)
            }
            touch(index)
            scheduleSave()
        }
    }

    /// Creates a label from the picker's text field and applies it to the task.
    /// A name that slugs to an existing key just applies that label.
    /// `color` is the compose dialog's choice; `nil` — every other caller —
    /// takes the next colour off the rotation, see ``nextLabelColor``. Ignored
    /// for a name that already names a label: recolouring is `recolorLabel`'s,
    /// and "adding" an existing label must not repaint it as a side effect.
    func createLabel(named name: String, color: SwatchColor? = nil, on taskID: TaskItem.ID) {
        let trimmed = Self.labelName(name)
        guard !trimmed.isEmpty else { return }
        let key = LabelDef.key(from: trimmed)
        let exists = label(forKey: key) != nil
        let action = exists
            ? String(localized: "Add Label", comment: "Undo action name for putting a label on a task")
            : String(localized: "Create Label", comment: "Undo action name for making a new label")

        undoable(action) {
            // Folds into this step — a nested `undoable` runs its body bare —
            // so the definition and its application stay one ⌘Z.
            createLabel(named: name, color: color)
            if let index = position(of: taskID), !tasks[index].labelKeys.contains(key) {
                tasks[index].labelKeys.append(key)
                tasks[index].activity.insert(ActivityEntry(.labelAdded(key: key, name: trimmed)), at: 0)
                touch(index)
            }
            scheduleSave()
        }
    }

    /// The definition alone, applied to nothing — the label manager's create.
    ///
    /// A name that slugs to an existing key makes nothing and returns that
    /// key: the row it names is already on the list the person is looking at.
    /// The returned key is `nil` only for a name with nothing in it.
    @discardableResult
    func createLabel(named name: String, color: SwatchColor? = nil) -> String? {
        let trimmed = Self.labelName(name)
        guard !trimmed.isEmpty else { return nil }
        let key = LabelDef.key(from: trimmed)
        guard label(forKey: key) == nil else { return key }
        undoable(String(localized: "Create Label", comment: "Undo action name for making a new label")) {
            let tone = labelTones(for: color ?? nextLabelColor)
            labels.append(LabelDef(key: key, name: trimmed, light: tone.light, dark: tone.dark))
            scheduleSave()
        }
        return key
    }

    /// Renames a label everywhere it appears.
    ///
    /// `key` is deliberately left alone. It is what every task stores, so
    /// regenerating it from the new name would leave every task carrying the old
    /// slug and silently detach the label from all of them.
    func renameLabel(_ key: String, to name: String) {
        let trimmed = Self.labelName(name)
        guard !trimmed.isEmpty,
              let index = labels.firstIndex(where: { $0.key == key }),
              labels[index].name != trimmed
        else { return }
        undoable(String(localized: "Rename Label", comment: "Undo action name for renaming a label")) {
            labels[index].name = trimmed
            scheduleSave()
        }
    }

    /// Recolours a label. Tasks are untouched — they store the key, and the
    /// colour lives on the definition.
    /// Recolours a label from one colour, which is what a picker returns.
    ///
    /// The four a chip actually wears are derived here rather than in the view
    /// — see ``LabelTone/pair(from:)`` — because the same derivation has to run
    /// where a *new* label takes the next colour in the palette, and two copies
    /// of it would make a label created in one place a different colour from
    /// the same label recoloured in another.
    func recolorLabel(_ key: String, to swatch: SwatchColor) {
        recolorLabel(key, to: labelTones(for: swatch))
    }

    /// A label's four colours for a palette swatch.
    ///
    /// What is stored is the *colour the label was given* — what a picker has to
    /// ring, and what ``Palette/chipTone(for:)`` derives the chip from at render
    /// time through the theme's rule. A label painted `.accent` keeps saying
    /// accent rather than being rewritten to a hex, exactly as a board dot
    /// painted accent does — one spelling for one colour wherever it is worn,
    /// and the symbol is pinned to one literal (``SwatchColor/accentHex``).
    func labelTones(for swatch: SwatchColor) -> (light: LabelTone, dark: LabelTone) {
        switch swatch {
        case .rgb(let value, _): LabelTone.pair(from: value)
        case .accent: LabelTone.accentPair
        case .ink: LabelTone.inkPair
        }
    }

    func recolorLabel(_ key: String, to tone: (light: LabelTone, dark: LabelTone)) {
        guard let index = labels.firstIndex(where: { $0.key == key }),
              labels[index].light != tone.light || labels[index].dark != tone.dark
        else { return }
        undoable(String(localized: "Change Label Colour", comment: "Undo action name for recolouring a label")) {
            labels[index].light = tone.light
            labels[index].dark = tone.dark
            scheduleSave()
        }
    }

    /// Removes a label from the board's vocabulary and from every task carrying
    /// it. Each of those tasks records the removal: a chip disappearing from a
    /// card should be explicable from that card's own history.
    /// Reorders the vocabulary — the manager's drag, and its menu's Move
    /// Up/Down, both through `dropOffset` so the two cannot disagree about
    /// where a row lands. Order is presentation: no task changes, so nothing
    /// is touched and no activity is written, but it is board data — the
    /// picker draws the list in this order on every device.
    func moveLabel(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = labels
        reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        guard reordered != labels else { return }
        undoable(String(localized: "Reorder Labels", comment: "Undo action name for reordering the label list")) {
            labels = reordered
            scheduleSave()
        }
    }

    func deleteLabel(_ key: String) {
        guard let index = labels.firstIndex(where: { $0.key == key }) else { return }
        let name = labels[index].name
        undoable(String(localized: "Delete Label", comment: "Undo action name for deleting a label")) {
            labels.remove(at: index)
            for taskIndex in tasks.indices where tasks[taskIndex].labelKeys.contains(key) {
                tasks[taskIndex].labelKeys.removeAll { $0 == key }
                tasks[taskIndex].activity.insert(ActivityEntry(.labelRemoved(key: key, name: name)), at: 0)
                touch(taskIndex)
            }
            scheduleSave()
        }
    }

    /// A label name as it is stored: one line, trimmed, and capped at a length
    /// a chip can still show — past this it is all ellipsis and no information.
    private static func labelName(_ raw: String) -> String {
        String(singleLine(raw).trimmingCharacters(in: .whitespaces).prefix(labelNameLimit))
            .trimmingCharacters(in: .whitespaces)
    }

    private static let labelNameLimit = 40

    /// What the next label made without a colour choice will wear.
    ///
    /// Round the *saved* palette rather than a list of its own, so a colour
    /// the user added is handed out to new labels like every other, and one
    /// they deleted stops being. Public so the compose dialog can open its
    /// colour well on the answer rather than on a guess.
    var nextLabelColor: SwatchColor {
        savedColors[labels.count % savedColors.count].swatch
    }

    /// Creates the label one surface has typed and clears only that surface's
    /// draft for that task. `color` as ``createLabel(named:color:on:)`` takes it.
    func commitLabelDraft(for scope: DetailScope, task taskID: TaskItem.ID, color: SwatchColor? = nil) {
        let key = DraftKey(scope: scope, task: taskID)
        createLabel(named: labelDrafts[key] ?? "", color: color, on: taskID)
        labelDrafts[key] = ""
    }

    func labelDraft(for scope: DetailScope, task: TaskItem.ID) -> String {
        labelDrafts[DraftKey(scope: scope, task: task)] ?? ""
    }

    func setLabelDraft(_ value: String, for scope: DetailScope, task: TaskItem.ID) {
        labelDrafts[DraftKey(scope: scope, task: task)] = value
    }

    func toggleLabelPicker(_ scope: DetailScope, task: TaskItem.ID) {
        labelPickerScope = labelPickerScope == scope ? nil : scope
        labelDrafts[DraftKey(scope: scope, task: task)] = ""
    }

    func closeLabelPicker(_ scope: DetailScope, task: TaskItem.ID) {
        labelPickerScope = nil
        labelDrafts[DraftKey(scope: scope, task: task)] = ""
    }

    // MARK: - Column management

    /// The board a column is on, as an index, for the mutations that edit one.
    private func boardIndex(ofColumn id: BoardColumn.ID) -> Int? {
        boards.firstIndex { board in board.columns.contains { $0.id == id } }
    }

    private var activeBoardIndex: Int? { boards.firstIndex { $0.id == activeBoardID } }

    /// Adds a column to the active board, **before its Done column**. Returns
    /// its id, or `nil` for a name with nothing in it — an unnamed column is
    /// unreachable — or for no board to add it to.
    ///
    /// Before, not at the end, because the end is what makes a column Done — see
    /// ``Board/doneColumn``. Appending would hand every new column the finished
    /// work and quietly demote the old one, which is the failure mode that made
    /// "the last column is Done" look unworkable until the column was pinned.
    /// A new column goes where work is still moving, which is also where anyone
    /// adding one wants it.
    ///
    /// `short` falls back to the name: the "move to" control would otherwise
    /// draw a blank segment, and a long name in a tight segment is still better
    /// than no name at all.
    @discardableResult
    func addColumn(
        named name: String,
        short: String = "",
        dot: SwatchColor = BoardColumn.defaultDot
    ) -> BoardColumn.ID? {
        let trimmed = Self.columnName(name)
        guard !trimmed.isEmpty, let boardIndex = activeBoardIndex else { return nil }
        let abbreviated = Self.columnName(short)
        let column = BoardColumn(
            name: trimmed, short: abbreviated.isEmpty ? trimmed : abbreviated, dot: dot
        )
        undoable(String(localized: "Add Column", comment: "Undo action name for adding a board column")) {
            // A board with no columns at all is being set up for the first time
            // and has no Done column to go in front of yet, so this makes the
            // pair — see `createBoard`, which is the only other place a Done
            // column is minted.
            if boards[boardIndex].columns.isEmpty {
                boards[boardIndex].columns = [column, .freshDone()]
            } else {
                boards[boardIndex].columns.insert(column, at: boards[boardIndex].columns.count - 1)
            }
            scheduleSave()
        }
        return column.id
    }

    /// Renames a column. `short` left `nil` keeps the abbreviation as it is:
    /// the two are edited by different fields, and a rename must not quietly
    /// undo an abbreviation the user chose.
    ///
    /// Nothing is logged. The name is on screen, and the tasks in the column did
    /// not change — the `.moved` entries that name it keep the name they were
    /// written with, which is what makes an old entry still read correctly.
    func renameColumn(_ id: BoardColumn.ID, to name: String, short: String? = nil) {
        let trimmed = Self.columnName(name)
        guard !trimmed.isEmpty, let board = boardIndex(ofColumn: id),
              let index = boards[board].columns.firstIndex(where: { $0.id == id })
        else { return }
        // An abbreviation trimmed away to nothing is the same as not offering
        // one: a blank segment in the "move to" control names nothing.
        let abbreviated = short.map(Self.columnName).flatMap { $0.isEmpty ? nil : $0 }
        let column = boards[board].columns[index]
        guard column.name != trimmed || abbreviated.map({ $0 != column.short }) == true else { return }
        undoable(String(localized: "Rename Column", comment: "Undo action name for renaming a board column")) {
            boards[board].columns[index].name = trimmed
            if let abbreviated { boards[board].columns[index].short = abbreviated }
            scheduleSave()
        }
    }

    /// Recolours a column's dot. Tasks are untouched — they store the id, and
    /// the colour lives on the column.
    func recolorColumn(_ id: BoardColumn.ID, to dot: SwatchColor) {
        guard let board = boardIndex(ofColumn: id),
              let index = boards[board].columns.firstIndex(where: { $0.id == id }),
              boards[board].columns[index].dot != dot
        else { return }
        undoable(String(localized: "Change Column Colour", comment: "Undo action name for recolouring a board column")) {
            boards[board].columns[index].dot = dot
            scheduleSave()
        }
    }

    /// The widest limit a column may be given. Not a rule about kanban — a
    /// board with a hundred cards in one column has bigger problems than the
    /// chip — but a field that accepts `999999999` is a field that draws
    /// `4/999999999` in a pill eight points wide.
    static let columnLimitRange = 1...99

    /// Sets a column's WIP limit, or clears it with `nil`.
    ///
    /// A limit outside ``columnLimitRange`` is clamped rather than refused, and
    /// **zero clears** — the field is a number field, `0` is what backspacing
    /// to nothing and typing one digit passes through on the way, and a column
    /// nothing may ever be in is not a thing anybody means. See
    /// ``BoardColumn/limit`` for why the stored form is an `Int?` and not a
    /// zero-means-none `Int`.
    ///
    /// Nothing is logged and no card is touched, for `renameColumn`'s reason:
    /// the limit is on screen, and the cards in the column did not change.
    func setColumnLimit(_ limit: Int?, on id: BoardColumn.ID) {
        let clamped = limit.flatMap { value -> Int? in
            guard value > 0 else { return nil }
            return min(max(value, Self.columnLimitRange.lowerBound), Self.columnLimitRange.upperBound)
        }
        guard let board = boardIndex(ofColumn: id),
              let index = boards[board].columns.firstIndex(where: { $0.id == id }),
              boards[board].columns[index].limit != clamped
        else { return }
        undoable(String(localized: "Change Column Limit",
                        comment: "Undo action name for setting or clearing a board column's WIP limit")) {
            boards[board].columns[index].limit = clamped
            scheduleSave()
        }
    }

    /// How full a column is against its limit.
    ///
    /// **Measured against what the board draws, not against
    /// ``cardCount(inColumn:)``.** That one counts archived cards, deliberately
    /// and correctly — it exists for the delete-a-column warning, where a
    /// promise to move four cards must not then move nine. A limit counting
    /// them would climb for as long as the board is used: every card ever
    /// finished and filed away would still be pressing against the limit, and a
    /// column would sit permanently over one with nothing on screen to explain
    /// it. Archived is off the board, and off the board is not work in
    /// progress.
    ///
    /// So this reads ``visibleTasks(in:)`` — the same array the column header
    /// already has in hand, and the same number the pill has always shown. The
    /// search query does not narrow it (see ``searchResults``) and a saved view
    /// draws no columns at all, so there is no state in which the pill's count
    /// and the limit's count are different numbers.
    func load(ofColumn id: BoardColumn.ID) -> ColumnLoad {
        ColumnLoad(count: visibleTasks(in: id).count, limit: column(id: id)?.limit)
    }

    // MARK: The palette

    /// Adds a colour to the palette every picker draws from.
    ///
    /// **A no-op for a colour already in it**, rather than a second entry: the
    /// list is a set of choices drawn in order, and two swatches of the same
    /// colour are one choice a person has to compare pixel by pixel. It is not
    /// a failure either — pressing Save on a colour that is already saved has
    /// got the user exactly what they asked for.
    ///
    /// Opacity is dropped on the way in. A picker offers a colour rather than a
    /// colour-and-a-transparency, and a 40% swatch on the palette's own ground
    /// draws as a different colour from the one it puts on a card.
    func saveColor(_ swatch: SwatchColor) {
        let saved: SwatchColor = if case .rgb(let value, _) = swatch { .hex(value) } else { swatch }
        guard !savedColors.contains(where: { $0.swatch == saved }) else { return }
        undoable(String(localized: "Save Colour", comment: "Undo action name for adding a colour to the palette")) {
            savedColors.append(PaletteSwatch(saved))
            scheduleSave()
        }
    }

    /// Takes a colour out of the palette.
    ///
    /// **Nothing wearing it changes.** A board, a column and a label each store
    /// the colour itself rather than a place in this list, so deleting a swatch
    /// removes an *offer* and never repaints anything — which is what makes the
    /// button safe enough to sit in a context menu with no alert in front of it.
    /// ⌘Z puts the offer back.
    ///
    /// The accent is refused: it is not a hex but "whatever the accent theme
    /// is", nothing else in the palette can say that, and a board wearing it
    /// would be left pointing at a choice the picker no longer offers. See
    /// ``PaletteSwatch/isRemovable``.
    @discardableResult
    func deleteSavedColor(_ swatch: SwatchColor) -> Bool {
        guard let index = savedColors.firstIndex(where: { $0.swatch == swatch }),
              savedColors[index].isRemovable, savedColors.count > 1
        else { return false }
        undoable(String(localized: "Delete Colour", comment: "Undo action name for removing a colour from the palette")) {
            savedColors.remove(at: index)
            scheduleSave()
        }
        return true
    }

    /// Reorders the active board's columns. Logs nothing, for `moveSubtask`'s
    /// reason: the order is on screen, and a feed of "column moved" would bury
    /// the changes that matter.
    ///
    /// **Done stays last.** It is the last column that makes it the Done column
    /// — see ``Board/doneColumn`` — so dragging it is refused outright, and
    /// dragging something *past* it lands that column just in front instead,
    /// which is where the drop was heading anyway. This is what a warning used
    /// to be needed for: up to v8 a reorder could silently change where every
    /// future tick sent a card, and the sheet had to ask before it moved
    /// anything. It cannot now, so it does not ask.
    func moveColumn(fromOffsets: IndexSet, toOffset: Int) {
        guard let board = activeBoardIndex else { return }
        let current = boards[board].columns
        guard let last = current.indices.last, !fromOffsets.contains(last) else { return }
        var reordered = current
        reordered.move(fromOffsets: fromOffsets, toOffset: min(toOffset, last))
        guard reordered != boards[board].columns else { return }
        undoable(String(localized: "Reorder Columns", comment: "Undo action name for reordering the board's columns")) {
            boards[board].columns = reordered
            scheduleSave()
        }
    }

    /// Where a drop that landed *on* something goes in the list it is joining.
    ///
    /// `move(fromOffsets:toOffset:)` counts the offset in the **pre-move**
    /// array, so landing after the target is one past it and landing before it
    /// is exactly it. It is here rather than in the view because a drag is not
    /// reachable from a test and this is the half that can be.
    ///
    /// **The label manager's rows are what is left using it for a *drag*.** The
    /// board's cards, the settings sheet's columns and the checklist's sub-tasks
    /// all moved to a caret, which names a gap and so needs no rule for turning a
    /// row into one — see ``drop(_:at:)``, ``dropColumn(_:at:)`` and
    /// ``dropSubtask(_:on:at:)``.
    ///
    /// It stays because the **Move Up / Move Down** menu items are still written
    /// against it, in the checklist and the label manager both: a menu item names
    /// the row it is moving *past*, which is exactly the row-into-gap question
    /// this answers, and it is the direction of travel there rather than a guess.
    static func dropOffset(from: Int, to: Int) -> Int {
        to > from ? to + 1 : to
    }

    /// Puts the dragged column in the gap the caret names.
    ///
    /// **This replaced `dropColumn(_:onto:)`**, and for the reason ``drop(_:at:)``
    /// replaced the cards' `move(_:onto:)`: a drop that names a *row* can only be
    /// resolved by the direction the drag came from, so the same gap was reached
    /// by aiming at one row from above and the other from below, and the top of
    /// the list could not be named at all. Worse, it is unguessable from the
    /// outside — what lit up was the row the pointer was on, which is not where
    /// the column was going. A caret names the gap, so this inserts into it.
    ///
    /// Refused across boards — `moveColumn` is defined over the active board, so
    /// an index from another one names a place in a list this column is not in.
    /// Refused against itself, and against the gaps either side of itself, where
    /// there is nothing to do. Refused for the Done column in both directions:
    /// it never travels, and nothing lands after it, because being last is what
    /// makes it the Done column. `false` says the drop was not taken, which is
    /// what a drop handler owes its caller.
    @discardableResult
    func dropColumn(_ payload: ColumnTransfer, at caret: ColumnCaret) -> Bool {
        guard payload.boardID == activeBoardID, payload.columnID != caret.column,
              let from = columns.firstIndex(where: { $0.id == payload.columnID }),
              let anchor = columns.firstIndex(where: { $0.id == caret.column }),
              let last = columns.indices.last, from != last
        else { return false }
        let offset: Int
        switch caret {
        case .above:
            // Already sitting in that gap: the row under the caret is the one
            // immediately after the dragged column.
            guard anchor != from + 1 else { return false }
            offset = anchor
        case .below:
            guard anchor != last else { return false }
            guard anchor != from - 1 else { return false }
            offset = anchor + 1
        }
        moveColumn(fromOffsets: IndexSet(integer: from), toOffset: offset)
        return true
    }

    /// Deletes a column, moving its cards — archived ones included — to the
    /// first column left. Nothing is thrown away silently, and each card that
    /// moved says so in its own history.
    ///
    /// Refused rather than crashed for the two columns a board cannot lose: its
    /// Done column, which every board keeps, and its last working one, without
    /// which there is nowhere for work to start. `nil` means it happened.
    @discardableResult
    func deleteColumn(_ id: BoardColumn.ID) -> ColumnRefusal? {
        guard let board = boardIndex(ofColumn: id),
              let index = boards[board].columns.firstIndex(where: { $0.id == id })
        else { return .unknownColumn }
        guard boards[board].columns.last?.id != id else { return .doneColumn }
        let boardID = boards[board].id
        var remaining = boards[board].columns
        let removed = remaining.remove(at: index)
        // Two, not one: what is left is a working column *and* the Done column
        // it keeps, so a board down to `[something, Done]` has reached the
        // floor.
        guard remaining.count >= 2 else { return .lastWorkingColumn }
        // The same first-column-left the warning in front of this promised —
        // one rule, asked twice.
        guard let destination = refuge(ifTrashing: id) else { return .unknownColumn }

        undoable(String(localized: "Delete Column", comment: "Undo action name for deleting a board column")) {
            boards[board].columns = remaining
            for taskIndex in tasks.indices where tasks[taskIndex].columnID == removed.id {
                tasks[taskIndex].placement = .column(board: boardID, column: destination.id)
                tasks[taskIndex].activity.insert(
                    ActivityEntry(.moved(columnID: destination.id.uuidString, columnName: destination.name)),
                    at: 0
                )
                touch(taskIndex)
            }
            detachSurfacesFromMissingColumns()
            scheduleSave()
        }
        return nil
    }

    /// Moves the session off a column that is no longer there — at launch,
    /// after a delete, after switching boards, and after an undo that restored
    /// a board from before a column was added.
    ///
    /// Launch is the one that is not about something going away: `mobileColumnID`
    /// is session state and starts every run at a seed column's id, which is on
    /// no board the user made. See `init`.
    private func detachSurfacesFromMissingColumns() {
        let ids = Set(columns.map(\.id))
        // The first **working** column, never Done: a board that has only just
        // been made holds nothing else, and pointing the pager's composer at it
        // would have the first card added on that board arrive already complete.
        // Left where it is when there is none, which `mobileAddPlacement` reads
        // as "not a column of this board" and answers with the Inbox — the same
        // answer it gave when a new board had no columns at all.
        if let first = workingColumns.first?.id, !ids.contains(mobileColumnID) {
            mobileColumnID = first
        }
        if let addingColumnID, !ids.contains(addingColumnID) { cancelDraft() }
        if let dropTargetColumnID, !ids.contains(dropTargetColumnID) { self.dropTargetColumnID = nil }
    }

    /// A column name as it is stored: one line, trimmed, and capped where a
    /// column header stops being able to show it.
    private static func columnName(_ raw: String) -> String {
        String(singleLine(raw).trimmingCharacters(in: .whitespaces).prefix(columnNameLimit))
            .trimmingCharacters(in: .whitespaces)
    }

    private static let columnNameLimit = 40


    // MARK: - Board management

    /// Switches to a board. Navigation rather than a change to the board, so it
    /// registers no undo step — but `activeBoardID` is saved, so it does write.
    func selectBoard(_ id: Board.ID) {
        guard boards.contains(where: { $0.id == id }) else { return }
        activeBoardID = id
        surface = .board
        // **After the surface, and not left to it.** Picking a board from the
        // board is the one arrival `surface`'s `didSet` cannot see: it is
        // already `.board`, so the assignment above changes nothing and the
        // observer never runs. The Inbox is global — the same cards whichever
        // board is under them — so the rule is the same on arrival either way.
        raiseInboxWithTheBoard()
        // The pager and the composer were on the board just left.
        detachSurfacesFromMissingColumns()
        scheduleSave()
    }

    /// Adds a board and moves to it. Returns its id, or `nil` for a name with
    /// nothing in it — an unnamed board is unreachable in the sidebar.
    ///
    /// **It starts with its Done column and nothing else.** It used to arrive
    /// holding a copy of the seed workflow — Backlog, Up Next, In Progress,
    /// Done — so that a card could be put on it straight away, and the first
    /// thing anyone making a board of their own did was delete four columns they
    /// had not asked for. Then it arrived with none at all, which left the one
    /// column every board is *required* to have as something the app added
    /// behind the user's back with their first real one.
    ///
    /// One column, and it is the one that cannot be argued with: every board
    /// keeps a Done column — see ``Board/doneColumn`` — so a board that has one
    /// and nothing else is a board with the whole of its workflow still to say.
    /// Every surface that draws a board with no *working* column offers the
    /// column composer instead of the card one, which is the first thing such a
    /// board needs.
    ///
    /// The invariant this does *not* touch is deletion's: `deleteColumn` still
    /// refuses to take a board's last Done column or its last working one. A
    /// board is allowed to have never had a column and is not allowed to be
    /// emptied down to none — those read as the same rule from the outside
    /// ("this board has no columns; add one") and are different rules
    /// underneath, because the second one has cards in it to lose.
    @discardableResult
    func createBoard(
        named name: String, symbol: String = SymbolMark.boardFallback, codePrefix: String = ""
    ) -> Board.ID? {
        let trimmed = Board.name(name)
        guard !trimmed.isEmpty else { return nil }
        let board = Board(
            name: trimmed,
            symbol: Board.symbol(symbol),
            columns: [.freshDone()],
            codePrefix: Board.codePrefix(codePrefix, fallingBackTo: trimmed)
        )
        undoable(String(localized: "New Board", comment: "Undo action name for adding a board")) {
            boards.append(board)
            scheduleSave()
        }
        // Outside the step, like the selection `addTask` moves: where the user
        // is looking is not what a ⌘Z is aimed at.
        selectBoard(board.id)
        return board.id
    }

    /// Renames a board. Nothing is logged on its cards: the name is on screen,
    /// and a board's history is its cards' rather than its own.
    func renameBoard(_ id: Board.ID, to name: String) {
        let trimmed = Board.name(name)
        guard !trimmed.isEmpty, let index = boards.firstIndex(where: { $0.id == id }),
              boards[index].name != trimmed
        else { return }
        undoable(String(localized: "Rename Board", comment: "Undo action name for renaming a board")) {
            boards[index].name = trimmed
            scheduleSave()
        }
    }

    /// Changes a board's icon. Tasks are untouched — they store the id, and the
    /// mark lives on the board.
    func setBoardSymbol(_ id: Board.ID, to symbol: String) {
        let wanted = Board.symbol(symbol)
        guard let index = boards.firstIndex(where: { $0.id == id }), boards[index].symbol != wanted
        else { return }
        undoable(String(localized: "Change Board Icon", comment: "Undo action name for changing a board's icon")) {
            boards[index].symbol = wanted
            scheduleSave()
        }
    }

    /// Reorders the sidebar's board list. Logs nothing, for `moveColumn`'s
    /// reason: the order is on screen.
    func moveBoard(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = boards
        reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        guard reordered != boards else { return }
        undoable(String(localized: "Reorder Boards", comment: "Undo action name for reordering the boards")) {
            boards = reordered
            scheduleSave()
        }
    }

    /// Deletes a board and takes every card that was on it — archived ones
    /// included — off the board with it.
    ///
    /// **The cards used to be scattered into the Inbox instead**, each with an
    /// `.unfiled` line in its own history. That made deleting a board a *move*
    /// wearing a delete's clothes: a board with forty cards on it left forty
    /// loose cards behind, in the one list that is meant to be short, and the
    /// user who wanted rid of the board had to find and delete them one at a
    /// time. It also made the trash's promise unkeepable — see `trashBoard`,
    /// which is the only caller and which cannot put a board back the way it
    /// was if the cards are no longer the board's to give.
    ///
    /// Nothing is thrown away silently even so: this is what the *trash* calls,
    /// so the cards handed back here go into the trash entry beside the board
    /// and come out of it together. ⌘Z puts the lot back either way.
    ///
    /// Deleting the last board is allowed. What is left is the Inbox, which is
    /// global and was never one board's — cards captured straight to it are not
    /// on any board and are untouched by this — plus the affordance to make
    /// another. So it is a state the user can both reach and leave, and
    /// refusing it would be inventing a rule to protect them from a reversible
    /// act. It also survives a relaunch: `restored` adopts an empty board list
    /// rather than seeding over it.
    ///
    /// The board and its cards come back so a caller can keep them, and say
    /// what went.
    @discardableResult
    func deleteBoard(_ id: Board.ID) -> (board: Board, tasks: [TaskItem])? {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = boards[index]
        // The next board down, else the one above, else none — the rule the
        // selection follows when a card leaves the board.
        let successor = boards.count > 1
            ? boards[index + 1 < boards.count ? index + 1 : index - 1].id
            : nil
        // The board's order, so a board that goes into the trash with forty
        // cards on it comes back out with them in the order it had them.
        let doomed = tasks.filter { $0.boardID == id }.map(\.id)
        var taken: [TaskItem] = []
        undoable(String(localized: "Delete Board", comment: "Undo action name for deleting a board")) {
            boards.remove(at: index)
            // Through `discard` rather than a bulk `removeAll`, for the reason
            // `trashTasks` goes through it: a card leaving the board has to
            // take the session's hold on it with it — the selection, a
            // half-typed sub-task, an open editing session — and a card removed
            // out from under those leaves them pointing at nothing.
            for card in doomed {
                restoreEmptiedFields(on: card)
                if let gone = discard(card) { taken.append(gone) }
            }
            if activeBoardID == id { activeBoardID = successor }
            detachSurfacesFromMissingColumns()
            scheduleSave()
        }
        return (removed, taken)
    }

    // MARK: - Drafts

    /// Everything transient a task owns. Called when the task goes away, so a
    /// half-typed sub-task cannot outlive it and land on whatever is selected
    /// next.
    func clearDrafts(for id: TaskItem.ID) {
        subtaskDrafts = subtaskDrafts.filter { $0.key.task != id }
        labelDrafts = labelDrafts.filter { $0.key.task != id }
        editSessions = editSessions.filter { $0.key.task != id }
        searchTexts[id] = nil
        taskRevisions[id] = nil
    }

    // MARK: - iOS navigation

    /// The columns the pager steps through: the active board's. The Inbox is
    /// not among them — it is a tab of its own, and global.
    var pagerColumns: [BoardColumn] { columns }

    /// The active board's columns before Done — what "is this board set up yet"
    /// is asked of. `columns` alone answers *yes* for a board that has only just
    /// been made, which now always holds its Done column.
    var workingColumns: [BoardColumn] { activeBoard?.workingColumns ?? [] }

    private var mobileColumnIndex: Int {
        columns.firstIndex { $0.id == mobileColumnID } ?? 0
    }

    /// Falls back to the Inbox's own name and dot where there is no column to
    /// be on: a store with no boards, which is what deleting the last one
    /// leaves and what `restored` reads back — and a board that has not been
    /// given a column yet, which is how every board now starts. No phone
    /// surface draws this in the second case; the board tab shows the
    /// no-columns state instead of a pager. See `createBoard`.
    var mobileColumn: BoardColumn {
        columns.indices.contains(mobileColumnIndex) ? columns[mobileColumnIndex] : Self.inboxColumn
    }

    /// The Inbox drawn as though it were a column, for the two phone surfaces
    /// that need a name and a dot rather than a place. It is on no board and no
    /// card is ever in it — a card is in the Inbox by being on no board.
    private static let inboxColumn = BoardColumn(
        id: BoardColumn.inbox.id, name: Board.inboxName, short: Board.inboxName,
        dot: Board.inboxDot
    )

    /// The name the "+ Add task to …" row shows. The board's, always: the Inbox
    /// is a slide-over now and carries its own add row, which knows where it is
    /// without having to ask.
    var mobileColumnName: String { mobileColumn.name }

    /// Where a phone-side add lands: the column the pager is on, and the Inbox
    /// where that column is not on the board in front of the user.
    ///
    /// **The guard is about a board with no columns**, which is what a new one
    /// is. `mobileColumnID` is session state that outlives a board switch —
    /// `detachSurfacesFromMissingColumns` moves it to the new board's first
    /// column, and a board with no first column leaves it naming the *previous*
    /// board's. `placement(forColumn:)` resolves an id against every board, and
    /// `isPlaceable` agrees with it, so without this a card added on a blank
    /// board would land on the board before it — filed somewhere the user
    /// cannot see, with nothing on screen to say so.
    var mobileAddPlacement: TaskPlacement {
        guard columns.contains(where: { $0.id == mobileColumnID }) else { return .inbox }
        return placement(forColumn: mobileColumnID)
    }

    /// Wraps around at both ends, matching the spec's modulo step.
    func stepMobileColumn(by delta: Int) {
        let count = columns.count
        guard count > 0 else { return }
        let next = (mobileColumnIndex + delta + count) % count
        mobileColumnID = columns[next].id
    }

    /// What the phone list shows: a saved view if one is open, otherwise the
    /// current tab's slice of the board.
    ///
    /// **The Board tab ignores the query outright**, which is the rule the desk
    /// and the iPad have now taken for the whole board. One `query` is bound by
    /// every surface in the app, but `PhoneHeader` only puts the field on screen
    /// for Search — so filtering the Board through it left a board that had
    /// silently lost most of its cards with nothing on screen to explain why or
    /// to undo it. The query applies where it can be seen and where the user
    /// asked for it: the Search tab, which *is* the results list, and a saved
    /// view the phone has opened (which says so through
    /// `showsMobileFilterNotice`).
    func mobileTasks(today: CalendarDay) -> [TaskItem] {
        if let activeView { return narrowed(tasks(in: activeView, today: today)) }
        switch tab {
        case .board: return visibleTasks(in: mobileColumnID)
        case .search: return searchResults
        }
    }

    /// Whether the phone's current surface honours the search query at all.
    var mobileAppliesQuery: Bool { activeView != nil || tab == .search }

    /// A query is narrowing what is on screen while the field it was typed into
    /// is not — a saved view opened from the drawer while the tab bar sits on
    /// Board. The surface has to say so and offer to clear it; an invisible
    /// filter is the defect this whole rule exists to remove.
    var showsMobileFilterNotice: Bool {
        isFiltering && mobileAppliesQuery && tab != .search
    }

    /// The dashed "add here" row is hidden while searching, and in a saved view,
    /// which is a filter over the board rather than a place to put a card.
    var showsMobileAddRow: Bool { activeView == nil && tab != .search }

    /// Whether a card names its column. It does wherever the list is flat —
    /// Search and every saved view — and does not on the Board tab, where the
    /// pager directly above has just said which column this is (4.8). The
    /// Inbox's slide-over draws its own rows and does not ask: every card in it
    /// is unfiled, so a chip on each would say "Inbox" under a panel titled
    /// Inbox.
    var showsMobileColumnChips: Bool { activeView != nil || tab != .board }

    /// Picks a tab, which is picking a place, so it leaves whatever saved view
    /// was standing in for the board.
    ///
    /// The alternative is the view outranking the tab — which is what
    /// `mobileTasks` does when both are set — and that means tapping "Board"
    /// and being shown Today. Going through here rather than assigning `tab`
    /// keeps the two from disagreeing.
    func selectTab(_ tab: PhoneTab) {
        // Every tab is the board's surface now that the Inbox is not one of
        // them: what the phone draws is chosen by `tab`, and `surface` is only
        // still set here to leave whatever saved view was standing in.
        surface = .board
        self.tab = tab
        // Search is a tab you go to in order to type in it. It used to arrive
        // as an empty field with no keyboard and no caret, so reaching it cost
        // two taps and the second one had to find a 22pt band of text. Every
        // route through here asks for the field, and the field decides whether
        // it is in a position to take it — see `PhoneHeader.searchField`.
        if tab == .search { focusSearch() }
    }

    /// Whether the Search tab is the surface on screen — which `tab == .search`
    /// on its own does not answer.
    ///
    /// A saved view outranks the tab in `mobileTasks`, so with Today standing in
    /// front of the board the list is the view's and Search is somewhere the
    /// user is not. The header's title, the tab bar's lit slot and
    /// ``toggleSearch()`` all read this one predicate, so what is named, what is
    /// lit and what a second tap puts away cannot come apart.
    var isSearching: Bool { activeView == nil && tab == .search }

    /// The phone's Search slot, which is a switch rather than a destination:
    /// tapped from anywhere else it opens search, tapped again it puts it away.
    ///
    /// **A destination row is not a toggle** — the drawer's board and view rows
    /// do nothing when you press the one you are already on, because a
    /// destination that undoes itself on a second press is one control with two
    /// meanings. Search is not a destination. It is a field over the list, the
    /// same thing the desk's folded search row is, and that row closes on a
    /// second click too (`BoardToolbar.toggleSearchRow`). Without this the phone
    /// had no way back at all: the Board slot is gone, so leaving search meant
    /// opening the drawer and picking the board you were already looking at.
    ///
    /// **Closing it is a cancel, query and all**, which is `closeSearchRow`'s
    /// bargain as well: the field goes when the tab does, so a query left behind
    /// is text nothing on screen shows — waiting to narrow the next saved view
    /// opened from the drawer, and waiting to be typed into the middle of, since
    /// arriving on Search puts the caret at the end of whatever is already
    /// there.
    func toggleSearch() {
        guard isSearching else { return selectTab(.search) }
        selectTab(.board)
        clearQuery()
    }

    /// The floating "+" button: start a new capture in the Inbox.
    ///
    /// The task is created untitled and its sheet opens with the title field
    /// focused, so the capture is finished by typing rather than by editing a
    /// placeholder afterwards. Leaving a saved view is for the same reason
    /// `selectTab` does it: the card lands in the Inbox, and a filter it is
    /// unlikely to match is not where the user should be left looking.
    func quickCapture() {
        // **The Inbox does not come up.** It used to: the card lands there, so
        // the panel was raised to leave it visible once the detail sheet was
        // closed. What that actually did was open a second surface *behind* a
        // sheet the user is already typing into — the panel is never seen while
        // it matters, and dismissing the sheet reveals a slide-over nobody
        // asked for and now has to put away. Capture is one act, and it should
        // move the user nowhere.
        //
        // The card is still in the Inbox and the sheet says so while it is being
        // typed into: `PhoneDetailSheet`'s Move-to row names where it lives.
        //
        // Leaving a saved view stays, and is a different question — a filter the
        // new card is unlikely to match is not a list to strand somebody in
        // whether or not a panel comes up over it. See
        // `SearchScopingTests.aQuickCaptureLeavesTheSavedViewBehindWithoutRaisingTheInbox`.
        surface = .board
        addTask(to: .inbox, title: "", fromPhone: true, log: .captured)
    }

    func addTaskToCurrentMobileColumn() {
        addTask(to: mobileAddPlacement, title: "", fromPhone: true)
    }
}

/// What a save did, which is not always what it was asked to do: a write that
/// was overtaken while it waited out the debounce is dropped, and the store
/// must not then tell the user their board was saved.
private enum SaveOutcome: Sendable {
    case wrote
    case superseded
    case failed(String)
}
