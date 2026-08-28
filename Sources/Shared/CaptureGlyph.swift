import SwiftUI

/// The mark on the three ever-present "+" buttons: a tray with a `+` over it.
///
/// **A path rather than an SF Symbol, because there is no symbol for this.**
/// The three buttons — the foot of the desk's source list, the iPad's board
/// header, the phone's over its tab bar — all capture into the Inbox, and a
/// bare `plus` said only *makes something*, which is the one thing every other
/// `+` in the app says too. `tray.and.arrow.down` is a download; `tray` alone
/// is where the panel's own toggle points; there is no `tray.badge.plus` to
/// ask for. So the mark is drawn: the Inbox's tray, and the `+` going into it.
///
/// The geometry is `add-to-inbox.svg` at the root of the repo, kept in its own
/// 24-unit grid so the two can be compared line for line — see
/// ``CaptureGlyph/Mark``.
struct CaptureGlyph: View {
    /// The design point size, following the reader's text size exactly as an
    /// SF Symbol given the same number would. See ``ScaledGlyph``.
    private let size: ScaledGlyph
    private let weight: Font.Weight

    init(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body,
        cap: CGFloat = 1.6
    ) {
        self.size = ScaledGlyph(size, relativeTo: textStyle, cap: cap)
        self.weight = weight
    }

    var body: some View {
        let points = size.points
        Mark()
            .stroke(
                style: StrokeStyle(
                    lineWidth: Self.stroke(weight) * points / Mark.grid,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            // Square, and the same number the call site would have passed to
            // `symbolSize`: an SF Symbol at 19pt inks about 16 points tall, and
            // this grid inks 20.5 of its 24 — so the two land within a quarter
            // of a point of each other at any size, and a button that swapped
            // one for the other does not change size.
            .frame(width: points, height: points)
    }

    /// What a weight means in the 24-unit grid.
    ///
    /// SF Symbols answer `weight:` by drawing a different glyph; a path can
    /// only get thicker, which is most of what that difference *is* at these
    /// sizes. 2 is what the file was drawn at, and is `.regular` by definition;
    /// the two steps either side of it are the ones the buttons ask for.
    private static func stroke(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: 1.2
        case .thin: 1.5
        case .light: 1.75
        case .medium: 2.25
        case .semibold: 2.5
        case .bold: 2.8
        case .heavy: 3.1
        case .black: 3.4
        default: 2
        }
    }

    /// The strokes of `add-to-inbox.svg`, in the grid it was drawn on.
    ///
    /// Centred in whatever square it is given rather than stretched to the
    /// rect: the mark is 18 units wide and 20.5 tall inside its 24, and a
    /// non-square frame would shear it.
    struct Mark: Shape {
        /// The side of the SVG's `viewBox`.
        static let grid: CGFloat = 24

        func path(in rect: CGRect) -> Path {
            let side = min(rect.width, rect.height)
            let unit = side / Self.grid
            let originX = rect.midX - side / 2
            let originY = rect.midY - side / 2
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: originX + x * unit, y: originY + y * unit)
            }

            var path = Path()

            // The tray's two top rims, left and right of the gap the "+" comes
            // down through.
            path.move(to: at(6.5, 9))
            path.addLine(to: at(9.2, 9))
            path.move(to: at(14.8, 9))
            path.addLine(to: at(17.5, 9))

            // And the two slopes down from them to the body's shoulders.
            path.move(to: at(6.5, 9))
            path.addLine(to: at(4, 13.5))
            path.move(to: at(17.5, 9))
            path.addLine(to: at(20, 13.5))

            // The mouth: across the shoulders, dipping in the middle, which is
            // what makes a tray a tray rather than a box.
            path.move(to: at(4, 13.5))
            path.addLine(to: at(8, 13.5))
            path.addLine(to: at(10, 16))
            path.addLine(to: at(14, 16))
            path.addLine(to: at(16, 13.5))
            path.addLine(to: at(20, 13.5))

            // The body, with the two rounded bottom corners the file draws as
            // quadratics.
            path.move(to: at(4, 13.5))
            path.addLine(to: at(4, 19))
            path.addQuadCurve(to: at(6, 21), control: at(4, 21))
            path.addLine(to: at(18, 21))
            path.addQuadCurve(to: at(20, 19), control: at(20, 21))
            path.addLine(to: at(20, 13.5))

            // The "+", above the gap.
            path.move(to: at(12, 2.5))
            path.addLine(to: at(12, 8.5))
            path.move(to: at(9, 5.5))
            path.addLine(to: at(15, 5.5))

            return path
        }
    }
}
