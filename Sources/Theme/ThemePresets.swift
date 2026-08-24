import Foundation

/// The twenty themes the app ships with, transcribed from the theme explorer.
///
/// **In the document's own order**, which is not the order they were designed
/// in: round two (`2a`–`2j`) is the first section of the page and round one
/// (`1a`–`1j`) the second, so ``ember`` is the eleventh of the twenty. The ids
/// are the document's references, kept so that a conversation about "1e" and a
/// theme in the picker are the same thing.
///
/// **``ember`` is the reference point.** It is the shipping theme, tuned — the
/// flat charcoal opened out into a slow warm gradient and the accent taken a
/// little hotter — so it is the one to read against the app to see what a
/// parameter does. ``porcelain`` is the quietest of the light ten and stands in
/// the light slot for the same reason.
///
/// Nothing here is editable. A preset the user changes becomes a copy of their
/// own — see ``Theme/duplicated(named:)`` — because a reference point that can
/// be overwritten is not one.
enum ThemePresets {
    /// The default dark slot: the theme this app has always worn.
    static let emberID = "1a"
    /// The default light slot. There is no light twin of Ember in the twenty,
    /// and Porcelain is the document's own light control — warm whites, ink
    /// text, one vermilion accent.
    static let porcelainID = "2h"

    static func isPresetID(_ id: Theme.ID) -> Bool { byID[id] != nil }

    static func theme(_ id: Theme.ID) -> Theme? { byID[id] }

    private static let byID: [Theme.ID: Theme] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The default for a slot, used when a board file names a theme that is not
    /// installed — an import from a machine that had a custom theme this one has
    /// never seen, most likely — and by a board that has never chosen one.
    static func fallback(for appearance: ThemeAppearance) -> Theme {
        let id = appearance == .dark ? emberID : porcelainID
        // Force-unwrapped against a constant in the same file: if `1a` is not in
        // the list the list is wrong, and a silent grey app is a worse way to
        // find that out than a crash in the first test that runs.
        return byID[id]!
    }

    static let all: [Theme] = [
        // MARK: Round two

        Theme(
            id: "2a", name: "Oxblood", appearance: .dark,
            displayFont: ThemeFont("Libre Caslon Text", weight: 400, italic: false),
            uiFont: ThemeFont("Manrope"),
            windowBackground: ThemeGradient(155, (ThemeColor(0x3E1220), 0), (ThemeColor(0x22090F), 0.55), (ThemeColor(0x0E0406), 1)),
            panelOverlay: ThemeColor(0x000000, opacity: 0.34),
            card: ThemeCard(
                fill: ThemeColor(0x2C141C),
                border: ThemeColor(0xF4EAE6, opacity: 0.09),
                radius: 11
            ),
            ink: ThemeInk(base: ThemeColor(0xF4EAE6), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xF4EAE6, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xE07A6B),
                soft: ThemeColor(0xE07A6B, opacity: 0.15),
                onAccent: ThemeColor(0x33100A)
            ),
            status: ThemeStatus(done: ThemeColor(0x5FAF8E), medium: ThemeColor(0xD8A048)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        ),
        Theme(
            id: "2b", name: "Glacier", appearance: .light,
            displayFont: ThemeFont("Sora", weight: 500, italic: false),
            uiFont: ThemeFont("Public Sans"),
            windowBackground: ThemeGradient(145, (ThemeColor(0xEAF4FF), 0), (ThemeColor(0xC9DDF2), 0.55), (ThemeColor(0xA9C2DE), 1)),
            panelOverlay: ThemeColor(0xFFFFFF, opacity: 0.58),
            card: ThemeCard(
                fill: ThemeColor(0xFDFEFF),
                border: ThemeColor(0x101C2C, opacity: 0.1),
                radius: 10
            ),
            ink: ThemeInk(base: ThemeColor(0x101C2C), muted: 0.62, faint: 0.42),
            wash: ThemeColor(0x101C2C, opacity: 0.08),
            highlight: ThemeHighlight(
                accent: ThemeColor(0x1B5FE0),
                soft: ThemeColor(0x1B5FE0, opacity: 0.11),
                onAccent: ThemeColor(0xF0F5FF)
            ),
            status: ThemeStatus(done: ThemeColor(0x1F8A66), medium: ThemeColor(0xC08A10)),
            labelChips: .light,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xBE2828, opacity: 0.13), foreground: ThemeColor(0xA32222)),
                warm: ThemeChip(background: ThemeColor(0xC8466E, opacity: 0.13), foreground: ThemeColor(0xA03356))
            )
        ),
        Theme(
            id: "2c", name: "Rainforest", appearance: .dark,
            displayFont: ThemeFont("Bricolage Grotesque", weight: 600, italic: false),
            uiFont: ThemeFont("Work Sans"),
            windowBackground: ThemeGradient(140, (ThemeColor(0x04382C), 0), (ThemeColor(0x0A5A40), 0.5), (ThemeColor(0x0E7A3E), 1)),
            panelOverlay: ThemeColor(0x01140E, opacity: 0.45),
            card: ThemeCard(
                fill: ThemeColor(0x062A20, opacity: 0.88),
                border: ThemeColor(0xE8F4EA, opacity: 0.11),
                radius: 13
            ),
            ink: ThemeInk(base: ThemeColor(0xE8F4EA), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xE8F4EA, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xF5D33F),
                soft: ThemeColor(0xF5D33F, opacity: 0.15),
                onAccent: ThemeColor(0x2E2604)
            ),
            status: ThemeStatus(done: ThemeColor(0x5BE0A0), medium: ThemeColor(0xF5D33F)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        ),
        Theme(
            id: "2d", name: "Flamingo", appearance: .light,
            displayFont: ThemeFont("DM Sans", weight: 500, italic: false),
            uiFont: ThemeFont("DM Sans"),
            windowBackground: ThemeGradient(135, (ThemeColor(0xFF9A8B), 0), (ThemeColor(0xFF6A88), 0.55), (ThemeColor(0xFF99AC), 1)),
            panelOverlay: ThemeColor(0xFFF8F8, opacity: 0.55),
            card: ThemeCard(
                fill: ThemeColor(0xFFFEFE),
                border: ThemeColor(0x34101C, opacity: 0.1),
                radius: 14
            ),
            ink: ThemeInk(base: ThemeColor(0x34101C), muted: 0.62, faint: 0.42),
            wash: ThemeColor(0x34101C, opacity: 0.08),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xD6246E),
                soft: ThemeColor(0xD6246E, opacity: 0.11),
                onAccent: ThemeColor(0xFFF2F7)
            ),
            status: ThemeStatus(done: ThemeColor(0x1F8A66), medium: ThemeColor(0xC98A0F)),
            labelChips: .light,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xBE2828, opacity: 0.13), foreground: ThemeColor(0xA32222)),
                warm: ThemeChip(background: ThemeColor(0xC8466E, opacity: 0.13), foreground: ThemeColor(0xA03356))
            )
        ),
        Theme(
            id: "2e", name: "Nocturne", appearance: .dark,
            displayFont: ThemeFont("Spectral", weight: 600, italic: false),
            uiFont: ThemeFont("IBM Plex Sans"),
            windowBackground: ThemeGradient(160, (ThemeColor(0x232A44), 0), (ThemeColor(0x171C30), 0.55), (ThemeColor(0x0E1020), 1)),
            panelOverlay: ThemeColor(0x040610, opacity: 0.4),
            card: ThemeCard(
                fill: ThemeColor(0x222842),
                border: ThemeColor(0xEAECF4, opacity: 0.09),
                radius: 11
            ),
            ink: ThemeInk(base: ThemeColor(0xEAECF4), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xEAECF4, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xA78BFA),
                soft: ThemeColor(0xA78BFA, opacity: 0.15),
                onAccent: ThemeColor(0x1E1038)
            ),
            status: ThemeStatus(done: ThemeColor(0x5FC49A), medium: ThemeColor(0xD8AC40)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        ),
        Theme(
            id: "2f", name: "Honey", appearance: .light,
            displayFont: ThemeFont("Crimson Pro", weight: 600, italic: false),
            uiFont: ThemeFont("Epilogue"),
            windowBackground: ThemeGradient(150, (ThemeColor(0xFFE8B0), 0), (ThemeColor(0xF7C873), 0.55), (ThemeColor(0xE0A445), 1)),
            panelOverlay: ThemeColor(0xFFFAEE, opacity: 0.55),
            card: ThemeCard(
                fill: ThemeColor(0xFFFBF2),
                border: ThemeColor(0x2D1A08, opacity: 0.11),
                radius: 12
            ),
            ink: ThemeInk(base: ThemeColor(0x2D1A08), muted: 0.62, faint: 0.42),
            wash: ThemeColor(0x2D1A08, opacity: 0.08),
            highlight: ThemeHighlight(
                accent: ThemeColor(0x7A4A12),
                soft: ThemeColor(0x7A4A12, opacity: 0.13),
                onAccent: ThemeColor(0xFFF6E6)
            ),
            status: ThemeStatus(done: ThemeColor(0x3B7A4E), medium: ThemeColor(0xB07C0C)),
            labelChips: .light,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xBE2828, opacity: 0.13), foreground: ThemeColor(0xA32222)),
                warm: ThemeChip(background: ThemeColor(0xC8466E, opacity: 0.13), foreground: ThemeColor(0xA03356))
            )
        ),
        Theme(
            id: "2g", name: "Neon Grid", appearance: .dark,
            displayFont: ThemeFont("Space Grotesk", weight: 500, italic: false),
            uiFont: ThemeFont("Archivo"),
            windowBackground: ThemeGradient(120, (ThemeColor(0x0A0A0F), 0), (ThemeColor(0x141024), 0.45), (ThemeColor(0x351449), 0.78), (ThemeColor(0xB0186E), 1)),
            panelOverlay: ThemeColor(0x000000, opacity: 0.42),
            card: ThemeCard(
                fill: ThemeColor(0x181624),
                border: ThemeColor(0xF0EEF6, opacity: 0.1),
                radius: 10
            ),
            ink: ThemeInk(base: ThemeColor(0xF0EEF6), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xF0EEF6, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xFF3D9A),
                soft: ThemeColor(0xFF3D9A, opacity: 0.16),
                onAccent: ThemeColor(0xFFF0F7)
            ),
            status: ThemeStatus(done: ThemeColor(0x3DE0B0), medium: ThemeColor(0xE8C15A)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        ),
        Theme(
            id: "2h", name: "Porcelain", appearance: .light,
            displayFont: ThemeFont("Newsreader", weight: 500, italic: true),
            uiFont: ThemeFont("Familjen Grotesk"),
            windowBackground: ThemeGradient(165, (ThemeColor(0xFBFAF7), 0), (ThemeColor(0xF2EFE8), 0.6), (ThemeColor(0xE7E2D6), 1)),
            panelOverlay: ThemeColor(0xFFFFFF, opacity: 0.62),
            card: ThemeCard(
                fill: ThemeColor(0xFFFFFF),
                border: ThemeColor(0x201C14, opacity: 0.09),
                radius: 10
            ),
            ink: ThemeInk(base: ThemeColor(0x201C14), muted: 0.62, faint: 0.42),
            wash: ThemeColor(0x5C3F20, opacity: 0.08),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xD4491F),
                soft: ThemeColor(0xD4491F, opacity: 0.1),
                onAccent: ThemeColor(0xFFF4EF)
            ),
            status: ThemeStatus(done: ThemeColor(0x2F7D4F), medium: ThemeColor(0xB98A12)),
            labelChips: .light,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xBE2828, opacity: 0.13), foreground: ThemeColor(0xA32222)),
                warm: ThemeChip(background: ThemeColor(0xC8466E, opacity: 0.13), foreground: ThemeColor(0xA03356))
            )
        ),
        Theme(
            id: "2i", name: "Tidepool", appearance: .light,
            displayFont: ThemeFont("IBM Plex Serif", weight: 600, italic: false),
            uiFont: ThemeFont("DM Sans"),
            windowBackground: ThemeGradient(170, (ThemeColor(0xE2F7F4), 0), (ThemeColor(0xB8E6DC), 0.55), (ThemeColor(0x8FCFC4), 1)),
            panelOverlay: ThemeColor(0xFAFFFE, opacity: 0.58),
            card: ThemeCard(
                fill: ThemeColor(0xFDFFFE),
                border: ThemeColor(0x0C2A2A, opacity: 0.1),
                radius: 12
            ),
            ink: ThemeInk(base: ThemeColor(0x0C2A2A), muted: 0.62, faint: 0.42),
            wash: ThemeColor(0x0C2A2A, opacity: 0.08),
            highlight: ThemeHighlight(
                accent: ThemeColor(0x0E7C74),
                soft: ThemeColor(0x0E7C74, opacity: 0.11),
                onAccent: ThemeColor(0xEDFBF9)
            ),
            status: ThemeStatus(done: ThemeColor(0x0E7C74), medium: ThemeColor(0xB98A12)),
            labelChips: .light,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xBE2828, opacity: 0.13), foreground: ThemeColor(0xA32222)),
                warm: ThemeChip(background: ThemeColor(0xC8466E, opacity: 0.13), foreground: ThemeColor(0xA03356))
            )
        ),
        Theme(
            id: "2j", name: "Eclipse", appearance: .dark,
            displayFont: ThemeFont("Epilogue", weight: 500, italic: false),
            uiFont: ThemeFont("Epilogue"),
            windowBackground: ThemeGradient(0, (ThemeColor(0x3D1A05), 0), (ThemeColor(0x170A03), 0.28), (ThemeColor(0x000000), 0.62)),
            panelOverlay: ThemeColor(0xFFFFFF, opacity: 0.035),
            card: ThemeCard(
                fill: ThemeColor(0x161311),
                border: ThemeColor(0xF2EEEA, opacity: 0.1),
                radius: 11
            ),
            ink: ThemeInk(base: ThemeColor(0xF2EEEA), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xF2EEEA, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xFF7A1A),
                soft: ThemeColor(0xFF7A1A, opacity: 0.15),
                onAccent: ThemeColor(0x2E1500)
            ),
            status: ThemeStatus(done: ThemeColor(0x58B896), medium: ThemeColor(0xE0A83A)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        ),

        // MARK: Round one

        Theme(
            id: "1a", name: "Ember", appearance: .dark,
            displayFont: ThemeFont("Instrument Serif", weight: 400, italic: false),
            uiFont: ThemeFont("Manrope"),
            windowBackground: ThemeGradient(160, (ThemeColor(0x2A1E15), 0), (ThemeColor(0x17110D), 0.55), (ThemeColor(0x0D0A08), 1)),
            panelOverlay: ThemeColor(0x000000, opacity: 0.32),
            card: ThemeCard(
                fill: ThemeColor(0x28211A),
                border: ThemeColor(0xF3EDE4, opacity: 0.08),
                radius: 11
            ),
            ink: ThemeInk(base: ThemeColor(0xF3EDE4), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xF3EDE4, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xE8703F),
                soft: ThemeColor(0xE8703F, opacity: 0.16),
                onAccent: ThemeColor(0xFFF7F2)
            ),
            status: ThemeStatus(done: ThemeColor(0x58B896), medium: ThemeColor(0xE2B33C)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        ),
        Theme(
            id: "1b", name: "Aurora", appearance: .dark,
            displayFont: ThemeFont("Space Grotesk", weight: 500, italic: false),
            uiFont: ThemeFont("Space Grotesk"),
            windowBackground: ThemeGradient(140, (ThemeColor(0x0A1B3F), 0), (ThemeColor(0x12414F), 0.48), (ThemeColor(0x2A1B5E), 1)),
            panelOverlay: ThemeColor(0x040A1A, opacity: 0.45),
            card: ThemeCard(
                fill: ThemeColor(0x0D1C34, opacity: 0.85),
                border: ThemeColor(0xE8F0F8, opacity: 0.1),
                radius: 11
            ),
            ink: ThemeInk(base: ThemeColor(0xE8F0F8), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xE8F0F8, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0x4FE3C1),
                soft: ThemeColor(0x4FE3C1, opacity: 0.14),
                onAccent: ThemeColor(0x04241C)
            ),
            status: ThemeStatus(done: ThemeColor(0x4FE3C1), medium: ThemeColor(0xE8C15A)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        ),
        Theme(
            id: "1c", name: "Daybreak", appearance: .light,
            displayFont: ThemeFont("Newsreader", weight: 500, italic: false),
            uiFont: ThemeFont("Work Sans"),
            windowBackground: ThemeGradient(150, (ThemeColor(0xFFEDE0), 0), (ThemeColor(0xFFD9CF), 0.52), (ThemeColor(0xF6C6D8), 1)),
            panelOverlay: ThemeColor(0xFFFCF8, opacity: 0.55),
            card: ThemeCard(
                fill: ThemeColor(0xFFFDFB),
                border: ThemeColor(0x241713, opacity: 0.1),
                radius: 12
            ),
            ink: ThemeInk(base: ThemeColor(0x241713), muted: 0.62, faint: 0.42),
            wash: ThemeColor(0x241713, opacity: 0.08),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xE0492F),
                soft: ThemeColor(0xE0492F, opacity: 0.12),
                onAccent: ThemeColor(0xFFF6F2)
            ),
            status: ThemeStatus(done: ThemeColor(0x1F7A55), medium: ThemeColor(0xC9880F)),
            labelChips: .light,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xBE2828, opacity: 0.13), foreground: ThemeColor(0xA32222)),
                warm: ThemeChip(background: ThemeColor(0xC8466E, opacity: 0.13), foreground: ThemeColor(0xA03356))
            )
        ),
        Theme(
            id: "1d", name: "Ultraviolet", appearance: .dark,
            displayFont: ThemeFont("Sora", weight: 500, italic: false),
            uiFont: ThemeFont("Sora"),
            windowBackground: ThemeGradient(135, (ThemeColor(0x3A0CA3), 0), (ThemeColor(0x7209B7), 0.5), (ThemeColor(0xB5179E), 1)),
            panelOverlay: ThemeColor(0x140430, opacity: 0.42),
            card: ThemeCard(
                fill: ThemeColor(0x220A40, opacity: 0.88),
                border: ThemeColor(0xF5EEFA, opacity: 0.14),
                radius: 13
            ),
            ink: ThemeInk(base: ThemeColor(0xF5EEFA), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xF5EEFA, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xFFD166),
                soft: ThemeColor(0xFFD166, opacity: 0.16),
                onAccent: ThemeColor(0x3A2400)
            ),
            status: ThemeStatus(done: ThemeColor(0x7CF2C0), medium: ThemeColor(0xFFD166)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        ),
        Theme(
            id: "1e", name: "Deep Sea", appearance: .dark,
            displayFont: ThemeFont("IBM Plex Serif", weight: 600, italic: false),
            uiFont: ThemeFont("IBM Plex Sans"),
            windowBackground: ThemeGradient(180, (ThemeColor(0x03264D), 0), (ThemeColor(0x075A7A), 0.68), (ThemeColor(0x0B8FA0), 1)),
            panelOverlay: ThemeColor(0x021226, opacity: 0.5),
            card: ThemeCard(
                fill: ThemeColor(0x082C4E, opacity: 0.88),
                border: ThemeColor(0xE6F3F8, opacity: 0.11),
                radius: 10
            ),
            ink: ThemeInk(base: ThemeColor(0xE6F3F8), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xE6F3F8, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0x5BE7F0),
                soft: ThemeColor(0x5BE7F0, opacity: 0.14),
                onAccent: ThemeColor(0x032A30)
            ),
            status: ThemeStatus(done: ThemeColor(0x5BE7A8), medium: ThemeColor(0xE8C15A)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        ),
        Theme(
            id: "1f", name: "Meadow", appearance: .light,
            displayFont: ThemeFont("Spectral", weight: 600, italic: false),
            uiFont: ThemeFont("Public Sans"),
            windowBackground: ThemeGradient(160, (ThemeColor(0xF6F3E7), 0), (ThemeColor(0xDCEAD3), 0.55), (ThemeColor(0xBFDCC4), 1)),
            panelOverlay: ThemeColor(0xFCFBF4, opacity: 0.6),
            card: ThemeCard(
                fill: ThemeColor(0xFEFDF8),
                border: ThemeColor(0x1A2018, opacity: 0.1),
                radius: 12
            ),
            ink: ThemeInk(base: ThemeColor(0x1A2018), muted: 0.62, faint: 0.42),
            wash: ThemeColor(0x1A2018, opacity: 0.08),
            highlight: ThemeHighlight(
                accent: ThemeColor(0x2F7D4F),
                soft: ThemeColor(0x2F7D4F, opacity: 0.12),
                onAccent: ThemeColor(0xF2FBF5)
            ),
            status: ThemeStatus(done: ThemeColor(0x2F7D4F), medium: ThemeColor(0xB98A12)),
            labelChips: .light,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xBE2828, opacity: 0.13), foreground: ThemeColor(0xA32222)),
                warm: ThemeChip(background: ThemeColor(0xC8466E, opacity: 0.13), foreground: ThemeColor(0xA03356))
            )
        ),
        Theme(
            id: "1g", name: "Graphite", appearance: .dark,
            displayFont: ThemeFont("Archivo", weight: 500, italic: false),
            uiFont: ThemeFont("Archivo"),
            windowBackground: ThemeGradient(170, (ThemeColor(0x1F2226), 0), (ThemeColor(0x151719), 0.6), (ThemeColor(0x101214), 1)),
            panelOverlay: ThemeColor(0x000000, opacity: 0.3),
            card: ThemeCard(
                fill: ThemeColor(0x1E2126),
                border: ThemeColor(0xECEEF2, opacity: 0.08),
                radius: 9
            ),
            ink: ThemeInk(base: ThemeColor(0xECEEF2), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xECEEF2, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0x4D7CFE),
                soft: ThemeColor(0x4D7CFE, opacity: 0.15),
                onAccent: ThemeColor(0xF2F6FF)
            ),
            status: ThemeStatus(done: ThemeColor(0x4EC08F), medium: ThemeColor(0xD8A62E)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        ),
        Theme(
            id: "1h", name: "Candy", appearance: .light,
            displayFont: ThemeFont("Bricolage Grotesque", weight: 600, italic: false),
            uiFont: ThemeFont("DM Sans"),
            windowBackground: ThemeGradient(130, (ThemeColor(0xBFE3FF), 0), (ThemeColor(0xE7D6FF), 0.5), (ThemeColor(0xFFD3E8), 1)),
            panelOverlay: ThemeColor(0xFFFFFF, opacity: 0.55),
            card: ThemeCard(
                fill: ThemeColor(0xFFFFFF),
                border: ThemeColor(0x1E162E, opacity: 0.09),
                radius: 16
            ),
            ink: ThemeInk(base: ThemeColor(0x1E162E), muted: 0.62, faint: 0.42),
            wash: ThemeColor(0x1E162E, opacity: 0.08),
            highlight: ThemeHighlight(
                accent: ThemeColor(0x7048E8),
                soft: ThemeColor(0x7048E8, opacity: 0.12),
                onAccent: ThemeColor(0xF6F2FF)
            ),
            status: ThemeStatus(done: ThemeColor(0x1F9E6E), medium: ThemeColor(0xD69412)),
            labelChips: .light,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xBE2828, opacity: 0.13), foreground: ThemeColor(0xA32222)),
                warm: ThemeChip(background: ThemeColor(0xC8466E, opacity: 0.13), foreground: ThemeColor(0xA03356))
            )
        ),
        Theme(
            id: "1i", name: "Terracotta", appearance: .light,
            displayFont: ThemeFont("Crimson Pro", weight: 600, italic: false),
            uiFont: ThemeFont("Familjen Grotesk"),
            windowBackground: ThemeGradient(155, (ThemeColor(0xF1D9C4), 0), (ThemeColor(0xE0B294), 0.55), (ThemeColor(0xC1815F), 1)),
            panelOverlay: ThemeColor(0xFBF4EC, opacity: 0.55),
            card: ThemeCard(
                fill: ThemeColor(0xFBF4EC),
                border: ThemeColor(0x2C1810, opacity: 0.11),
                radius: 11
            ),
            ink: ThemeInk(base: ThemeColor(0x2C1810), muted: 0.62, faint: 0.42),
            wash: ThemeColor(0x2C1810, opacity: 0.08),
            highlight: ThemeHighlight(
                accent: ThemeColor(0x9C3D1E),
                soft: ThemeColor(0x9C3D1E, opacity: 0.13),
                onAccent: ThemeColor(0xFDF3EC)
            ),
            status: ThemeStatus(done: ThemeColor(0x356B4C), medium: ThemeColor(0xA87710)),
            labelChips: .light,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xBE2828, opacity: 0.13), foreground: ThemeColor(0xA32222)),
                warm: ThemeChip(background: ThemeColor(0xC8466E, opacity: 0.13), foreground: ThemeColor(0xA03356))
            )
        ),
        Theme(
            id: "1j", name: "Midnight Gold", appearance: .dark,
            displayFont: ThemeFont("Instrument Serif", weight: 400, italic: true),
            uiFont: ThemeFont("Epilogue"),
            windowBackground: ThemeGradient(165, (ThemeColor(0x131538), 0), (ThemeColor(0x0A0B1C), 0.55), (ThemeColor(0x050609), 1)),
            panelOverlay: ThemeColor(0x000000, opacity: 0.36),
            card: ThemeCard(
                fill: ThemeColor(0x16182E),
                border: ThemeColor(0xF0ECE2, opacity: 0.09),
                radius: 11
            ),
            ink: ThemeInk(base: ThemeColor(0xF0ECE2), muted: 0.62, faint: 0.4),
            wash: ThemeColor(0xF0ECE2, opacity: 0.09),
            highlight: ThemeHighlight(
                accent: ThemeColor(0xD9B45B),
                soft: ThemeColor(0xD9B45B, opacity: 0.14),
                onAccent: ThemeColor(0x241A04)
            ),
            status: ThemeStatus(done: ThemeColor(0x6BBF9A), medium: ThemeColor(0xD9B45B)),
            labelChips: .dark,
            dueChips: ThemeDueChips(
                hot: ThemeChip(background: ThemeColor(0xF05A5A, opacity: 0.22), foreground: ThemeColor(0xF5A0A0)),
                warm: ThemeChip(background: ThemeColor(0xEB8C96, opacity: 0.2), foreground: ThemeColor(0xF0B7BE))
            )
        )
    ]
}
