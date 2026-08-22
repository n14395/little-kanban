import SwiftUI

/// The segmented "Status" / "Move to" control.
///
/// The board is passed in rather than read from a global: the columns are that
/// board's, and a segment hands back a whole `TaskPlacement`, so a column can
/// never reach the caller without the board that owns it.
///
/// The Inbox leads the segments. The spec's `COLS` — as opposed to `ALL_COLS` —
/// left it out, which on the phone, where this control is the only route a card
/// has out of a column, meant a card could leave the Inbox and never return.
/// Now that the Inbox is global it is no longer a column any board draws
/// either, so this is the route on both surfaces rather than only on one.
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
    /// — the user can delete the last one — and the Inbox is then the only
    /// destination there is, which is the honest thing to show.
    let board: Board?
    /// The task's column, or `nil` for a card in the Inbox, which is then the
    /// segment that reads as current.
    let currentColumnID: BoardColumn.ID?
    var metrics: Metrics = .desk
    let onSelect: (TaskPlacement) -> Void

    var body: some View {
        // The segments share the width when they fit, and fall back to a
        // scroller only when they cannot — the spec's `flex: 1 0 auto` plus
        // `overflow-x: auto`, which a plain ScrollView alone cannot express.
        // The Inbox added a fifth segment, so on a 375pt phone this is now the
        // scroller rather than a hypothetical.
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

    /// The Inbox first, then the board's columns in board order — which is the
    /// order the sidebar lists its destinations in, and was `ALL_COLS`'s.
    private var destinations: [Destination] {
        let columns = board.map { board in
            board.columns.map {
                Destination(placement: .column(board: board.id, column: $0.id), title: $0.short)
            }
        }
        return [Destination(placement: .inbox, title: Board.inboxName)] + (columns ?? [])
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
