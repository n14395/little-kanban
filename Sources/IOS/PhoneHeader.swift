#if os(iOS)

import SwiftUI

/// Board title, drawer button and the board-actions menu, over whichever of the
/// second row's four bars the current surface calls for: the saved view that has
/// replaced the board, the search field, the column chips, and the notice that a
/// query is narrowing a list whose field is elsewhere.
struct PhoneHeader: View {
    /// How many rows the list below is drawing. The saved-view bar's pill sits
    /// directly on top of that list, so it reports its length rather than the
    /// view's membership — a pill reading "3" over "Nothing matched" makes the
    /// search look broken instead of the view look full. The drawer row's pill
    /// is the unnarrowed `count(of:)`, because that one is a badge on a
    /// destination rather than a caption on a list.
    let listCount: Int

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    /// The phone on its side has 402pt of height and the same chrome as 852pt
    /// of portrait, which left the columns a single card tall. Everything this
    /// gates is vertical space (5.5).
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @FocusState private var isSearchFocused: Bool
    @State private var isManagingLabels = false
    @State private var isRenamingBoard = false

    private var isShort: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: isShort ? 9 : 16) {
            HStack(alignment: .bottom, spacing: 12) {
                Button { store.isNavDrawerOpen = true } label: {
                    hamburger
                }
                .buttonStyle(.bare)
                .accessibilityLabel("Show boards")

                Text(title)
                    .font(SimpleKanbanFont.serif(isShort ? 22 : 30))
                    .lineSpacing(2)
                    .lineLimit(isShort ? 1 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                boardMenu
            }

            if let view = store.activeView {
                savedViewBar(view)
            }

            // Search keeps its field wherever it is, including inside a saved
            // view: the query narrows the view, and the control that set it has
            // to stay reachable.
            if store.tab == .search {
                searchField
            } else if store.isColumnPaging, !isShort {
                // Dropped on a short screen, where the pages carry their own
                // headings and the strip below still jumps between them: the
                // chips are the third thing naming the same column, and the one
                // that costs a card's worth of height to say it.
                columnChips
            }

            if store.showsMobileFilterNotice {
                filteredIndicator
            }
        }
        .padding(.horizontal, 20)
        .labelManagerSheet(isPresented: $isManagingLabels, metrics: .sheet)
        .sheet(isPresented: $isRenamingBoard) {
            if let id = store.activeBoardID {
                PhoneBoardEditor(boardID: id, focusesName: true)
                    .environment(store)
                    .environment(\.palette, palette)
                    .tint(palette.accent)
            }
        }
    }

    /// What is on screen, named. The board's own name — this was the product
    /// name written out as a literal in four files (4.7) — except on the Inbox,
    /// which belongs to no board and so cannot borrow one's name, and on a store
    /// with no boards left, which is a state deleting the last one reaches.
    private var title: String {
        if store.tab == .inbox, store.activeView == nil { return Board.inboxName }
        return store.activeBoard?.name ?? String(
            localized: "No Board", comment: "Phone header title when every board has been deleted"
        )
    }

    /// The board-level actions with no other home on the phone (4.4). This was a
    /// decorated `Image` — no action, no label, no target — beside a hamburger
    /// that has always been a real button.
    private var boardMenu: some View {
        Menu {
            // Renaming the board is here rather than on the title itself (4.7):
            // a serif line that turns into a field on a tap is a control nothing
            // on screen says is one.
            Section {
                Button { isRenamingBoard = true } label: {
                    Label("Rename Board…", systemImage: "pencil")
                }
                .disabled(store.activeBoard == nil)

                Button { store.isNavDrawerOpen = true } label: {
                    Label("Switch Board…", systemImage: "rectangle.stack")
                }
            } header: {
                Text("Board")
            }

            Section {
                if store.activeView != nil {
                    Button { store.selectTab(.board) } label: {
                        Label("Back to Board", systemImage: "square.grid.2x2")
                    }
                }
                // Not `allCases`: the Inbox is a tab on this surface — see
                // `SavedView.phone`.
                ForEach(SavedView.phone) { view in
                    Button { store.activeView = view } label: {
                        Label(view.label, systemImage: view.symbol)
                    }
                }
            } header: {
                Text("Views")
            }

            Section {
                Button { store.archiveCompleted() } label: {
                    Label("Archive Completed", systemImage: "archivebox")
                }
                .disabled(store.completedTasks.isEmpty)

                Button { isManagingLabels = true } label: {
                    Label("Manage Labels", systemImage: "tag")
                }

                Button { store.clearQuery() } label: {
                    Label("Clear Search", systemImage: "xmark.circle")
                }
                .disabled(!store.isFiltering)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(SimpleKanbanFont.ui(15, .extraBold, relativeTo: .subheadline))
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

    /// What is on screen when the columns are not: the view's name, the length
    /// of the list under it, and the way back. Without this the tab bar still
    /// reads "Board" while the list underneath is something else entirely.
    private func savedViewBar(_ view: SavedView) -> some View {
        HStack(spacing: 9) {
            Image(systemName: view.symbol)
                .imageScale(.small)
            Text(view.label)
                .font(SimpleKanbanFont.ui(14.5, .bold, relativeTo: .subheadline))
            CountPill(count: listCount, font: 11.5)
            Spacer(minLength: 0)
            Button { store.selectTab(.board) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").imageScale(.small)
                    Text("Board")
                        .font(SimpleKanbanFont.ui(13, .bold, relativeTo: .footnote))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.bare)
            .accessibilityLabel("Back to board")
        }
        .foregroundStyle(palette.accent)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(palette.accentSoft, in: .rect(cornerRadius: 14))
    }

    /// A query narrowing a list whose field is on another tab. The rule is that
    /// a filter is never invisible (1.11), so where the field cannot be shown
    /// this says the filter exists and undoes it in one tap.
    private var filteredIndicator: some View {
        Button { store.clearQuery() } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease").imageScale(.small)
                Text("Filtered · \(store.query)")
                    .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .footnote))
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
                .font(SimpleKanbanFont.ui(14, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.inkText(0.45))
            TextField("Search all tasks", text: $store.query)
                .textFieldStyle(.plain)
                .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
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

    private var columnChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(store.pagerColumns) { column in
                    let isCurrent = column.id == store.mobileColumnID
                    Button { store.mobileColumnID = column.id } label: {
                        HStack(spacing: 6) {
                            Text(column.name)
                                .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .footnote))
                            Text("\(store.boardTasks(in: column.id).count)")
                                .font(SimpleKanbanFont.ui(10.5, .extraBold, relativeTo: .caption2))
                                .opacity(0.65)
                        }
                        .foregroundStyle(isCurrent ? palette.onAccent : palette.inkText(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isCurrent ? palette.accent : palette.ink(0.055), in: .capsule)
                        // The capsule stays as drawn; the row around it is the
                        // 44pt minimum.
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.bare)
                    .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }
}

/// Previous / dots / next, stepping through the workflow columns.
///
/// Every one of the three is a real control. The dots were decoration — the one
/// part of the spec's pager that said where you were and offered no way to go
/// anywhere — so each is now the button for its column, which is also the
/// non-gesture way to page for a reader who cannot swipe (7.1).
struct PhoneColumnPager: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isShort: Bool { verticalSizeClass == .compact }

    var body: some View {
        HStack(spacing: 10) {
            stepButton(systemName: "chevron.left", label: "Previous column") {
                store.stepMobileColumn(by: -1)
            }

            dots

            stepButton(systemName: "chevron.right", label: "Next column") {
                store.stepMobileColumn(by: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, isShort ? 2 : 14)
        .padding(.bottom, isShort ? 0 : 10)
    }

    /// The drawn capsules keep the design's size; the target around each is a
    /// share of the strip, capped at a finger's width so four dots do not
    /// spread across a phone and floored by the `HStack` when a board has more
    /// columns than the strip has room for.
    private var dots: some View {
        HStack(spacing: 0) {
            ForEach(store.pagerColumns) { column in
                let isCurrent = column.id == store.mobileColumnID
                Button { store.mobileColumnID = column.id } label: {
                    Capsule()
                        .fill(isCurrent ? palette.accent : palette.ink(0.18))
                        .frame(width: isCurrent ? 22 : 5, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.bare)
                .accessibilityLabel(column.name)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
        .frame(maxWidth: CGFloat(store.pagerColumns.count) * 44)
        .frame(maxWidth: .infinity)
        .motionAnimation(.snappy(duration: 0.2), value: store.mobileColumnID)
    }

    private func stepButton(systemName: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(SimpleKanbanFont.ui(12, .semibold, relativeTo: .footnote))
                .foregroundStyle(palette.inkText(0.6))
                .frame(minWidth: 30, minHeight: 30)
                .background(palette.ink(0.06), in: .circle)
                .frame(minWidth: 44, minHeight: 44)
                // The arrow is the button, so it must not also be an element
                // inside it: "Previous column" containing an `Image` called
                // "Back" is one control named twice and differently.
                .accessibilityHidden(true)
        }
        .buttonStyle(.bare)
        .contentShape(.circle)
        .accessibilityLabel(label)
    }
}

#endif
