import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

/// Where a column of a saved view stops and the next one starts.
///
/// **A value test because the wrapping is arithmetic**, and because the only
/// other way to reach it is to render a window and measure what came out — which
/// is how a packing rule goes wrong on one screen and passes on every other.
/// `ColumnFlowLayout.columns(of:into:cardSpacing:)` is split out of the `Layout`
/// for exactly this: a `Layout`'s `Subviews` cannot be built by a test, so the
/// decision is a function of `[CGFloat]` and the layout is what measures them.
/// The same arrangement `SidebarRoomTests` has with `yields(to:in:)`.
///
/// The heights here are cards: 110 is a title and a due chip, 60 a bare title,
/// 240 one with a description and a checklist.
@MainActor
@Suite struct ColumnFlowTests {
    private let spacing: CGFloat = 8

    private func columns(_ heights: [CGFloat], into available: CGFloat) -> [[Int]] {
        ColumnFlowLayout.columns(of: heights, into: available, cardSpacing: spacing)
    }

    /// Four 110pt cards and three 8pt gaps is 464, so 470 holds them and 460
    /// does not — and what will not fit goes to the top of the next column
    /// rather than being dropped or squeezed.
    @Test func aColumnTakesWhatFitsAndTheRestStartsTheNext() {
        #expect(columns([110, 110, 110, 110], into: 470) == [[0, 1, 2, 3]])
        #expect(columns([110, 110, 110, 110], into: 460) == [[0, 1, 2], [3]])
    }

    /// **The gaps are counted, and only the ones that exist.** A column of *n*
    /// cards has *n − 1* of them: counting one per card makes the last column
    /// wrap a card early, which is the off-by-one that looks like the layout
    /// merely being cautious.
    @Test func theGapsCountedAreTheGapsBetween() {
        // Exactly two cards and the one gap between them.
        #expect(columns([100, 100], into: 208) == [[0, 1]])
        // A point less, and the second card cannot be in the same column.
        #expect(columns([100, 100], into: 207) == [[0], [1]])
    }

    /// **A card taller than the window still gets drawn.** It overflows its
    /// column, which is a card running past the bottom edge; opening a fresh
    /// column in front of it would be a column holding nothing, and the card
    /// would overflow the next one just the same.
    ///
    /// The card *after* it starts a column of its own rather than being stranded
    /// beside it — the bug this asks about is a run of oversized cards each
    /// pushing an empty column ahead of itself.
    @Test func aCardTallerThanTheWindowIsDrawnRatherThanDropped() {
        #expect(columns([900], into: 400) == [[0]])
        #expect(columns([900, 100], into: 400) == [[0], [1]])
        #expect(columns([900, 900], into: 400) == [[0], [1]])
    }

    /// Before the first layout pass there is no height to wrap at, and an
    /// unbounded proposal has to read as *one column* rather than as a column
    /// per card: the second is what a `.infinity` compared the wrong way round
    /// produces, and it draws every card in its own column across a mile of
    /// scroll.
    @Test func anUnboundedHeightIsOneColumn() {
        #expect(columns([110, 110, 110, 110], into: .infinity) == [[0, 1, 2, 3]])
    }

    /// Nothing in is nothing out — not one empty column, which would draw a
    /// column's width of ground with no cards on it beside the empty state.
    @Test func noCardsIsNoColumns() {
        #expect(columns([], into: 800).isEmpty)
    }

    /// **The invariant, over a range of window heights**: every card is placed
    /// exactly once, and the reading order is unchanged. A saved view is sorted
    /// — newest filing first in the Archive, due date in Today — so a packing
    /// that balanced its columns by moving a card between them would be
    /// reordering the view to make it look tidy.
    @Test(arguments: [200.0, 320, 470, 700, 900, 1400] as [CGFloat])
    func everyCardIsPlacedOnceAndInOrder(height: CGFloat) {
        let heights: [CGFloat] = [110, 60, 240, 110, 110, 60, 180, 90, 110, 300, 60, 110]
        let flattened = columns(heights, into: height).flatMap { $0 }

        #expect(flattened == Array(heights.indices),
                "the cards came out reordered or repeated at \(height)pt")
    }

    /// And a taller window never needs more columns than a shorter one, which is
    /// the property that makes resizing feel like resizing: drag the window down
    /// and the columns multiply, drag it back and they gather up again.
    @Test func atallerWindowNeverNeedsMoreColumns() {
        let heights: [CGFloat] = [110, 60, 240, 110, 110, 60, 180, 90, 110, 300]
        let counts = [200.0, 320, 470, 700, 900, 1400].map { columns(heights, into: $0).count }

        #expect(counts == counts.sorted(by: >),
                "the column count did not fall as the window grew: \(counts)")
    }
}

/// The phone's half, which wraps the other way.
///
/// There is no packing to check — `LazyVGrid` does the wrapping — so what is
/// left is the number the grid is handed, and the reason it is a *minimum*
/// rather than a width.
@MainActor
@Suite struct PhoneColumnMetricTests {
    /// A landscape page of the phone's board measures 250: 874 less 62 either
    /// side of the sensor housing is 750, which is three of them. A saved view
    /// turned sideways asks for its cards at that same width, so the two
    /// surfaces do not disagree about how wide a card is on one phone.
    @Test func theSidewaysGridIsTheLandscapeBoardsOwnPage() {
        #expect(TaskColumnMetrics.phone.columnWidth == 250)
        // Narrower than either pointer surface's column, because the screen is.
        #expect(TaskColumnMetrics.phone.columnWidth < TaskColumnMetrics.pad.columnWidth)
    }

    /// **What the minimum actually buys, on the two phones it is drawn on** —
    /// and the reason it is stated here rather than assumed: the number came
    /// from the board, and the board spends no horizontal margin where this
    /// surface spends 16 either side. Two columns on a 17 Pro, three on a Pro
    /// Max. Screenshotted on the 17 Pro in landscape: two.
    @Test func theHousingAndTheMarginsDecideHowManyFit() {
        let metrics = TaskColumnMetrics.phone
        let margins = metrics.horizontalPadding * 2

        // `LazyVGrid(.adaptive(minimum:))` fits n where n*minimum + (n-1)*spacing
        // is within the width it is given.
        func fits(_ width: CGFloat) -> Int {
            let usable = width - margins
            var count = 1
            while CGFloat(count + 1) * metrics.columnWidth
                + CGFloat(count) * metrics.columnSpacing <= usable { count += 1 }
            return count
        }

        // 874 and 956 less 62 either side of the sensor housing.
        #expect(fits(874 - 124) == 2)
        #expect(fits(956 - 124) == 3)
        // And upright there is room for exactly one, which is the list this
        // surface is not drawn as in that orientation.
        #expect(fits(402) == 1)
    }

    /// No room left under the last card for a bar that is not there: turned on
    /// its side the phone draws its tab bar in the header, so the 130pt
    /// `TaskListMetrics.sheet` leaves for a floating one would be a third of the
    /// screen spent on nothing.
    @Test func theSidewaysGridLeavesNoRoomForTheFloatingBar() {
        #expect(TaskColumnMetrics.phone.bottomInset < TaskListMetrics.sheet.bottomInset)
        #expect(TaskColumnMetrics.phone.bottomInset > 0)
    }
}
