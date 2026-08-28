#if os(macOS)

import SwiftUI

/// The macOS window body: sidebar, whichever surface the sidebar points at,
/// optional inspector, status strip.
struct MacRootView: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    /// The app's, when there is an app: the menu bar toggles the sidebar and it
    /// lives outside every window's view tree, so the state it toggles has to
    /// be owned above the window. Optional because this view must still stand
    /// up without one — `UndoHandoverTests` puts it in a bare `NSHostingView`,
    /// and a preview has no app either. The subtree is handed whichever it got,
    /// so nothing below here has to ask the question twice.
    @Environment(MacWindowState.self) private var injectedWindow: MacWindowState?
    @Environment(\.dayClock) private var dayClock
    @State private var standaloneWindow = MacWindowState()
    /// What the shared board publishes about its own keyboard. The board is
    /// `Sources/Shared` and cannot name a window, so this is where the two are
    /// introduced: the relay is handed down, and mirrored onto the window state
    /// the menu bar reads.
    @State private var focusRelay = BoardFocusRelay()
    /// What File ▸ Import… last did. The settings pane reports the same thing
    /// in its own alert; this is the menu bar's, because the menu bar has no
    /// surface of its own to say it on.
    @State private var transferNotice: SettingsNotice?
    /// The source list's, held here so the window can take itself out of the
    /// accessibility tree while the sheet is up — see `BoardSidebar`.
    @State private var isManagingLabels = false
    /// What the header actually measured. The traffic lights are put on that
    /// row, and the bar grows with the type inside it — so the row is read off
    /// the laid-out bar rather than off the metric it started from.
    @State private var headerHeight = BoardToolbar.Metrics.desk.height

    private var resolvedWindow: MacWindowState { injectedWindow ?? standaloneWindow }

    var body: some View {
        @Bindable var store = store
        @Bindable var window = resolvedWindow

        return HStack(spacing: 0) {
            if window.isSidebarVisible {
                BoardSidebar(isNamingNewBoard: $window.isNamingNewBoard, isManagingLabels: $isManagingLabels)
                    .transition(.move(edge: .leading))
                    // Above the Inbox panel, always. A `.move(edge: .leading)`
                    // transition offsets a view by its own width from where it
                    // sits and nothing clips it on the way, so the panel's
                    // travel takes it across the source list — and, drawn in
                    // `HStack` order, on top of it. Putting the list above is
                    // what makes the panel slide out from *behind* it and stop
                    // at its edge, rather than sail in from the far left of the
                    // window over everything in between.
                    .zIndex(1)
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Full height of everything above the status strip — the
                    // toolbar's row included, so the panel starts at the top of
                    // the window the way the source list does and the board's
                    // name begins where the panel ends.
                    if store.isInboxShowing {
                        InboxPanel(leadingInset: window.isSidebarVisible ? 0 : 68)
                            .transition(.move(edge: .leading))
                    }

                    VStack(spacing: 0) {
                        // The window has no title bar, so this bar is the top of
                        // the window and the traffic lights sit on its row —
                        // which is what the measurement is for. With the sidebar
                        // gone they float over the bar itself; the sidebar keeps
                        // a gap of its own for them, and this is that gap,
                        // moved. The panel keeps the same gap when it is the one
                        // they land on, which is why the toolbar stops needing
                        // it as soon as either is out.
                        BoardToolbar(
                            leadingInset: window.isSidebarVisible || store.isInboxShowing ? 0 : 68
                        )
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                        // The search results hang out of the bar and over the
                        // board and the inspector, which are the next two
                        // siblings down — see `BoardToolbar.resultsPanel`.
                        .zIndex(1)

                        HStack(spacing: 0) {
                            surface
                            // The panel holds its 336pt with nothing selected.
                            // Dropping it reflowed the whole board out from
                            // under a ⌘⌥I that had done exactly what it says,
                            // which read as a broken toggle.
                            //
                            // A child view rather than `store.selectedTask`
                            // read here: the read reached `tasks`, so every
                            // keystroke into any field re-ran — and re-diffed —
                            // the whole window. The pane is where that
                            // dependency now stops.
                            if store.isInspectorOpen {
                                MacInspectorPane()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .boardToast()

                MacStatusBar()
            }
        }
        .background(palette.windowFill)
        // The title bar is hidden but SwiftUI still keeps its 32pt out of the
        // safe area, and that band is the whole reason the header used to read
        // as a strip *under* the chrome: the bar was drawn below the traffic
        // lights rather than around them. Taking it back is what puts the two
        // on one row.
        .ignoresSafeArea(.container, edges: .top)
        // Which is the row the lights are then moved onto.
        .windowButtons(centredAt: headerHeight / 2)
        // A modal takes the pointer away from everything behind it; without
        // this it takes nothing away from a reader. Applied under the sheet
        // modifiers rather than over them, which is what leaves the sheet's own
        // 55 elements published while the 84 behind it go.
        .accessibilityHidden(isManagingLabels)
        // The board's own floor, which is what `.contentMinSize` on the window
        // is measured against. The sidebar can go, so the floor goes with it.
        .frame(minWidth: Self.floor(sidebar: window.isSidebarVisible, inbox: store.isInboxShowing),
               minHeight: 620)
        // No `value: store.selection` here any more: an animation keyed on the
        // selection at the root put every click and every arrow key through a
        // 0.16s diff-and-interpolate of the entire window. The pieces that
        // actually move on selection animate themselves — the inspector pane
        // on its own task, the card on its own ring.
        .motionAnimation(.easeOut(duration: 0.16), value: store.isInspectorOpen)
        .motionAnimation(.easeOut(duration: 0.16), value: store.surface)
        .motionAnimation(.easeOut(duration: 0.16), value: window.isSidebarVisible)
        .motionAnimation(.easeOut(duration: 0.16), value: store.isInboxShowing)
        .sheet(isPresented: $store.isShowingShortcuts) {
            MacShortcutsSheet()
        }
        .sheet(isPresented: $window.isPickingDueDate) {
            MacDueDateSheet()
        }
        // File ▸ Export… / Import…. Presented here rather than by the settings
        // pane so the panel sheets onto the window the menu belongs to; the
        // pane keeps its own pair for the rows inside it.
        .modifier(BoardTransfer(
            isExportingBoard: $store.isExportingBoard,
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
        .environment(resolvedWindow)
        .environment(focusRelay)
        // Both directions, because the menu hands focus on as well as reading
        // it: ⌘⌫ names the neighbour of the card it deleted. Each write is a
        // no-op when the two already agree, so neither can chase the other.
        .onChange(of: focusRelay.focusedTaskID) { _, id in window.focusedTaskID = id }
        .onChange(of: window.focusedTaskID) { _, id in focusRelay.focusedTaskID = id }
        // One way only: nothing outside the board sets which column is under
        // the keyboard, ⌘N only asks.
        .onChange(of: focusRelay.focusedColumnID) { _, id in window.focusedColumnID = id }
    }

    /// The two things the main area can be. The Inbox is not one of them any
    /// more: it is global, a card is in it by being on no board at all, and it
    /// now stands beside the board rather than in front of it — see
    /// ``InboxPanel``.
    @ViewBuilder
    private var surface: some View {
        switch store.surface {
        case .board:
            BoardScrollView()
        case .view(let id):
            MacSavedViewList(viewID: id)
        }
    }
}

extension MacRootView {
    /// The board's own floor, which is what `.contentMinSize` on the window is
    /// measured against: a board worth looking at, plus whatever is beside it.
    /// Both the source list and the Inbox panel can go, so the floor goes with
    /// them — a window pinned to a width for a panel that is not there is a
    /// window you cannot make small.
    static func floor(sidebar: Bool, inbox: Bool) -> CGFloat {
        var width: CGFloat = 708
        if sidebar { width += 232 }
        if inbox { width += InboxPanel.Metrics.desk.width }
        return width
    }
}

/// The inspector column: the selected task's panel, or the empty one.
///
/// A view of its own so that `selectedTask` — a read that reaches both the
/// selection and the whole `tasks` array — is observed *here* rather than by
/// `MacRootView.body`. Any task edit re-renders this pane and nothing above
/// it; the swap between panels keeps the fade the window-level animation used
/// to give it, scoped to the one column that moves.
private struct MacInspectorPane: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        Group {
            if let task = store.selectedTask {
                TaskInspector(task: task)
            } else {
                MacEmptyInspector()
            }
        }
        .motionAnimation(.easeOut(duration: 0.16), value: store.selectedID)
    }
}

/// The detail panel with nothing selected. Carries the same width, ground and
/// seam as `TaskInspector` so the board does not move when a card is picked.
private struct MacEmptyInspector: View {
    @Environment(\.palette) private var palette

    private var chrome = ChromeScale()

    var body: some View {
        EmptyStateView.noSelection(metrics: .desk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The panel's own width, grown by whatever `TaskInspector` grows
            // by, so the board does not step sideways when a card is picked.
            .frame(width: chrome.scaling(TaskInspector.Metrics.desk.width, cap: TaskInspector.widthCap))
            .background(palette.panelOverlay)
            .hairline(.leading, color: palette.ink(0.08))
            .transition(.opacity)
    }
}

/// A saved view in place of the board: the view's name, how many rows are under
/// it, the way back, and the shared flat list underneath.
///
/// The list is `TaskListView` rather than a second implementation — the iOS
/// Search and Inbox tabs draw the same thing, and three copies of "cards from
/// anywhere on the board" would drift apart within a phase.
struct MacSavedViewList: View {
    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store
    /// See `InboxPanel`: the surface's keyboard focus, not each row's.
    @FocusState private var focus: TaskItem.ID?

    /// The view's **id**, looked up on every draw. A `SavedView` handed in
    /// whole would be the one this surface was built with, so a rule edited in
    /// the editor would leave the list underneath it drawing the old one until
    /// something else forced a redraw.
    let viewID: SavedView.ID

    /// `if let` rather than `guard`-and-`AnyView`: erasing the whole surface
    /// hid its structure from SwiftUI's differ, so every invalidation replaced
    /// the subtree — every card in it — instead of diffing into it.
    @ViewBuilder
    var body: some View {
        if let view = store.view(id: viewID) {
            content(view)
        }
    }

    /// **No header over the list.** The view is named in the toolbar's title
    /// now — see ``BoardToolbar`` — so a strip under it repeating the name, the
    /// symbol and a Back to Board button was the same answer given twice and a
    /// second way out of a place the source list is already one click from.
    @ViewBuilder private func content(_ view: SavedView) -> some View {
        let tasks = store.tasks(in: view, today: dayClock.today)

        VStack(spacing: 0) {
            if tasks.isEmpty {
                emptyState(view)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The card the flat surfaces draw is the keyboard-reachable
                // one: ⌘A, ⌘C, ⌘V, ⎋ and ↑/↓ read here exactly as they do on
                // the board, less the two pairs that need columns.
                //
                // Columns rather than one long run down the middle — see
                // ``TaskColumnsView``. The order the arrows walk is unchanged,
                // because the order is unchanged: it now runs down a column and
                // on to the top of the next instead of down a single list.
                TaskColumnsView(tasks: tasks, metrics: .desk) { task in
                    PlatformTaskCard(task: task, focus: $focus)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One emptiness now: a view nobody has filed anything into yet, saying
    /// what would land in it. The query no longer narrows a view on this
    /// platform — it opens ``SearchResultsPanel`` over whatever is on screen —
    /// so "the query emptied it" is not one of the states this can be in.
    private func emptyState(_ view: SavedView) -> some View {
        EmptyStateView.savedView(view, metrics: .desk)
    }
}

#endif
