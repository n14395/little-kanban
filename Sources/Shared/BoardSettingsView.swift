import SwiftUI

/// **A board's settings**: its name, its colour, and the columns it is made of —
/// each one's name, abbreviation, colour and place, plus the two that change the
/// shape of the board, adding a column and throwing one away.
///
/// **One view for three surfaces.** It was the phone's alone, and everything in
/// it existed on the desk as three separate controls: a rename in the sidebar's
/// context menu, a colour in a popover off the same menu, and a column's four
/// fields in a popover hanging off its header dot — with the order of the
/// columns spelled as *Move Left* / *Move Right* menu items, one column at a
/// time, and no way to see the order you were changing. A board is one thing and
/// this is where it is edited, on whichever platform.
///
/// The desk gets the same view at its own sizes rather than a second one: two
/// copies of "everything about a column" is two places for them to drift, and
/// this file has already been through that once — see `renameColumn(_:to:short:)`,
/// which exists because the phone could rename a column and nothing could rename
/// its abbreviation.
///
/// It holds the board's **id** rather than the board: a rename lands in the
/// store, and a snapshot taken when the sheet opened would go on showing the old
/// name underneath the field that had just changed it.
struct BoardSettingsView: View {
    /// The two idioms' sizes. A pointer's controls are the desk's, a finger's
    /// clear 44pt — the same split `SettingsView` and `DotPicker` make.
    struct Metrics {
        /// The board's name, which is the one serif line in here.
        var titleFont: CGFloat
        var rowFont: CGFloat
        var fieldFont: CGFloat
        /// What every control claims, whatever it draws.
        var hit: CGFloat
        /// Between the sections.
        var spacing: CGFloat
        var padding: CGFloat
        var radius: CGFloat
        var dots: DotPicker.Metrics

        static let desk = Metrics(
            titleFont: 21, rowFont: 13, fieldFont: 13, hit: 28,
            spacing: 15, padding: 18, radius: 10, dots: .desk
        )
        static let sheet = Metrics(
            titleFont: 26, rowFont: 15, fieldFont: 15, hit: 44,
            spacing: 18, padding: 20, radius: 12, dots: .sheet
        )
    }

    /// Which of the column editor's fields has the caret. The pair is the same
    /// on every row, so one enum covers whichever row is open, plus the
    /// composer's own field at the bottom of the list.
    private enum ColumnField: Hashable { case name, short, new }


    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let boardID: Board.ID
    var metrics: Metrics = .sheet
    /// Set by the routes that say *rename* rather than *settings*, which name
    /// the one field they mean and so should land the caret in it.
    var focusesName: Bool = false
    /// A column to arrive with already unfolded, set by the routes that name
    /// one: a phone chip's **Edit Column…** and the desk column header's.
    ///
    /// The same sheet rather than one of its own: everything a column can be
    /// changed to is already in this row — its name, its abbreviation, its
    /// colour, where it sits and whether it stays — and a second surface holding
    /// a copy of the four is a second place for them to drift. The board's own
    /// fields stay above it, which is also true: a column belongs to a board,
    /// and the chip that opened this is one of that board's.
    var expandsColumn: BoardColumn.ID?

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
    @FocusState private var columnFocus: ColumnField?
    /// Why the last delete did not happen. `BoardColumnView` keeps the same
    /// state for the same reason: a menu item that silently does nothing is
    /// indistinguishable from a bug.
    @State private var refusal: ColumnRefusal?
    /// The column a Trash button has asked about, and what trashing it would
    /// cost — see ``ColumnTrashWarning``. Held rather than acted on: this is the
    /// one control in here that moves other people's cards.
    @State private var trashWarning: ColumnTrashWarning?

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
        // How it is *presented* — a detent and a grabber on iOS, a fixed frame
        // on the desk — belongs to whatever put it up, the split `SettingsView`
        // makes with `SettingsSheet` and `SettingsWindow`.
        .focusWhenReady($isNameFocused, when: focusesName)
        .onAppear {
            draft = board?.name ?? ""
            // `addColumn` and `moveColumn` are defined over the *active* board —
            // a column has no board of its own to name, only the board that
            // holds it. Editing a board that is not the one on screen would
            // otherwise add the column to whichever board was, under a list of
            // the columns of the one being edited. Switching to it is the
            // cheaper half of that bargain: every route in here is a way in to a
            // board, and the user ends up on the board they were just editing.
            if store.activeBoardID != boardID { store.selectBoard(boardID) }
            if let expandsColumn, let column = board?.column(id: expandsColumn) {
                open(column)
            }
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
        // **The one change in here that reaches past the board's own chrome.**
        // Everything else — a name, an abbreviation, a colour, an order — is
        // visible the moment it happens and is one ⌘Z from being back. Trashing
        // a column is not: it moves other people's cards to another column. So
        // it says what it is about to do, in the numbers of this board.
        //
        // A reorder used to ask as well, because it could change which column
        // was the Done one and so where every future tick sent a card, with
        // nothing on the board to show for it. It cannot now — Done is the last
        // column and does not move — so there is nothing left to ask about.
        .alert(
            trashWarning?.title ?? "",
            isPresented: Binding(get: { trashWarning != nil }, set: { if !$0 { trashWarning = nil } }),
            presenting: trashWarning
        ) { warning in
            Button("Trash Column", role: .destructive) { trash(warning.column) }
            Button("Cancel", role: .cancel) { trashWarning = nil }
        } message: { warning in
            Text(warning.detail)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Board Settings")
                .font(SimpleKanbanFont.ui(metrics.rowFont, .bold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Done")
                    .font(SimpleKanbanFont.ui(metrics.rowFont, .bold, relativeTo: .body))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 10)
                    .frame(minHeight: metrics.hit)
            }
            .buttonStyle(.bare)
        }
        .padding(.horizontal, metrics.padding)
        .padding(.vertical, 8)
    }

    private func content(_ board: Board) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.spacing) {
                    nameField
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Colour").sectionLabelStyle(opacity: Palette.readableInk)
                        DotPicker(current: board.dot, metrics: metrics.dots) {
                            store.recolorBoard(boardID, to: $0)
                        }
                        // The row of squares tiles edge to edge, so the first dot
                        // sits inset from the margin the fields keep.
                        .padding(.leading, -(metrics.dots.hitSize - metrics.dots.dot) / 2)
                    }
                    columns(board)
                    deleteRow
                }
                .padding(.horizontal, metrics.padding)
                .padding(.top, metrics.padding - 4)
                .padding(.bottom, metrics.padding + 16)
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
            // A sheet opened straight onto a column has to *show* it. The board
            // name, the colour row and however many columns come first are
            // above it, so the fifth column of five opens off the bottom of the
            // sheet and it looks as though it ignored what was asked for.
            .onAppear {
                guard let expandsColumn else { return }
                reveal(expandsColumn, in: proxy, anchor: .center)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Name").sectionLabelStyle(opacity: Palette.readableInk)
            TextField("Board name", text: $draft)
                .textFieldStyle(.plain)
                .font(SimpleKanbanFont.serif(metrics.titleFont))
                .foregroundStyle(palette.ink)
                .focused($isNameFocused)
                .submitLabel(.done)
                .onSubmit {
                    commitRename()
                    isNameFocused = false
                }
                // The field's own hit area is the height of its text; the rest
                // of the 44pt row hands focus over, as the detail sheet's do.
                .frame(maxWidth: .infinity, minHeight: metrics.hit, alignment: .leading)
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
                        .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .body))
                        .foregroundStyle(palette.ink(0.8))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Nothing but the name. Up to v8 every row carried its
                    // `ColumnRole` here — "Backlog", "Doing", "Done" — beside a
                    // "Completed" pill on whichever column a tick actually sent
                    // a card to. Two of the three roles never did anything, the
                    // third is now the last row by definition, and the pill was
                    // marking a distinction that no longer exists.
                    Text(verbatim: isOpen ? "\u{2303}" : "\u{2304}")
                        .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .caption2))
                        .foregroundStyle(palette.inkText(0.35))
                }
                .padding(12)
                .frame(minHeight: metrics.hit)
                .contentShape(.rect)
            }
            .buttonStyle(.bare)
            // `viewRow`'s treatment, for `viewRow`'s reason: the row is one
            // thing to a reader — the column's name, its role as the value.
            .accessibilityRepresentation {
                Button(column.name) { toggle(column) }
                    // The Done column still says so out loud. Sighted readers
                    // have its position and the line in its open editor; a
                    // reader moving row by row has neither.
                    .accessibilityValue(
                        isDoneColumn(column)
                            ? String(localized: "Completed tasks land here",
                                     comment: "Spoken value on the board's last column, where ticking a task sends it")
                            : ""
                    )
                    .accessibilityAddTraits(isOpen ? [.isSelected] : [])
            }

            if isOpen {
                columnEditor(column, index: index, count: count)
            }
        }
        .background(isOpen ? palette.ink(0.045) : .clear, in: .rect(cornerRadius: metrics.radius))
        // What `expandsColumn` scrolls to.
        .id(column.id)
    }

    /// Whether this is the board's Done column: its last, which is
    /// ``Board/doneColumn``'s rule read back rather than restated.
    ///
    /// It is the one row that cannot be moved or trashed, so it is the one row
    /// that draws neither control.
    private func isDoneColumn(_ column: BoardColumn) -> Bool {
        board?.doneColumn?.id == column.id
    }

    /// Everything a column can be changed to. Since v9 that is all of it: there
    /// is no role left to leave out.
    ///
    /// **The Done column gets the fields and not the buttons.** It can be
    /// renamed and recoloured — real boards call it Shipped, Live and Published,
    /// and `SeedData.contentCalendar` already ships one called Published — but
    /// it cannot be moved off the end or thrown away, because being on the end
    /// is what makes it the column a tick sends cards to. A line of text says so
    /// where the controls would have been, rather than three disabled buttons
    /// that would leave a person pressing them to find out why.
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
                DotPicker(current: column.dot, metrics: metrics.dots) {
                    store.recolorColumn(column.id, to: $0)
                }
                .padding(.leading, -(metrics.dots.hitSize - metrics.dots.dot) / 2)
            }

            if isDoneColumn(column) {
                Text("Every board keeps its Done column, at the end. Ticking a task sends it here.")
                    .font(SimpleKanbanFont.ui(12.5, .medium, relativeTo: .footnote))
                    .foregroundStyle(palette.inkText(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    // Reordering, for a list that cannot be dragged: these rows
                    // are a `VStack` in a sheet's scroller, and `onMove` belongs
                    // to `List`. The drawer's board rows make the same trade.
                    stepButton("Move Up", glyph: "\u{2191}", isEnabled: index > 0) {
                        move(from: index, to: index - 1)
                    }
                    // `count - 2`, not `count - 1`: the last row is Done and
                    // stays there, so the row above it is already as far down as
                    // a working column goes. The store clamps this too — see
                    // `moveColumn` — and the button is disabled rather than
                    // silently doing nothing.
                    stepButton("Move Down", glyph: "\u{2193}", isEnabled: index < count - 2) {
                        move(from: index, to: index + 2)
                    }
                    Spacer(minLength: 0)
                    deleteColumnButton(column)
                }
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
                .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .body))
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
                .frame(maxWidth: .infinity, minHeight: metrics.hit, alignment: .leading)
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
                .font(SimpleKanbanFont.ui(metrics.rowFont, .bold, relativeTo: .body))
                .foregroundStyle(palette.ink(isEnabled ? 0.6 : 0.22))
                .frame(minWidth: metrics.hit, minHeight: metrics.hit)
                .background(palette.ink(0.06), in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.bare)
        .disabled(!isEnabled)
        .accessibilityLabel(name)
    }

    /// **This one asks.** The cards on a column are not thrown away with it —
    /// they move to the first column left — but they *do* move, and they are not
    /// necessarily the cards of whoever is in this sheet reshaping a board. The
    /// alert says how many and where to; see ``ColumnTrashWarning``.
    ///
    /// It can also be refused outright, and a refusal has to say why: a board
    /// down to its last working column has nowhere for work to start. The Done
    /// column never reaches here — it draws no Trash button at all.
    private func deleteColumnButton(_ column: BoardColumn) -> some View {
        Button(role: .destructive) {
            commitColumnRename()
            trashWarning = ColumnTrashWarning(
                column: column.id,
                name: column.name,
                cards: store.cardCount(inColumn: column.id),
                refuge: store.refuge(ifTrashing: column.id)?.name
            )
        } label: {
            Text("Trash Column")
                .font(SimpleKanbanFont.ui(13.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(destructiveTone.foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: metrics.hit)
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
                    .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .body))
                    .foregroundStyle(palette.inkText(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .frame(minHeight: metrics.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)
        }
    }

    private var addColumnComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            // A name and nothing else. There used to be four role segments
            // above this field, and they had to be *above* it because the band
            // below is where the software keyboard lands — a tap aimed at Doing
            // or Done reached the keyboard instead and the column was made a
            // Backlog without a word said. Both problems left with the roles.
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
                        .frame(minHeight: metrics.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.bare)
                Spacer(minLength: 0)
                Button { addColumn() } label: {
                    Text("Add Column")
                        .font(SimpleKanbanFont.ui(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: metrics.hit)
                        .background(palette.accent, in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.bare)
            }
        }
        .padding(12)
        .background(palette.ink(0.045), in: .rect(cornerRadius: metrics.radius))
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
    /// pinning the composer's bottom edge to the bottom of what is left puts the
    /// whole of it in reach.
    private func reveal(in proxy: ScrollViewProxy) {
        reveal(Self.composerAnchor, in: proxy, anchor: .bottom)
    }

    /// Brings something in this sheet into view, after the beat the sheet takes
    /// to finish arriving — scrolling a `ScrollView` that is still being
    /// presented moves nothing.
    private func reveal(_ id: some Hashable, in proxy: ScrollViewProxy, anchor: UnitPoint) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
                proxy.scrollTo(id, anchor: anchor)
            }
        }
    }

    /// A name with nothing in it is refused by the store, and the composer stays
    /// open rather than closing on a column that was never made.
    private func addColumn() {
        guard store.addColumn(named: newColumnName) != nil else { return }
        cancelAddColumn()
    }

    private func cancelAddColumn() {
        newColumnName = ""
        columnFocus = nil
        isAddingColumn = false
    }

    /// Opening one column closes whichever was open, committing its fields on
    /// the way — the same bargain the board's own name field makes.
    private func toggle(_ column: BoardColumn) {
        if expandedColumnID == column.id {
            commitColumnRename()
            columnFocus = nil
            expandedColumnID = nil
        } else {
            open(column)
        }
    }

    /// Unfolds a column's editor and fills its fields.
    ///
    /// Split out of `toggle` so a chip's **Edit Column…** and a tap on the row
    /// arrive in exactly the same state: the drafts are what the fields bind to,
    /// and a row unfolded without them shows the *last* column's name in the
    /// field under this column's heading.
    private func open(_ column: BoardColumn) {
        commitColumnRename()
        columnFocus = nil
        expandedColumnID = column.id
        columnNameDraft = column.name
        columnShortDraft = column.short
    }

    private func commitColumnRename() {
        guard let id = expandedColumnID else { return }
        store.renameColumn(id, to: columnNameDraft, short: columnShortDraft)
        if let column = store.column(id: id) {
            columnNameDraft = column.name
            columnShortDraft = column.short
        }
    }

    /// Moves a column.
    ///
    /// `toOffset` is `SwiftUI`'s: an index in the list *before* the move, which
    /// is why moving down is `index + 2`. The callers keep that spelling and
    /// this passes it through untouched — arithmetic done twice is arithmetic
    /// that can disagree.
    ///
    /// It used to have a question in front of it, because a reorder could change
    /// which column completed cards landed in. Done is the last column now and
    /// does not move, so a reorder cannot change anything a person would want
    /// warning about.
    private func move(from index: Int, to offset: Int) {
        store.moveColumn(fromOffsets: IndexSet(integer: index), toOffset: offset)
    }

    private func trash(_ id: BoardColumn.ID) {
        trashWarning = nil
        refusal = store.trashColumn(id)
        if refusal == nil { expandedColumnID = nil }
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
                .frame(minHeight: metrics.hit + 4)
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
        palette.dueTone(urgency: .overdue, isDone: false)
    }

    private func commitRename() {
        store.renameBoard(boardID, to: draft)
        draft = store.board(id: boardID)?.name ?? draft
    }
}

/// What trashing a column would cost, held while the alert asks.
///
/// The numbers are taken when the button is pressed rather than read again in
/// the alert: what the user is agreeing to is what they were shown, and the
/// board can change underneath a presented alert — a card dropped into the
/// column by a drag on another surface, a sync landing.
struct ColumnTrashWarning: Identifiable, Equatable {
    var column: BoardColumn.ID
    var name: String
    /// Archived cards included: `deleteColumn` moves those too, and a count that
    /// left them out would promise to move four cards and move nine.
    var cards: Int
    /// The first column left standing, which is where the cards go. `nil` only
    /// where there is no column left at all, which the store refuses anyway.
    var refuge: String?

    var id: BoardColumn.ID { column }

    var title: String {
        String(localized: "Trash “\(name)”?",
               comment: "Alert title before a board column is thrown away; the placeholder is the column's name")
    }

    /// Three facts, in the order they matter: what happens to the cards, where
    /// they go, and that the column itself is recoverable. An empty column says
    /// only the last of them — "0 cards move to Backlog" is noise.
    var detail: String {
        let recovery = String(
            localized: "The column goes to the Trash, where it can be restored for thirty days.",
            comment: "Alert body explaining that a trashed column can be restored"
        )
        guard cards > 0, let refuge else { return recovery }
        let moved = String(
            localized: "Its \(cards) cards move to “\(refuge)” — nothing on it is deleted.",
            comment: "Alert body: how many cards a trashed column holds and which column they move to"
        )
        return moved + " " + recovery
    }
}

