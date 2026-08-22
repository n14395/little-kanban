#if os(iOS)

import SwiftUI

/// The slide-over board list. The design specifies a drawer at 84% width with a
/// scrim, so this stays a custom overlay rather than a navigation split view.
struct PhoneNavDrawer: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var isManagingLabels = false
    @State private var isEditingReminders = false
    @State private var isCreatingBoard = false
    /// The board whose editor is open. A snapshot only names which one — the
    /// editor reads the board back out of the store, so a rename inside it does
    /// not leave the sheet holding the old one.
    @State private var editingBoard: Board?
    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            palette.ink(0.3)
                .ignoresSafeArea()
                .onTapGesture { store.isNavDrawerOpen = false }
                .transition(.opacity)
                // The scrim is the drawer's own ground, not a control: without
                // this it reads as an unlabelled element between the panel and
                // the board it is hiding.
                .accessibilityHidden(true)

            panel
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.84 }
                .transition(.move(edge: .leading))
                // `@AccessibilityFocusState`, not the keyboard's — this moves
                // the VoiceOver cursor into the drawer, and `focusWhenReady` is
                // about a text field taking key input. The two are different
                // focuses and only one of them has the run-loop problem.
                .onAppear { isTitleFocused = true }
        }
        // What actually keeps a reader inside the drawer. `PhoneRootView`'s
        // `accessibilityHidden` takes the bars behind it out of the tree but
        // cannot reach the list's cells, so without this every card under the
        // scrim is still reachable by swiping past the drawer's last row.
        .accessibilityAddTraits(.isModal)
        // Hosted here, and the drawer deliberately stays open behind it: the
        // panel is what presents the sheet, so closing the drawer first would
        // take the presentation down with it. The board editor and the new-board
        // prompt are here for the same reason.
        .labelManagerSheet(isPresented: $isManagingLabels, metrics: .sheet)
        .sheet(isPresented: $isEditingReminders) {
            PhoneRemindersSheet()
                .environment(\.palette, palette)
                .tint(palette.accent)
        }
        .sheet(item: $editingBoard) { board in
            PhoneBoardEditor(boardID: board.id)
                .environment(store)
                .environment(\.palette, palette)
                .tint(palette.accent)
        }
        .newBoardAlert(isPresented: $isCreatingBoard) { _ in
            // A new board is the one the user is now on, and the drawer is over
            // it. The prompt has already dismissed itself by the time this runs,
            // so taking the drawer down with it is safe.
            store.isNavDrawerOpen = false
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // The product's own name, read off the bundle and shown
                // verbatim: it is spelled the same in every language, and a
                // literal in a `Text` would have offered it to a translator.
                Text(verbatim: Self.wordmark)
                    .font(SimpleKanbanFont.serif(26))
                    // Opening the drawer has to move the VoiceOver cursor into
                    // it. Landing on the heading rather than the first row is
                    // what lets the reader hear where they are before they hear
                    // what is on offer.
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
                Spacer(minLength: 0)
                Button { store.isNavDrawerOpen = false } label: {
                    Image(systemName: "xmark")
                        .font(SimpleKanbanFont.ui(12, .semibold, relativeTo: .footnote))
                        .foregroundStyle(palette.inkText(0.55))
                        .frame(minWidth: 30, minHeight: 30)
                        .background(palette.ink(0.07), in: .circle)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bare)
                .contentShape(.circle)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // Everything below the title scrolls, rather than the rows being
            // given whatever height was left after something pinned to the
            // bottom: on a 402x874 phone that was 481pt for 620pt of rows, so
            // the Archive row was clipped and "Manage labels" sat 59pt past
            // the fold with no indicator to say so.
            //
            // **The drawer is a list of places and nothing else.** It carried a
            // "this week, N shipped" card and the accent switcher under the
            // rows; the desk's source list gave both up for the same reason,
            // and the accent is still in Settings, which `settingsRow` opens.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    lists
                    settingsRow
                        .padding(.horizontal, 12)
                        .padding(.top, 14)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.bottom, 12, for: .scrollContent)
        }
        .padding(.top, 20)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(palette.sidebar)
                // The drawer's shadow falls onto the board it is covering, so
                // it goes the way the drawer opened. Mirrored by hand: a
                // shadow offset is a raw coordinate and is the one thing on
                // this panel that `layoutDirection` does not flip, which put
                // the shadow *under* the panel in Arabic — measured at 5 levels
                // of luma against 17 in English.
                .shadow(color: palette.shadow(0.24), radius: 20, x: layoutDirection == .rightToLeft ? -8 : 8)
                .ignoresSafeArea()
        }
    }

    private var lists: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Above the boards rather than inside one of them: the Inbox is
            // global, and a card is in it by being on no board at all.
            inboxRow.padding(.horizontal, 12)

            sectionHeader("Boards", topPadding: 22)
            VStack(spacing: 2) {
                ForEach(store.boards) { boardRow($0) }
                newBoardRow
            }
            .padding(.horizontal, 12)

            sectionHeader("Views", topPadding: 24)
            VStack(spacing: 2) {
                // Not `filters`: the Inbox is the row above the boards on
                // this surface, and listing it again here would be two ways to
                // the same place a thumb's width apart.
                ForEach(SavedView.phoneFilters) { viewRow($0) }
                // The Archive is where things go rather than a filter over the
                // board, so it sits under the filters with a gap instead of in
                // amongst them.
                viewRow(.archive).padding(.top, 6)
            }
            .padding(.horizontal, 12)

            sectionHeader("Labels", topPadding: 24)
            manageLabelsRow
                .padding(.horizontal, 12)

            sectionHeader("Reminders", topPadding: 24)
            remindersRow
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Renaming, recolouring and deleting a label are board-wide edits, so they
    /// hang off the board's own list rather than off any one task's chips —
    /// the same reasoning, and the same view, as the macOS sidebar's row.
    private var manageLabelsRow: some View {
        Button { isManagingLabels = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "tag")
                    .imageScale(.medium)
                    .foregroundStyle(palette.inkText(0.5))
                Text("Manage labels")
                    .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                    .foregroundStyle(palette.ink(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
                CountPill(count: store.labels.count, font: 12.5, horizontalPadding: 8)
            }
            .padding(12)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .accessibilityRepresentation {
            Button(String(localized: "Manage labels",
                          comment: "Accessibility name of the drawer row that opens the label manager")) {
                isManagingLabels = true
            }
                .accessibilityValue(Text(verbatim: "\(store.labels.count)"))
        }
    }

    /// The only way into Settings on this platform — macOS gets ⌘, and the
    /// `Settings` scene for free, and everything behind this row (export,
    /// import, the backups, the reset) would otherwise be unreachable here.
    ///
    /// The drawer closes *before* the flag is set: the sheet is presented from
    /// the root, and one raised under an open overlay is a sheet nobody can
    /// touch.
    private var settingsRow: some View {
        Button {
            store.isNavDrawerOpen = false
            store.isShowingSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
                    .foregroundStyle(palette.inkText(0.5))
                Text("Settings")
                    .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                    .foregroundStyle(palette.ink(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.bare)
    }

    /// The phone's way to the notification settings item 6.5 needs somewhere to
    /// put: the time of day reminders arrive, and — the part that matters — what
    /// is happening when they do not arrive at all. A refused permission is a
    /// standing condition rather than an error to report once, so it is stated
    /// beside the switch it has silenced.
    private var remindersRow: some View {
        Button { isEditingReminders = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "bell")
                    .imageScale(.medium)
                    .foregroundStyle(palette.inkText(0.5))
                Text("Due date reminders")
                    .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                    .foregroundStyle(palette.ink(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(reminderSummary)
                    .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.45))
            }
            .padding(12)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .accessibilityRepresentation {
            Button(String(localized: "Due date reminders",
                          comment: "Accessibility name of the drawer row that opens reminder settings")) {
                isEditingReminders = true
            }
                .accessibilityValue(Text(reminderSummary))
        }
    }

    private var reminderSummary: String {
        let scheduler = NotificationScheduler.shared
        if scheduler.needsSystemSettings {
            return String(localized: "Not allowed", comment: "Drawer row value when notification permission was refused")
        }
        guard scheduler.isEnabled else {
            return String(localized: "Off", comment: "Drawer row value when due date reminders are switched off")
        }
        return scheduler.reminderTime.formatted(date: .omitted, time: .shortened)
    }

    private static let wordmark = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? "Simple Kanban"

    private func sectionHeader(_ title: LocalizedStringKey, topPadding: CGFloat) -> some View {
        Text(title)
            .sectionLabelStyle(opacity: Palette.readableInk)
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .padding(.bottom, 8)
    }

    /// The global Inbox. A destination of its own rather than the first column
    /// of whichever board happens to be open, which is what it was through v4.
    private var inboxRow: some View {
        destinationRow(
            name: Board.inboxName, dot: Board.inboxDot,
            count: store.inboxCount, isActive: isShowingInbox,
            action: showInbox
        )
    }

    /// A real board, with its own count and its own context menu. These were
    /// three literals with the counts 9 and 4 painted on (4.2).
    private func boardRow(_ board: Board) -> some View {
        destinationRow(
            name: board.name, dot: board.dot,
            count: store.taskCount(for: board.id), isActive: isActive(board),
            action: { show(board) }
        )
        // A long press rather than a swipe: these rows are a `VStack` inside the
        // drawer's own scroller, not a `List`, and the menu is also the only one
        // of the two VoiceOver and Switch Control can reach.
        .contextMenu {
            Button { editingBoard = board } label: {
                Label("Edit Board…", systemImage: "pencil")
            }
            reorderButtons(for: board)
            Button(role: .destructive) { store.trashBoard(board.id) } label: {
                Label("Trash Board", systemImage: "trash")
            }
        }
    }

    /// Reordering, for a list that cannot be dragged: the drawer's rows are laid
    /// out by hand, and `onMove` belongs to `List`.
    @ViewBuilder private func reorderButtons(for board: Board) -> some View {
        if let index = store.boards.firstIndex(where: { $0.id == board.id }) {
            if index > 0 {
                Button { store.moveBoard(fromOffsets: [index], toOffset: index - 1) } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
            }
            if index < store.boards.count - 1 {
                Button { store.moveBoard(fromOffsets: [index], toOffset: index + 2) } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
            }
        }
    }

    /// Text rather than a symbol and a word, for the reason `viewRow` states at
    /// length: an `Image` inside a button's label is published to VoiceOver as a
    /// hittable element of its own, named from Apple's catalogue.
    private var newBoardRow: some View {
        Button { isCreatingBoard = true } label: {
            Text("+ New board")
                .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                .foregroundStyle(palette.inkText(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.bare)
    }

    /// The Inbox row and every board row, which differ only in what they count.
    ///
    /// The representation is `viewRow`'s, for `viewRow`'s reason and one more of
    /// its own: gathered, the count is read as part of the destination's *name*
    /// — "Inbox, 3" against the views' "Today" value "1", in the same list — and
    /// the name of a place then changes every time a card is added to it.
    private func destinationRow(
        name: String, dot: SwatchColor, count: Int, isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Circle()
                    .fill(palette.resolve(dot))
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(SimpleKanbanFont.ui(15, isActive ? .bold : .semibold, relativeTo: .body))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)")
                    .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .caption))
                    .opacity(isActive ? 0.7 : 0.5)
            }
            .foregroundStyle(isActive ? palette.accent : palette.ink(0.66))
            .padding(12)
            .frame(minHeight: 44)
            .background(isActive ? palette.accentSoft : .clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .accessibilityRepresentation {
            Button(name, action: action)
                .accessibilityValue(Text(verbatim: "\(count)"))
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
        }
    }

    /// A real control with a live count, which is the whole of 4.1 on this
    /// surface: these rows were layout with a handler-less count on "Today",
    /// which is worse than showing nothing. Selecting the open view again is a
    /// second way back to the board, next to the board row's own.
    private func viewRow(_ view: SavedView) -> some View {
        let isActive = store.activeView == view
        return Button { open(view) } label: {
            HStack(spacing: 10) {
                Image(systemName: view.symbol)
                    .imageScale(.small)
                    .frame(width: 17)
                Text(view.label)
                    .font(SimpleKanbanFont.ui(15, isActive ? .bold : .semibold, relativeTo: .body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                CountPill(count: store.count(of: view, today: dayClock.today), font: 12.5, horizontalPadding: 8)
            }
            .foregroundStyle(isActive ? palette.accent : palette.ink(0.66))
            .padding(12)
            .frame(minHeight: 44)
            .background(isActive ? palette.accentSoft : .clear, in: .rect(cornerRadius: 12))
            .contentShape(.rect)
        }
        .buttonStyle(.bare)
        // The row is one thing to a reader — its name, its count as the value.
        // Stated rather than gathered, because an `Image` among siblings inside
        // a button's label is published whatever else is asked of it: neither
        // `accessibilityHidden` on the symbol nor `children: .ignore` on the row
        // took these out of the tree, and they arrive named from Apple's
        // catalogue — hittable elements called "Warning" and "Brightness
        // Higher" between the rows. Substituting the subtree is what removes them.
        .accessibilityRepresentation {
            Button(view.label) { open(view) }
                .accessibilityValue(
                    Text(verbatim: "\(store.count(of: view, today: dayClock.today))")
                )
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
        }
    }

    /// The drawer covers the list it is changing, so a pick has to close it —
    /// otherwise the only feedback is a row highlight behind a scrim.
    ///
    /// Selecting the open view again puts the tab bar's own place back, rather
    /// than assuming that place was the board: the Inbox is a destination now,
    /// and returning from Today to a board the user was not on would be the
    /// drawer answering a question nobody asked.
    private func open(_ view: SavedView) {
        if store.activeView == view {
            store.selectTab(store.tab)
        } else {
            store.activeView = view
        }
        store.isNavDrawerOpen = false
    }

    /// The drawer's Inbox row raises the slide-over and closes the drawer on
    /// its way out. Both at once is a board list half-covered by the Inbox,
    /// which is the wrong way round: the drawer is the way to a *board*.
    private func showInbox() {
        store.isInboxOpen = true
        store.isNavDrawerOpen = false
    }

    /// Both calls, in this order: `selectBoard` says which board and clears any
    /// saved view standing in for it, `selectTab` says the phone's list is the
    /// board's rather than the search results it may have been showing.
    private func show(_ board: Board) {
        store.selectBoard(board.id)
        store.selectTab(.board)
        store.isNavDrawerOpen = false
    }

    /// Which row is highlighted. The Inbox is a panel over the board now rather
    /// than a place instead of it, so this row marks itself while the panel is
    /// up and the board row underneath goes on marking the board that is still
    /// there behind it — which is the truth about both.
    private var isShowingInbox: Bool { store.isInboxOpen }

    private func isActive(_ board: Board) -> Bool {
        store.activeView == nil && board.id == store.activeBoardID
    }
}

// MARK: - Reminders

/// The whole of the notification preference on this platform: whether reminders
/// happen, when they arrive, and what to do when the system has refused them.
///
/// Bound to ``NotificationScheduler/shared`` rather than to `@AppStorage`. The
/// scheduler is what has to act on a change — moving the time of day moves every
/// pending request — so it owns the values and writes them to `UserDefaults`
/// itself; a second copy in a view would set the preference without rescheduling
/// anything.
struct PhoneRemindersSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var scheduler = NotificationScheduler.shared

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Reminders")
                    .font(SimpleKanbanFont.ui(17, .bold, relativeTo: .headline))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Text("Done")
                        .font(SimpleKanbanFont.ui(15, .bold, relativeTo: .body))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bare)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .hairline(.bottom, color: palette.ink(0.08))

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $scheduler.isEnabled) {
                    Text("Remind me on the due date")
                        .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                }
                .frame(minHeight: 44)

                DatePicker(selection: $scheduler.reminderTime, displayedComponents: .hourAndMinute) {
                    Text("At")
                        .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                }
                .frame(minHeight: 44)
                .disabled(!scheduler.isEnabled)
                .opacity(scheduler.isEnabled ? 1 : 0.4)

                if let explanation = scheduler.explanation {
                    Text(explanation)
                        .font(SimpleKanbanFont.ui(13, .medium, relativeTo: .footnote))
                        .foregroundStyle(palette.inkText(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if scheduler.needsSystemSettings {
                    Button { scheduler.openSystemSettings() } label: {
                        Text("Open Settings")
                            .font(SimpleKanbanFont.ui(14, .bold, relativeTo: .callout))
                            .foregroundStyle(palette.accent)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.bare)
                } else if scheduler.authorization == .notDetermined {
                    Button { Task { await scheduler.requestAuthorization() } } label: {
                        Text("Allow Notifications")
                            .font(SimpleKanbanFont.ui(14, .bold, relativeTo: .callout))
                            .foregroundStyle(palette.accent)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.bare)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.sheet)
        .presentationBackground(palette.sheet)
        .presentationDetents([.medium])
        // The board never asks at launch, so the answer can have changed in
        // System Settings since the app started.
        .task { await scheduler.refreshAuthorization() }
    }
}

// MARK: - Board management

/// One board's name, colour and existence. The phone's answer to the macOS
/// sidebar's context menu, and the sheet both the drawer's long press and the
/// header's "…" menu raise.
///
/// It holds the board's **id** rather than the board: a rename lands in the
/// store, and a snapshot taken when the sheet opened would go on showing the old
/// name underneath the field that had just changed it.
struct PhoneBoardEditor: View {
    /// Which of the column editor's fields has the caret. The pair is the same
    /// on every row, so one enum covers whichever row is open, plus the
    /// composer's own field at the bottom of the list.
    private enum ColumnField: Hashable { case name, short, new }


    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let boardID: Board.ID
    /// Set by the header's "Rename Board…", which names the one field it means
    /// and so should land the caret in it.
    var focusesName: Bool = false

    /// The store refuses an empty name, so the field cannot bind straight
    /// through it — backspacing to nothing would snap the old name back under
    /// the cursor. Committed when the field gives up focus, as
    /// `LabelManagerView` does with the same bargain.
    @State private var draft: String = ""
    @FocusState private var isNameFocused: Bool

    /// The column whose editor is open, if any. One at a time: the rows are
    /// 44pt apart in a sheet, and two open editors put the second one off the
    /// bottom of the screen.
    @State private var expandedColumnID: BoardColumn.ID?
    @State private var isAddingColumn = false
    @State private var columnNameDraft = ""
    @State private var columnShortDraft = ""
    @State private var newColumnName = ""
    @State private var newColumnRole: ColumnRole = .backlog
    @FocusState private var columnFocus: ColumnField?
    /// Why the last delete did not happen. `BoardColumnView` keeps the same
    /// state for the same reason: a menu item that silently does nothing is
    /// indistinguishable from a bug.
    @State private var refusal: ColumnRefusal?

    private var board: Board? { store.board(id: boardID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.hairline(.bottom, color: palette.ink(0.08))
            if let board {
                content(board)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.sheet)
        // `.large` for `PhoneDetailSheet`'s reason: a sheet held at a smaller
        // detent is scaled to fit its inset, and every 44pt control in here
        // would render under the touch minimum.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(palette.sheet)
        .focusWhenReady($isNameFocused, when: focusesName)
        .onAppear {
            draft = board?.name ?? ""
            // `addColumn` and `moveColumn` are defined over the *active* board —
            // a column has no board of its own to name, only the board that
            // holds it. Editing a board the phone is not on would otherwise add
            // the column to whichever board was, under a list of the columns of
            // the one on screen. Showing the board is the cheaper half of that
            // bargain: the drawer's long press is a way in to a board, and the
            // user ends up on the board they were just editing.
            if store.activeBoardID != boardID { store.selectBoard(boardID) }
        }
        .onDisappear {
            commitRename()
            commitColumnRename()
        }
        .alert(
            refusal?.errorDescription ?? "",
            isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } }),
            presenting: refusal
        ) { _ in
            Button("OK", role: .cancel) { refusal = nil }
        } message: { refusal in
            if let suggestion = refusal.recoverySuggestion { Text(suggestion) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Board")
                .font(SimpleKanbanFont.ui(15, .bold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Done")
                    .font(SimpleKanbanFont.ui(15, .bold, relativeTo: .body))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bare)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func content(_ board: Board) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    nameField
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Colour").sectionLabelStyle(opacity: Palette.readableInk)
                        DotPicker(current: board.dot, metrics: .sheet) {
                            store.recolorBoard(boardID, to: $0)
                        }
                        // The row of squares tiles edge to edge, so the first dot
                        // sits inset from the margin the fields keep.
                        .padding(.leading, -(DotPicker.Metrics.sheet.hitSize - DotPicker.Metrics.sheet.dot) / 2)
                    }
                    columns(board)
                    deleteRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The other half of `reveal`: a keyboard already up can be pushed
            // back down by dragging the sheet's content, which is the way to
            // the composer's buttons without committing anything.
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: isAddingColumn) { _, isOpen in
                if isOpen { reveal(in: proxy) }
            }
            .onChange(of: columnFocus) { _, focus in
                if focus == .new { reveal(in: proxy) }
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Name").sectionLabelStyle(opacity: Palette.readableInk)
            TextField("Board name", text: $draft)
                .textFieldStyle(.plain)
                .font(SimpleKanbanFont.serif(26))
                .foregroundStyle(palette.ink)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit {
                    commitRename()
                    isNameFocused = false
                }
                // The field's own hit area is the height of its text; the rest
                // of the 44pt row hands focus over, as the detail sheet's do.
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { isNameFocused = true }
                }
                .accessibilityLabel("Board name")
        }
    }

    // MARK: Columns

    /// The board's columns, which the phone could not touch at all: columns
    /// became board data in D1, but every call site for the store's column
    /// mutations was in `Sources/Mac/`, so a board created here was stuck with
    /// the four it was seeded with for good.
    private func columns(_ board: Board) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Columns").sectionLabelStyle(opacity: Palette.readableInk)
            VStack(spacing: 2) {
                ForEach(Array(board.columns.enumerated()), id: \.element.id) { index, column in
                    columnRow(column, index: index, count: board.columns.count)
                }
            }
            addColumnRow
        }
    }

    /// One column, closed to its name and open to everything about it.
    ///
    /// A tap opens it rather than a long press: the drawer's board rows can
    /// afford a context menu because they are a list of destinations with a
    /// primary action of their own, and this row has none — hiding the only
    /// thing it does behind a gesture nothing on screen names would leave the
    /// section looking as inert as the counts this phase came to remove.
    @ViewBuilder private func columnRow(_ column: BoardColumn, index: Int, count: Int) -> some View {
        let isOpen = expandedColumnID == column.id

        VStack(alignment: .leading, spacing: 0) {
            Button { toggle(column) } label: {
                HStack(spacing: 11) {
                    Circle()
                        .fill(palette.resolve(column.dot))
                        .frame(width: 8, height: 8)
                    Text(column.name)
                        .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                        .foregroundStyle(palette.ink(0.8))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Self.roleName(column.role))
                        .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .caption2))
                        .foregroundStyle(palette.inkText(0.4))
                    Text(verbatim: isOpen ? "\u{2303}" : "\u{2304}")
                        .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .caption2))
                        .foregroundStyle(palette.inkText(0.35))
                }
                .padding(12)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.bare)
            // `viewRow`'s treatment, for `viewRow`'s reason: the row is one
            // thing to a reader — the column's name, its role as the value.
            .accessibilityRepresentation {
                Button(column.name) { toggle(column) }
                    .accessibilityValue(Self.roleName(column.role))
                    .accessibilityAddTraits(isOpen ? [.isSelected] : [])
            }

            if isOpen {
                columnEditor(column, index: index, count: count)
            }
        }
        .background(isOpen ? palette.ink(0.045) : .clear, in: .rect(cornerRadius: 12))
    }

    /// Everything about a column except its role, which nothing can change once
    /// the column exists — `BoardStore` has no `setColumnRole`, and the macOS
    /// editor leaves it out for the same reason.
    private func columnEditor(_ column: BoardColumn, index: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            columnField("Name", text: $columnNameDraft, focus: .name)
            // Nothing else edits the abbreviation, and `MoveToPicker` is what
            // draws it: without this a column renamed on the phone went on
            // calling itself by the old name in the only control the phone has
            // for moving a card.
            columnField("Short", text: $columnShortDraft, focus: .short)

            VStack(alignment: .leading, spacing: 6) {
                Text("Colour").sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
                DotPicker(current: column.dot, metrics: .sheet) {
                    store.recolorColumn(column.id, to: $0)
                }
                .padding(.leading, -(DotPicker.Metrics.sheet.hitSize - DotPicker.Metrics.sheet.dot) / 2)
            }

            HStack(spacing: 8) {
                // Reordering, for a list that cannot be dragged: these rows are
                // a `VStack` in a sheet's scroller, and `onMove` belongs to
                // `List`. The drawer's board rows make the same trade.
                stepButton("Move Up", glyph: "\u{2191}", isEnabled: index > 0) {
                    store.moveColumn(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                }
                stepButton("Move Down", glyph: "\u{2193}", isEnabled: index < count - 1) {
                    store.moveColumn(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                }
                Spacer(minLength: 0)
                deleteColumnButton(column)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private func columnField(_ title: LocalizedStringKey, text: Binding<String>, focus target: ColumnField) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                .foregroundStyle(palette.ink)
                .focused($columnFocus, equals: target)
                .submitLabel(.done)
                .onSubmit {
                    if target == .new {
                        addColumn()
                    } else {
                        commitColumnRename()
                        columnFocus = nil
                    }
                }
                .padding(.horizontal, 12)
                // The field's own hit area is the height of its text; the pill
                // around it hands focus over, as the name field above does. The
                // shape is named for the same reason `ChecklistView`'s is: the
                // frame alone left the published element a rounding short of
                // the 44 it was asked for.
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.accessibility, Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(palette.ink(0.06))
                        .contentShape(.rect)
                        .onTapGesture { columnFocus = target }
                }
                .accessibilityLabel(
                    target == .short
                        ? String(localized: "Short name",
                                 comment: "Accessibility name for the field holding a column's abbreviation")
                        : String(localized: "Column name",
                                 comment: "Accessibility name for the field holding a column's name")
                )
        }
    }

    /// Text rather than a symbol, for `newBoardRow`'s reason: an `Image` inside
    /// a button's label arrives as a hittable element of its own, named from
    /// Apple's catalogue.
    private func stepButton(
        _ name: LocalizedStringKey, glyph: String, isEnabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(verbatim: glyph)
                .font(SimpleKanbanFont.ui(15, .bold, relativeTo: .body))
                .foregroundStyle(palette.ink(isEnabled ? 0.6 : 0.22))
                .frame(minWidth: 44, minHeight: 44)
                .background(palette.ink(0.06), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.bare)
        .disabled(!isEnabled)
        .accessibilityLabel(name)
    }

    /// The cards go to the first column left rather than anywhere final, so this
    /// asks for no confirmation either — but it can be refused, and a refusal
    /// has to say why.
    private func deleteColumnButton(_ column: BoardColumn) -> some View {
        Button(role: .destructive) {
            refusal = store.trashColumn(column.id)
            if refusal == nil { expandedColumnID = nil }
        } label: {
            Text("Trash Column")
                .font(SimpleKanbanFont.ui(13.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(destructiveTone.foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(destructiveTone.background, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.bare)
    }

    @ViewBuilder private var addColumnRow: some View {
        if isAddingColumn {
            addColumnComposer
        } else {
            Button {
                commitColumnRename()
                expandedColumnID = nil
                isAddingColumn = true
            } label: {
                Text("+ Add column")
                    .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                    .foregroundStyle(palette.inkText(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)
        }
    }

    private var addColumnComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                // The role is chosen here and nowhere else — a column's role
                // cannot be changed later — which is also how a board is given
                // the second Done column the refusal above asks for.
                Text("Role").sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
                rolePicker
            }
            // Above the name field, not below it. The segments used to sit in
            // the band the software keyboard lands in, so once the field had
            // focus a tap aimed at Doing or Done reached the keyboard instead
            // and the column was created as a Backlog without a word said.
            // Ahead of the field they are on the far side of the caret from the
            // keyboard, and `reveal` keeps them there.
            columnField("Name", text: $newColumnName, focus: .new)
            HStack(spacing: 8) {
                // The height belongs inside the label. Hung on the `Button`
                // instead it framed the control and not its shape, and
                // `.buttonStyle(.bare)` hands the shape straight to the label —
                // so the target published was the 47.3×19.3 of the word, in a
                // sheet where every other control clears 44.
                Button { cancelAddColumn() } label: {
                    Text("Cancel")
                        .font(SimpleKanbanFont.ui(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.inkText(0.55))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.bare)
                Spacer(minLength: 0)
                Button { addColumn() } label: {
                    Text("Add Column")
                        .font(SimpleKanbanFont.ui(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(palette.accent, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.bare)
            }
        }
        .padding(12)
        .background(palette.ink(0.045), in: .rect(cornerRadius: 12))
        .id(Self.composerAnchor)
    }

    /// What `reveal` scrolls to. The composer is the last thing in the sheet, so
    /// nothing else can be pulled above the keyboard on its behalf.
    private static let composerAnchor = "add-column-composer"

    /// Scrolls the composer clear of the software keyboard.
    ///
    /// The keyboard's safe-area inset arrives a beat *after* the field takes
    /// focus, so a scroll issued in the same turn aims at a viewport that is
    /// about to lose a third of its height — which is how a control above the
    /// caret ended up underneath the keyboard. Waiting for the inset and then
    /// pinning the composer's bottom edge to the bottom of what is left puts
    /// the whole of it, role segments included, in reach.
    private func reveal(in proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
                proxy.scrollTo(Self.composerAnchor, anchor: .bottom)
            }
        }
    }

    private var rolePicker: some View {
        HStack(spacing: 4) {
            ForEach(ColumnRole.allCases, id: \.self) { option in
                let isCurrent = option == newColumnRole
                Button { newColumnRole = option } label: {
                    Text(Self.roleName(option))
                        .font(SimpleKanbanFont.ui(13, .bold, relativeTo: .footnote))
                        .foregroundStyle(isCurrent ? palette.ink : palette.inkText(0.5))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 38)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isCurrent ? palette.card : .clear)
                                .shadow(color: isCurrent ? palette.shadow(0.16) : .clear, radius: 1.5, y: 1)
                        }
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bare)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 3)
        .background(palette.ink(0.06), in: .rect(cornerRadius: 10))
    }

    /// A name with nothing in it is refused by the store, and the composer stays
    /// open rather than closing on a column that was never made.
    private func addColumn() {
        guard store.addColumn(named: newColumnName, role: newColumnRole) != nil else { return }
        cancelAddColumn()
    }

    private func cancelAddColumn() {
        newColumnName = ""
        newColumnRole = .backlog
        columnFocus = nil
        isAddingColumn = false
    }

    /// Opening one column closes whichever was open, committing its fields on
    /// the way — the same bargain the board's own name field makes.
    private func toggle(_ column: BoardColumn) {
        commitColumnRename()
        columnFocus = nil
        if expandedColumnID == column.id {
            expandedColumnID = nil
        } else {
            expandedColumnID = column.id
            columnNameDraft = column.name
            columnShortDraft = column.short
        }
    }

    private func commitColumnRename() {
        guard let id = expandedColumnID else { return }
        store.renameColumn(id, to: columnNameDraft, short: columnShortDraft)
        if let column = store.column(id: id) {
            columnNameDraft = column.name
            columnShortDraft = column.short
        }
    }

    private static func roleName(_ role: ColumnRole) -> String {
        switch role {
        case .backlog:
            String(localized: "Backlog", comment: "Column role: work that has not started")
        case .active:
            String(localized: "Doing", comment: "Column role: work in flight")
        case .done:
            String(localized: "Done", comment: "Column role: work that is complete")
        }
    }

    /// No confirmation, matching the task row's Trash: the act is undoable, and
    /// the line under the button says the one thing a person would want a
    /// confirmation for — that the cards on it are not going with it.
    private var deleteRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(role: .destructive) {
                store.trashBoard(boardID)
                dismiss()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "trash")
                    Text("Trash Board")
                }
                .font(SimpleKanbanFont.ui(14.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(destructiveTone.foreground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(destructiveTone.background, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.bare)

            Text("Its cards move to the Inbox rather than being deleted.")
                .font(SimpleKanbanFont.ui(12.5, .medium, relativeTo: .footnote))
                .foregroundStyle(palette.inkText(0.45))
        }
        .padding(.top, 6)
    }

    /// `Palette` has no danger semantic of its own, so this borrows the overdue
    /// tone rather than naming a colour (C2) — `PhoneDetailSheet` does the same.
    private var destructiveTone: (background: Color, foreground: Color) {
        palette.dueTone(urgency: .overdue, role: .backlog)
    }

    private func commitRename() {
        store.renameBoard(boardID, to: draft)
        draft = store.board(id: boardID)?.name ?? draft
    }
}

extension View {
    /// Presents the "name it" prompt a new board needs. An alert rather than a
    /// sheet: a board is a name, and the name is the whole of what is being
    /// asked for.
    ///
    /// Shared by the drawer's "+ New board" row and by the empty state the Board
    /// tab shows once the last board has been deleted, which is a state the user
    /// has to be able to leave.
    func newBoardAlert(
        isPresented: Binding<Bool>, onCreate: @escaping (Board.ID) -> Void = { _ in }
    ) -> some View {
        modifier(NewBoardAlert(isPresented: isPresented, onCreate: onCreate))
    }
}

private struct NewBoardAlert: ViewModifier {
    @Environment(BoardStore.self) private var store

    @Binding var isPresented: Bool
    let onCreate: (Board.ID) -> Void

    @State private var name = ""

    func body(content: Content) -> some View {
        content.alert("New Board", isPresented: $isPresented) {
            TextField("Board name", text: $name)
            Button("Cancel", role: .cancel) { name = "" }
            Button("Create") {
                // `createBoard` refuses a blank name and moves to the board it
                // made, so the caller only has to say where to look afterwards.
                if let id = store.createBoard(named: name) {
                    store.selectTab(.board)
                    onCreate(id)
                }
                name = ""
            }
        } message: {
            Text("A board has columns of its own. Anything you have not filed stays in the Inbox.")
        }
    }
}

#endif
