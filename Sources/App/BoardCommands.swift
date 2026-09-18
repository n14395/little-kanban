import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The menu bar, **generated** from ``AppCommand`` rather than transcribed from
/// it: each placement draws `AppCommand.menuItems(in:)` for one section, and
/// one `perform(_:on:)` switch says what each of them does. Nothing here names an
/// item, so no item can be lost or gained here without the vocabulary saying
/// so, and a command added to the enum cannot compile until it has both a
/// section and an action.
///
/// **On both platforms**, which it was not. iPadOS draws a real menu bar for
/// every app now, and an app that declares no `.commands` gets the system's
/// default one — File, Edit, View with nothing of ours in any of them, and every
/// key this app has taught people going nowhere. The desk and the iPad ask for
/// the same things, so they ask for them from the same list; ``AppCommand/platforms``
/// is where the two items that exist on one machine only are named, and
/// ``AppWindowState`` is the per-window state both menus write into.
///
/// Everything aimed at a card acts on ``targets`` — the focused card and
/// whatever it brings with it, or the selection when the board has no focus —
/// and is **disabled** when none of those cards can accept it. From the outside
/// a command that does nothing is a broken one, and "does nothing" is a
/// question about the cards, not about whether anything is selected at all: on
/// the Archive surface every item on the Task menu is aimed at a card that is
/// off the board. The items that are aimed at the *board* rather than at a card
/// ask ``AppCommand/isAvailable(in:)`` the same way — New Column on no board,
/// Sync Now with sync off.
///
/// Three groups are deliberately absent. Undo and Redo are `UndoManager`'s and
/// the system puts them on the Edit menu itself; declaring them here would put
/// two of each there. The `.board` commands — ⌘C, ⌘V, ⌘A, the arrows — get no
/// menu item either: a Copy item on the Edit menu takes ⌘C from every text
/// field in the app. They are handled where the board has focus and taught by
/// the sheet.
struct BoardCommands: Commands {
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    /// The two preferences the View menu can set. Read through `@AppStorage`
    /// rather than through `Preferences` so that the tick beside the current row
    /// follows a change made anywhere else — Settings has the same two controls,
    /// and a menu that had read the value once would go on ticking yesterday's.
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(CardDensity.storageKey) private var density = CardDensity.fallback

    let store: BoardStore
    let window: AppWindowState

    var body: some Commands {
        // ⌘N belonged to New Window while the toolbar had quietly taken it for
        // New Task, so the menu and the key disagreed about what the app did.
        // Replacing the group is what settles it.
        CommandGroup(replacing: .newItem) { items(.new) }

        // Import… and Export… open a panel the user then has to answer, so
        // neither carries a key. Saving and syncing are in the same block
        // because all four are the board as a *file*: what is written, what is
        // read, and what is sent.
        CommandGroup(replacing: .importExport) {
            items(.importExport)
            Divider()
            items(.file)
        }

        // **Replacing, and only where there is something to replace.** The desk
        // has SwiftUI's `Settings` scene, which puts the system's own item and
        // its ⌘, on the app menu; ours would be a second one beside it, so the
        // `.app` section is empty there and this block is not hung at all.
        //
        // iPadOS puts an item there too — `Little Kanban Settings…`, wired to
        // `orderFrontPreferencesPanel:` — for an app that has no `Settings`
        // scene to open. Declaring ours *after* it is not a duplicate item but a
        // duplicate **key**, and UIKit does not merely resolve that in somebody's
        // favour: it throws `NSInvalidArgumentException` while building the menu,
        // which is a crash on launch. Measured on an iPad Pro 13", where it took
        // the whole test host down before a single test ran. So on the platform
        // whose settings are a sheet of ours, the item that opens them is ours.
        #if !os(macOS)
        CommandGroup(replacing: .appSettings) { items(.app) }
        #endif

        CommandGroup(after: .pasteboard) {
            Divider()
            items(.edit)
        }

        CommandGroup(after: .sidebar) {
            items(.view)
            Divider()
            items(.savedView)
            Divider()
            items(.viewOptions)
            Divider()
            items(.navigate)
            Divider()
            destinations
        }

        CommandMenu(AppCommandGroup.task.title) {
            items(.task)
            Divider()
            items(.filing)
        }

        // **A menu of its own**, because a column is neither a card nor the
        // board. Everything in it was reachable only from the ⋯ on a column
        // header — a control that has to be found with a pointer, on a header
        // that scrolls off the side of a wide board — and every item is aimed
        // at the column holding the focused card, which is the only column the
        // app can name without one. See ``AppCommand/needsColumn``.
        CommandMenu(AppCommandGroup.column.title) {
            items(.column)
        }

        #if os(macOS)
        // The one item that is about the *app* rather than about the board
        // or a card. It is not in ``AppCommand`` because that vocabulary is
        // the board's — everything in it is aimed at cards, counts them in its
        // title and goes dead when there are none — and because replacing
        // `.appInfo` is the only way to take the system's own About item away,
        // which has to happen for there to be one place the app talks about
        // itself rather than two that disagree. The iPad reaches it through
        // Settings, which is where its own About row already lives.
        CommandGroup(replacing: .appInfo) {
            Button(String(localized: "About Little Kanban", comment: "App menu item")) {
                openAbout()
            }
            #if SPARKLE
            SparkleCheckForUpdatesButton()
            #endif
        }
        #endif

        // The default item leads to a help book this app does not have.
        CommandGroup(replacing: .help) { items(.help) }
    }

    // MARK: Items

    /// One block of the menu bar: every command the vocabulary declares into
    /// that section *on this machine*, in the order it declares them.
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
        // The anchors. Their rows are the store's or the preferences' and change
        // as the user works, so the enum names the anchor and the menu fills it.
        case .moveToColumn: columnRows
        case .moveToBoard: boardRows
        case .setPriority: priorityRows
        case .setLabels: labelRows
        case .appearance: appearanceRows
        case .cardDensity: densityRows
        case .sortOrder: sortRows
        default:
            let acting = applicable(command)
            Button(command.title(selectionCount: acting.count)) { perform(command, on: acting) }
                // ``AppCommand/menuShortcut``, not the first of `shortcuts`:
                // Open Task's ↩ belongs to the board and would be taken out of
                // every text field in the app by an item carrying it.
                .keyboardShortcut(command.menuShortcut)
                .disabled(!command.isEnabled(for: targets, in: store)
                          || !command.isEnabled(forColumn: window.focusedColumnID, in: store))
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
        case .newColumn: openBoardSettings(addingColumn: true)
        case .newView: newView()
        case .boardSettings: openBoardSettings(addingColumn: false)
        case .saveBoard: store.saveNow()
        case .syncNow: Task { await store.syncNow() }
        case .settings: store.isShowingSettings = true
        case .trashTask: trash(ids)
        case .find: store.focusSearch()
        case .toggleInspector: store.isInspectorOpen.toggle()
        case .toggleSidebar: window.isSidebarVisible.toggle()
        case .toggleInbox: store.toggleInbox()
        case .showTrash: showTrash()
        case .manageLabels: window.isManagingLabels = true
        case .themes: openThemes()
        case .previousBoard: step(-1)
        case .nextBoard: step(1)
        case .completeTask: store.complete(ids)
        case .reopenTask: store.reopen(ids)
        case .setDueDate: pickDueDate(for: ids)
        case .showInBoard: showPlace(of: ids)
        case .archiveTask: store.archive(ids)
        case .unarchiveTask: store.unarchive(ids)
        case .shortcuts: store.isShowingShortcuts = true
        case .importBoard: store.isImportingBoard = true
        case .exportBoard: store.isExportingBoard = true
        case .exportMarkdown: store.isExportingMarkdown = true
        case .revealBoardFile: revealBoardFile()
        case .restoreBackup: window.isRestoringBackup = true
        case .emptyTrash: window.isConfirmingEmptyTrash = true
        case .editView: editView()
        case .duplicateView: duplicateView()
        case .deleteView: deleteView()
        case .restoreBuiltInViews: store.restoreSeededViews()
        case .moveBoardUp: moveBoard(by: -1)
        case .moveBoardDown: moveBoard(by: 1)
        case .copyLink: copyLink(to: ids)
        case .openTask: open(ids)
        case .archiveCompleted: store.archiveCompleted()
        case .archiveInboxCompleted: store.archiveInboxCompleted()
        case .editColumn: editColumn()
        case .moveColumnLeft: moveColumn(by: -1)
        case .moveColumnRight: moveColumn(by: 1)
        case .trashColumn: trashColumn()
        case .moveToColumn, .moveToBoard, .setPriority, .setLabels,
             .appearance, .cardDensity, .sortOrder:
            // Anchors: the rows underneath them are what act.
            break
        case .undo, .redo, .copyTask, .pasteTask, .selectAll, .deselect,
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
    /// Focus first because the menu bar owns ⌘⌫ and ⌘⏎ — the menu is offered a
    /// press before the focused view is, so a card that claimed either would
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

    /// Which board a card is filed on, the Inbox included — the same list
    /// `BoardDestinationItems` draws beside a card, as a menu that can be aimed
    /// at several at once.
    ///
    /// Filing does **not** follow the card here. From a card's own pill it does,
    /// because the panel in front of you would otherwise be showing a card that
    /// has left the board behind it; from the menu bar the act is a filing act
    /// aimed at a selection, and being thrown onto another board after each one
    /// is the worse answer.
    private var boardRows: some View {
        let ids = applicable(.moveToBoard)
        return Menu(AppCommand.moveToBoard.title) {
            let isInbox = every(ids) { $0.isUnfiled }
            row(Board.inboxName, isCurrent: isInbox) { file(ids, onto: nil) }
                .disabled(isInbox)

            if !store.boards.isEmpty { Divider() }

            ForEach(store.boards) { board in
                let isCurrent = every(ids) { $0.boardID == board.id }
                row(board.name, isCurrent: isCurrent) { file(ids, onto: board.id) }
                    .disabled(isCurrent)
            }
        }
        .disabled(ids.isEmpty)
    }

    /// The board's labels, each a row that puts one on or takes it off.
    ///
    /// **Not the shape of the three above it.** Those name a place a card can
    /// be in exactly one of — a column, a board, a priority — so the current
    /// one is ticked *and dead*, because a row that would move a card to where
    /// it already is does nothing. A card wears any number of labels, so every
    /// row here stays live: the tick says the cards already carry it, and
    /// pressing it takes it off again. `toggleLabel(_:on:)` decides which way a
    /// mixed selection goes — anything not already carrying it gets it — so the
    /// menu does not have to.
    private var labelRows: some View {
        let ids = applicable(.setLabels)
        return Menu(AppCommand.setLabels.title) {
            ForEach(store.labels) { label in
                row(label.name, isCurrent: every(ids) { $0.labelKeys.contains(label.key) }) {
                    store.toggleLabel(label.key, on: ids)
                }
            }
        }
        .disabled(ids.isEmpty || store.labels.isEmpty)
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

    /// Light, dark, or whatever the system is doing — the same three Settings
    /// offers, writing the same key.
    private var appearanceRows: some View {
        Menu(AppCommand.appearance.title) {
            ForEach(AppAppearance.allCases) { choice in
                row(choice.label, isCurrent: appearance == choice) { appearance = choice }
            }
        }
    }

    private var densityRows: some View {
        Menu(AppCommand.cardDensity.title) {
            ForEach(CardDensity.allCases) { choice in
                row(choice.label, isCurrent: density == choice) { density = choice }
            }
        }
    }

    /// How a column's cards are ordered. A display preference on the store
    /// rather than in `UserDefaults` alone — see ``BoardSortOrder`` — so this
    /// writes what the column headers' own picker writes.
    private var sortRows: some View {
        Menu(AppCommand.sortOrder.title) {
            ForEach(BoardSortOrder.allCases) { order in
                row(order.label, isCurrent: store.sortOrder == order) { store.sortOrder = order }
            }
        }
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

        ForEach(store.views) { view in
            row(view.label, isCurrent: store.activeView?.id == view.id) {
                store.selectSurface(.view(view.id))
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

    /// New Column… and Board Settings… are one door with the composer either
    /// open or shut — the same request `BoardSidebar`'s board menu makes, and
    /// the same one `BoardScrollView`'s blank state makes. There is nowhere else
    /// a column can be added from: the strip stopped carrying an add tile when
    /// columns became something a board owns.
    private func openBoardSettings(addingColumn: Bool) {
        guard let board = store.activeBoardID else { return }
        store.boardSettings = BoardSettingsRequest(board: board, addsColumn: addingColumn)
    }

    /// A view is made and its editor opens on it, which is the sidebar's own
    /// "New view" in one step: an empty saved view with no rule shows nothing,
    /// so handing somebody one without the editor would be handing them a blank
    /// row to wonder about.
    ///
    /// Raised through ``BoardStore/editingViewID`` rather than through state of
    /// the sidebar's own, for the reason the phone's drawer already had: the
    /// asker is not the presenter. The menu bar is outside every view tree, and
    /// the source list it would otherwise borrow the flag from may not be on
    /// screen at all.
    private func newView() {
        store.editingViewID = store.addView().id
    }

    /// Task ▸ Set Due Date…. The sheet is aimed at the cards the item was aimed
    /// at, which it is told rather than asked to work out again.
    private func pickDueDate(for ids: Set<TaskItem.ID>) {
        window.dueDateTargets = ids
        window.isPickingDueDate = true
    }

    /// ⌘J: go to where this card lives and light it up. Aimed at one card —
    /// the first in board order — because there is one board to land on, and a
    /// selection spread across three of them cannot be shown at once.
    private func showPlace(of ids: Set<TaskItem.ID>) {
        guard let id = store.tasks.first(where: { ids.contains($0.id) })?.id else { return }
        store.showPlace(of: id)
    }

    /// Files several cards at once, as one undo step. `nil` is the Inbox, which
    /// is what a card on no board at all is.
    private func file(_ ids: Set<TaskItem.ID>, onto boardID: Board.ID?) {
        guard !ids.isEmpty else { return }
        let ordered = store.tasks.filter { ids.contains($0.id) }.map(\.id)
        let name = ordered.count > 1
            ? String(localized: "Move Tasks", comment: "Undo action name for filing several tasks onto another board")
            : String(localized: "Move Task", comment: "Undo action name for filing a task onto another board")
        store.undoable(name) {
            for id in ordered {
                if let boardID {
                    store.file(id, onto: boardID)
                } else {
                    store.unfile(id)
                }
            }
        }
    }

    /// ⌃⌘C. Aimed at one card for ``showPlace(of:)``'s reason: the pasteboard
    /// holds one thing, and a selection of three cannot be linked to at once.
    private func copyLink(to ids: Set<TaskItem.ID>) {
        guard let id = store.tasks.first(where: { ids.contains($0.id) })?.id else { return }
        TaskLink.copyToPasteboard(id)
    }

    /// What ↩ does where the board has focus, said as a menu item for the
    /// readers a key press is not offered to — see ``AppCommand/menuShortcut``
    /// for why the item cannot carry the key itself. The same two lines
    /// `BoardKeyboard` runs, aimed at one card, because the inspector shows one.
    private func open(_ ids: Set<TaskItem.ID>) {
        guard let id = store.tasks.first(where: { ids.contains($0.id) })?.id else { return }
        store.select(id)
        store.isInspectorOpen = true
    }

    /// The saved view on screen, which is what the three View ▸ items act on.
    /// The source list's row menu acts on the row it hangs off; the menu bar has
    /// no row to hang off, so it acts on where you are standing.
    private func editView() {
        store.editingViewID = store.activeView?.id
    }

    private func duplicateView() {
        guard let id = store.activeView?.id else { return }
        // Straight into the editor, as the list's own Duplicate does: a copy
        // named "… copy" sitting in the sidebar is a row to wonder about.
        store.editingViewID = store.duplicateView(id)?.id
    }

    private func deleteView() {
        guard let id = store.activeView?.id else { return }
        store.deleteView(id)
    }

    /// View ▸ Move Board Up / Down, which reorders the source list rather than
    /// moving through it — `step(_:)` above is the one that navigates.
    ///
    /// `toOffset` is `index + 2` going down for `move(fromOffsets:toOffset:)`'s
    /// arithmetic: the offset names a gap in the list *before* the row is taken
    /// out of it. The sidebar's own two rows say the same thing.
    private func moveBoard(by delta: Int) {
        guard let index = store.boards.firstIndex(where: { $0.id == store.activeBoardID }) else { return }
        store.moveBoard(fromOffsets: IndexSet(integer: index), toOffset: delta < 0 ? index - 1 : index + 2)
    }

    // MARK: The column the keyboard is in

    /// The column holding the focused card, which is what the Column menu is
    /// aimed at. `nil` while the keyboard is not on a card — on the Archive, in
    /// a saved view, or with nothing focused at all — and every item in that
    /// menu is then disabled rather than aimed at a column nobody chose.
    private var focusedColumn: BoardColumn.ID? {
        guard let id = window.focusedColumnID, store.column(id: id) != nil else { return nil }
        return id
    }

    /// The whole board with this column already unfolded in it, which is what
    /// the column header's own Edit Column… opens. There is no separate column
    /// editor to raise: the popover the header shows belongs to the header.
    private func editColumn() {
        guard let column = focusedColumn, let board = store.activeBoardID else { return }
        store.boardSettings = BoardSettingsRequest(board: board, column: column)
    }

    private func moveColumn(by delta: Int) {
        guard let column = focusedColumn,
              let index = store.columns.firstIndex(where: { $0.id == column })
        else { return }
        store.moveColumn(fromOffsets: IndexSet(integer: index), toOffset: delta < 0 ? index - 1 : index + 2)
    }

    /// A refusal has a reason and the reason has to be read, so it goes to the
    /// window — the header keeps its own copy of this alert for the menu it
    /// draws, and the menu bar has no view of its own to put one on.
    private func trashColumn() {
        guard let column = focusedColumn else { return }
        window.columnRefusal = store.trashColumn(column)
    }

    #if os(macOS)
    private func revealBoardFile() {
        guard let url = store.boardFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #else
    /// Unreachable: ``AppCommand/revealBoardFile`` is `.desk` only. Present so
    /// the one `perform(_:on:)` switch stays exhaustive rather than growing a
    /// platform hole — the same bargain ``openThemes()`` makes below.
    private func revealBoardFile() {}
    #endif

    /// ⌥⌘↑ and ⌥⌘↓.
    private func step(_ delta: Int) {
        guard let next = Self.board(delta, from: store.activeBoardID, in: store.boards) else { return }
        store.clearQuery()
        store.selectBoard(next)
    }

    /// The board `delta` steps from the one in front of you, **wrapping at both
    /// ends**: a list of three that stopped at the last one would need the user
    /// to know which end they were at before pressing, which is a keyboard
    /// command that has to be looked at to be used.
    ///
    /// A static of the rule rather than a body inside the action, so it can be
    /// held up to a test — a `Commands` body has nothing a test can enumerate.
    /// `nil` when there is nowhere else to go, which is the one board case; a
    /// board that is not in the list at all — the Inbox is the surface, say —
    /// counts as being before the first, so ↓ lands on the first and ↑ on the
    /// last.
    static func board(_ delta: Int, from current: Board.ID?, in boards: [Board]) -> Board.ID? {
        guard boards.count > 1 else { return nil }
        guard let index = boards.firstIndex(where: { $0.id == current }) else {
            return delta > 0 ? boards.first?.id : boards.last?.id
        }
        return boards[(index + delta % boards.count + boards.count) % boards.count].id
    }

    /// The Trash is a popover hanging off the source list's own row — see
    /// `BoardSidebar` — so the list has to be out for there to be anything to
    /// hang it from. Raising the flag against a hidden list is a menu item that
    /// silently does nothing, which is the one thing an item may not do.
    ///
    /// The wait is for the list to be *there*: a popover asks its anchor for a
    /// frame at the moment it is presented, and a view added in the same runloop
    /// turn has none yet. `sidebarTravel` is the animation the two roots move it
    /// with, plus the slack `BoardScrollView.panelTravel` allows for the same
    /// reason.
    private func showTrash() {
        guard !window.isSidebarVisible else {
            store.isShowingTrash = true
            return
        }
        window.isSidebarVisible = true
        Task { @MainActor in
            try? await Task.sleep(for: Self.sidebarTravel)
            store.isShowingTrash = true
        }
    }

    static let sidebarTravel: Duration = .milliseconds(210)

    /// ⌘⌫. Focus follows the card off the board, which the card can no longer
    /// do for itself now that the menu takes the press first. Worked out before
    /// the delete, while the card is still there to have a neighbour.
    private func trash(_ ids: Set<TaskItem.ID>) {
        if let focused = window.focusedTaskID, ids.contains(focused) {
            window.focusedTaskID = BoardFocusMap(store).card(after: focused)
        }
        store.trashTasks(ids)
    }

    #if os(macOS)
    private func openAbout() {
        openWindow(id: LittleKanbanApp.aboutWindowID)
    }

    private func openThemes() {
        openWindow(id: LittleKanbanApp.themesWindowID)
    }
    #else
    /// Unreachable: ``AppCommand/themes`` is `.desk` only, so no item for it is
    /// drawn here. Present so the one `perform(_:on:)` switch stays exhaustive
    /// over the whole vocabulary rather than growing a platform hole.
    private func openThemes() {}
    #endif
}
