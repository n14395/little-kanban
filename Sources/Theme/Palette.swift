import SwiftUI

/// The four accent options the design exposes as an editable prop.
enum AccentTheme: String, CaseIterable, Identifiable, Sendable, Codable {
    case ember, pine, indigo, ink

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ember: "Ember"
        case .pine: "Pine"
        case .indigo: "Indigo"
        case .ink: "Ink"
        }
    }

    /// The accent as a literal, for the places that need the *value* and not
    /// the colour — deriving a label's four tones from it, mostly, where the
    /// arithmetic happens in the model and there is no `Color` to take apart.
    ///
    /// `nil` for Ink, which is not a hex: it is the theme's own ink and differs
    /// between light and dark. A caller that needs a number has to say what it
    /// means by the absence of one.
    var hex: UInt32? {
        switch self {
        case .ember: 0xC2532F
        case .pine: 0x1F6F63
        case .indigo: 0x3B5BA9
        case .ink: nil
        }
    }
}

/// Colour tokens lifted from the design's `[data-theme="light"]` /
/// `[data-theme="dark"]` blocks.
///
/// Anything the spec writes as `rgba(var(--ink-rgb), a)` goes through
/// ``ink(_:)`` and anything written as `rgba(var(--sh-rgb), a)` goes through
/// ``shadow(_:)`` — those two differ in dark mode, where shadows go pure black
/// while ink goes near-white.
struct Palette: Equatable, Sendable {
    var colorScheme: ColorScheme
    var accentTheme: AccentTheme = .ember

    private var isDark: Bool { colorScheme == .dark }

    // MARK: Ink & shadow

    /// `--ink-rgb`
    private var inkHex: UInt32 { isDark ? 0xEEEAE2 : 0x171310 }
    /// `--sh-rgb`
    private var shadowHex: UInt32 { isDark ? 0x000000 : 0x171310 }

    var ink: Color { Color(hex: inkHex) }
    func ink(_ opacity: Double) -> Color { Color(hex: inkHex, opacity: opacity) }
    func shadow(_ opacity: Double) -> Color { Color(hex: shadowHex, opacity: opacity) }

    // MARK: Surfaces

    /// `--win` — the macOS window body.
    var window: Color { Color(hex: isDark ? 0x191614 : 0xFCFBF9) }
    /// `--side` — sidebar and iOS navigation drawer.
    var sidebar: Color { Color(hex: isDark ? 0x141211 : 0xF1EDE6) }
    /// `--card` — task cards and popovers.
    var card: Color { Color(hex: isDark ? 0x221E1B : 0xFFFFFF) }
    /// `--panel` — the macOS inspector.
    var panel: Color { Color(hex: isDark ? 0x171514 : 0xFAF8F4) }
    /// `--app` — the iOS app background.
    var appBackground: Color { Color(hex: isDark ? 0x131110 : 0xF6F3EE) }
    /// `--sheet` — the iOS detail sheet.
    var sheet: Color { Color(hex: isDark ? 0x1C1917 : 0xFBF9F5) }

    // MARK: Accent

    var accent: Color {
        accentTheme.hex.map { Color(hex: $0) } ?? ink
    }

    var accentSoft: Color {
        switch accentTheme {
        case .ember: Color(hex: 0xC2532F, opacity: 0.12)
        case .pine: Color(hex: 0x1F6F63, opacity: 0.13)
        case .indigo: Color(hex: 0x3B5BA9, opacity: 0.12)
        case .ink: ink(0.08)
        }
    }

    // MARK: Resolution

    func resolve(_ swatch: SwatchColor) -> Color {
        switch swatch {
        case .rgb(let hex, let opacity): Color(hex: hex, opacity: opacity)
        case .ink(let opacity): ink(opacity)
        case .accent: accent
        }
    }

    func resolve(_ tone: LabelTone) -> (background: Color, foreground: Color) {
        (resolve(tone.background), resolve(tone.foreground))
    }
}

extension EnvironmentValues {
    @Entry var palette = Palette(colorScheme: .light)
}
