// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The app icon's corner, as a shape.
///
/// A superellipse rather than `RoundedRectangle`, for the reason in
/// ``AppIconArtwork/squircle(in:exponent:)``: circular corners read visibly
/// tighter beside the system's own icons, and this drawing is shown next to
/// them in a Dock. `InsettableShape` so the selection ring can be stroked
/// inside its own edge rather than straddling it.
struct IconSquircle: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        Path(AppIconArtwork.squircle(in: rect.insetBy(dx: inset, dy: inset)))
    }

    func inset(by amount: CGFloat) -> IconSquircle {
        IconSquircle(inset: inset + amount)
    }
}

/// The icon itself: a gradient ground with the capped-columns mark over it.
///
/// **Full bleed and unclipped**, because the two places it is drawn want
/// different edges — the picker wants a squircle it can put a ring around, and
/// the Dock icon wants a squircle inset inside a shadow. Both are the caller's
/// business; this is the picture.
///
/// A ``Canvas`` rather than nine stacked `RoundedRectangle`s: the drawing is
/// twelve fills of pure geometry with no layout in it, and the picker puts
/// eleven copies of it on screen at once.
struct AppIconMark: View {
    let art: AppIconArt
    /// Below about 33 pixels the cards close up into a smudge — see
    /// ``AppIconArtwork/stacks``. Nothing in the app asks for the simplified
    /// mark today; the tool that writes the 16pt slots does.
    var isSimplified = false

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            let ground = art.ground
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    ground.gradient,
                    startPoint: Self.point(ground.startPoint, in: size),
                    endPoint: Self.point(ground.endPoint, in: size)
                )
            )
            let scale = size.width / AppIconArtwork.unit
            if isSimplified {
                fill(AppIconArtwork.stacks, art.card, scale, in: &context)
            } else {
                fill(AppIconArtwork.headers, art.cap, scale, in: &context)
                fill(AppIconArtwork.cards, art.card, scale, in: &context)
            }
        }
        // Twelve rectangles are not twelve things to a reader. What the icon is
        // called is said by the row around it.
        .accessibilityHidden(true)
    }

    private func fill(
        _ bars: [AppIconArtwork.Bar], _ colour: ThemeColor, _ scale: CGFloat,
        in context: inout GraphicsContext
    ) {
        let shading = GraphicsContext.Shading.color(colour.color)
        for bar in bars {
            let rect = CGRect(
                x: bar.x * scale, y: bar.y * scale,
                width: bar.width * scale, height: bar.height * scale
            )
            context.fill(Path(roundedRect: rect, cornerRadius: bar.radius * scale), with: shading)
        }
    }

    /// A ``UnitPoint`` is a fraction of the frame; a `Canvas` draws in points.
    private static func point(_ unit: UnitPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }
}

/// The icon as the picker shows it: squircled, with a hairline so a pale ground
/// still has an edge, and a ring when it is the one in use.
struct AppIconTile: View {
    let art: AppIconArt
    var size: CGFloat
    var isCurrent = false

    @Environment(\.palette) private var palette

    var body: some View {
        AppIconMark(art: art)
            .frame(width: size, height: size)
            .clipShape(IconSquircle())
            // The tile's own edge, not the theme's: `4j` and Porcelain are very
            // nearly the colour of the panel they sit on, and an icon with no
            // edge on a page of icons with edges reads as a gap.
            .overlay { IconSquircle().strokeBorder(palette.ink(0.12), lineWidth: 1) }
            .overlay {
                // Outside the icon rather than over it. A ring drawn on top of
                // the artwork eats two points of a drawing whose whole subject
                // is a margin — the columns run from 20 to 80 of 100 — and on
                // `4c`, whose ground reaches the corner in near-white, a ring
                // in the accent laid inside would vanish into it.
                IconSquircle()
                    .strokeBorder(isCurrent ? palette.accent : .clear, lineWidth: 2.5)
                    .padding(-4)
            }
    }
}
