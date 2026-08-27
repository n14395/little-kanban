import SwiftUI

/// Wraps subviews onto as many lines as they need — the equivalent of the
/// design's `display: flex; flex-wrap: wrap` label rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat?

    private var verticalSpacing: CGFloat { lineSpacing ?? spacing }

    /// One packing, kept between the calls SwiftUI makes with the same width —
    /// ``ColumnFlowLayout/Cache``'s bargain, at chip scale. Without it,
    /// `sizeThatFits` measured every chip, `placeSubviews` measured them all
    /// again to re-pack, and then a third time to place — and SwiftUI asks
    /// `sizeThatFits` more than once per pass besides, so a card with four
    /// label chips paid a dozen text measurements per layout.
    ///
    /// Dropped whenever the subviews change at all (see `updateCache`), not
    /// just when their count does: a renamed label changes a chip's width
    /// without changing how many there are, and a wrap packed from the old
    /// width would break lines in the wrong place.
    struct Cache {
        var width: CGFloat?
        var isStale: Bool
        var rows: [Row]
        var sizes: [CGSize]
        var size: CGSize
    }

    struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(width: nil, isStale: true, rows: [], sizes: [], size: .zero)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.isStale = true
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        pack(maxWidth: proposal.width ?? .infinity, subviews: subviews, cache: &cache)
        return cache.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        pack(maxWidth: bounds.width, subviews: subviews, cache: &cache)
        var y = bounds.minY
        for row in cache.rows {
            var x = bounds.minX
            for index in row.indices {
                let size = cache.sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func pack(maxWidth: CGFloat, subviews: Subviews, cache: inout Cache) {
        guard cache.isStale || cache.width != maxWidth else { return }
        let sizes = subviews.indices.map { subviews[$0].sizeThatFits(.unspecified) }
        let rows = layout(sizes: sizes, maxWidth: maxWidth)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height }
            + verticalSpacing * CGFloat(max(0, rows.count - 1))
        cache.width = maxWidth
        cache.isStale = false
        cache.rows = rows
        cache.sizes = sizes
        cache.size = CGSize(
            width: min(width, maxWidth == .infinity ? width : maxWidth), height: height
        )
    }

    private func layout(sizes: [CGSize], maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for (index, size) in sizes.enumerated() {
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, needed > maxWidth {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
