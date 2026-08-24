import SwiftUI

/// A label's background/foreground pair for one colour scheme.
struct LabelTone: Hashable, Sendable, Codable {
    var background: SwatchColor
    var foreground: SwatchColor

    static func tinted(_ hex: UInt32, _ opacity: Double, on foreground: UInt32) -> LabelTone {
        LabelTone(background: .rgb(hex, opacity: opacity), foreground: .hex(foreground))
    }

    /// The four colours a chip needs, worked out from the one a picker returns.
    ///
    /// **Because a colour picker returns a colour and a label wears four.** A
    /// chip is a tinted ground with text on it, in both schemes, and the ten
    /// pairs the app shipped with were hand-tuned — which is fine for ten and
    /// impossible for "any colour the user mixes". So the pair is derived:
    /// the ground is the colour itself at a low opacity so it sits *on* the
    /// card rather than over it, and the text is the same hue taken away from
    /// the ground — darker in light mode, lighter in dark — because a chip
    /// whose text is a different colour from its ground reads as two things.
    ///
    /// The numbers are read off the seeds rather than invented: `Design` is
    /// `#C2532F` on a 12% ground with `#9E3E1F` text in light, and a lifted
    /// `#E87C58` ground with `#F1B49B` text in dark. See ``LabelDef/seed``,
    /// which keeps its hand-tuned values — nothing already on a board is
    /// repainted by this arriving.
    ///
    /// The **dark** ground is lifted before it is tinted. A dark chip is a
    /// low-opacity wash over a near-black card, and `#1F6F63` at 19% over that
    /// is almost the card: what the eye needs is the *lighter* relative of the
    /// colour, which is what the seeds all use.
    static func pair(from hex: UInt32) -> (light: LabelTone, dark: LabelTone) {
        (
            light: LabelTone(
                background: .rgb(hex, opacity: 0.13),
                foreground: .hex(ColorMath.shade(hex, by: -0.2))
            ),
            dark: LabelTone(
                background: .rgb(ColorMath.shade(hex, by: 0.45), opacity: 0.19),
                foreground: .hex(ColorMath.shade(hex, by: 0.78))
            )
        )
    }

    /// The pair for a colour that is not a literal: the theme's own ink, at the
    /// two weights the `API` seed label uses. A picker can return `.ink` — the
    /// palette has a grey in it — and there is no hue to derive anything from.
    /// The pair for a label painted with the accent, which is not a colour but
    /// a *reference* to one. Stored as the reference, so the label follows the
    /// theme the way a board dot painted accent does; the chip's two colours are
    /// worked out from it at render time by ``Palette/chipTone(for:)``.
    static let accentPair: (light: LabelTone, dark: LabelTone) = (
        light: LabelTone(background: .accent, foreground: .accent),
        dark: LabelTone(background: .accent, foreground: .accent)
    )

    static let inkPair: (light: LabelTone, dark: LabelTone) = (
        light: LabelTone(background: .ink(opacity: 0.08), foreground: .ink(opacity: 0.6)),
        dark: LabelTone(background: .ink(opacity: 0.10), foreground: .ink(opacity: 0.65))
    )
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

    /// The one colour a picker shows for this label, out of the four it wears.
    ///
    /// The light ground, at full strength: it *is* the colour the pair was
    /// derived from — see ``LabelTone/pair(from:)`` — so a label made from the
    /// palette's Ember comes back to the picker with Ember ringed. The opacity
    /// is dropped because the ground is a tint of the colour rather than the
    /// colour, and a swatch drawn at 13% is a swatch of the card behind it.
    var baseColor: SwatchColor {
        switch light.background {
        case .rgb(let value, _): .hex(value)
        case .ink(let opacity): .ink(opacity: opacity)
        case .accent: .accent
        }
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

    /// **The ten hand-tuned pairs that used to live here are gone.** A label's
    /// colour is picked from `BoardStore.savedColors` now, the same list a board
    /// and a column are picked from, and the four colours a chip wears are
    /// derived from the one that comes back — see ``LabelTone/pair(from:)``. Two
    /// palettes was the reason a colour saved while recolouring a board could
    /// not be given to a label.
    ///
    /// The seeds above keep their hand-tuned values on purpose: nothing already
    /// on a board is repainted by the derivation arriving.


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
