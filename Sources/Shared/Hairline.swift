import SwiftUI

/// A 1pt rule on one edge — the design's `border-right: 1px solid …` seams.
/// Drawn as an overlay so it never takes part in layout.
extension View {
    func hairline(_ edge: Edge, color: Color, width: CGFloat = 1) -> some View {
        overlay(alignment: edge.alignment) {
            Rectangle()
                .fill(color)
                .frame(
                    width: edge == .leading || edge == .trailing ? width : nil,
                    height: edge == .top || edge == .bottom ? width : nil
                )
        }
    }
}

private extension Edge {
    var alignment: Alignment {
        switch self {
        case .top: .top
        case .leading: .leading
        case .bottom: .bottom
        case .trailing: .trailing
        }
    }
}
