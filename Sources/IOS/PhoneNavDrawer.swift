#if os(iOS)

import SwiftUI

/// The slide-over board list. The design specifies a drawer at 84% width with a
/// scrim, so this stays a custom overlay rather than a navigation split view.
struct PhoneNavDrawer: View {
    /// How much of the screen the panel takes — the design's 84%. Shared rather
    /// than spelled here alone, because a finger dragging the drawer in has to
    /// know how far it has to come before it is all the way in.
    static let widthFraction: CGFloat = 0.84

    /// How wide the panel is drawn: 84% of the screen's **short edge**, not of
    /// whatever is beside it.
    ///
    /// It used to be 84% of the container, which is the same number in portrait
    /// and a different surface entirely on its side: an iPhone in landscape is
    /// 956pt across, and 84% of that is 803pt of board list over 150pt of board.
    /// The short edge does not change when the phone is turned, so neither does
    /// the drawer — it is 370pt on a Pro Max and 315 on an SE, held either way
    /// up. Nothing here is a fixed maximum, because the number that must not be
    /// exceeded is that phone's own portrait width and no other.
    ///
    /// The container is still in the sum, and last rather than first: a screen
    /// that has not been measured yet leaves it as the only answer available,
    /// which is what this was before there was a screen to ask.
    static func width(in container: CGFloat, screen: CGSize) -> CGFloat {
        let edges = [container, screen.width, screen.height].filter { $0 > 0 }
        return (edges.min() ?? container) * widthFraction
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var isManagingLabels = false
    @State private var isCreatingBoard = false
    /// The board whose editor is open. A snapshot only names which one — the
    /// editor reads the board back out of the store, so a rename inside it does
    /// not leave the sheet holding the old one.
    @AccessibilityFocusState private var isTitleFocused: Bool

    /// How far in the drawer is: 0 shut, 1 open.
    ///
    /// **1 everywhere except under a finger.** The hamburger, the edge-swipe's
    /// own settle and every row that closes the drawer leave this alone and let
    /// `.transition(.move(edge: .leading))` do the sliding — one animation,
    /// written once. A pan in flight is the other case: it is not an animation
    /// at all but a position, arriving a frame at a time, and a transition
    /// running alongside it would be a second opinion about where the panel is.
    /// See `PhoneRootView.drawerPan`.
    var progress: CGFloat = 1

    /// The window, both dimensions of it, so ``width(in:screen:)`` can take the
    /// short one. Measured by `PhoneRootView` rather than here: it is on screen
    /// long before the drawer is, so the panel never draws a frame at a width it
    /// is about to correct, and the pan that drags the drawer in has to arrive
    /// at the same number anyway.
    var screen: CGSize = .zero

    var body: some View {
        ZStack(alignment: .leading) {
            // The scrim darkens as the panel comes in, so a drag half-way in is
            // half-way to hiding the board rather than a panel floating over an
            // untouched one. `scrim` rather than `ink`: see `Palette.scrim`.
            palette.scrim(progress)
                .ignoresSafeArea()
                .onTapGesture { store.isNavDrawerOpen = false }
                .transition(.opacity)
                // The scrim is the drawer's own ground, not a control: without
                // this it reads as an unlabelled element between the panel and
                // the board it is hiding.
                .accessibilityHidden(true)

            panel
                .containerRelativeFrame(.horizontal) { width, _ in
                    Self.width(in: width, screen: screen)
                }
                // `visualEffect` rather than `.offset`, for the width: the panel
                // is the only thing that knows how wide 84% turned out to be,
                // and this is where it can be asked without a `GeometryReader`
                // around the drawer or the number being computed twice. At
                // `progress == 1` the shift is zero, so every non-interactive
                // way in is left to the transition below, untouched.
                .visualEffect { content, proxy in
                    content.offset(x: parked(by: proxy.size.width))
                }
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
        .newBoardAlert(isPresented: $isCreatingBoard) { _ in
            // A new board is the one the user is now on, and the drawer is over
            // it. The prompt has already dismissed itself by the time this runs,
            // so taking the drawer down with it is safe.
            store.isNavDrawerOpen = false
        }
    }

    /// How far out of sight the panel is drawn, in points, in whichever
    /// direction "out" is: `.offset` is a raw coordinate and does not mirror
    /// itself, the same trap the panel's shadow falls into below.
    private func parked(by width: CGFloat) -> CGFloat {
        let hidden = (1 - progress) * width
        return layoutDirection == .rightToLeft ? hidden : -hidden
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

            // **Reminders used to be a section of its own down here**, opening
            // a sheet with the switch and the time of day on it. It was a
            // preference in a list of *places* — every other row in this drawer
            // goes somewhere the user's work is — and it was the second copy of
            // a pane Settings already had, with two of Settings' four switches
            // missing from it. Settings ▸ Notifications is the whole of it now,
            // and `settingsRow` below is the way there.
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

    /// One of the phone's two ways into Settings — the header's ⋯ menu has the
    /// other, and neither is a duplicate of a *destination* the way the menu's
    /// old board and view items were: this is a panel of preferences, reached
    /// from wherever the hand already is. macOS gets ⌘, and the `Settings` scene
    /// for free, and everything behind this row (export, import, the backups,
    /// the reset) would otherwise be unreachable here.
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
            Button { store.boardSettings = BoardSettingsRequest(board: board.id) } label: {
                Label("Board Settings…", systemImage: "slider.horizontal.3")
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
