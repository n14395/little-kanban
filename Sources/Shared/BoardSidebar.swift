import SwiftUI

/// The source list: the Inbox, the boards, saved views, and the weekly ship
/// count.
///
/// Every row is a real destination. The Inbox leads them, above the boards
/// rather than inside them, because it is global — a card is in it by being on
/// no board at all — and the rows under "Boards" are `store.boards`, each with
/// its own count, renamed, recoloured, reordered and deleted from its context
/// menu. A card can be dragged onto any of them.
struct BoardSidebar: View {
    /// The list at a pointer and the list under a finger. The design's 232pt
    /// column and its 34pt rows are pointer sizes; the split view sizes its own
    /// column, and touch needs 44 on every row — see **Touch targets**.
    struct Metrics {
        /// `nil` where the container decides, which is what a
        /// `NavigationSplitView` does.
        var width: CGFloat?
        /// The band the window's own traffic lights sit in. Nothing on iPad.
        var trafficLightInset: CGFloat
        var rowFont: CGFloat
        var rowVerticalPadding: CGFloat
        var rowRadius: CGFloat
        /// The floor under a row, which the pointer never needed.
        var rowHit: CGFloat
        /// What a row that has become a text field claims — see ``FieldHitArea``.
        var fieldHit: CGFloat
        var sectionSpacing: CGFloat
        var accent: AccentPicker.Metrics
        var dots: DotPicker.Metrics
        var labelManager: LabelManagerView.Metrics

        static let desk = Metrics(
            width: 232, trafficLightInset: 16, rowFont: 13, rowVerticalPadding: 7,
            rowRadius: 9, rowHit: 0, fieldHit: 0, sectionSpacing: 22,
            accent: .desk, dots: .desk, labelManager: .desk
        )
        static let pad = Metrics(
            width: nil, trafficLightInset: 0, rowFont: 15, rowVerticalPadding: 10,
            rowRadius: 11, rowHit: 44, fieldHit: 44, sectionSpacing: 24,
            accent: .drawer, dots: .sheet, labelManager: .sheet
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store

    var metrics: Metrics = .desk
    /// Set by File ▸ New Board and cleared here when the field opens. A menu
    /// bar is the only thing that ever asks, so this is `nil` everywhere else.
    var isNamingNewBoard: Binding<Bool>?
    /// Whether the label manager is up, where something above the list needs to
    /// know. The window does: a sheet leaves the surface behind it reachable to
    /// a reader — measured, `New task` reported `hittable=true` with the sheet
    /// open — and only a view that contains the whole surface can take it out
    /// of the tree. `nil` on the surfaces that have no such view, where the row
    /// keeps the flag itself and nothing changes.
    var isManagingLabels: Binding<Bool>?

    @State private var ownManagingLabels = false
    /// Which board's swatches are open. One at a time, so this is which board
    /// rather than a flag per row.
    @State private var recoloringBoardID: Board.ID?
    /// Which row has become a text field, and what it says so far. The store
    /// refuses an empty name, so a field bound straight through it would snap
    /// the old name back under the cursor on the last backspace.
    @State private var editing: BoardField?
    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool
    /// The row a card is being dragged over. Local rather than the store's
    /// `dropTargetColumnID`: neither of these is a column.
    @State private var dropTarget: DropTarget?

    private var managingLabels: Binding<Bool> { isManagingLabels ?? $ownManagingLabels }

    /// A 232pt column of rows whose type grows — see ``ChromeScale``. Capped
    /// lower than the board's columns: the source list takes its width off the
    /// board rather than off a scroller.
    private var chrome = ChromeScale()

    private enum BoardField: Hashable {
        case rename(Board.ID)
        case newBoard
    }

    private enum DropTarget: Hashable {
        case inbox
        case board(Board.ID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            trafficLightInset

            inboxRow
                .padding(.horizontal, 8)

            sectionHeader("Boards", topPadding: metrics.sectionSpacing)
            VStack(spacing: 2) {
                ForEach(Array(store.boards.enumerated()), id: \.element.id) { index, board in
                    boardRow(board, index: index)
                }
                newBoardRow
            }
            .padding(.horizontal, 8)

            sectionHeader("Views", topPadding: metrics.sectionSpacing)
            VStack(spacing: 2) {
                ForEach(SavedView.filters) { viewRow($0) }
                // The Archive is reached from the same list but is a place
                // things go rather than a filter over the board, so it sits a
                // little apart from the five that are.
                viewRow(.archive)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 8)

            sectionHeader("Labels", topPadding: metrics.sectionSpacing)
            manageLabelsRow
                .padding(.horizontal, 8)
            settingsRow
                .padding(.horizontal, 8)

            Spacer(minLength: 0)
            weeklySummary
            AccentPicker(metrics: metrics.accent)
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: chrome.scaling(metrics.width, cap: 1.4))
        .background(palette.sidebar)
        .hairline(.trailing, color: palette.ink(0.07))
        .labelManagerSheet(isPresented: managingLabels, metrics: metrics.labelManager)
        // File ▸ New Board. A board is named as it is made, and the field that
        // names it is this list's own row — so the menu asks for the row rather
        // than making a board called something the user did not choose.
        //
        // `task(id:)` rather than `onChange` because the menu can ask while the
        // sidebar is hidden: showing it again runs this on the way in.
        .task(id: isNamingNewBoard?.wrappedValue ?? false) {
            guard isNamingNewBoard?.wrappedValue == true else { return }
            isNamingNewBoard?.wrappedValue = false
            beginEditing(.newBoard, text: "")
        }
    }

    // MARK: Destinations

    private var inboxRow: some View {
        let isActive = store.surface == .inbox

        return Button { store.selectSurface(.inbox) } label: {
            destinationRow(
                dot: Board.inboxDot, count: store.inboxCount,
                isActive: isActive, isDropTarget: isDropTarget(.inbox)
            ) {
                rowName(Board.inboxName, isActive: isActive)
            }
        }
        .buttonStyle(.bare)
        // The count is what the row is worth, not part of what it is called:
        // gathered into the name it came out as "Inbox 4", which is a row whose
        // name changes every time a card is filed.
        .accessibilityLabel(Board.inboxName)
        .accessibilityValue(Text(verbatim: "\(store.inboxCount)"))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        // The way back for a card that was filed by mistake. On the board it is
        // the only way back by pointer: the Inbox is no longer a column, so
        // there is no column to drop it on.
        .dropDestination(for: TaskTransfer.self) { items, _ in
            guard store.allowsCardDrag, let dropped = items.first, store[dropped.id] != nil
            else { return false }
            store.unfile(dropped.id)
            return true
        } isTargeted: { targeted in
            setDropTarget(.inbox, targeted: targeted)
        }
    }

    private func boardRow(_ board: Board, index: Int) -> some View {
        let isActive = store.surface == .board && store.activeBoardID == board.id
        let isRenaming = editing == .rename(board.id)

        return Group {
            if isRenaming {
                destinationRow(
                    dot: board.dot, count: store.taskCount(for: board.id), isActive: isActive
                ) {
                    rowField(.rename(board.id), placeholder: "Board name")
                }
            } else {
                Button { store.selectBoard(board.id) } label: {
                    destinationRow(
                        dot: board.dot, count: store.taskCount(for: board.id),
                        isActive: isActive, isDropTarget: isDropTarget(.board(board.id))
                    ) {
                        rowName(board.name, isActive: isActive)
                    }
                }
                .buttonStyle(.bare)
                // Name and count stated separately — see `inboxRow`. Stated
                // rather than substituted, because the row's context menu is
                // the only route rename, recolour and delete have to a reader.
                .accessibilityLabel(board.name)
                .accessibilityValue(Text(verbatim: "\(store.taskCount(for: board.id))"))
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
        }
        .contextMenu { boardMenu(board, index: index) }
        .popover(
            isPresented: Binding(
                get: { recoloringBoardID == board.id },
                set: { if !$0 { recoloringBoardID = nil } }
            ),
            arrowEdge: .trailing
        ) {
            DotPicker(current: board.dot, metrics: metrics.dots) { swatch in
                store.recolorBoard(board.id, to: swatch)
                recoloringBoardID = nil
            }
            .padding(10)
            .environment(\.palette, palette)
        }
        .dropDestination(for: TaskTransfer.self) { items, _ in
            guard store.allowsCardDrag, let dropped = items.first, store[dropped.id] != nil
            else { return false }
            store.file(dropped.id, onto: board.id)
            return true
        } isTargeted: { targeted in
            setDropTarget(.board(board.id), targeted: targeted)
        }
    }

    /// Rename, recolour, reorder, delete. Reordering is two menu items rather
    /// than a drag: the list is short, the rows are already carrying a drop
    /// destination for cards, and the two gestures would fight.
    @ViewBuilder
    private func boardMenu(_ board: Board, index: Int) -> some View {
        Button { beginEditing(.rename(board.id), text: board.name) } label: {
            Label("Rename Board", systemImage: "pencil")
        }
        Button { recoloringBoardID = board.id } label: {
            Label("Board Colour…", systemImage: "paintpalette")
        }
        Divider()
        Button {
            store.moveBoard(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        } label: {
            Label("Move Up", systemImage: "arrow.up")
        }
        .disabled(index == 0)
        Button {
            store.moveBoard(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
        } label: {
            Label("Move Down", systemImage: "arrow.down")
        }
        .disabled(index == store.boards.count - 1)
        Divider()
        // No confirmation, the way deleting a task and deleting a label have
        // none: the cards go to the Inbox rather than anywhere final, and ⌘Z is
        // the way back.
        Button(role: .destructive) {
            if editing == .rename(board.id) { cancelField() }
            store.deleteBoard(board.id)
        } label: {
            Label("Delete Board", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var newBoardRow: some View {
        if editing == .newBoard {
            destinationRow(dot: .accent, count: nil, isActive: false) {
                rowField(.newBoard, placeholder: "Board name")
            }
        } else {
            Button { beginEditing(.newBoard, text: "") } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(SimpleKanbanFont.ui(9, .bold, relativeTo: .caption2))
                        .frame(width: 7)
                        .accessibilityHidden(true)
                    Text("New board", comment: "Sidebar row that starts a board")
                        .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(palette.inkText(0.45))
                .padding(.vertical, metrics.rowVerticalPadding)
                .padding(.horizontal, 10)
                .frame(minHeight: metrics.rowHit)
                .hoverBackground(palette.ink(0.05), radius: metrics.rowRadius)
            }
            .buttonStyle(.bare)
            // The plus is a nested element beside the word unless the subtree
            // is substituted — see `viewRow`.
            .accessibilityRepresentation {
                Button(String(localized: "New board",
                              comment: "Accessibility name of the sidebar row that starts a new board")) {
                    beginEditing(.newBoard, text: "")
                }
            }
        }
    }

    /// Every row selects its view, and selecting the active one again comes
    /// back to the board — the same thing the list header's "Board" button
    /// does, so a user who reached a view from here can leave it from here.
    ///
    /// The count is the view's own membership rather than what the list is
    /// currently showing: it is deliberately not narrowed by the search, which
    /// would make the badge report the query instead of the view.
    private func viewRow(_ view: SavedView) -> some View {
        let isActive = store.activeView == view

        return Button {
            store.selectSurface(isActive ? .board : .view(view))
        } label: {
            HStack(spacing: 8) {
                Text(view.label)
                    .font(SimpleKanbanFont.ui(metrics.rowFont, isActive ? .bold : .semibold, relativeTo: .subheadline))
                    .foregroundStyle(isActive ? palette.accent : palette.ink(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
                CountPill(count: store.count(of: view, today: dayClock.today))
            }
            .padding(.vertical, metrics.rowVerticalPadding)
            .padding(.horizontal, 10)
            .frame(minHeight: metrics.rowHit)
            .background(isActive ? palette.accentSoft : .clear, in: .rect(cornerRadius: metrics.rowRadius))
            .hoverBackground(isActive ? .clear : palette.ink(0.05), radius: metrics.rowRadius)
        }
        .buttonStyle(.bare)
        .accessibilityLabel(view.label)
        .accessibilityValue(Text(verbatim: "\(store.count(of: view, today: dayClock.today))"))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// Renaming, recolouring and deleting a label are board-wide edits, so they
    /// hang off the board's own list rather than off any one task's chips.
    /// Settings ▸ Labels opens the same view from its own row.
    private var manageLabelsRow: some View {
        Button { managingLabels.wrappedValue = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .imageScale(.small)
                    .foregroundStyle(palette.inkText(0.5))
                    .accessibilityHidden(true)
                Text("Manage labels")
                    .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
                CountPill(count: store.labels.count)
            }
            .padding(.vertical, metrics.rowVerticalPadding)
            .padding(.horizontal, 10)
            .frame(minHeight: metrics.rowHit)
            .hoverBackground(palette.ink(0.05), radius: metrics.rowRadius)
        }
        .buttonStyle(.bare)
        // Substituted rather than named, because this row has a symbol in it:
        // an `Image` among siblings inside a button's label is published as an
        // element of its own whatever else is asked of it, `accessibilityHidden`
        // included. The count is the row's value either way — see `inboxRow`.
        .accessibilityRepresentation {
            Button(String(localized: "Manage labels",
                          comment: "Accessibility name of the sidebar row that opens the label manager")) {
                managingLabels.wrappedValue = true
            }
                .accessibilityValue(Text(verbatim: "\(store.labels.count)"))
        }
    }

    /// iPad only, and the `#if` is about *reachability* rather than about size:
    /// SwiftUI puts Settings… and ⌘, on the macOS app menu for free, so a second
    /// door there would be a duplicate, while on iPad this sidebar is the whole
    /// of the chrome and without the row export, import, the backups and the
    /// reset have no way in at all.
    @ViewBuilder private var settingsRow: some View {
        #if os(iOS)
        Button { store.isShowingSettings = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .imageScale(.small)
                    .foregroundStyle(palette.inkText(0.5))
                    .accessibilityHidden(true)
                Text("Settings")
                    .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, metrics.rowVerticalPadding)
            .padding(.horizontal, 10)
            .frame(minHeight: metrics.rowHit)
            .hoverBackground(palette.ink(0.05), radius: metrics.rowRadius)
        }
        .buttonStyle(.bare)
        .accessibilityRepresentation {
            Button(String(localized: "Settings",
                          comment: "Accessibility name of the sidebar row that opens Settings")) {
                store.isShowingSettings = true
            }
        }
        #endif
    }

    // MARK: Row furniture

    /// The shape every destination shares: a dot, a name, a count, and the
    /// active row's ground. The name is a view rather than a string so a row
    /// being renamed can put its field exactly where its name was.
    private func destinationRow(
        dot: SwatchColor, count: Int?, isActive: Bool, isDropTarget: Bool = false,
        @ViewBuilder name: () -> some View
    ) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(palette.resolve(dot))
                .frame(width: 7, height: 7)
            name()
                .frame(maxWidth: .infinity, alignment: .leading)
            if let count {
                Text("\(count)")
                    .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .caption2))
                    .opacity(isActive ? 0.7 : 0.5)
            }
        }
        .foregroundStyle(isActive ? palette.accent : palette.ink(0.66))
        .padding(.vertical, metrics.rowVerticalPadding)
        .padding(.horizontal, 10)
        .frame(minHeight: metrics.rowHit)
        .background(isActive ? palette.accentSoft : .clear, in: .rect(cornerRadius: metrics.rowRadius))
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: metrics.rowRadius)
                    .strokeBorder(palette.accent, lineWidth: 2)
            }
        }
        .hoverBackground(isActive ? .clear : palette.ink(0.05), radius: metrics.rowRadius)
    }

    private func rowName(_ text: String, isActive: Bool) -> some View {
        Text(text)
            .font(SimpleKanbanFont.ui(metrics.rowFont, isActive ? .bold : .semibold, relativeTo: .subheadline))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// The name lands when the field gives up focus, so a name typed a letter
    /// at a time is one store mutation and one ⌘Z — the bargain the label
    /// manager and the task fields both make.
    private func rowField(_ field: BoardField, placeholder: String) -> some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
            .foregroundStyle(palette.ink)
            .focused($isFieldFocused)
            .fieldHitArea(minHeight: metrics.fieldHit) { isFieldFocused = true }
            .onSubmit { isFieldFocused = false }
            .onKeyPress(.escape) {
                cancelField()
                return .handled
            }
            .onAppear { isFieldFocused = true }
            // Only while this is still the row being edited. Opening a field on
            // another row files this one first, and this one's parting focus
            // change would otherwise land its draft on the other row's name.
            .onChange(of: isFieldFocused) { _, focused in
                guard !focused, editing == field else { return }
                commitField()
            }
            .accessibilityLabel(placeholder)
    }

    // MARK: Editing

    private func beginEditing(_ field: BoardField, text: String) {
        // A field already open somewhere else files its name first: its own
        // focus change never fires, because the row it lives in is replaced.
        commitField()
        draft = text
        editing = field
    }

    private func commitField() {
        switch editing {
        case .rename(let id):
            store.renameBoard(id, to: draft)
        case .newBoard:
            store.createBoard(named: draft)
        case nil:
            return
        }
        cancelField()
    }

    private func cancelField() {
        editing = nil
        draft = ""
    }

    // MARK: Drops

    private func isDropTarget(_ target: DropTarget) -> Bool {
        dropTarget == target && store.draggingID != nil
    }

    private func setDropTarget(_ target: DropTarget, targeted: Bool) {
        if targeted, store.allowsCardDrag {
            dropTarget = target
        } else if dropTarget == target {
            dropTarget = nil
        }
    }

    // MARK: Furniture

    /// The window's own traffic lights sit here (the title bar is hidden), so
    /// the sidebar reserves the band they are drawn in. A split view's own
    /// column has no such lights and no such band.
    ///
    /// The 14pt above, the band and the 20pt below come to the height of
    /// `BoardToolbar.Metrics.desk.height`, which is deliberate: the lights are
    /// centred on the header's row, so the first row of the list starts level
    /// with the seam under the header beside it.
    @ViewBuilder
    private var trafficLightInset: some View {
        if metrics.trafficLightInset > 0 {
            Color.clear
                .frame(height: metrics.trafficLightInset)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, topPadding: CGFloat) -> some View {
        Text(title)
            .sectionLabelStyle(opacity: Palette.readableInk)
            .padding(.horizontal, 12)
            .padding(.top, topPadding)
            .padding(.bottom, 6)
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This week")
                .sectionLabelStyle(tracking: 0.08, opacity: Palette.readableInk)
                .padding(.bottom, 8)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(store.weeklyShippedCount(today: dayClock.today))")
                    .font(SimpleKanbanFont.serif(30))
                Text("shipped")
                    .font(SimpleKanbanFont.ui(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.5))
            }

            ProgressMeter(fraction: store.weeklyProgressFraction(today: dayClock.today), height: 5)
                .padding(.top, 10)
        }
        .padding(12)
        .background(palette.ink(0.045), in: .rect(cornerRadius: 12))
        .padding(.horizontal, 12)
    }
}
