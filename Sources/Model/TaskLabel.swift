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
    static let seed: [LabelDef] = [
        LabelDef(key: "design", name: "Design",
                 light: .tinted(0xC2532F, 0.12, on: 0x9E3E1F),
                 dark: .tinted(0xE87C58, 0.20, on: 0xF1B49B)),
        LabelDef(key: "ios", name: "iOS",
                 light: .tinted(0x1F6F63, 0.13, on: 0x175A50),
                 dark: .tinted(0x50BEAA, 0.18, on: 0x87DBC9)),
        LabelDef(key: "api", name: "API",
                 light: LabelTone(background: .ink(opacity: 0.08), foreground: .ink(opacity: 0.6)),
                 dark: LabelTone(background: .ink(opacity: 0.10), foreground: .ink(opacity: 0.65))),
        LabelDef(key: "bug", name: "Bug",
                 light: .tinted(0xBE2828, 0.12, on: 0xA32222),
                 dark: .tinted(0xF05A5A, 0.18, on: 0xF5A0A0)),
        LabelDef(key: "polish", name: "Polish",
                 light: .tinted(0xC98A16, 0.15, on: 0x8A5D06),
                 dark: .tinted(0xE6AF3C, 0.18, on: 0xEFCB84)),
    ]

    /// Colours handed out, in order, to labels the user creates.
    static let palette: [(light: LabelTone, dark: LabelTone)] = [
        (.tinted(0x3B5BA9, 0.12, on: 0x2F4A8C), .tinted(0x6E96F0, 0.18, on: 0xA9C2F7)),
        (.tinted(0x783CA0, 0.12, on: 0x6A3C9E), .tinted(0xB478F0, 0.18, on: 0xCDAEF5)),
        (.tinted(0x1F6F63, 0.13, on: 0x175A50), .tinted(0x50BEAA, 0.18, on: 0x87DBC9)),
        (.tinted(0xBE2828, 0.12, on: 0xA32222), .tinted(0xF05A5A, 0.18, on: 0xF5A0A0)),
        (.tinted(0xC98A16, 0.15, on: 0x8A5D06), .tinted(0xE6AF3C, 0.18, on: 0xEFCB84)),
        (LabelTone(background: .ink(opacity: 0.08), foreground: .ink(opacity: 0.6)),
         LabelTone(background: .ink(opacity: 0.10), foreground: .ink(opacity: 0.65))),
    ]

    /// Slugifies user input the way the spec does: lowercase, non-alphanumerics
    /// collapsed to single hyphens — then trimmed, so "Infra Work!" is
    /// `infra-work` and not `infra-work-`. A name of pure punctuation slugs to
    /// nothing, so it falls back to a unique key rather than an empty one.
    ///
    /// Keys already on disk keep resolving: this only affects labels made from
    /// here on, and nothing rewrites keys on load.
    static func key(from text: String) -> String {
        let slug = text.lowercased().replacingOccurrences(
            of: "[^a-z0-9]+", with: "-", options: .regularExpression
        )
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !trimmed.isEmpty else { return "label-" + UUID().uuidString.prefix(8).lowercased() }
        return trimmed
    }
}
