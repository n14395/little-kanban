import Foundation

/// One colour in the palette every colour picker in the app draws from.
///
/// **The palette is data now, not a constant.** It used to be `Board.dots` — six
/// hexes written into the source, offered by whichever picker happened to be on
/// screen. A colour the user mixes has to be somewhere the *next* picker can
/// find it, and a colour they throw away has to disappear from all of them, so
/// the list lives in the board file beside the labels and the boards. See
/// ``BoardStore/savedColors``.
///
/// The name is what a reader hears, and it is optional because only the six the
/// app ships with have one. A swatch announced as "Colour 4" tells a VoiceOver
/// user its position and nothing about what choosing it does — which is why the
/// names were written beside the hexes in the first place — and the honest
/// answer for a colour somebody mixed themselves is its hex. See
/// ``displayName``.
struct PaletteSwatch: Identifiable, Hashable, Codable, Sendable {
    var swatch: SwatchColor
    /// The name this colour ships under, or `nil` for one the user mixed.
    ///
    /// Stored rather than looked up so a seeded name survives a rename of the
    /// constant it came from, and so the file says what the user was shown.
    var name: String?

    /// The colour itself, which is what a picker matches the current selection
    /// against — two entries of the same colour would be one choice drawn twice.
    var id: SwatchColor { swatch }

    init(_ swatch: SwatchColor, name: String? = nil) {
        self.swatch = swatch
        self.name = name
    }

    /// What a reader hears: the shipped name, the shipped name of an identical
    /// colour that has been re-added by hand, or the hex.
    var displayName: String {
        if let name { return name }
        if case .rgb(let value, _) = swatch,
           let known = Self.seed.first(where: { $0.swatch == .hex(value) })?.name {
            return known
        }
        switch swatch {
        case .rgb(let value, _): return ColorMath.hexString(value)
        case .ink: return String(localized: "Grey", comment: "Palette colour: the app's fixed mid grey")
        case .accent: return String(localized: "Accent", comment: "Board dot colour: the app's own fixed accent orange")
        }
    }

    /// **The accent is the palette's anchor and cannot be thrown away.** It is
    /// pinned to one literal now — see ``SwatchColor/accentHex`` — rather than
    /// following the theme, but it is still stored as `.accent` in every board
    /// file ever written, and deleting it here would leave those files ringing
    /// a swatch no picker offers.
    var isRemovable: Bool { swatch != .accent }

    /// What a board file that has never seen a palette gets, and what a fresh
    /// install starts with: the six `Board.dots` were offered by, in that order.
    ///
    /// `Board.dots` stays the source, rather than this list being retyped, so
    /// the seed colours and the names the rest of the app knows them by cannot
    /// drift apart.
    static var seed: [PaletteSwatch] {
        Board.dots.map { PaletteSwatch($0.swatch, name: $0.name) }
    }
}
