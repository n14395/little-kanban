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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var chrome = ChromeScale()

    /// A flat list on a 13" display — `TaskListMetrics.pad`, named beside its
    /// siblings rather than here, so a test can enumerate it.
    private static let listMetrics = TaskListMetrics.pad

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .environment(focusRelay)
        .background(palette.appBackground.ignoresSafeArea())
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
        .background(palette.sidebar)
        .navigationSplitViewColumnWidth(
            min: chrome(260, cap: 1.4), ideal: chrome(300, cap: 1.4), max: chrome(360, cap: 1.4)
        )
        // The bar would draw a second, empty header above our own.
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The toolbar, and under it the board with its panel beside it.
    ///
    /// The panel is laid out here rather than taken from `.inspector` on the
    /// detail column. That spelling put the panel over the *whole* column,
    /// toolbar included: in portrait with the source list out, the New task
    /// button measured 117×44 at x=839 inside a 1032pt window and reported
    /// `hittable=false`, because the inspector was drawn on top of it. The
    /// primary action of the surface was unreachable in one of the two
    /// orientations. An `HStack` under the toolbar is what macOS does with the
    /// same three pieces — see `MacRootView` — and it cannot cover a sibling.
    private var detail: some View {
        VStack(spacing: 0) {
            BoardToolbar(metrics: .pad, toggleSidebar: toggleSidebar)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.window)
        .motionAnimation(.easeOut(duration: 0.16), value: store.isInspectorOpen)
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
    /// The board's own floor: one `.pad` column and the strip's margins. Below
    /// it the panel stops being a column and becomes an overlay.
    private var boardFloor: CGFloat { chrome(BoardColumnView.Metrics.pad.width) + 32 }

    private var hasRoomBesideTheBoard: Bool {
        // Zero before the first layout pass, which must not read as "no room":
        // the panel would flash as an overlay on the way in.
        rowWidth <= 0 || rowWidth - inspectorWidth >= boardFloor
    }

    /// The three things the main area can be, exactly as on the desk: the Inbox
    /// is one of them rather than a column of the board, because it is global.
    @ViewBuilder
    private var surface: some View {
        switch store.surface {
        case .board:
            BoardScrollView(metrics: .pad)
        case .inbox:
            inboxList
        case .view(let view):
            savedViewList(view)
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
                    .background(palette.panel)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// `.automatic` is whatever the system chose, and the first press has to
    /// mean something either way round: in landscape it hides the list, in
    /// portrait — where the list is already off screen — it brings it out.
    private func toggleSidebar() {
        Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    // MARK: The flat surfaces

    /// Everything filed nowhere. Composable, unlike a saved view: a card is
    /// *in* the Inbox rather than merely matching it.
    private var inboxList: some View {
        let tasks = store.visibleInboxTasks
        let isComposing = store.addingPlacement == .inbox

        return VStack(spacing: 0) {
            header(symbol: "tray", title: Board.inboxName, count: tasks.count) {
                store.beginAdding(in: .inbox)
            }
            if isComposing {
                BoardTaskComposer(placement: .inbox, metrics: .pad)
                    .frame(maxWidth: Self.listMetrics.maxRowWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Self.listMetrics.horizontalPadding)
                    .padding(.top, Self.listMetrics.topInset)
            }
            if tasks.isEmpty, !isComposing {
                inboxEmptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(tasks)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
        TaskListView(tasks: tasks, metrics: Self.listMetrics) { task in
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
                .font(SimpleKanbanFont.ui(17, .extraBold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
            CountPill(count: count)

            Spacer(minLength: 0)

            if let add {
                Button(action: add) {
                    Image(systemName: "plus")
                        .font(SimpleKanbanFont.ui(15, .medium, relativeTo: .body))
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

    @ViewBuilder
    private var inboxEmptyState: some View {
        if store.isFiltering {
            EmptyStateView.noResults(query: store.query, metrics: .sheet) {
                store.clearQuery()
            }
        } else {
            EmptyStateView.inbox(metrics: .sheet) { store.beginAdding(in: .inbox) }
        }
    }

    @ViewBuilder
    private func savedViewEmptyState(_ view: SavedView) -> some View {
        if store.isFiltering {
            EmptyStateView.noResults(query: store.query, metrics: .sheet) {
                store.clearQuery()
            }
        } else {
            EmptyStateView.savedView(view, metrics: .sheet)
        }
    }
}

#endif
