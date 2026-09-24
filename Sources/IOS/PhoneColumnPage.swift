// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

#if os(iOS)

import SwiftUI

/// One column of the phone's pager: its heading, its cards, and — the reason it
/// is a view of its own — **the ground around them**.
///
/// **``PhoneCardStack`` rather than `TaskListView`'s `List`**, which is what a
/// page was until a drop had somewhere to land: a `List` handles drags inside
/// its own bounds, so a card released anywhere on this page — squarely on
/// another card, in the space under the last one, anywhere at all in a column
/// with nothing in it — reached nothing. That file has the rest of the argument.
///
/// The page draws the whole column and takes the whole column's drops. Where in
/// it the card lands is not this view's to decide: a card names a gap and the
/// ground names none — see ``BoardStore/drop(_:onGroundOf:)``.
struct PhoneColumnPage<Trailing: View>: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let column: BoardColumn
    let tasks: [TaskItem]
    /// Landscape puts three pages on screen at once, and a heading is then the
    /// only thing that says which is which. In portrait the header's chips have
    /// just said it, and a second caption under them is the count pill 4.4
    /// removed.
    var showsHeading: Bool = false
    var metrics: TaskListMetrics = .sheet
    /// Rows of the caller's own after the cards — the empty state and the
    /// dashed "add task to…" row, which `PhoneRootView` builds because the flat
    /// list needs the same two and one wording of each is enough.
    @ViewBuilder let trailing: () -> Trailing

    /// Lit while a card is over this page. `draggingID` guards it the way the
    /// desk's column highlight is guarded: a flag left true by a drop that went
    /// elsewhere would leave the page tinted with nothing over it.
    private var isDropTarget: Bool {
        store.dropTargetColumnID == column.id && store.draggingID != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeading { heading }
            cards
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The tint the desk's column draws, without its 2pt border: a strip in
        // a row of strips needs an edge to be told apart from its neighbours,
        // and a page that fills the screen has nothing to be told apart from.
        .background(isDropTarget ? palette.accent.opacity(0.07) : Color.clear)
        // Most of a page is empty space, and empty space is hit-tested only
        // where something has said what shape it is. Without this the drop
        // destination below covers the cards and nothing else, which is the
        // state this view was written to end.
        .contentShape(.rect)
        // Only this app's cards are a payload, and only while the rows on
        // screen are the board's own order — `BoardTaskCard` has the why.
        .dropDestination(for: TaskTransfer.self) { items, _ in
            guard store.allowsCardDrag, let dropped = items.first, store[dropped.id] != nil
            else { return false }
            // The column's ground, not a gap between two of its cards — so it
            // lands at the foot, or at the head of Done; see
            // `BoardStore.drop(_:onGroundOf:)`.
            store.drop(dropped.id, onGroundOf: store.placement(forColumn: column.id))
            return true
        } isTargeted: { targeted in
            // A lift is not a drag until a destination has seen it, and where
            // the system never says the drag is over, every destination letting
            // go at once is what does — see `BoardStore.dragTargeting`.
            store.dragTargeting(targeted)
            if targeted, store.allowsCardDrag {
                store.dropTargetColumnID = column.id
                // The page's own ground, which is what this firing means — a
                // nested zone takes the hover from its parent. See
                // `BoardStore.dropTargetCaret` for why that is what retires a
                // caret and leaving a row is not.
                store.dropTargetCaret = nil
            } else if store.dropTargetColumnID == column.id {
                store.dropTargetColumnID = nil
            }
        }
    }

    /// The cards, in the container a column has always used.
    ///
    /// The stack's scroll view fills the page whether or not the cards do, and
    /// the drop destination is *outside* it, so the space below the last card is
    /// inside the page's own frame rather than behind something that would
    /// swallow it.
    private var cards: some View {
        PhoneCardStack(tasks: tasks, metrics: metrics, preview: preview, trailing: trailing)
            // The stand-in *is* the insertion point on a page a card can be
            // dropped into, so the rows beside it draw no line of their own —
            // see `drawsDropCaret`. Set here rather than in the stack because
            // the Inbox sheet draws the same stack and keeps its line.
            .environment(\.drawsDropCaret, false)
    }

    /// Where in this column a dragged card would land, or `nil` when none is on
    /// the way here. ``BoardStore/dropPreview(in:)`` works it out; the page only
    /// makes room for it.
    private var preview: DropPreview? {
        store.dropPreview(in: store.placement(forColumn: column.id))
    }

    /// Which column this page is, drawn only when more than one is on screen.
    ///
    /// **The pill portrait's switcher draws**, not a caption of its own. It was
    /// one — a coloured dot, the name, and a `CountPill` beside it — which meant
    /// a column looked like one thing with the phone upright and another thing
    /// with it on its side, for no reason a user could name. `ColumnPill` is now
    /// the one drawing, and it explains why this one is never accent-filled.
    ///
    /// The dot went with the caption. It is the one thing portrait's chips have
    /// never carried, and a strip of pills each wearing a swatch is a busier row
    /// than a column heading needs — the pages are side by side and the name is
    /// what tells them apart.
    private var heading: some View {
        HStack(spacing: 8) {
            ColumnPill(name: column.name, count: tasks.count, limit: column.limit)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#endif
