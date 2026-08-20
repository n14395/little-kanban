import SwiftUI

/// A colour the design expresses either as a literal (`#C98A16`) or as a
/// theme-relative ink tint (`rgba(var(--ink-rgb), 0.35)`). The latter can only
/// be resolved once the colour scheme is known, so swatches stay symbolic in
/// the model layer and are resolved by ``Palette`` at render time.
enum SwatchColor: Hashable, Sendable {
    case fixed(Color)
    case ink(opacity: Double)
    case accent

    static func hex(_ value: UInt32) -> SwatchColor { .fixed(Color(hex: value)) }
}
