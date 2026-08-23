#if os(iOS)

import SwiftUI

/// The iPhone screen: header, task list or paged board, floating tab bar,
/// plus the drawer, the Inbox slide-over and the detail sheet over the top.
struct PhoneRootView: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock
    /// Compact height is the phone on its side, which is the one shape with
    /// room for two columns at once (5.5). A size class rather than an
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

    var body: some View {
        // Resolved once and handed to both: the saved-view bar's count pill and
        // the list under it are then the same array by construction, and cannot
        // drift apart the way they did while the header counted the view's
        // membership and the list drew the query's result.
        let tasks = store.mobileTasks(today: dayClock.today)

        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                PhoneHeader(listCount: tasks.count)
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
        .trashToast(metrics: isShort ? .sheet : .phone)
        .background(palette.appBackground.ignoresSafeArea())
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
        .overlay {
            if store.isNavDrawerOpen {
                PhoneNavDrawer(progress: drawerPull ?? 1)
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
        .sheet(isPresented: inboxPresentation) {
            PhoneInboxSheet()
                .environment(store)
                .environment(\.palette, palette)
                .environment(\.dayClock, dayClock)
        }
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
    }

    private var inboxPresentation: Binding<Bool> {
        Binding(get: { store.isInboxOpen }, set: { store.isInboxOpen = $0 })
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
    /// not a screenful: in landscape two of them share the width and the swipe
    /// still advances by one, which `.paging` — which steps by the viewport —
    /// cannot express. The bounce at either end is the scroll view's own.
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

    /// How many columns share the screen. Two only where there is width for
    /// them, which on a phone is landscape — the shape 5.5 unlocks.
    private var columnsPerScreen: Int {
        isShort && store.pagerColumns.count > 1 ? 2 : 1
    }

    /// A page is a column, and is drawn by ``PhoneColumnPage`` rather than by
    /// the flat list below: a column has ground around its cards that means
    /// *put it here*, and a `List` is the one container that will not let a
    /// finger say so. The two rows under the cards are still built here,
    /// because the flat list needs the same two.
    @ViewBuilder private func page(_ column: BoardColumn) -> some View {
        let tasks = store.boardTasks(in: column.id)

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
            return store.activeBoard == nil ? noBoard : emptyColumn(column)
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

    private func addRow(in column: BoardColumn?) -> some View {
        Button { add(to: column) } label: {
            Text("+ Add task to \(column?.name ?? store.mobileColumnName)")
                .font(SimpleKanbanFont.ui(13.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.inkText(0.45))
                .frame(maxWidth: .infinity)
                .padding(14)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            palette.ink(0.18),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                }
        }
        .buttonStyle(.bare)
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
        let reach = pan.width * PhoneNavDrawer.widthFraction
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
