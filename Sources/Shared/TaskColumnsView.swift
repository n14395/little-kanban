import SwiftUI

/// Sizes for ``TaskColumnsView``.
///
/// Every number here is the board's own, read off ``BoardColumnView/Metrics``
/// and ``BoardScrollView`` rather than picked again: a saved view is the same
/// cards the board draws, so a card that changed width crossing into one would
/// be saying the two surfaces are different kinds of thing. They are not — one
/// is grouped by column and the other by the filter that gathered it.
///
/// Free-standing rather than nested for ``TaskListMetrics``' reason: the view is
/// generic over its card, so a nested type could only be spelled
/// `TaskColumnsView<SomeCard>.Metrics` and nothing outside could name it.
struct TaskColumnMetrics {
    /// How wide one column is. The board's, so the cards line up.
    var columnWidth: CGFloat
    /// The gap between two columns.
    var columnSpacing: CGFloat
    /// The gap between two cards inside one.
    var cardSpacing: CGFloat
    /// The margin either side of the whole run of columns.
    var horizontalPadding: CGFloat
    var topInset: CGFloat
    var bottomInset: CGFloat

    /// `@MainActor`, and the three of them are for one reason: `BoardScrollView`
    /// is a `View`, so its `gutter` and `stripPadding` are isolated to the main
    /// actor along with it. The alternative is copying two numbers the board
    /// already owns into a second place, which is the drift these presets exist
    /// to prevent. Everything that reads one is a view body or a `@MainActor`
    /// suite already.
    @MainActor static let desk = TaskColumnMetrics(
        columnWidth: BoardColumnView.Metrics.desk.width,
        columnSpacing: BoardScrollView.gutter,
        cardSpacing: BoardColumnView.Metrics.desk.cardSpacing,
        horizontalPadding: BoardScrollView.stripPadding,
        topInset: 12,
        bottomInset: 16
    )

    @MainActor static let pad = TaskColumnMetrics(
        columnWidth: BoardColumnView.Metrics.pad.width,
        columnSpacing: BoardScrollView.gutter,
        cardSpacing: BoardColumnView.Metrics.pad.cardSpacing,
        horizontalPadding: 20,
        topInset: 12,
        bottomInset: 28
    )

    /// The phone on its side. 250 is not a new number: it is what a page of the
    /// landscape board measures — 874pt less 62 either side of the sensor
    /// housing is 750, which is three pages of 250 — so a view turned sideways
    /// asks for its cards at the width the board beside it draws them.
    ///
    /// **It is a *minimum* rather than a width**, because this is the flow that
    /// scrolls down; see ``TaskColumnsView/Flow``. A grid that scrolls down has
    /// a right-hand edge the reader can see, and columns that stopped short of
    /// it would leave a ragged strip of nothing beside every row — so the grid
    /// fits what it can at this width and then stretches them to the edge.
    ///
    /// What that comes to, measured: a 17 Pro draws **two**. 874 less the
    /// housing is 750 and less this preset's own margins is 718, which is two
    /// columns and not three — the board gets its third by spending no margin at
    /// all, and a flat surface has no column ground to stand in for one. A Pro
    /// Max, 82pt wider, draws three. Neither is told a number.
    @MainActor static let phone = TaskColumnMetrics(
        columnWidth: 250,
        columnSpacing: 10,
        cardSpacing: 10,
        horizontalPadding: 16,
        topInset: 4,
        bottomInset: 24
    )
}

/// The saved views as columns rather than as one long list.
///
/// **The app is wide, and a saved view was the one surface that answered by
/// being tall.** A board is a strip of columns; the Inbox, Today, the Archive
/// and the rest were a single 620pt-wide run of cards down the middle of a
/// window with the other two-thirds empty. The cards are the same cards — a
/// saved view has always drawn ``BoardTaskCard`` and only stretched it — so what
/// changes here is the arrangement and nothing else.
///
/// **The two flows go opposite ways, and the screen decides which.** See
/// ``Flow``: a wide surface wraps down and then across and scrolls sideways, the
/// way the board does; a phone held sideways wraps across and then down and
/// scrolls down, because 390pt of height is two cards and paging sideways
/// through columns two deep is worse than the list it replaced.
///
/// **Not a `List`.** ``TaskListView`` is one, and its doc explains why it stays
/// one: a `List` handles drags inside its own bounds, so swapping the container
/// under a surface that takes drops would change what a drop does. This surface
/// takes none — `BoardStore.allowsCardDrag` is `activeView == nil && sortOrder
/// == .manual`, so it is off in every saved view, and `ReorderableCard` reads
/// the same flag before it offers a lift. Nothing is given up by leaving.
struct TaskColumnsView<Card: View>: View {
    /// Which way the cards run, and therefore which way the surface scrolls.
    ///
    /// The two are one decision rather than two: cards that wrap downward have
    /// to be able to run off the right-hand edge, and cards that wrap across
    /// have to be able to run off the bottom. A flow that wrapped one way and
    /// scrolled the other would either clip or never wrap.
    enum Flow {
        /// Fill a column to the bottom of the window, then start the next one to
        /// the right. Reading order runs down each column. Scrolls sideways.
        case downThenAcross
        /// Fill a row left to right, then wrap to the next row down. Reading
        /// order runs across. Scrolls down.
        case acrossThenDown
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The keyboard's way of asking for a card to be brought into view. Absent
    /// on surfaces that stand this up without a board around them — a preview,
    /// a test host — which is why it is optional here and flattened below.
    @Environment(BoardFocusRelay.self) private var relay: BoardFocusRelay?

    let tasks: [TaskItem]
    var metrics: TaskColumnMetrics = .desk
    var flow: Flow = .downThenAcross
    private let card: (TaskItem) -> Card

    /// A column of rows whose type grows — see ``ChromeScale``. Capped at the
    /// board's own cap, since it is the board's own column.
    private var chrome = ChromeScale()

    init(
        tasks: [TaskItem],
        metrics: TaskColumnMetrics = .desk,
        flow: Flow = .downThenAcross,
        @ViewBuilder card: @escaping (TaskItem) -> Card
    ) {
        self.tasks = tasks
        self.metrics = metrics
        self.flow = flow
        self.card = card
    }

    var body: some View {
        switch flow {
        case .downThenAcross: sideways
        case .acrossThenDown: downwards
        }
    }

    // MARK: Down, then across

    /// The wide surfaces. A horizontal scroll view holding one custom layout,
    /// which is where the wrapping happens — see ``ColumnFlowLayout``.
    ///
    /// The height the layout packs into is the one the scroll view proposes, so
    /// resizing the window re-flows the columns rather than clipping them. That
    /// is the behaviour the request asks for in as many words: a column wraps
    /// *when there are too many items in it*, and how many is too many is a
    /// question about the window.
    private var sideways: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                ColumnFlowLayout(
                    columnWidth: chrome(metrics.columnWidth),
                    columnSpacing: metrics.columnSpacing,
                    cardSpacing: metrics.cardSpacing
                ) {
                    ForEach(tasks) { task in
                        card(task).id(task.id)
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topInset)
                .padding(.bottom, metrics.bottomInset)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: reveal) { _, reveal in
                scroll(proxy, to: reveal)
            }
        }
    }

    // MARK: Across, then down

    /// The phone on its side. A `LazyVGrid` and not the layout above, because
    /// wrapping across is exactly what a grid already does — and the lazy half
    /// is worth having on the one surface where the whole run of cards is a
    /// scroll away rather than a window away.
    ///
    /// `.adaptive` rather than a fixed count: the number of columns is whatever
    /// the width holds at ``TaskColumnMetrics/phone``'s minimum, so a Pro Max
    /// gets three where a 13 mini gets two, and neither is told a number.
    private var downwards: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: [GridItem(
                        .adaptive(minimum: chrome(metrics.columnWidth)),
                        spacing: metrics.columnSpacing,
                        alignment: .top
                    )],
                    alignment: .leading,
                    spacing: metrics.cardSpacing
                ) {
                    ForEach(tasks) { task in
                        card(task).id(task.id)
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topInset)
                .padding(.bottom, metrics.bottomInset)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: reveal) { _, reveal in
                scroll(proxy, to: reveal)
            }
        }
    }

    // MARK: Bringing a card into view

    /// Flattened, for the reason ``BoardScrollView`` gives.
    private var reveal: BoardReveal? { relay?.reveal ?? nil }

    /// A card focused by a key can be a whole screen away — off the right-hand
    /// edge here rather than off the bottom of a column — so the same request
    /// the board answers is answered here, in the same two manners. See
    /// ``BoardReveal``.
    private func scroll(_ proxy: ScrollViewProxy, to reveal: BoardReveal?) {
        guard let reveal, tasks.contains(where: { $0.id == reveal.task }) else { return }
        Motion.run(.easeOut(duration: 0.16), reduceMotion: reduceMotion) {
            switch reveal.manner {
            case .centred: proxy.scrollTo(reveal.task, anchor: .center)
            case .intoView: proxy.scrollTo(reveal.task)
            }
        }
    }
}

/// Packs its subviews into fixed-width columns, filling each one down to the
/// height it is given before starting the next to its right.
///
/// **The height has to come from outside, and it does.** Inside a horizontal
/// `ScrollView` the width proposed is unbounded and the height is the scroll
/// view's own, which is exactly the pair this needs: an unknown width to grow
/// into and a known height to wrap at.
///
/// **Every card is measured rather than assumed.** A card's height depends on
/// its title's line count, whether it carries a description, and how many chips
/// and sub-task bars it has under that — so a fixed number of cards per column
/// would be right for one board and wrong for the next. `sizeThatFits` is asked
/// of each subview at the column's width, which is also the width it will be
/// placed at, so the answer is the height it will actually draw.
struct ColumnFlowLayout: Layout {
    var columnWidth: CGFloat
    var columnSpacing: CGFloat
    var cardSpacing: CGFloat

    /// One packing, kept between the two calls SwiftUI makes with the same
    /// proposal. Measuring *n* cards is *n* layout passes of their own, and
    /// `sizeThatFits` and `placeSubviews` would otherwise each pay for a full
    /// set — which at the five hundred cards `ScaleTests` builds is the
    /// difference between a re-flow being free and being felt.
    struct Cache {
        var height: CGFloat?
        var count: Int
        var columns: [[Int]]
        var size: CGSize
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(height: nil, count: -1, columns: [], size: .zero)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        // The contents changed under us, so the packing is stale whatever the
        // proposal was.
        if cache.count != subviews.count { cache.count = -1 }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        pack(proposal: proposal, subviews: subviews, cache: &cache)
        return cache.size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
    ) {
        pack(proposal: proposal, subviews: subviews, cache: &cache)

        var x = bounds.minX
        for column in cache.columns {
            var y = bounds.minY
            for index in column {
                let height = subviews[index].sizeThatFits(
                    ProposedViewSize(width: columnWidth, height: nil)
                ).height
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: columnWidth, height: height)
                )
                y += height + cardSpacing
            }
            x += columnWidth + columnSpacing
        }
    }

    private func pack(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let available = proposal.height ?? .infinity
        guard cache.count != subviews.count || cache.height != available else { return }

        let heights = subviews.indices.map {
            subviews[$0].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
        let columns = Self.columns(of: heights, into: available, cardSpacing: cardSpacing)

        let width = columns.isEmpty
            ? 0
            : columnWidth * CGFloat(columns.count) + columnSpacing * CGFloat(columns.count - 1)
        let tallest = columns.map { column in
            column.reduce(0) { $0 + heights[$1] } + cardSpacing * CGFloat(max(0, column.count - 1))
        }.max() ?? 0

        cache.height = available
        cache.count = subviews.count
        cache.columns = columns
        // The available height rather than the tallest column, so the run of
        // columns fills the scroll view it is in — a shorter answer lets the
        // last column float in the middle of the window with the ones beside it
        // starting higher up.
        cache.size = CGSize(width: width, height: available == .infinity ? tallest : available)
    }

    /// **Where the wrapping is decided, as a function of nothing but numbers.**
    ///
    /// Split out of the layout because a `Layout`'s `Subviews` cannot be built
    /// by a test — the arithmetic would otherwise be reachable only by rendering
    /// a window and measuring it, which is how a packing rule goes wrong in one
    /// place and passes everywhere else. `ColumnFlowTests` calls this directly,
    /// the way `SidebarRoomTests` calls `PadRootView.yields(to:in:)`.
    ///
    /// Greedy, and greedy is right here: the cards are in an order the reader
    /// can see — newest filing first in the Archive, due date in Today — so a
    /// packing that balanced the columns by moving cards between them would be
    /// reordering the view to make it look tidy.
    static func columns(
        of heights: [CGFloat], into available: CGFloat, cardSpacing: CGFloat
    ) -> [[Int]] {
        var columns: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0

        for index in heights.indices {
            let needed = current.isEmpty ? heights[index] : used + cardSpacing + heights[index]
            // `!current.isEmpty` is what keeps a card taller than the window
            // from opening an empty column in front of itself and then
            // overflowing the next one anyway. One card that does not fit is a
            // card drawn past the bottom edge; a column that cannot hold it
            // *either* is a column of nothing, and then so is every column
            // after it.
            if !current.isEmpty, needed > available {
                columns.append(current)
                current = [index]
                used = heights[index]
            } else {
                current.append(index)
                used = needed
            }
        }
        if !current.isEmpty { columns.append(current) }
        return columns
    }
}
