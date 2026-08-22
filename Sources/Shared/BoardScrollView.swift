import SwiftUI

/// The horizontally scrolling column strip.
struct BoardScrollView: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    /// What the surface tells the world outside it. `nil` where there is no
    /// such world: the iPad has no menu bar to ask, and a preview has neither.
    @Environment(BoardFocusRelay.self) private var relay: BoardFocusRelay?
    /// A scroll that carries the view across the board is motion like any
    /// other: the card still has to arrive, it just arrives at once.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var metrics: BoardColumnView.Metrics = .desk

    @State private var isAddingColumn = false
    /// Which card the keyboard is on. A view concern rather than board state:
    /// it is where the next key press lands, it is not saved, and a second
    /// surface showing the same card would have its own.
    @FocusState private var focus: TaskItem.ID?

    /// A board with nothing on it anywhere takes one empty state rather than
    /// four stacked ones. The per-column copy is for a column that is empty
    /// while the others are not, which is a different thing to say.
    ///
    /// A board that is being composed into — a task or a column — is not empty:
    /// the row being typed into is in the strip, and swapping the strip out
    /// from under it would take the field away mid-word.
    private var isEmpty: Bool {
        !isAddingColumn && store.addingColumnID == nil
            && store.columns.allSatisfy { store.visibleTasks(in: $0.id).isEmpty }
    }

    var body: some View {
        if store.activeBoard == nil {
            noBoards
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            columns
        }
    }

    private var columns: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(store.columns.enumerated()), id: \.element.id) { index, column in
                        BoardColumnView(
                            column: column, index: index, metrics: metrics, focus: $focus
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                        .id(column.id)
                    }
                    AddColumnTile(isComposing: $isAddingColumn, metrics: metrics)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .id(Self.addColumnID)
                }
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The board scrolls sideways and the composer is drawn inside a
            // column, so ⌘N on a board scrolled right used to take the focus to
            // a text field several hundred points off the edge of the window —
            // typing went somewhere the user could not see.
            .onChange(of: store.addingColumnID) { _, id in
                guard let id else { return }
                Motion.run(.easeOut(duration: 0.16), reduceMotion: reduceMotion) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: isAddingColumn) { _, composing in
                guard composing else { return }
                Motion.run(.easeOut(duration: 0.16), reduceMotion: reduceMotion) {
                    proxy.scrollTo(Self.addColumnID, anchor: .trailing)
                }
            }
            // Focus moving off the right-hand edge has to bring the board with
            // it, for the same reason.
            .onChange(of: focus) { _, id in
                let columnID = id.flatMap { store[$0]?.columnID }
                // Only when the column itself changes: ↑ and ↓ stay where they
                // are, and re-centring a column that is already on screen under
                // every key press is a board that will not sit still.
                guard columnID != relay?.focusedColumnID else { return }
                relay?.focusedColumnID = columnID
                guard let columnID else { return }
                Motion.run(.easeOut(duration: 0.16), reduceMotion: reduceMotion) {
                    proxy.scrollTo(columnID, anchor: .center)
                }
            }
            .onDisappear { relay?.focusedColumnID = nil }
        }
    }

    private static let addColumnID = "add-column"

    /// The empty board carries the "add a column" way out as well as the "add a
    /// task" one, because the tile that usually offers it lives in the strip
    /// this state replaces — and a board with no columns at all, which a
    /// hand-edited file can still be, would otherwise have no way forward.
    @ViewBuilder
    private var emptyState: some View {
        if store.isFiltering {
            EmptyStateView.noResults(query: store.query, metrics: metrics.emptyState) {
                store.clearQuery()
            }
        } else {
            VStack(spacing: 4) {
                EmptyStateView.board(metrics: metrics.emptyState, add: addTask)
                addColumnButton
            }
        }
    }

    private var addTask: (() -> Void)? {
        guard let column = store.activeBoard?.landingColumn else { return nil }
        return { store.beginAdding(in: column.id) }
    }

    private var addColumnButton: some View {
        Button { isAddingColumn = true } label: {
            Text("Add a column", comment: "Empty board button that starts a column")
                .font(SimpleKanbanFont.ui(11.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.inkText(0.45))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .frame(minHeight: metrics.rowHit)
        }
        .buttonStyle(.bare)
        .hoverBackground(palette.ink(0.06), radius: 9)
    }

    /// No boards at all, which deleting the last one is allowed to reach.
    private var noBoards: EmptyStateView {
        .noBoards(metrics: metrics.emptyState, add: createFirstBoard)
    }

    /// Named rather than asked for: the sidebar's row is where a board is named
    /// as it is made, and this one exists so the board surface is not a dead
    /// end. The toolbar title is the field that renames it, and it is one click
    /// away.
    private func createFirstBoard() {
        store.createBoard(named: String(
            localized: "New Board",
            comment: "Default name for the board made from the empty board surface"
        ))
    }
}
