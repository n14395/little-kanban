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
/// **A real `.sheet` held at a detent, the same as ``PhoneDetailSheet``.** It
/// was hand-rolled for a while — an overlay with a scrim, a transition, a drag
/// gesture and an offset of its own — to dodge the one thing a detent below
/// `.large` costs: the sheet is laid out at the full screen width and then
/// inset 8pt each side and scaled by `(W - 16) / W`, so a 44pt control renders
/// at about 42.2. The editor pays that knowingly and this pays it too, because
/// everything else the hand-rolled panel did was a worse copy of what the
/// system already does. What went away with the swap: the scrim and its fade,
/// the insertion and removal transitions, the live drag offset and the rule for
/// how far is far enough, the `scrollDisabled` that decided whether a pan
/// belonged to the list or to the panel, and `.isModal`. What arrived: the
/// platform's own physics — rubber banding, a flick that carries, the drag
/// handed to the list while the list can use it and taken back at the top of
/// it, and VoiceOver's cursor moved and trapped without being asked.
///
/// See **Touch targets** in the README for the two ways to have both the height
/// and the 44pt, neither of which is a smaller edit than accepting the 4%.
struct PhoneInboxSheet: View {
    struct Metrics {
        /// How much of the screen the panel takes.
        ///
        /// A fixed share rather than "as tall as its contents, up to a ceiling",
        /// which is what this wanted to be and cannot be: the list inside is
        /// `TaskListView`, `TaskListView` is a `List`, and a `List` reports no
        /// useful intrinsic height. Under `fixedSize` it collapses to nothing
        /// and the panel draws as a header over a hole; measured, that is
        /// exactly what happened. A share of the screen is what every detent on
        /// this platform is anyway.
        ///
        /// Most of the screen, with the board's own title row left showing: the
        /// Inbox is a list you work *through* — file this one, keep that one —
        /// and two thirds of a phone was four cards and a scroll for the rest.
        /// What the strip along the top buys is the thing a panel has over the
        /// page this used to be: you can still see what you left, and it is
        /// obvious that tapping it puts you back.
        var heightFraction: CGFloat
        /// The sheet's own corner radius, which is the editor's — two sheets
        /// coming up over the same board should not be different shapes.
        var cornerRadius: CGFloat
        var titleSize: CGFloat

        static let phone = Metrics(heightFraction: 0.90, cornerRadius: 28, titleSize: 19)
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock
    @AccessibilityFocusState private var isTitleFocused: Bool

    var metrics: Metrics = .phone

    /// The sheet's contents. Everything about *how* it arrives — the slide, the
    /// scrim, the drag, the corner, what a reader's cursor does — is the four
    /// presentation modifiers at the bottom and the system behind them.
    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .frame(maxWidth: .infinity)
        .background(palette.sheet)
        // The editor's presentation, to the point: same detent arithmetic, same
        // indicator, same corner, same ground. The height is this panel's own —
        // the Inbox is a list to work through and the editor is one card.
        .presentationDetents([.fraction(metrics.heightFraction)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(metrics.cornerRadius)
        .presentationBackground(palette.sheet)
        // A card tapped in here opens the editor, and the root cannot put that
        // sheet up while this one is over it — see `phoneTaskDetailSheet`.
        .phoneTaskDetailSheet()
        // The VoiceOver cursor, not the keyboard's. The system moves it into a
        // sheet on its own; this puts it on the title rather than on whatever
        // the first element happens to be. `PhoneNavDrawer` has the long version
        // of why the two are different focuses.
        .onAppear { isTitleFocused = true }
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
            // Named as well as labelled: the editor's × is called Close too,
            // and once a card in here can raise that sheet over this one, both
            // are on screen at the same time. `InboxToggle` in the toolbar was
            // added for the same collision, one floor up.
            .accessibilityIdentifier("InboxClose")
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
    /// The list is what fills the sheet and what scrolls in it; the header
    /// above it does not go anywhere — and the drag indicator over that is the
    /// system's, drawn by `presentationDragIndicator`.
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
