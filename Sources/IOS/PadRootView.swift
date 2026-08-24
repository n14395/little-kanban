#if os(iOS)

import SwiftUI

/// The iPad screen: the desk's three panes — source list, board, inspector —
/// in a `NavigationSplitView`.
///
/// Every one of those panes is the same view macOS draws, at its `.pad`
/// metrics: `BoardSidebar`, `BoardToolbar`, `BoardScrollView` and
/// `TaskInspector` all live in `Sources/Shared` precisely so this file does not
/// have to be a third copy of the board. What is genuinely the iPad's is the
/// container and the two flat surfaces below, which are a list and a heading.
///
/// A split view rather than a layout of our own because slide-over, Stage
/// Manager and the sidebar's show/hide behaviour come with it; the drawer the
/// phone uses would have to reimplement all three.
struct PadRootView: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock

    /// Whether the source list is showing. `.automatic` lets the system decide
    /// on the way in — beside the board in landscape, over it in portrait — and
    /// the toolbar's button drives it from there.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    /// The board's own; see ``BoardFocusRelay``. Nothing outside the view tree
    /// reads it here — iPadOS has no menu bar of ours — but the board asks it
    /// which column the keyboard is in before scrolling, and without one it
    /// would re-centre the strip under every arrow press.
    @State private var focusRelay = BoardFocusRelay()
    /// Which row the keyboard is on in the flat surfaces. Owned here for
    /// `BoardScrollView`'s reason: ↑ and ↓ cross rows, and a row cannot see its
    /// neighbours.
    @FocusState private var focus: TaskItem.ID?
    /// How wide the board and the panel have to share, measured rather than
    /// assumed: an iPad's detail pane changes width with the source list, the
    /// orientation and Stage Manager, and the panel is a column only while
    /// there is a column's worth left for the board.
    @State private var rowWidth: CGFloat = 0
    /// The whole detail column, panel included — which `rowWidth` is not, since
    /// the panel is that row's sibling. Measuring the room for the panel off a
    /// width the panel is subtracted from is a feedback loop: it fits, so it
    /// appears, so the row shrinks, so it no longer fits. Measured once, here.
    @State private var detailWidth: CGFloat = 0
    /// The whole split view, source list included — which `detailWidth` is not.
    /// The difference between the two is what the list is costing the board, and
    /// that difference is the only thing that knows whether this window can hold
    /// both of the panels that open on its left. See ``hasRoomForBothSidebars``.
    @State private var windowWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var chrome = ChromeScale()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        // Two panels open on the left of this window — the source list and the
        // Inbox — and where it cannot hold both, the one being opened takes the
        // room from the other. See ``hasRoomForBothSidebars``.
        //
        // `isInboxShowing` rather than `isInboxOpen`: the panel stands beside the
        // board and a saved view has taken the board's place, so on Today the
        // flag is set and there is nothing on screen to make room for.
        .onChange(of: store.isInboxShowing) { _, showing in
            guard showing, !hasRoomForBothSidebars else { return }
            Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
                columnVisibility = .detailOnly
            }
        }
        // And the other way. Keyed on the list *taking width* rather than on
        // `columnVisibility`, which is a request rather than an outcome: the
        // split view answers `.automatic` itself and writes its answer back into
        // the binding, and it can draw the list over the board instead of beside
        // it — in which case the list costs the board nothing and there is
        // nothing to make room for. What is watched here is the fact.
        .onChange(of: sidebarIsBesideTheBoard) { _, beside in
            guard beside, !hasRoomForBothSidebars else { return }
            store.isInboxOpen = false
        }
        // The source list's other way in, and the same gesture the phone's
        // drawer answers. A split view looks like it should bring this with it
        // — `UISplitViewController` has `presentsWithGesture` — and measured on
        // an iPad Pro 13" in portrait it does not: a pull from x=0 across the
        // board left the list where it was. What claims that pan is the board's
        // own horizontal scroll view, which is exactly what `leadingEdgeSwipe`
        // is built to outrank.
        .leadingEdgeSwipe(perform: revealSidebar)
        .trashToast(metrics: .sheet)
        .environment(focusRelay)
        .background(palette.windowFill.ignoresSafeArea())
        .motionAnimation(.easeOut(duration: 0.16), value: store.surface)
        // The same two acts the phone marks (5.8): picking where you are.
        .sensoryFeedback(.selection, trigger: store.surface)
    }

    // MARK: Panes

    /// In a scroll view because the list is taller than a landscape iPad mini
    /// once every row claims its 44pt, and a source list that cannot reach its
    /// last row is worse than one that scrolls.
    private var sidebar: some View {
        ScrollView {
            BoardSidebar(metrics: .pad)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(palette.panelOverlay)
        .navigationSplitViewColumnWidth(
            min: chrome(260, cap: 1.4), ideal: chrome(Self.sidebarIdeal, cap: 1.4),
            max: chrome(360, cap: 1.4)
        )
        // The bar would draw a second, empty header above our own.
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The toolbar, and under it the board with its panel beside it.
    ///
    /// The panel is laid out here rather than taken from `.inspector` on the
    /// detail column. That spelling put the panel over the *whole* column,
    /// toolbar included: in portrait with the source list out, the bar's capture
    /// button — a labelled **New task** then, 117×44 — measured at x=839 inside
    /// a 1032pt window and reported `hittable=false`, because the inspector was
    /// drawn on top of it. The primary action of the surface was unreachable in
    /// one of the two orientations. An `HStack` under the toolbar is what macOS does with the
    /// same three pieces — see `MacRootView` — and it cannot cover a sibling.
    private var detail: some View {
        HStack(spacing: 0) {
            // Full height of the detail column, toolbar row included, so the
            // panel starts where the source list stops — the same place it
            // starts on the desk.
            if store.isInboxShowing, hasRoomForTheInbox {
                InboxPanel(metrics: .pad)
                    .transition(.move(edge: .leading))
            }

            VStack(spacing: 0) {
            BoardToolbar(metrics: .pad, toggleSidebar: toggleSidebar)
                // The search results hang out of the bar and over the board and
                // the inspector, which are the next two siblings down — see
                // `BoardToolbar.resultsPanel`.
                .zIndex(1)
            HStack(spacing: 0) {
                surface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.isInspectorOpen, hasRoomBesideTheBoard {
                    inspector
                        .frame(width: inspectorWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Where there is not room for both, the panel goes *over the
            // board* — never over the toolbar, which is the whole point. An
            // iPad mini in portrait with the source list out leaves 166pt of
            // detail beside a 348pt panel, and 166pt is half a column: showing
            // the board underneath is worth more than showing a sliver of it.
            .overlay(alignment: .trailing) {
                if store.isInspectorOpen, !hasRoomBesideTheBoard {
                    inspector
                        .frame(width: inspectorWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
        // The Inbox panel's `.move(edge: .leading)` takes it a column's width
        // to the left of where it sits, and the split view does not clip its
        // detail column — so without this the panel slides in from the far left
        // of the *window*, across the source list, and out the same way. The
        // desk answers the same thing by drawing the source list above the
        // panel; here the two are in different containers, so `zIndex` has
        // nothing to say and the column has to hold its own edge.
        .clipped()
        .background(palette.windowFill)
        .motionAnimation(.easeOut(duration: 0.16), value: store.isInspectorOpen)
        .motionAnimation(.easeOut(duration: 0.16), value: store.isInboxShowing)
        .motionAnimation(.easeOut(duration: 0.16), value: store.selection)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// What `.inspector`'s ideal width was. A fixed column rather than a
    /// resizable one: the divider came with `.inspector`, and so did drawing
    /// over the toolbar.
    /// Both grow with the reader's text size, by the same factor the panel and
    /// the columns inside them do — otherwise a 348pt slot holds a panel that
    /// has grown to 470 and clips it, and the floor lets a column through that
    /// is no longer wide enough to draw.
    private var inspectorWidth: CGFloat { chrome(Self.baseInspectorWidth, cap: TaskInspector.widthCap) }
    private static let baseInspectorWidth: CGFloat = 348
    /// What the split view lays the source list out at, named once because two
    /// things read it: the column-width modifier that asks for it, and
    /// ``sidebarWidth``, which has to know what the list would take while the
    /// list is not there to be measured.
    static let sidebarIdeal: CGFloat = 300

    /// The board's own floor: one `.pad` column and the strip's margins. Below
    /// it the panel stops being a column and becomes an overlay.
    private var boardFloor: CGFloat { chrome(BoardColumnView.Metrics.pad.width) + 32 }

    private var hasRoomBesideTheBoard: Bool {
        // Zero before the first layout pass, which must not read as "no room":
        // the panel would flash as an overlay on the way in.
        rowWidth <= 0 || rowWidth - inspectorWidth >= boardFloor
    }

    /// What the source list is taking from the board right now: the difference
    /// between the window and the detail column. Zero when it is not out — and
    /// zero as well when the system has drawn it *over* the board rather than
    /// beside it, which is the right answer both times, because this is what the
    /// list costs the board rather than whether it is on screen.
    private var sidebarCost: CGFloat { max(0, windowWidth - detailWidth) }
    private var sidebarIsBesideTheBoard: Bool { sidebarCost > 1 }

    /// The width the list takes when it is out, whether or not it is out now:
    /// measured while it is, and the column's own ideal while it is not. There
    /// is nothing to measure then, and the ideal is what the split view lays it
    /// out at — the same estimate-rather-than-oscillate trade `BoardToolbar`
    /// makes about its own row.
    private var sidebarWidth: CGFloat {
        sidebarIsBesideTheBoard ? sidebarCost : chrome(Self.sidebarIdeal, cap: 1.4)
    }

    /// Whether this window can hold the source list, the Inbox panel and a board
    /// worth looking at, all at once.
    ///
    /// Where it cannot, the two panels take turns: opening either closes the
    /// other. That is the alternative to what this shape used to do, which was
    /// nothing at all — `hasRoomForTheInbox` simply declined to draw the panel,
    /// so on an 11" in portrait with the list out the Inbox button was a control
    /// that did not appear to work. Both of these open on the left of the same
    /// window and both are a column wide; asking the user to close one before
    /// the other will open is asking them to work out an arithmetic they cannot
    /// see.
    private var hasRoomForBothSidebars: Bool {
        Self.holdsBothSidebars(
            window: windowWidth,
            sidebar: sidebarWidth,
            inspector: store.isInspectorOpen ? inspectorWidth : 0,
            panel: chrome(InboxPanel.Metrics.pad.width),
            floor: boardFloor
        )
    }

    /// Whether the Inbox panel fits without taking the board's last column.
    ///
    /// The inspector answers this by moving on top of the board when it will
    /// not fit; the Inbox cannot borrow that trick, because it sits *above* the
    /// toolbar and an overlay there is exactly the defect the panel's own
    /// comment describes — the button drawn over and unhittable. So it waits
    /// instead.
    ///
    /// **And it waits for the board alone.** The inspector's width used to count
    /// against this too, which looked like arithmetic and behaved like a dead button:
    /// an 11" in portrait is 834pt, and 834 less the inspector's 348 and the
    /// panel's 320 is 166 — so with a task selected the panel went on declining
    /// *after* the source list had closed to make room for it, and the Inbox
    /// button did nothing but put the source list away. The inspector needs no
    /// room reserved here precisely because it has its own answer to being
    /// squeezed: it draws over the board. This one counts what cannot move.
    ///
    /// What is left for it to decline is a detail column with no room for a
    /// panel and a board at all — 672pt, down where `RootSurface` is about to
    /// hand the window to the phone's layout anyway.
    private var hasRoomForTheInbox: Bool {
        Self.holdsTheInbox(
            detail: detailWidth, panel: chrome(InboxPanel.Metrics.pad.width), floor: boardFloor
        )
    }

    /// The two things the main area can be, exactly as on the desk. The Inbox
    /// is not one of them: it is global, and it now stands beside the board in
    /// a panel of its own rather than taking the board's place.
    @ViewBuilder
    private var surface: some View {
        switch store.surface {
        case .board:
            BoardScrollView(metrics: .pad)
        case .view(let id):
            // Looked up on every draw rather than carried: the view is editable
            // now, so a copy taken when the surface was chosen would go on
            // drawing the rule the editor has just changed.
            if let view = store.view(id: id) { savedViewList(view) }
        }
    }

    /// The panel holds its column with nothing selected, the way the desk's
    /// does: dropping it would reflow the board out from under the toggle that
    /// had just done what it says.
    @ViewBuilder
    private var inspector: some View {
        Group {
            if let task = store.selectedTask {
                TaskInspector(task: task, metrics: .pad)
            } else {
                EmptyStateView.noSelection(metrics: .sheet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.panelOverlay)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Whether a window this wide holds both of the panels that open on its left
    /// and still leaves a board worth looking at.
    ///
    /// Static and arithmetic so that `PadSurfaceTests` can ask it: what it
    /// decides is which of two panels closes, and a rule that only a booted iPad
    /// can be asked is one that gets re-derived by hand every time somebody
    /// changes a column's width.
    ///
    /// Zero before the first layout pass reads as *room for both*, which is the
    /// safe way round: the alternative is a window that shuts one of its panels
    /// on the way in.
    static func holdsBothSidebars(
        window: CGFloat, sidebar: CGFloat, inspector: CGFloat,
        panel: CGFloat, floor: CGFloat
    ) -> Bool {
        guard window > 0 else { return true }
        return window - sidebar - inspector - panel >= floor
    }

    /// Whether a detail column this wide holds the Inbox panel and a board.
    ///
    /// The inspector is deliberately not an argument — ``hasRoomForTheInbox``
    /// says why — and the pair of rules have an invariant between them that only
    /// a test can hold: every window ``holdsBothSidebars`` turns down is a window
    /// this has to accept once the source list has gone. Where it does not, the
    /// Inbox button closes the source list and nothing else happens.
    ///
    /// Zero reads as *room* for the same reason as above: the first layout pass
    /// must not shut a panel on the way in.
    static func holdsTheInbox(detail: CGFloat, panel: CGFloat, floor: CGFloat) -> Bool {
        guard detail > 0 else { return true }
        return detail - panel >= floor
    }

    /// `.automatic` is whatever the system chose, and the first press has to
    /// mean something either way round: in landscape it hides the list, in
    /// portrait — where the list is already off screen — it brings it out.
    private func toggleSidebar() {
        Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    /// A pull from the edge only ever means *show me the list*. It is not the
    /// button's other half: in landscape the list is already beside the board,
    /// and a gesture that put it away would be the swipe undoing itself on the
    /// one shape where the edge and the list are the same place.
    private func revealSidebar() {
        guard columnVisibility != .all else { return }
        Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
            columnVisibility = .all
        }
    }

    // MARK: The flat surfaces

    private func savedViewList(_ view: SavedView) -> some View {
        // Resolved once and handed to both, so the count above the list is the
        // length of the list under it.
        let tasks = store.tasks(in: view, today: dayClock.today)

        return VStack(spacing: 0) {
            header(symbol: view.symbol, title: view.label, count: tasks.count)
            if tasks.isEmpty {
                savedViewEmptyState(view)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(tasks)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The same card the board draws, not the phone's. Tapping it selects and
    /// opens the inspector — this surface has one — where a tap on the phone
    /// raises a sheet the iPad never presents; and the keyboard reaches these
    /// rows for the same reason the desk's do.
    private func list(_ tasks: [TaskItem]) -> some View {
        TaskColumnsView(tasks: tasks, metrics: .pad) { task in
            ListCard(task: task, metrics: .pad, focus: $focus)
        }
    }

    /// No "back to the board" button: the source list is one tap away and every
    /// destination in it is a row, which is the whole reason the iPad has a
    /// split view and the phone has a drawer.
    private func header(
        symbol: String, title: String, count: Int, add: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .imageScale(.medium)
                .foregroundStyle(palette.inkText(0.45))
                .accessibilityHidden(true)
            Text(title)
                .font(palette.ui(17, .extraBold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
            CountPill(count: count)

            Spacer(minLength: 0)

            if let add {
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(palette.ui(15, .medium, relativeTo: .body))
                        .foregroundStyle(palette.inkText(0.45))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bare)
                .accessibilityLabel("Capture a task")
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 60)
        .hairline(.bottom, color: palette.ink(0.07))
    }

    /// One emptiness now: a view with nothing in it. The query opens
    /// ``SearchResultsPanel`` over the board rather than narrowing what is
    /// behind it, so a view the search emptied is not a state this can be in.
    private func savedViewEmptyState(_ view: SavedView) -> some View {
        EmptyStateView.savedView(view, metrics: .sheet)
    }
}

#endif
