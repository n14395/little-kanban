#if os(iOS)

import SwiftUI

/// The iPhone screen: header, task list or paged board, floating tab bar,
/// plus the drawer, the Inbox slide-over and the detail sheet over the top.
struct PhoneRootView: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock
    /// Compact height is the phone on its side, which is the one shape with
    /// room for more than one column at once (5.5). A size class rather than an
    /// orientation: Slide Over and Split View arrive at the same shape without
    /// the device having turned.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isCreatingBoard = false
    /// Which column the horizontal scroller is settled on, mirrored to
    /// `store.mobileColumnID` in both directions. It is view state rather than
    /// board state because it is a scroll offset: the store already owns the
    /// answer to *which column*, and two owners of one fact is how the chips
    /// and the page fall out of step.
    @State private var pagedColumnID: BoardColumn.ID?
    /// How far a finger has pulled the drawer in — 0 shut, 1 open — or `nil`
    /// when no pan is driving it.
    ///
    /// View state for `pagedColumnID`'s reason: it is a position in a gesture,
    /// not a fact about the board. `nil` rather than 1 for "not being dragged",
    /// because the two are not the same thing to draw: a drawer nobody is
    /// touching is the transition's to move, and one under a finger is not.
    @State private var drawerPull: CGFloat?
    /// The window, both dimensions of it. `PhoneNavDrawer` is 84% of its *short*
    /// edge — see `PhoneNavDrawer.width(in:screen:)` — and neither the panel nor
    /// the pan that drags it in can work that out from the width it is handed,
    /// which on its side is the long one.
    ///
    /// Measured here rather than in the drawer because this view is on screen
    /// from launch: by the time there is a drawer to draw, the number is already
    /// known, and the panel never renders a frame at a width it is about to
    /// correct.
    @State private var screen: CGSize = .zero
    /// Whether the Inbox is up **as a sheet**, which is not the same question as
    /// whether the Inbox is open: on its side it is open as an overlay and there
    /// is no sheet at all.
    ///
    /// View state rather than a binding computed off the store, and that is the
    /// whole point of it: a computed binding cannot tell apart the two ways it
    /// goes false. Turning the phone takes the sheet down, and SwiftUI reports
    /// that back as a dismissal — through whichever binding it happens to be
    /// holding, which may be one made before the phone turned, so a guard inside
    /// the setter reads the old shape and takes the dismissal at its word.
    /// Measured: rotating with the panel up closed the Inbox instead of handing
    /// it to the overlay. `onChange` runs against the values the body has *now*,
    /// which is why this is three of those rather than one closure.
    @State private var showsInboxSheet = false
    /// The app's, when there is an app — `PadRootView`'s reason, and this root
    /// is not exempt from having one: the menu bar is declared into every iOS
    /// scene, an iPhone with a hardware keyboard answers its keys, and an iPad
    /// in Slide Over or a narrow split draws *this* root while iPadOS keeps the
    /// menu up. Whatever the menu raises has to appear here too, or the items
    /// are live, enabled, and do nothing at all.
    @Environment(AppWindowState.self) private var injectedWindow: AppWindowState?
    @State private var standaloneWindow = AppWindowState()
    /// What an import folded in, or why a transfer could not be done —
    /// `MacRootView`'s, for the panels the menu bar raises here too.
    @State private var transferNotice: SettingsNotice?

    private var resolvedWindow: AppWindowState { injectedWindow ?? standaloneWindow }

    var body: some View {
        @Bindable var store = store
        @Bindable var window = resolvedWindow

        // Resolved once and handed to both: the saved-view bar's count pill and
        // the list under it are then the same array by construction, and cannot
        // drift apart the way they did while the header counted the view's
        // membership and the list drew the query's result.
        let tasks = store.mobileTasks(today: dayClock.today)

        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PhoneHeader()
                    .padding(.top, 4)

                // No columns means no board — the user can delete the last one —
                // and there is then nothing to page between.
                if store.isColumnPaging {
                    // The chip strip in the header is the one thing that says
                    // which column you are on, and it is also how you get to
                    // another one by name; the arrows-and-dots row that used to
                    // sit under it said the same thing again in a vaguer
                    // alphabet. The swipe is unchanged, and so is every route
                    // in the header.
                    columnPages
                        // The row that used to sit here was also the gap
                        // between the chips and the first card; the chips have
                        // 4pt of their own and the list 2, which is not a gap.
                        //
                        // On its side there are no chips to clear, and for a
                        // while that meant no gap at all: the column pills sat
                        // directly under the board's name, close enough to read
                        // as a second line of the title rather than as the tops
                        // of four lists. Landscape is the orientation with 402pt
                        // of height to spend, so it is also the one where a
                        // heading crowding the title is most obvious — hence the
                        // larger of the two numbers, not the smaller.
                        .padding(.top, isShort ? 14 : 10)
                        // **Kept out of the sensor housing.** A `ScrollView`
                        // reaches past the safe area by design and insets only
                        // its content, so the *next* column along is drawn in
                        // the strip beside the housing — which on a phone held
                        // sideways is 60-odd points of half-covered card at the
                        // leading edge. The rail used to hide that strip by
                        // standing in it with an opaque ground; with the bar in
                        // the header there is nothing there any more, so the
                        // pager is clipped to the frame it was given instead.
                        //
                        // A no-op in portrait, where the horizontal insets are
                        // zero and the clip is the scroll view's own bounds.
                        .clipped()
                } else if isShort, store.activeView != nil {
                    // The flow has no rows to trail an empty state behind the
                    // way the flat list does, so a view narrowed to nothing
                    // rendered as blank screen — same emptiness, no sentence.
                    // The portrait list's own answer, centred in the room the
                    // columns would have had; rotation was the only way out.
                    if tasks.isEmpty {
                        emptyState(in: nil)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        taskColumns(tasks)
                    }
                } else {
                    taskList(tasks)
                }
            }
            // Portrait keeps the bar floating over the foot of the list, which
            // is what the gradient behind it is for, and which is where a thumb
            // is. **Turned on its side it is drawn by `PhoneHeader` instead**,
            // in the title row — so it is not here at all, and the board is not
            // inset for it.
            //
            // It was a rail up the leading edge before that, held by a
            // `safeAreaInset(edge: .leading)`, which bought back the 130pt of
            // height the floating bar cost and charged the board 76pt of width
            // for it. The header row was the third answer and is the only one
            // that costs nothing: it is already drawn, already 44pt tall, and
            // the space between the board's name and the ⋯ was empty.
            if !isShort { PhoneTabBar() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // `.phone` clears a tab bar along the foot; on its side there is none
        // there to clear, and the card sits where every other touch surface
        // puts it.
        .boardToast(metrics: isShort ? .sheet : .phone)
        .background {
            palette.windowFill
                .ignoresSafeArea()
                // The window, and this is the one thing in the view that is
                // measured outside the safe area on purpose: the drawer's width
                // is the screen's short edge, and on its side the short edge is
                // the *height* — which inside the safe area is short by the home
                // indicator's 21pt, so the drawer would come out 18pt narrower
                // turned than it is upright. Same edge, same number, either way
                // up.
                .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
        }
        // The drawer is a scrim over the board, so to a sighted user the board
        // is gone. This takes the header and the tab bar out of the tree with
        // it — but *not* the list: its rows are hosted in collection view
        // cells, which the modifier does not reach, and putting a second
        // one on `taskList` does not reach them either. Measured with the
        // drawer up, every card was still enumerable. What actually keeps a
        // reader out of the board is the drawer's own `.isModal`; this is worth
        // keeping for the two bars it does take, and is not the whole of it.
        .accessibilityHidden(store.isNavDrawerOpen || store.isInboxOpen)
        // The drawer's other way in. The hamburger was the only one, and a
        // panel that slides out from the leading edge is one every other iOS
        // app opens by pulling from that edge. `PadRootView` takes the same
        // recognizer for its source list, in the fire-once spelling: a split
        // view's column is not something a finger can be given hold of.
        //
        // The pan is followed rather than merely noticed — see `drawerPan`,
        // which is also where the three guards live that keep it from opening a
        // drawer behind something already over the board.
        .leadingEdgePan(drawerPan)
        // The Inbox, on its side only. A sheet in a compact height is laid out
        // at the whole screen, which takes this view out of the hierarchy
        // underneath it — so the panel had no board behind it and no scrim it
        // could honestly draw. `PhoneInboxSheet` has the measurements; what
        // matters here is that turned sideways the Inbox is one of this view's
        // overlays and upright it is a real sheet, and the flag is the same one.
        .overlay {
            if store.isInboxOpen, isShort {
                inbox
            }
        }
        .motionAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28), value: store.isInboxOpen)
        .overlay {
            if store.isNavDrawerOpen {
                PhoneNavDrawer(progress: drawerPull ?? 1, screen: screen)
            }
        }
        // Under the drawer rather than over it: the drawer is the way to a
        // *board*, and a board list half-covered by the Inbox is the wrong way
        // round. Both up at once is reachable — the drawer's Inbox row opens
        // this one — and that row closes the drawer on its way.
        .motionAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28), value: store.isNavDrawerOpen)
        // 5.8's `.selection` half: paging and the tab bar are the same act —
        // picking where you are — and both are one tap or one swipe, never a
        // keystroke. The card owns the other two, because both are things that
        // happen to a particular card: `.success` on the tick, `.impact` on the
        // lift and the landing.
        .sensoryFeedback(.selection, trigger: store.mobileColumnID)
        .sensoryFeedback(.selection, trigger: store.tab)
        // The Board tab's own way out of a board list emptied to nothing. The
        // drawer has the same prompt, but reaching it means knowing the way out
        // is behind the hamburger.
        .newBoardAlert(isPresented: $isCreatingBoard)
        // Held back while the Inbox is up, which puts the editor over itself
        // instead — a sheet is presented by whatever is on screen, and this view
        // is behind one by then. See `phoneTaskDetailSheet`.
        .phoneTaskDetailSheet(isEnabled: !store.isInboxOpen)
        // The Inbox, which used to be an overlay of this view's own with a
        // scrim, a transition and a drag gesture hand-rolled to match what a
        // sheet does. It is a sheet now — see ``PhoneInboxSheet``.
        .sheet(isPresented: $showsInboxSheet) { inbox }
        // Opened or closed from anywhere — the tab bar's slot, the drawer's row,
        // a card filed to the Inbox from the editor — and a sheet only while the
        // phone is upright.
        .onChange(of: store.isInboxOpen) { _, open in showsInboxSheet = open && !isShort }
        // Turned with the panel up: the sheet goes and the overlay takes it, and
        // the flag the two of them share is not touched.
        .onChange(of: isShort) { _, short in showsInboxSheet = store.isInboxOpen && !short }
        // The one direction the store cannot see for itself: the sheet swiped
        // away, or dismissed by a tap outside it. Ignored while the phone is on
        // its side, where a sheet going down is the handover above rather than
        // anybody asking for it.
        .onChange(of: showsInboxSheet) { _, shows in
            if !shows, !isShort { store.isInboxOpen = false }
        }
        // A launch straight into the Inbox — `-LittleKanbanShowInbox`, and a
        // deep link — arrives before any of those can fire.
        .onAppear { showsInboxSheet = store.isInboxOpen && !isShort }
        // Raised from the header's board menu, which is this surface's drawer
        // for everything with no other home. Presented here rather than there
        // because the menu is inside the header and a sheet wants the root —
        // the same split `SettingsSheet` makes for the drawer's Settings row.
        //
        // A sheet on the phone and a popover on the two pointer surfaces, off
        // the same flag: there is no source list here to hang a popover from.
        .sheet(isPresented: trashPresentation) {
            TrashSheet()
                .environment(store)
                .environment(\.palette, palette)
                .environment(\.dayClock, dayClock)
        }
        // The drawer's rows raise this and close, and so does the header's ⋯
        // menu while a view is the surface — see `BoardStore.editingViewID` for
        // why the asking and the presenting are two different surfaces here and
        // one on the iPad. Both askers are gone by the time the sheet opens.
        .sheet(item: viewEditorPresentation) { draft in
            SavedViewEditor(viewID: draft.id, metrics: .sheet)
                .environment(store)
                .environment(\.palette, palette)
                .environment(\.dayClock, dayClock)
        }
        // What the menu bar opens — the same slate the iPad's root presents,
        // because the same menu is up over both: an iPhone with a hardware
        // keyboard answers its keys, and an iPad in Slide Over or a narrow
        // split resolves to this root with the menu still drawn. Each of these
        // was a flag the menu set and nothing here read.
        .sheet(isPresented: $store.isShowingShortcuts) {
            ShortcutsSheet()
        }
        .sheet(isPresented: $window.isPickingDueDate) {
            DueDateSheet()
        }
        .labelManagerSheet(isPresented: $window.isManagingLabels, metrics: .sheet)
        // File ▸ Restore from a Backup…, Edit ▸ Empty Trash… and a refused
        // Column ▸ Trash Column.
        .menuPresentations(window: window, backups: .sheet)
        // **File ▸ Import… / Export… / Export as Markdown…** — the pass
        // `PadRootView` records having needed once already, made here for the
        // same reason it was needed there.
        .modifier(BoardTransfer(
            isExportingBoard: $store.isExportingBoard,
            isExportingMarkdown: $store.isExportingMarkdown,
            isImporting: $store.isImportingBoard,
            today: dayClock.today,
            onImport: { transferNotice = .importing($0, into: store) },
            onFailure: { transferNotice = SettingsNotice(
                title: String(localized: "That export could not be written.",
                              comment: "Alert title when saving an exported file failed"),
                message: $0
            ) }
        ))
        .alert(
            transferNotice?.title ?? "",
            isPresented: Binding(get: { transferNotice != nil }, set: { if !$0 { transferNotice = nil } }),
            presenting: transferNotice
        ) { _ in
            Button("OK") { transferNotice = nil }
        } message: { notice in
            Text(notice.message)
        }
        // File ▸ New Board asks the source list to open its naming field, and
        // this surface's board list is the drawer — which has no field, but the
        // root has the naming alert its own empty state uses. Same question,
        // this surface's way of asking it.
        .onChange(of: window.isNamingNewBoard) { _, naming in
            guard naming else { return }
            window.isNamingNewBoard = false
            isCreatingBoard = true
        }
        // No surface here draws the composer — the column strip's and the Inbox
        // panel's are the wide layouts' — so a request to open one is answered
        // in this surface's own idiom instead: the card is made where the
        // request aimed and its editor opens with the title focused, exactly
        // what the floating "+" does. ⌘N, File ▸ New Task and an intent's
        // capture all land here; unanswered, the flag sat orphaned until the
        // window widened again and popped a composer nobody had just asked for.
        .onChange(of: store.addingPlacement) { _, placement in
            guard let placement else { return }
            store.addTask(to: placement, title: "", fromPhone: true)
        }
        .onAppear {
            // A composer the *wide* root had open when the window narrowed into
            // this one: what was typed is kept — committed to where the field
            // was aiming it — and the empty request is put away rather than
            // turned into a card nobody asked for.
            if store.addingPlacement != nil {
                store.commitDraft()
                store.cancelDraft()
            }
            // And the keyboard-focus mirror the wide root was keeping for the
            // menu bar. Nothing here writes it, so left standing it aims ⌘⌫
            // and ⌘⏎ at whichever card had focus before the window narrowed —
            // a card no longer on screen.
            resolvedWindow.focusedTaskID = nil
            resolvedWindow.focusedColumnID = nil
        }
        .environment(resolvedWindow)
    }

    /// Written through a binding for `trashPresentation`'s reason: every way out
    /// of the sheet — Done, a swipe down, the view being deleted underneath it —
    /// goes through one place.
    private var viewEditorPresentation: Binding<SavedViewDraft?> {
        Binding(
            get: { store.editingViewID.flatMap { store.view(id: $0) }.map(SavedViewDraft.init) },
            set: { store.editingViewID = $0?.id }
        )
    }

    /// The panel itself, built the same way for both shapes — the environment
    /// is passed by hand because a sheet is its own hierarchy and does not
    /// inherit it, and the overlay is handed it for nothing.
    private var inbox: some View {
        PhoneInboxSheet(screen: screen)
            .environment(store)
            .environment(\.palette, palette)
            .environment(\.dayClock, dayClock)
    }

    private var trashPresentation: Binding<Bool> {
        Binding(get: { store.isShowingTrash }, set: { store.isShowingTrash = $0 })
    }

    // MARK: - The board, one column per screen

    /// The spec's pager, finally holding the gesture it describes: *"One column
    /// per screen, rubber-band at the ends"* (seed task `t4`). It was a strip
    /// of dots over a list that did not move; the chips in the header are now
    /// the whole of what says where you are.
    ///
    /// `.viewAligned` rather than `.paging` because a page here is a *column*,
    /// not a screenful: in landscape three of them share the width and the
    /// swipe still advances by one, which `.paging` — which steps by the
    /// viewport — cannot express. The bounce at either end is the scroll view's
    /// own.
    private var columnPages: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(store.pagerColumns) { column in
                    page(column)
                        .containerRelativeFrame(
                            .horizontal, count: columnsPerScreen, span: 1, spacing: 0
                        )
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollPosition(id: $pagedColumnID, anchor: .leading)
        .onAppear { pagedColumnID = store.mobileColumnID }
        // The two directions of the same fact. Each guards on inequality, which
        // is what keeps a swipe from re-scrolling itself and a chip tap from
        // being undone by the scroll it just caused.
        .onChange(of: pagedColumnID) { _, id in
            if let id, id != store.mobileColumnID { store.mobileColumnID = id }
        }
        .onChange(of: store.mobileColumnID) { _, id in
            guard pagedColumnID != id else { return }
            Motion.run(.snappy(duration: 0.28), reduceMotion: reduceMotion) { pagedColumnID = id }
        }
    }

    /// The phone on its side — `PhoneHeader`'s name for the same test, and a
    /// size class rather than an orientation for the same reason: Slide Over
    /// and Split View arrive at that shape without the device having turned.
    private var isShort: Bool { verticalSizeClass == .compact }

    /// How many columns share the screen. More than one only where there is
    /// width for them, which on a phone is landscape — the shape 5.5 unlocks.
    ///
    /// **Three, not two.** The pager divides the width *inside* the safe area,
    /// so the count is exact rather than approximate: measured on a 17 Pro on
    /// its side, 874pt less 62 either side of the sensor housing is 750, which
    /// is three pages of 250 as cleanly as it was two of 375. What a page loses
    /// is the card inside it — 210pt of row, 142 of it title, against 335 and
    /// 267 — and what the board gains is the third of four seed columns, which
    /// is the difference between seeing where a card is going and having to
    /// swipe to find out.
    ///
    /// Capped at the board's own column count, which two never had to be: a
    /// board with two columns divided into three leaves a third of the screen
    /// showing nothing, and a board is allowed to have two.
    private var columnsPerScreen: Int {
        isShort ? min(3, max(store.pagerColumns.count, 1)) : 1
    }

    /// A page is a column, and is drawn by ``PhoneColumnPage`` rather than by
    /// the flat list below: a column has ground around its cards that means
    /// *put it here*, and a `List` is the one container that will not let a
    /// finger say so. The two rows under the cards are still built here,
    /// because the flat list needs the same two.
    @ViewBuilder private func page(_ column: BoardColumn) -> some View {
        let tasks = store.visibleTasks(in: column.id)

        PhoneColumnPage(
            column: column,
            tasks: tasks,
            showsHeading: columnsPerScreen > 1,
            metrics: listMetrics
        ) {
            if tasks.isEmpty {
                emptyState(in: column)
            }
            // The empty state carries the same "add a task" offer, so the dashed
            // row would only be a second copy of it under the first.
            if store.showsMobileAddRow, !tasks.isEmpty {
                addRow(in: column)
            }
        }
    }

    // MARK: - The list

    /// `TaskListView`, not a second list: the Search tab, the Inbox tab and a
    /// saved view are the same flat list of cards the desk draws, and this
    /// surface used to hand-roll it — down to a private copy of the row
    /// modifier — while the shared view had a single macOS-only call site.
    /// What is genuinely the phone's stays here as trailing rows.
    ///
    /// **Off the board only.** The board's own pages are ``PhoneColumnPage``,
    /// which is a stack: a `List` will not hand a drop on its own ground to
    /// anything behind it, and a column's ground is where a card is aimed when
    /// it is not aimed at another card. Nowhere this list is drawn is a place a
    /// card can be put, so nothing here wants that ground — which is why the
    /// two containers can differ without the two surfaces disagreeing.
    private func taskList(_ tasks: [TaskItem]) -> some View {
        TaskListView(
            tasks: tasks, metrics: listMetrics, showsColumn: showsPlaceChips
        ) {
            if tasks.isEmpty {
                emptyState(in: nil)
            }
            // The empty state carries the same "add a task" offer, so the dashed
            // row would only be a second copy of it under the first.
            if store.showsMobileAddRow, !tasks.isEmpty {
                addRow(in: nil)
            }
        }
    }

    /// A saved view on a phone held sideways, which is the one shape on this
    /// platform with width to spend — see ``TaskColumnsView``.
    ///
    /// **Across and then down, where the two wide surfaces go down and then
    /// across.** The flow follows the scroll, and the scroll follows the shape
    /// of the screen: a landscape phone has 390-odd points of height, which is
    /// two cards, so wrapping downward would mean paging sideways through
    /// columns two deep — a worse read than the single list it replaced. Wrapped
    /// across, the same width holds two cards a row on a 17 Pro and three on a
    /// Pro Max — see ``TaskColumnMetrics/phone`` for that arithmetic — and the
    /// surface goes on scrolling the way it always did.
    ///
    /// **A saved view only, and only on its side.** The Inbox tab and the Search
    /// tab draw through ``taskList(_:)`` whichever way the phone is held: they
    /// are `TaskListView`'s last call site, and the trailing rows they carry —
    /// the empty state, the dashed add row — are rows of that list rather than
    /// cards. Upright, a saved view has one column's width and there is nothing
    /// to wrap into.
    private func taskColumns(_ tasks: [TaskItem]) -> some View {
        TaskColumnsView(tasks: tasks, metrics: .phone, flow: .acrossThenDown) { task in
            PlatformTaskCard(task: task, showsColumn: showsPlaceChips)
        }
    }

    /// The touch preset, with the room under the last card taken back on a
    /// screen that has none to spare.
    ///
    /// `sheet`'s 130pt is a floating tab bar plus the space to scroll the last
    /// card clear of it — a third of a phone held sideways, spent on a bar that
    /// on this shape is not down there any more but up the leading edge. What
    /// is left is the ordinary clearance under a last row.
    private var listMetrics: TaskListMetrics {
        var metrics = TaskListMetrics.sheet
        if isShort {
            metrics.topInset = 0
            metrics.bottomInset = 24
        }
        return metrics
    }

    /// A saved view always gets the chips: it can hold cards from any board and
    /// the Inbox at once, which is when a chip earns its room (4.8). The Inbox's
    /// own list used to be the exception here and is no longer this view's to
    /// draw — ``PhoneInboxSheet`` makes the same call for itself, where the
    /// reason for it is local.
    private var showsPlaceChips: Bool {
        store.activeView != nil || store.showsMobileColumnChips
    }

    /// The empty cases, which all rendered as blank space (4.3). Which kind of
    /// empty it is decides the way out: a place with nothing in it offers to
    /// add, a query that matched nothing offers to drop the query, and a saved
    /// view offers neither because it is a filter rather than a place.
    private func emptyState(in column: BoardColumn?) -> EmptyStateView {
        // Ahead of the tab, because a view outranks the tab in `mobileTasks`.
        // Being narrowed to nothing is the same dead end wherever it happens.
        if store.mobileAppliesQuery, store.isFiltering {
            return .noResults(query: store.query, metrics: .sheet, clear: store.clearQuery)
        }
        if let view = store.activeView {
            return .savedView(view, metrics: .sheet)
        }
        switch store.tab {
        case .search:
            // An unqueried Search lists the whole board, so reaching this means
            // there is no board yet rather than no result.
            return .board(metrics: .sheet, add: store.addTaskToCurrentMobileColumn)
        case .board:
            // Deleting the last board is allowed, so the Board tab has to have
            // something to say when there is no board to draw — and has to
            // offer the way back, which is the only one there is.
            guard let board = store.activeBoard else { return noBoard }
            // A board with nothing but its Done column is a *new* board — that
            // is the one column every board is made holding. Not the same empty
            // as a column with nothing in it, and not the same way out either.
            guard !store.workingColumns.isEmpty else { return blankBoard(board) }
            return emptyColumn(column)
        }
    }

    /// A board that has not been given a column yet.
    ///
    /// **The way out is the board's settings**, which is where a column is made
    /// on this platform: the desk composes one in the strip beside the last
    /// column, and a phone has no strip to compose in — its columns are a row
    /// of chips over a pager, and there is nothing to page. The same sheet the
    /// ⋯ menu's **Board Settings…** opens, arriving on the board rather than on
    /// a column.
    private func blankBoard(_ board: Board) -> EmptyStateView {
        .noColumns(metrics: .sheet) {
            store.boardSettings = BoardSettingsRequest(board: board.id)
        }
    }

    private var noBoard: EmptyStateView {
        .noBoards(metrics: .sheet, add: { isCreatingBoard = true })
    }

    /// Not `EmptyStateView.column`: its copy tells the reader to drag a card
    /// here, and on a surface that shows one column at a time the card to drag
    /// is on another screen. A drag *does* land here — the page takes a drop
    /// anywhere in it, see ``PhoneColumnPage`` — but it is the second way in
    /// rather than the one to name, and the phone's own copy names the first:
    /// add a task, or swipe to a column that has some. Everything else about
    /// the state is the same.
    private func emptyColumn(_ column: BoardColumn?) -> EmptyStateView {
        let name = column?.name ?? store.mobileColumnName
        return EmptyStateView(
            symbol: "tray",
            headline: String(
                localized: "Nothing in \(name)",
                comment: "Empty state headline for the column the iOS pager is on"
            ),
            message: String(
                localized: "Add the first task to this column, or swipe to another.",
                comment: "Empty state body copy for the column the iOS pager is on"
            ),
            actionTitle: String(
                localized: "Add a task", comment: "Empty state button that starts a new task"
            ),
            action: { add(to: column) },
            metrics: .sheet
        )
    }

    /// ``ColumnAddRow``, which the desk and the iPad draw at the foot of their
    /// columns too. It was this surface's alone until it was lifted out; what
    /// stayed here is the destination — a column when the pager is on the
    /// board, the current one when the list is flat.
    private func addRow(in column: BoardColumn?) -> some View {
        ColumnAddRow(name: column?.name ?? store.mobileColumnName) { add(to: column) }
    }

    private func add(to column: BoardColumn?) {
        guard let column else {
            store.addTaskToCurrentMobileColumn()
            return
        }
        store.addTask(to: column.id, title: "", fromPhone: true)
    }

    // MARK: - The drawer, under a finger

    /// How the drawer is settled when the finger comes off, and how it is put
    /// back when a pan is cancelled. Shorter than the tap's 0.28: the panel is
    /// already most of the way there.
    private static let drawerSettle = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.24)

    /// Past this many points a second, the throw decides rather than the
    /// distance — a flick that never reached the middle still means open, which
    /// is how every drawer on this platform reads a pan.
    private static let drawerFlick: CGFloat = 350

    /// The drawer, dragged in. It used to arrive whole on the first report and
    /// slide itself in over 0.28s while the finger went its own way; now the
    /// panel is wherever the finger is, and the animation is only what happens
    /// after it lifts.
    private func drawerPan(_ pan: EdgePan) {
        // The panel's own width, asked the same way the panel asks: a finger
        // that has to cross 803pt to open a 370pt drawer leaves the drawer
        // trailing a third of the way behind it.
        let reach = PhoneNavDrawer.width(in: pan.width, screen: screen)
        switch pan.phase {
        case .began:
            // The same three guards the tap-to-open path had: this recognizer
            // sits under the drawer and the Inbox both, and a sheet is a
            // presentation it cannot see.
            guard !store.isNavDrawerOpen, !store.isInboxOpen, store.sheetID == nil else { return }
            // Into the tree at nothing, without animating: the panel is about
            // to be positioned by a finger, and its own transition would be a
            // second answer to where it is.
            withoutAnimation {
                drawerPull = 0
                store.isNavDrawerOpen = true
            }
        case .changed:
            guard drawerPull != nil, reach > 0 else { return }
            drawerPull = min(1, pan.distance / reach)
        case .ended:
            guard let pulled = drawerPull else { return }
            if pan.velocity > Self.drawerFlick {
                settleDrawer(open: true)
            } else if pan.velocity < -Self.drawerFlick {
                settleDrawer(open: false)
            } else {
                settleDrawer(open: pulled >= 0.5)
            }
        case .cancelled:
            guard drawerPull != nil else { return }
            settleDrawer(open: false)
        }
    }

    /// Finishes the drag, and hands the drawer back to the way it is drawn when
    /// nobody is touching it.
    ///
    /// Opening lets `drawerPull` go before the panel is anywhere else: at 1 it
    /// is exactly where the transition would have put it, so `nil` moves
    /// nothing. Closing has to wait — the panel is only taken out of the tree
    /// once it has finished sliding out of sight, and taking it out is itself
    /// unanimated, because by then there is nothing left to see go.
    private func settleDrawer(open: Bool) {
        Motion.run(Self.drawerSettle, reduceMotion: reduceMotion) {
            drawerPull = open ? 1 : 0
        } completion: {
            guard drawerPull != nil else { return }
            if open {
                drawerPull = nil
            } else {
                withoutAnimation {
                    store.isNavDrawerOpen = false
                    drawerPull = nil
                }
            }
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}

extension BoardStore {
    /// Whether the board itself is on screen with columns to page through, as
    /// opposed to one of the flat lists.
    ///
    /// It used to be the answer to *who owns a horizontal drag here* as well,
    /// because the board's rows had to give up their swipe actions to the pager
    /// while the flat lists kept theirs: a pan beginning on a row is claimed by
    /// whichever recognizer gets there first and an enclosing scroll view always
    /// does — measured both ways round, with a paging `ScrollView` and with a
    /// `TabView(.page)`, and the leading swipe never revealed Complete. That
    /// question has since been settled everywhere rather than per surface: **no
    /// card swipes**, on the board or off it (6.4, and see
    /// ``PhoneTaskRowActions``). What is left here is the layout question it was
    /// named for.
    var isColumnPaging: Bool {
        tab == .board && activeView == nil && !pagerColumns.isEmpty
    }
}

#endif
