import SwiftUI
import Testing
@testable import Simple_Kanban

/// The semantic colours, asked the question a view has no way to ask itself.
///
/// C2 puts every colour in `Palette`, which buys nothing unless what `Palette`
/// hands out is *right* — and a colour that is wrong in this particular way does
/// not look wrong, it looks like nothing at all. Contrast is the one property of
/// a colour pair a test can hold, so the pair a filled control is made of is
/// held here.
@Suite struct PaletteSemanticTests {
    /// WCAG relative luminance. `Color.Resolved` hands back linear sRGB
    /// components, which is what the coefficients want, so there is no
    /// gamma step to get wrong here.
    private func luminance(_ color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        return 0.2126 * Double(resolved.linearRed)
            + 0.7152 * Double(resolved.linearGreen)
            + 0.0722 * Double(resolved.linearBlue)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    /// A translucent colour laid over an opaque one, which is the only form a
    /// scrim is ever seen in.
    private func composited(_ color: Color, over ground: Color) -> Color {
        let top = color.resolve(in: EnvironmentValues())
        let base = ground.resolve(in: EnvironmentValues())
        let alpha = Double(top.opacity)
        func mix(_ a: Float, _ b: Float) -> Double {
            Double(a) * alpha + Double(b) * (1 - alpha)
        }
        return Color(
            red: mix(top.red, base.red),
            green: mix(top.green, base.green),
            blue: mix(top.blue, base.blue)
        )
    }

    /// **A scrim has to make the thing behind it darker.** It reads like a
    /// tautology and was not one: both of the iPhone's covering panels — the
    /// navigation drawer and the Inbox slide-over — wrote their scrim as
    /// `ink(0.3)`, and ink in dark mode is 0xEEEAE2. Opening either one laid a
    /// near-white veil over the board and lit the screen up. It went unnoticed
    /// because ink and shadow are the same 0x171310 in light mode, so the only
    /// scheme anybody checked was the one where the two spellings agree.
    ///
    /// The same defect `aLabelOnTheAccentIsReadableForEveryAccentInEitherScheme`
    /// exists for, from the other end, and pinned the same way: both schemes,
    /// because the wrong one is the one nobody looks at.
    @Test func aScrimDarkensWhatItCoversInEitherScheme() {
        for scheme in [ColorScheme.light, .dark] {
            let palette = Palette(colorScheme: scheme)
            let board = palette.appBackground
            let veiled = composited(palette.scrim(), over: board)
            #expect(
                luminance(veiled) <= luminance(board) * 0.8,
                "the scrim does not darken the board in \(scheme) — \(luminance(board)) became \(luminance(veiled))"
            )
        }
    }

    /// And it has to fade out rather than jump, because a panel dragged in
    /// brings its scrim with it a frame at a time.
    @Test func aScrimFadesWithTheFractionItIsGiven() {
        for scheme in [ColorScheme.light, .dark] {
            let palette = Palette(colorScheme: scheme)
            let board = palette.appBackground
            let half = luminance(composited(palette.scrim(0.5), over: board))
            #expect(half < luminance(board), "half a scrim does not darken at all in \(scheme)")
            #expect(half > luminance(composited(palette.scrim(), over: board)),
                    "half a scrim is as dark as a whole one in \(scheme)")
            // Within a rounding step: the composite goes out through
            // `Color(red:green:blue:)` and back through `resolve`, and a colour
            // space round trip does not land on the same float it started on.
            #expect(abs(luminance(composited(palette.scrim(0), over: board)) - luminance(board)) < 0.001,
                    "a scrim at nothing still marks the board in \(scheme)")
        }
    }

    /// Seven views drew the label of a filled accent control as a literal
    /// `.white`. Three of the four accents are dark, saturated colours in either
    /// scheme and white is right on them — but `.ink` *is* the ink colour, and
    /// ink in dark mode is 0xEEEAE2. White on that is white on near-white: the
    /// source list's capture button, the completion tick, the pager chips
    /// and the due-date presets were all blank for anyone using the ink accent
    /// after dark, in both the app and the previews.
    ///
    /// Every accent in every scheme, because the defect was in one cell of that
    /// eight-cell table and nothing else in the app iterates it.
    @Test func aLabelOnTheAccentIsReadableForEveryAccentInEitherScheme() {
        for scheme in [ColorScheme.light, .dark] {
            for theme in AccentTheme.allCases {
                let palette = Palette(colorScheme: scheme, accentTheme: theme)
                let ratio = contrast(palette.onAccent, palette.accent)
                // 4.5:1 is WCAG AA for body text, which is what these labels
                // are — 12.5pt bold is under the 14pt the large-text
                // relaxation starts at. `.white` on the dark-mode ink accent
                // scores 1.2.
                #expect(ratio >= 4.5,
                        "\(theme.rawValue) in \(scheme == .dark ? "dark" : "light") reads at \(ratio):1")
            }
        }
    }

    /// The tick a completed card wears, and the accent it sits on, are the pair
    /// above — so a scheme that inverts one has to invert the other. Named
    /// separately because `onAccent` is easy to read as "white, spelt longer",
    /// which is what it was before and is only true for three of the four.
    @Test func theAccentThatFollowsTheSchemeTakesItsLabelWithIt() {
        let light = Palette(colorScheme: .light, accentTheme: .ink)
        let dark = Palette(colorScheme: .dark, accentTheme: .ink)
        #expect(light.accent != dark.accent)
        #expect(light.onAccent != dark.onAccent)

        // And the three fixed accents do not move, so a change to the ink case
        // cannot quietly pull them along.
        for theme in [AccentTheme.ember, .pine, .indigo] {
            #expect(Palette(colorScheme: .light, accentTheme: theme).onAccent
                    == Palette(colorScheme: .dark, accentTheme: theme).onAccent)
        }
    }
}
