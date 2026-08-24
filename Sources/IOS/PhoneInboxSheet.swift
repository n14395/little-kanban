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
/// **On its side it is not a sheet at all.** A sheet in a compact height
/// ignores its detent and is laid out at the whole screen, so a phone turned
/// sideways drew this as a full-screen list with cards stretched 874pt across —
/// thicker turned than upright, which is the wrong way round for a panel that
/// is meant to be *over* something. Sizing the panel fixed the panel and not
/// what it stood on: a sheet that covers the screen has the view that presented
/// it taken out of the hierarchy underneath, so the board is not behind it and
/// cannot be put there. Measured three ways — a clear presentation background,
/// the app's own ground painted behind the panel, and
/// `presentationBackgroundInteraction(.enabled)`, which sounds like it should
/// keep the presenter alive and does not — what is behind a compact-height
/// sheet is the bare window: white in light and black in dark. A scrim over
/// that is not a wash but a slab, and the panel was standing in a hole.
///
/// So on its side this is an overlay of `PhoneRootView`'s instead, which is the
/// shape ``PhoneNavDrawer`` already has: a scrim with the live board under it,
/// and the panel over that — no wider than the screen's short edge, which is
/// that phone's own portrait width held either way up, and standing on the
/// bottom edge as a card. See ``panel`` for the arithmetic.
///
/// What that costs is the two things the sheet was doing for nothing, and both
/// are hand-rolled here: ``grabber`` carries the pull that puts the panel away,
/// and `.isModal` keeps a reader inside it. **Upright, nothing changed** — it is
/// a real sheet at a detent, and everything above about what a sheet gives is
/// still true there.
///
/// See **Touch targets** in the README for the two ways to have both the height
/// and the 44pt, neither of which is a smaller edit than accepting the 4%.
struct PhoneInboxSheet: View {
    struct Metrics {
        /// How much of the screen the panel takes.
        ///
        /// A fixed share rather than "as tall as its contents, up to a ceiling",
        /// which is what this wanted to be and cannot be: the list inside was
        /// `TaskListView`, `TaskListView` is a `List`, and a `List` reports no
        /// useful intrinsic height. Under `fixedSize` it collapses to nothing
        /// and the panel draws as a header over a hole; measured, that is
        /// exactly what happened. It is ``PhoneCardStack`` now and a scroll view
        /// answers that question no better — it takes whatever it is offered —
        /// and a share of the screen is what every detent on this platform is
        /// anyway. The height wants the space around the cards regardless:
        /// that space is where a card arriving from elsewhere lands.
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
    /// The phone on its side, which is the one thing about this panel that the
    /// shape of the screen decides. Read here rather than handed in, because a
    /// sheet is its own presentation: it takes the environment from whatever
    /// put it up, and the trait it needs is the one it is drawn in.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isTitleFocused: Bool
    /// How far the panel has been pulled down, in points, while a finger is on
    /// ``grabber``. Only ever a positive number: a panel dragged upwards has
    /// nowhere to go.
    @State private var pushedDown: CGFloat = 0

    var metrics: Metrics = .phone
    /// The window, both dimensions of it, handed down by whoever put this up.
    ///
    /// The panel is capped at the screen's short edge and neither shape can work
    /// that out from the height it is given: inside a sheet the height arrives
    /// short by the home indicator, and inside an overlay it arrives short by
    /// the safe area on every side. `PhoneRootView` measures the window outside
    /// all of that once — `PhoneNavDrawer` reads the same number for the same
    /// reason — so 402 is 402 either way up and in either shape.
    var screen: CGSize = .zero

    /// Lit while a card is over the panel — ``BoardStore/isInboxDropTarget``,
    /// which the desk's panel sets too, and for the reason it lives on the store
    /// rather than in here: a drop destination nested inside another takes the
    /// hover from its parent, so the flag has to be readable from a card's own
    /// zone. `draggingID` guards it the way every other highlight is guarded — a
    /// flag left true by a drop that went elsewhere would leave the sheet tinted
    /// with nothing over it.
    private var isDropTarget: Bool { store.isInboxDropTarget && store.draggingID != nil }

    /// What this is. Everything about *how* it arrives — the slide, the dimming,
    /// the drag, the corner, what a reader's cursor does — is the presentation
    /// modifiers below and the system behind them upright, and the overlay's own
    /// scrim, transition and gesture on its side; how big it is drawn and where
    /// it stands is ``panel``, which is one piece of arithmetic for both.
    ///
    /// The modifiers are applied to the one shape they mean something in rather
    /// than being handed a value that turns them off. They used to read
    /// `isShort ? .hidden : .visible` and `opacity(isShort ? 0 : 1)`, which is
    /// how a view says *I am two things and one of them is wearing the other's
    /// clothes*.
    var body: some View {
        Group {
            if isShort {
                // What the sheet was giving and the overlay is not: a reader let
                // into the panel and kept there. `PhoneRootView` hides the bars
                // behind it, and cannot reach the list's own cells — the drawer
                // has the long version of why that is not enough on its own.
                //
                // And the panel gets out of the way of anything raised over it,
                // which the sheet also used to do for nothing: a card opened
                // from in here puts the editor up, and while this was a sheet
                // UIKit covered it and took it out of the tree. As an overlay it
                // is a sibling of the window's own content rather than something
                // underneath a presentation — measured, both the panel's × and
                // the editor's were reachable at once, and both are labelled
                // Close.
                panel
                    .accessibilityAddTraits(.isModal)
                    .accessibilityHidden(store.sheetID != nil)
            } else {
                panel
                    // The editor's presentation, to the point: same detent
                    // arithmetic, same indicator, same corner, same ground. The
                    // height is this panel's own — the Inbox is a list to work
                    // through and the editor is one card.
                    .presentationDetents([.fraction(metrics.heightFraction)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(metrics.cornerRadius)
                    .presentationBackground(palette.windowFill)
            }
        }
        // A card tapped in here opens the editor. Upright the root cannot put
        // that sheet up while this one is over it — see `phoneTaskDetailSheet` —
        // and on its side this is a view in the root's own hierarchy, so the
        // presentation lands over the overlay either way.
        .phoneTaskDetailSheet()
        // **The panel comes down when the card it has open leaves the Inbox.**
        //
        // The other direction already reads this way and is where the idea came
        // from: file a card *to* the Inbox from the editor's Move to menu and
        // `showPlace` raises this panel, so the editor drops, the Inbox slides
        // up, and the editor comes back over it — you watch the card arrive
        // somewhere. Going the other way said nothing at all. `showPlace`
        // selected the board and set the pager's column exactly as it should,
        // and every one of those changes happened *behind a modal panel* still
        // showing the list the card had just left, with the editor on top of
        // that. The only thing that moved on screen was the pill's own label.
        //
        // So the panel takes itself down, and the sequence mirrors the one that
        // works: the editor drops with this sheet, the board it was sent to is
        // uncovered with the right column already paged to, and the root puts
        // the editor back up over it — see `PhoneRootView`, where the root's
        // copy of the editor sheet is held back by `isInboxOpen` and is
        // released by exactly this.
        //
        // **On the phone and nowhere else**, which is why it is here rather than
        // in `showPlace`. The iPad's Inbox is a panel that stands *beside* the
        // board rather than over it: a card filed from there is visible on the
        // board the moment it moves, and closing a panel the user deliberately
        // opened would be taking something away for no reason. The store cannot
        // tell the two apart — `isInboxOpen` is one flag meaning two shapes —
        // and this view is only ever built on the phone.
        .onChange(of: store.sheetTask?.isUnfiled) { wasUnfiled, isUnfiled in
            // Only the crossing, and only outwards. `nil` on either side is the
            // editor opening or closing rather than a card moving.
            guard wasUnfiled == true, isUnfiled == false else { return }
            store.isInboxOpen = false
        }
        // The VoiceOver cursor, not the keyboard's. The system moves it into a
        // sheet on its own; this puts it on the title rather than on whatever
        // the first element happens to be. `PhoneNavDrawer` has the long version
        // of why the two are different focuses.
        .onAppear { isTitleFocused = true }
    }

    private var isShort: Bool { verticalSizeClass == .compact }

    /// Where the panel is and how big — the whole of what turning the phone
    /// changes.
    ///
    /// **No thicker on its side than it is upright.** A sheet in a compact
    /// height ignores its detent and is laid out at the full screen, so the
    /// Inbox turned sideways was a full-screen page with cards stretched 874pt
    /// across. The cap is the *short edge* of what the sheet is offered, which
    /// is that phone's own portrait width held either way up:
    /// `PhoneNavDrawer.width(in:screen:)` sizes the board list by the same rule
    /// and for the same reason, and upright the short edge *is* the width — so
    /// this is one line that reads the same in both shapes rather than a
    /// branch. Nothing here is a fixed maximum, because the number that must
    /// not be exceeded is that phone's own portrait width and no other.
    ///
    /// The height is the same share of the screen either way, which upright is
    /// what the detent has already done and on its side is this: the panel is
    /// stood on the bottom edge and the board's own title row is left showing
    /// above it, which is the strip the ``Metrics/heightFraction`` note is
    /// about.
    private var panel: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if isShort {
                    ground
                    // The drawer's pattern, and for the drawer's reason: a scrim
                    // and the thing it is under do not arrive the same way. One
                    // fades in over what it is covering; the other comes in from
                    // an edge.
                    .transition(.opacity)
                }
                contents
                    .frame(
                        width: Self.width(in: proxy, screen: screen),
                        height: proxy.size.height * (isShort ? metrics.heightFraction : 1)
                    )
                    // The corner the system rounds the sheet by, drawn on the
                    // panel itself. Upright that is the same curve in the same
                    // place and so costs nothing; on its side it is the only one
                    // there is, the sheet behind it being clear — and all four
                    // of them, because there the panel is a card standing clear
                    // of the bottom edge rather than a sheet fixed to it. The
                    // gap under it is the home indicator's own strip, which is
                    // where a floating panel leaves it.
                    .clipShape(
                        .rect(
                            topLeadingRadius: metrics.cornerRadius,
                            bottomLeadingRadius: isShort ? metrics.cornerRadius : 0,
                            bottomTrailingRadius: isShort ? metrics.cornerRadius : 0,
                            topTrailingRadius: metrics.cornerRadius
                        )
                    )
                    // Where the finger has it. Zero except during a pull, and
                    // not put back at the end of one that dismisses: the panel
                    // leaves from wherever it was let go of, and snapping it
                    // home first would be the panel jumping up to slide down.
                    .offset(y: pushedDown)
                    .transition(.move(edge: .bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// How wide the panel is drawn: the screen's short edge, which is that
    /// phone's own portrait width held either way up.
    ///
    /// The screen is the measured window where there is one. The fallback puts
    /// it back together out of what the proxy has, which is the same sum with a
    /// worse view of it: inside a sheet the height arrives short by the home
    /// indicator — 381 is not this phone's portrait width, 402 is — and inside
    /// an overlay the safe area is gone from every side. It is here for a
    /// preview and a first frame rather than for the app, which measures.
    private static func width(in proxy: GeometryProxy, screen: CGSize) -> CGFloat {
        let insets = proxy.safeAreaInsets
        let measured = min(screen.width, screen.height)
        guard measured <= 0 else { return measured }
        return min(
            proxy.size.width + insets.leading + insets.trailing,
            proxy.size.height + insets.top + insets.bottom
        )
    }

    /// What the panel stands on when the phone is on its side: the drawer's
    /// scrim, over the board it is really covering, and a tap on it puts the
    /// panel away.
    ///
    /// **A scrim is only a scrim if something is behind it.** While this shape
    /// was a sheet, the same `palette.scrim()` was laid over the bare window —
    /// see this type's note — and came out a grey field in light and a black one
    /// in dark, because a wash over nothing is not a wash but a slab. Nothing
    /// about the colour changed to fix that: what changed is that there is a
    /// board under it now.
    ///
    /// The tap is ours because the overlay has no system dismissal of its own,
    /// which is the drawer's arrangement exactly. Hidden from a reader, who has
    /// the × in the header.
    private var ground: some View {
        palette.scrim()
            .ignoresSafeArea()
            .contentShape(.rect)
            .onTapGesture { store.isInboxOpen = false }
            .accessibilityHidden(true)
    }

    /// The handle the system draws upright, drawn by us on its side — and doing
    /// the job it advertises, which is the harder half.
    ///
    /// A capsule at the top of a panel that comes up from the bottom says *pull
    /// me down*, and the overlay has no system gesture to make that true. The
    /// pull is here rather than on the panel because the panel is mostly a
    /// scroll view: a drag over the cards belongs to the list, and a sheet
    /// arbitrates that for itself where an overlay would have to be told. The
    /// handle is the one strip of the panel that has nothing else to do with a
    /// finger.
    ///
    /// The capsule is 5pt tall and the strip around it is 28, because a target
    /// the size of the thing drawn is a target nobody hits.
    private var grabber: some View {
        Capsule()
            .fill(palette.ink(0.18))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(.rect)
            .gesture(pull)
            .accessibilityHidden(true)
    }

    /// Far enough down to mean it, in points. A quarter of the panel would be
    /// the sheet's own rule and is the wrong one here: this panel is 90% of a
    /// landscape phone, so a quarter of it is most of a thumb's travel.
    private static let dismissReach: CGFloat = 80
    /// And fast enough to mean it regardless of how far it came, which is how
    /// every panel on this platform reads a flick. `PhoneRootView.drawerFlick`
    /// is the same number for the same gesture turned 90°.
    private static let dismissFlick: CGFloat = 350

    private var pull: some Gesture {
        DragGesture(minimumDistance: 4)
            // Downwards only. A panel already standing on the bottom edge has
            // nowhere to be dragged up to, and rubber-banding it would be
            // offering a direction that does nothing.
            .onChanged { pushedDown = max(0, $0.translation.height) }
            .onEnded { drag in
                guard pushedDown > Self.dismissReach || drag.velocity.height > Self.dismissFlick
                else {
                    Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
                        pushedDown = 0
                    }
                    return
                }
                store.isInboxOpen = false
            }
    }

    /// The panel itself: its header, its cards, its ground, and the whole of it
    /// a place a card can be dropped.
    private var contents: some View {
        VStack(spacing: 0) {
            if isShort { grabber }
            header
            list
        }
        // Both directions, because on its side the panel is given a frame
        // rather than filling a detent, and a `VStack` asked for a height it
        // does not need would leave its ground short of the corner.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The tint goes *over* the ground rather than replacing it: the ground
        // is the theme's gradient now, and a flat accent wash in its place would
        // make the panel change shape as well as colour under a card.
        .background { palette.windowFill.overlay(isDropTarget ? palette.accent.opacity(0.07) : .clear) }
        // Most of a panel is the space around its cards, and empty space is hit
        // tested only where something has said what shape it is.
        .contentShape(.rect)
        // **The whole panel takes a card, not just the rows in it.** The same
        // destination `InboxPanel` hangs around the desk's Inbox, and the same
        // call: the ground names no gap, so the card lands at the foot, and
        // `drop(_:onGroundOf:)` refuses a card already in the Inbox rather than
        // spending a ⌘Z on a card that has not gone anywhere.
        .dropDestination(for: TaskTransfer.self) { items, _ in
            store.isInboxDropTarget = false
            guard store.allowsCardDrag, let dropped = items.first, store[dropped.id] != nil
            else { return false }
            store.drop(dropped.id, onGroundOf: .inbox)
            return true
        } isTargeted: { targeted in
            if store.allowsCardDrag { store.isInboxDropTarget = targeted }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(Board.inboxName)
                .font(palette.display(metrics.titleSize))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
            CountPill(count: store.inboxCount, font: 12)
            Spacer(minLength: 0)
            Button { store.isInboxOpen = false } label: {
                Image(systemName: "xmark")
                    .font(palette.ui(12, .semibold, relativeTo: .footnote))
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

    /// The cards, in ``PhoneCardStack`` — the board pages' container, and the
    /// desk panel's, for the reason both of them are in it: the Inbox is a place
    /// a card can be put, and a `List` keeps every drop inside its own bounds.
    /// It was `TaskListView` here until the rows in it could neither be
    /// rearranged by dragging nor land a card arriving from anywhere else.
    ///
    /// The stack is what fills the sheet and what scrolls in it; the header
    /// above it does not go anywhere — and the drag indicator over that is the
    /// system's, drawn by `presentationDragIndicator`.
    private var list: some View {
        // One filter-and-sort, not two: `inboxTasks` walks the whole board on
        // every access.
        let tasks = store.inboxTasks
        return PhoneCardStack(tasks: tasks, metrics: .sheet) {
            if tasks.isEmpty {
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
                .font(palette.ui(13.5, .bold, relativeTo: .subheadline))
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
