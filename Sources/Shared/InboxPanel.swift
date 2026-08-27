import SwiftUI

/// The global Inbox, standing **beside** the board rather than in place of it.
///
/// It used to be a page: picking Inbox in the source list took the board away,
/// which is the wrong trade for the one list you reach for *while* working on a
/// board. So it is a column-wide panel between the source list and the board,
/// switched by the same row that used to navigate to it, and the row is a
/// toggle — see ``BoardStore/isInboxOpen``.
///
/// A column's width because that is what it reads as: the same strip, holding
/// the cards that are on no board at all. It is not a `BoardColumnView` — the
/// Inbox has no name to rename, no dot to recolour, no role and no delete — but
/// it keeps the column's gutter and the column's card, so the eye is not asked
/// to learn a second kind of stack.
///
/// Shared rather than written twice: the desk and the iPad draw the same panel
/// at their own metrics. The phone has neither the width nor the pointer for it
/// and keeps its tab.
struct InboxPanel: View {
    struct Metrics {
        /// A column's, and stated as such: the panel drifting off the column
        /// grid would be visible from across the room.
        var width: CGFloat
        var headerHeight: CGFloat
        var headerPadding: CGFloat
        var headerSpacing: CGFloat
        var titleSize: CGFloat
        /// The square the header's "+" claims. A finger needs 44.
        var button: CGFloat
        var glyph: CGFloat
        var list: TaskListMetrics
        var card: BoardTaskCard.Metrics
        var composer: BoardTaskComposer.Metrics
        var emptyState: EmptyStateView.Metrics

        static let desk = Metrics(
            width: BoardColumnView.Metrics.desk.width,
            headerHeight: 46, headerPadding: 14, headerSpacing: 8, titleSize: 14,
            button: 24, glyph: 12,
            list: .panel, card: .desk, composer: .desk, emptyState: .desk
        )
        static let pad = Metrics(
            width: BoardColumnView.Metrics.pad.width,
            headerHeight: 60, headerPadding: 16, headerSpacing: 10, titleSize: 15,
            button: 44, glyph: 15,
            list: .panelPad, card: .pad, composer: .pad, emptyState: .sheet
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    /// Which row the keyboard is on. Owned here rather than by the rows, for
    /// `BoardScrollView`'s reason: ↑ and ↓ cross rows, and a row cannot see its
    /// neighbours.
    @FocusState private var focus: TaskItem.ID?
    @Environment(BoardFocusRelay.self) private var relay: BoardFocusRelay?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Flattened, for the reason ``BoardScrollView`` gives.
    private var reveal: BoardReveal? { relay?.reveal ?? nil }

    var metrics: Metrics = .desk
    /// The gap the window's traffic lights need when the panel is what they
    /// land on — the source list is gone and the panel is leftmost. Zero
    /// everywhere else, and zero always on iPad.
    var leadingInset: CGFloat = 0

    private var chrome = ChromeScale()

    private var isComposing: Bool { store.addingPlacement == .inbox }
    /// Lit while a card is over the panel — see ``BoardStore/isInboxDropTarget``
    /// for why it is on the store and not in here. `draggingID` guards it the
    /// way the columns' highlight is guarded: a flag left true by a drop that
    /// went elsewhere would leave the panel lit with nothing over it.
    private var isDropTarget: Bool { store.isInboxDropTarget && store.draggingID != nil }

    var body: some View {
        let tasks = store.inboxTasks

        VStack(spacing: 0) {
            header(count: tasks.count)
            if isComposing {
                BoardTaskComposer(placement: .inbox, metrics: metrics.composer)
                    .padding(.horizontal, metrics.list.horizontalPadding)
                    .padding(.top, metrics.list.topInset)
            }
            if tasks.isEmpty, !isComposing {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                cards(tasks)
            }
        }
        .frame(width: chrome(metrics.width))
        .frame(maxHeight: .infinity)
        .background(isDropTarget ? palette.accent.opacity(0.07) : palette.panelOverlay)
        .hairline(.trailing, color: palette.ink(0.08))
        .overlay {
            if isDropTarget {
                Rectangle().strokeBorder(palette.accent, lineWidth: 2)
            }
        }
        // The way back for a card filed by mistake, and the obvious one now
        // that the Inbox is on screen: a panel you can see and cannot drop onto
        // reads as broken. The source list's row still takes drops too — that
        // one is the only route when the panel is shut.
        .dropDestination(for: TaskTransfer.self) { items, _ in
            store.isInboxDropTarget = false
            guard store.allowsCardDrag, let dropped = items.first, store[dropped.id] != nil
            else { return false }
            // A card already in the Inbox has landed on empty panel rather
            // than on one of its neighbours, which is not a move — and one
            // arriving off a board lands at the foot, the way a column's ground
            // puts it there. Both are `drop(_:onGroundOf:)`'s.
            store.drop(dropped.id, onGroundOf: .inbox)
            return true
        } isTargeted: { targeted in
            guard store.allowsCardDrag else { return }
            store.isInboxDropTarget = targeted
            // The panel's own ground, which is what a *true* here means: a
            // nested zone takes the hover from its parent, so one of the rows
            // would have swallowed it. That retires whatever gap a row was
            // naming — see `BoardStore.dropTargetCaret`.
            if targeted { store.dropTargetCaret = nil }
        }
    }

    /// **A column's stack, not `TaskListView`'s `List`.**
    ///
    /// A `List` is the wrong container for the reason this panel exists: it
    /// handles drags inside its own bounds, so a card dropped anywhere but
    /// exactly on top of another card never reached the panel's drop destination
    /// behind it. The columns have always used `ScrollView` + `LazyVStack`,
    /// which is why dropping between them has always worked, and the panel is a
    /// column.
    ///
    /// Nothing is lost by the swap. It cost the rows their `swipeActions` when
    /// this was written, and it costs nothing at all since 6.4 — no card in the
    /// app swipes now, on any surface.
    private func cards(_ tasks: [TaskItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: metrics.list.rowSpacing) {
                    ForEach(tasks) { task in
                        // No column chip: it names where a card is, and inside
                        // the Inbox every card is in the Inbox. The flat
                        // surfaces earn the chip because their rows come from
                        // anywhere.
                        ListCard(task: task, showsColumn: false, metrics: metrics.card, focus: $focus)
                            .id(task.id)
                    }
                }
                .padding(.horizontal, metrics.list.horizontalPadding)
                .padding(.top, metrics.list.topInset)
                .padding(.bottom, metrics.list.bottomInset)
            }
            .scrollBounceBehavior(.basedOnSize)
            // The panel is as tall as the board, so a key landing on a card
            // near the bottom has to bring the card with it — the same reason
            // `BoardColumnView` carries this, and the same reason a click is
            // not one of the routes that does.
            .onChange(of: reveal) { _, reveal in
                guard let reveal, tasks.contains(where: { $0.id == reveal.task }) else { return }
                Motion.run(.easeOut(duration: 0.16), reduceMotion: reduceMotion) {
                    switch reveal.manner {
                    case .centred: proxy.scrollTo(reveal.task, anchor: .center)
                    case .intoView: proxy.scrollTo(reveal.task)
                    }
                }
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: metrics.headerSpacing) {
            Image(systemName: "tray")
                .imageScale(.small)
                .foregroundStyle(palette.inkText(0.45))
                .accessibilityHidden(true)
            Text(Board.inboxName)
                .font(palette.ui(metrics.titleSize, .extraBold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
            CountPill(count: count)

            Spacer(minLength: 0)

            Button { store.beginAdding(in: .inbox) } label: {
                Image(systemName: "plus")
                    .font(palette.ui(metrics.glyph, .medium, relativeTo: .footnote))
                    .foregroundStyle(palette.inkText(0.45))
                    .frame(minWidth: metrics.button, minHeight: metrics.button)
            }
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.08), radius: 8)
            .accessibilityLabel("Capture a task")
        }
        .padding(.horizontal, metrics.headerPadding)
        .padding(.leading, leadingInset)
        .frame(minHeight: metrics.headerHeight)
        .hairline(.bottom, color: palette.ink(0.07))
    }

    private var emptyState: some View {
        EmptyStateView.inbox(metrics: metrics.emptyState) {
            store.beginAdding(in: .inbox)
        }
    }
}
