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
    case view(SavedView)
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
            String(localized: "Your board was saved by a newer version of Simple Kanban (format \(version)).",
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
    /// It is the board's only `.done` column. Completing a task, the weekly
    /// meter and the archive all mean nothing without one.
    case lastDoneColumn
    /// Everything left would be a Done column, which is a list rather than a
    /// board: there would be nowhere for work to start.
    case lastWorkingColumn

    var errorDescription: String? {
        switch self {
        case .unknownColumn:
            String(localized: "That column is not on this board.",
                   comment: "Explanation when a column change names a column that does not exist")
        case .lastDoneColumn:
            String(localized: "A board needs a Done column.",
                   comment: "Explanation when deleting the last Done column is refused")
        case .lastWorkingColumn:
            String(localized: "A board needs at least one column that is not Done.",
                   comment: "Explanation when deleting the last column work can start in is refused")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unknownColumn:
            nil
        case .lastDoneColumn:
            String(localized: "Add another Done column first, then delete this one.",
                   comment: "How to get past the refusal to delete the last Done column")
        case .lastWorkingColumn:
            String(localized: "Add another column first, then delete this one.",
                   comment: "How to get past the refusal to delete the last column work can start in")
        }
    }
}

/// The card that says something has just been thrown away.
///
/// **Session state, and firmly not board state**: it is not in `BoardSnapshot`,
/// not in `BoardMutation`, and a relaunch does not bring it back. What happened
/// is already recorded — the thing is in the trash — and this is only the app
/// saying so out loud for a few seconds.
///
/// The `id` is what makes a *repeat* land. Trashing two cards with the same
/// title in a row produces two announcements reading the same words, and a view
/// keyed on the text alone would treat the second as "no change" and leave the
/// first one's dismissal timer running — so the second card would vanish early
/// or not appear at all.
struct TrashAnnouncement: Identifiable, Equatable, Sendable {
    let id = UUID()
    let text: String

    /// One thing, by name. The name is the card's title, the column's or the
    /// board's — see ``TrashedItem/name``.
    init(name: String) {
        text = String(localized: "Moved \(name) to the trash",
                      comment: "Confirmation shown after something is thrown away")
    }

    /// Several cards at once, which have no one name between them.
    init(taskCount: Int) {
        text = String(localized: "Moved \(taskCount) tasks to the trash",
                      comment: "Confirmation shown after several tasks are thrown away at once")
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
}

/// Board state and every mutation the design defines.
///
/// This is a port of the `Component extends DCLogic` class in
/// the design spec (see `simple-kanban design spec.zip`): same state fields,
/// same transition rules.
@MainActor
@Observable
final class BoardStore {
    // MARK: Content

    /// Read-only from outside: every mutation goes through a method that files
    /// an undo step and a save, and a settable array is a way round both —
    /// `store.tasks.removeAll()` would empty the board with `canUndo` still false.
    private(set) var tasks: [TaskItem]
    /// The boards, in sidebar order, each carrying its own columns.
    private(set) var boards: [Board]
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

    /// The card on screen saying what has just been thrown away, or `nil`.
    ///
    /// Written by the three trash verbs and cleared by whichever surface drew
    /// it once its few seconds are up — the timer is the view's, because how
    /// long a message stays on screen is a fact about the screen. Also cleared
    /// by `apply`, so a ⌘Z takes the sentence away with the act it describes;
    /// a card still reading "Moved Ship the thing to the trash" over a board
    /// that has Ship the thing back on it is the app contradicting itself.
    var trashAnnouncement: TrashAnnouncement?
    /// Ordered — the label picker lists them in creation order, and new labels
    /// take their colour from the palette by current count.
    private(set) var labels: [LabelDef] { didSet { labelsByKey = nil } }
    /// The design exposes the accent as an editable prop; this is the choice,
    /// and it is saved with the board.
    private(set) var accentTheme: AccentTheme

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

    var draggingID: TaskItem.ID?
    /// The column being dragged by its name, or `nil` when none is.
    ///
    /// A separate flag from `draggingID` rather than a shared "something is in
    /// the air", because the two say different things to the same view: a card
    /// in flight makes a column a place to *put* it, and a column in flight
    /// makes it a place to put a *column*. Nothing can raise both — a pointer
    /// carries one payload — and `BoardColumnView` reads this to decide which
    /// of its two drop destinations is the live one.
    var draggingColumnID: BoardColumn.ID?
    var dropTargetColumnID: BoardColumn.ID?
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
    var dropTargetCaret: DropCaret?
    var query: String = ""
    /// Where the inline "Task title, then ⏎" composer is open, or `nil` for
    /// none. A place rather than a column id, so the Inbox can have one too.
    var addingPlacement: TaskPlacement?
    /// The column the composer is open in, for a column that wants to ask
    /// whether it is the one. `nil` while it is closed, and while it is open on
    /// the Inbox — which is not a column.
    var addingColumnID: BoardColumn.ID? { addingPlacement?.columnID }
    var draft: String = ""

    // MARK: Surfaces

    var isInspectorOpen: Bool = !BoardStore.inspectorHiddenAtLaunch

    /// `-SimpleKanbanHideInspector YES`, for the same reason the Inbox has a
    /// launch argument: a UI test needs a column beside the panel, and on an
    /// iPad in portrait the inspector is holding that room.
    #if DEBUG
    static let inspectorHiddenAtLaunch = UserDefaults.standard.bool(forKey: "SimpleKanbanHideInspector")
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
    var isInboxDropTarget: Bool = false

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

    /// The panel starts shut, and a harness cannot click it open: a simulator
    /// takes no synthetic taps from outside, and driving the host Mac's pointer
    /// is not a verification — it is a fight with whoever is using the machine.
    /// So there is a launch argument, the same shape as `FirstRun`'s pair:
    ///
    ///     xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanShowInbox YES
    #if DEBUG
    static let inboxOpensAtLaunch = UserDefaults.standard.bool(forKey: "SimpleKanbanShowInbox")
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
    /// wait past the thirtieth day, so it has a door of its own now: the bin at
    /// the foot of the source list on macOS and iPad, and the board menu on the
    /// phone.
    ///
    /// On the store rather than in a view because the three doors are in three
    /// different trees — `BoardSidebar` on two platforms, `PhoneHeader` on the
    /// third — and the phone's sheet is presented by the root, which is neither.
    var isShowingTrash: Bool = false
    /// Whether File ▸ Export… / Import… has asked for its panel. On the store
    /// for the reason the shortcuts sheet is: the menu bar lives outside every
    /// window's view tree, and the panels are presented by a view inside one.
    /// The settings surface raises the same panels from state of its own — see
    /// `BoardTransfer` for why they are not shared.
    var isExportingBoard: Bool = false
    var isImportingBoard: Bool = false
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

    static let sortOrderKey = "SimpleKanbanSortOrder"

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
    @ObservationIgnored private let sync: BoardSyncStore?

    /// Whether the board is reaching iCloud right now. `false` when sync is
    /// off, when the entitlement is missing, and in every test.
    var isSyncing: Bool { sync?.isSyncing ?? false }

    @ObservationIgnored private var remoteChangeObserver: (any NSObjectProtocol)?

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
    static func restored(file: BoardFile = .default, sync: BoardSyncStore? = nil) -> BoardStore {
        if let sync, let synced = try? sync.load() {
            let store = BoardStore(
                tasks: synced.tasks, boards: synced.boards, activeBoardID: synced.activeBoardID,
                labels: synced.labels, accentTheme: synced.accentTheme,
                nextSerial: synced.nextSerial,
                // The board came from the records; the trash is this device's
                // and only ever lived in the file — see `BoardStore.trash`. The
                // file is written on every save whether sync is on or not, so it
                // is there to be read even on the path where the records won.
                trash: file.load().snapshot?.trash ?? [],
                file: file, sync: sync
            )
            store.applyStoredPreferences()
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
                accentTheme: snapshot.accentTheme,
                nextSerial: snapshot.nextSerial,
                trash: snapshot.trash,
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
        // Whatever the JSON said is now what the records should say: either
        // this is the upgrade that first fills them, or SwiftData failed to
        // read and is being given the board back.
        store.pushToSync()
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
            surface = SavedView(rawValue: raw).map(BoardSurface.view) ?? .board
        }
        // **After the surface, not before it.** "Open the Inbox with the board"
        // is a promise about the board, and a launch that lands on Today has not
        // made it — on the phone the Inbox is a sheet drawn over whatever is
        // there, so an unconditional raise would put the panel over Today and
        // hide the very thing the launch went to. The `#if DEBUG` flag is not
        // conditional: it is how a UI test asks for the panel outright.
        isInboxOpen = Self.inboxOpensAtLaunch
            || (Preferences.opensInboxAtLaunch && surface == .board)
        #if DEBUG
        // **Last, so it is the last word.** These ran at the end of `init`,
        // which was before any of the above — fine while nothing here touched
        // the surface, and wrong the moment a launch landed somewhere by
        // default: `-SimpleKanbanTab board` set the board and this method put
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
        accentTheme: AccentTheme = .ember,
        nextSerial: Int = BoardSnapshot.baseSerial,
        trash: [TrashedItem] = [],
        file: BoardFile? = nil,
        sync: BoardSyncStore? = nil
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
        self.accentTheme = accentTheme
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
        accentTheme: AccentTheme = .ember,
        nextSerial: Int = BoardSnapshot.baseSerial,
        file: BoardFile? = nil
    ) {
        var board = SeedData.defaultBoard
        board.columns = columns
        self.init(tasks: tasks, boards: [board], activeBoardID: board.id, labels: labels,
                  accentTheme: accentTheme, nextSerial: nextSerial, file: file)
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

    // MARK: - Persistence

    private var snapshot: BoardSnapshot {
        BoardSnapshot(tasks: tasks, boards: boards, labels: labels, nextSerial: nextSerial,
                      accentTheme: accentTheme, activeBoardID: activeBoardID, trash: trash)
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
    /// The snapshot is taken *now* and the task holds it, the file and its
    /// place in the file's write order rather than `self`: an edit made just
    /// before the store goes away must still reach the disk.
    private func scheduleSave() {
        boardRevision &+= 1
        guard let file, !isSaveBlocked else { return }
        // Reminders and the Spotlight index follow the board from here rather
        // than from each mutation, because every mutation already comes through
        // this one funnel — the bulk commands, a drag into Done, undo and redo
        // included — and a per-call-site hook silently misses all of them. Both
        // reconcile against what they last published, so a keystroke that
        // changes no due date sends nothing.
        //
        // Below the guard on purpose: a store with no file is a preview, and a
        // preview may not reach the machine's Notification Centre. `BoardFile`
        // asks the second question for the same reason it steps `.default`
        // aside — `xcodebuild test` launches this app as the test host under
        // its real bundle identifier, so the suite's stores are file-backed and
        // the Notification Centre and Spotlight index they would reach are the
        // developer's own. A test that wants to drive the scheduler injects a
        // fake `TaskNotificationCenter` instead of coming through here.
        if !BoardFile.isRunningTests {
            reconcileReminders()
            TaskSpotlightIndex.shared.reconcile(tasks)
        }
        let pending = snapshot
        // The records first, and on this actor: SwiftData's main context is
        // main-actor work, and `apply` only touches what changed, so the cost
        // is one card's worth rather than the board's.
        pushToSync(pending)
        let generation = file.nextWriteGeneration()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
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
            self?.recordSave(outcome)
        }
    }

    /// Writes at once, for backgrounding and quit — points where the debounce
    /// would never get to fire and the last edit would be lost. Synchronous on
    /// purpose: at quit the ordering genuinely matters.
    func saveNow() {
        guard let file, !isSaveBlocked else { return }
        saveTask?.cancel()
        saveTask = nil
        pushToSync()
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
        guard let sync else { return }
        do {
            try sync.apply(board ?? snapshot)
            if case .sync = lastError { lastError = nil }
        } catch {
            lastError = .sync(message: error.localizedDescription)
        }
    }

    /// Adopts what another device changed.
    ///
    /// The records are authoritative here, not this device's copy: CloudKit has
    /// already merged the two, so re-reading is how this side finds out what it
    /// won and lost. The undo stack is deliberately left alone — a step that
    /// reversed somebody else's edit on their behalf would be worse than no
    /// step at all — and `invalidateDiff` tells the next write that what it
    /// thinks is on disk is no longer what is.
    func mergeRemoteChanges() {
        guard let sync, let incoming = try? sync.load() else { return }
        sync.invalidateDiff()
        adoptContent(incoming)
        lastSyncedAt = .now
    }

    /// Starts listening for another device's changes. Called by `RootView`;
    /// safe to call twice.
    func beginObservingRemoteChanges() {
        guard sync?.isSyncing == true, remoteChangeObserver == nil else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mergeRemoteChanges() }
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
    /// Nothing here defeats the file's write ordering: `scheduleSave()` claims
    /// its generation when the restore is queued, so a debounced write issued
    /// before it is by definition the older one and is dropped rather than
    /// landing on top of the restored board.
    func restore(fromBackup url: URL) throws {
        guard let file else { throw BoardFileError.unreadable }
        // Before anything is disturbed: a backup that cannot be read must leave
        // the board exactly as it was.
        let restored = try file.restore(from: url)
        saveNow()
        keepACopy(with: file)
        undoable(String(localized: "Restore Backup",
                        comment: "Undo action name for putting a backup of the board back")) {
            adoptContent(restored)
        }
    }

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
    /// `accentTheme` and `activeBoardID` are deliberately not adopted. The first
    /// is a preference the user set on this machine, and the second is where
    /// they are looking — neither is the arriving file's to change.
    ///
    /// The **trash is not adopted either**, and it is the clearest case of the
    /// three. An import is somebody else's file, and their thrown-away boards
    /// are not things this user should be offered back. A backup is this user's
    /// own file from an earlier moment, which sounds like the opposite — but
    /// taking its trash would resurrect the things they have permanently deleted
    /// since, which is the one act in the app that is meant to stick. Either way
    /// what is carried across is the *board*; the trash stays this session's.
    private func adoptContent(_ content: BoardSnapshot) {
        apply(BoardMutation(
            tasks: Self.placed(content.tasks, on: content.boards),
            labels: content.labels,
            nextSerial: content.nextSerial,
            boards: content.boards,
            trash: trash
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
        BoardMutation(tasks: tasks, labels: labels, nextSerial: nextSerial, boards: boards, trash: trash)
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
        // See `trashAnnouncement`: the message describes an act this is
        // reversing, so it goes with it.
        trashAnnouncement = nil
        // The restore may have taken away the board being looked at — undoing
        // the creation of one, say — and a surface reading `activeBoard` must
        // never be shown nothing while there is still a board to show.
        if !boards.contains(where: { $0.id == activeBoardID }) { activeBoardID = boards.first?.id }
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

    /// One of the two mutations that deliberately register no undo step — the
    /// other is `selectBoard`. The accent is a preference rather than board
    /// data, it is not in `BoardMutation`, and a ⌘Z aimed at a card the user had
    /// just moved should not repaint the app.
    func setAccentTheme(_ theme: AccentTheme) {
        guard theme != accentTheme else { return }
        accentTheme = theme
        scheduleSave()
    }

    #if DEBUG
    /// Opens a surface straight from a launch argument, so the sheet, drawer and
    /// individual tabs can be driven from `simctl launch` or a UI test without
    /// scripting taps. The sheet takes either a task's `code` or its UUID:
    ///
    ///     xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanOpenSheet NW-118
    ///     xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanOpenDrawer YES
    ///     xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanOpenSettings YES
    ///     xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanOpenTrash YES
    ///     xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanOpenBoardSettings YES
    ///     xcrun simctl launch <device> com.n14395.SimpleKanban -SimpleKanbanTab search
    private func applyLaunchOverrides() {
        let defaults = UserDefaults.standard
        if let identifier = defaults.string(forKey: "SimpleKanbanOpenSheet"),
           let task = task(matching: identifier) {
            sheetID = task.id
        }
        if defaults.bool(forKey: "SimpleKanbanOpenDrawer") {
            isNavDrawerOpen = true
        }
        if defaults.bool(forKey: "SimpleKanbanOpenSettings") {
            isShowingSettings = true
        }
        if defaults.bool(forKey: "SimpleKanbanOpenTrash") {
            isShowingTrash = true
        }
        // The board's own settings, on whichever board the launch settles on.
        // The one surface here that is a *sheet on macOS too*, and so the one a
        // desk screenshot needs a way in to that is not a right-click.
        if defaults.bool(forKey: "SimpleKanbanOpenBoardSettings"), let board = activeBoardID {
            boardSettings = BoardSettingsRequest(board: board)
        }
        if let raw = defaults.string(forKey: "SimpleKanbanTab"), let parsed = PhoneTab(rawValue: raw) {
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
    var selectedTasks: [TaskItem] { tasks.filter { selection.contains($0.id) } }

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
        case .view(let view):
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
    var activeBoard: Board? { boards.first { $0.id == activeBoardID } }

    func board(id: Board.ID?) -> Board? {
        guard let id else { return nil }
        return boards.first { $0.id == id }
    }

    func board(for task: TaskItem) -> Board? { board(id: task.boardID) }

    /// Which board a column belongs to. Column ids are unique across boards, so
    /// a move that names only a column still knows where it is going.
    func board(ofColumn id: BoardColumn.ID) -> Board? {
        boards.first { board in board.columns.contains { $0.id == id } }
    }

    // MARK: - Columns

    /// The active board's columns, in board order. The Inbox is not one of them
    /// on any board: it is global, and a card is in it by being on no board at
    /// all — see `TaskPlacement`.
    var columns: [BoardColumn] { activeBoard?.columns ?? [] }

    /// Resolves a column id against every board, not just the active one: a
    /// search result names its column whichever board it is on. `nil` for an id
    /// no column answers to, which is a real state — a deleted column outlives
    /// itself in the activity feed.
    func column(id: BoardColumn.ID?) -> BoardColumn? {
        guard let id else { return nil }
        return boards.lazy.compactMap { $0.column(id: id) }.first
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

    /// Whether a task is complete — the one question the three Done behaviours
    /// used to answer by comparing its column id against the literal "done".
    func isDone(_ task: TaskItem) -> Bool { role(of: task) == .done }

    /// A task's column's role. A card in the Inbox, or whose column has gone,
    /// reads as `.backlog` rather than as complete: the harmless answer of the
    /// three.
    func role(of task: TaskItem) -> ColumnRole { column(id: task.columnID)?.role ?? .backlog }

    func role(ofColumn id: BoardColumn.ID) -> ColumnRole { column(id: id)?.role ?? .backlog }

    /// Where `complete` sends a task, and what "Archive completed" clears. The
    /// first `.done` column, so a board with two of them still has one answer.
    var doneColumnID: BoardColumn.ID? { doneColumnID(onBoard: activeBoardID) }

    /// The same, on a named board. A card is completed onto *its own* board's
    /// Done column, which is not always the one on screen.
    func doneColumnID(onBoard id: Board.ID?) -> BoardColumn.ID? {
        (board(id: id) ?? activeBoard)?.columns.first { $0.role == .done }?.id
    }

    /// Which column completed cards would land in **after** a reorder, worked
    /// out without performing one.
    ///
    /// What makes a column the one completed work lands in is its *role*, not
    /// its position — see `doneColumnID` — so most reorders change nothing about
    /// it. The exception is a board with more than one Done column, where the
    /// first of them is the answer and moving them past each other changes it.
    /// That is the case the settings sheet asks about before it moves anything:
    /// it is invisible on the board, it changes where every future tick sends a
    /// card, and no undo step announces itself.
    func doneColumnID(afterMoving fromOffsets: IndexSet, toOffset: Int) -> BoardColumn.ID? {
        guard let board = activeBoard else { return nil }
        var reordered = board.columns
        reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        return reordered.first { $0.role == .done }?.id
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

    /// Tasks in the active board's Done column, unfiltered — what the archive
    /// affordances count and act on. Scoped to the board on screen: "archive
    /// completed" tidies the board the user is looking at, not every board.
    var completedTasks: [TaskItem] {
        tasks.filter { $0.boardID == activeBoardID && isDone($0) && !$0.isArchived }
    }

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

    /// The global Inbox: everything on no board, in board order.
    var inboxTasks: [TaskItem] {
        sorted(tasks.filter { !$0.isArchived && $0.isUnfiled })
    }

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

    var totalCount: Int { tasks.count { !$0.isArchived } }

    /// What the Inbox row shows: cards on no board.
    var inboxCount: Int { tasks.count { $0.isUnfiled && !$0.isArchived } }

    /// What a board row shows: that board's cards, archived ones excluded, the
    /// same way `totalCount` excludes them.
    func taskCount(for boardID: Board.ID) -> Int {
        tasks.count { $0.boardID == boardID && !$0.isArchived }
    }

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
            lastSurfaceName = activeView?.rawValue ?? Self.boardSurfaceName
            Preferences.remember(surface: lastSurfaceName)
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
    static var landingSurface: BoardSurface {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? .view(.today) : .board
        #else
        .board
        #endif
    }

    /// Which saved view has replaced the board, or `nil` for the board itself.
    ///
    /// A face on `surface` rather than a field of its own, so the two cannot
    /// disagree about what is on screen. Clearing it returns to the board, which
    /// is what every "close this view" affordance means; the Inbox is left
    /// through `selectSurface(_:)` or the tab bar instead.
    var activeView: SavedView? {
        get { if case .view(let view) = surface { view } else { nil } }
        set { surface = newValue.map(BoardSurface.view) ?? .board }
    }

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
    /// `simplekanban://` link, a Spotlight or notification tap, and a result
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
            activeView = .archive
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
    func count(of view: SavedView, today: CalendarDay) -> Int {
        members(of: view, today: today).count
    }

    private func members(of view: SavedView, today: CalendarDay) -> [TaskItem] {
        var members = tasks.filter { view.matches($0, today: today, isDone: isDone($0), week: weekMeaning) }
        if let sort = view.sort { members = Self.stableSorted(members, by: sort) }
        if let limit = view.limit { members = Array(members.prefix(limit)) }
        return members
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
        dropTargetColumnID = nil
        dropTargetCaret = nil
        isInboxDropTarget = false
    }

    /// Says a column has been picked up, from `beginDrag`'s signal and with its
    /// expiry: `.draggable` asking for its payload is the one moment both
    /// platforms agree on, and a session the OS eats would otherwise leave the
    /// board thinking a column is still in the air forever.
    func beginColumnDrag(_ id: BoardColumn.ID) {
        Task { @MainActor [weak self] in
            guard let self, draggingColumnID != id else { return }
            draggingColumnID = id
            try? await Task.sleep(for: .seconds(Self.liftExpiry))
            if draggingColumnID == id { endColumnDrag() }
        }
    }

    func endColumnDrag() { draggingColumnID = nil }

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
    /// The expiry is for the case that has no callback at all before
    /// `onDragSessionUpdated`: a card let go over nothing ends its session
    /// without telling anybody, and without this the board would stay dimmed
    /// and highlighted until the next pick-up. Every drop clears the lift on
    /// the way through `endDrag`, so the ordinary case never reaches it.
    func beginDrag(_ id: TaskItem.ID, onLift: @escaping () -> Void = {}) {
        Task { @MainActor [weak self] in
            guard let self, draggingID != id else { return }
            draggingID = id
            onLift()
            try? await Task.sleep(for: .seconds(Self.liftExpiry))
            if draggingID == id { endDrag() }
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
    /// or over the ground of the column it already sits in, which the drop
    /// treats as aimed at where the card already is. The column stays lit in
    /// that last case: the highlight says which list the pointer is in, and the
    /// caret says where the card would go, and there being nowhere for it to go
    /// is a true thing to draw.
    var dropCaret: DropCaret? {
        guard allowsCardDrag else { return nil }
        if let caret = dropTargetCaret {
            // Not on the card in the air: it is about to leave, and a line
            // against a card that is going says nothing about where anything
            // lands. `draggingID` is *not* required for the rest — a caret is a
            // fact about the pointer, and on a build with no drag-session
            // callback there may be nothing in `draggingID` to compare with.
            return caret.card == draggingID ? nil : caret
        }
        // The pointer is on a list's own ground rather than on a gap it has
        // named, and a drop there lands at the foot — see ``groundCaret(in:)``.
        guard let dragging = draggingID,
              let destination = hoveredDropPlacement,
              self[dragging]?.placement != destination
        else { return nil }
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
    /// rule of its own: a drop on the ground of the list the card is already in
    /// is aimed at where it already is, and `performMove` would return without
    /// moving it — but only after `undoable` had opened a step for it. Refusing
    /// up front is what keeps a ⌘Z from taking back a card that never went
    /// anywhere, and `unfile` says the same about the Inbox.
    ///
    /// Kept as a name of its own rather than folded into that one call, because
    /// the four surfaces that take a drop on ground say which kind of drop it is
    /// at the call site — and `DragReorderTests` reads those call sites to check
    /// that a *ground* drop has not quietly become one that names a card.
    func drop(_ id: TaskItem.ID, onGroundOf placement: TaskPlacement) {
        guard isPlaceable(placement), let task = self[id] else { return }
        guard task.placement != placement else { return endDrag() }
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
            if role(ofColumn: columnID) == .done, wasElsewhere {
                let outstanding = moved.subtasks.count { !$0.done }
                if outstanding > 0 {
                    moved.subtasks = moved.subtasks.map { var s = $0; s.done = true; return s }
                    moved.activity.insert(ActivityEntry(.subtasksCompletedOnDone(count: outstanding)), at: 0)
                }
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

    /// Sends a task to Done. The move logs where it went, and the entry under
    /// it says where it was, which is what `reopen` reads.
    ///
    /// An archived task refuses both this and `reopen`: in the Archive the verb
    /// is Restore and only Restore, and the refusal lives here so no surface can
    /// reintroduce a tick that silently picks the column a filed card would
    /// reappear in and closes its outstanding sub-tasks on the way.
    /// Completing a card that is in the Inbox files it onto the board on
    /// screen: being complete is a column's role, and the Inbox has no columns,
    /// so there is nowhere else for a ticked card to be.
    func complete(_ id: TaskItem.ID) {
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
        guard let task = self[id], !task.isArchived, !isDone(task),
              let done = doneColumnID(onBoard: task.boardID) else { return nil }
        return placement(forColumn: done)
    }

    /// Takes a task back out of Done, to wherever it was working before.
    func reopen(_ id: TaskItem.ID) {
        guard let task = self[id], !task.isArchived, isDone(task) else { return }
        let target = reopenPlacement(for: task)
        undoable(String(localized: "Reopen Task", comment: "Undo action name for reopening a completed task")) {
            performMove(id, to: target)
        }
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
        for entry in task.activity {
            guard case .moved(let columnID, _) = entry.kind,
                  let id = UUID(uuidString: columnID),
                  let column = board.column(id: id), column.role != .done
            else { continue }
            return .column(board: board.id, column: column.id)
        }
        guard let column = board.columns.first(where: { $0.role != .done })
        else { return task.placement }
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

    var trashCount: Int { trashedItems.count }

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
        if let removed { announce(TrashAnnouncement(name: removed.displayTitle)) }
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
                 ? TrashAnnouncement(name: first.displayTitle)
                 : TrashAnnouncement(taskCount: removed.count))
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
        if refusal == nil { announce(TrashAnnouncement(name: column.name)) }
        return refusal
    }

    /// Throws a board away. Its cards go to the global Inbox as they always
    /// have; what goes in the trash is the board, with its columns inside it.
    @discardableResult
    func trashBoard(_ id: Board.ID) -> Board? {
        guard let position = boards.firstIndex(where: { $0.id == id }) else { return nil }
        var removed: Board?
        undoable(String(localized: "Trash Board", comment: "Undo action name for putting a board in the trash")) {
            removed = deleteBoard(id)
            if let removed { keep(.board(removed, position: position)) }
        }
        if let removed { announce(TrashAnnouncement(name: removed.name)) }
        return removed
    }

    /// Raises the card. Outside the undo step on purpose: it is not part of what
    /// ⌘Z reverses, and a step that captured it would put the message back on
    /// screen on redo.
    private func announce(_ announcement: TrashAnnouncement) {
        trashAnnouncement = announcement
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
    /// changed length since.
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
            case .board(let board, let position):
                guard !boards.contains(where: { $0.id == board.id }) else {
                    refusal = .alreadyThere
                    return
                }
                boards.insert(board, at: min(position, boards.count))
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
        return isDone(task) || canComplete(id)
    }

    /// Whether archiving this card would do anything. A card already in the
    /// Archive is the only one it would not.
    func canArchive(_ id: TaskItem.ID) -> Bool { self[id]?.isArchived == false }

    /// The cards `complete(_:)` will move, in board order.
    func completeTargets(_ ids: Set<TaskItem.ID>) -> [TaskItem.ID] { ordered(ids).filter(canComplete) }

    /// The cards `archive(_:)` will file away, in board order.
    func archiveTargets(_ ids: Set<TaskItem.ID>) -> [TaskItem.ID] { ordered(ids).filter(canArchive) }

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
        log kind: ActivityEntry.Kind = .created
    ) -> TaskItem.ID {
        let id = mintTask(to: placement, title: title, log: kind)

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
    private func mintTask(
        to placement: TaskPlacement, title: String, log kind: ActivityEntry.Kind,
        today: CalendarDay = CalendarDay(.now)
    ) -> TaskItem.ID {
        let startsDue = defaultDueDate.day(from: today)
        let placement = isPlaceable(placement) ? placement : .inbox
        var task = TaskItem(
            code: BoardSnapshot.code(prefix: codePrefix(for: placement), forSerial: nextSerial),
            title: title,
            due: startsDue,
            priority: .default,
            activity: [ActivityEntry(kind)]
        )
        task.placement = placement
        undoable(String(localized: "New Task", comment: "Undo action name for adding a task")) {
            nextSerial += 1
            tasks.append(task)
            scheduleSave()
        }
        return task.id
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

    /// Commits the inline "Task title, then ⏎" composer at the top of a column.
    func commitDraft() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let placement = addingPlacement, !title.isEmpty else { return }
        addTask(to: placement, title: title)
    }

    func cancelDraft() {
        addingPlacement = nil
        draft = ""
    }

    func beginAdding(in columnID: BoardColumn.ID) {
        beginAdding(in: placement(forColumn: columnID))
    }

    func beginAdding(in placement: TaskPlacement) {
        addingPlacement = placement
        draft = ""
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
    func beginAddingWhereVisible(to destination: NewTaskDestination = Preferences.newTaskDestination) {
        // The setting wins over what is on screen, which is the whole of what
        // it is for: a capture habit files later rather than placing now.
        if destination == .inbox {
            showInbox()
            return beginAdding(in: .inbox)
        }
        guard let column = activeBoard?.landingColumn else {
            showInbox()
            return beginAdding(in: .inbox)
        }
        selectSurface(.board)
        beginAdding(in: column.id)
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

    private func value(_ field: TaskField, on id: TaskItem.ID, subtask: SubTask.ID? = nil) -> FieldValue {
        value(field, on: id, subtask: subtask, in: mutation)
    }

    /// The same read against a captured board rather than the live one, so an
    /// undo can ask what a step it is about to restore says about a field.
    private func value(
        _ field: TaskField, on id: TaskItem.ID, subtask: SubTask.ID?, in state: BoardMutation
    ) -> FieldValue {
        let task = state.tasks.first { $0.id == id }
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
        let name = tasks[taskIndex].subtasks[subIndex].done
            ? String(localized: "Reopen Sub-task", comment: "Undo action name for un-ticking a sub-task")
            : String(localized: "Complete Sub-task", comment: "Undo action name for ticking a sub-task")
        undoable(name) {
            tasks[taskIndex].subtasks[subIndex].done.toggle()
            touch(taskIndex)
            scheduleSave()
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
    func createLabel(named name: String, on taskID: TaskItem.ID) {
        let trimmed = Self.labelName(name)
        guard !trimmed.isEmpty else { return }
        let key = LabelDef.key(from: trimmed)
        let exists = label(forKey: key) != nil
        let action = exists
            ? String(localized: "Add Label", comment: "Undo action name for putting a label on a task")
            : String(localized: "Create Label", comment: "Undo action name for making a new label")

        undoable(action) {
            if !exists {
                let tone = LabelDef.palette[labels.count % LabelDef.palette.count]
                labels.append(LabelDef(key: key, name: trimmed, light: tone.light, dark: tone.dark))
            }
            if let index = position(of: taskID), !tasks[index].labelKeys.contains(key) {
                tasks[index].labelKeys.append(key)
                tasks[index].activity.insert(ActivityEntry(.labelAdded(key: key, name: trimmed)), at: 0)
                touch(index)
            }
            scheduleSave()
        }
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

    /// Creates the label one surface has typed and clears only that surface's
    /// draft for that task.
    func commitLabelDraft(for scope: DetailScope, task taskID: TaskItem.ID) {
        let key = DraftKey(scope: scope, task: taskID)
        createLabel(named: labelDrafts[key] ?? "", on: taskID)
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

    /// Adds a column at the end of the active board. Returns its id, or `nil`
    /// for a name with nothing in it — an unnamed column is unreachable — or
    /// for no board to add it to.
    ///
    /// `short` falls back to the name: the "move to" control would otherwise
    /// draw a blank segment, and a long name in a tight segment is still better
    /// than no name at all.
    @discardableResult
    func addColumn(
        named name: String,
        short: String = "",
        dot: SwatchColor = .ink(opacity: 0.35),
        role: ColumnRole = .backlog
    ) -> BoardColumn.ID? {
        let trimmed = Self.columnName(name)
        guard !trimmed.isEmpty, let boardIndex = activeBoardIndex else { return nil }
        let abbreviated = Self.columnName(short)
        let column = BoardColumn(
            name: trimmed, short: abbreviated.isEmpty ? trimmed : abbreviated, dot: dot, role: role
        )
        undoable(String(localized: "Add Column", comment: "Undo action name for adding a board column")) {
            boards[boardIndex].columns.append(column)
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

    /// Reorders the active board's columns. Logs nothing, for `moveSubtask`'s
    /// reason: the order is on screen, and a feed of "column moved" would bury
    /// the changes that matter.
    func moveColumn(fromOffsets: IndexSet, toOffset: Int) {
        guard let board = activeBoardIndex else { return }
        var reordered = boards[board].columns
        reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
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
    /// is exactly it. Every reorder in this app is that one expression — the
    /// checklist's rows, the board's columns — and it is here rather than in
    /// either of them because a drag is not reachable from a test and this is
    /// the half that can be.
    static func dropOffset(from: Int, to: Int) -> Int {
        to > from ? to + 1 : to
    }

    /// Puts the dragged column where `target` sits, which is what dropping one
    /// column on another means.
    ///
    /// Refused across boards — `moveColumn` is defined over the active board, so
    /// an index from another one names a place in a list this column is not in —
    /// and refused onto itself, where there is nothing to do. `false` says the
    /// drop was not taken, which is what a drop handler owes its caller.
    @discardableResult
    func dropColumn(_ payload: ColumnTransfer, onto target: BoardColumn.ID) -> Bool {
        guard payload.boardID == activeBoardID,
              let from = columns.firstIndex(where: { $0.id == payload.columnID }),
              let to = columns.firstIndex(where: { $0.id == target }),
              from != to
        else { return false }
        moveColumn(fromOffsets: IndexSet(integer: from), toOffset: Self.dropOffset(from: from, to: to))
        return true
    }

    /// Deletes a column, moving its cards — archived ones included — to the
    /// first column left. Nothing is thrown away silently, and each card that
    /// moved says so in its own history.
    ///
    /// Refused rather than crashed when it would leave the board without a Done
    /// column or without one that is not Done. `nil` means it happened.
    @discardableResult
    func deleteColumn(_ id: BoardColumn.ID) -> ColumnRefusal? {
        guard let board = boardIndex(ofColumn: id),
              let index = boards[board].columns.firstIndex(where: { $0.id == id })
        else { return .unknownColumn }
        let boardID = boards[board].id
        var remaining = boards[board].columns
        let removed = remaining.remove(at: index)
        guard remaining.contains(where: { $0.role == .done }) else { return .lastDoneColumn }
        guard remaining.contains(where: { $0.role != .done }) else { return .lastWorkingColumn }
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
        if let first = columns.first?.id, !ids.contains(mobileColumnID) {
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
        // The pager and the composer were on the board just left.
        detachSurfacesFromMissingColumns()
        scheduleSave()
    }

    /// Adds a board and moves to it. Returns its id, or `nil` for a name with
    /// nothing in it — an unnamed board is unreachable in the sidebar.
    ///
    /// **It starts with no columns.** It used to arrive holding a copy of the
    /// seed workflow — Backlog, Up Next, In Progress, Done — so that a card
    /// could be put on it straight away, and the first thing anyone making a
    /// board of their own did was delete four columns they had not asked for.
    /// A new board is a blank one; every surface that draws a board with no
    /// columns offers the column composer instead of the card one, which is the
    /// first thing a blank board needs.
    ///
    /// The invariant this does *not* touch is deletion's: `deleteColumn` still
    /// refuses to take a board's last Done column or its last working one. A
    /// board is allowed to have never had a column and is not allowed to be
    /// emptied down to none — those read as the same rule from the outside
    /// ("this board has no columns; add one") and are different rules
    /// underneath, because the second one has cards in it to lose.
    @discardableResult
    func createBoard(named name: String, dot: SwatchColor = .accent, codePrefix: String = "") -> Board.ID? {
        let trimmed = Board.name(name)
        guard !trimmed.isEmpty else { return nil }
        let board = Board(
            name: trimmed,
            dot: dot,
            columns: [],
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

    /// Recolours a board's dot. Tasks are untouched — they store the id, and
    /// the colour lives on the board.
    func recolorBoard(_ id: Board.ID, to dot: SwatchColor) {
        guard let index = boards.firstIndex(where: { $0.id == id }), boards[index].dot != dot else { return }
        undoable(String(localized: "Change Board Colour", comment: "Undo action name for recolouring a board")) {
            boards[index].dot = dot
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

    /// Deletes a board and sends every card that was on it — archived ones
    /// included — to the Inbox. Nothing is thrown away silently, and each card
    /// says in its own history where it went.
    ///
    /// Deleting the last board is allowed. What is left is the Inbox, which is
    /// global and was never one board's, plus the affordance to make another —
    /// so it is a state the user can both reach and leave, and refusing it
    /// would be inventing a rule to protect them from a reversible act. It also
    /// survives a relaunch: `restored` adopts an empty board list rather than
    /// seeding over it.
    ///
    /// The board comes back so a caller can say what went.
    @discardableResult
    func deleteBoard(_ id: Board.ID) -> Board? {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = boards[index]
        // The next board down, else the one above, else none — the rule the
        // selection follows when a card leaves the board.
        let successor = boards.count > 1
            ? boards[index + 1 < boards.count ? index + 1 : index - 1].id
            : nil
        undoable(String(localized: "Delete Board", comment: "Undo action name for deleting a board")) {
            boards.remove(at: index)
            for taskIndex in tasks.indices where tasks[taskIndex].boardID == id {
                tasks[taskIndex].placement = .inbox
                tasks[taskIndex].activity.insert(ActivityEntry(.unfiled), at: 0)
                touch(taskIndex)
            }
            if activeBoardID == id { activeBoardID = successor }
            detachSurfacesFromMissingColumns()
            scheduleSave()
        }
        return removed
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
        dot: Board.inboxDot, role: .backlog
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
