import SwiftUI

/// Which menu a command sits in, and the heading it is listed under in the
/// keyboard-shortcuts sheet.
enum AppCommandGroup: String, CaseIterable, Identifiable, Sendable {
    case file, edit, view, task
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
/// filing a card away apart from editing it.
///
/// `BoardCommands` renders one section per placement by iterating
/// ``AppCommand/menuItems(in:)``, so the menu bar is generated from this
/// vocabulary rather than transcribed from it: an item cannot be lost or gained
/// there without the enum saying so.
enum AppMenuSection: String, CaseIterable, Identifiable, Sendable {
    case new, importExport, edit, view, task, filing, help

    var id: String { rawValue }
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
    /// and because `MacShortcutsSheet` and `ShortcutTests` already know how to
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
    case newTask, newBoard, importBoard, exportBoard
    case undo, redo, trashTask, find
    case toggleInspector, toggleSidebar
    case completeTask, moveToColumn, setPriority, setDueDate, archiveTask
    case copyTask, pasteTask, selectAll, deselect, openTask
    case focusPreviousColumn, focusNextColumn, focusCardAbove, focusCardBelow
    case moveCardLeft, moveCardRight
    case shortcuts

    var id: String { rawValue }

    var group: AppCommandGroup {
        switch self {
        case .newTask, .newBoard, .importBoard, .exportBoard: .file
        case .undo, .redo, .trashTask, .find: .edit
        case .toggleInspector, .toggleSidebar: .view
        case .completeTask, .moveToColumn, .setPriority, .setDueDate, .archiveTask: .task
        case .copyTask, .pasteTask, .selectAll, .deselect, .openTask,
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

    /// Whether the command is aimed at a task at all. The coarse half of
    /// ``isEnabled(for:in:)``, which is what a menu item asks — on its own this
    /// knows only that *something* must be selected, and not that Complete Task
    /// means nothing to a card already in Done or that the whole Task menu
    /// means nothing to a card in the Archive.
    var needsSelection: Bool {
        switch self {
        case .trashTask, .completeTask, .moveToColumn, .setPriority, .setDueDate,
             .archiveTask, .copyTask, .deselect, .openTask, .moveCardLeft, .moveCardRight:
            true
        default:
            false
        }
    }

    /// Whether the command acts on every selected card rather than on one, and
    /// so has a plural title to offer.
    var actsOnWholeSelection: Bool {
        switch self {
        case .trashTask, .completeTask, .moveToColumn, .setPriority, .setDueDate,
             .archiveTask, .copyTask:
            true
        default:
            false
        }
    }

    /// Whether this command can do anything to `task`.
    ///
    /// A card in the Archive is off the board: moving it to a column, giving it
    /// a priority or a due date all silently edit something the user is looking
    /// at as a record, and completing or filing it again is a no-op. Being
    /// selected is not the same as being a fit subject, and this is the
    /// difference.
    ///
    /// Asked of the store rather than of the task alone because the answers are
    /// the board's, not the card's — which column counts as Done, and whether
    /// this card's board has one at all — and because the two the store already
    /// answers for itself are asked of it here rather than written out a second
    /// time.
    @MainActor
    func applies(to task: TaskItem, in store: BoardStore) -> Bool {
        switch self {
        case .completeTask:
            // The store's own question, asked of the store: `complete(_:)` acts
            // on this answer, so the item is live exactly when it works.
            store.canComplete(task.id)
        case .archiveTask:
            store.canArchive(task.id)
        case .moveToColumn, .setPriority, .setDueDate, .moveCardLeft, .moveCardRight:
            !task.isArchived
        case .trashTask, .copyTask, .deselect, .openTask:
            // All four read or dispose of a card wherever it is, the Archive
            // included: a filed card can still be opened, copied and deleted.
            true
        case .newTask, .newBoard, .importBoard, .exportBoard, .undo, .redo, .find,
             .toggleInspector, .toggleSidebar, .pasteTask, .selectAll,
             .focusPreviousColumn, .focusNextColumn, .focusCardAbove, .focusCardBelow,
             .shortcuts:
            // Not aimed at a task at all.
            true
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
        guard needsSelection else { return true }
        return tasks.contains { applies(to: $0, in: store) }
    }

    /// Whether it opens a submenu rather than doing something itself. The
    /// submenu's rows come from the store — the board's columns, the priorities.
    var opensSubmenu: Bool { self == .moveToColumn || self == .setPriority }

    /// Whether the `.commands` block declares this item itself.
    var isMenuItem: Bool { group.hasMenu && source != .system }

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
        case .newTask, .newBoard: .new
        case .importBoard, .exportBoard: .importExport
        case .trashTask, .find: .edit
        case .toggleInspector, .toggleSidebar: .view
        case .completeTask, .moveToColumn, .setPriority, .setDueDate: .task
        case .archiveTask: .filing
        case .shortcuts: .help
        case .undo, .redo, .copyTask, .pasteTask, .selectAll, .deselect, .openTask,
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
        case .importBoard, .exportBoard, .setDueDate, .archiveTask, .moveToColumn, .setPriority: []
        case .undo: [AppShortcut("z", .command)]
        case .redo: [AppShortcut("z", [.command, .shift])]
        case .trashTask: [AppShortcut(.delete, .command)]
        case .find: [AppShortcut("f", .command)]
        case .toggleInspector: [AppShortcut("i", [.command, .option])]
        case .toggleSidebar: [AppShortcut("s", [.command, .control])]
        case .completeTask: [AppShortcut(.return, .command), AppShortcut(.space)]
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

    var title: String {
        switch self {
        case .newTask:
            String(localized: "New Task", comment: "File menu item that opens the inline task composer")
        case .newBoard:
            String(localized: "New Board", comment: "File menu item that adds a board")
        case .importBoard:
            String(localized: "Import…", comment: "File menu item that reads a board in from a file")
        case .exportBoard:
            String(localized: "Export…", comment: "File menu item that writes the board out to a file")
        case .undo:
            String(localized: "Undo", comment: "Edit menu item, provided by the system")
        case .redo:
            String(localized: "Redo", comment: "Edit menu item, provided by the system")
        case .trashTask:
            String(localized: "Trash Task", comment: "Edit menu item that puts the selected task in the trash")
        case .find:
            String(localized: "Find", comment: "Edit menu item that puts the cursor in the search field")
        case .toggleInspector:
            String(localized: "Toggle Inspector", comment: "View menu item that shows or hides the detail panel")
        case .toggleSidebar:
            String(localized: "Toggle Sidebar", comment: "View menu item that shows or hides the board list")
        case .completeTask:
            String(localized: "Complete Task", comment: "Task menu item that sends the selected task to Done")
        case .moveToColumn:
            String(localized: "Move to Column", comment: "Task submenu listing the board's columns")
        case .setPriority:
            String(localized: "Set Priority", comment: "Task submenu listing the priorities")
        case .setDueDate:
            String(localized: "Set Due Date…", comment: "Task menu item that opens the due-date picker")
        case .archiveTask:
            String(localized: "Archive Task", comment: "Task menu item that files the selected task away")
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
        case .archiveTask:
            return String(localized: "Archive \(count) Tasks", comment: "Menu item that archives several selected tasks")
        case .copyTask:
            return String(localized: "Copy \(count) Tasks", comment: "Menu item that copies several selected tasks")
        default:
            // Move to Column, Set Priority and Set Due Date read the same
            // whatever they are aimed at.
            return title
        }
    }

    static func commands(in group: AppCommandGroup) -> [AppCommand] {
        allCases.filter { $0.group == group }
    }

    /// The items one block of the menu bar declares, in the order the menu draws
    /// them. `BoardCommands` renders exactly this and nothing else.
    static func menuItems(in section: AppMenuSection) -> [AppCommand] {
        allCases.filter { $0.menuSection == section }
    }

    /// Every group that has anything to list, in menu order — what the shortcuts
    /// sheet walks.
    static var groups: [AppCommandGroup] {
        AppCommandGroup.allCases.filter { group in allCases.contains { $0.group == group } }
    }
}
