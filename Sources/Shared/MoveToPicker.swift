import SwiftUI

/// The segmented "Status" / "Move to" control.
///
/// The board is passed in rather than read from a global: the columns are that
/// board's, and a segment hands back a whole `TaskPlacement`, so a column can
/// never reach the caller without the board that owns it.
///
/// **Columns only — the Inbox is not one of them.** It led the segments for a
/// while, because a card that could only move between columns could leave the
/// Inbox and never return. That is no longer this control's problem to solve:
/// both surfaces that draw it draw `BoardDestinationMenu` directly above it,
/// and the Inbox is the first item in that menu. Which is the truer split
/// anyway — the menu answers *which board*, and a card in the Inbox is on none;
/// this answers *where on it*, and the Inbox is not a place on a board.
struct MoveToPicker: View {
    struct Metrics {
        var containerRadius: CGFloat
        var itemRadius: CGFloat
        var itemMinWidth: CGFloat
        /// The segment's floor. The drawn pill keeps its own height and floats
        /// in the taller band, so only the track around it grows.
        var itemHit: CGFloat
        var itemVerticalPadding: CGFloat
        var itemHorizontalPadding: CGFloat
        var font: CGFloat

        static let desk = Metrics(
            containerRadius: 10, itemRadius: 8, itemMinWidth: 62, itemHit: 0,
            itemVerticalPadding: 6, itemHorizontalPadding: 8, font: 11
        )
        static let sheet = Metrics(
            containerRadius: 12, itemRadius: 10, itemMinWidth: 72, itemHit: 44,
            itemVerticalPadding: 9, itemHorizontalPadding: 10, font: 12
        )
    }

    @Environment(\.palette) private var palette

    /// The board whose columns are offered. `nil` when there is no board at all
    /// — the user can delete the last one — and there is then nothing to offer,
    /// so the control draws nothing rather than an empty track.
    let board: Board?
    /// The task's column, or `nil` for a card in the Inbox — which is on no
    /// board, so no segment reads as current and every one of them is a way to
    /// file it.
    let currentColumnID: BoardColumn.ID?
    var metrics: Metrics = .desk
    let onSelect: (TaskPlacement) -> Void

    var body: some View {
        // Nothing to move between is not an empty track with a border round it.
        if !destinations.isEmpty {
            // The segments share the width when they fit, and fall back to a
            // scroller only when they cannot — the spec's `flex: 1 0 auto` plus
            // `overflow-x: auto`, which a plain ScrollView alone cannot express.
            // A board can carry as many columns as the user makes, so the
            // scroller is not a hypothetical.
            ViewThatFits(in: .horizontal) {
                segments(expanding: true)
                    .padding(3)
                ScrollView(.horizontal) {
                    segments(expanding: false)
                        .padding(3)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(palette.ink(0.06), in: .rect(cornerRadius: metrics.containerRadius))
        }
    }

    /// The board's columns in board order — which is the order the board itself
    /// draws them in, and was `COLS`'s.
    private var destinations: [Destination] {
        guard let board else { return [] }
        return board.columns.map {
            Destination(placement: .column(board: board.id, column: $0.id), title: $0.short)
        }
    }

    private func segments(expanding: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(destinations) { destination in
                // Matched on the column rather than on the whole placement: a
                // card opened from a saved view can be on a board other than
                // the one on screen, and comparing boards too would mark the
                // Inbox segment current for it, which is a lie about where it
                // is. Nothing reads as current instead.
                let isCurrent = destination.placement.columnID == currentColumnID
                Button { onSelect(destination.placement) } label: {
                    Text(destination.title)
                        .font(SimpleKanbanFont.ui(metrics.font, .bold, relativeTo: .caption))
                        .foregroundStyle(isCurrent ? palette.ink : palette.inkText(0.5))
                        .lineLimit(1)
                        .fixedSize(horizontal: !expanding, vertical: false)
                        .padding(.vertical, metrics.itemVerticalPadding)
                        .padding(.horizontal, metrics.itemHorizontalPadding)
                        // `min-width` in the spec is border-box, so the frame
                        // wraps the padding rather than sitting inside it.
                        .frame(minWidth: metrics.itemMinWidth, maxWidth: expanding ? .infinity : nil)
                        .background {
                            RoundedRectangle(cornerRadius: metrics.itemRadius)
                                .fill(isCurrent ? palette.card : .clear)
                                .shadow(color: isCurrent ? palette.shadow(0.16) : .clear, radius: 1.5, y: 1)
                        }
                        .frame(minHeight: metrics.itemHit)
                }
                .buttonStyle(.bare)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
    }

    /// One segment: where it sends the card, and the word on it.
    private struct Destination: Identifiable {
        let placement: TaskPlacement
        let title: String

        var id: TaskPlacement { placement }
    }
}
