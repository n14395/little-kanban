// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// **A board's settings**: its name, its icon, and the columns it is made of —
/// each one's name, abbreviation, colour and place, plus the two that change the
/// shape of the board, adding a column and throwing one away.
///
/// **One view for three surfaces.** It was the phone's alone, and everything in
/// it existed on the desk as three separate controls: a rename in the sidebar's
/// context menu, a mark in a popover off the same menu, and a column's four
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
        /// How far a row's two insertion targets reach past it, into the gap
        /// either side. Half the 2pt the rows are spaced by would be 1, which is
        /// nothing to aim at; this overlaps the neighbouring row instead, and
        /// the half nearest the pointer is the one it is over.
        static let dropReach: CGFloat = 6

        /// The narrowest a Name field may be before the composer gives up on
        /// one row and stacks its colour swatches under the fields. Not per
        /// idiom: it is how much of a column name has to be legible while it is
        /// typed, which is the same question on every surface.
        static let nameFloor: CGFloat = 140

        /// What the Short field claims beside a Name field that takes the rest.
        /// Sized to what goes in it — "Backlog", "Doing", "Rev" — rather than to
        /// a share of the row, because the row is a different width on every
        /// surface and the word in it is not.
        var shortWidth: CGFloat
        /// What the colour button claims beside the two fields, where they
        /// share a row. Wider than the words need so the swatch reads as a
        /// swatch rather than as a tinted label.
        var colourWidth: CGFloat
        var colorWell: ColorWell.Metrics
        /// The board's icon control, which stands where its colour well stood.
        /// Columns have no icon: a column is still a coloured dot.
        var symbolWell: SymbolWell.Metrics

        static let desk = Metrics(
            titleFont: 21, rowFont: 13, fieldFont: 13, hit: 28,
            spacing: 15, padding: 18, radius: 10, shortWidth: 96,
            colourWidth: 132, colorWell: .desk, symbolWell: .desk
        )
        static let sheet = Metrics(
            titleFont: 26, rowFont: 15, fieldFont: 15, hit: 44,
            spacing: 18, padding: 20, radius: 12, shortWidth: 108,
            colourWidth: 148, colorWell: .sheet, symbolWell: .sheet
        )
    }

    /// Which field holds the keyboard. Two rows have two fields each — a
    /// column's editor and the composer that makes one — so this names the row
    /// as well as the field, and the two questions the rest of the file asks of
    /// it are answered here rather than at each site by listing cases.
    private enum ColumnField: Hashable {
        case name, short, new, newShort

        /// The composer's pair, which is what the software keyboard has to be
        /// scrolled clear of: it is the last thing in the sheet.
        var isComposer: Bool { self == .new || self == .newShort }

        /// The two that hold an abbreviation rather than a name, so a reader
        /// hears the same thing in either row.
        var isShort: Bool { self == .short || self == .newShort }
    }


    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let boardID: Board.ID
    var metrics: Metrics = .sheet
    /// Set by the routes that say *rename* rather than *settings*, which name
    /// the one field they mean and so should land the caret in it.
    var focusesName: Bool = false
    /// Whether to arrive with the add-column composer already open — see
    /// ``BoardSettingsRequest/addsColumn``.
    var addsColumn: Bool = false
    /// Whether the board has just been made — see
    /// ``BoardSettingsRequest/namesNewBoard``. The name field arrives focused
    /// and empty.
    var namesNewBoard: Bool = false
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
    /// The gap a column being dragged would land in, and the column in the air
    /// that would land there. Local because this is the only place a column is
    /// dragged — the board's own strip re-orders from a menu — and because a
    /// session left open by a drag that ended inside a dismissed sheet would
    /// outlive the thing that started it.
    @State private var columnCaret: ColumnCaret?
    @State private var draggingColumnID: BoardColumn.ID?
    @State private var columnNameDraft = ""
    @State private var columnShortDraft = ""
    @State private var newColumnName = ""
    /// The abbreviation for the column being composed. Empty is a real answer,
    /// not a missing one — `addColumn` reads it as "call it what the column is
    /// called".
    @State private var newColumnShort = ""
    /// The dot for the column being composed. Opens on the same value a column
    /// made without touching the picker would have had — see
    /// ``BoardColumn/defaultDot``, which is why no swatch is ringed to begin
    /// with.
    @State private var newColumnDot = BoardColumn.defaultDot
    @FocusState private var columnFocus: ColumnField?
    /// Why the last delete did not happen. `BoardColumnView` keeps the same
    /// state for the same reason: a menu item that silently does nothing is
    /// indistinguishable from a bug.
    @State private var refusal: ColumnRefusal?
    /// The column a Trash button has asked about, and what trashing it would
    /// cost — see ``ColumnTrashWarning``. Held rather than acted on: this is the
    /// one control in here that moves other people's cards.
    @State private var trashWarning: ColumnTrashWarning?
    /// The same for the board itself — see ``BoardTrashWarning``. Trashing a
    /// board now takes every card on it, which is the most destructive thing
    /// this sheet can do and the one act in it that has to be agreed to.
    @State private var boardWarning: BoardTrashWarning?

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
        .background(palette.windowFill)
        // How it is *presented* — a detent and a grabber on iOS, a fixed frame
        // on the desk — belongs to whatever put it up, the split `SettingsView`
        // makes with `SettingsSheet` and `SettingsWindow`.
        .focusWhenReady($isNameFocused, when: focusesName || namesNewBoard)
        .onAppear {
            // Empty for a board that has only just been made: it is called
            // ``Board/defaultName`` and nobody chose that, so the field shows
            // its placeholder and the first keystroke is the name. Closing
            // without typing leaves the board called what it was — `renameBoard`
            // refuses an empty name, and `commitRename` reads the kept one back.
            draft = namesNewBoard ? "" : (board?.name ?? "")
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
            if addsColumn { isAddingColumn = true }
        }
        .onDisappear {
            commitRename()
            commitColumnRename()
        }
        // A sheet with no board under it is a header over nothing. The merge
        // race used to leave exactly that on screen — a just-made board
        // swallowed while its settings opened — and a board can also genuinely
        // go while its settings are up, deleted on another device. Either way
        // the sheet goes with its board rather than standing empty.
        .onChange(of: board == nil) { _, isGone in
            if isGone { store.boardSettings = nil }
        }
        .task {
            if board == nil { store.boardSettings = nil }
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
        // The sheet is dismissed by the confirm rather than by the button that
        // raises this, or it would close out from under its own alert and take
        // the question with it.
        .alert(
            boardWarning?.title ?? "",
            isPresented: Binding(get: { boardWarning != nil }, set: { if !$0 { boardWarning = nil } }),
            presenting: boardWarning
        ) { warning in
            Button("Trash Board", role: .destructive) {
                boardWarning = nil
                store.trashBoard(warning.board)
                dismiss()
            }
            Button("Cancel", role: .cancel) { boardWarning = nil }
        } message: { warning in
            Text(warning.detail)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Board Settings")
                .font(palette.ui(metrics.rowFont, .bold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Done")
                    .font(palette.ui(metrics.rowFont, .bold, relativeTo: .body))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 10)
                    .frame(minHeight: metrics.hit)
            }
            .bareButton()
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
                        Text("Icon").sectionLabelStyle(opacity: Palette.readableInk)
                        SymbolWell(selection: board.symbol, metrics: metrics.symbolWell) {
                            store.setBoardSymbol(boardID, to: $0)
                        }
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
                if focus?.isComposer == true { reveal(in: proxy) }
            }
            // A sheet opened straight onto a column has to *show* it. The board
            // name, the icon row and however many columns come first are
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
                .font(palette.display(metrics.titleFont))
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
    /// The columns in board order, with the composer **between the working ones
    /// and Done**.
    ///
    /// Where a new column actually goes — `addColumn` inserts in front of Done,
    /// which stays last — so the button sits where the column it makes will
    /// appear. On the end it read as "add a column after Done", which is the one
    /// place a column cannot go.
    ///
    /// `index` is the column's place in `board.columns`, not in either of the
    /// two runs, because that is what `move(from:to:)` and `moveColumn` count in.
    private func columns(_ board: Board) -> some View {
        let count = board.columns.count
        return VStack(alignment: .leading, spacing: 7) {
            Text("Columns").sectionLabelStyle(opacity: Palette.readableInk)
            VStack(spacing: 2) {
                ForEach(Array(board.workingColumns.enumerated()), id: \.element.id) { index, column in
                    columnRow(column, index: index, count: count)
                }
            }
            addColumnRow
            if let done = board.doneColumn {
                columnRow(done, index: count - 1, count: count)
            }
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
                        .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .body))
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
                        .font(palette.ui(11, .bold, relativeTo: .caption2))
                        .foregroundStyle(palette.inkText(0.35))
                }
                .padding(12)
                .frame(minHeight: metrics.hit)
                .contentShape(.rect)
            }
            .bareButton()
            // **The grip.** The closed header only: an open row is one being
            // typed into, and a drag starting on its fields would fight the
            // caret. `BoardColumnView` makes the same trade for the same reason
            // — there the whole header is the grip and the two buttons on it
            // take their own presses first.
            .modifier(
                ColumnRowGrip(
                    isEnabled: !isOpen && !isDoneColumn(column),
                    payload: {
                        liftColumn(column.id)
                        return ColumnTransfer(column, on: boardID)
                    }
                )
            )
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
        // **Where a dragged column would land**, drawn in the gap it would land
        // in rather than on a row it would not.
        .overlay { dropZones(for: column) }
        .overlay(alignment: caretEdge(for: column) ?? .top) { caretMark(for: column) }
        // What `expandsColumn` scrolls to.
        .id(column.id)
    }

    // MARK: Re-ordering by drag

    /// The row's two halves, as separate insertion targets: the top half means
    /// *above this column*, the bottom half means *below it*. `BoardTaskCard`
    /// does the same for the board's cards, and the notes there are the notes
    /// here — halves because a drop that names a *row* can only mean a gap by
    /// guessing which way the drag came from, over the row rather than behind
    /// it because a drop stops at whatever is in front, and only while
    /// something is in the air because otherwise they take the tap that opens
    /// the row.
    ///
    /// The Done row is the one that draws a single zone: nothing lands after
    /// it, so the whole of it means *in front of Done*. And they reach
    /// ``Metrics/dropReach`` past the row at each end so one row's halves meet
    /// the next one's in the middle of the gap, and a pointer between two rows
    /// is over one of them rather than over neither.
    @ViewBuilder private func dropZones(for column: BoardColumn) -> some View {
        if draggingColumnID != nil {
            VStack(spacing: 0) {
                dropZone(.above(column.id))
                if !isDoneColumn(column) { dropZone(.below(column.id)) }
            }
            .padding(.vertical, -Metrics.dropReach)
        }
    }

    private func dropZone(_ caret: ColumnCaret) -> some View {
        Color.clear
            .contentShape(.rect)
            .dropDestination(for: ColumnTransfer.self) { items, _ in
                defer { endColumnDrag() }
                guard let dropped = items.first else { return false }
                commitColumnRename()
                return store.dropColumn(dropped, at: caret)
            } isTargeted: { targeted in
                // Cleared only by the half that set it: leaving one for the next
                // fires this one's `false` after the other's `true`, and an
                // unguarded clear would take the new target down with it.
                if targeted {
                    columnCaret = caret
                } else if columnCaret == caret {
                    columnCaret = nil
                }
            }
    }

    /// Which edge of this row the mark goes on, or `nil` for no mark.
    ///
    /// Nothing against the row in the air — it is about to leave, and a line on
    /// a row that is going says nothing about where anything lands — and nothing
    /// against the two gaps it already sits between, which is `dropColumn`
    /// refusing a move to where the column already is, read back.
    private func caretEdge(for column: BoardColumn) -> Alignment? {
        guard let columnCaret, columnCaret.column == column.id,
              let dragging = draggingColumnID, dragging != column.id,
              let from = store.columns.firstIndex(where: { $0.id == dragging }),
              let anchor = store.columns.firstIndex(where: { $0.id == column.id })
        else { return nil }
        switch columnCaret {
        case .above: return anchor == from + 1 ? nil : .top
        case .below: return anchor == from - 1 ? nil : .bottom
        }
    }

    /// The insertion point: the line that says *here*, in the gap the column
    /// would land in. The same mark the board's cards and the checklist's rows
    /// draw, drawn against the row it names rather than floating in the gap —
    /// an overlay knows its row's bounds and not the list's spacing.
    @ViewBuilder private func caretMark(for column: BoardColumn) -> some View {
        if caretEdge(for: column) != nil {
            Capsule()
                .fill(palette.accent)
                .frame(height: 3)
                .padding(.horizontal, 1)
                // A mark, not a target: without this it is a hole in the row it
                // is drawn on, and the drop under it goes nowhere.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// A column has left the ground. Deferred into a task of its own because
    /// this is called from the payload closure `.draggable` evaluates when the
    /// session starts, and writing state straight from there is writing it
    /// inside a view update — the latch and the expiry are `BoardStore.beginDrag`'s,
    /// which is where the same problem was solved for cards.
    ///
    /// **The expiry is what a cancelled drag needs.** A column let go over
    /// nothing tells nobody, and until this clears the zones stay over every row
    /// and take the tap that opens one.
    private func liftColumn(_ id: BoardColumn.ID) {
        Task { @MainActor in
            guard draggingColumnID != id else { return }
            draggingColumnID = id
            try? await Task.sleep(for: .seconds(BoardStore.liftExpiry))
            if draggingColumnID == id { endColumnDrag() }
        }
    }

    private func endColumnDrag() {
        draggingColumnID = nil
        columnCaret = nil
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
            columnShape(
                name: $columnNameDraft, nameFocus: .name,
                short: $columnShortDraft, shortFocus: .short,
                dot: column.dot, setDot: { store.recolorColumn(column.id, to: $0) }
            )

            columnLimit(column)

            if isDoneColumn(column) {
                Text("Every board keeps its Done column, at the end. Ticking a task sends it here.")
                    .font(palette.ui(12.5, .medium, relativeTo: .footnote))
                    .foregroundStyle(palette.inkText(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    // **The reachable half of re-ordering.** The rows are
                    // draggable — see ``ColumnRowGrip`` — and a drag is not a
                    // control: it cannot be reached by keyboard, VoiceOver
                    // cannot offer it, and Switch Control cannot perform it. So
                    // the pair stays. It is also the only route while a row is
                    // open, which is exactly when somebody is deciding where the
                    // column they are editing belongs.
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

    /// The column's WIP limit — see ``BoardColumn/limit``.
    ///
    /// **A toggle and a stepper, because that is what the one other optional
    /// number in this app already is:** `SavedViewEditor` sets a view's card cap
    /// with exactly this pair. Two spellings of "an `Int?` the user chooses"
    /// would be two controls to learn for one idea, and a text field would need
    /// its own answer to what a half-typed `1` on its way to `13` means.
    ///
    /// Written straight to the store rather than into a draft, the way the
    /// colour well above it is. There is nothing to type here, so there is no
    /// half-finished state that a commit-on-close would be protecting.
    ///
    /// **The Done column gets one too.** It is unusual to limit finished work
    /// and it is not this pane's business to say so: a board whose last column
    /// is Ready to Ship is a board where a cap means something, and the limit
    /// is advisory everywhere, so the worst an odd one can do is colour a pill.
    @ViewBuilder private func columnLimit(_ column: BoardColumn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { column.limit != nil },
                // **Switched on, it starts at what the column already holds.**
                // Any fixed default would put most columns straight over a
                // limit the user has not chosen yet — a warning colour arriving
                // as the result of turning the feature on, which reads as
                // having broken something. Starting at the current count can
                // never produce `over`; narrowing it from there is a decision
                // somebody makes on purpose.
                set: { on in
                    let count = store.visibleTasks(in: column.id).count
                    store.setColumnLimit(on ? max(count, 1) : nil, on: column.id)
                }
            )) {
                Text("Limit work in progress")
                    .font(palette.ui(13, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink(0.7))
            }
            .toggleStyle(.switch)

            if let limit = column.limit {
                ThemedStepper(
                    value: Binding(
                        get: { limit },
                        set: { store.setColumnLimit($0, on: column.id) }
                    ),
                    range: BoardStore.columnLimitRange,
                    name: String(localized: "Limit",
                                 comment: "Accessibility name of the stepper setting a column's WIP limit"),
                    hit: metrics.hit
                ) {
                    Text(String(localized: "At most \(limit) at a time",
                                comment: "How many cards a column is meant to hold at once — its WIP limit"))
                        .font(palette.ui(13, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(palette.ink(0.7))
                        .monospacedDigit()
                }
            }
        }
    }

    private func columnField(_ title: LocalizedStringKey, text: Binding<String>, focus target: ColumnField) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .body))
                .foregroundStyle(palette.ink)
                .focused($columnFocus, equals: target)
                // **Next on the composer's name, Done on everything else.** A
                // Return that made the column would step over a field the user
                // can see directly underneath the caret, and a keyboard that
                // says "done" while there is a filled-in field below it is
                // saying the wrong thing. The composer's Short is the end of
                // the chain and makes the column.
                .submitLabel(target == .new ? .next : .done)
                .onSubmit {
                    switch target {
                    case .new: columnFocus = .newShort
                    case .newShort: addColumn()
                    case .name, .short:
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
                    target.isShort
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
                .font(palette.ui(metrics.rowFont, .bold, relativeTo: .body))
                .foregroundStyle(palette.ink(isEnabled ? 0.6 : 0.22))
                .frame(minWidth: metrics.hit, minHeight: metrics.hit)
                .background(palette.ink(0.06), in: .rect(cornerRadius: 10))
        }
        .bareButton()
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
                .font(palette.ui(13.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(destructiveTone.foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: metrics.hit)
                .background(destructiveTone.background, in: .rect(cornerRadius: 10))
        }
        .bareButton()
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
                    .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .body))
                    .foregroundStyle(palette.inkText(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .frame(minHeight: metrics.hit)
                    .contentShape(.rect)
            }
            .bareButton()
        }
    }

    private var addColumnComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            columnShape(
                name: $newColumnName, nameFocus: .new,
                short: $newColumnShort, shortFocus: .newShort,
                dot: newColumnDot, setDot: { newColumnDot = $0 }
            )
            HStack(spacing: 8) {
                // The height belongs inside the label. Hung on the `Button`
                // instead it framed the control and not its shape, and
                // `.bareButton()` hands the shape straight to the label —
                // so the target published was the 47.3×19.3 of the word, in a
                // sheet where every other control clears 44.
                Button { cancelAddColumn() } label: {
                    Text("Cancel")
                        .font(palette.ui(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.inkText(0.55))
                        .padding(.horizontal, 14)
                        .frame(minHeight: metrics.hit)
                        .contentShape(.rect)
                }
                .bareButton()
                Spacer(minLength: 0)
                Button { addColumn() } label: {
                    Text("Add Column")
                        .font(palette.ui(14, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: metrics.hit)
                        .background(palette.accent, in: .rect(cornerRadius: 10))
                }
                .bareButton()
            }
        }
        .padding(12)
        .background(palette.ink(0.045), in: .rect(cornerRadius: metrics.radius))
        .id(Self.composerAnchor)
        // The composer opens to be typed into, so its Name field takes the
        // caret — on both routes in: the "+ Add column" row above, and a sheet
        // that arrived with `addsColumn` already asked for. Hung on the
        // composer rather than set where `isAddingColumn` flips, because the
        // field is not in the tree yet at either of those moments — the
        // assignment this app has watched fail three times over — see
        // `focusWhenReady`.
        .focusWhenReady($columnFocus, .new)
    }

    /// **Name, Short and Colour — the whole of what a column is**, in the one
    /// arrangement both the composer and a column's own editor draw them in.
    ///
    /// One function rather than two layouts, because they are the same three
    /// controls a moment apart: the composer is the column, and the editor is
    /// the column once it exists. Two arrangements is two places for them to
    /// drift, and this file has been through that once already — see
    /// `renameColumn(_:to:short:)`, which exists because the phone could rename
    /// a column and nothing could rename its abbreviation.
    ///
    /// **One row where there is width for it, two where there is not**, and the
    /// fallback is measured rather than a taste. All three stacked, the composer
    /// stands near 300pt; a landscape phone leaves 184 between the sheet's
    /// header and the top of the software keyboard, and the controls below the
    /// caret go under it — the same failure the four role segments used to cause
    /// here, which is why they had to sit *above* the name field rather than
    /// below it. A landscape phone is the one surface with no height and plenty
    /// of width, so it is the one that gets the single row; the fields keep a
    /// floor of ``Metrics/nameFloor`` so "fits" cannot mean a name field
    /// squeezed to nothing.
    private func columnShape(
        name: Binding<String>, nameFocus: ColumnField,
        short: Binding<String>, shortFocus: ColumnField,
        dot: SwatchColor, setDot: @escaping (SwatchColor) -> Void
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                columnFields(name: name, nameFocus: nameFocus, short: short, shortFocus: shortFocus)
                columnColour(dot: dot, fillsTheRow: false, setDot: setDot)
            }
            VStack(alignment: .leading, spacing: 14) {
                columnFields(name: name, nameFocus: nameFocus, short: short, shortFocus: shortFocus)
                columnColour(dot: dot, fillsTheRow: true, setDot: setDot)
            }
        }
    }

    /// Name and Short, side by side on every surface: an abbreviation is a word
    /// rather than a sentence, so it is the half that takes a fixed width.
    ///
    /// Nothing else edits the abbreviation, and `MoveToPicker` is what draws it —
    /// without this a column renamed on the phone went on calling itself by the
    /// old name in the only control the phone has for moving a card.
    ///
    /// **Empty Short is an answer**: `addColumn` falls back to the full name,
    /// and `renameColumn` keeps the one the column has. The placeholder stays
    /// the word "Short" rather than echoing the name to say so — measured,
    /// "Code Review" in a 96pt field renders as "Code Reviev", and a control
    /// that looks broken while explaining itself has explained nothing.
    private func columnFields(
        name: Binding<String>, nameFocus: ColumnField,
        short: Binding<String>, shortFocus: ColumnField
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            columnField("Name", text: name, focus: nameFocus)
                .frame(minWidth: Metrics.nameFloor)
            columnField("Short", text: short, focus: shortFocus)
                .frame(width: metrics.shortWidth)
        }
    }

    /// The swatches. `setDot` is the difference between the two callers rather
    /// than a second control: the editor recolours the column as it is pressed,
    /// and the composer holds the pick on a value until Add Column is, because
    /// there is no column to recolour yet.
    ///
    /// `fillsTheRow` is whether the button takes the width it is given or the
    /// ``Metrics/colourWidth`` it needs: stacked under the fields it runs the
    /// width of them, and beside them it takes its own share.
    private func columnColour(
        dot: SwatchColor, fillsTheRow: Bool, setDot: @escaping (SwatchColor) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Colour").sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
            ColorWell(selection: dot, metrics: metrics.colorWell) { setDot($0) }
                .frame(maxWidth: fillsTheRow ? .infinity : metrics.colourWidth)
        }
        .frame(maxWidth: fillsTheRow ? .infinity : metrics.colourWidth, alignment: .leading)
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
        guard store.addColumn(named: newColumnName, short: newColumnShort, dot: newColumnDot) != nil
        else { return }
        cancelAddColumn()
    }

    private func cancelAddColumn() {
        newColumnName = ""
        newColumnShort = ""
        newColumnDot = BoardColumn.defaultDot
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

    /// **It asks now, because the answer changed.** This used to go straight
    /// through, on the grounds that the act was undoable and that the line under
    /// the button already said the one thing worth warning about — that the
    /// cards were staying. They are not staying any more: the board takes every
    /// card on it, which is the largest amount of work any one press in this app
    /// can move, and a press that big is one to be asked about rather than one
    /// to be explained after the fact. See ``BoardTrashWarning``, which puts the
    /// number in the title.
    private var deleteRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(role: .destructive) {
                boardWarning = BoardTrashWarning(
                    board: boardID,
                    name: board?.name ?? "",
                    tasks: store.cardCount(onBoard: boardID)
                )
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "trash")
                    Text("Trash Board")
                }
                .font(palette.ui(14.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(destructiveTone.foreground)
                .frame(maxWidth: .infinity)
                .frame(minHeight: metrics.hit + 4)
                .background(destructiveTone.background, in: .rect(cornerRadius: 14))
            }
            .bareButton()

            Text("Its tasks go with it and can be restored with it for 30 days.")
                .font(palette.ui(12.5, .medium, relativeTo: .footnote))
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

/// The drag half of re-ordering a column in the settings sheet.
///
/// A `ViewModifier` rather than a ternary because `.draggable` takes a payload
/// and not an optional one — `DraggableWhenOrdered` is the same shape for the
/// same reason. The payload is built when the *session* starts rather than when
/// the row is drawn, which is what keeps the column's name on it current after a
/// rename in the row above.
private struct ColumnRowGrip: ViewModifier {
    let isEnabled: Bool
    let payload: () -> ColumnTransfer

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(payload())
        } else {
            content
        }
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

/// What trashing a *board* would cost, held while the alert asks.
///
/// **The count is in the title.** Trashing a board takes everything on it now —
/// see `BoardStore.deleteBoard` — so the one fact that decides the answer is how
/// much work is on it, and a person dismissing a dialog reads the title and not
/// always the line under it. "Trash “Northwind iOS 3.0” and its 24 tasks?" is a
/// question somebody can answer from the title alone; "Trash this board?" is one
/// they can only answer by remembering what was on it.
///
/// The numbers are taken when the button is pressed rather than read again in
/// the alert, for ``ColumnTrashWarning``'s reason: what the user agrees to is
/// what they were shown, and a sync can land under a presented alert.
///
/// A shared type rather than one per surface: the sheet and the phone's drawer
/// both ask this question, and two spellings of one warning is how two surfaces
/// start promising different things about the same act.
struct BoardTrashWarning: Identifiable, Equatable {
    var board: Board.ID
    var name: String
    /// Archived cards included — `deleteBoard` takes those too. See
    /// ``BoardStore/cardCount(onBoard:)``, which is deliberately not the
    /// sidebar's count.
    var tasks: Int

    var id: Board.ID { board }

    var title: String {
        guard tasks > 0 else {
            return String(
                localized: "Trash “\(name)”?",
                comment: "Alert title before an empty board is thrown away; the placeholder is the board's name"
            )
        }
        return String(
            localized: "Trash “\(name)” and its \(tasks) tasks?",
            comment: "Alert title before a board is thrown away; the placeholders are the board's name and how many tasks are on it"
        )
    }

    /// Two facts: that the cards go *with* the board rather than being left
    /// loose, and that the whole lot comes back together. An empty board has no
    /// cards to say anything about and says only the second.
    var detail: String {
        let recovery = String(
            localized: "The board goes to the Trash, where it can be restored for thirty days.",
            comment: "Alert body explaining that a trashed board can be restored"
        )
        guard tasks > 0 else { return recovery }
        let taken = String(
            localized: "Its \(tasks) tasks go with it, archived ones included, and come back with it if you restore it.",
            comment: "Alert body: how many tasks a trashed board takes with it and that restoring returns them"
        )
        return taken + " " + recovery
    }
}

