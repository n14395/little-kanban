import Foundation

/// One colour in the palette every colour picker in the app draws from.
///
/// **The palette is data now, not a constant.** It used to be six hexes written
/// into the source — `Board.dots`, as it then was — offered by whichever picker
/// happened to be on screen. A colour the user mixes has to be somewhere the
/// *next* picker can find it, and a colour they throw away has to disappear
/// from all of them, so the list lives in the board file beside the labels and
/// the boards. See ``BoardStore/savedColors``.
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
        case .accent: return String(localized: "Accent", comment: "Palette colour: the app's own fixed accent orange")
        }
    }

    /// **The accent is the palette's anchor and cannot be thrown away.** It is
    /// pinned to one literal now — see ``SwatchColor/accentHex`` — rather than
    /// following the theme, but it is still stored as `.accent` in every board
    /// file ever written, and deleting it here would leave those files ringing
    /// a swatch no picker offers.
    var isRemovable: Bool { swatch != .accent }

    /// What a board file that has never seen a palette gets, and what a fresh
    /// install starts with.
    ///
    /// **These six were `Board.dots` until v16**, when a board's mark became a
    /// glyph and the last thing on `Board` that was about colour was a list of
    /// colours boards no longer wear. They are the same six, in the same order,
    /// and they are still the seed rather than the whole of what a picker can
    /// offer: since v10 the list a picker draws is the user's, in the file, and
    /// can be added to and taken from.
    ///
    /// Six, because that is a row of 44pt targets on the narrowest phone with
    /// no spacing left to give away — and the six are chosen so every dot the
    /// seed workflow ships with is among them, so a column can always be put
    /// back the way it arrived. ``Board/inboxDot`` is deliberately not offered:
    /// a column wearing the Inbox's grey in the same list is a puzzle, not a
    /// choice.
    ///
    /// The last three are the accent themes' own hexes, so they take the accent
    /// themes' names: one vocabulary for one colour, whichever control is
    /// offering it. The first is `.accent` — the app's own orange, pinned to
    /// one literal now rather than following the theme (see
    /// ``SwatchColor/accentHex``), and still spelled symbolically because every
    /// board file ever written spells it that way.
    ///
    /// The names are here rather than in whichever view happens to draw a
    /// swatch: a colour picked by eye is picked by index to anyone who cannot
    /// see it, "Colour 4" says nothing about what choosing it does, and a name
    /// kept in a view drifts from the colour the moment either is edited.
    static var seed: [PaletteSwatch] {
        [
            PaletteSwatch(.accent,
                          name: String(localized: "Accent", comment: "Palette colour: the app's own fixed accent orange")),
            PaletteSwatch(.hex(0xA8A29A),
                          name: String(localized: "Stone", comment: "Palette colour: warm grey")),
            PaletteSwatch(.hex(0xC98A16),
                          name: String(localized: "Amber", comment: "Palette colour: golden yellow")),
            PaletteSwatch(.hex(0xC2532F),
                          name: String(localized: "Ember", comment: "Palette colour: burnt orange")),
            PaletteSwatch(.hex(0x1F6F63),
                          name: String(localized: "Pine", comment: "Palette colour: deep green")),
            PaletteSwatch(.hex(0x3B5BA9),
                          name: String(localized: "Indigo", comment: "Palette colour: deep blue")),
        ]
    }

    /// The seed as bare colours — what a caller comparing a palette against
    /// what the app ships with wants, and what `Board.dotPalette` was.
    static var seedPalette: [SwatchColor] { seed.map(\.swatch) }
}
