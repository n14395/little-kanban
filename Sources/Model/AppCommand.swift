import SwiftUI

/// Which menu a command sits in, and the heading it is listed under in the
/// keyboard-shortcuts sheet.
enum AppCommandGroup: String, CaseIterable, Identifiable, Sendable {
    case file, edit, view, task
    /// The column the keyboard is in, and what can be done to it — a menu of
    /// its own because a column is not a card and not the board either. Every
    /// item in it was reachable only from the ⋯ on a column header, which is a
    /// control that has to be found with a pointer.
    case column
    /// The board's own keys — focus movement, ⌘C/⌘V, Select All. These get no
    /// menu item: a Copy on the Edit menu takes ⌘C away from every text field
    /// in the app, and Select All takes ⌘A. They are taught by the sheet and
    /// handled where the board has focus.
    case board
    case help

    var id: String { rawValue }

    /// Whether the menu bar builds a menu for this group at all.
    var hasMenu: Bool { self != .board }

    var title: String {
        switch self {
        case .file: String(localized: "File", comment: "Menu title, and a heading in the shortcuts sheet")
        case .edit: String(localized: "Edit", comment: "Menu title, and a heading in the shortcuts sheet")
        case .view: String(localized: "View", comment: "Menu title, and a heading in the shortcuts sheet")
        case .task: String(localized: "Task", comment: "Menu title, and a heading in the shortcuts sheet")
        case .column: String(localized: "Column", comment: "Menu title, and a heading in the shortcuts sheet")
        case .board: String(localized: "Board", comment: "Heading in the shortcuts sheet for the keys the board itself handles")
        case .help: String(localized: "Help", comment: "Menu title, and a heading in the shortcuts sheet")
        }
    }
}

/// The block of the menu bar an item is declared into.
///
/// A group is the menu; a section is one divider-separated block of it. The
/// File menu needs two because macOS puts New and Import… in different parts of
/// it and SwiftUI has a separate placement for each, and the Task menu keeps
/// filing a card away apart from editing it. The View menu keeps ``savedView``
/// apart for the same kind of reason: showing and hiding a panel is not the
/// same act as editing the saved view you are standing in.
///
/// `BoardCommands` renders one section per placement by iterating
/// ``AppCommand/menuItems(in:)``, so the menu bar is generated from this
/// vocabulary rather than transcribed from it: an item cannot be lost or gained
/// there without the enum saying so.
enum AppMenuSection: String, CaseIterable, Identifiable, Sendable {
    case new, importExport, file, app, edit
    case view, savedView, viewOptions, navigate
    case task, filing, column, help

    var id: String { rawValue }
}

/// Which machine is asking.
///
/// The vocabulary is one list on both platforms — every command in it means the
/// same thing on a desk and on an iPad, and the shortcuts sheet prints the same
/// rows — but two of them exist on one platform only: the desk's Settings… is
/// the system's own item on the app menu and ours would be a second, and the
/// theme browser is a **window**, which is a thing an iPad's Settings sheet
/// carries a row for instead.
///
/// Named rather than written as `#if os(macOS)` at each site so that a test can
/// ask for both answers on either machine — a menu that is wrong on the platform
/// you are not building for is exactly the drift nothing notices.
enum AppPlatform: String, CaseIterable, Sendable {
    case desk, touch

    static var current: AppPlatform {
        #if os(macOS)
        .desk
        #else
        .touch
        #endif
    }
}

/// Who performs a command, which is what the menu bar has to know to avoid
/// declaring an item twice or promising one that does not work yet.
enum AppCommandSource: Sendable {
    /// The app: the menu declares the item and a surface performs it.
    case app
    /// The system already provides both the item and the key — `UndoManager`
    /// puts Undo and Redo on the Edit menu on its own. Declaring them again
    /// would put two of each there. Listed here so the sheet is complete.
    case system
    /// Named but not yet built. The menu draws it disabled, so the vocabulary
    /// is whole and the gap is visible rather than silently absent. Nothing is
    /// in this state now that Import… and Export… are wired; the case stays
    /// because the next unbuilt item should be declared rather than omitted,
    /// and because `ShortcutsSheet` and `ShortcutTests` already know how to
    /// account for one.
    case unbuilt
}

/// A key, named rather than borrowed from `KeyEquivalent`, so the sheet can
/// print it. `KeyEquivalent` holds the character SwiftUI needs and nothing a
/// person can read: `.leftArrow` is U+F702, which renders as nothing at all.
enum AppKey: Hashable, Sendable {
    case character(Character)
    case leftArrow, rightArrow, upArrow, downArrow
    case `return`, space, delete, escape

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .character(let character): KeyEquivalent(character)
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .return: .return
        case .space: .space
        case .delete: .delete
        case .escape: .escape
        }
    }

    /// What the sheet prints. Upper case for letters, matching every menu on
    /// the system — ⌘N is written ⌘N whether or not shift is held.
    var display: String {
        switch self {
        case .character(let character): String(character).uppercased()
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .return: "↩"
        case .space: String(localized: "Space", comment: "The space bar, named in the keyboard-shortcuts sheet")
        case .delete: "⌫"
        case .escape: "⎋"
        }
    }
}

/// The modifiers, as this app's own option set rather than SwiftUI's, for
/// `AppKey`'s reason: `EventModifiers` cannot print itself.
struct AppModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let command = AppModifiers(rawValue: 1 << 0)
    static let shift = AppModifiers(rawValue: 1 << 1)
    static let option = AppModifiers(rawValue: 1 << 2)
    static let control = AppModifiers(rawValue: 1 << 3)

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if contains(.command) { result.insert(.command) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.option) { result.insert(.option) }
        if contains(.control) { result.insert(.control) }
        return result
    }

    /// ⌃⌥⇧⌘ in that order, which is the order the system writes them in and so
    /// the order a user recognises at a glance.
    var display: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

/// One key press.
struct AppShortcut: Hashable, Sendable {
    var key: AppKey
    var modifiers: AppModifiers = []

    init(_ key: AppKey, _ modifiers: AppModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// A character key, which is most of them: `.init("n", .command)`.
    init(_ character: Character, _ modifiers: AppModifiers = []) {
        self.init(.character(character), modifiers)
    }

    /// What the sheet prints, and what `.help()` can show beside a button.
    var display: String { modifiers.display + key.display }

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(key.keyEquivalent, modifiers: modifiers.eventModifiers)
    }
}

/// Every command the app can be asked for by name: the menu bar's items, the
/// board's key handlers and the keyboard-shortcuts sheet, from one list.
///
/// Three surfaces could otherwise disagree about what a key does, and a sheet
/// claiming a shortcut the menu does not have is worse than no sheet at all. So
/// the title, the keys, the menu and whether the command needs a selection are
/// stated here once and read from here by all three.
///
/// Two things are deliberately not here. The *contents* of a submenu — the
/// columns under Move to Column, the priorities, the saved views and boards
/// under View — belong to the store and change as the user works; the enum
/// names the anchor and the menu fills it. And the *doing*: a command is a name
/// and a key, and which store call it makes is the surface's business, because
/// the same command means the selection on macOS and the open sheet's task on
/// iOS.
///
/// **⌘N is New Task and ⇧⌘N is New Board.** It used to sit on a toolbar button
/// while the default File menu still advertised ⌘N as New Window, so the menu
/// and the key disagreed about what the app did. Replacing SwiftUI's `.newItem`
/// group with these two is what settles it.
enum AppCommand: String, CaseIterable, Identifiable, Sendable {
    case newTask, newBoard, newColumn, newView
    case importBoard, exportBoard, exportMarkdown
    case boardSettings, saveBoard, syncNow, revealBoardFile, restoreBackup, settings
    case undo, redo, trashTask, emptyTrash, find
    case toggleInspector, toggleSidebar, toggleInbox
    case showTrash, manageLabels, themes
    case editView, duplicateView, deleteView, restoreBuiltInViews
    case appearance, cardDensity, sortOrder
    case previousBoard, nextBoard, moveBoardUp, moveBoardDown
    case completeTask, reopenTask, moveToColumn, moveToBoard, setPriority, setLabels
    case setDueDate, showInBoard, copyLink, openTask
    case archiveTask, unarchiveTask, archiveCompleted, archiveInboxCompleted
    case editColumn, moveColumnLeft, moveColumnRight, trashColumn
    case copyTask, pasteTask, selectAll, deselect
    case focusPreviousColumn, focusNextColumn, focusCardAbove, focusCardBelow
    case moveCardLeft, moveCardRight
    case shortcuts

    var id: String { rawValue }

    var group: AppCommandGroup {
        switch self {
        case .newTask, .newBoard, .newColumn, .newView, .importBoard, .exportBoard,
             .exportMarkdown, .boardSettings, .saveBoard, .syncNow, .revealBoardFile,
             .restoreBackup, .settings: .file
        case .undo, .redo, .trashTask, .emptyTrash, .find: .edit
        case .toggleInspector, .toggleSidebar, .toggleInbox, .showTrash, .manageLabels,
             .themes, .editView, .duplicateView, .deleteView, .restoreBuiltInViews,
             .appearance, .cardDensity, .sortOrder,
             .previousBoard, .nextBoard, .moveBoardUp, .moveBoardDown: .view
        case .completeTask, .reopenTask, .moveToColumn, .moveToBoard, .setPriority,
             .setLabels, .setDueDate, .showInBoard, .copyLink, .openTask,
             .archiveTask, .unarchiveTask, .archiveCompleted, .archiveInboxCompleted: .task
        case .editColumn, .moveColumnLeft, .moveColumnRight, .trashColumn: .column
        case .copyTask, .pasteTask, .selectAll, .deselect,
             .focusPreviousColumn, .focusNextColumn, .focusCardAbove, .focusCardBelow,
             .moveCardLeft, .moveCardRight: .board
        case .shortcuts: .help
        }
    }

    var source: AppCommandSource {
        switch self {
        case .undo, .redo: .system
        default: .app
        }
    }

    /// Which machines draw this item.
    ///
    /// Two commands are one platform's only, and both for the same kind of
    /// reason — the system already has the item, or the thing it opens does not
    /// exist there:
    ///
    /// - **Settings…** is the desk's app menu's own, put there by SwiftUI's
    ///   `Settings` scene along with ⌘, . An item of ours would be a second one
    ///   beside it. The iPad has no such scene — Settings is a sheet raised by
    ///   `BoardStore.isShowingSettings` — so there the app must offer it.
    /// - **Themes…** opens a `Window`, which iPadOS has no equivalent of; the
    ///   iPad reaches the browser through Settings ▸ Appearance instead.
    /// - **Reveal Board File in Finder** opens the Finder, which is a thing one
    ///   machine has. iPadOS shows the path in Settings instead and cannot open
    ///   anything at it, so an item there would be a promise nothing can keep.
    /// - **Toggle Sidebar** is UIKit's on the iPad. A `NavigationSplitView` is a
    ///   `UISplitViewController` there, and the system puts *Show Sidebar* —
    ///   ⌃⌘S, `toggleSidebar:` — on the View menu for it. The column moves
    ///   either way, and `PadRootView` reads the movement back onto
    ///   ``AppWindowState/isSidebarVisible``, so the menu items that need the
    ///   list out still get it out. The desk has no such item, and its source
    ///   list is an `HStack`'s first child rather than a split view column.
    ///
    /// **Three, and each of them because the platform already has the item.**
    /// That is not a style rule: a second item on the same key is a `UIKeyCommand`
    /// collision, and UIKit answers one by throwing while it builds the menu —
    /// the app terminates on launch, before any window appears. Both of the
    /// touch platform's exclusions here were found that way.
    var platforms: Set<AppPlatform> {
        switch self {
        case .settings: [.touch]
        case .themes, .toggleSidebar, .revealBoardFile: [.desk]
        default: Set(AppPlatform.allCases)
        }
    }

    /// Whether the command is aimed at a task at all. The coarse half of
    /// ``isEnabled(for:in:)``, which is what a menu item asks — on its own this
    /// knows only that *something* must be selected, and not that Complete Task
    /// means nothing to a card already in Done or that most of the Task menu
    /// means nothing to a card in the Archive.
    var needsSelection: Bool {
        switch self {
        case .trashTask, .completeTask, .reopenTask, .moveToColumn, .moveToBoard,
             .setPriority, .setLabels, .setDueDate, .showInBoard, .copyLink,
             .archiveTask, .unarchiveTask,
             .copyTask, .deselect, .openTask, .moveCardLeft, .moveCardRight:
            true
        default:
            false
        }
    }

    /// Whether the command is aimed at a **column** rather than at a card — the
    /// one holding the focused card, which is the only column the app can name
    /// without a pointer over it.
    ///
    /// Its own question rather than a case of ``needsSelection`` because the two
    /// disable on different things: a column command is live with nothing
    /// selected as long as the keyboard is somewhere on the board, and dead on
    /// the Archive and in a saved view, where the cards on screen are not a
    /// column's.
    var needsColumn: Bool {
        switch self {
        case .editColumn, .moveColumnLeft, .moveColumnRight, .trashColumn: true
        default: false
        }
    }

    /// Whether the command acts on every selected card rather than on one, and
    /// so has a plural title to offer.
    var actsOnWholeSelection: Bool {
        switch self {
        case .trashTask, .completeTask, .reopenTask, .moveToColumn, .moveToBoard,
             .setPriority, .setLabels, .setDueDate, .archiveTask, .unarchiveTask, .copyTask:
            true
        default:
            false
        }
    }

    /// Whether this command can do anything to `task`.
    ///
    /// A card in the Archive is off the board: moving it to a column or a board,
    /// giving it a priority or a due date all silently edit something the user is
    /// looking at as a record, and completing or filing it again is a no-op.
    /// Being selected is not the same as being a fit subject, and this is the
    /// difference.
    ///
    /// Asked of the store rather than of the task alone because the answers are
    /// the board's, not the card's — which column counts as Done, and whether
    /// this card's board has one at all — and because the ones the store already
    /// answers for itself are asked of it here rather than written out a second
    /// time.
    @MainActor
    func applies(to task: TaskItem, in store: BoardStore) -> Bool {
        switch self {
        case .completeTask:
            // The store's own question, asked of the store: `complete(_:)` acts
            // on this answer, so the item is live exactly when it works.
            store.canComplete(task.id)
        case .reopenTask:
            store.canReopen(task.id)
        case .archiveTask:
            store.canArchive(task.id)
        case .unarchiveTask:
            store.canUnarchive(task.id)
        case .moveToColumn, .moveToBoard, .setPriority, .setLabels, .setDueDate, .showInBoard,
             .moveCardLeft, .moveCardRight:
            !task.isArchived
        case .trashTask, .copyTask, .copyLink, .deselect, .openTask:
            // All five read or dispose of a card wherever it is, the Archive
            // included: a filed card can still be opened, copied, linked to and
            // deleted.
            true
        case .newTask, .newBoard, .newColumn, .newView, .importBoard, .exportBoard,
             .exportMarkdown, .boardSettings, .saveBoard, .syncNow, .revealBoardFile,
             .restoreBackup, .settings, .undo, .redo, .emptyTrash, .find,
             .toggleInspector, .toggleSidebar, .toggleInbox, .showTrash, .manageLabels,
             .themes, .editView, .duplicateView, .deleteView, .restoreBuiltInViews,
             .appearance, .cardDensity, .sortOrder,
             .previousBoard, .nextBoard, .moveBoardUp, .moveBoardDown,
             .archiveCompleted, .archiveInboxCompleted,
             .editColumn, .moveColumnLeft, .moveColumnRight, .trashColumn,
             .pasteTask, .selectAll,
             .focusPreviousColumn, .focusNextColumn, .focusCardAbove, .focusCardBelow,
             .shortcuts:
            // Not aimed at a task at all.
            true
        }
    }

    /// What the *board* has to be for this item to be live, for the commands
    /// that are aimed at something other than a card.
    ///
    /// The same rule the Task menu follows, one level up: an item that cannot do
    /// anything must disable rather than no-op silently. New Column on a board
    /// that is not there has nowhere to add one; Sync Now with sync switched off
    /// would spin and adopt nothing; Next Board on a one-board install is a
    /// press that changes nothing.
    @MainActor
    func isAvailable(in store: BoardStore) -> Bool {
        switch self {
        case .newColumn, .boardSettings, .editColumn:
            store.activeBoard != nil
        case .syncNow:
            store.isSyncing
        case .previousBoard, .nextBoard:
            store.boards.count > 1
        // The board file is where the Finder would be sent, and an in-memory
        // board — a test's, a preview's — has none.
        case .revealBoardFile:
            store.boardFileURL != nil
        // Each of these three empties or files away a list, and an empty list is
        // nothing to act on. The counts are the same ones the surfaces that
        // already offer these items put in their titles.
        case .emptyTrash:
            store.trashCount > 0
        case .archiveCompleted:
            store.completedCount > 0
        case .archiveInboxCompleted:
            store.inboxCompletedCount > 0
        // The three that act on the saved view you are standing in, which is
        // nothing at all while the board is on screen.
        case .editView, .duplicateView, .deleteView:
            store.activeView != nil
        // Offered only where something is actually missing, so the menu does not
        // carry a permanently dead row on the installs that never deleted a view
        // — the same condition the source list's own row is drawn under.
        case .restoreBuiltInViews:
            store.isMissingSeededViews
        case .moveBoardUp:
            Self.boardIndex(in: store).map { $0 > 0 } ?? false
        case .moveBoardDown:
            Self.boardIndex(in: store).map { $0 < store.boards.count - 1 } ?? false
        default:
            true
        }
    }

    /// Where the board on screen sits in the list the source list draws, which
    /// is what Move Up and Move Down move it through.
    @MainActor
    private static func boardIndex(in store: BoardStore) -> Int? {
        store.boards.firstIndex { $0.id == store.activeBoardID }
    }

    /// Whether a column command can do anything to `id` — the column holding
    /// the focused card, or `nil` while the keyboard is not on the board.
    ///
    /// The rules are the column header's own menu's, said here instead of a
    /// second time: Move Left is dead on the first column and on Done, which is
    /// the board's last and does not move; Move Right is dead on the one before
    /// Done, which is as far right as a working column goes. `moveColumn`
    /// refuses and clamps the same two cases — these grey out rather than
    /// no-op, because an item that can be pressed and does nothing is
    /// indistinguishable from a bug.
    @MainActor
    func isEnabled(forColumn id: BoardColumn.ID?, in store: BoardStore) -> Bool {
        guard needsColumn else { return true }
        guard let id, let index = store.columns.firstIndex(where: { $0.id == id }) else { return false }
        switch self {
        case .moveColumnLeft: return index > 0 && !store.isDone(column: id)
        case .moveColumnRight: return index < store.columns.count - 2
        default: return true
        }
    }

    /// Whether a menu item for this command is live for the cards it would act
    /// on — the selection, or the focused card and whatever it brings with it.
    ///
    /// Live when *any* of them can accept it, and the surface then acts on that
    /// subset: a mixed selection offers what it can do rather than nothing. The
    /// rule the menu bar follows is that an item that cannot do anything must
    /// **disable** rather than no-op silently, and "cannot do anything" is a
    /// question about these cards, not about whether the set is empty.
    @MainActor
    func isEnabled(for tasks: [TaskItem], in store: BoardStore) -> Bool {
        guard source != .unbuilt else { return false }
        guard isAvailable(in: store) else { return false }
        guard needsSelection else { return true }
        return tasks.contains { applies(to: $0, in: store) }
    }

    /// Whether it opens a submenu rather than doing something itself. The rows
    /// underneath come from the store or from the preferences — the board's
    /// columns, the boards themselves, the priorities, the three appearances.
    var opensSubmenu: Bool {
        switch self {
        case .moveToColumn, .moveToBoard, .setPriority, .setLabels,
             .appearance, .cardDensity, .sortOrder:
            true
        default:
            false
        }
    }

    /// Whether the `.commands` block declares this item itself, on any machine.
    var isMenuItem: Bool { group.hasMenu && source != .system }

    /// Whether *this* machine's menu bar declares it. See ``platforms``.
    func isMenuItem(on platform: AppPlatform) -> Bool {
        isMenuItem && platforms.contains(platform)
    }

    /// Which block of the menu bar declares it, or `nil` for the commands the
    /// menu bar does not declare at all: the board's own keys, and the two the
    /// system puts on the Edit menu itself.
    ///
    /// Exhaustive on purpose. A command added to the vocabulary has to answer
    /// this before it compiles, which is the moment to decide which menu it
    /// belongs on — and the menu bar draws whatever this says, so an item
    /// cannot be silently absent from it.
    var menuSection: AppMenuSection? {
        switch self {
        case .newTask, .newBoard, .newColumn, .newView: .new
        case .importBoard, .exportBoard, .exportMarkdown: .importExport
        case .boardSettings, .saveBoard, .syncNow, .revealBoardFile, .restoreBackup: .file
        case .settings: .app
        case .trashTask, .emptyTrash, .find: .edit
        case .toggleInspector, .toggleSidebar, .toggleInbox, .showTrash, .manageLabels, .themes: .view
        case .editView, .duplicateView, .deleteView, .restoreBuiltInViews: .savedView
        case .appearance, .cardDensity, .sortOrder: .viewOptions
        case .previousBoard, .nextBoard, .moveBoardUp, .moveBoardDown: .navigate
        case .completeTask, .reopenTask, .moveToColumn, .moveToBoard, .setPriority,
             .setLabels, .setDueDate, .showInBoard, .copyLink, .openTask: .task
        case .archiveTask, .unarchiveTask, .archiveCompleted, .archiveInboxCompleted: .filing
        case .editColumn, .moveColumnLeft, .moveColumnRight, .trashColumn: .column
        case .shortcuts: .help
        case .undo, .redo, .copyTask, .pasteTask, .selectAll, .deselect,
             .focusPreviousColumn, .focusNextColumn, .focusCardAbove, .focusCardBelow,
             .moveCardLeft, .moveCardRight:
            nil
        }
    }

    /// The keys, in order of prominence: a menu shows the first, the sheet shows
    /// them all, and a key handler matches any of them. Only completion has two
    /// — ⌘⏎ from the menu, and Space on a card that has focus.
    var shortcuts: [AppShortcut] {
        switch self {
        case .newTask: [AppShortcut("n", .command)]
        case .newBoard: [AppShortcut("n", [.command, .shift])]
        case .newColumn: [AppShortcut("n", [.command, .option])]
        // **⌃⌘N is not free.** `MenuBarQuickAdd` is documented — and the seed
        // board's own card `t8` promises — as the quick-add key, and a menu item
        // that took it would be the app disagreeing with itself in writing. A
        // fourth New item is not worth the last N in the alphabet of modifiers.
        case .newView,
             .importBoard, .exportBoard, .exportMarkdown, .restoreBackup,
             .themes, .setDueDate, .archiveTask, .unarchiveTask,
             .archiveCompleted, .archiveInboxCompleted,
             .editView, .duplicateView, .deleteView, .restoreBuiltInViews,
             .moveBoardUp, .moveBoardDown, .editColumn, .trashColumn,
             .moveToColumn, .moveToBoard, .setPriority, .setLabels,
             .appearance, .cardDensity, .sortOrder:
            []
        case .boardSettings: [AppShortcut(",", [.command, .shift])]
        case .saveBoard: [AppShortcut("s", .command)]
        case .syncNow: [AppShortcut("r", .command)]
        case .revealBoardFile: [AppShortcut("r", [.command, .shift])]
        // The key the desk's own Settings… already carries, claimed here for the
        // platform that has no such item to inherit it from.
        case .settings: [AppShortcut(",", .command)]
        case .undo: [AppShortcut("z", .command)]
        case .redo: [AppShortcut("z", [.command, .shift])]
        case .trashTask: [AppShortcut(.delete, .command)]
        // The Finder's own pairing, and the same one one step along: ⌘⌫ throws
        // this away, ⇧⌘⌫ throws away what has already been thrown away.
        case .emptyTrash: [AppShortcut(.delete, [.command, .shift])]
        case .find: [AppShortcut("f", .command)]
        case .toggleInspector: [AppShortcut("i", [.command, .option])]
        case .toggleSidebar: [AppShortcut("s", [.command, .control])]
        case .toggleInbox: [AppShortcut("i", [.command, .shift])]
        case .showTrash: [AppShortcut("t", [.command, .shift])]
        case .manageLabels: [AppShortcut("l", [.command, .shift])]
        case .previousBoard: [AppShortcut(.upArrow, [.command, .option])]
        case .nextBoard: [AppShortcut(.downArrow, [.command, .option])]
        case .completeTask: [AppShortcut(.return, .command), AppShortcut(.space)]
        case .reopenTask: [AppShortcut(.return, [.command, .shift])]
        case .showInBoard: [AppShortcut("j", .command)]
        // ⌘C is the board's own copy — the card, as text. This is the other
        // thing there is to copy off a card, so it takes the same letter under
        // a different modifier rather than a letter of its own.
        case .copyLink: [AppShortcut("c", [.command, .control])]
        // A column moves under the same arrows a card does, one modifier along.
        case .moveColumnLeft: [AppShortcut(.leftArrow, [.control, .option])]
        case .moveColumnRight: [AppShortcut(.rightArrow, [.control, .option])]
        case .copyTask: [AppShortcut("c", .command)]
        case .pasteTask: [AppShortcut("v", .command)]
        case .selectAll: [AppShortcut("a", .command)]
        case .deselect: [AppShortcut(.escape)]
        case .openTask: [AppShortcut(.return)]
        case .focusPreviousColumn: [AppShortcut(.leftArrow)]
        case .focusNextColumn: [AppShortcut(.rightArrow)]
        case .focusCardAbove: [AppShortcut(.upArrow)]
        case .focusCardBelow: [AppShortcut(.downArrow)]
        case .moveCardLeft: [AppShortcut(.leftArrow, .option)]
        case .moveCardRight: [AppShortcut(.rightArrow, .option)]
        case .shortcuts: [AppShortcut("/", .command)]
        }
    }

    /// What `.keyboardShortcut(_:)` takes. `nil` for the items that are menu
    /// entries without a key of their own.
    var keyboardShortcut: KeyboardShortcut? { shortcuts.first?.keyboardShortcut }

    /// The press the **menu item** claims, or `nil` for an item drawn without a
    /// key — which is every command with no key at all, and one that has one.
    ///
    /// Read by ``menuShortcut`` for the item itself and by
    /// `BoardKeyboard.menuOwnedShortcuts` for the other side of the same fact:
    /// a card must stand aside for a key the menu bar takes first, and must
    /// **not** stand aside for one it does not. Deriving both from here is what
    /// stops the second question being answered by the first's assumption.
    var menuPress: AppShortcut? {
        self == .openTask ? nil : shortcuts.first
    }

    /// The key the **menu item** carries, which is ``keyboardShortcut`` for
    /// every command but one.
    ///
    /// **Open Task's ↩ cannot go on a menu.** ↩ where the board has focus is one
    /// thing; ↩ on a menu item is ↩ *everywhere*, because a menu key equivalent
    /// is offered the press before the responder chain ever sees it — so the
    /// item would take Return out of every text field in the app, the composer
    /// and the card's own title among them. It is the `.board` group's bargain
    /// one step along: those commands keep the key and give up the item, and
    /// this one keeps the item and gives up the key. The sheet goes on teaching
    /// ↩ either way, and the board goes on handling it.
    var menuShortcut: KeyboardShortcut? { menuPress?.keyboardShortcut }

    var title: String {
        switch self {
        case .newTask:
            String(localized: "New Task", comment: "File menu item that opens the inline task composer")
        case .newBoard:
            String(localized: "New Board", comment: "File menu item that adds a board")
        case .newColumn:
            String(localized: "New Column…", comment: "File menu item that opens board settings with the add-column field open")
        case .newView:
            String(localized: "New View…", comment: "File menu item that adds a saved view and opens its editor")
        case .importBoard:
            String(localized: "Import…", comment: "File menu item that reads a board in from a file")
        case .exportBoard:
            String(localized: "Export…", comment: "File menu item that writes the board out to a file")
        case .exportMarkdown:
            String(localized: "Export as Markdown…", comment: "File menu item that writes the board out as text")
        case .boardSettings:
            String(localized: "Board Settings…", comment: "File menu item that opens this board's columns and name")
        case .saveBoard:
            String(localized: "Save Board", comment: "File menu item that writes the board out now rather than on the debounce")
        case .syncNow:
            String(localized: "Sync Now", comment: "File menu item that sends this device's changes to iCloud and takes in the other devices'")
        case .revealBoardFile:
            String(localized: "Reveal in Finder", comment: "File menu item that opens the board's folder in the Finder")
        case .restoreBackup:
            String(localized: "Restore from a Backup…", comment: "File menu item that lists the rolling backups to put one back")
        case .settings:
            String(localized: "Settings…", comment: "Menu item that opens the app's settings, on the platforms where the system does not provide one")
        case .undo:
            String(localized: "Undo", comment: "Edit menu item, provided by the system")
        case .redo:
            String(localized: "Redo", comment: "Edit menu item, provided by the system")
        case .trashTask:
            String(localized: "Trash Task", comment: "Edit menu item that puts the selected task in the trash")
        case .emptyTrash:
            String(localized: "Empty Trash…", comment: "Edit menu item that permanently deletes everything in the trash")
        case .find:
            String(localized: "Find", comment: "Edit menu item that puts the cursor in the search field")
        case .toggleInspector:
            String(localized: "Toggle Inspector", comment: "View menu item that shows or hides the detail panel")
        case .toggleSidebar:
            String(localized: "Toggle Sidebar", comment: "View menu item that shows or hides the board list")
        case .toggleInbox:
            String(localized: "Toggle Inbox", comment: "View menu item that shows or hides the Inbox panel beside the board")
        case .showTrash:
            String(localized: "Show Trash", comment: "View menu item that opens the trash")
        case .manageLabels:
            String(localized: "Labels…", comment: "View menu item that opens the label manager")
        case .themes:
            String(localized: "Themes…", comment: "View menu item that opens the theme browser window")
        case .editView:
            String(localized: "Edit View…", comment: "View menu item that opens the rules of the saved view on screen")
        case .duplicateView:
            String(localized: "Duplicate View", comment: "View menu item that copies the saved view on screen")
        case .deleteView:
            String(localized: "Delete View", comment: "View menu item that deletes the saved view on screen")
        case .restoreBuiltInViews:
            String(localized: "Restore Built-in Views", comment: "View menu item that puts back the saved views the app ships with")
        case .appearance:
            String(localized: "Appearance", comment: "View submenu listing light, dark and system")
        case .cardDensity:
            String(localized: "Card Size", comment: "View submenu listing the card densities")
        case .sortOrder:
            String(localized: "Sort By", comment: "View submenu listing the orders a column can be drawn in")
        case .previousBoard:
            String(localized: "Previous Board", comment: "View menu item that opens the board above this one in the sidebar")
        case .nextBoard:
            String(localized: "Next Board", comment: "View menu item that opens the board below this one in the sidebar")
        case .moveBoardUp:
            String(localized: "Move Board Up", comment: "View menu item that moves this board one place up the sidebar")
        case .moveBoardDown:
            String(localized: "Move Board Down", comment: "View menu item that moves this board one place down the sidebar")
        case .completeTask:
            String(localized: "Complete Task", comment: "Task menu item that sends the selected task to Done")
        case .reopenTask:
            String(localized: "Reopen Task", comment: "Task menu item that takes a completed task back out of Done")
        case .moveToColumn:
            String(localized: "Move to Column", comment: "Task submenu listing the board's columns")
        case .moveToBoard:
            String(localized: "Move to Board", comment: "Task submenu listing the Inbox and the boards")
        case .setPriority:
            String(localized: "Set Priority", comment: "Task submenu listing the priorities")
        case .setLabels:
            String(localized: "Set Labels", comment: "Task submenu listing the board's labels, each of which can be put on or taken off")
        case .setDueDate:
            String(localized: "Set Due Date…", comment: "Task menu item that opens the due-date picker")
        case .showInBoard:
            String(localized: "Show in Board", comment: "Task menu item that goes to where the task lives and reveals it")
        case .archiveTask:
            String(localized: "Archive Task", comment: "Task menu item that files the selected task away")
        case .copyLink:
            String(localized: "Copy Link", comment: "Task menu item that puts the task's cardstock:// link on the pasteboard")
        case .unarchiveTask:
            String(localized: "Restore Task", comment: "Task menu item that takes a task back out of the archive")
        case .archiveCompleted:
            String(localized: "Archive Completed", comment: "Task menu item that files away every finished task in the board's Done column")
        case .archiveInboxCompleted:
            String(localized: "Archive Completed in Inbox", comment: "Task menu item that files away every ticked capture in the Inbox")
        case .editColumn:
            String(localized: "Edit Column…", comment: "Column menu item that opens the focused column's name, colour and limit")
        case .moveColumnLeft:
            String(localized: "Move Left", comment: "Column menu item that moves the focused column one place left")
        case .moveColumnRight:
            String(localized: "Move Right", comment: "Column menu item that moves the focused column one place right")
        case .trashColumn:
            String(localized: "Trash Column", comment: "Column menu item that puts the focused column in the trash")
        case .copyTask:
            String(localized: "Copy", comment: "Copies the selected task's code and title to the pasteboard")
        case .pasteTask:
            String(localized: "Paste", comment: "Makes a task from the plain text on the pasteboard")
        case .selectAll:
            String(localized: "Select All", comment: "Selects every task on the surface being looked at")
        case .deselect:
            String(localized: "Deselect", comment: "Clears the selection")
        case .openTask:
            String(localized: "Open Task", comment: "Opens the focused card's detail surface")
        case .focusPreviousColumn:
            String(localized: "Focus Previous Column", comment: "Moves card focus one column left")
        case .focusNextColumn:
            String(localized: "Focus Next Column", comment: "Moves card focus one column right")
        case .focusCardAbove:
            String(localized: "Focus Card Above", comment: "Moves card focus up within a column")
        case .focusCardBelow:
            String(localized: "Focus Card Below", comment: "Moves card focus down within a column")
        case .moveCardLeft:
            String(localized: "Move Card Left", comment: "Moves the focused card to the previous column")
        case .moveCardRight:
            String(localized: "Move Card Right", comment: "Moves the focused card to the next column")
        case .shortcuts:
            String(localized: "Keyboard Shortcuts", comment: "Help menu item that opens the shortcuts sheet")
        }
    }

    /// The title for a selection of `count` cards, so a menu item aimed at three
    /// of them says so rather than promising to delete one and taking all three.
    ///
    /// `count` only reaches this above one, so the plural is written out: there
    /// is no singular case here to get wrong.
    func title(selectionCount count: Int) -> String {
        guard count > 1, actsOnWholeSelection else { return title }
        switch self {
        case .trashTask:
            return String(localized: "Trash \(count) Tasks", comment: "Menu item that puts several selected tasks in the trash")
        case .completeTask:
            return String(localized: "Complete \(count) Tasks", comment: "Menu item that completes several selected tasks")
        case .reopenTask:
            return String(localized: "Reopen \(count) Tasks", comment: "Menu item that takes several completed tasks back out of Done")
        case .archiveTask:
            return String(localized: "Archive \(count) Tasks", comment: "Menu item that archives several selected tasks")
        case .unarchiveTask:
            return String(localized: "Restore \(count) Tasks", comment: "Menu item that takes several tasks back out of the archive")
        case .copyTask:
            return String(localized: "Copy \(count) Tasks", comment: "Menu item that copies several selected tasks")
        default:
            // The submenus and Set Due Date read the same whatever they are
            // aimed at.
            return title
        }
    }

    static func commands(in group: AppCommandGroup) -> [AppCommand] {
        allCases.filter { $0.group == group }
    }

    /// The commands of one menu that `platform` has at all — what the shortcuts
    /// sheet prints, so that a machine is never taught a key it does not carry.
    static func commands(in group: AppCommandGroup, on platform: AppPlatform) -> [AppCommand] {
        commands(in: group).filter { $0.platforms.contains(platform) }
    }

    /// The items one block of the menu bar declares, in the order the menu draws
    /// them. `BoardCommands` renders exactly this and nothing else.
    static func menuItems(in section: AppMenuSection,
                          on platform: AppPlatform = .current) -> [AppCommand] {
        allCases.filter { $0.menuSection == section && $0.platforms.contains(platform) }
    }

    /// Every group that has anything to list, in menu order — what the shortcuts
    /// sheet walks.
    static var groups: [AppCommandGroup] {
        AppCommandGroup.allCases.filter { group in allCases.contains { $0.group == group } }
    }
}
