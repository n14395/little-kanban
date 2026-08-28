import SwiftUI

/// One board column: header, inline composer, and its cards.
struct BoardColumnView: View {
    /// The column at a pointer and the column under a finger.
    ///
    /// The design's 272pt strip and 22pt header buttons are pointer sizes. Touch
    /// needs 44pt on anything tappable, and a column wide enough that a card
    /// title is not three words a line — see **Touch targets** in the README.
    struct Metrics {
        var width: CGFloat
        var cornerRadius: CGFloat
        var horizontalPadding: CGFloat
        var topPadding: CGFloat
        var bottomPadding: CGFloat
        var titleSize: CGFloat
        /// The square the header's menu and "+" claim.
        var headerButton: CGFloat
        /// The trailing add-column tile, which stands on its side. A whole
        /// column's width for a two-word button is a card's worth of board
        /// spent on nothing, so it claims a strip and turns the words to match.
        /// Touch still needs 44 of it.
        var headerButtonRadius: CGFloat
        /// The "+" glyph inside it.
        var headerGlyph: CGFloat
        /// The floor under a row that is not a button of its own — the role
        /// segments on the add-column tile. Zero at a pointer.
        var rowHit: CGFloat
        var cardSpacing: CGFloat
        /// Whether the foot's add row opens the draft field under itself, or
        /// sends it to the head of the column with everything else.
        ///
        /// **The desk's does; the iPad's does not, and the difference is the
        /// software keyboard.** A field at the foot of a column is a field at
        /// the foot of the screen, which is where the keyboard comes up — and
        /// the column is a scroller nested inside the board's own, so the
        /// keyboard's inset does not reach it and nothing scrolls the field
        /// clear. It opened under the keyboard and read as a button that had
        /// done nothing. The head of a column is above every keyboard there
        /// is, and is where the heading's `+` has always put it.
        var composesUnderTheAddRow: Bool
        var card: BoardTaskCard.Metrics
        var composer: BoardTaskComposer.Metrics
        var emptyState: EmptyStateView.Metrics
        var editor: ColumnEditorMetrics
        var colorWell: ColorWell.Metrics

        static let desk = Metrics(
            width: 272, cornerRadius: 16, horizontalPadding: 8, topPadding: 10, bottomPadding: 8,
            titleSize: 12.5, headerButton: 22, headerButtonRadius: 7,
            headerGlyph: 12, rowHit: 0,
            cardSpacing: 8, composesUnderTheAddRow: true,
            card: .desk, composer: .desk, emptyState: .desk,
            editor: .desk, colorWell: .desk
        )
        static let pad = Metrics(
            width: 320, cornerRadius: 18, horizontalPadding: 10, topPadding: 12, bottomPadding: 10,
            titleSize: 13.5, headerButton: 44, headerButtonRadius: 12,
            headerGlyph: 15, rowHit: 44,
            cardSpacing: 10, composesUnderTheAddRow: false,
            card: .pad, composer: .pad, emptyState: .sheet,
            editor: .pad, colorWell: .sheet
        )
    }

    /// The name/short/colour popover's sizes. Free-standing so ``Metrics`` can
    /// hold one without nesting a type inside a type inside a type.
    struct ColumnEditorMetrics {
        var width: CGFloat
        var fieldHeight: CGFloat
        var fieldFont: CGFloat
        var padding: CGFloat
        var spacing: CGFloat
        /// What the field claims for touch and for a reader, which is not what
        /// it draws — see ``FieldHitArea``.
        var fieldHit: CGFloat
        /// Which side of the header dot the popover hangs off, or `nil` to let
        /// the system place it.
        ///
        /// The desk names one because a window has room on every side of a
        /// column header and a fixed side reads as deliberate. The iPad names
        /// none: its header sits 134pt from the top of the display and a popover
        /// pinned above it opened *off the screen* — the Name field measured at
        /// y = -4.5 and every colour swatch reported `hittable=false`. Left to
        /// choose, UIKit puts it below the dot, which is where there is room.
        var arrowEdge: Edge?

        static let desk = ColumnEditorMetrics(
            width: 236, fieldHeight: 28, fieldFont: 13, padding: 14, spacing: 12, fieldHit: 0,
            arrowEdge: .bottom
        )
        static let pad = ColumnEditorMetrics(
            width: 280, fieldHeight: 44, fieldFont: 15, padding: 16, spacing: 14, fieldHit: 44,
            arrowEdge: nil
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(BoardFocusRelay.self) private var relay: BoardFocusRelay?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The strip is 272pt at a pointer and 320 under a finger, around a heading
    /// and cards that both grow with Dynamic Type — so the strip grows too. The
    /// board scrolls sideways, so a wider column costs nothing but the scroll.
    private var chrome = ChromeScale()

    let column: BoardColumn
    /// Its place in the board's own order, which is what "move left" means.
    let index: Int
    var metrics: Metrics = .desk
    /// The board's keyboard focus. Owned by ``BoardScrollView``, because focus
    /// crosses columns and no column can see its neighbours.
    @FocusState.Binding var focus: TaskItem.ID?

    @State private var isEditing = false
    /// Which end of the column the composer is open at.
    ///
    /// The heading's `+` opens it at the head, where it has always been. The
    /// foot's row opens it under itself where the platform lets it — a card is
    /// appended (`BoardStore.mintTask`), so the foot is also where the card is
    /// about to appear — and at the head where a software keyboard would take
    /// the foot of the screen; see ``Metrics/composesUnderTheAddRow``. Neither
    /// end can be open while the other is, because a column has one draft — see
    /// ``BoardStore/addingPlacement``.
    @State private var composesAtFoot = false
    /// Why the last delete did not happen. A refusal has an explanation to
    /// show — from the outside, a menu item that does nothing is a bug.
    @State private var refusal: ColumnRefusal?

    private var tasks: [TaskItem] { store.visibleTasks(in: column.id) }
    private var isDropTarget: Bool { store.dropTargetColumnID == column.id && store.draggingID != nil }
    private var isComposing: Bool { store.addingColumnID == column.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            cards
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
        .frame(width: chrome(metrics.width))
        // Lit while a card is over the column, which is the only thing that can
        // be dropped on one: a column is re-ordered from a menu now, so there is
        // no second kind of landing here to tell apart.
        .background(
            isDropTarget ? palette.accent.opacity(0.07) : palette.ink(0.035),
            in: .rect(cornerRadius: metrics.cornerRadius)
        )
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: metrics.cornerRadius)
                    .strokeBorder(palette.accent, lineWidth: 2)
            }
        }
        // Only this app's cards are a payload — a URL dragged out of Safari
        // used to light the column up as a drop target. Dropping is off in a
        // saved view, for the reason `BoardTaskCard` explains.
        .dropDestination(for: TaskTransfer.self) { items, _ in
            guard store.allowsCardDrag, let dropped = items.first, store[dropped.id] != nil
            else { return false }
            // The column's ground, not a gap between two of its cards — so it
            // lands at the foot; see `BoardStore.drop(_:onGroundOf:)`.
            store.drop(dropped.id, onGroundOf: store.placement(forColumn: column.id))
            return true
        } isTargeted: { targeted in
            if targeted, store.allowsCardDrag {
                store.dropTargetColumnID = column.id
                // On the column's *own ground* — a nested zone takes the hover
                // from its parent, so this firing at all means the pointer is
                // in no gap between two cards. That is the fact that retires a
                // caret; see `BoardStore.dropTargetCaret`.
                store.dropTargetCaret = nil
            } else if store.dropTargetColumnID == column.id {
                store.dropTargetColumnID = nil
            }
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
        .contextMenu { columnMenuItems }
    }

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(palette.resolve(column.dot))
                .frame(width: 8, height: 8)
                .popover(isPresented: $isEditing, arrowEdge: metrics.editor.arrowEdge) {
                    BoardColumnEditor(column: column, metrics: metrics)
                        .environment(store)
                        .environment(\.palette, palette)
                }

            Text(column.name)
                .font(palette.ui(metrics.titleSize, .extraBold, relativeTo: .footnote))
                .kerning(metrics.titleSize * 0.02)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            CountPill(count: tasks.count)

            Spacer(minLength: 0)

            columnMenu

            Button {
                composesAtFoot = false
                store.beginAdding(in: column.id)
            } label: {
                Image(systemName: "plus")
                    .symbolSize(metrics.headerGlyph, weight: .medium, relativeTo: .footnote)
                    .foregroundStyle(palette.inkText(0.45))
                    .frame(minWidth: chrome(metrics.headerButton), minHeight: chrome(metrics.headerButton))
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.08), radius: metrics.headerButtonRadius)
            .accessibilityLabel("Add task to \(column.name)")
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    /// Whether this is its board's Done column — the one that neither moves nor
    /// goes. See ``Board/doneColumn``.
    private var isDone: Bool { store.isDone(column: column.id) }

    private var columnMenu: some View {
        return Menu {
            columnMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .imageScale(.small)
                .foregroundStyle(palette.inkText(0.45))
                .frame(minWidth: chrome(metrics.headerButton), minHeight: chrome(metrics.headerButton))
                .contentShape(.rect)
                // The menu is named below; left in the tree the glyph is a
                // second element beside it, called "ellipsis" from Apple's
                // catalogue. `TaskInspector`'s board menu hides its own.
                .accessibilityHidden(true)
        }
        .modifier(BorderlessMenu())
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverBackground(palette.ink(0.08), radius: metrics.headerButtonRadius)
        .accessibilityLabel("\(column.name) column actions")
    }

    @ViewBuilder private var columnMenuItems: some View {
        let completedCount = isDone ? store.completedCount : 0
        if isDone {
            Button { store.archiveCompleted() } label: {
                Label(
                    String(localized: "Archive \(completedCount) Completed",
                           comment: "Menu item that files every finished task in the Done column away"),
                    systemImage: "archivebox"
                )
            }
            .disabled(completedCount == 0)
            Divider()
        }

            Button { isEditing = true } label: {
                Label("Edit Column…", systemImage: "pencil")
            }
            // The whole board, with this column already unfolded in it — where
            // the order of the columns is a list you can see rather than the two
            // items below, which move one column one place with nothing on
            // screen to say what the order was.
            Button {
                store.boardSettings = BoardSettingsRequest(
                    board: store.activeBoardID ?? column.id, column: column.id
                )
            } label: {
                Label("Board Settings…", systemImage: "slider.horizontal.3")
            }
            .disabled(store.activeBoardID == nil)
            Divider()
            // **Both are dead on the Done column, and Right is dead on the one
            // in front of it.** Done is the board's last column and that is what
            // makes it the column a tick sends cards to — see
            // ``Board/doneColumn`` — so it does not move, and nothing moves past
            // it. `moveColumn` refuses and clamps the same two cases; these are
            // greyed rather than left live because a menu item that can be
            // pressed and does nothing is indistinguishable from a bug, and
            // there is nothing to explain afterwards that the position does not
            // already say.
            Button {
                store.moveColumn(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
            } label: {
                Label("Move Left", systemImage: "arrow.left")
            }
            .disabled(index == 0 || isDone)
            Button {
                store.moveColumn(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
            } label: {
                Label("Move Right", systemImage: "arrow.right")
            }
            // `count - 2`, not `count - 1`: the last column is Done, so the one
            // before it is already as far right as a working column goes. Done
            // itself satisfies this too, which is why it needs no clause.
            .disabled(index >= store.columns.count - 2)
            Divider()
            // The cards go to the first column left rather than anywhere final,
            // so this asks for no confirmation either — but it can be refused,
            // and a refusal has to say why.
            Button(role: .destructive) {
                refusal = store.trashColumn(column.id)
            } label: {
                Label("Trash Column", systemImage: "trash")
            }
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: metrics.cardSpacing) {
                    if isComposing, !composesAtFoot { composer }
                    if preview?.index == 0 { previewCard }
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { row, task in
                        BoardCard(task: task, metrics: metrics.card, focus: $focus)
                            .id(task.id)
                        // After this card, which is the gap the stand-in opens
                        // when it is the row *following* this one.
                        if preview?.index == row + 1 { previewCard }
                    }
                    // A column with a card on the way into it is not empty, and
                    // the offer to add one is the wrong thing to be reading in
                    // the half-second before a drop lands.
                    if tasks.isEmpty, !isComposing, preview == nil {
                        emptyState
                            .padding(.top, 6)
                    }
                    if isComposing, composesAtFoot { composer }
                    // The empty state above carries the same offer in more
                    // words, and the composer *is* the offer taken — so the row
                    // is drawn under a column that has cards and no draft, and
                    // nowhere else.
                    if !tasks.isEmpty, !isComposing { addRow }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
                // The stand-in *is* the insertion point here, so the cards
                // beside it draw no line of their own — see `drawsDropCaret`.
                .environment(\.drawsDropCaret, false)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(minHeight: 40)
            // A column is taller than the window as often as not, so a key
            // landing on a card near the bottom has to bring the card with it.
            // A click asks for less: the card it landed on shown whole, and
            // nothing when it is whole already. See ``BoardReveal``.
            .onChange(of: reveal) { _, reveal in
                guard let reveal, tasks.contains(where: { $0.id == reveal.task }) else { return }
                Motion.run(.easeOut(duration: 0.16), reduceMotion: reduceMotion) {
                    switch reveal.manner {
                    case .centred: proxy.scrollTo(reveal.task, anchor: .center)
                    case .intoView: proxy.scrollTo(reveal.task)
                    }
                }
            }
            .onChange(of: isComposing) { _, composing in
                guard composing else {
                    // The next one opens where its own control says, not where
                    // the last one happened to be.
                    composesAtFoot = false
                    return
                }
                proxy.scrollTo(Self.composerID, anchor: .top)
            }
            // And when it changes ends without ever closing — the foot's row
            // pressed while the heading's composer is still up, which moves the
            // field rather than opening a second one.
            .onChange(of: composesAtFoot) { _, _ in
                guard isComposing else { return }
                proxy.scrollTo(Self.composerID, anchor: .top)
            }
        }
    }

    /// Where in this column a dragged card would land, or `nil` when none is
    /// on the way here. ``BoardStore/dropPreview(in:)`` is where the answer is
    /// worked out; the column only makes room for it.
    private var preview: DropPreview? { store.dropPreview(in: placement) }

    /// The stand-in itself, built once for the two places it can be drawn.
    @ViewBuilder private var previewCard: some View {
        if let preview {
            DropPreviewCard(
                preview: preview, cornerRadius: metrics.card.cornerRadius,
                reach: metrics.card.dropReach
            ) {
                BoardTaskCard(task: preview.task, metrics: metrics.card, isStandIn: true)
            }
            .id(Self.previewID)
        }
    }

    /// The one draft field, drawn at whichever end asked for it.
    private var composer: some View {
        BoardTaskComposer(placement: placement, metrics: metrics.composer)
            .id(Self.composerID)
    }

    /// The offer at the foot of the column, which is where the reading of a
    /// column ends and — the board being taller than the window as often as
    /// not — the only `+` in reach without scrolling back to the heading. The
    /// same row the phone draws under its own column pages; see
    /// ``ColumnAddRow``.
    private var addRow: some View {
        ColumnAddRow(name: column.name) {
            composesAtFoot = metrics.composesUnderTheAddRow
            store.beginAdding(in: column.id)
        }
        .padding(.top, 2)
    }

    /// This column as a place a card can be put.
    private var placement: TaskPlacement { store.placement(forColumn: column.id) }

    /// Flattened, for the reason ``BoardScrollView`` gives.
    private var reveal: BoardReveal? { relay?.reveal ?? nil }

    /// The composer's row, which has no task to be identified by.
    private static let composerID = "composer"
    /// The stand-in's, which has no task of its own either — the card it stands
    /// for is still in the column it is leaving.
    private static let previewID = "drop-preview"

    /// A column that renders as bare space says nothing about why. There is
    /// only one emptiness left to describe: the search does not empty a column
    /// any more — it opens a panel over the board instead, see
    /// ``SearchResultsPanel`` — so "nothing matched" cannot happen here.
    private var emptyState: some View {
        EmptyStateView.column(column, metrics: metrics.emptyState) {
            composesAtFoot = false
            store.beginAdding(in: column.id)
        }
    }
}

/// Name, abbreviation and dot for one column, in a popover off its header.
///
/// The abbreviation is here because nothing else edits it and `MoveToPicker`
/// draws it: a column renamed with no way to change its short name went on
/// calling itself by the old one in the control the phone uses to move cards.
///
/// There is no role here, and since v9 there is no role anywhere: a column is
/// the Done column by being its board's *last*, and nothing else about it says
/// what it is for. See ``Board/doneColumn``.
private struct BoardColumnEditor: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store

    let column: BoardColumn
    let metrics: BoardColumnView.Metrics

    @State private var name = ""
    @State private var short = ""
    @FocusState private var focus: Field?
    private var chrome = ChromeScale()

    private enum Field { case name, short }

    private var editor: BoardColumnView.ColumnEditorMetrics { metrics.editor }

    var body: some View {
        VStack(alignment: .leading, spacing: editor.spacing) {
            field("Name", text: $name, focus: .name)
            field("Short", text: $short, focus: .short)
            VStack(alignment: .leading, spacing: 6) {
                Text("Colour").sectionLabelStyle(size: 10, opacity: Palette.readableInk)
                ColorWell(selection: column.dot, metrics: metrics.colorWell) {
                    store.recolorColumn(column.id, to: $0)
                }
            }
        }
        .padding(editor.padding)
        .frame(width: chrome(editor.width, cap: 1.45))
        .onAppear {
            name = column.name
            short = column.short
        }
        .focusWhenReady($focus, .name)
        // Clicking away is a commit, the way the label manager's rename is. An
        // empty name is refused by the store and the fields simply fall back to
        // what is stored the next time this is opened.
        .onSubmit {
            commit()
            dismiss()
        }
        .onDisappear { commit() }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, focus target: Field) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).sectionLabelStyle(size: 10, opacity: Palette.readableInk)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(palette.ui(editor.fieldFont, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)
                .focused($focus, equals: target)
                .padding(.horizontal, 8)
                .frame(minHeight: chrome(editor.fieldHeight))
                .fieldHitArea(minHeight: editor.fieldHit) { focus = target }
                .background(palette.ink(0.06), in: .rect(cornerRadius: 8))
        }
    }

    private func commit() {
        store.renameColumn(column.id, to: name, short: short)
    }
}
