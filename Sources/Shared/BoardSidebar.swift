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
/// its own count, reordered by dragging one — the whole row at a pointer, the
/// grip at its trailing end under a finger; see ``boardDropZones(for:)`` — or
/// from its context menu, and renamed, recoloured and deleted through the
/// Board Settings that menu opens. A card can be dragged onto any of them.
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
        /// The slot every row symbol is drawn in, so a column of them lines up
        /// on one edge whatever each glyph measures — a calendar is half again
        /// as wide as a sun, and left to themselves the labels stagger.
        var rowGlyph: CGFloat
        /// The reorder grip at the trailing end of every board row: the glyph
        /// as drawn, the square it claims, and how much of that claim it hands
        /// straight back — ``ChecklistView/Metrics``'s trio, for this list. A
        /// `gripHit` of 0 is no grip at all: the desk's rows are dragged whole,
        /// the way a column is by its header, because a pointer needs no handle
        /// — and a handle is the one thing a finger *does* need, since the row
        /// under it already spends its long press on the context menu.
        var gripGlyph: CGFloat
        var gripHit: CGFloat
        var gripOverhang: CGFloat
        /// What a row that has become a text field claims — see ``FieldHitArea``.
        var fieldHit: CGFloat
        var sectionSpacing: CGFloat
        var labelManager: LabelManagerView.Metrics
        /// The Trash, which hangs off its row under Views in a popover — so the
        /// iPad's copy is at `.sheet`'s touch sizes even though it is not a
        /// sheet.
        var trash: TrashView.Metrics
        /// Which side of the Trash row that popover hangs off, or `nil` to let
        /// the system place it — ``BoardColumnView/ColumnEditorMetrics/arrowEdge``
        /// exactly, and for the same measured reason.
        ///
        /// The desk names the trailing edge, which is where the board is. The
        /// iPad names none: asked for `.trailing` there, UIKit put the box
        /// *over* the source list and hard against the left edge of the screen
        /// — 380pt starting at x = 10 on a 1032pt window, with no arrow in
        /// sight. Left to choose, it hangs off the row's trailing edge pointing
        /// back at it, which is what was asked for in the first place.
        var trashArrowEdge: Edge?
        /// Whether the pane paints its own ground and its own seam.
        ///
        /// **The desk's does; the iPad's cannot.** On macOS this view *is* the
        /// column: it runs the height of the window, so a wash and a hairline
        /// hung on it cover the column exactly. On iPad it sits inside a
        /// `ScrollView` — the list is taller than a landscape iPad mini once
        /// every row claims its 44pt — and inside one it is only ever as tall
        /// as its rows. The wash stopped under the last row and the hairline
        /// stopped with it, which is the reported bug: a band of column under
        /// the list in a paler colour, with no line down the side of it. The
        /// paler was the tell — the scroll view was washing the whole column
        /// from behind, so the list had the wash twice and the band once.
        ///
        /// Both belong to the scroll view there, which is the one thing in that
        /// column that is the column's height — see ``PadRootView/sidebar``. A
        /// flag rather than a `nil` colour because it is two decisions taken
        /// together: a ground with no seam is as wrong as a seam with no
        /// ground, and nothing should be able to take one without the other.
        var paintsItsOwnGround: Bool

        /// Whether the board rows carry the grip, said as the question the
        /// call sites ask rather than as a second flag that could disagree
        /// with the width.
        var reordersByGrip: Bool { gripHit > 0 }

        /// The gap between rows, named because the boards' drop zones are
        /// measured against it — ``ChecklistView/Metrics/rowGap``'s reason.
        /// One number on both surfaces, so a static rather than a field.
        static let rowGap: CGFloat = 2
        /// How far each board row's drop halves spill past it: half the gap, so
        /// the two rows either side of one tile it exactly and a pointer
        /// between two rows is over one of them rather than over neither.
        static var dropReach: CGFloat { rowGap / 2 }

        static let desk = Metrics(
            width: 232, trafficLightInset: 16, rowFont: 13, rowVerticalPadding: 7,
            rowRadius: 9, rowHit: 0, rowGlyph: 14,
            gripGlyph: 0, gripHit: 0, gripOverhang: 0,
            fieldHit: 0, sectionSpacing: 22,
            labelManager: .desk, trash: .desk, trashArrowEdge: .trailing,
            paintsItsOwnGround: true
        )
        static let pad = Metrics(
            width: nil, trafficLightInset: 0, rowFont: 15, rowVerticalPadding: 10,
            rowRadius: 11, rowHit: 44, rowGlyph: 17,
            gripGlyph: 14, gripHit: 44, gripOverhang: 7,
            fieldHit: 44, sectionSpacing: 24,
            labelManager: .sheet, trash: .sheet, trashArrowEdge: nil,
            paintsItsOwnGround: false
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
    /// The view the editor is open on, if any. A box rather than the id alone
    /// because `sheet(item:)` wants something `Identifiable`, and tracking the
    /// view rather than a flag beside it is what lets the sheet close itself
    /// when the view stops existing — `capture`'s arrangement, for its reason.
    @State private var editing: SavedViewDraft?
    /// The row a card is being dragged over. Local rather than the store's
    /// `dropTargetColumnID`: neither of these is a column.
    @State private var dropTarget: DropTarget?
    /// The board that has left the ground, and the gap the drop is aimed at —
    /// the settings sheet's `draggingColumnID`/`columnCaret` pair, for this
    /// list. Surface state rather than the store's, for the checklist's
    /// reason: what is being carried is a fact about this sidebar, and the
    /// desk can have a second window with a sidebar of its own.
    @State private var draggingBoardID: Board.ID?
    @State private var boardCaret: BoardCaret?
    /// Every lift is numbered, and every deferred answer carries its number —
    /// see ``ChecklistView``'s `lifts`, which is where the arrangement is
    /// explained: it is what stops a signal belonging to one drag from landing
    /// on the next.
    @State private var boardLifts = 0
    /// Which board the current run of payload asks belongs to — a latch that
    /// outlives the drag by a beat, for the one build whose drag session does
    /// not announce itself. See ``lifted(_:)``.
    @State private var liftedBoardID: Board.ID?
    /// The same four, for the rows under **Views** — separate state rather
    /// than one shared set because the two lists never share a drag, and a
    /// caret in one is meaningless against rows in the other.
    @State private var draggingViewID: SavedView.ID?
    @State private var viewCaret: SavedViewCaret?
    @State private var viewLifts = 0
    @State private var liftedViewID: SavedView.ID?
    /// The card the capture popover is filling in. Local rather than the
    /// store's: it is which popover is open, not anything about the board, and
    /// `BoardStore` already holds one surface's worth of that too many.
    @State private var capture: Capture?

    private var managingLabels: Binding<Bool> { isManagingLabels ?? $ownManagingLabels }

    /// A 232pt column of rows whose type grows — see ``ChromeScale``. Capped
    /// lower than the board's columns: the source list takes its width off the
    /// board rather than off a scroller.
    private var chrome = ChromeScale()

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
            VStack(spacing: Metrics.rowGap) {
                ForEach(Array(store.boards.enumerated()), id: \.element.id) { index, board in
                    boardRow(board, index: index)
                }
                newBoardRow
            }
            .padding(.horizontal, 8)

            sectionHeader("Views", topPadding: metrics.sectionSpacing)
            VStack(spacing: Metrics.rowGap) {
                // The board's own list rather than a fixed seven: since v11 a
                // view is a row in the file, so the order here is the user's and
                // the last row is the way to add another.
                ForEach(store.views) { viewRow($0) }
                newViewRow
            }
            .padding(.horizontal, 8)

            // **Manage**, not Labels, because the section is no longer one row
            // about one thing. What it holds is the app's own furniture — the
            // board's labels, the Trash, and on iPad the settings — rather than
            // anywhere a card is filed. The Trash was the last row under
            // **Views** and is the reason the heading had to change: a place
            // things are thrown away to is not a view of the board, and it read
            // as one sitting under five filters.
            sectionHeader("Manage", topPadding: metrics.sectionSpacing)
            VStack(spacing: 2) {
                labelsRow
                trashRow
                settingsRow
            }
            .padding(.horizontal, 8)

            // The rows sit at the top of the column; the footer sits at the
            // foot of it, under everything it is not one of.
            Spacer(minLength: 0)
            footer
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: chrome.scaling(metrics.width, cap: 1.4))
        // Drawn here only where this view is the column — see
        // ``Metrics/paintsItsOwnGround``. Where it is not, the two are the
        // scroll view's, so that they are the column's height rather than the
        // list's. `.clear` rather than a branch: the pane's shape should not
        // depend on which surface is drawing it.
        .background(metrics.paintsItsOwnGround ? palette.panelOverlay : .clear)
        .hairline(.trailing, color: metrics.paintsItsOwnGround ? palette.ink(0.07) : .clear)
        .labelManagerSheet(isPresented: managingLabels, metrics: metrics.labelManager)
        .sheet(item: $editing) { draft in
            SavedViewEditor(viewID: draft.id)
                .environment(store)
                .environment(\.palette, palette)
        }
        // File ▸ New Board, which does exactly what this list's own row does —
        // makes the board and opens its settings on the empty name field. The
        // menu asks the row rather than calling the store itself so there is one
        // answer to "what does making a board do".
        //
        // `task(id:)` rather than `onChange` because the menu can ask while the
        // sidebar is hidden: showing it again runs this on the way in.
        .task(id: isNamingNewBoard?.wrappedValue ?? false) {
            guard isNamingNewBoard?.wrappedValue == true else { return }
            isNamingNewBoard?.wrappedValue = false
            createBoard()
        }
    }

    // MARK: Destinations

    private func boardRow(_ board: Board, index: Int) -> some View {
        let isActive = store.surface == .board && store.activeBoardID == board.id
        // Hoisted: the count is a pass over every task, and the row used to ask
        // twice — once for the pill and once for the accessibility value.
        let count = store.taskCount(for: board.id)

        return HStack(spacing: 0) {
            Button { store.selectBoard(board.id) } label: {
                destinationRow(symbol: board.symbol, count: count, isActive: isActive) {
                    rowName(board.name, isActive: isActive)
                }
            }
            .buttonStyle(.bare)
            // Name and count stated separately — see `BoardToolbar`. Substituted
            // rather than named, now that the row has a symbol in it: an `Image`
            // among siblings inside a button's label is published as an element of
            // its own whatever else is asked of it, which is `viewRow`'s reason and
            // was the dot's too, drawn as a `Circle` that published nothing. The
            // representation keeps the row's own action, so the context menu — the
            // only route Board Settings has to a reader — is still on the button
            // underneath it.
            .accessibilityRepresentation {
                Button(board.name) { store.selectBoard(board.id) }
                    .accessibilityValue(Text(verbatim: "\(count)"))
                    .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
            // On the button, and pointedly not on the grip beside it — the
            // checklist's arrangement, for its measured reason: a long press on
            // the grip is how a drag begins on touch, and a menu on the whole
            // row would come up over the drag that was starting.
            .contextMenu { boardMenu(board, index: index) }

            if metrics.reordersByGrip { grip(for: board) }
        }
        // The active wash, the hover and the card drag's ring are the row's
        // rather than the button's since the grip arrived, so all three span
        // the handle instead of stopping short of the trailing edge.
        .background(isActive ? palette.accentSoft : .clear, in: .rect(cornerRadius: metrics.rowRadius))
        .overlay {
            if isDropTarget(.board(board.id)) {
                RoundedRectangle(cornerRadius: metrics.rowRadius)
                    .strokeBorder(palette.accent, lineWidth: 2)
            }
        }
        .hoverBackground(isActive ? .clear : palette.ink(0.05), radius: metrics.rowRadius)
        // The desk's drag, where there is no grip because the whole row is one
        // — see ``grip(for:)`` for why touch cannot make the same trade.
        .modifier(WholeRowDrag(
            isEnabled: !metrics.reordersByGrip,
            payload: { lifted(board) },
            begin: { beginBoardLift(board.id) },
            end: endBoardLift
        ))
        .dropDestination(for: TaskTransfer.self) { items, _ in
            guard store.allowsCardDrag, let dropped = items.first, store[dropped.id] != nil
            else { return false }
            store.file(dropped.id, onto: board.id)
            return true
        } isTargeted: { targeted in
            // A lift is not a drag until a destination has seen it, and where
            // the system never says the drag is over, every destination letting
            // go at once is what does — see `BoardStore.dragTargeting`.
            store.dragTargeting(targeted)
            setDropTarget(.board(board.id), targeted: targeted)
        }
        // Where a dragged board would land, drawn in the gap it would land in
        // rather than on a row it would not.
        .overlay { boardDropZones(for: board) }
        .overlay(alignment: caretEdge(for: board) ?? .top) { caretMark(for: board) }
    }

    /// Settings, and where the board sits in the list. The rows drag now —
    /// whole at a pointer, by the grip under a finger — and the Move Up / Move
    /// Down pair is the same answer said in words, kept because a drag is not
    /// a control: it cannot be reached by keyboard, VoiceOver cannot offer it,
    /// and Switch Control cannot perform it. The settings sheet's columns make
    /// exactly this pair of trades.
    ///
    /// **Rename, Board Colour and Trash Board used to be here**, and left the
    /// way the phone's **Rename Board…** went: the sheet holds the name, the
    /// colour, every column and the delete, so an item here is a second door to
    /// a room the first item already opens. What is left is the two the sheet
    /// does *not* hold — a board's place among the others is a fact about the
    /// list rather than about the board, and there is nothing in a board's own
    /// settings for it to be a field of.
    ///
    /// Renaming still has a fast path where a board's name is actually on
    /// screen — the title in `BoardToolbar` is editable in place. Deleting
    /// deliberately has none: it is the one act here that takes a board away
    /// from under the pointer, and it now takes every card on it as well. The
    /// sheet's version asks first and counts them — see ``BoardTrashWarning`` —
    /// which is the whole of why it is worth the extra press.
    @ViewBuilder
    private func boardMenu(_ board: Board, index: Int) -> some View {
        // **Everything a board is**, which is more than this menu can hold: its
        // columns' names, abbreviations, colours and order used to be reachable
        // only one column at a time, through a popover hanging off a column
        // header that is not on screen while another board is. See
        // ``BoardSettingsView``.
        Button { store.boardSettings = BoardSettingsRequest(board: board.id) } label: {
            Label("Board Settings…", systemImage: "slider.horizontal.3")
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
    }

    /// **It makes the board and opens its settings**, rather than turning into
    /// a text field where it stands.
    ///
    /// A name was all the row could ask for, and a name is the least of what a
    /// new board needs: it arrives holding its Done column and nothing else, so
    /// the next thing to do is always say what its columns are — which is the
    /// sheet, not this row. Opening it there puts the name field and the column
    /// composer on one surface, in the order they are wanted, and the board on
    /// screen behind is already the new one.
    ///
    /// The field arrives focused and empty even though the board is called
    /// ``Board/defaultName`` by then; see ``BoardSettingsRequest/namesNewBoard``.
    private var newBoardRow: some View {
        Group {
            Button(action: createBoard) {
                // The plus stands in the glyph slot the boards' own marks use,
                // so the column of symbols above it does not step sideways at
                // the last row — see ``destinationRow(symbol:count:isActive:isDropTarget:name:)``.
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(palette.ui(9, .bold, relativeTo: .caption2))
                        .frame(width: metrics.rowGlyph)
                        .accessibilityHidden(true)
                    Text("New board", comment: "Sidebar row that starts a board")
                        .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
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
                    createBoard()
                }
            }
        }
    }

    private func createBoard() {
        guard let id = store.createBoard(named: Board.defaultName) else { return }
        store.boardSettings = BoardSettingsRequest(board: id, namesNewBoard: true)
    }

    /// Every row selects its view, and selecting the active one again comes
    /// back to the board — the same thing the list header's "Board" button
    /// does, so a user who reached a view from here can leave it from here.
    ///
    /// The count is the view's own membership rather than what the list is
    /// currently showing: it is deliberately not narrowed by the search, which
    /// would make the badge report the query instead of the view.
    ///
    /// The symbol is `SavedView.symbol` — the same glyph the view's empty state
    /// and the phone's drawer already drew, so a row and the surface it opens
    /// carry one mark rather than each picking their own. The boards above wear
    /// one too since v16: both say what the destination is *for*, and both are
    /// the user's to change, picked from the same browser. What keeps the two
    /// sections apart is what each picker *opens* on — see
    /// ``Board/startingSymbols`` and ``SavedView/startingSymbols``, which share
    /// no glyph — and the section headings they sit under.
    private func viewRow(_ view: SavedView) -> some View {
        let isActive = store.activeView?.id == view.id
        let count = store.count(of: view, today: dayClock.today)

        return HStack(spacing: 0) {
            Button {
                // **Not a toggle.** Pressing the row of the view you are already
                // on used to send you back to the board, which is a second
                // meaning for one control and the wrong one: a destination row
                // means "go here", and a row that undoes itself is a row you
                // cannot press twice. The store's `surface` already refuses a
                // no-op assignment, so arriving where you are costs nothing.
                store.selectSurface(.view(view.id))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: view.symbol)
                        .imageScale(.small)
                        // Dimmer than the label it stands beside, the way the
                        // two rows under Labels already are, so the column of
                        // glyphs does not read as loud as the words. The active
                        // row takes the accent whole rather than half.
                        .foregroundStyle(isActive ? palette.accent : palette.inkText(0.5))
                        .frame(width: metrics.rowGlyph)
                        .accessibilityHidden(true)
                    Text(view.label)
                        .font(palette.ui(metrics.rowFont, isActive ? .bold : .semibold, relativeTo: .subheadline))
                        .foregroundStyle(isActive ? palette.accent : palette.ink(0.66))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CountPill(count: count)
                }
                .padding(.vertical, metrics.rowVerticalPadding)
                .padding(.horizontal, 10)
                .frame(minHeight: metrics.rowHit)
                .contentShape(.rect)
            }
            .buttonStyle(.bare)
            // Substituted rather than named, now that the row has a symbol in
            // it: an `Image` among siblings inside a button's label is
            // published as an element of its own whatever else is asked of it,
            // `accessibilityHidden` included — the same reason the two rows
            // under Labels are substituted. The name, the count as the value
            // and the trait are all as they were.
            .accessibilityRepresentation {
                Button(view.label) {
                    store.selectSurface(.view(view.id))
                }
                    .accessibilityValue(Text(verbatim: "\(count)"))
                    .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
            // On the button, and pointedly not on the grip beside it — see
            // `boardRow`, whose arrangement this whole row is: a long press on
            // the grip is how a drag begins on touch, and a menu on the whole
            // row would come up over the drag that was starting.
            .contextMenu { viewMenu(view) }

            if metrics.reordersByGrip { grip(for: view) }
        }
        // The active wash and the hover span the handle, `boardRow`'s reason.
        .background(isActive ? palette.accentSoft : .clear, in: .rect(cornerRadius: metrics.rowRadius))
        .hoverBackground(isActive ? .clear : palette.ink(0.05), radius: metrics.rowRadius)
        // The desk's drag, where there is no grip because the whole row is one.
        .modifier(WholeRowDrag(
            isEnabled: !metrics.reordersByGrip,
            payload: { lifted(view) },
            begin: { beginViewLift(view.id) },
            end: endViewLift
        ))
        // Where a dragged view would land, drawn in the gap it would land in
        // rather than on a row it would not.
        .overlay { viewDropZones(for: view) }
        .overlay(alignment: caretEdge(for: view) ?? .top) { caretMark(for: view) }
    }

    /// What can be done to a view without opening it. The board rows have had
    /// the same menu since boards became data, and a view is data now too —
    /// down to the Move pair, which is the drag said in words and the only
    /// route VoiceOver, Switch Control and a keyboard have to it.
    ///
    /// **Delete asks nothing**, unlike a board's. A board holds work and a view
    /// holds a rule, so the worst a mistaken delete costs is the rule — which is
    /// one ⌘Z away, and for a seeded view is also one press of **Restore
    /// Built-in Views** away.
    @ViewBuilder private func viewMenu(_ view: SavedView) -> some View {
        Button { editing = SavedViewDraft(view) } label: {
            Label("Edit View…", systemImage: "slider.horizontal.3")
        }
        Button { editing = store.duplicateView(view.id).map(SavedViewDraft.init) } label: {
            Label("Duplicate View", systemImage: "plus.square.on.square")
        }
        // Looked up here rather than passed in, the way the drawer's board
        // rows do: the views' `ForEach` iterates the list without offsets, and
        // a menu is built on demand, so the index is fresh by construction.
        if let index = store.views.firstIndex(where: { $0.id == view.id }) {
            Divider()
            Button {
                store.moveView(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
            } label: {
                Label("Move Up", systemImage: "arrow.up")
            }
            .disabled(index == 0)
            Button {
                store.moveView(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
            } label: {
                Label("Move Down", systemImage: "arrow.down")
            }
            .disabled(index == store.views.count - 1)
        }
        Divider()
        Button(role: .destructive) { store.deleteView(view.id) } label: {
            Label("Delete View", systemImage: "trash")
        }
        // Only where something is actually missing, so the menu does not carry
        // a permanently dead row on the installs that never deleted anything.
        if store.isMissingSeededViews {
            Divider()
            Button { store.restoreSeededViews() } label: {
                Label("Restore Built-in Views", systemImage: "arrow.uturn.backward")
            }
        }
    }

    /// The way to make one, under the list it joins — where **New board** sits
    /// under the boards, and for the same reason: the row that adds to a list
    /// belongs at the end of it rather than in a toolbar the list has not got.
    ///
    /// It opens the editor on a view that already exists rather than on a draft
    /// of one. A view made and then abandoned is a row the user can delete; a
    /// draft that has to be committed is a second kind of thing, and the
    /// editor would need a cancel that means *undo the creation* on one path
    /// and *undo the edits* on the other.
    private var newViewRow: some View {
        Button { editing = SavedViewDraft(store.addView()) } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .imageScale(.small)
                    .foregroundStyle(palette.inkText(0.45))
                    .frame(width: metrics.rowGlyph)
                    .accessibilityHidden(true)
                Text("New view")
                    .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.inkText(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, metrics.rowVerticalPadding)
            .padding(.horizontal, 10)
            .frame(minHeight: metrics.rowHit)
            .hoverBackground(palette.ink(0.05), radius: metrics.rowRadius)
        }
        .buttonStyle(.bare)
        .accessibilityRepresentation {
            Button(String(localized: "New view",
                          comment: "Accessibility name of the sidebar row that creates a saved view")) {
                editing = SavedViewDraft(store.addView())
            }
        }
    }

    /// Renaming, recolouring and deleting a label are board-wide edits, so they
    /// hang off the board's own list rather than off any one task's chips.
    /// Settings ▸ Labels opens the same view from its own row.
    ///
    /// **Named for what it is rather than for what pressing it does**, like
    /// every other row in this list: the boards are not "Open board" and the
    /// Archive is not "Show archive". It said *Manage labels* while it stood
    /// under a heading that said Labels, which spent the word twice and the
    /// heading now spends on something else.
    private var labelsRow: some View {
        Button { managingLabels.wrappedValue = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .imageScale(.small)
                    .foregroundStyle(palette.inkText(0.5))
                    .frame(width: metrics.rowGlyph)
                    .accessibilityHidden(true)
                Text("Labels")
                    .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
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
            Button(String(localized: "Labels",
                          comment: "Accessibility name of the sidebar row that opens the label manager")) {
                managingLabels.wrappedValue = true
            }
                .accessibilityValue(Text(verbatim: "\(store.labels.count)"))
        }
    }

    /// **On every platform**, which it was not: the row was `#if os(iOS)` on
    /// the reasoning that ⌘, and the app menu are the desk's door and a second
    /// one would be a duplicate. That is true of the *key* and not of the list:
    /// this section is where the app's own furniture is kept, and a Manage
    /// section that holds the labels and the Trash on all three platforms and
    /// the settings on two is a list that reads differently depending on which
    /// machine you are sitting at. The menu keeps ⌘, ; this is the row.
    ///
    /// `SettingsLink` rather than a flag, because the desk's Settings is a
    /// *scene*: `store.isShowingSettings` raises the sheet the phone and the
    /// iPad use and does nothing at all on macOS, where the window is opened by
    /// the system.
    private var settingsRow: some View {
        Group {
            #if os(macOS)
            SettingsLink { settingsRowLabel }
            #else
            Button { store.isShowingSettings = true } label: { settingsRowLabel }
            #endif
        }
        .buttonStyle(.bare)
        .accessibilityRepresentation {
            // A `SettingsLink` is a button whose action belongs to the system,
            // so the substitute carries the name and leaves the press to it —
            // on iOS the flag is the whole of the action and is set here.
            #if os(macOS)
            SettingsLink {
                Text("Settings", comment: "Accessibility name of the sidebar row that opens Settings")
            }
            #else
            Button(String(localized: "Settings",
                          comment: "Accessibility name of the sidebar row that opens Settings")) {
                store.isShowingSettings = true
            }
            #endif
        }
    }

    /// Drawn once for both, so the two doors cannot drift apart in a row that
    /// is the same row on either platform.
    private var settingsRowLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape")
                .imageScale(.small)
                .foregroundStyle(palette.inkText(0.5))
                .frame(width: metrics.rowGlyph)
                .accessibilityHidden(true)
            Text("Settings")
                .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink(0.66))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, metrics.rowVerticalPadding)
        .padding(.horizontal, 10)
        .frame(minHeight: metrics.rowHit)
        .hoverBackground(palette.ink(0.05), radius: metrics.rowRadius)
    }

    // MARK: The foot of the list

    /// The bottom of the column: quick capture, and nothing else.
    ///
    /// The one thing here that is not a row and does not belong in the list, put
    /// where a window's own furniture goes. Capture is the desk's alone — the
    /// iPad's toolbar carries a `+` of its own — so on that platform there is
    /// nothing left to put at the foot and the whole strip goes with it. The bin
    /// that used to stand at the other end is a row under **Manage** now; see
    /// ``trashRow``.
    @ViewBuilder private var footer: some View {
        #if os(macOS)
        HStack(spacing: 8) {
            captureButton
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        #endif
    }

    // MARK: The Trash

    /// The way into the Trash on both pointer surfaces: a row under **Manage**,
    /// beneath the labels.
    ///
    /// **A row rather than the bin it was.** The bin was a glyph in the corner —
    /// the shape the Finder, Mail and Photos give it — and the corner is where a
    /// thing goes when there is nowhere in the list it belongs.
    ///
    /// It spent a while under **Views**, beneath the Archive, on the reading
    /// that work leaves the board two ways — filed or thrown away — and the two
    /// rows that reach them belong together. The Archive holds cards and answers
    /// to the same predicates the filters above it do; the Trash holds columns
    /// and whole boards as well, and nothing in it is *on* the board at all. So
    /// it sits with the app's own furniture instead, and took the heading with
    /// it.
    ///
    /// **It still says whether there is anything in it before it is opened**, and
    /// says it the way every row in this list does — a count in the pill, where
    /// the Archive's is. The glyph fills while the trash holds something, which
    /// is the one thing the bin said that a count does not.
    ///
    /// Not a ``SavedView``, and it cannot be one: the views are predicates over
    /// the board's cards, and the Trash holds columns and whole boards as well —
    /// see ``TrashedItem/Contents``. So the row is built here rather than by
    /// ``viewRow(_:)``, in the shape its neighbours share.
    ///
    /// The popover hangs off the trailing edge, where the board is — but only
    /// on the desk, which is the one platform that has to be told; see
    /// ``Metrics/trashArrowEdge``.
    private var trashRow: some View {
        @Bindable var store = store
        let count = store.trashCount
        let isOpen = store.isShowingTrash

        return Button { store.isShowingTrash = true } label: {
            HStack(spacing: 8) {
                Image(systemName: count > 0 ? "trash.fill" : "trash")
                    .imageScale(.small)
                    .foregroundStyle(isOpen ? palette.accent : palette.inkText(0.5))
                    .frame(width: metrics.rowGlyph)
                    .accessibilityHidden(true)
                Text("Trash")
                    .font(palette.ui(metrics.rowFont, isOpen ? .bold : .semibold, relativeTo: .subheadline))
                    .foregroundStyle(isOpen ? palette.accent : palette.ink(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
                CountPill(count: count)
            }
            .padding(.vertical, metrics.rowVerticalPadding)
            .padding(.horizontal, 10)
            .frame(minHeight: metrics.rowHit)
            .background(isOpen ? palette.accentSoft : .clear, in: .rect(cornerRadius: metrics.rowRadius))
            .hoverBackground(isOpen ? .clear : palette.ink(0.05), radius: metrics.rowRadius)
        }
        .buttonStyle(.bare)
        .help("Show the Trash")
        // Substituted rather than named, for `viewRow`'s reason: an `Image`
        // among siblings inside a button's label is published as an element of
        // its own whatever else is asked of it, `accessibilityHidden` included,
        // and the row would read "Trash" and then "trash.fill" from Apple's
        // catalogue.
        .accessibilityRepresentation {
            Button(String(localized: "Trash",
                          comment: "Accessibility name of the sidebar row that opens the Trash")) {
                store.isShowingTrash = true
            }
                .accessibilityValue(Text(verbatim: "\(count)"))
                .accessibilityAddTraits(isOpen ? [.isSelected] : [])
        }
        .accessibilityIdentifier(Self.trashButtonID)
        .popover(isPresented: $store.isShowingTrash, arrowEdge: metrics.trashArrowEdge) {
            trashPopover
        }
    }

    /// The identifier the Trash row carries, spelled once here rather than in
    /// this source and a test's string literal both — the arrangement
    /// ``BoardToolbar/inboxToggleID`` and `SettingsTab.chipID` have.
    /// `UITests/TrashSurfaceTests` drives the phone's door, which is a menu item
    /// rather than this.
    static let trashButtonID = "Sidebar.trash"

    /// The Trash itself, at a width of its own.
    ///
    /// A popover sizes itself to its content, and this content is a list that is
    /// empty on most days and thirty items long on one of them — so the scroll
    /// is capped rather than fixed. `TrashView` is short when the trash is
    /// empty and the box is short with it; past the cap the box stops growing
    /// and the list scrolls inside it.
    private var trashPopover: some View {
        ScrollView {
            TrashView(metrics: metrics.trash)
                .padding(14)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: chrome(Self.trashPopoverWidth, cap: 1.3))
        .frame(maxHeight: Self.trashPopoverHeight)
        .environment(store)
        .environment(\.palette, palette)
    }

    private static let trashPopoverWidth: CGFloat = 380
    private static let trashPopoverHeight: CGFloat = 460

    // MARK: Capture

    /// The `+` and the tray at the foot of the list, at a point size of their
    /// own: a shade under the pill's 44 × 0.45 because this button carries the
    /// heavier weight of the three — `.semibold` against the iPad's `.medium` —
    /// and a heavier glyph at the same size draws bigger.
    private static let captureGlyph: CGFloat = 19

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
    /// wants touch metrics and a width of its own, and the iPad's toolbar
    /// carries capture itself — the same pill, at the right of the bar. See
    /// ``BoardToolbar/captureButton``.
    ///
    /// **A `+` and a tray, in a capsule.** The glyph pair is
    /// ``CaptureGlyphs``, shared with the other two surfaces: the `+` is the
    /// verb and the tray is where the card lands, which on this button was the
    /// half nothing on screen said. Room it has — the foot of the list is
    /// otherwise empty, and 200pt of source list sit under a 67pt pill.
    @ViewBuilder private var captureButton: some View {
        #if os(macOS)
        Button { capture = Capture(id: store.captureToInbox()) } label: {
            CaptureGlyphs(size: Self.captureGlyph, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(palette.onAccent)
                // The one control in the list that is a target rather than a
                // row, so it takes a shape of its own rather than the row
                // height — and grows with the type inside it like the rest.
                //
                // 44 is where it stops shrinking: the touch minimum, which is
                // not this surface's rule — the desk is the only place this is
                // drawn — but is a floor worth landing on rather than passing
                // through, and the glyphs keep their share of the pill. Only
                // the width moved when the disc became a capsule; this is the
                // same 44pt band of the foot it always was.
                .frame(width: chrome(CaptureGlyphs.width(Self.captureGlyph)), height: chrome(44))
                .background(palette.accent, in: .capsule)
                .shadow(color: palette.shadow(0.2), radius: 5, y: 2)
        }
        .buttonStyle(.bare)
        .help("Capture a task in the Inbox")
        .accessibilityLabel("Capture a task")
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
    /// be `$capture`: a capture nothing was filled into has to be dropped
    /// again, and SwiftUI reports that dismissal by writing `nil` here and
    /// nowhere else.
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

    /// Closes the popover, and takes the card with it when every control in it
    /// is still as capture left it — see `BoardStore.discardIfBlank`, which is
    /// what decides. Pressing ✕ and clicking away are the same act and land
    /// here alike.
    private func endCapture() {
        if let capture { store.discardIfBlank(capture.id) }
        capture = nil
    }

    // MARK: Row furniture

    /// The shape every destination shares: a mark, a name and a count. The
    /// name is a view rather than a string so the row that names a new board
    /// can put its field exactly where a name will be.
    ///
    /// The active row's ground, the hover and the card drag's ring are
    /// `boardRow`'s rather than this label's, since the grip arrived: they
    /// have to span the handle, which stands beside the button this draws.
    ///
    /// The glyph sits in ``Metrics/rowGlyph``'s slot, which is the one the
    /// views' rows use, so the two sections line their labels up on one edge
    /// however wide each mark measures.
    private func destinationRow(
        symbol: String, count: Int?, isActive: Bool,
        @ViewBuilder name: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: SymbolMark.resolved(symbol))
                .imageScale(.small)
                // Dimmer than the label it stands beside, exactly as the views'
                // rows are; the active row takes the accent whole.
                .foregroundStyle(isActive ? palette.accent : palette.inkText(0.5))
                .frame(width: metrics.rowGlyph)
                .accessibilityHidden(true)
            name()
                .frame(maxWidth: .infinity, alignment: .leading)
            if let count {
                Text("\(count)")
                    .font(palette.ui(11, .bold, relativeTo: .caption2))
                    .opacity(isActive ? 0.7 : 0.5)
            }
        }
        .foregroundStyle(isActive ? palette.accent : palette.ink(0.66))
        .padding(.vertical, metrics.rowVerticalPadding)
        .padding(.horizontal, 10)
        .frame(minHeight: metrics.rowHit)
        .contentShape(.rect)
    }

    private func rowName(_ text: String, isActive: Bool) -> some View {
        Text(text)
            .font(palette.ui(metrics.rowFont, isActive ? .bold : .semibold, relativeTo: .subheadline))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: Re-ordering by drag

    /// **The grip**, at the trailing end of a board or view row — the touch
    /// surfaces' way to lift one, in the place a list's reorder handle belongs
    /// and where the checklist's rows already keep theirs.
    ///
    /// A control of its own rather than the row, for the checklist's measured
    /// reason: on touch a drag begins with a long press, and the row's long
    /// press is spent on its context menu — one gesture cannot mean both. The
    /// desk has no such conflict (its menu is a right-click), so it has no
    /// grip and drags the whole row; see ``WholeRowDrag``.
    ///
    /// Hidden from accessibility because a drag is not something VoiceOver or
    /// Switch Control can perform: what they get is Move Up / Move Down in the
    /// row's context menu, which is why those stay.
    ///
    /// `draggable` takes its payload as an autoclosure, so `lifted` runs when
    /// the *session* starts and not when the row is drawn — which keeps the
    /// name on the payload current after a rename.
    private func grip(for board: Board) -> some View {
        gripGlyph
            .draggable(lifted(board))
            .modifier(RowDragSession(
                begin: { beginBoardLift(board.id) },
                end: endBoardLift
            ))
            .accessibilityHidden(true)
    }

    /// The same handle for a row under **Views**, differing only in what it
    /// picks up and which session it reports to.
    private func grip(for view: SavedView) -> some View {
        gripGlyph
            .draggable(lifted(view))
            .modifier(RowDragSession(
                begin: { beginViewLift(view.id) },
                end: endViewLift
            ))
            .accessibilityHidden(true)
    }

    /// The grip as drawn, shared by both lists' rows.
    private var gripGlyph: some View {
        Image(systemName: "line.3.horizontal")
            .font(palette.ui(metrics.gripGlyph, .semibold, relativeTo: .caption2))
            .foregroundStyle(palette.inkText(0.32))
            .frame(width: metrics.gripHit, height: metrics.gripHit)
            // An image's own shape is the glyph, which on touch is a target
            // the width of three thin lines. The square is what is aimed at.
            .contentShape(.rect)
            .padding(-metrics.gripOverhang)
    }

    /// The payload — and, where there is no better signal, the lift as well.
    ///
    /// Where the drag session announces itself it is the authority — see
    /// ``RowDragSession``, and ``BoardStore/announcesDragEnd`` for which
    /// builds have it. Only iOS 26 has nothing else to go on, and only there
    /// does the latch below run: the payload is asked for more than once per
    /// drag, and keeps being asked through the drop, so the asks are
    /// de-duplicated against ``liftedBoardID`` — the checklist's arrangement,
    /// explained at length on its `lifted(_:)`.
    private func lifted(_ board: Board) -> BoardRowTransfer {
        if !BoardStore.announcesDragEnd {
            let id = board.id
            // Deferred a turn, because the ask lands inside a view update and
            // this writes the state the list is drawn from.
            Task { @MainActor in
                guard liftedBoardID != id else { return }
                beginBoardLift(id)
            }
        }
        return BoardRowTransfer(board)
    }

    /// A board has left the ground, and the number of the lift that says so.
    /// The expiry is the last resort for a drag that ends without anything
    /// saying so — `BoardSettingsView.liftColumn`'s backstop, at its cost: a
    /// row of zones that outlive a cancelled drag, and nothing more.
    @discardableResult
    private func beginBoardLift(_ id: Board.ID) -> Int {
        boardLifts += 1
        liftedBoardID = id
        draggingBoardID = id
        boardCaret = nil
        let lift = boardLifts
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(BoardStore.liftExpiry))
            if boardLifts == lift, draggingBoardID == id { endBoardDrag() }
        }
        return lift
    }

    /// The end of the drag numbered `lift`, from the session that began it —
    /// refused when a later lift owns the screen, because a session's closing
    /// callbacks can arrive after the *next* drag has started.
    private func endBoardLift(_ lift: Int) {
        guard lift == boardLifts else { return }
        endBoardDrag()
    }

    private func endBoardDrag() {
        draggingBoardID = nil
        boardCaret = nil
        releaseBoardLatch()
    }

    /// Opens ``liftedBoardID`` again, a beat after the drag it belonged to
    /// ended — long enough to outlast the trailing payload asks a drop shakes
    /// loose, and well inside the half second the next long press takes. Only
    /// the no-callback path consults the latch, but it is released on every
    /// path; see the checklist's `releaseLatch`, which this is.
    private func releaseBoardLatch() {
        guard let id = liftedBoardID else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.latchSettle))
            if liftedBoardID == id { liftedBoardID = nil }
        }
    }

    private static let latchSettle: TimeInterval = 0.25

    /// The view rows' copies of the four functions above, told apart only by
    /// which list's state they write — the boards' carry the notes.

    private func lifted(_ view: SavedView) -> SavedViewTransfer {
        if !BoardStore.announcesDragEnd {
            let id = view.id
            Task { @MainActor in
                guard liftedViewID != id else { return }
                beginViewLift(id)
            }
        }
        return SavedViewTransfer(view)
    }

    @discardableResult
    private func beginViewLift(_ id: SavedView.ID) -> Int {
        viewLifts += 1
        liftedViewID = id
        draggingViewID = id
        viewCaret = nil
        let lift = viewLifts
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(BoardStore.liftExpiry))
            if viewLifts == lift, draggingViewID == id { endViewDrag() }
        }
        return lift
    }

    private func endViewLift(_ lift: Int) {
        guard lift == viewLifts else { return }
        endViewDrag()
    }

    private func endViewDrag() {
        draggingViewID = nil
        viewCaret = nil
        releaseViewLatch()
    }

    private func releaseViewLatch() {
        guard let id = liftedViewID else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.latchSettle))
            if liftedViewID == id { liftedViewID = nil }
        }
    }

    /// The row's two halves, as separate insertion targets: the top half means
    /// *above this board*, the bottom half means *below it*. The settings
    /// sheet's columns, the checklist's rows and the board's cards all do the
    /// same, and the notes there are the notes here — halves because a drop
    /// that names a *row* can only mean a gap by guessing which way the drag
    /// came from, and only while a board is in the air because otherwise they
    /// take the click that selects one and the card drops the row underneath
    /// is waiting for.
    ///
    /// Both halves on every row, the last included: the board list has no
    /// pinned Done row, so below the bottom board is a gap like any other.
    @ViewBuilder private func boardDropZones(for board: Board) -> some View {
        if draggingBoardID != nil {
            VStack(spacing: 0) {
                boardDropZone(.above(board.id))
                boardDropZone(.below(board.id))
            }
            .padding(.vertical, -Metrics.dropReach)
        }
    }

    private func boardDropZone(_ caret: BoardCaret) -> some View {
        Color.clear
            .contentShape(.rect)
            .dropDestination(for: BoardRowTransfer.self) { items, _ in
                defer { endBoardDrag() }
                guard let dropped = items.first else { return false }
                return store.dropBoard(dropped, at: caret)
            } isTargeted: { targeted in
                // Cleared only by the half that set it: leaving one for the
                // next fires this one's `false` after the other's `true`, and
                // an unguarded clear would take the new target down with it.
                if targeted {
                    boardCaret = caret
                } else if boardCaret == caret {
                    boardCaret = nil
                }
            }
    }

    /// Which edge of this row the mark goes on, or `nil` for no mark.
    ///
    /// Nothing against the row in the air — it is about to leave, and a line
    /// on a row that is going says nothing about where anything lands — and
    /// nothing against the two gaps it already sits between, which is
    /// `dropBoard` refusing a move to where the board already is, read back.
    private func caretEdge(for board: Board) -> Alignment? {
        guard let boardCaret, boardCaret.board == board.id,
              let dragging = draggingBoardID, dragging != board.id,
              let from = store.boards.firstIndex(where: { $0.id == dragging }),
              let anchor = store.boards.firstIndex(where: { $0.id == board.id })
        else { return nil }
        switch boardCaret {
        case .above: return anchor == from + 1 ? nil : .top
        case .below: return anchor == from - 1 ? nil : .bottom
        }
    }

    /// The insertion point: the line that says *here*, in the gap the board
    /// would land in — the same mark the settings sheet's columns draw, drawn
    /// against the row it names rather than floating in the gap, because an
    /// overlay knows its row's bounds and not the list's spacing.
    @ViewBuilder private func caretMark(for board: Board) -> some View {
        if caretEdge(for: board) != nil { caretCapsule }
    }

    /// The zones and the caret for a row under **Views** — the boards' pair
    /// above, over the other list. Note what these do *not* need: a view row
    /// takes no card drops, so unlike a board's there is nothing underneath
    /// for the zones to be kept out of the way of — only the click.
    @ViewBuilder private func viewDropZones(for view: SavedView) -> some View {
        if draggingViewID != nil {
            VStack(spacing: 0) {
                viewDropZone(.above(view.id))
                viewDropZone(.below(view.id))
            }
            .padding(.vertical, -Metrics.dropReach)
        }
    }

    private func viewDropZone(_ caret: SavedViewCaret) -> some View {
        Color.clear
            .contentShape(.rect)
            .dropDestination(for: SavedViewTransfer.self) { items, _ in
                defer { endViewDrag() }
                guard let dropped = items.first else { return false }
                return store.dropView(dropped, at: caret)
            } isTargeted: { targeted in
                // Cleared only by the half that set it — see `boardDropZone`.
                if targeted {
                    viewCaret = caret
                } else if viewCaret == caret {
                    viewCaret = nil
                }
            }
    }

    private func caretEdge(for view: SavedView) -> Alignment? {
        guard let viewCaret, viewCaret.view == view.id,
              let dragging = draggingViewID, dragging != view.id,
              let from = store.views.firstIndex(where: { $0.id == dragging }),
              let anchor = store.views.firstIndex(where: { $0.id == view.id })
        else { return nil }
        switch viewCaret {
        case .above: return anchor == from + 1 ? nil : .top
        case .below: return anchor == from - 1 ? nil : .bottom
        }
    }

    @ViewBuilder private func caretMark(for view: SavedView) -> some View {
        if caretEdge(for: view) != nil { caretCapsule }
    }

    /// The mark itself, one drawing for both lists.
    private var caretCapsule: some View {
        Capsule()
            .fill(palette.accent)
            .frame(height: 3)
            .padding(.horizontal, 1)
            // A mark, not a target: without this it is a hole in the row
            // it is drawn on, and the drop under it goes nowhere.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

/// The desk's half of re-ordering a board or a view: the whole row is the
/// grip, the way a column is dragged by its header, because a pointer needs
/// no handle and its context menu is a right-click rather than the long press
/// a drag starts with.
///
/// A `ViewModifier` rather than a ternary because `.draggable` takes a payload
/// and not an optional one — `ColumnRowGrip` is the same shape for the same
/// reason. Generic over the payload because the two lists lift different
/// things and nothing else about the drag differs. The payload is built when
/// the *session* starts rather than when the row is drawn, which keeps the
/// name on it current after a rename.
private struct WholeRowDrag<Payload: Transferable>: ViewModifier {
    let isEnabled: Bool
    let payload: () -> Payload
    /// Raises the lift and answers with its number.
    let begin: () -> Int
    /// Ends the lift of that number, if it is still the one in hand.
    let end: (Int) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .draggable(payload())
                .modifier(RowDragSession(begin: begin, end: end))
        } else {
            content
        }
    }
}

/// Where a board or view row's drag begins and ends, on the builds that say
/// so — ``ChecklistView``'s `SubtaskDragSession` for the sidebar's and the
/// drawer's rows, and the same shape for the same reason: `onDragSessionUpdated`
/// is macOS 26 but iOS **27**, so where it exists it is the exact answer, and
/// where it does not the lift is inferred from the payload ask and the end
/// from the drop and `BoardStore.liftExpiry`'s backstop.
///
/// **It carries the lift's number between the two**, which is what makes a
/// late closing callback harmless: the session hands back the number it was
/// given when it started, and the view ignores anything that does not belong
/// to the drag in hand.
///
/// Internal rather than private: the sidebar's rows and the phone drawer's
/// are separate surfaces with separate state, and this is the one piece the
/// two can share whole — `CardDragSession`'s arrangement. It knows nothing of
/// what is being dragged, so one type serves both lists.
struct RowDragSession: ViewModifier {
    /// Raises the lift and answers with its number.
    let begin: () -> Int
    /// Ends the lift of that number, if it is still the one in hand.
    let end: (Int) -> Void

    @State private var lift: Int?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        reporting(content)
        #else
        if #available(iOS 27.0, *) {
            reporting(content)
        } else {
            content
        }
        #endif
    }

    @available(iOS 27.0, macOS 26.0, *)
    private func reporting(_ content: Content) -> some View {
        content.onDragSessionUpdated { session in
            switch session.phase {
            case .initial:
                lift = begin()
            case .ended(let operation):
                // An operation that carries something is a drop, and the drop
                // handler is what clears up after it — running here as well
                // would shut the zones out from under a drop still landing.
                switch operation {
                case .copy, .move: break
                default: finish()
                }
            case .dataTransferCompleted:
                // The payload has been handed over. Almost always already
                // cleared by the drop handler; what is left for this to catch
                // is a drop that went through without moving the row.
                finish()
            default:
                break
            }
        }
    }

    /// Once per session, and only for a session this view actually started:
    /// the number is taken back on the way out so a second closing callback —
    /// and there are usually two — cannot be read as a second drag ending.
    private func finish() {
        guard let lift else { return }
        self.lift = nil
        end(lift)
    }
}
