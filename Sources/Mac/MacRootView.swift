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

    private var resolvedWindow: MacWindowState { injectedWindow ?? standaloneWindow }

    var body: some View {
        @Bindable var store = store
        @Bindable var window = resolvedWindow

        return HStack(spacing: 0) {
            if window.isSidebarVisible {
                BoardSidebar(isNamingNewBoard: $window.isNamingNewBoard, isManagingLabels: $isManagingLabels)
                    .transition(.move(edge: .leading))
            }

            VStack(spacing: 0) {
                // The window has no title bar, so with the sidebar gone the
                // traffic lights float over the toolbar. The sidebar keeps a
                // gap of its own for them; this is that gap, moved.
                BoardToolbar(leadingInset: window.isSidebarVisible ? 0 : 68)

                HStack(spacing: 0) {
                    surface
                    // The panel holds its 336pt with nothing selected. Dropping
                    // it reflowed the whole board out from under a ⌘⌥I that had
                    // done exactly what it says, which read as a broken toggle.
                    if store.isInspectorOpen {
                        if let task = store.selectedTask {
                            TaskInspector(task: task)
                        } else {
                            MacEmptyInspector()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                MacStatusBar()
            }
        }
        .background(palette.window)
        // A modal takes the pointer away from everything behind it; without
        // this it takes nothing away from a reader. Applied under the sheet
        // modifiers rather than over them, which is what leaves the sheet's own
        // 55 elements published while the 84 behind it go.
        .accessibilityHidden(isManagingLabels)
        // The board's own floor, which is what `.contentMinSize` on the window
        // is measured against. The sidebar can go, so the floor goes with it.
        .frame(minWidth: window.isSidebarVisible ? 940 : 708, minHeight: 620)
        .motionAnimation(.easeOut(duration: 0.16), value: store.isInspectorOpen)
        .motionAnimation(.easeOut(duration: 0.16), value: store.selection)
        .motionAnimation(.easeOut(duration: 0.16), value: store.surface)
        .motionAnimation(.easeOut(duration: 0.16), value: window.isSidebarVisible)
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
            snapshot: store.exportedSnapshot,
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

    /// The three things the main area can be. The Inbox is one of them rather
    /// than a column of the board: it is global, and a card is in it by being
    /// on no board at all.
    @ViewBuilder
    private var surface: some View {
        switch store.surface {
        case .board:
            BoardScrollView()
        case .inbox:
            MacInboxList()
        case .view(let view):
            MacSavedViewList(view: view)
        }
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
            .background(palette.panel)
            .hairline(.leading, color: palette.ink(0.08))
            .transition(.opacity)
    }
}

/// The global Inbox in place of the board: everything filed nowhere.
///
/// The same shape as `MacSavedViewList` — header, count, the way back, the
/// shared flat list — because it is the same kind of surface: cards drawn from
/// outside any one column. It is not a saved view, though. A card is *in* the
/// Inbox rather than merely matching it, so this one can be composed into, and
/// the sidebar row it belongs to takes drops.
struct MacInboxList: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    /// Which row the keyboard is on. Owned here rather than by the rows for
    /// `BoardScrollView`'s reason: ↑ and ↓ cross rows, and a row cannot see its
    /// neighbours.
    @FocusState private var focus: TaskItem.ID?

    private var isComposing: Bool { store.addingPlacement == .inbox }

    var body: some View {
        let tasks = store.visibleInboxTasks

        VStack(spacing: 0) {
            header(count: tasks.count)
            // Carries the list's own margins so the field lines up with the
            // cards under it rather than with the header above it.
            if isComposing {
                BoardTaskComposer(placement: .inbox)
                    .frame(maxWidth: TaskListMetrics.desk.maxRowWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, TaskListMetrics.desk.horizontalPadding)
                    .padding(.top, TaskListMetrics.desk.topInset)
            }
            if tasks.isEmpty, !isComposing {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The card the flat surfaces draw is the keyboard-reachable
                // one: ⌘A, ⌘C, ⌘V, ⎋ and ↑/↓ read here exactly as they do on
                // the board, less the two pairs that need columns.
                TaskListView(tasks: tasks, metrics: .desk) { task in
                    PlatformTaskCard(task: task, focus: $focus)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 12) {
            Button { store.selectSurface(.board) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .imageScale(.small)
                    Text("Board", comment: "Button that leaves the Inbox for the column board")
                        .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .subheadline))
                }
                .foregroundStyle(palette.inkText(0.55))
                .padding(.horizontal, 9)
                .frame(minHeight: 28)
                .hoverBackground(palette.ink(0.06), radius: 9)
            }
            .buttonStyle(.bare)
            // The chevron beside the word is decoration, and a label on the
            // button does not take it out of the tree — it stays as a second
            // element named from Apple's catalogue. Substituting the subtree
            // does, and leaves the button saying what it does.
            .accessibilityRepresentation {
                Button(String(localized: "Back to the board",
                              comment: "Accessibility name of the button leaving the Inbox or a saved view")) {
                    store.selectSurface(.board)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "tray")
                    .imageScale(.small)
                    .foregroundStyle(palette.inkText(0.45))
                    .accessibilityHidden(true)
                Text(Board.inboxName)
                    .font(SimpleKanbanFont.ui(14, .extraBold, relativeTo: .headline))
                    .foregroundStyle(palette.ink)
                CountPill(count: count)
            }

            Spacer(minLength: 0)

            Button { store.beginAdding(in: .inbox) } label: {
                Image(systemName: "plus")
                    .font(SimpleKanbanFont.ui(12, .medium, relativeTo: .footnote))
                    .foregroundStyle(palette.inkText(0.45))
                    .frame(minWidth: 24, minHeight: 24)
            }
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.08), radius: 8)
            .accessibilityLabel("Capture a task")
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 46)
        .hairline(.bottom, color: palette.ink(0.07))
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.isFiltering {
            EmptyStateView.noResults(query: store.query, metrics: .desk) {
                store.clearQuery()
            }
        } else {
            EmptyStateView.inbox(metrics: .desk) {
                store.beginAdding(in: .inbox)
            }
        }
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
    /// See `MacInboxList`: the surface's keyboard focus, not each row's.
    @FocusState private var focus: TaskItem.ID?

    let view: SavedView

    var body: some View {
        // Resolved once and handed down: the header counts the rows it heads,
        // so both have to be the same array.
        let tasks = store.tasks(in: view, today: dayClock.today)

        VStack(spacing: 0) {
            header(count: tasks.count)
            if tasks.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The card the flat surfaces draw is the keyboard-reachable
                // one: ⌘A, ⌘C, ⌘V, ⎋ and ↑/↓ read here exactly as they do on
                // the board, less the two pairs that need columns.
                TaskListView(tasks: tasks, metrics: .desk) { task in
                    PlatformTaskCard(task: task, focus: $focus)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The pill counts what is on screen, not what is in the view. The sidebar
    /// row's pill is the unnarrowed membership and stays that way — it is a
    /// badge on a destination — but a count sitting directly on top of a list
    /// is read as that list's length, and reading "7" above "Nothing matched"
    /// makes the search look broken rather than the view look full.
    private func header(count: Int) -> some View {
        HStack(spacing: 12) {
            Button { store.selectSurface(.board) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .imageScale(.small)
                    Text("Board", comment: "Button that leaves a saved view for the column board")
                        .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .subheadline))
                }
                .foregroundStyle(palette.inkText(0.55))
                .padding(.horizontal, 9)
                .frame(minHeight: 28)
                .hoverBackground(palette.ink(0.06), radius: 9)
            }
            .buttonStyle(.bare)
            // See `MacInboxList`: the chevron is a nested element a label alone
            // does not remove.
            .accessibilityRepresentation {
                Button(String(localized: "Back to the board",
                              comment: "Accessibility name of the button leaving the Inbox or a saved view")) {
                    store.selectSurface(.board)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: view.symbol)
                    .imageScale(.small)
                    .foregroundStyle(palette.inkText(0.45))
                    .accessibilityHidden(true)
                Text(view.label)
                    .font(SimpleKanbanFont.ui(14, .extraBold, relativeTo: .headline))
                    .foregroundStyle(palette.ink)
                CountPill(count: count)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 46)
        .hairline(.bottom, color: palette.ink(0.07))
    }

    /// Two different emptinesses, and the difference is the whole point: a view
    /// nobody has filed anything into yet says what would land in it, and a view
    /// the query has emptied offers to drop the query.
    @ViewBuilder
    private var emptyState: some View {
        if store.isFiltering {
            EmptyStateView.noResults(query: store.query, metrics: .desk) {
                store.clearQuery()
            }
        } else {
            EmptyStateView.savedView(view, metrics: .desk)
        }
    }
}

#endif
