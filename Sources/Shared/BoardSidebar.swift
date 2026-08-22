import SwiftUI

/// The source list: the Inbox, the boards, saved views and labels.
///
/// Rows and nothing else. The weekly ship count and the accent swatches used to
/// sit under them; the count now lives only in the phone's drawer, and the
/// accent is Settings' — where the rest of what is global to the app already
/// was.
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
        var dots: DotPicker.Metrics
        var labelManager: LabelManagerView.Metrics

        static let desk = Metrics(
            width: 232, trafficLightInset: 16, rowFont: 13, rowVerticalPadding: 7,
            rowRadius: 9, rowHit: 0, fieldHit: 0, sectionSpacing: 22,
            dots: .desk, labelManager: .desk
        )
        static let pad = Metrics(
            width: nil, trafficLightInset: 0, rowFont: 15, rowVerticalPadding: 10,
            rowRadius: 11, rowHit: 44, fieldHit: 44, sectionSpacing: 24,
            dots: .sheet, labelManager: .sheet
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
    /// The card the capture popover is filling in. Local rather than the
    /// store's: it is which popover is open, not anything about the board, and
    /// `BoardStore` already holds one surface's worth of that too many.
    @State private var capture: Capture?

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
        case board(Board.ID)
    }

    /// The card the capture popover is filling in. A one-field box because
    /// `popover(item:)` wants something `Identifiable`, and tracking the card
    /// rather than a flag beside it is what lets the popover close itself when
    /// the card stops existing.
    private struct Capture: Identifiable { let id: TaskItem.ID }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            trafficLightInset

            // The Inbox was the row above this one until it stopped being a
            // destination. It is a toggle for a panel that stands beside the
            // board, so it belongs beside the board's name — see
            // `BoardToolbar.inboxToggle`, which took its drop target with it.
            sectionHeader("Boards", topPadding: 0)
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

            // The rows sit at the top of the column; capture sits at the foot of
            // it, under everything it is not one of.
            Spacer(minLength: 0)
            captureButton
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
                // Name and count stated separately — see `BoardToolbar`. Stated
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
        // included. The count is the row's value either way.
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

    // MARK: Capture

    /// Quick capture, at the foot of the list: one press makes a card in the
    /// Inbox and opens the whole inspector on it in a popover — a title, a
    /// description, a due date, labels, a checklist, and the board menu to file
    /// it with once the user knows where it goes.
    ///
    /// The inspector rather than a one-line composer because the two are for
    /// different moments. A composer belongs at the head of the column it is
    /// adding to, where the destination is already decided and only the title is
    /// missing. This one is the opposite: the thing is worth writing down and
    /// nothing else about it is settled yet, so it opens with everything on
    /// offer and defaults the one decision it has to make — the Inbox, which is
    /// where a card is by being nowhere.
    ///
    /// macOS only. `PadRootView` draws this same list, but a popover that size
    /// wants touch metrics and its own width, and the iPad's toolbar already
    /// carries New task.
    @ViewBuilder private var captureButton: some View {
        #if os(macOS)
        Button { capture = Capture(id: store.captureToInbox()) } label: {
            Image(systemName: "plus")
                .symbolSize(23, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(palette.onAccent)
                // The one control in the list that is a target rather than a
                // row, so it takes a square of its own rather than the row
                // height — and grows with the type inside it like the rest.
                .frame(width: chrome(52), height: chrome(52))
                .background(palette.accent, in: .circle)
                .shadow(color: palette.shadow(0.2), radius: 5, y: 2)
        }
        .buttonStyle(.bare)
        .help("Capture a task in the Inbox")
        .accessibilityLabel("Capture a task")
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Out to the side rather than up: the button is at the bottom-left of
        // the window, so above it is the list it was just put under.
        .popover(item: capturing, arrowEdge: .trailing) { capture in
            if let task = store[capture.id] {
                TaskInspector(task: task, container: .popover(dismiss: endCapture))
                    // A popover sizes itself to its content, and the panel's
                    // content is a `ScrollView` — which will take whatever it is
                    // given. Height is the popover's to decide, so it decides.
                    .frame(height: 540)
            }
        }
        #endif
    }

    /// The popover's presentation, written through a binding so that every way
    /// out of it goes through one place.
    ///
    /// Light dismissal — clicking away, Escape — is the reason it cannot simply
    /// be `$capture`: a capture nobody typed into has to be dropped again, and
    /// SwiftUI reports that dismissal by writing `nil` here and nowhere else.
    private var capturing: Binding<Capture?> {
        Binding(
            // Deleting the card from inside the popover takes the popover with
            // it. There is nothing left to fill in, and an empty box hanging off
            // the button is not an answer.
            get: { capture.flatMap { store[$0.id] == nil ? nil : $0 } },
            set: { next in
                guard next == nil else { capture = next; return }
                endCapture()
            }
        )
    }

    /// Closes the popover, and takes the card with it when the user gave it
    /// nothing — see `BoardStore.discardIfUntouched`. Pressing ✕ and clicking
    /// away are the same act and land here alike.
    private func endCapture() {
        if let capture { store.discardIfUntouched(capture.id) }
        capture = nil
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

}
