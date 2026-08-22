import SwiftUI

/// The row of swatches a board's or a column's dot is chosen from.
///
/// Both surfaces recolour the same property from the same six `Board.dots`, and
/// drawing that twice is how the desk ended up with a 26pt target: the numbers
/// are what differ, so the numbers are what is passed. Each swatch is announced
/// by its colour's name rather than its position, which is the only thing that
/// tells one from another without seeing it.
struct DotPicker: View {
    struct Metrics {
        /// The drawn circle, which the ring sits outside and the target around.
        var dot: CGFloat
        /// Between the circle and its ring.
        var ringGap: CGFloat
        var ringWidth: CGFloat
        var spacing: CGFloat
        /// The square a swatch claims. Touch needs 44 whatever the circle
        /// measures; the pointer preset claims what it draws.
        var hitSize: CGFloat
        var showsHover: Bool

        static let desk = Metrics(
            dot: 14, ringGap: 3, ringWidth: 1.5, spacing: 4, hitSize: 26, showsHover: true
        )
        // Six 44pt targets and any gap between them do not both fit a 375pt
        // phone, so the squares tile edge to edge — `AccentPicker.Metrics.drawer`
        // makes the same trade for the same reason.
        static let sheet = Metrics(
            dot: 20, ringGap: 4, ringWidth: 2, spacing: 0, hitSize: 44, showsHover: false
        )
    }

    @Environment(\.palette) private var palette

    let current: SwatchColor
    var metrics: Metrics = .desk
    let onSelect: (SwatchColor) -> Void

    var body: some View {
        HStack(spacing: metrics.spacing) {
            ForEach(Board.dots) { dot in swatch(dot) }
        }
    }

    private func swatch(_ dot: Board.Dot) -> some View {
        let isCurrent = dot.swatch == current

        return Button { onSelect(dot.swatch) } label: {
            Circle()
                .fill(palette.resolve(dot.swatch))
                .frame(width: metrics.dot, height: metrics.dot)
                .padding(metrics.ringGap)
                .overlay {
                    Circle().strokeBorder(
                        isCurrent ? palette.ink(0.45) : .clear, lineWidth: metrics.ringWidth
                    )
                }
                .frame(minWidth: metrics.hitSize, minHeight: metrics.hitSize)
                .hoverBackground(
                    metrics.showsHover ? palette.ink(0.08) : .clear, radius: metrics.hitSize / 2
                )
        }
        .buttonStyle(.bare)
        .help(dot.name)
        .accessibilityLabel(dot.name)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}
