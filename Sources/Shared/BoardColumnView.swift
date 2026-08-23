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
        var addColumnWidth: CGFloat
        var headerButtonRadius: CGFloat
        /// The "+" glyph inside it.
        var headerGlyph: CGFloat
        /// The floor under a row that is not a button of its own — the role
        /// segments on the add-column tile. Zero at a pointer.
        var rowHit: CGFloat
        var cardSpacing: CGFloat
        var card: BoardTaskCard.Metrics
        var composer: BoardTaskComposer.Metrics
        var emptyState: EmptyStateView.Metrics
        var editor: ColumnEditorMetrics
        var dots: DotPicker.Metrics

        static let desk = Metrics(
            width: 272, cornerRadius: 16, horizontalPadding: 8, topPadding: 10, bottomPadding: 8,
            titleSize: 12.5, headerButton: 22, addColumnWidth: 38, headerButtonRadius: 7,
            headerGlyph: 12, rowHit: 0,
            cardSpacing: 8, card: .desk, composer: .desk, emptyState: .desk,
            editor: .desk, dots: .desk
        )
        static let pad = Metrics(
            width: 320, cornerRadius: 18, horizontalPadding: 10, topPadding: 12, bottomPadding: 10,
            titleSize: 13.5, headerButton: 44, addColumnWidth: 44, headerButtonRadius: 12,
            headerGlyph: 15, rowHit: 44,
            cardSpacing: 10, card: .pad, composer: .pad, emptyState: .sheet,
            editor: .pad, dots: .sheet
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
    /// Lit while a dragged column is over this one. Local rather than in the
    /// store, unlike `dropTargetColumnID`: a card's caret has to be drawn
    /// against a card the pointer never touched, and this is only ever drawn by
    /// the column under it.
    @State private var isColumnDropTarget = false
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
        // The same tint a card in flight draws, and deliberately: it says "let
        // go here" either way, and only one kind of thing can be in the air at a
        // time, so there is nothing for a second colour to tell apart.
        .background(
            isDropTarget || isColumnDropTarget
                ? palette.accent.opacity(0.07) : palette.ink(0.035),
            in: .rect(cornerRadius: metrics.cornerRadius)
        )
        .overlay {
            if isDropTarget || isColumnDropTarget {
                RoundedRectangle(cornerRadius: metrics.cornerRadius)
                    .strokeBorder(palette.accent, lineWidth: 2)
            }
        }
        // Above the card destination below, and drawn only while a column is in
        // the air — see ``columnDropZone``.
        .overlay { columnDropZone }
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
                .font(SimpleKanbanFont.ui(metrics.titleSize, .extraBold, relativeTo: .footnote))
                .kerning(metrics.titleSize * 0.02)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            CountPill(count: tasks.count)

            Spacer(minLength: 0)

            columnMenu

            Button {
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
        // **The grip a column is re-ordered by.** See ``lifted()``.
        //
        // Not on the Done column, which is its board's last and stays there —
        // see ``Board/doneColumn``. A grip that lifted and then refused to land
        // anywhere is worse than no grip: the store would refuse the drop, and
        // the only thing on screen to explain it would be the column sliding
        // back. `dropColumn` refuses it too, because a payload can also arrive
        // from a build that offered the drag.
        .contentShape(.rect)
        .modifier(ColumnGrip(isEnabled: !isDone, lift: lifted))
    }

    /// The payload, and the session with it — `ReorderableCard`'s trick, for its
    /// reason: `.draggable` takes this as an autoclosure and calls it when a
    /// session begins rather than when the header is drawn, which makes it the
    /// one moment both platforms agree a column has been picked up.
    ///
    /// **The whole header row is the grip, and it had to be.** The name alone
    /// was the obvious answer and it does not work: the board is a horizontal
    /// `ScrollView`, and a lift that starts on a run of text 57pt wide loses the
    /// touch to the scroller's pan every single time — measured on an iPad Air,
    /// where the board slid sideways and the column stayed exactly where it was.
    /// Padding the text was not enough; giving it the width the header had left
    /// was not enough either. What wins is the header itself, at the full width
    /// of the column. It is also the honest shape to aim at: the dot, the name
    /// and the count are one label, and the only two things in that row with
    /// business of their own are the `…` and `+` buttons, which take their own
    /// taps before this ever sees them.
    /// Whether this is its board's Done column — the one that neither moves nor
    /// goes. See ``Board/doneColumn``.
    private var isDone: Bool { store.isDone(column: column.id) }

    private func lifted() -> ColumnTransfer {
        store.beginColumnDrag(column.id)
        // The board this column is actually on, looked up rather than assumed
        // to be the active one — that is the fact `dropColumn` refuses across,
        // and a payload that simply repeated `activeBoardID` would make the
        // refusal tautological. A column no board owns cannot be drawn here at
        // all, and the fresh id it would carry is refused on arrival, which is
        // the right answer to a drag of nothing.
        return ColumnTransfer(column, on: store.board(ofColumn: column.id)?.id ?? Board.ID())
    }

    /// Where a dragged column can land: this whole column, but **only while one
    /// is in the air**.
    ///
    /// An overlay rather than a second `dropDestination` on the body, which
    /// already carries one for cards — ``ReorderableCard`` draws its gaps the
    /// same way and for the same reason. Nothing can be dragging a card and a
    /// column at once, so covering the card destination while a column is in
    /// flight costs nothing, and the rest of the time this is not in the tree at
    /// all.
    ///
    /// The whole column rather than its header: the header is where the grip is,
    /// but a 30pt band is not where a pointer carrying a column expects to have
    /// to let go.
    @ViewBuilder private var columnDropZone: some View {
        if store.draggingColumnID != nil {
            Color.clear
                .contentShape(.rect)
                .dropDestination(for: ColumnTransfer.self) { items, _ in
                    defer { store.endColumnDrag() }
                    guard let dropped = items.first else { return false }
                    isColumnDropTarget = false
                    return store.dropColumn(dropped, onto: column.id)
                } isTargeted: { targeted in
                    // Not the column being dragged: a line against the column
                    // that is leaving says nothing about where it lands.
                    // Not the column being dragged — a line against the column
                    // that is leaving says nothing about where it lands — and
                    // not past Done, which a drop here would be asking for: the
                    // store lands it in front instead, so the line belongs on
                    // the column before this one, not on this one.
                    isColumnDropTarget = targeted && store.draggingColumnID != column.id && !isDone
                }
        }
    }

    /// Everything that can be done to the column itself, plus — on a Done
    /// column with something in it — the archive.
    ///
    /// The archive item is drawn only while there is something to file. A
    /// control that is greyed out from the day it ships teaches people not to
    /// open the menu, and the column's own empty state already says there is
    /// nothing there. It archives what `completedTasks` holds rather than what
    /// the search has left visible — `archiveCompleted` is defined over Done,
    /// not over the query — so the count says how many are about to go.
    private var columnMenu: some View {
        Menu {
            if store.isDone(column: column.id), !store.completedTasks.isEmpty {
                Button {
                    store.archiveCompleted()
                } label: {
                    Label(
                        String(localized: "Archive \(store.completedTasks.count) Completed",
                               comment: "Menu item on the Done column header that files every finished task away"),
                        systemImage: "archivebox"
                    )
                }
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
            Button {
                store.moveColumn(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
            } label: {
                Label("Move Left", systemImage: "arrow.left")
            }
            .disabled(index == 0)
            Button {
                store.moveColumn(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
            } label: {
                Label("Move Right", systemImage: "arrow.right")
            }
            .disabled(index == store.columns.count - 1)
            Divider()
            // The cards go to the first column left rather than anywhere final,
            // so this asks for no confirmation either — but it can be refused,
            // and a refusal has to say why.
            Button(role: .destructive) {
                refusal = store.trashColumn(column.id)
            } label: {
                Label("Trash Column", systemImage: "trash")
            }
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

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: metrics.cardSpacing) {
                    if isComposing {
                        BoardTaskComposer(
                            placement: store.placement(forColumn: column.id),
                            metrics: metrics.composer
                        )
                        .id(Self.composerID)
                    }
                    ForEach(tasks) { task in
                        BoardCard(task: task, metrics: metrics.card, focus: $focus)
                            .id(task.id)
                    }
                    if tasks.isEmpty, !isComposing {
                        emptyState
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
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
                guard composing else { return }
                proxy.scrollTo(Self.composerID, anchor: .top)
            }
        }
    }

    /// Flattened, for the reason ``BoardScrollView`` gives.
    private var reveal: BoardReveal? { relay?.reveal ?? nil }

    /// The composer's row, which has no task to be identified by.
    private static let composerID = "composer"

    /// A column that renders as bare space says nothing about why. There is
    /// only one emptiness left to describe: the search does not empty a column
    /// any more — it opens a panel over the board instead, see
    /// ``SearchResultsPanel`` — so "nothing matched" cannot happen here.
    private var emptyState: some View {
        EmptyStateView.column(column, metrics: metrics.emptyState) {
            store.beginAdding(in: column.id)
        }
    }
}

/// The header's drag grip, on every column but Done.
///
/// A `ViewModifier` rather than a ternary because `.draggable` takes a payload,
/// not an optional one — `DraggableWhenOrdered` is the same shape for the same
/// reason. `lift` stays an escaping closure so the payload is still built when
/// the *session* starts rather than when the header is drawn; see ``lifted()``,
/// which is what makes `beginColumnDrag` land at the right moment.
private struct ColumnGrip: ViewModifier {
    let isEnabled: Bool
    let lift: () -> ColumnTransfer

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .draggable(lift())
                .help("Drag to re-order the columns")
        } else {
            content.help("The Done column stays at the end")
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
                DotPicker(current: column.dot, metrics: metrics.dots) {
                    store.recolorColumn(column.id, to: $0)
                }
                // Pulled back by half the swatch's own inset so the first dot
                // lines up with the labels above it rather than its target does.
                .padding(.leading, -3)
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
                .font(SimpleKanbanFont.ui(editor.fieldFont, .semibold, relativeTo: .subheadline))
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

/// The trailing tile of the column strip: how a board grows a column.
///
/// It names the column and nothing else, which since v9 is everything there is
/// to say: a column has no role to choose, and it lands where every new column
/// lands — in front of the board's Done column, which stays last. The role
/// segments that used to sit under this field are gone, and so is the pair they
/// were the only pointer-side way to reach.
struct AddColumnTile: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    /// Owned by ``BoardScrollView``, which has to know: an empty board draws
    /// one empty state instead of the strip, and the tile lives in the strip.
    @Binding var isComposing: Bool
    var metrics: BoardColumnView.Metrics = .desk

    @State private var name = ""
    @FocusState private var isFocused: Bool
    private var chrome = ChromeScale()

    /// The button is a strip and the composer is a column: naming a column
    /// wants a text field and the four roles beside it, which is a column's
    /// width whatever the button that opened it was.
    var body: some View {
        Group {
            if isComposing {
                composer.frame(width: chrome(metrics.width))
            } else {
                button.frame(width: chrome(metrics.addColumnWidth))
            }
        }
        .padding(.top, metrics.topPadding)
    }

    private var button: some View {
        Button { isComposing = true } label: {
            VStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .footnote))
                    .accessibilityHidden(true)
                // Turned rather than wrapped: the words are the tile's height,
                // and `verticalText` is what stops them claiming a column's
                // width while they are drawn on their side.
                Text("Add column", comment: "Button at the end of the board that starts a column")
                    .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .footnote))
                    .verticalText()
            }
            .foregroundStyle(palette.inkText(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        palette.ink(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            }
            // A strip narrower than the dashes are long has nothing to hit at
            // its edges; the shape is what the pointer and the finger get.
            .contentShape(.rect(cornerRadius: 16))
            .hoverBackground(palette.ink(0.05), radius: 16)
        }
        .buttonStyle(.bare)
        // The glyph beside the word is a second element to a reader whatever it
        // is asked to be; substituting the subtree is what takes it out.
        .accessibilityRepresentation {
            Button(String(localized: "Add column",
                          comment: "Accessibility name of the button that adds a column to the board")) {
                isComposing = true
            }
        }
    }

    private var composer: some View {
        TextField("Column name, then ⏎", text: $name)
            .accessibilityLabel("Column name")
            .textFieldStyle(.plain)
            .font(SimpleKanbanFont.ui(12.5, .extraBold, relativeTo: .footnote))
            .foregroundStyle(palette.ink)
            .focused($isFocused)
            .fieldHitArea(minHeight: metrics.rowHit) { isFocused = true }
            .onSubmit { create() }
            .onKeyPress(.escape) {
                cancel()
                return .handled
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(palette.card)
                    .shadow(color: palette.shadow(0.1), radius: 1, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(palette.accent.opacity(0.35), lineWidth: 2)
            }
            .focusWhenReady($isFocused)
            // The tile is a button that becomes a field, and it is a field only
            // while the field is being used: clicking away puts the button
            // back. Unlike the *task* composer, which holds a half-typed title
            // against a stray click, because there the row it leaves behind is
            // harmless — a column half-named is a control sitting where a
            // button should be, at the end of the strip, for the session.
            .onChange(of: isFocused) { _, focused in
                guard !focused else { return }
                Task { @MainActor in
                    // A turn before it acts, and the loss re-checked on the far
                    // side of it. The strip scrolls this tile into view in the
                    // same turn the composer opens in — see `BoardScrollView` —
                    // and a close that fired on any momentary loss would be a
                    // field that shuts as it appears.
                    await Task.yield()
                    guard !isFocused, isComposing else { return }
                    cancel()
                }
            }
    }

    /// A name with nothing in it is refused by the store, and the field stays
    /// open rather than closing on a column that was never made.
    private func create() {
        guard store.addColumn(named: name) != nil else { return }
        cancel()
    }

    private func cancel() {
        name = ""
        isComposing = false
    }
}
