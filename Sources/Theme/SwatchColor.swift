import SwiftUI

/// A colour the design expresses either as a literal (`#C98A16`) or as a
/// theme-relative ink tint (`rgba(var(--ink-rgb), 0.35)`). The latter can only
/// be resolved once the colour scheme is known, so swatches stay symbolic in
/// the model layer and are resolved by ``Palette`` at render time.
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
}
