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
    /// The board a context menu's Trash Board has asked about, and what it would
    /// cost — see ``BoardTrashWarning``. A menu item cannot present an alert of
    /// its own, so the question is raised here, on the panel that hosts the row.
    @State private var boardWarning: BoardTrashWarning?
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
        // The drawer stays open behind it, the way the sheets above do: the
        // panel is what presents this, and the board being asked about is the
        // row the finger is still on.
        .alert(
            boardWarning?.title ?? "",
            isPresented: Binding(get: { boardWarning != nil }, set: { if !$0 { boardWarning = nil } }),
            presenting: boardWarning
        ) { warning in
            Button("Trash Board", role: .destructive) {
                boardWarning = nil
                store.trashBoard(warning.board)
            }
            Button("Cancel", role: .cancel) { boardWarning = nil }
        } message: { warning in
            Text(warning.detail)
        }
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

    /// One proxy for the two halves of the same fact.
    ///
    /// **The strip at the foot is the device's, and it was being paid for
    /// twice.** The drawer is an overlay, so its frame already stops at the
    /// safe area — 34pt above the glass on a home-indicator phone — and the
    /// panel then took another 34 of its own as a hand-written bottom padding.
    /// The ground never showed it, because that ignores the safe area and ran
    /// to the glass either way; what stopped short was the rows, 68pt up an
    /// 874pt screen, which reads as a list cut off rather than a short panel.
    ///
    /// So the panel reclaims the strip — the negative padding of
    /// ``HomeIndicatorFoot``, spelled here because the same number is wanted
    /// twice — and the scroll view hands it straight back as a content margin,
    /// so the rows *run* to the bottom of the screen while the last of them
    /// still comes to rest above the pill.
    private var panel: some View {
        GeometryReader { proxy in
            panelBody(homeIndicator: proxy.safeAreaInsets.bottom)
        }
    }

    private func panelBody(homeIndicator: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // The product's own name, read off the bundle and shown
                // verbatim: it is spelled the same in every language, and a
                // literal in a `Text` would have offered it to a translator.
                Text(verbatim: Self.wordmark)
                    .font(palette.display(26))
                    // Opening the drawer has to move the VoiceOver cursor into
                    // it. Landing on the heading rather than the first row is
                    // what lets the reader hear where they are before they hear
                    // what is on offer.
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
                Spacer(minLength: 0)
                Button { store.isNavDrawerOpen = false } label: {
                    Image(systemName: "xmark")
                        .font(palette.ui(12, .semibold, relativeTo: .footnote))
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
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .contentMargins(.bottom, 12 + homeIndicator, for: .scrollContent)
        }
        .padding(.top, 20)
        .padding(.bottom, -homeIndicator)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(palette.panelSolid)
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
            // The Inbox was the row above this one, and it went for the
            // reason it went from the desk's source list — see
            // `BoardSidebar`'s body. It is not a place instead of the board:
            // it is a sheet over whatever is on screen, raised and lowered by
            // ``PhoneTabBar``'s middle slot, which is on screen at all times
            // and is where a thumb already is. A row here was a second switch
            // for the same panel, in a drawer that has to be opened first —
            // and it was the one row in this list that did not go anywhere.
            sectionHeader("Boards", topPadding: 0)
            VStack(spacing: 2) {
                ForEach(store.boards) { boardRow($0) }
                newBoardRow
            }
            .padding(.horizontal, 12)

            sectionHeader("Views", topPadding: 24)
            VStack(spacing: 2) {
                // `store.views`, whole and unfiltered — the same rows in
                // the same order as the desk's source list and the menu bar's
                // submenu, because they are the same rows: the board file's
                // own list, which since v11 is the user's to order, rename and
                // delete. The seeded Inbox used to be dropped here, on the
                // argument that the row above the boards already went there;
                // that row is gone, and a surface that quietly holds a view
                // back reads as the board having lost one.
                ForEach(store.views) { viewRow($0) }
                newViewRow
            }
            .padding(.horizontal, 12)

            // **Manage**, and the same three rows in the same order as the
            // sidebar's: the phone's drawer and the desk's source list are the
            // same list of places, and a heading that said *Labels* over one row
            // while the other platforms said *Manage* over three was the drift
            // this section exists to end. What it holds is the app's own
            // furniture rather than anywhere a card is filed.
            sectionHeader("Manage", topPadding: 24)
            VStack(spacing: 0) {
                labelsRow
                trashRow
                settingsRow
            }
            .padding(.horizontal, 12)

            // **Reminders used to be a section of its own down here**, opening
            // a sheet with the switch and the time of day on it. It was a
            // preference in a list of *places* — every other row in this drawer
            // goes somewhere the user's work is — and it was the second copy of
            // a pane Settings already had, with two of Settings' four switches
            // missing from it. Settings ▸ Notifications is the whole of it now,
            // and the Settings row under **Manage** is the way there.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Renaming, recolouring and deleting a label are board-wide edits, so they
    /// hang off the board's own list rather than off any one task's chips —
    /// the same reasoning, and the same view, as the macOS sidebar's row.
    ///
    /// **Named for what it is rather than for what pressing it does**, like
    /// every other row in this drawer: the boards are not "Open board". It said
    /// *Manage labels* under a heading that said *Labels*, which spent the word
    /// twice; the heading spends it on the section now.
    private var labelsRow: some View {
        Button { isManagingLabels = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "tag")
                    .imageScale(.medium)
                    .foregroundStyle(palette.inkText(0.5))
                Text("Labels")
                    .font(palette.ui(15, .semibold, relativeTo: .body))
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
            Button(String(localized: "Labels",
                          comment: "Accessibility name of the drawer row that opens the label manager")) {
                isManagingLabels = true
            }
                .accessibilityValue(Text(verbatim: "\(store.labels.count)"))
        }
    }

    /// The Trash, which the header's ⋯ menu also carries. Two doors rather than
    /// one because they answer different questions — the menu is *what can I do
    /// here*, this list is *where can I go* — and because the drawer is the one
    /// place all three platforms put the same three rows.
    ///
    /// The drawer closes before the flag is set, for ``settingsRow``'s reason:
    /// the sheet is presented from the root, and one raised under an open
    /// overlay is a sheet nobody can touch.
    private var trashRow: some View {
        let count = store.trashCount

        return Button {
            store.isNavDrawerOpen = false
            store.isShowingTrash = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: count > 0 ? "trash.fill" : "trash")
                    .imageScale(.medium)
                    .foregroundStyle(palette.inkText(0.5))
                Text("Trash")
                    .font(palette.ui(15, .semibold, relativeTo: .body))
                    .foregroundStyle(palette.ink(0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
                CountPill(count: count, font: 12.5, horizontalPadding: 8)
            }
            .padding(12)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.bare)
        // Substituted for the reason every row with a symbol in it is: an
        // `Image` among siblings inside a button's label is published as an
        // element of its own whatever else is asked of it, so the row would
        // read "Trash" and then "trash.fill" from Apple's catalogue.
        .accessibilityRepresentation {
            Button(String(localized: "Trash",
                          comment: "Accessibility name of the drawer row that opens the Trash")) {
                store.isNavDrawerOpen = false
                store.isShowingTrash = true
            }
                .accessibilityValue(Text(verbatim: "\(count)"))
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
                    .font(palette.ui(15, .semibold, relativeTo: .body))
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

    /// A real board, with its own count and its own context menu. These were
    /// three literals with the counts 9 and 4 painted on (4.2).
    private func boardRow(_ board: Board) -> some View {
        destinationRow(
            name: board.name, symbol: board.symbol,
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
            Button(role: .destructive) {
                boardWarning = BoardTrashWarning(
                    board: board.id,
                    name: board.name,
                    tasks: store.cardCount(onBoard: board.id)
                )
            } label: {
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
                .font(palette.ui(15, .semibold, relativeTo: .body))
                .foregroundStyle(palette.inkText(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.bare)
    }

    /// Every board row. One function rather than a literal per row because it
    /// drew the Inbox too until that row went — and because the boards are
    /// `store.boards`, which is however many the user has made.
    ///
    /// The representation is `viewRow`'s, for `viewRow`'s reason and one more of
    /// its own: gathered, the count is read as part of the destination's *name*
    /// — "Backlog, 3" against the views' "Today" value "1", in the same list —
    /// and the name of a place then changes every time a card is added to it.
    private func destinationRow(
        name: String, symbol: String, count: Int, isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // The views' rows below draw their glyph at this size in this
                // slot; the boards' marks line up with them rather than sitting
                // where a 8pt dot used to.
                Image(systemName: SymbolMark.resolved(symbol))
                    .imageScale(.small)
                    .frame(width: 17)
                    .accessibilityHidden(true)
                Text(name)
                    .font(palette.ui(15, isActive ? .bold : .semibold, relativeTo: .body))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)")
                    .font(palette.ui(12.5, .bold, relativeTo: .caption))
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
    /// which is worse than showing nothing. Picking the view you are already on
    /// closes the drawer and changes nothing — see ``open(_:)``.
    private func viewRow(_ view: SavedView) -> some View {
        let isActive = store.activeView?.id == view.id
        // Hoisted: the count walks every task, the row asks twice — the pill
        // and the accessibility value — and the drawer redraws these rows on
        // every frame of the pull that opens it.
        let count = store.count(of: view, today: dayClock.today)
        return Button { open(view) } label: {
            HStack(spacing: 10) {
                Image(systemName: view.symbol)
                    .imageScale(.small)
                    .frame(width: 17)
                Text(view.label)
                    .font(palette.ui(15, isActive ? .bold : .semibold, relativeTo: .body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                CountPill(count: count, font: 12.5, horizontalPadding: 8)
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
                .accessibilityValue(Text(verbatim: "\(count)"))
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
        }
        .contextMenu { viewMenu(view) }
    }

    /// The same three the sidebar's rows carry. A long press, because the
    /// drawer's rows have no room for a trailing `…` and a tap already means
    /// *go there* — the board rows below make the same trade.
    @ViewBuilder private func viewMenu(_ view: SavedView) -> some View {
        Button { edit(view.id) } label: {
            Label("Edit View…", systemImage: "slider.horizontal.3")
        }
        Button {
            if let copy = store.duplicateView(view.id) { edit(copy.id) }
        } label: {
            Label("Duplicate View", systemImage: "plus.square.on.square")
        }
        Divider()
        Button(role: .destructive) { store.deleteView(view.id) } label: {
            Label("Delete View", systemImage: "trash")
        }
        if store.isMissingSeededViews {
            Divider()
            Button { store.restoreSeededViews() } label: {
                Label("Restore Built-in Views", systemImage: "arrow.uturn.backward")
            }
        }
    }

    /// The way to make one, under the list it joins — where the sidebar's own
    /// **New view** row sits, and where **New board** sits under the boards.
    private var newViewRow: some View {
        Button { edit(store.addView().id) } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .imageScale(.small)
                    .frame(width: 17)
                    .accessibilityHidden(true)
                Text("New view")
                    .font(palette.ui(15, .semibold, relativeTo: .subheadline))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(palette.inkText(0.55))
            .padding(12)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .accessibilityRepresentation {
            Button(String(localized: "New view",
                          comment: "Accessibility name of the drawer row that creates a saved view")) {
                edit(store.addView().id)
            }
        }
    }

    /// Names the view and gets out of the way. The drawer cannot present the
    /// sheet itself — it is about to close, and a sheet presented from a view
    /// leaving the tree goes with it — so `PhoneRootView` presents on the flag.
    /// See ``BoardStore/editingViewID``.
    private func edit(_ id: SavedView.ID) {
        store.editingViewID = id
        store.isNavDrawerOpen = false
    }

    /// The drawer covers the list it is changing, so a pick has to close it —
    /// otherwise the only feedback is a row highlight behind a scrim.
    ///
    /// **Picking the view you are already on does nothing but close the drawer.**
    /// It used to put the tab bar's own place back, which is the sidebar's old
    /// toggle by another name: a destination row means "go here", and one that
    /// undoes itself when pressed twice is a control with two meanings and no
    /// way to tell which you are about to get.
    private func open(_ view: SavedView) {
        store.activeView = view
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

    private func isActive(_ board: Board) -> Bool {
        store.activeView == nil && board.id == store.activeBoardID
    }
}

extension View {
    /// Makes a board and opens its settings on the empty name field, the moment
    /// `isPresented` goes true.
    ///
    /// **It used to be an alert asking for a name**, on the argument that a
    /// board *is* a name. It is not: it is a name and the columns work moves
    /// through, and a board arrives holding only its Done column — so the next
    /// thing to do after naming one is always to say what its columns are. The
    /// settings sheet holds both, in that order, and the desk's sidebar row does
    /// exactly this too.
    ///
    /// The binding stays rather than becoming a call, because the two callers
    /// are a drawer row and an empty state that also want to know it happened.
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

    func body(content: Content) -> some View {
        // `task(id:)` rather than `onChange` for `BoardSidebar`'s reason: the
        // asking surface can be going away in the same turn, and this has to run
        // on the way in either way.
        content.task(id: isPresented) {
            guard isPresented else { return }
            isPresented = false
            // `createBoard` moves to the board it made, so the caller only has
            // to say where to look afterwards.
            guard let id = store.createBoard(named: Board.defaultName) else { return }
            store.selectTab(.board)
            store.boardSettings = BoardSettingsRequest(board: id, namesNewBoard: true)
            onCreate(id)
        }
    }
}

#endif
