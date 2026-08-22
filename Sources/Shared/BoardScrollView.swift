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
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    ForEach(Array(store.columns.enumerated()), id: \.element.id) { index, column in
                        BoardColumnView(
                            column: column, index: index, metrics: metrics, focus: $focus
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, Self.revealInset)
                        .id(column.id)
                    }
                    AddColumnTile(isComposing: $isAddingColumn, metrics: metrics)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, Self.revealInset)
                        .id(Self.addColumnID)
                }
                .padding(.vertical, Self.stripPadding)
                .padding(.horizontal, Self.stripInset)
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
            // Which column ⌘N adds to, kept in step with wherever focus is by
            // whatever route — a click included. This one is bookkeeping and
            // moves nothing.
            .onChange(of: focus) { _, id in
                relay?.focusedColumnID = id.flatMap { store[$0]?.columnID }
            }
            // Focus moving off the right-hand edge has to bring the board
            // with it — as far as whoever moved it asked for. See
            // ``BoardReveal``: a key wants the column in the middle, a click
            // wants it merely whole.
            .onChange(of: reveal) { previous, reveal in
                guard let reveal, let columnID = store[reveal.task]?.columnID else { return }
                switch reveal.manner {
                case .centred:
                    // Only when the column itself changes: ↑ and ↓ stay where
                    // they are, and re-centring a column that is already on
                    // screen under every key press is a board that will not sit
                    // still. Asked of the card revealed *before* this one
                    // rather than of a remembered column, which is a second
                    // piece of state that could disagree with this one.
                    guard columnID != previous.flatMap({ store[$0.task]?.columnID }) else { return }
                    scroll { proxy.scrollTo(columnID, anchor: .center) }
                case .intoView:
                    // `anchor: nil` is the minimum scroll that makes the column
                    // whole, and no scroll at all when it is whole already —
                    // which is the entire behaviour a click is allowed. The
                    // margin either side of it comes from `revealInset`.
                    scroll { proxy.scrollTo(columnID) }
                }
            }
            .onDisappear { relay?.focusedColumnID = nil }
        }
    }

    /// Flattened: `relay` is itself optional, so the chain is a double optional
    /// and `onChange` would be comparing one.
    private var reveal: BoardReveal? { relay?.reveal ?? nil }

    /// One animation for every reveal, so the two manners cannot drift into
    /// moving the board at different speeds.
    private func scroll(_ body: () -> Void) {
        Motion.run(.easeOut(duration: 0.16), reduceMotion: reduceMotion, body)
    }

    /// The gap the design puts between two columns, and the board's own margin
    /// at either end of the strip. What the board must still measure once the
    /// reveal inset has been taken out of both.
    static let gutter: CGFloat = 12
    static let stripPadding: CGFloat = 16

    /// How much board is brought into view either side of a column that is
    /// scrolled to.
    ///
    /// `scrollTo` has no notion of a margin: with no anchor it moves the
    /// minimum that makes the target whole, which leaves a revealed column
    /// flush against the window's edge with nothing beside it — technically
    /// visible and reading as still cut off. So each column is scrolled to
    /// *wrapped in this much padding*, which is what the identifier is attached
    /// to, and the wrapper is what has to fit.
    ///
    /// It costs the layout nothing: the padding is taken back out of the
    /// `HStack`'s spacing and the strip's own margin, so the columns sit
    /// exactly where they did — `gutter` apart and `stripPadding` from the
    /// ends. The wrappers overlap each other by twice this, which is empty
    /// space either way and hit-tests as nothing.
    static let revealInset: CGFloat = 16

    /// The spacing and the margin that are actually spent, once each column has
    /// taken `revealInset` of its own. Both go *negative* as the inset passes
    /// the thing it is taken out of, which is allowed and is the point: what has
    /// to hold is that the two add back up, and `BoardRevealTests` asks that.
    static var columnSpacing: CGFloat { gutter - revealInset * 2 }
    static var stripInset: CGFloat { stripPadding - revealInset }

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
