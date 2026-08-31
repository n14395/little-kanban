#if os(iOS)

import SwiftUI

/// Board title, drawer button and the board-actions menu, over whichever of the
/// second row's four bars the current surface calls for: the saved view that has
/// replaced the board, the search field, the column chips, and the notice that a
/// query is narrowing a list whose field is elsewhere.
struct PhoneHeader: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    /// The phone on its side has 402pt of height and the same chrome as 852pt
    /// of portrait, which left the columns a single card tall. Everything this
    /// gates is vertical space (5.5).
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// A strip that jumps to the current chip is motion like any other: the
    /// chip still has to be in view, it just arrives at once.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var isSearchFocused: Bool
    @State private var isManagingLabels = false
    /// Why the last Trash Column did not happen. A refusal has an explanation
    /// to show — from the outside, a menu item that does nothing is a bug, which
    /// is why `BoardColumnView` and ``BoardSettingsView`` both keep one too.
    @State private var refusal: ColumnRefusal?

    private var isShort: Bool { verticalSizeClass == .compact }

    /// Raises ``BoardSettingsView`` on the board that is on screen, optionally
    /// with one column already unfolded. The request goes on the store because
    /// the root presents the sheet — a menu can set a flag and cannot present
    /// anything, the same split the Trash makes.
    private func openBoardSettings(expanding column: BoardColumn.ID? = nil) {
        guard let id = store.activeBoardID else { return }
        store.boardSettings = BoardSettingsRequest(board: id, column: column)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isShort ? 9 : 16) {
            HStack(alignment: .bottom, spacing: 12) {
                Button { store.isNavDrawerOpen = true } label: {
                    hamburger
                }
                .buttonStyle(.bare)
                .accessibilityLabel("Show boards")

                titleLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(Self.titleID)
                    .accessibilityAddTraits(.isHeader)

                // The phone on its side puts the tab bar here, between the
                // title and the ⋯. Nowhere else on this shape is free: along
                // the foot it cost a third of the height, and up the leading
                // edge it cost the board 76pt of width — while this row is
                // already drawn, already 44pt tall, and holds one line of
                // serif with the whole middle of the screen after it. The
                // title takes what is left rather than the bar taking what
                // the title leaves, which is what `maxWidth: .infinity` above
                // already said.
                //
                // Portrait keeps the bar floating over the foot, where a thumb
                // reaches it — see ``PhoneTabBar`` and `PhoneRootView`.
                if isShort { PhoneTabBar(placement: .header) }

                boardMenu
            }

            // Search keeps its field wherever it is, including inside a saved
            // view: the query narrows the view, and the control that set it has
            // to stay reachable.
            if store.tab == .search {
                searchField
            } else if store.isColumnPaging, !isShort {
                // Dropped on a short screen, where two pages are side by side
                // under headings of their own: the chips would be a second
                // thing naming the same columns, and the one that costs a
                // card's worth of height to say it.
                columnChips
            }

            if store.showsMobileFilterNotice {
                filteredIndicator
            }
        }
        .padding(.horizontal, 20)
        .labelManagerSheet(isPresented: $isManagingLabels, metrics: .sheet)
    }

    /// What is on screen, named. The board's own name — this was the product
    /// name written out as a literal in four files (4.7) — except on a store
    /// with no boards left, which is a state deleting the last one reaches. The
    /// Inbox used to be the other exception, borrowing no board's name because
    /// it is on none; it is a panel over this header now rather than under it,
    /// and carries its own title.
    ///
    /// **Search is the exception that is left.** Its results come from every
    /// board and the Inbox alike (see `BoardStore.searchResults`), so the active
    /// board's name stood in the largest type on screen over a list that was
    /// mostly not from it — a title answering "where am I" with somewhere you
    /// are not. The word is ``PhoneTab/search``'s own, the one the slot that got
    /// you here is drawn with, rather than a second literal to keep in step with
    /// it. No glyph beside it, where a saved view has one: the field directly
    /// underneath opens with the same magnifier, and the pair a hand's width
    /// apart would be the strip the saved-view title replaced in miniature.
    ///
    /// A saved view still outranks it, as it does in `mobileTasks` — which is
    /// what ``BoardStore/isSearching`` says, and why `titleLabel` asks about the
    /// view first.
    private var title: String {
        if store.isSearching { return PhoneTab.search.label }
        return store.activeBoard?.name ?? String(
            localized: "No Board", comment: "Phone header title when every board has been deleted"
        )
    }

    /// **A saved view takes the title**, with its own symbol beside it. It was
    /// named in a strip under this row instead, which said the same thing twice
    /// — the title named the board you were *not* looking at, and the strip
    /// named the view you were — and carried a Back to Board button the drawer
    /// one thumb away already is. One title that answers "where am I" is the
    /// whole of what a title is for.
    ///
    /// One line for a view rather than the board's two: a view's name is short
    /// and fixed where a board's is the user's to make as long as they like.
    /// The one way a UI test can name this title. "Today" is a word the board
    /// under it also uses — a due chip says it — so a query by label picks
    /// whichever it reaches first. Shared through the source rather than by both
    /// ends spelling the same string, as `BoardToolbar.inboxToggleID` is.
    static let titleID = "PhoneHeaderTitle"

    @ViewBuilder
    private var titleLabel: some View {
        let size: CGFloat = isShort ? 22 : 30
        if let view = store.activeView {
            HStack(spacing: 8) {
                Image(systemName: view.symbol)
                    // Sized off the title rather than pinned to points, so the
                    // glyph grows with Dynamic Type alongside the words.
                    .font(palette.ui(size * 0.55, .semibold, relativeTo: .title3))
                    .foregroundStyle(palette.inkText(0.5))
                    .accessibilityHidden(true)
                Text(view.label)
                    .font(palette.display(size))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // One element rather than a hidden glyph beside a label: an `Image`
            // among siblings inside a container is published on its own whatever
            // `accessibilityHidden` says, which is the same trap the sidebar's
            // rows document.
            .accessibilityElement(children: .combine)
        } else {
            Text(title)
                .font(palette.display(size))
                .lineSpacing(2)
                .lineLimit(isShort ? 1 : 2)
        }
    }

    /// The board-level actions with no other home on the phone (4.4). This was a
    /// decorated `Image` — no action, no label, no target — beside a hamburger
    /// that has always been a real button.
    ///
    /// **What is *not* in here is the drawer's.** It carried a Switch Board item
    /// and the whole list of saved views, both of which the hamburger one thumb's
    /// width away draws in full — the boards with their marks and counts, the
    /// views with theirs, the Archive under them — so the menu was a second,
    /// shorter, worse copy of the panel beside it. It also carried Clear Search,
    /// which the search field's own × does and which the filtered indicator
    /// under this header does for the surfaces the field is not on: a filter is
    /// never invisible here, so there is always a control on screen that undoes
    /// it. Two sections are left, and each holds things that are reachable
    /// nowhere else.
    private var boardMenu: some View {
        Menu {
            // Everything that acts on the board that is on screen. The name is
            // changed in the settings sheet rather than on the title itself
            // (4.7): a serif line that turns into a field on a tap is a control
            // nothing on screen says is one — and the sheet holds the rest of
            // what a board is, its colour and its columns, which the phone
            // could otherwise reach only through the drawer.
            Section {
                // **The first row names the surface that is on screen.** On a
                // saved view it used to offer Board Settings — the settings of
                // the board standing *behind* the view, which is not what the
                // reader is looking at and not what they would expect the row
                // to change. A view has its own settings, and this is the
                // phone's only door to them other than the drawer: the sheet is
                // raised through ``BoardStore/editingViewID`` because a menu,
                // like the drawer, is gone by the time the sheet would open.
                if let view = store.activeView {
                    Button { store.editingViewID = view.id } label: {
                        Label("Edit View…", systemImage: "slider.horizontal.3")
                    }
                } else {
                    Button { openBoardSettings() } label: {
                        Label("Board Settings…", systemImage: "slider.horizontal.3")
                    }
                    .disabled(store.activeBoard == nil)
                }

                Button { store.archiveCompleted() } label: {
                    Label(
                        String(localized: "Archive \(store.completedCount) Completed",
                               comment: "Menu item that files every finished task on the active board away"),
                        systemImage: "archivebox"
                    )
                }
                .disabled(store.completedCount == 0)

                Button { isManagingLabels = true } label: {
                    Label("Manage Labels", systemImage: "tag")
                }
            } header: {
                Text("Board")
            }

            // And the two that are about the app rather than about this board:
            // the phone's door to the Trash, which used to be a tab of Settings
            // two surfaces away — see `BoardStore.isShowingTrash` for why it is
            // not a setting — and Settings itself, which until now was reachable
            // only by opening the drawer and scrolling to the foot of it.
            //
            // The trash count is in the title rather than beside it because a
            // menu row has nowhere to put a trailing anything, and "Trash" alone
            // makes opening it the only way to learn there is nothing in it.
            Section {
                Button { store.isShowingTrash = true } label: {
                    Label(trashTitle, systemImage: store.trashCount > 0 ? "trash.fill" : "trash")
                }

                Button { store.isShowingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(palette.ui(15, .extraBold, relativeTo: .subheadline))
                .foregroundStyle(palette.inkText(0.5))
                .frame(minWidth: 34, minHeight: 34)
                .background(palette.ink(0.06), in: .circle)
                // The disc stays at the design's 34pt and the target grows into
                // the space above it, the same trade the hamburger makes.
                .frame(minWidth: 44, minHeight: 44, alignment: .bottomTrailing)
                .contentShape(.rect)
                .padding(.bottom, 3)
                // A menu's label is hosted in a button of its own, and anything
                // inside it is published as a second element under this one —
                // here an `Image` named from Apple's catalogue, so the control
                // read "Board actions" and then "More". `viewRow`'s remedy is
                // not available to a menu: `accessibilityRepresentation`
                // substitutes the subtree and takes the menu with it. Hiding
                // the label is what leaves the menu whole and the extra element
                // out — measured, drawing the glyph as `Text` instead only
                // renames the extra element.
                .accessibilityHidden(true)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("Board actions")
    }

    /// "Trash", or "Trash (4)" while there is something in it.
    private var trashTitle: String {
        let count = store.trashCount
        guard count > 0 else {
            return String(localized: "Trash", comment: "Phone board menu item that opens the Trash")
        }
        return String(localized: "Trash (\(count))",
                      comment: "Phone board menu item that opens the Trash, with how much is in it")
    }


    /// A query narrowing a list whose field is on another tab. The rule is that
    /// a filter is never invisible (1.11), so where the field cannot be shown
    /// this says the filter exists and undoes it in one tap.
    private var filteredIndicator: some View {
        Button { store.clearQuery() } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease").imageScale(.small)
                Text("Filtered · \(store.query)")
                    .font(palette.ui(12.5, .bold, relativeTo: .footnote))
                    .lineLimit(1)
                Image(systemName: "xmark.circle.fill").imageScale(.small)
            }
            .foregroundStyle(palette.inkText(0.6))
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(palette.ink(0.06), in: .capsule)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .accessibilityLabel("Clear the search filter")
    }

    /// The circle stays the design's 34pt; the frame around it is the 44pt
    /// touch minimum, anchored bottom-leading so the drawn disc keeps its place
    /// against the margin and the baseline while the target grows into the
    /// space above and beside it.
    private var hamburger: some View {
        VStack(spacing: 4) {
            Capsule().frame(width: 14, height: 1.8)
            Capsule().frame(width: 14, height: 1.8)
            Capsule().frame(width: 9, height: 1.8).padding(.trailing, 5)
        }
        .foregroundStyle(palette.inkText(0.55))
        .frame(minWidth: 34, minHeight: 34)
        .background(palette.ink(0.06), in: .circle)
        .frame(minWidth: 44, minHeight: 44, alignment: .bottomLeading)
        .padding(.bottom, 3)
    }

    private var searchField: some View {
        @Bindable var store = store

        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(palette.ui(14, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.inkText(0.45))
            TextField("Search all tasks", text: $store.query)
                .textFieldStyle(.plain)
                .font(palette.ui(15, .semibold, relativeTo: .body))
                .foregroundStyle(palette.ink)
                .focused($isSearchFocused)
                // The 44pt row the catcher below claims for a finger was 22pt to
                // a VoiceOver or Switch Control cursor: the element belongs to
                // the field UIKit puts inside, sized to its text whatever
                // SwiftUI lays out around it, so the frame alone does not move
                // it and the shape has to be named.
                .frame(minHeight: 44)
                .contentShape(.accessibility, Rectangle())
                // A placeholder is not a name — it is gone the moment there is
                // a query, which is when a reader most needs telling what the
                // text they are hearing belongs to.
                .accessibilityLabel("Search all tasks")
            if !store.query.isEmpty {
                clearButton
            }
        }
        .padding(.leading, 14)
        // The clear button carries its own 44pt of trailing room, so the pill's
        // inset would only push it off the end of the field.
        .padding(.trailing, store.query.isEmpty ? 14 : 0)
        .frame(minHeight: 42)
        // Decoration, and it says so: a filled background is hit-testable and
        // would swallow the taps the catcher below is there to receive.
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.ink(0.06))
                .allowsHitTesting(false)
        }
        // A text field's own hit area is the height of the text it draws — 22pt
        // here — so the pill around it would be dead space. The row claims the
        // 44pt minimum and the catcher hands it anything that is not the text,
        // which leaves the text itself to the field and its caret.
        .frame(minHeight: 44)
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { isSearchFocused = true }
        }
        // Arriving on the Search tab is asking to search: the field opens with
        // the keyboard up, the way every other field in this app that is opened
        // *by* something does. `focusWhenReady` rather than `onAppear`, which
        // lands before the field can hold the keyboard and is dropped on the
        // floor — the modifier has the long version.
        .focusWhenReady($isSearchFocused)
        // And the same request arriving while the field is already on screen:
        // the Search tab tapped again, or ⌘F from a hardware keyboard. A token
        // rather than a flag so a second ask is still a change — see
        // `BoardStore.searchFocusToken`, and `BoardToolbar`, which watches it
        // for the desk.
        .onChange(of: store.searchFocusToken) { _, _ in isSearchFocused = true }
    }

    /// Emptying the field from the field itself, which neither surface offered
    /// (1.11). It keeps focus rather than dismissing the keyboard: clearing is
    /// usually the start of the next search, not the end of this one.
    private var clearButton: some View {
        Button {
            store.clearQuery()
            isSearchFocused = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .imageScale(.medium)
                .foregroundStyle(palette.inkText(0.35))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .accessibilityLabel("Clear search")
    }

    /// The chips, and **the strip keeping the current one in view**.
    ///
    /// Four columns with ordinary names overrun a phone's width — the seed
    /// board's Done chip is cut off at 19 of its 70 points, measured — and the
    /// strip never moved, so paging to the last column highlighted a chip that
    /// was half off the screen and left it there. The chip that says where you
    /// are is the one that has to be legible.
    ///
    /// `scrollTo` with no anchor is the *minimum* scroll that makes the chip
    /// whole, and no scroll at all when it is whole already, which is what the
    /// board's own reveal does on the desk — see `BoardScrollView`. Centring it
    /// instead would shuffle the strip under every page turn, including the
    /// ones that needed nothing.
    ///
    /// `onAppear` as well as `onChange`, because a board is not always opened on
    /// its first column: the strip has to start where the board does, and that
    /// one is not animated because there is nothing to have moved from.
    private var columnChips: some View {
        ScrollViewReader { strip in
            chips
                .onChange(of: store.mobileColumnID) { _, id in
                    Motion.run(.snappy(duration: 0.28), reduceMotion: reduceMotion) {
                        strip.scrollTo(id)
                    }
                }
                .onAppear { strip.scrollTo(store.mobileColumnID) }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(store.pagerColumns.enumerated()), id: \.element.id) { index, column in
                    let isCurrent = column.id == store.mobileColumnID
                    Button { store.mobileColumnID = column.id } label: {
                        // The same capsule the landscape pages draw over
                        // themselves — see ``ColumnPill``, which is where it
                        // lives so the two orientations cannot drift into two
                        // ideas of what a column looks like.
                        ColumnPill(
                            name: column.name,
                            count: store.visibleTasks(in: column.id).count,
                            limit: column.limit,
                            isCurrent: isCurrent
                        )
                        // The capsule stays as drawn; the row around it is the
                        // 44pt minimum.
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.bare)
                    .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                    .contextMenu { columnMenu(column, index: index) }
                    // What the strip above scrolls to.
                    .id(column.id)
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
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

    /// Everything that can be done to a column, on the one control the phone
    /// draws a column as.
    ///
    /// **A long press, because the tap is taken.** The chip's tap pages to that
    /// column and has to keep doing so — it is the switcher. A context menu is
    /// the gesture iOS gives a control that already has a primary action, and it
    /// is what the desk's column header offers behind its ⋯ button; this is that
    /// menu, item for item, on the surface that had none of it. Until now a
    /// column on the phone could only be renamed, recoloured, reordered or
    /// thrown away by opening the drawer, long-pressing the board, and finding
    /// the row in the sheet that came up.
    ///
    /// ``BoardSettingsView`` is what **Edit Column…** opens, arriving with this
    /// column already unfolded — see its `expandsColumn`. Not a sheet of its
    /// own: everything a column can be changed to is already in that row.
    @ViewBuilder private func columnMenu(_ column: BoardColumn, index: Int) -> some View {
        let completedCount = store.isDone(column: column.id) ? store.completedCount : 0
        if store.isDone(column: column.id) {
            Button {
                store.archiveCompleted()
            } label: {
                Label(
                    String(localized: "Archive \(completedCount) Completed",
                           comment: "Menu item on a column that files every finished task away"),
                    systemImage: "archivebox"
                )
            }
            .disabled(completedCount == 0)
            Divider()
        }

        Button {
            openBoardSettings(expanding: column.id)
        } label: {
            Label("Edit Column…", systemImage: "pencil")
        }

        Divider()

        // Left and right rather than up and down: the chips are a horizontal
        // strip and the board pages sideways, so this is the direction the user
        // is looking at. `PhoneBoardEditor`'s own pair says up and down because
        // there the columns are a vertical list.
        //
        // Both dead on the Done column, and Right dead on the one in front of
        // it: Done is the board's last column and that is what makes it Done, so
        // it does not move and nothing moves past it. `BoardColumnView`'s menu
        // greys the same two cases, and `moveColumn` refuses and clamps them.
        Button {
            store.moveColumn(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        } label: {
            Label("Move Left", systemImage: "arrow.left")
        }
        .disabled(index == 0 || store.isDone(column: column.id))

        Button {
            store.moveColumn(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
        } label: {
            Label("Move Right", systemImage: "arrow.right")
        }
        // `count - 2` for `BoardColumnView`'s reason: the last column is Done.
        .disabled(index >= store.pagerColumns.count - 2)

        Divider()

        // No confirmation, matching every other Trash in the app: the act is
        // undoable and the column waits thirty days in the trash. It can still
        // be refused — the last Done column, a board left with none — and a
        // refusal has to say why.
        Button(role: .destructive) {
            refusal = store.trashColumn(column.id)
        } label: {
            Label("Trash Column", systemImage: "trash")
        }
    }
}

#endif
