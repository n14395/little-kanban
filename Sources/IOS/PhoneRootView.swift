#if os(iOS)

import SwiftUI

/// The iPhone screen: header, optional pager, task list, floating tab bar,
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
    /// answer to *which column*, and two owners of one fact is how the dots
    /// and the page fall out of step.
    @State private var pagedColumnID: BoardColumn.ID?

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
                // and a pager with nothing to step through is two dead arrows.
                if store.isColumnPaging {
                    // Portrait only. Turned on its side the phone shows two
                    // columns at once, each under its own name and count, so
                    // the dots are a second and vaguer copy of what the
                    // headings have already said — and the strip is 44pt of
                    // the one dimension a phone in landscape has least of. The
                    // swipe is unchanged, and so is every route in the header.
                    if !isShort { PhoneColumnPager() }
                    columnPages
                } else {
                    taskList(tasks)
                }
            }

            PhoneTabBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .trashToast(metrics: .phone)
        .background(palette.appBackground.ignoresSafeArea())
        // The drawer is a scrim over the board, so to a sighted user the board
        // is gone. This takes the header, the pager and the tab bar out of the
        // tree with it — but *not* the list: its rows are hosted in collection
        // view cells, which the modifier does not reach, and putting a second
        // one on `taskList` does not reach them either. Measured with the
        // drawer up, every card was still enumerable. What actually keeps a
        // reader out of the board is the drawer's own `.isModal`; this is worth
        // keeping for the three bars it does take, and is not the whole of it.
        .accessibilityHidden(store.isNavDrawerOpen || store.isInboxOpen)
        // The drawer's other way in. The hamburger was the only one, and a
        // panel that slides out from the leading edge is one every other iOS
        // app opens by pulling from that edge. `PadRootView` takes the same
        // modifier for its source list.
        //
        // Guarded rather than unconditional, because two of the three things
        // that can be over the board are *overlays in this tree* — the drawer
        // and the Inbox — so the pan still lands here with either up, and would
        // otherwise re-open what is already open or open a second panel behind
        // the first. The detail sheet is the third: a real presentation, out of
        // this recognizer's reach, and named anyway so the rule reads as one.
        .leadingEdgeSwipe {
            guard !store.isNavDrawerOpen, !store.isInboxOpen, store.sheetID == nil else { return }
            store.isNavDrawerOpen = true
        }
        .overlay {
            if store.isNavDrawerOpen {
                PhoneNavDrawer()
            }
        }
        // Under the drawer rather than over it: the drawer is the way to a
        // *board*, and a board list half-covered by the Inbox is the wrong way
        // round. Both up at once is reachable — the drawer's Inbox row opens
        // this one — and that row closes the drawer on its way.
        .overlay {
            if store.isInboxOpen {
                PhoneInboxSheet()
            }
        }
        .motionAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28), value: store.isNavDrawerOpen)
        .motionAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.28), value: store.isInboxOpen)
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
        .sheet(isPresented: sheetBinding) {
            if let task = store.sheetTask {
                PhoneDetailSheet(task: task)
                    .environment(store)
                    .environment(\.palette, palette)
                    .environment(\.dayClock, dayClock)
            }
        }
    }

    // MARK: - The board, one column per screen

    /// The spec's pager, finally holding the gesture it describes: *"One column
    /// per screen, rubber-band at the ends, dots reflect position"* (seed task
    /// `t4`). It was a strip of dots over a list that did not move.
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

    @ViewBuilder private func page(_ column: BoardColumn) -> some View {
        let tasks = store.boardTasks(in: column.id)

        VStack(spacing: 0) {
            if columnsPerScreen > 1 { heading(column, count: tasks.count) }
            taskList(tasks, in: column)
        }
    }

    /// Which column this page is. Drawn only when more than one is on screen:
    /// in portrait the chips row and the dots directly above have both just
    /// said it, and a third caption would be the count pills 4.4 removed.
    private func heading(_ column: BoardColumn, count: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(palette.resolve(column.dot))
                .frame(width: 7, height: 7)
            Text(column.name)
                .font(SimpleKanbanFont.ui(12.5, .extraBold, relativeTo: .footnote))
                .foregroundStyle(palette.inkText(0.6))
            CountPill(count: count, font: 10.5)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TaskListMetrics.sheet.horizontalPadding)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - The list

    /// `TaskListView`, not a second list: the Search tab, the Inbox tab and a
    /// saved view are the same flat list of cards the desk draws, and this
    /// surface used to hand-roll it — down to a private copy of the row
    /// modifier — while the shared view had a single macOS-only call site.
    /// What is genuinely the phone's stays here as trailing rows.
    ///
    /// `column` is the page's own, and is nil off the board. Two pages are on
    /// screen at once in landscape, so a dashed row that says Doing has to add
    /// to Doing rather than to whichever column the pager happens to be on.
    private func taskList(_ tasks: [TaskItem], in column: BoardColumn? = nil) -> some View {
        TaskListView(
            tasks: tasks, metrics: listMetrics, showsColumn: showsPlaceChips
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

    /// The touch preset, with the room under the last card taken back on a
    /// screen that has none to spare. 130pt is the floating tab bar plus the
    /// space to scroll the last card clear of it, which is a third of a phone
    /// held sideways.
    private var listMetrics: TaskListMetrics {
        var metrics = TaskListMetrics.sheet
        if isShort {
            metrics.topInset = 0
            metrics.bottomInset = 92
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
    /// here, which is a pointer gesture the phone does not have. Everything else
    /// about the state is the same.
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

    /// Dismissing the sheet is also where a quick capture the user never typed
    /// into is thrown away (1.14). This covers the drag-down and any other
    /// route SwiftUI takes to close it; the sheet's own × goes through the same
    /// pair of calls.
    private var sheetBinding: Binding<Bool> {
        Binding(
            get: { store.sheetID != nil },
            set: { isPresented in
                guard !isPresented, let id = store.sheetID else { return }
                store.sheetID = nil
                store.discardIfUntouched(id)
            }
        )
    }
}

extension BoardStore {
    /// Whether the board itself is on screen with columns to page through, as
    /// opposed to one of the flat lists.
    ///
    /// It is also the answer to *who owns a horizontal drag here*, which is why
    /// it is one predicate and not two. A pan that begins on a list row is
    /// claimed by whichever recognizer gets there first, and an enclosing
    /// scroll view always does — measured both ways round, with a paging
    /// `ScrollView` and with a `TabView(.page)`: the leading swipe never
    /// revealed Complete, the board simply turned to the next column. Neither
    /// SwiftUI nor UIKit exposes the failure requirement that would settle it
    /// the other way. So the board's rows do not draw swipe actions they cannot
    /// deliver, and every verb they carried is on the long press instead —
    /// which is where VoiceOver and Switch Control read them from anyway. Off
    /// the board — Inbox, Search, a saved view, the Archive — nothing is
    /// competing and the swipes are untouched.
    var isColumnPaging: Bool {
        tab == .board && activeView == nil && !pagerColumns.isEmpty
    }
}

#endif
