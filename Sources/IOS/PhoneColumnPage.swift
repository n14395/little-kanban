#if os(iOS)

import SwiftUI

/// One column of the phone's pager: its heading, its cards, and — the reason it
/// is a view of its own — **the ground around them**.
///
/// **A stack rather than `TaskListView`'s `List`, for the reason `InboxPanel` is
/// one.** A `List` handles drags inside its own bounds, so on this page a card
/// released anywhere but squarely on another card reached nothing at all: the
/// space under the last card took no drop, and a column with nothing in it — all
/// of which is that space — could not be dragged to by any gesture. The desk's
/// columns have always been `ScrollView` + `LazyVStack`, which is why dropping
/// onto one has always worked, and a page here *is* a column.
///
/// The swap costs the rows their `swipeActions`, and nothing else. No card in
/// this app swipes since 6.4 — see ``PhoneTaskRowActions`` — so what is given up
/// is a capability the phone had already put in a menu. The flat surfaces keep
/// the `List`: Search, a saved view and the Inbox sheet have no ground that
/// means anything, because none of them is a place a card can be put.
///
/// The page draws the whole column and takes the whole column's drops. Where in
/// it the card lands is not this view's to decide: a card names a gap and the
/// ground names none — see ``BoardStore/drop(_:onGroundOf:)``.
struct PhoneColumnPage<Trailing: View>: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let column: BoardColumn
    let tasks: [TaskItem]
    /// Landscape puts two pages on screen at once, and a heading is then the
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
            // The column's ground, not a gap between two of its cards: the card
            // keeps the row it was on — see `BoardStore.drop(_:onGroundOf:)`.
            store.drop(dropped.id, onGroundOf: store.placement(forColumn: column.id))
            return true
        } isTargeted: { targeted in
            if targeted, store.allowsCardDrag {
                store.dropTargetColumnID = column.id
            } else if store.dropTargetColumnID == column.id {
                store.dropTargetColumnID = nil
            }
        }
    }

    /// The cards, in the container a column has always used.
    ///
    /// The scroll view fills the page whether or not the cards do, and the drop
    /// destination is *outside* it, so the space below the last card is inside
    /// the page's own frame rather than behind something that would swallow it.
    private var cards: some View {
        ScrollView {
            LazyVStack(spacing: metrics.rowSpacing) {
                ForEach(tasks) { task in
                    // No column chip: this page is the column, and a chip on
                    // every card would name it once per row (4.8).
                    PlatformTaskCard(task: task, showsColumn: false)
                }
                trailing()
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.topInset)
            .padding(.bottom, metrics.bottomInset)
        }
        // A column shorter than the page does not bounce — the desk's columns
        // ask for the same thing, and here it also keeps a short column's
        // ground still under a finger that is about to drop a card on it.
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    /// Which column this page is, drawn only when more than one is on screen.
    private var heading: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(palette.resolve(column.dot))
                .frame(width: 7, height: 7)
            Text(column.name)
                .font(SimpleKanbanFont.ui(12.5, .extraBold, relativeTo: .footnote))
                .foregroundStyle(palette.inkText(0.6))
            CountPill(count: tasks.count, font: 10.5)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#endif
