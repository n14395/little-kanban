import SwiftUI

/// The segmented "Status" / "Move to" control. Lists the workflow columns only —
/// a task can be moved out of Inbox but never back into it from here, which is
/// what the spec's `COLS` (as opposed to `ALL_COLS`) encodes.
struct MoveToPicker: View {
    struct Metrics {
        var containerRadius: CGFloat
        var itemRadius: CGFloat
        var itemMinWidth: CGFloat
        var itemVerticalPadding: CGFloat
        var itemHorizontalPadding: CGFloat
        var font: CGFloat

        static let desk = Metrics(
            containerRadius: 10, itemRadius: 8, itemMinWidth: 62,
            itemVerticalPadding: 6, itemHorizontalPadding: 8, font: 11
        )
        static let sheet = Metrics(
            containerRadius: 12, itemRadius: 10, itemMinWidth: 72,
            itemVerticalPadding: 9, itemHorizontalPadding: 10, font: 12
        )
    }

    @Environment(\.palette) private var palette

    let currentColumnID: BoardColumn.ID
    var metrics: Metrics = .desk
    let onSelect: (BoardColumn) -> Void

    var body: some View {
        // The four segments share the width when they fit, and fall back to a
        // scroller only when they cannot — the spec's `flex: 1 0 auto` plus
        // `overflow-x: auto`, which a plain ScrollView alone cannot express.
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

    private func segments(expanding: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(BoardColumn.workflow) { column in
                let isCurrent = column.id == currentColumnID
                Button { onSelect(column) } label: {
                    Text(column.short)
                        .font(SimpleKanbanFont.ui(metrics.font, .bold, relativeTo: .caption))
                        .foregroundStyle(isCurrent ? palette.ink : palette.ink(0.5))
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
                }
                .buttonStyle(.bare)
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
            }
        }
    }
}
