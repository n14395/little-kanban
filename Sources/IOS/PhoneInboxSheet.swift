#if os(iOS)

import SwiftUI

/// The Inbox on the phone: a panel that comes up from the bottom, over whatever
/// is there.
///
/// **It was a tab.** The Inbox is global — a card is in it by being on no board
/// — and it is the list you reach for *while* working on a board, which is
/// exactly what a tab is bad at: going to it meant leaving the board, and coming
/// back meant remembering which board you were on. The desk and the iPad answer
/// that with a panel beside the board. A phone has nothing to put a panel
/// beside, so this one goes over the top and takes the height it needs.
///
/// **Hand-rolled rather than a `.sheet` with detents**, and for a measured
/// reason rather than a stylistic one. A sheet held at any detent below `.large`
/// floats inset from the screen edges on this OS and is *scaled* to compensate —
/// 0.9602 on a 402pt-wide phone — so every 44pt control inside it lands at
/// 42.25pt, under the touch minimum, and the factor differs per device so no
/// amount of padding buys it back. `PhoneDetailSheet` gave up its 82% height to
/// that and takes `.large`. This panel wants to be *short*, so it is a
/// `PhoneNavDrawer`-shaped overlay instead: a scrim, a transition, and
/// `.isModal` — the drawer's own answer, rotated a quarter turn.
struct PhoneInboxSheet: View {
    struct Metrics {
        /// How much of the screen the panel takes.
        ///
        /// A fixed share rather than "as tall as its contents, up to a ceiling",
        /// which is what this wanted to be and cannot be: the list inside is
        /// `TaskListView`, and `TaskListView` is a `List` — for `swipeActions`,
        /// which no hand-rolled scroll view offers — and a `List` reports no
        /// useful intrinsic height. Under `fixedSize` it collapses to nothing
        /// and the panel draws as a header over a hole; measured, that is
        /// exactly what happened. A share of the screen is what every detent on
        /// this platform is anyway.
        ///
        /// Two thirds: room for four cards, and short enough that the board it
        /// came up over is still legible above it — which is the whole reason
        /// this is a panel rather than the page it used to be.
        var heightFraction: CGFloat
        var cornerRadius: CGFloat
        var titleSize: CGFloat

        static let phone = Metrics(heightFraction: 0.66, cornerRadius: 24, titleSize: 19)
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock
    @AccessibilityFocusState private var isTitleFocused: Bool

    var metrics: Metrics = .phone

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.ink(0.3)
                .ignoresSafeArea()
                .onTapGesture { store.isInboxOpen = false }
                .transition(.opacity)
                // The scrim is the panel's ground, not a control — see
                // `PhoneNavDrawer`, which makes the same claim about its own.
                .accessibilityHidden(true)

            panel
                .containerRelativeFrame(.vertical, alignment: .bottom) { height, _ in
                    height * metrics.heightFraction
                }
                .transition(.move(edge: .bottom))
                // The VoiceOver cursor, not the keyboard's. `PhoneNavDrawer`
                // has the long version of why the two are different focuses.
                .onAppear { isTitleFocused = true }
        }
        // What actually keeps a reader inside the panel: `PhoneRootView`'s
        // `accessibilityHidden` takes the bars behind it out of the tree but
        // cannot reach the list's cells, so without this every card on the board
        // under the scrim is still reachable by swiping past the last row here.
        .accessibilityAddTraits(.isModal)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            grabber
            header
            list
        }
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: metrics.cornerRadius, topTrailingRadius: metrics.cornerRadius
            )
            .fill(palette.sheet)
            .shadow(color: palette.shadow(0.28), radius: 18, y: -6)
            .ignoresSafeArea(edges: .bottom)
        }
        // Dragged down to dismiss, which is what the grabber promises and the
        // one gesture anybody tries on a panel with one drawn on it. Only
        // downwards counts: there is nowhere further up for it to go.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { drag in
                    guard drag.translation.height > 60 else { return }
                    store.isInboxOpen = false
                }
        )
    }

    /// The handle every bottom sheet on this platform draws, so the panel says
    /// it can be dragged before anybody tries.
    private var grabber: some View {
        Capsule()
            .fill(palette.ink(0.18))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(Board.inboxName)
                .font(SimpleKanbanFont.serif(metrics.titleSize))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
            CountPill(count: store.inboxCount, font: 12)
            Spacer(minLength: 0)
            Button { store.isInboxOpen = false } label: {
                Image(systemName: "xmark")
                    .font(SimpleKanbanFont.ui(12, .semibold, relativeTo: .footnote))
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.inkText(0.55))
                    .frame(minWidth: 28, minHeight: 28)
                    .background(palette.ink(0.07), in: .circle)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bare)
            .contentShape(.circle)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, TaskListMetrics.sheet.horizontalPadding)
        .padding(.bottom, 6)
    }

    /// The same flat list of cards every other surface draws — `TaskListView`,
    /// not a second list — with the Inbox's own add row under it.
    ///
    /// **No column chips.** Every card in here is unfiled and the chip for an
    /// unfiled card names the Inbox, so the whole list would read "INBOX" under
    /// a panel titled Inbox. That is the argument `showsMobileColumnChips`
    /// makes about the board, from the other end.
    ///
    /// The list is what fills the panel and what scrolls in it; the grabber and
    /// the header above it do not go anywhere.
    private var list: some View {
        TaskListView(tasks: store.inboxTasks, metrics: .sheet, showsColumn: false) {
            if store.inboxTasks.isEmpty {
                EmptyStateView.inbox(metrics: .sheet, add: add)
            } else {
                // The empty state carries the same offer, so the dashed row
                // under it would be a second copy of the first — the rule the
                // board's list follows.
                addRow
            }
        }
    }

    private var addRow: some View {
        Button(action: add) {
            Text("+ Add task to \(Board.inboxName)")
                .font(SimpleKanbanFont.ui(13.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.inkText(0.45))
                .frame(maxWidth: .infinity)
                .padding(14)
                .frame(minHeight: 44)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            palette.ink(0.18),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                }
        }
        .buttonStyle(.bare)
    }

    /// Straight to `.inbox` rather than through `mobileAddPlacement`, which
    /// answers for the board behind this panel. A card added here is added
    /// *here*.
    private func add() {
        store.addTask(to: .inbox, title: "", fromPhone: true)
    }
}

#endif
