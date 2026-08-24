import Foundation
import Testing
@testable import Simple_Kanban

/// The arithmetic under the colour picker.
///
/// **Because none of it can be seen.** A hex field that quietly accepts
/// `#12345`, a spectrum whose knob lands a shade off the finger, a chip whose
/// text comes out the same lightness as its ground — every one of those looks
/// like a working picker in a screenshot. `ColorMath` is where the rules are,
/// so this is where they are asked.
@Suite struct ColorMathTests {
    // MARK: Hex

    @Test func aValueIsWrittenAsSixUppercaseDigits() {
        #expect(ColorMath.hexString(0xC2532F) == "#C2532F")
        // Padded rather than shortened: `#0F1` is a different colour from
        // `#0000F1`, and a field showing three digits invites the confusion.
        #expect(ColorMath.hexString(0x0000F1) == "#0000F1")
        #expect(ColorMath.hexString(0) == "#000000")
        #expect(ColorMath.hexString(0xFFFFFF) == "#FFFFFF")
    }

    /// The forms a person actually types. Lenient about the hash, the case and
    /// the spaces around it, because none of those is a different colour.
    @Test func everySpellingOfOneColourReadsAsThatColour() {
        for spelling in ["#C2532F", "c2532f", "C2532F", "  #c2532F  ", "#C2532f"] {
            #expect(ColorMath.hexValue(spelling) == 0xC2532F, "\(spelling) did not read")
        }
    }

    /// CSS's three-digit shorthand, which doubles each digit — `#C53` is
    /// `#CC5533` and has been for thirty years.
    @Test func theThreeDigitShorthandDoublesEachDigit() {
        #expect(ColorMath.hexValue("#C53") == 0xCC5533)
        #expect(ColorMath.hexValue("fff") == 0xFFFFFF)
        #expect(ColorMath.hexValue("#000") == 0x000000)
    }

    /// **Refused rather than salvaged.** A field that reads `#12345` as
    /// `#123450` puts a colour on the board that nobody chose, and the user has
    /// no way to tell it happened.
    @Test func anythingThatIsNotAHexIsRefused() {
        for junk in ["", "#", "#12345", "#1234567", "#GG0000", "12 34 56", "rebeccapurple", "#-10000"] {
            #expect(ColorMath.hexValue(junk) == nil, "\(junk) was read as a colour")
        }
    }

    // MARK: The two ways of naming a colour

    /// Every colour the app ships with, out to HSB and back. The spectrum moves
    /// in HSB and the file stores hex, so this round trip happens on every drag
    /// — a rounding that loses a digit would walk a colour away from itself as
    /// the picker was opened and closed.
    @Test func everyShippedColourSurvivesTheRoundTrip() {
        let shipped: [UInt32] = [
            0xA8A29A, 0xC98A16, 0xC2532F, 0x1F6F63, 0x3B5BA9,   // Board.dots
            0xBE2828, 0x783CA0, 0xE87C58, 0xF1B49B,             // label tones
            0x000000, 0xFFFFFF, 0x808080, 0x010203,             // the corners
        ]
        for value in shipped {
            #expect(ColorMath.value(of: ColorMath.hsb(of: value)) == value,
                    "\(ColorMath.hexString(value)) came back as \(ColorMath.hexString(ColorMath.value(of: ColorMath.hsb(of: value))))")
        }
    }

    /// Grey is the case the conversion loses information on — every grey has the
    /// same hue, because it has no hue — so it has to come back grey rather than
    /// come back red.
    @Test func greyHasNoHueAndStaysGrey() {
        let grey = ColorMath.hsb(of: 0x808080)
        #expect(grey.saturation == 0)
        #expect(ColorMath.value(of: grey) == 0x808080)
    }

    @Test func hueWrapsRatherThanClamping() {
        // The hue slider is a loop: dragging past the bottom is red again, not
        // stuck on magenta.
        #expect(ColorMath.HSB(hue: 1.25, saturation: 1, brightness: 1).hue == 0.25)
        #expect(abs(ColorMath.HSB(hue: -0.25, saturation: 1, brightness: 1).hue - 0.75) < 0.0001)
        // Saturation and brightness are not: a drag off the side of the square
        // means the edge of it.
        #expect(ColorMath.HSB(hue: 0, saturation: 1.4, brightness: -0.2).saturation == 1)
        #expect(ColorMath.HSB(hue: 0, saturation: 1.4, brightness: -0.2).brightness == 0)
    }

    // MARK: Contrast

    /// The threshold is WCAG's, not "brighter than mid-grey", and the app's own
    /// colours are what makes the difference visible: Ember is well under half
    /// brightness by eye and takes white text, while Amber is lighter than it
    /// looks and takes black.
    @Test func textOnASwatchIsPickedByLuminanceRatherThanByBrightness() {
        #expect(ColorMath.prefersDarkText(on: 0xFFFFFF))
        #expect(ColorMath.prefersDarkText(on: 0x000000) == false)
        #expect(ColorMath.prefersDarkText(on: 0xC2532F) == false, "Ember would take black text")
        #expect(ColorMath.prefersDarkText(on: 0xC98A16), "Amber would take white text")
        #expect(ColorMath.prefersDarkText(on: 0x1F6F63) == false, "Pine would take black text")
        #expect(ColorMath.prefersDarkText(on: 0xA8A29A), "Stone would take white text")
    }

    /// Green reads far lighter than blue at the same numbers, which is the whole
    /// reason the channels are weighted rather than averaged.
    @Test func luminanceWeightsTheChannelsTheWayAnEyeDoes() {
        #expect(ColorMath.luminance(of: 0x00FF00) > ColorMath.luminance(of: 0x0000FF))
        #expect(ColorMath.luminance(of: 0xFFFFFF) == 1)
        #expect(ColorMath.luminance(of: 0x000000) == 0)
    }

    // MARK: Shades

    @Test func lighteningAndDarkeningKeepTheHue() {
        let base: UInt32 = 0x1F6F63
        let hue = ColorMath.hsb(of: base).hue
        for amount in [-0.4, -0.2, 0.2, 0.45, 0.78] {
            let shaded = ColorMath.shade(base, by: amount)
            #expect(abs(ColorMath.hsb(of: shaded).hue - hue) < 0.02,
                    "\(amount) moved the hue of \(ColorMath.hexString(base))")
        }
    }

    @Test func aShadeMovesInTheDirectionItIsAsked() {
        let base: UInt32 = 0xC2532F
        #expect(ColorMath.luminance(of: ColorMath.shade(base, by: 0.5)) > ColorMath.luminance(of: base))
        #expect(ColorMath.luminance(of: ColorMath.shade(base, by: -0.3)) < ColorMath.luminance(of: base))
        #expect(ColorMath.shade(base, by: 0) == base)
    }

    /// Black has no hue and no saturation to lift, so lightening it has to give
    /// grey rather than stay black — the corner a picker lands on the moment
    /// somebody drags to the bottom of the square and then back up.
    @Test func blackAndWhiteShadeWithoutGettingStuck() {
        #expect(ColorMath.shade(0x000000, by: 0.5) != 0x000000)
        #expect(ColorMath.hsb(of: ColorMath.shade(0x000000, by: 0.5)).saturation == 0)
        #expect(ColorMath.shade(0xFFFFFF, by: -0.5) != 0xFFFFFF)
    }

    // MARK: What a label wears

    /// A chip is a tinted ground with text on it, and both come from the one
    /// colour a picker returns. What matters is that they stay *apart*: text the
    /// same lightness as its ground is a chip with nothing readable on it.
    @Test func aLabelsFourColoursComeApartFromOneColour() {
        for base: UInt32 in [0xC2532F, 0x1F6F63, 0x3B5BA9, 0xC98A16, 0xA8A29A] {
            let pair = LabelTone.pair(from: base)

            // The light ground is the colour itself, tinted — which is what
            // `LabelDef.baseColor` reads back to put the ring on the swatch the
            // label was made from.
            #expect(pair.light.background == .rgb(base, opacity: 0.13))
            #expect(LabelDef(key: "k", name: "n", light: pair.light, dark: pair.dark).baseColor == .hex(base))

            guard case .rgb(let lightText, _) = pair.light.foreground,
                  case .rgb(let darkGround, _) = pair.dark.background,
                  case .rgb(let darkText, _) = pair.dark.foreground
            else {
                Issue.record("a derived tone is not a literal")
                return
            }

            #expect(ColorMath.luminance(of: lightText) < ColorMath.luminance(of: base),
                    "light text is not darker than the colour it came from")
            #expect(ColorMath.luminance(of: darkGround) > ColorMath.luminance(of: base),
                    "the dark ground was not lifted")
            #expect(ColorMath.luminance(of: darkText) > ColorMath.luminance(of: darkGround),
                    "dark text is not lighter than its own ground")
        }
    }

    /// The palette's grey has no hue to derive from, so it gets the ink pair the
    /// `API` seed label wears rather than a tint of nothing.
    @MainActor
    @Test func aColourlessSwatchGetsTheInkPair() {
        let store = TestBoard.store()
        #expect(store.labelTones(for: .ink(opacity: 0.35)).light == LabelTone.inkPair.light)
        // The accent is resolved against the theme in force: a chip's ground is
        // a tint, and `.accent` carries no opacity to tint with.
        #expect(store.labelTones(for: .accent).light == LabelTone.accentPair.light)
    }
}
