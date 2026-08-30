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
/// its own count, reordered from its context menu and renamed, recoloured and
/// deleted through the Board Settings that menu opens. A card can be dragged
/// onto any of them.
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

        static let desk = Metrics(
            width: 232, trafficLightInset: 16, rowFont: 13, rowVerticalPadding: 7,
            rowRadius: 9, rowHit: 0, rowGlyph: 14, fieldHit: 0, sectionSpacing: 22,
            labelManager: .desk, trash: .desk, trashArrowEdge: .trailing
        )
        static let pad = Metrics(
            width: nil, trafficLightInset: 0, rowFont: 15, rowVerticalPadding: 10,
            rowRadius: 11, rowHit: 44, rowGlyph: 17, fieldHit: 44, sectionSpacing: 24,
            labelManager: .sheet, trash: .sheet, trashArrowEdge: nil
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
            VStack(spacing: 2) {
                ForEach(Array(store.boards.enumerated()), id: \.element.id) { index, board in
                    boardRow(board, index: index)
                }
                newBoardRow
            }
            .padding(.horizontal, 8)

            sectionHeader("Views", topPadding: metrics.sectionSpacing)
            VStack(spacing: 2) {
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
        .background(palette.panelOverlay)
        .hairline(.trailing, color: palette.ink(0.07))
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

        return Button { store.selectBoard(board.id) } label: {
            destinationRow(
                dot: board.dot, count: count,
                isActive: isActive, isDropTarget: isDropTarget(.board(board.id))
            ) {
                rowName(board.name, isActive: isActive)
            }
        }
        .buttonStyle(.bare)
        // Name and count stated separately — see `BoardToolbar`. Stated rather
        // than substituted, because the row's context menu is the only route
        // Board Settings has to a reader.
        .accessibilityLabel(board.name)
        .accessibilityValue(Text(verbatim: "\(count)"))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .contextMenu { boardMenu(board, index: index) }
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
    }

    /// Settings, and where the board sits in the list. Reordering is two menu
    /// items rather than a drag: the list is short, the rows are already
    /// carrying a drop destination for cards, and the two gestures would fight.
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
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(palette.ui(9, .bold, relativeTo: .caption2))
                        .frame(width: 7)
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
    /// carry one mark rather than each picking their own. The rows above this
    /// section wear a coloured dot instead, which is the truer split: a board's
    /// mark says *which* board and is the user's to change, while a view's says
    /// what the view is for and is the same on every install.
    private func viewRow(_ view: SavedView) -> some View {
        let isActive = store.activeView?.id == view.id
        let count = store.count(of: view, today: dayClock.today)

        return Button {
            // **Not a toggle.** Pressing the row of the view you are already on
            // used to send you back to the board, which is a second meaning for
            // one control and the wrong one: a destination row means "go here",
            // and a row that undoes itself is a row you cannot press twice. The
            // store's `surface` already refuses a no-op assignment, so arriving
            // where you are costs nothing.
            store.selectSurface(.view(view.id))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: view.symbol)
                    .imageScale(.small)
                    // Dimmer than the label it stands beside, the way the two
                    // rows under Labels already are, so the column of glyphs
                    // does not read as loud as the words. The active row takes
                    // the accent whole rather than half.
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
            .background(isActive ? palette.accentSoft : .clear, in: .rect(cornerRadius: metrics.rowRadius))
            .hoverBackground(isActive ? .clear : palette.ink(0.05), radius: metrics.rowRadius)
        }
        .buttonStyle(.bare)
        // Substituted rather than named, now that the row has a symbol in it:
        // an `Image` among siblings inside a button's label is published as an
        // element of its own whatever else is asked of it, `accessibilityHidden`
        // included — the same reason the two rows under Labels are substituted.
        // The name, the count as the value and the trait are all as they were.
        .accessibilityRepresentation {
            Button(view.label) {
                store.selectSurface(.view(view.id))
            }
                .accessibilityValue(Text(verbatim: "\(count)"))
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
        }
        .contextMenu { viewMenu(view) }
    }

    /// What can be done to a view without opening it. The board rows have had
    /// the same menu since boards became data, and a view is data now too.
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
    /// carries capture itself — a circle with a `+` in it, at the right of the
    /// bar. See ``BoardToolbar/captureButton``.
    @ViewBuilder private var captureButton: some View {
        #if os(macOS)
        Button { capture = Capture(id: store.captureToInbox()) } label: {
            Image(systemName: "plus")
                .symbolSize(19, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(palette.onAccent)
                // The one control in the list that is a target rather than a
                // row, so it takes a square of its own rather than the row
                // height — and grows with the type inside it like the rest.
                //
                // 44 is where it stops shrinking: the touch minimum, which is
                // not this surface's rule — the desk is the only place this is
                // drawn — but is a floor worth landing on rather than passing
                // through, and the glyph keeps its share of the disc.
                .frame(width: chrome(44), height: chrome(44))
                .background(palette.accent, in: .circle)
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

    /// The shape every destination shares: a dot, a name, a count, and the
    /// active row's ground. The name is a view rather than a string so the row
    /// that names a new board can put its field exactly where a name will be.
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
                    .font(palette.ui(11, .bold, relativeTo: .caption2))
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
            .font(palette.ui(metrics.rowFont, isActive ? .bold : .semibold, relativeTo: .subheadline))
            .lineLimit(1)
            .truncationMode(.tail)
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
