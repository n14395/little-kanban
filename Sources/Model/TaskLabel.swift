import SwiftUI

/// A label's background/foreground pair for one colour scheme.
struct LabelTone: Hashable, Sendable, Codable {
    var background: SwatchColor
    var foreground: SwatchColor

    static func tinted(_ hex: UInt32, _ opacity: Double, on foreground: UInt32) -> LabelTone {
        LabelTone(background: .rgb(hex, opacity: opacity), foreground: .hex(foreground))
    }
}

/// A label definition. `key` is the stable slug stored on tasks; `name` is what
/// the user sees on the chip.
struct LabelDef: Identifiable, Hashable, Sendable, Codable {
    var key: String
    var name: String
    var light: LabelTone
    var dark: LabelTone

    var id: String { key }

    func tone(for colorScheme: ColorScheme) -> LabelTone {
        colorScheme == .dark ? dark : light
    }
}

extension LabelDef {
    /// The five labels the board ships with.
    ///
    /// `key` is the slug tasks store and never moves; `name` is what the chip
    /// draws, so it is translated at seed time and left alone from then on —
    /// once the board exists the name is the user's to change. iOS and API are
    /// acronyms and will come back from most translators unchanged, which is
    /// the right answer rather than a missed one.
    static let seed: [LabelDef] = [
        LabelDef(key: "design", name: String(localized: "Design", comment: "Seed label"),
                 light: .tinted(0xC2532F, 0.12, on: 0x9E3E1F),
                 dark: .tinted(0xE87C58, 0.20, on: 0xF1B49B)),
        LabelDef(key: "ios", name: String(localized: "iOS", comment: "Seed label: Apple's mobile platform"),
                 light: .tinted(0x1F6F63, 0.13, on: 0x175A50),
                 dark: .tinted(0x50BEAA, 0.18, on: 0x87DBC9)),
        LabelDef(key: "api", name: String(localized: "API", comment: "Seed label: server work"),
                 light: LabelTone(background: .ink(opacity: 0.08), foreground: .ink(opacity: 0.6)),
                 dark: LabelTone(background: .ink(opacity: 0.10), foreground: .ink(opacity: 0.65))),
        LabelDef(key: "bug", name: String(localized: "Bug", comment: "Seed label: something broken"),
                 light: .tinted(0xBE2828, 0.12, on: 0xA32222),
                 dark: .tinted(0xF05A5A, 0.18, on: 0xF5A0A0)),
        LabelDef(key: "polish", name: String(localized: "Polish", comment: "Seed label: refinement work, not the language"),
                 light: .tinted(0xC98A16, 0.15, on: 0x8A5D06),
                 dark: .tinted(0xE6AF3C, 0.18, on: 0xEFCB84)),
    ]

    /// One colour a label can be given, in both schemes, under a name.
    ///
    /// `Board.Dot`'s counterpart for the thing that carries a background and a
    /// foreground rather than a single dot. The name is here beside the hexes
    /// rather than in the picker for the same reason: a swatch announced as
    /// "Colour 4" tells a VoiceOver user its position and nothing about what
    /// choosing it does, and a name kept in the view drifts from the colour the
    /// moment either is edited.
    struct PaletteEntry: Identifiable, Hashable, Sendable {
        var light: LabelTone
        var dark: LabelTone
        var name: String

        var id: LabelTone { light }
        var tone: (light: LabelTone, dark: LabelTone) { (light, dark) }
    }

    /// Colours handed out, in order, to labels the user creates. The names are
    /// the ones `Board.dots` already uses wherever the hex is the same one.
    static let tones: [PaletteEntry] = [
        PaletteEntry(light: .tinted(0x3B5BA9, 0.12, on: 0x2F4A8C),
                     dark: .tinted(0x6E96F0, 0.18, on: 0xA9C2F7),
                     name: String(localized: "Indigo", comment: "Label colour")),
        PaletteEntry(light: .tinted(0x783CA0, 0.12, on: 0x6A3C9E),
                     dark: .tinted(0xB478F0, 0.18, on: 0xCDAEF5),
                     name: String(localized: "Violet", comment: "Label colour")),
        PaletteEntry(light: .tinted(0x1F6F63, 0.13, on: 0x175A50),
                     dark: .tinted(0x50BEAA, 0.18, on: 0x87DBC9),
                     name: String(localized: "Pine", comment: "Label colour")),
        PaletteEntry(light: .tinted(0xBE2828, 0.12, on: 0xA32222),
                     dark: .tinted(0xF05A5A, 0.18, on: 0xF5A0A0),
                     name: String(localized: "Red", comment: "Label colour")),
        PaletteEntry(light: .tinted(0xC98A16, 0.15, on: 0x8A5D06),
                     dark: .tinted(0xE6AF3C, 0.18, on: 0xEFCB84),
                     name: String(localized: "Amber", comment: "Label colour")),
        PaletteEntry(light: LabelTone(background: .ink(opacity: 0.08), foreground: .ink(opacity: 0.6)),
                     dark: LabelTone(background: .ink(opacity: 0.10), foreground: .ink(opacity: 0.65)),
                     name: String(localized: "Stone", comment: "Label colour")),
    ]

    /// The tones alone, which is what `recolorLabel` and the round-robin in
    /// `addLabel` take. `Board.dotPalette` stands in the same place.
    static var palette: [(light: LabelTone, dark: LabelTone)] { tones.map(\.tone) }

    /// Slugifies user input the way the spec does: lowercase, non-alphanumerics
    /// collapsed to single hyphens — then trimmed, so "Infra Work!" is
    /// `infra-work` and not `infra-work-`. A name of pure punctuation slugs to
    /// nothing, so it falls back to a unique key rather than an empty one.
    ///
    /// "Alphanumeric" is Unicode's rather than ASCII's, which is not cosmetic:
    /// against `[^a-z0-9]` a label called 設計 or Ошибка keeps not one character
    /// and takes the unique-key fallback, so typing the same name a second time
    /// mints a second key — and `createLabel` dedupes by key, so the board ends
    /// up with two labels a person cannot tell apart. Every non-Latin script hit
    /// that.
    ///
    /// The fold is `lowercased()` and not `lowercased(with: .current)` on
    /// purpose. A key is stored on every task carrying the label, so it has to
    /// mean the same thing on every device: a Turkish phone folding "I" to "ı"
    /// would mint a key nothing else could find.
    ///
    /// Keys already on disk keep resolving: this only affects labels made from
    /// here on, and nothing rewrites keys on load.
    static func key(from text: String) -> String {
        var slug = ""
        for character in text.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
            } else if slug.last != "-" {
                slug.append("-")
            }
        }
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !trimmed.isEmpty else { return "label-" + UUID().uuidString.prefix(8).lowercased() }
        return trimmed
    }
}
