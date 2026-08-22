import SwiftUI

/// A label turned on its side, reading bottom to top.
///
/// `rotationEffect` draws a view at an angle without telling the layout about
/// it: the space claimed is still the *unrotated* one. A rotated label in a
/// narrow strip therefore leaves a hole the width of the horizontal words it
/// used to be — which is the whole thing the strip exists to avoid. The size
/// has to be transposed as well as the drawing.
///
/// **A `Layout` rather than a measurement written back into `@State`**, which
/// is the obvious version and is wrong: state lands on the *next* pass, so the
/// first one draws the label into no height at all. That is a flicker in the
/// running app and a permanently flat tile anywhere layout happens once —
/// `ImageRenderer`, a snapshot, a print. `AddColumnStripTests` renders the tile
/// and measures it, which is how the `@State` version was caught; it reported
/// 38x57 for a label needing 85pt of run.
///
/// Bottom to top rather than top to bottom because that is the direction every
/// vertical axis label and sidebar tab in this platform's own apps reads.
struct VerticalText: ViewModifier {
    func body(content: Content) -> some View {
        Transposed {
            content
                // Or the words are measured against whatever the strip
                // proposed, which is a strip's width of wrapped letters.
                .fixedSize()
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Claims its content's size with the axes swapped, and puts the content in the
/// middle of it.
///
/// The content is measured unrotated — a rotation is a draw, not a layout, so
/// `sizeThatFits` still answers in the unturned axes — and it is that answer,
/// turned, that this reports upwards.
private struct Transposed: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(.unspecified)
        return CGSize(width: size.height, height: size.width)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        // Centred, because the rotation spins the content about its own centre:
        // any other anchor and the turned label walks off the strip.
        subviews.first?.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified
        )
    }
}

extension View {
    /// Turns this view on its side, reading bottom to top, and claims the space
    /// the turned version actually needs rather than the space it used to.
    func verticalText() -> some View { modifier(VerticalText()) }
}
