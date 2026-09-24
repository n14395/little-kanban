// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// A colour the design expresses either as a literal (`#C98A16`) or as one of
/// two named symbols, `.accent` and `.ink`, that older board files still carry.
///
/// **The symbols are pinned now.** They used to be theme-relative — `.accent`
/// was whatever the theme's highlight happened to be, `.ink` a tint of its text
/// colour — which meant a board painted Accent repainted itself every time the
/// theme changed. The palette is the user's and a chosen colour is a choice, so
/// both symbols resolve to one literal each (``accentHex``, ``inkHex``) on
/// every theme. The cases stay because files and sync payloads store them; only
/// what they *mean* is fixed.
///
/// Literals keep their components rather than a built `Color`, which is what
/// lets a user-created label be written to disk — `Color` is not `Codable`.
enum SwatchColor: Hashable, Sendable, Codable {
    case rgb(UInt32, opacity: Double)
    case ink(opacity: Double)
    case accent

    static func hex(_ value: UInt32, opacity: Double = 1) -> SwatchColor {
        .rgb(value, opacity: opacity)
    }

    /// The literal behind `.accent`: Ember's orange, the accent the app has
    /// always shipped wearing. Pinned here rather than read off the theme so a
    /// board painted Accent is the same colour on every theme.
    static let accentHex: UInt32 = 0xE8703F

    /// The literal behind `.ink`: the mid grey the picker has always fallen
    /// back to, workable as a dot or a wash on light and dark grounds alike.
    static let inkHex: UInt32 = 0x8A8A8A

    /// The one hex this swatch draws, now that every swatch has one. `.ink`
    /// discards its opacity here — callers that tint go through
    /// ``Palette/resolve(_:)``, which keeps it.
    var literalValue: UInt32 {
        switch self {
        case .rgb(let value, _): value
        case .ink: Self.inkHex
        case .accent: Self.accentHex
        }
    }
}
