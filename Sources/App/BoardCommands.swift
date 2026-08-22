#if os(macOS)

import SwiftUI

/// What one macOS window knows about itself that the board does not: whether
/// its sidebar is showing, which column has the keyboard, and the two things a
/// menu item asks of a view it cannot reach.
///
/// Session state like the store's own, and here rather than there because none
/// of it means anything on a phone and none of it is saved. Owned by the app so
/// the menu bar — which is outside every window's view tree — can read and
/// write it.
@MainActor
@Observable
final class MacWindowState {
    var isSidebarVisible = true

    /// The column holding the focused card, or `nil` while nothing on the board
    /// has focus. ⌘N adds to it: the composer has to open where the user is
    /// looking, and on a board scrolled right the leftmost column is not it.
    var focusedColumnID: BoardColumn.ID?

    /// The card the keyboard is on, written by the surface that draws it.
    ///
    /// The menu bar reads it because ⌘⌫ and ⌘⏎ are *its* keys: an item on the
    /// menu bar wins a press before a focused view ever sees it, so a card
    /// claiming them too would simply never run. The menu asks what the
    /// keyboard is on instead, and acts on that card's `commandTargets`.
    var focusedTaskID: TaskItem.ID?

    /// Set by File ▸ New Board and cleared by the sidebar when it opens its
    /// field. A board is named as it is made, and the field that names it is a
    /// row in a list the menu has no way to reach.
    var isNamingNewBoard = false

    /// Set by Task ▸ Set Due Date… and cleared by the sheet it opens. The
    /// ellipsis in that title is a promise that something appears to type into.
    var isPickingDueDate = false

    /// Which of the two app-menu items opened the About window. Check for
    /// Updates… promises a check, so the panel starts one rather than making the
    /// user ask twice; About promises nothing and does nothing. Session state
    /// like the rest of this, and none of it is saved.
    var aboutStartsCheck = false

    /// The cards that item was aimed at, handed to the sheet rather than worked
    /// out there a second time.
    ///
    /// The sheet read `store.selection`, which is not what the item acts on: ⎋
    /// clears the selection and leaves focus where it was, so the item stayed
    /// live — rightly, it is aimed at the focused card — opened a sheet titled
    /// "Due date", and Set did nothing at all. Two derivations of one rule is
    /// how a menu comes to promise what it will not do; there is one now, and it
    /// is `applicable(_:)`.
    var dueDateTargets: Set<TaskItem.ID> = []
}

/// The menu bar, **generated** from ``AppCommand`` rather than transcribed from
/// it: each placement draws `AppCommand.menuItems(in:)` for one section, and
/// one `perform(_:on:)` switch says what each of them does. Nothing here names an
/// item, so no item can be lost or gained here without the vocabulary saying
/// so, and a command added to the enum cannot compile until it has both a
/// section and an action.
///
/// Everything aimed at a card acts on ``targets`` — the focused card and
/// whatever it brings with it, or the selection when the board has no focus —
/// and is **disabled** when none of those cards can accept it. From the outside
/// a command that does nothing is a broken one, and "does nothing" is a
/// question about the cards, not about whether anything is selected at all: on
/// the Archive surface every item on the Task menu is aimed at a card that is
/// off the board.
///
/// Three groups are deliberately absent. Undo and Redo are `UndoManager`'s and
/// the system puts them on the Edit menu itself; declaring them here would put
/// two of each there. The `.board` commands — ⌘C, ⌘V, ⌘A, the arrows — get no
/// menu item either: a Copy item on the Edit menu takes ⌘C from every text
/// field in the app. They are handled where the board has focus and taught by
/// the sheet.
struct BoardCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    let store: BoardStore
    let window: MacWindowState

    private func openAbout(checking: Bool) {
        window.aboutStartsCheck = checking
        openWindow(id: SimpleKanbanApp.aboutWindowID)
    }

    var body: some Commands {
        // ⌘N belonged to New Window while the toolbar had quietly taken it for
        // New Task, so the menu and the key disagreed about what the app did.
        // Replacing the group is what settles it.
        CommandGroup(replacing: .newItem) { items(.new) }

        // Neither carries a key: both open a panel the user then has to answer,
        // so a shortcut would buy one keystroke and cost one of the few left.
        CommandGroup(replacing: .importExport) { items(.importExport) }

        CommandGroup(after: .pasteboard) {
            Divider()
            items(.edit)
        }

        CommandGroup(after: .sidebar) {
            items(.view)
            Divider()
            destinations
        }

        CommandMenu(AppCommandGroup.task.title) {
            items(.task)
            Divider()
            items(.filing)
        }

        // The two items that are about the *app* rather than about the board
        // or a card. They are not in ``AppCommand`` because that vocabulary is
        // the board's — everything in it is aimed at cards, counts them in its
        // title and goes dead when there are none — and because replacing
        // `.appInfo` is the only way to take the system's own About item away,
        // which has to happen for there to be one place the app talks about
        // itself rather than two that disagree.
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About Simple Kanban", comment: "App menu item")) {
                openAbout(checking: false)
            }
            Button(String(localized: "Check for Updates…", comment: "App menu item")) {
                openAbout(checking: true)
            }
        }

        // The default item leads to a help book this app does not have.
        CommandGroup(replacing: .help) { items(.help) }
    }

    // MARK: Items

    /// One block of the menu bar: every command the vocabulary declares into
    /// that section, in the order it declares them.
    private func items(_ section: AppMenuSection) -> some View {
        ForEach(AppCommand.menuItems(in: section)) { item($0) }
    }

    /// One command as a menu item: its title for the number of cards it will
    /// change, its first key, and disabled when that number is nought.
    ///
    /// All three come off ``applicable(_:)``, so the item cannot promise one
    /// thing and do another: a menu titled "Complete 3 Tasks" that files one
    /// undo step called "Complete Task" has lied about what it was going to do.
    @ViewBuilder
    private func item(_ command: AppCommand) -> some View {
        switch command {
        // The two anchors. Their rows are the store's and change as the user
        // works, so the enum names the anchor and the menu fills it.
        case .moveToColumn: columnRows
        case .setPriority: priorityRows
        default:
            let acting = applicable(command)
            Button(command.title(selectionCount: acting.count)) { perform(command, on: acting) }
                .keyboardShortcut(command.keyboardShortcut)
                .disabled(!command.isEnabled(for: targets, in: store))
        }
    }

    /// What every item does, in one switch rather than beside each declaration.
    /// Exhaustive on purpose: a command added to the vocabulary has to be given
    /// an answer here, and the menu that draws it is generated from the same
    /// enum, so the two cannot drift apart.
    private func perform(_ command: AppCommand, on ids: Set<TaskItem.ID>) {
        switch command {
        case .newTask: newTask()
        case .newBoard: newBoard()
        case .trashTask: trash(ids)
        case .find: store.focusSearch()
        case .toggleInspector: store.isInspectorOpen.toggle()
        case .toggleSidebar: window.isSidebarVisible.toggle()
        case .completeTask: store.complete(ids)
        case .setDueDate: pickDueDate(for: ids)
        case .archiveTask: store.archive(ids)
        case .shortcuts: store.isShowingShortcuts = true
        case .importBoard: store.isImportingBoard = true
        case .exportBoard: store.isExportingBoard = true
        case .moveToColumn, .setPriority:
            // Anchors: the rows underneath them are what act.
            break
        case .undo, .redo, .copyTask, .pasteTask, .selectAll, .deselect, .openTask,
             .focusPreviousColumn, .focusNextColumn, .focusCardAbove, .focusCardBelow,
             .moveCardLeft, .moveCardRight:
            // Not the menu bar's: the system's own two, and the keys the board
            // handles where it has focus.
            break
        }
    }

    // MARK: Targets

    /// The cards a menu item is aimed at: the focused card and whatever it
    /// brings with it, or the selection when nothing on the board has focus.
    ///
    /// Focus first because the menu bar owns ⌘⌫ and ⌘⏎ — AppKit offers a press
    /// to the menu before the focused view, so a card that claimed either would
    /// never see it. A focused card that has since gone falls back to the
    /// selection rather than aiming at nothing.
    private var targets: [TaskItem] {
        guard let focused = window.focusedTaskID, store[focused] != nil else {
            return store.selectedTasks
        }
        let ids = store.commandTargets(focused)
        return store.tasks.filter { ids.contains($0.id) }
    }

    /// The targets one command can actually do something to: what it acts on,
    /// what it counts in its title, and — by being empty or not — whether it is
    /// live at all.
    ///
    /// Filtered rather than passed whole: an item is live when *any* of the
    /// cards can accept it, and it must then leave the others alone. Moving a
    /// mixed selection would otherwise drag an archived card back onto the
    /// board behind the user's back.
    private func applicable(_ command: AppCommand) -> Set<TaskItem.ID> {
        Set(targets.filter { command.applies(to: $0, in: store) }.map(\.id))
    }

    // MARK: Submenus

    /// The columns of the board on screen. The column the cards are already in
    /// is ticked and dead: a row that would move a card to where it is does
    /// nothing, and an item that does nothing is a broken one.
    private var columnRows: some View {
        let ids = applicable(.moveToColumn)
        return Menu(AppCommand.moveToColumn.title) {
            ForEach(store.columns) { column in
                let isCurrent = every(ids) { $0.columnID == column.id }
                row(column.name, isCurrent: isCurrent) { store.move(ids, to: column.id) }
                    .disabled(isCurrent)
            }
        }
        // Empty exactly when `isEnabled` is false: both ask whether any of the
        // cards can accept the move.
        .disabled(ids.isEmpty || store.columns.isEmpty)
    }

    private var priorityRows: some View {
        let ids = applicable(.setPriority)
        return Menu(AppCommand.setPriority.title) {
            ForEach(Priority.allCases) { priority in
                let isCurrent = every(ids) { $0.priority == priority }
                row(priority.displayName, isCurrent: isCurrent) { store.setPriority(priority, on: ids) }
                    .disabled(isCurrent)
            }
        }
        .disabled(ids.isEmpty)
    }

    /// Whether every targeted card already answers to the row — which is what
    /// makes the row a statement of where they are rather than somewhere to go.
    /// A mixed selection is not "current" anywhere and every row stays live.
    private func every(_ ids: Set<TaskItem.ID>, _ predicate: (TaskItem) -> Bool) -> Bool {
        !ids.isEmpty && ids.allSatisfy { id in store[id].map(predicate) ?? false }
    }

    /// Where the main surface can point, under the two toggles: the board of
    /// the moment, the Inbox, the saved views, and the boards themselves. A
    /// tick marks where the user already is, the way every other destination
    /// list in this app marks it.
    @ViewBuilder
    private var destinations: some View {
        row(String(localized: "Board", comment: "View menu item for the column board"),
            isCurrent: store.surface == .board) {
            store.selectSurface(.board)
        }
        .disabled(store.activeBoard == nil)

        // The *panel*, which is a switch rather than a destination: it stands
        // beside the board, so there is nowhere to go to reach it. Named apart
        // from the Inbox view below it, which is a destination and does replace
        // the board — two rows called "Inbox" in one menu would be a coin toss.
        row(String(localized: "Inbox Panel",
                   comment: "View menu item that shows the Inbox beside the board"),
            isCurrent: store.isInboxOpen) {
            store.toggleInbox()
        }

        Divider()

        ForEach(SavedView.allCases) { view in
            row(view.label, isCurrent: store.activeView == view) {
                store.selectSurface(.view(view))
            }
        }

        if !store.boards.isEmpty {
            Divider()
            ForEach(store.boards) { board in
                row(board.name, isCurrent: store.activeBoardID == board.id) {
                    store.selectBoard(board.id)
                }
            }
        }
    }

    private func row(_ title: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // A menu row cannot tint anything, so the tick carries the state —
            // see `PriorityPicker`, which marks the current priority this way.
            if isCurrent {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    // MARK: Actions

    /// ⌘N opens the composer in the column the user is looking at when the
    /// board has the keyboard, and in the store's landing column otherwise.
    /// `BoardScrollView` scrolls it into view either way: a composer that opens
    /// off the right-hand edge takes the focus somewhere the user cannot see.
    private func newTask() {
        guard store.surface == .board, let columnID = window.focusedColumnID,
              store.column(id: columnID) != nil
        else { return store.beginAddingWhereVisible() }
        store.beginAdding(in: columnID)
    }

    /// The sidebar's own row is where a board is named as it is made, so this
    /// asks for that row rather than making an untitled board of its own.
    private func newBoard() {
        window.isSidebarVisible = true
        window.isNamingNewBoard = true
    }

    /// Task ▸ Set Due Date…. The sheet is aimed at the cards the item was aimed
    /// at, which it is told rather than asked to work out again.
    private func pickDueDate(for ids: Set<TaskItem.ID>) {
        window.dueDateTargets = ids
        window.isPickingDueDate = true
    }

    /// ⌘⌫. Focus follows the card off the board, which the card can no longer
    /// do for itself now that the menu takes the press first. Worked out before
    /// the delete, while the card is still there to have a neighbour.
    private func trash(_ ids: Set<TaskItem.ID>) {
        if let focused = window.focusedTaskID, ids.contains(focused) {
            window.focusedTaskID = BoardFocusMap(store).card(after: focused)
        }
        store.trashTasks(ids)
    }
}

#endif
