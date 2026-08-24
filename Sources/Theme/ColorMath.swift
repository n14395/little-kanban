import Foundation

/// The arithmetic the colour picker needs, with no view in it.
///
/// **Here rather than in the picker** because every one of these is a rule that
/// can be wrong in a way a screenshot will not show: a hex field that accepts
/// `#GGG`, a spectrum whose knob lands a shade off where the finger was, a
/// label whose text comes out the same lightness as the chip behind it. A view
/// cannot be asked any of that; this can, and `ColorMathTests` does.
enum ColorMath {
    // MARK: Hex

    /// `#RRGGBB` for a packed value. Uppercase, because a hex field the user is
    /// typing into should not appear to change what they typed.
    static func hexString(_ value: UInt32) -> String {
        String(format: "#%06X", value & 0xFFFFFF)
    }

    /// The value a typed hex names, or `nil` for anything that is not one.
    ///
    /// Lenient about the things a person types and strict about the rest: a
    /// leading `#` is optional, case does not matter, surrounding space is
    /// ignored, and the three-digit shorthand (`#C53` → `#CC5533`) is the same
    /// colour CSS has meant by it for thirty years. Anything else — four
    /// digits, eight digits, a letter past F — is refused rather than salvaged,
    /// because a field that quietly reads `#12345` as `#123450` puts a colour
    /// on the board that nobody chose.
    static func hexValue(_ text: String) -> UInt32? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 3,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16)
        else { return nil }
        guard digits.count == 3 else { return value }
        // 0xC53 → 0xCC5533: each digit doubled, which is what the shorthand is.
        let red = (value >> 8) & 0xF, green = (value >> 4) & 0xF, blue = value & 0xF
        return (red << 20) | (red << 16) | (green << 12) | (green << 8) | (blue << 4) | blue
    }

    // MARK: Between the two ways of naming a colour

    /// Hue, saturation and brightness, each 0…1 — what the spectrum square and
    /// the hue slider move in. Hue wraps at 1, which is the same colour as 0.
    struct HSB: Hashable, Sendable {
        var hue: Double
        var saturation: Double
        var brightness: Double

        init(hue: Double, saturation: Double, brightness: Double) {
            self.hue = hue.truncatingRemainder(dividingBy: 1) < 0
                ? hue.truncatingRemainder(dividingBy: 1) + 1
                : hue.truncatingRemainder(dividingBy: 1)
            self.saturation = min(max(saturation, 0), 1)
            self.brightness = min(max(brightness, 0), 1)
        }
    }

    static func hsb(of value: UInt32) -> HSB {
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let high = max(red, green, blue), low = min(red, green, blue)
        let range = high - low

        var hue = 0.0
        if range > 0 {
            switch high {
            case red: hue = (green - blue) / range + (green < blue ? 6 : 0)
            case green: hue = (blue - red) / range + 2
            default: hue = (red - green) / range + 4
            }
            hue /= 6
        }
        return HSB(hue: hue, saturation: high > 0 ? range / high : 0, brightness: high)
    }

    static func value(of color: HSB) -> UInt32 {
        let sector = color.hue * 6
        let index = Int(sector.rounded(.down)) % 6
        let offset = sector - sector.rounded(.down)
        let high = color.brightness
        let low = high * (1 - color.saturation)
        let falling = high * (1 - color.saturation * offset)
        let rising = high * (1 - color.saturation * (1 - offset))

        let (red, green, blue): (Double, Double, Double) = switch index {
        case 0: (high, rising, low)
        case 1: (falling, high, low)
        case 2: (low, high, rising)
        case 3: (low, falling, high)
        case 4: (rising, low, high)
        default: (high, low, falling)
        }
        return pack(red, green, blue)
    }

    private static func pack(_ red: Double, _ green: Double, _ blue: Double) -> UInt32 {
        let channel = { (value: Double) in UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return (channel(red) << 16) | (channel(green) << 8) | channel(blue)
    }

    // MARK: Contrast

    /// How light a colour reads, 0…1 — WCAG's relative luminance, which weights
    /// the channels the way an eye does rather than averaging them. Pure green
    /// comes out at 0.72 and pure blue at 0.07, and a mean would call them the
    /// same.
    static func luminance(of value: UInt32) -> Double {
        func channel(_ raw: UInt32) -> Double {
            let part = Double(raw) / 255
            return part <= 0.03928 ? part / 12.92 : pow((part + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((value >> 16) & 0xFF)
            + 0.7152 * channel((value >> 8) & 0xFF)
            + 0.0722 * channel(value & 0xFF)
    }

    /// Whether text drawn on this colour should be dark.
    ///
    /// The threshold is where black and white contrast equally against the
    /// background — 0.179 by the WCAG ratio, rather than the 0.5 that "is it
    /// brighter than mid-grey" suggests. It matters: the app's own Ember
    /// (`#C2532F`) sits at 0.16, which the naive test calls dark and the eye
    /// agrees with, while Amber (`#C98A16`) is 0.31 and takes black text.
    static func prefersDarkText(on value: UInt32) -> Bool {
        luminance(of: value) > 0.179
    }

    // MARK: Shades

    /// The same hue, lighter or darker. `amount` is how far towards white
    /// (positive) or black (negative) to go, 0…1.
    ///
    /// Moves in *brightness and saturation together* rather than blending
    /// towards white, which is what keeps a lightened colour from going chalky:
    /// blending `#1F6F63` halfway to white gives a washed grey-green, while
    /// lifting its brightness keeps the green.
    static func shade(_ value: UInt32, by amount: Double) -> UInt32 {
        var color = hsb(of: value)
        if amount >= 0 {
            color.brightness = min(1, color.brightness + (1 - color.brightness) * amount)
            color.saturation = max(0, color.saturation * (1 - amount * 0.55))
        } else {
            color.brightness = max(0, color.brightness * (1 + amount))
            color.saturation = min(1, color.saturation * (1 - amount * 0.15))
        }
        return self.value(of: color)
    }
}
