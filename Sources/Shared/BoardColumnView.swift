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
        // used to light the column up as a drop target. Dropping is off while a
        // query filters the board, for the reason `BoardTaskCard` explains.
        .dropDestination(for: TaskTransfer.self) { items, _ in
            guard store.allowsCardDrag, let dropped = items.first, store[dropped.id] != nil
            else { return false }
            store.move(dropped.id, to: column.id)
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
            if column.role == .done, !store.completedTasks.isEmpty {
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
                refusal = store.deleteColumn(column.id)
            } label: {
                Label("Delete Column", systemImage: "trash")
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

    /// "Nothing matched" and "nothing here yet" are different problems with
    /// different ways out, and a column that renders as bare space says neither.
    @ViewBuilder
    private var emptyState: some View {
        if store.isFiltering {
            EmptyStateView.noResults(query: store.query, metrics: metrics.emptyState) {
                store.clearQuery()
            }
        } else {
            EmptyStateView.column(column, metrics: metrics.emptyState) {
                store.beginAdding(in: column.id)
            }
        }
    }
}

/// Name, abbreviation and dot for one column, in a popover off its header.
///
/// The abbreviation is here because nothing else edits it and `MoveToPicker`
/// draws it: a column renamed with no way to change its short name went on
/// calling itself by the old one in the control the phone uses to move cards.
///
/// The role is not here. Nothing can change a column's role once it exists —
/// `BoardStore` has no `setColumnRole`, which is also why the refusal to delete
/// the last Done column suggests something the user cannot yet do.
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
            focus = .name
        }
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
/// The role is chosen here and nowhere else, so a board can be given the second
/// Done column that changing an existing column's role would otherwise need.
struct AddColumnTile: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    /// Owned by ``BoardScrollView``, which has to know: an empty board draws
    /// one empty state instead of the strip, and the tile lives in the strip.
    @Binding var isComposing: Bool
    var metrics: BoardColumnView.Metrics = .desk

    @State private var name = ""
    @State private var role: ColumnRole = .backlog
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
        VStack(alignment: .leading, spacing: 10) {
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
            rolePicker
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
        .onAppear { isFocused = true }
    }

    /// What the column is *for*, which is the one thing about it the board
    /// behaves on: only `.done` carries anything, and picking it wrong is worth
    /// one control at the moment of creation.
    private var rolePicker: some View {
        HStack(spacing: 4) {
            ForEach(ColumnRole.allCases, id: \.self) { option in
                let isCurrent = option == role
                Button { role = option } label: {
                    Text(Self.roleName(option))
                        .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .caption))
                        .foregroundStyle(isCurrent ? palette.ink : palette.inkText(0.5))
                        .lineLimit(1)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: metrics.rowHit)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isCurrent ? palette.card : .clear)
                                .shadow(color: isCurrent ? palette.shadow(0.16) : .clear, radius: 1.5, y: 1)
                        }
                }
                .buttonStyle(.bare)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(palette.ink(0.06), in: .rect(cornerRadius: 10))
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

    /// A name with nothing in it is refused by the store, and the field stays
    /// open rather than closing on a column that was never made.
    private func create() {
        guard store.addColumn(named: name, role: role) != nil else { return }
        cancel()
    }

    private func cancel() {
        name = ""
        role = .backlog
        isComposing = false
    }
}
