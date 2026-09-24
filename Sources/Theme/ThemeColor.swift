// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// A colour a theme states outright: eight bits a channel and an opacity.
///
/// **Not ``SwatchColor``.** That one is deliberately symbolic — `.ink` and
/// `.accent` are questions the palette answers, and a theme is *where the
/// answers come from*. A theme written in terms of them could not be resolved
/// without having already been resolved.
///
/// Coded as a CSS hex string rather than as a pair of fields, because the
/// export format is a file a person edits by hand. `#2A1E15` is the spelling
/// every other tool in the business uses, and it is one line instead of three:
///
/// ```json
/// { "card": "#28211A", "border": "#F3EDE414" }
/// ```
///
/// Decoding is looser than encoding on purpose — the twenty themes were written
/// as CSS, and a theme pasted out of a stylesheet should import rather than
/// throw. `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb(r,g,b)` and `rgba(r,g,b,a)` all
/// read; only the first two forms are ever written.
struct ThemeColor: Hashable, Sendable {
    var hex: UInt32
    var opacity: Double

    /// **Opacity is quantised to eight bits on the way in**, which is the
    /// precision it is written at — `#00000052` — and therefore the precision it
    /// comes back at. Without this a theme would not survive its own export: the
    /// document says `0.32`, the file says `52`, and `0x52 / 255` is `0.3216`, so
    /// a theme exported and re-imported would compare unequal to itself and the
    /// editor would show 32% for a value that was no longer 32%. The error is one
    /// step in 255 of alpha, which is below anything an eye or a screen can hold.
    init(_ hex: UInt32, opacity: Double = 1) {
        self.hex = hex & 0xFFFFFF
        self.opacity = (min(max(opacity, 0), 1) * 255).rounded() / 255
    }

    /// The `rgba(r, g, b, a)` the design document is written in, so a preset can
    /// be transcribed without arithmetic in the middle of it.
    init(rgba r: UInt32, _ g: UInt32, _ b: UInt32, _ opacity: Double = 1) {
        self.init((r << 16) | (g << 8) | b, opacity: opacity)
    }

    var color: Color { Color(hex: hex, opacity: opacity) }

    /// The same colour at full strength — what a tint is a tint *of*. A theme
    /// writes the wash as ink at 9%, and the ink underneath is the part a
    /// picker has to show and an editor has to let you change.
    var solid: ThemeColor { ThemeColor(hex) }

    func withOpacity(_ opacity: Double) -> ThemeColor { ThemeColor(hex, opacity: opacity) }

    /// This colour laid over another and flattened, for the surfaces that have
    /// nothing behind them to be translucent against: a menu-bar popover, a
    /// sheet's own backing, a thumbnail of the theme in a picker. Alpha is
    /// spent, not kept — the result is opaque.
    func composited(over base: ThemeColor) -> ThemeColor {
        guard opacity < 1 else { return solid }
        return ThemeColor(ColorMath.composite(hex, opacity: opacity, over: base.hex))
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when there is an alpha to say.
    var cssString: String {
        guard opacity < 1 else { return ColorMath.hexString(hex) }
        return ColorMath.hexString(hex) + String(format: "%02X", Int((opacity * 255).rounded()))
    }
}

// MARK: - Coding

extension ThemeColor: Codable {
    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = ThemeColor(css: text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "\(text) is not a colour")
            )
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(cssString)
    }

    /// Every spelling of a colour the twenty themes are written in, plus the two
    /// this app writes back. `nil` rather than a fallback: a theme file with a
    /// typo in it should say so at the point of import, not paint one surface
    /// black and leave the reader to find which.
    init?(css: String) {
        let text = css.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("rgb") {
            // Anchored at both ends: `rgba(0,0,0)x` is not a colour with some
            // rubbish after it, it is a typo, and reading it as black would put
            // a colour nobody chose on a surface.
            guard text.hasSuffix(")") else { return nil }
            let inside = text.drop(while: { $0 != "(" }).dropFirst().dropLast()
            let parts = inside.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 3 || parts.count == 4 else { return nil }
            let channels = parts.prefix(3).compactMap { UInt32($0) }
            guard channels.count == 3, channels.allSatisfy({ $0 <= 255 }) else { return nil }
            let alpha = parts.count == 4 ? Double(parts[3]) : 1
            guard let alpha, (0...1).contains(alpha) else { return nil }
            self.init(rgba: channels[0], channels[1], channels[2], alpha)
            return
        }
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        if digits.count == 8 {
            guard let value = UInt32(digits, radix: 16) else { return nil }
            self.init(value >> 8, opacity: Double(value & 0xFF) / 255)
            return
        }
        guard let value = ColorMath.hexValue(text) else { return nil }
        self.init(value)
    }
}
