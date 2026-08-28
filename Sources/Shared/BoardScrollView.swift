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

    /// Which card the keyboard is on. A view concern rather than board state:
    /// it is where the next key press lands, it is not saved, and a second
    /// surface showing the same card would have its own.
    @FocusState private var focus: TaskItem.ID?

    /// Whether the strip steps aside for the blank-board state.
    ///
    /// Only for a board with no *structure* to draw: no working columns, and
    /// nothing sitting in Done either — a card completed out of the Inbox onto
    /// a fresh board must stay reachable. A board **with** a working column
    /// shows its columns however empty they are, each carrying its own
    /// "drag a card here" — the rule the phone has always applied, and the one
    /// that broke here: a column added to a blank board stayed invisible
    /// behind "This board is empty" until the first card materialised it.
    ///
    /// A board that is being composed into is never blank: the row being typed
    /// into is in the strip, and swapping the strip out from under it would
    /// take the field away mid-word.
    ///
    /// A static of three facts rather than a branch in the body, so the rule
    /// can be held up to a test — `RootSurface.resolve`'s bargain.
    static func showsBlankState(
        hasWorkingColumns: Bool, hasAnyVisibleCard: Bool, isComposing: Bool
    ) -> Bool {
        !isComposing && !hasWorkingColumns && !hasAnyVisibleCard
    }

    private var isEmpty: Bool {
        Self.showsBlankState(
            hasWorkingColumns: !store.workingColumns.isEmpty,
            hasAnyVisibleCard: store.columns.contains { !store.visibleTasks(in: $0.id).isEmpty },
            isComposing: store.addingColumnID != nil
        )
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
                }
                .padding(.vertical, Self.stripPadding)
                .padding(.horizontal, Self.stripInset)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The strip's margin is `stripPadding` at the head and the foot, and
            // on an iPad the foot's was landing on top of the home indicator's
            // 20pt — 16 above the columns and 36 below them, which reads as a
            // gap somebody chose. See ``HomeIndicatorFoot``; a no-op on the desk
            // and anywhere there is no such strip.
            .underTheHomeIndicator()
            // The board scrolls sideways and the composer is drawn inside a
            // column, so ⌘N on a board scrolled right used to take the focus to
            // a text field several hundred points off the edge of the window —
            // typing went somewhere the user could not see.
            .onChange(of: store.addingColumnID) { _, id in
                guard let id else { return }
                Motion.run(.easeOut(duration: 0.16), reduceMotion: reduceMotion) { proxy.scrollTo(id, anchor: .center) }
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
            // The panel opens *beside* the board and takes its width out of
            // the board's, so a card picked at the right-hand edge is behind
            // the panel by the time the panel is there: selected, and no longer
            // on screen. This is `.intoView` again — the least the board can do
            // — asked of the width the board is left with rather than the one
            // it had when the card was clicked.
            //
            // **Why it waits.** The reveal the click itself raises cannot
            // answer this: it is measured while the board is still whole, and
            // the minimum scroll that makes a column whole in a board about to
            // lose a third of itself is no scroll at all. Nor is measuring the
            // new width enough. Both were tried, in a 1240pt window with the
            // panel closed and the card at x=1234–1486: the layout reports
            // 672pt the instant the panel opens, and a scroll issued then — or
            // one runloop turn later — still left the card exactly where it
            // was, with the board's right-hand edge arriving at x=1312 over the
            // top of it. The scroll view's own visible rect follows the panel's
            // animation rather than jumping to the end of it, so the wait is
            // for that: the same measurement with the scroll taken after
            // `panelTravel` put the card at x=1034–1286, clear of the panel.
            //
            // Only on the way *open*. Closing the panel hands the width back,
            // and a column that was whole in the narrow board is whole in the
            // wide one.
            //
            // Nothing moves where the panel is drawn *over* the board instead,
            // which is the shape an iPad falls back to when there is not a
            // column's width left beside it — see
            // `PadRootView.hasRoomBesideTheBoard`. The board keeps its width
            // there, so the minimum scroll is none, which is the honest answer:
            // the panel is covering the board because there is nowhere else to
            // put it.
            .onChange(of: store.isInspectorOpen) { _, isOpen in
                guard isOpen, let columnID = store.selectedTask?.columnID else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: Self.panelTravel)
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

    /// How long to leave the detail panel to take its width before measuring
    /// the board against what is left.
    ///
    /// `MacRootView` and `PadRootView` both animate the panel over 0.16s, and
    /// the slack is three frames on top — the wait is for the scroll view's
    /// visible rect to have finished following it, and a scroll one frame early
    /// is a scroll measured against a board that is still moving.
    static let panelTravel: Duration = .milliseconds(210)

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

    /// The blank board carries the "add a column" way out, and it is the
    /// **only** thing on the board that offers one: the strip used to end in a
    /// dashed `AddColumnTile`, which spent 38pt of every board for ever on a
    /// button most people press once. Columns are managed in
    /// `BoardSettingsView` now — reachable from any column's header menu, from
    /// the sidebar's board menu, and from here — and a board with no columns at
    /// all would otherwise have no way forward.
    ///
    /// One state now, not two: the strip only ever steps aside for a board
    /// with no working columns — see ``showsBlankState`` — so the copy is
    /// always the blank board's, and the way forward is always a column. A
    /// board *with* columns and nothing in them draws the columns, each
    /// carrying its own empty copy, because the structure somebody just built
    /// in Board Settings has to be visible to be believed.
    private var emptyState: some View {
        EmptyStateView.noColumns(metrics: metrics.emptyState, add: addColumn)
    }

    /// Opens the board's settings with the add-column composer already open, so
    /// "add a column" lands in a field rather than in a sheet with a button in
    /// it — the promise `focusesName` keeps for the routes that say *rename*.
    private func addColumn() {
        guard let board = store.activeBoardID else { return }
        store.boardSettings = BoardSettingsRequest(board: board, addsColumn: true)
    }

    /// No boards at all, which deleting the last one is allowed to reach.
    private var noBoards: EmptyStateView {
        .noBoards(metrics: metrics.emptyState, add: createFirstBoard)
    }

    /// The same act the sidebar's row performs: the board is made under
    /// ``Board/defaultName`` and its settings open on the empty name field. This
    /// one exists so the board surface is not a dead end when there is no board
    /// at all to hang a sidebar row off.
    private func createFirstBoard() {
        guard let id = store.createBoard(named: Board.defaultName) else { return }
        store.boardSettings = BoardSettingsRequest(board: id, namesNewBoard: true)
    }
}
