// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WidgetKit

/// A board's columns and how much is in each — the shape of the board without
/// the board.
///
/// Medium only. It is a row of counts: at small there is no room for more than
/// one of them, and at large the honest thing to draw would be the cards
/// themselves, which is what the column widget is.
struct BoardOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetShare.Kind.boardOverview,
            intent: BoardWidgetIntent.self,
            provider: ConfiguredTimelineProvider<BoardWidgetIntent>()
        ) { entry in
            BoardOverviewWidgetView(entry: entry)
        }
        .configurationDisplayName(
            Text("Board overview", comment: "Widget name in the gallery: a board's columns and counts")
        )
        .description(
            Text("The columns on a board, and how much is in each.",
                 comment: "What the board overview widget is for, in the widget gallery")
        )
        .supportedFamilies([.systemMedium])
    }
}

struct BoardOverviewWidgetView: View {
    let entry: ConfiguredEntry<BoardWidgetIntent>

    /// The configured board — or the first one, which is only what a widget
    /// that has never been edited shows. One whose *configured* board has
    /// been deleted shows the missing note instead: the fallback used to
    /// cover that case too, which quietly redrew a different board under the
    /// same frame and left the note unreachable.
    private var board: WidgetBoard? {
        guard let picked = entry.configuration.board else { return entry.digest.boards.first }
        return entry.digest.board(id: picked.id)
    }

    var body: some View {
        WidgetSurface(entry.digest) { _ in
            if let board {
                content(board)
            } else {
                WidgetMissingNote(
                    text: String(localized: "That board is not on this device any more.",
                                 comment: "Widget: the board it was set up with has been deleted")
                )
            }
        }
    }

    private func content(_ board: WidgetBoard) -> some View {
        // Done is left off — see `WidgetBoard.workingColumns`, which is also
        // where the count in the heading comes from, so that the tiles add up
        // to the number above them.
        let working = board.workingColumns
        return VStack(alignment: .leading, spacing: 9) {
            WidgetHeading(
                mark: .symbol(SymbolMark.resolved(board.symbol)), title: board.name,
                count: working.reduce(0) { $0 + $1.count }
            )
            if working.isEmpty {
                WidgetEmptyNote(
                    text: String(localized: "This board has no columns to work in yet.",
                                 comment: "Widget: the board it is showing holds nothing but its Done column")
                )
            } else {
                HStack(alignment: .top, spacing: 7) {
                    ForEach(working.prefix(Self.tiles)) { column in
                        ColumnTile(column: column)
                    }
                    if working.count > Self.tiles {
                        OverflowTile(extra: working.count - Self.tiles)
                    }
                }
                // The tiles take whatever height is left under the heading
                // rather than hugging their contents, which is what makes a row
                // of them read as cards rather than as labels with numbers.
                .frame(maxHeight: .infinity)
            }
        }
        .widgetURL(AppLink.url(.board(board.id)))
    }

    /// **Four across a medium tile.** Five fits arithmetically and reads as five
    /// slivers, and a name that has to be abbreviated to fit one is how a column
    /// ends up labelled "Ba". Four is one more than a seeded board has to show
    /// now that Done is off, and a board with more says so with the tile beside
    /// them rather than by shrinking the ones it can show.
    private static let tiles = 4
}

/// One column: its dot, its name, and its count.
///
/// **The full name over two lines rather than the abbreviation on one.**
/// `BoardColumn.short` exists for the "move to" control, where the room is a
/// segment of a segmented control and there is exactly one line of it. There is
/// more room than that here, and "In Progress" wrapped over two lines is a
/// better answer than "Doing" — the abbreviation is a compromise, and this tile
/// no longer has to make it.
///
/// `reservesSpace: true` is what keeps the row even: without it a tile whose
/// name fits on one line is shorter than its neighbours, and a row of cards at
/// two different heights reads as a mistake. It also means the height does not
/// change when a column is renamed.
private struct ColumnTile: View {
    @Environment(\.palette) private var palette

    let column: WidgetColumn

    var body: some View {
        Link(destination: AppLink.url(.column(column.id))) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 4) {
                    Circle()
                        .fill(palette.resolve(column.dot))
                        .frame(width: 6, height: 6)
                        // Onto the first line's centre. A dot has no baseline
                        // for `.firstTextBaseline` to find, so it would sit on
                        // the line rather than beside it.
                        .padding(.top, 3)
                    Text(column.name)
                        .font(palette.ui(10, .bold, relativeTo: .caption2))
                        .lineLimit(2, reservesSpace: true)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(palette.inkText(0.7))
                }
                Spacer(minLength: 2)
                Text(column.count.formatted())
                    .font(palette.ui(24, .bold, relativeTo: .title2))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(palette.card, in: .rect(cornerRadius: palette.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: palette.cardRadius)
                    .strokeBorder(palette.cardBorder, lineWidth: 1)
            )
        }
    }
}

/// "+2", for a board with more columns than the tile can show. It is a link to
/// the board, so the columns it stands for are one tap away rather than lost.
private struct OverflowTile: View {
    @Environment(\.palette) private var palette

    let extra: Int

    var body: some View {
        Text(extra.formatted(.number.sign(strategy: .always(includingZero: false))))
            .font(palette.ui(12, .bold, relativeTo: .caption))
            .monospacedDigit()
            .foregroundStyle(palette.inkText(0.6))
            .frame(width: 30)
            .frame(maxHeight: .infinity)
            .background(palette.wash, in: .rect(cornerRadius: palette.cardRadius))
    }
}
