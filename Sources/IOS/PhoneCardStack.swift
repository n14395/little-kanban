#if os(iOS)

import SwiftUI

/// The phone's cards, stacked the way a column stacks them — a `ScrollView` and
/// a `LazyVStack`, with rows of the caller's own under them.
///
/// **Not `TaskListView`'s `List`, and the whole difference is drops.** A `List`
/// handles drags inside its own bounds: its rows are hosted in collection view
/// cells, a card released on one lands nowhere, and the space around them
/// reaches nothing behind it either. So the two surfaces that are *places a card
/// can be put* — a board column and the Inbox — draw their cards with this
/// instead, and hang their own drop destination around it. The desk made the
/// same choice for the same reason and earlier: see ``InboxPanel``.
///
/// The flat surfaces keep the `List`. Search, a saved view and the Archive are
/// filters over the board rather than places on it, and nothing can be dropped
/// into a filter.
///
/// What the stack costs is `swipeActions`, and nothing else — no card in this
/// app has swiped since 6.4. Everything those two edges held is on the card
/// (the tick), in the detail sheet, and in ``PhoneTaskRowActions``' menu for
/// a pointer.
struct PhoneCardStack<Trailing: View>: View {
    let tasks: [TaskItem]
    var metrics: TaskListMetrics = .sheet
    /// Rows after the cards — an empty state, a dashed "add task to…" row. The
    /// surfaces build their own, because the wording is theirs.
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ScrollView {
            LazyVStack(spacing: metrics.rowSpacing) {
                ForEach(tasks) { task in
                    // No column chip on either surface that draws this, and for
                    // the same argument from opposite ends (4.8): a column page
                    // *is* the column it would name, and every card in the Inbox
                    // is in the Inbox. The chip earns its room where a list
                    // gathers cards from anywhere, which is what the flat
                    // surfaces are.
                    PlatformTaskCard(task: task, showsColumn: false)
                }
                // The dashed "add task to…" row and the empty state's offer are
                // buttons, and they sit over the surface's drop destination —
                // which is where a finger aims when it means "the bottom of this
                // list". A card released on one lands on the ground behind it
                // all the same: a button takes clicks, and a drop is not one.
                // Measured, with `GroundDropFootTests` aimed squarely at the
                // dashed row rather than at bare ground beside it.
                trailing()
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.topInset)
            .padding(.bottom, metrics.bottomInset)
        }
        // A list shorter than the space it is given does not bounce — the desk's
        // columns ask for the same thing, and here it also keeps the ground
        // still under a finger that is about to drop a card on it.
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }
}

#endif
