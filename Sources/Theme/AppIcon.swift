import SwiftUI

/// The icon's artwork, reduced to the three things the design ever varies.
///
/// **One shape, three colours.** Every icon in the design document's fourth and
/// fifth rounds is the same nine rectangles — the `2e` "capped columns" mark —
/// over a gradient ground. What changes between `4a` and `4j`, and between one
/// theme's icon and another's, is the ground, the colour of the three header
/// rules, and the colour of the six cards. Nothing else. So that is what this
/// carries, and there is one drawing rather than thirty.
///
/// ``ThemeGradient`` rather than a gradient type of its own, because it is the
/// same thing a theme's window is painted with and the theme-matched icons are
/// literally that value — see ``AppIcon/art(matching:)``.
struct AppIconArt: Hashable, Sendable {
    var ground: ThemeGradient
    /// The three header rules over the columns.
    var cap: ThemeColor
    /// The six cards under them.
    var card: ThemeColor

    /// The same artwork with every alpha spent.
    ///
    /// An icon has nothing behind it: a translucent stop on the Home Screen is
    /// a hole, not a tint. The twenty presets are opaque throughout, so this
    /// changes nothing for them — it is the guarantee a theme somebody built in
    /// the editor cannot break.
    var opaque: AppIconArt {
        AppIconArt(
            ground: ThemeGradient(
                angle: ground.angle,
                stops: ground.stops.map { .init(color: $0.color.solid, location: $0.location) }
            ),
            cap: cap.solid,
            card: card.solid
        )
    }
}

/// One of the ten grounds from **Capped columns — 10 bold gradients**.
///
/// The `id` is the design document's own reference, kept for
/// ``ThemePresets``'s reason: a conversation about "4f" and a tile in the
/// picker should be the same thing. It is also what is stored in preferences
/// and what names the icon in the asset catalogue.
struct AppIconGradient: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var art: AppIconArt
}

/// Which icon the app is wearing, as the user chose it rather than as it
/// resolves — the two switches in Settings, in one value.
///
/// A value rather than two reads of `Preferences` at each use, so the rule in
/// ``AppIcon/resolve(_:themes:appearance:)`` can be held up to a test without
/// touching global state that every other suite is reading at the same time.
struct AppIconSelection: Hashable, Sendable {
    var gradientID: String
    var followsTheme: Bool

    static let fallback = AppIconSelection(gradientID: AppIcon.defaultID, followsTheme: false)
}

/// An icon resolved down to what each platform needs to put it on screen.
///
/// The two halves answer the two platforms, and both are always filled in
/// because either may be asked. `art` is what macOS draws — see
/// ``AppIconInstaller`` — and `assetName` is what iOS names, `nil` meaning the
/// icon compiled into the bundle as `AppIcon`.
struct ResolvedAppIcon: Hashable, Sendable {
    var art: AppIconArt
    var name: String
    /// The asset catalogue entry, or `nil` for the built-in one.
    var assetName: String?
}

enum AppIcon {
    /// The icon the app ships wearing, and the one `AppIcon.appiconset` holds:
    /// `4g`, teal through jade to chartreuse. Changing this constant is not the
    /// whole of changing the default — the bundled set is rasterised from it,
    /// so `Tools/make-app-icons` has to be re-run to make the catalogue agree.
    static let defaultID = "4g"

    /// The **Capped columns — 10 bold gradients** round, transcribed.
    ///
    /// Every ground is three stops at 0, 50 and 100 per cent. Eight run corner
    /// to corner and two — `4i` and `4j` — run straight down, which is the
    /// document's own split and the reason the angle is written per entry
    /// rather than assumed. In ``ThemeGradient``'s CSS degrees, corner to
    /// corner on a square is 135° and top to bottom is 180°.
    static let all: [AppIconGradient] = [
        gradient("4a", "Violet → magenta", 135, 0x4A18C9, 0xB91FD9, 0xFF3D9A, mark: 0xFFFFFF),
        gradient("4b", "Cobalt → cyan", 135, 0x0B2FE0, 0x1E7BFF, 0x37E1F0, mark: 0xFFFFFF),
        gradient("4c", "Sunrise", 135, 0xFF2E6B, 0xFF7A2F, 0xFFC53D, mark: 0x20120C),
        gradient("4d", "Emerald → lime", 135, 0x04624F, 0x12A66B, 0x8CE64A, mark: 0xFFFFFF),
        gradient("4e", "Ink → electric", 135, 0x0A0D14, 0x1B2C6B, 0x3D7BFF, mark: 0xFFFFFF),
        gradient("4f", "Peach → violet", 135, 0xFFB48A, 0xE0559B, 0x7B2CD9, mark: 0xFFFFFF),
        gradient("4g", "Teal → chartreuse", 135, 0x00696E, 0x00B39A, 0xC3F53C, mark: 0x04231F),
        gradient("4h", "Crimson → gold", 135, 0xB3053A, 0xF0403B, 0xFFC93C, mark: 0xFFFFFF),
        gradient("4i", "Indigo → rose", 180, 0x2B1DA8, 0x7D2BD1, 0xFF5C8A, mark: 0xFFFFFF),
        gradient("4j", "Aqua → deep sea", 180, 0x5BE7F0, 0x1B86D9, 0x07306B, mark: 0xFFFFFF),
    ]

    /// **Caps and cards are one colour in all ten.** The bold round took the
    /// stepped opacity out of the mark deliberately — "the ground carries the
    /// depth and the mark stays a flat, single-colour silhouette" — so the ten
    /// pass one `mark` where a theme passes two. The pair stays in
    /// ``AppIconArt`` because the theme-matched icons do use two.
    private static func gradient(
        _ id: String, _ name: String, _ angle: Double,
        _ first: UInt32, _ middle: UInt32, _ last: UInt32, mark: UInt32
    ) -> AppIconGradient {
        AppIconGradient(
            id: id, name: name,
            art: AppIconArt(
                ground: ThemeGradient(
                    angle,
                    (ThemeColor(first), 0), (ThemeColor(middle), 0.5), (ThemeColor(last), 1)
                ),
                cap: ThemeColor(mark), card: ThemeColor(mark)
            )
        )
    }

    private static let byID: [String: AppIconGradient] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func gradient(_ id: String) -> AppIconGradient? { byID[id] }

    /// The default, force-unwrapped against a constant in the same file: if
    /// `4g` is not in the list above then the list is wrong, and an app with no
    /// icon is a worse way to find that out than a crash in the first test.
    static var fallback: AppIconGradient { byID[defaultID]! }

    // MARK: - Icons from themes

    /// A theme's own icon: **the window gradient becomes the ground, the
    /// highlight becomes the header caps, the ink becomes the cards.**
    ///
    /// The design document's fifth round draws all twenty this way, and this is
    /// that rule rather than twenty transcriptions of its output — so a theme
    /// edited in the editor gets an icon that matches it, and the twenty cannot
    /// drift from the presets they are made of.
    static func art(matching theme: Theme) -> AppIconArt {
        AppIconArt(ground: theme.windowBackground, cap: theme.highlight.accent, card: theme.ink.base)
            .opaque
    }

    // MARK: - Resolving

    /// What to actually wear, given the two switches, the themes and the
    /// appearance on screen.
    ///
    /// **The appearance is a parameter and not a read of the system**, because
    /// the two theme slots are chosen between by ``AppAppearance`` — an override
    /// the user may have set — and the caller is the one holding it.
    static func resolve(
        _ selection: AppIconSelection, themes: ThemeSettings, appearance: ThemeAppearance
    ) -> ResolvedAppIcon {
        guard selection.followsTheme else {
            let chosen = gradient(selection.gradientID) ?? fallback
            return ResolvedAppIcon(
                art: chosen.art, name: chosen.name, assetName: assetName(gradient: chosen.id)
            )
        }
        let theme = themes.theme(for: appearance)
        return ResolvedAppIcon(
            art: art(matching: theme), name: theme.name, assetName: assetName(theme: theme)
        )
    }

    // MARK: - The asset catalogue

    /// What one of the ten is called in the catalogue, or `nil` for the one the
    /// bundle already wears — `setAlternateIconName(nil)` is how iOS is asked
    /// for the built-in icon, and `4g` *is* the built-in icon.
    static func assetName(gradient id: String) -> String? {
        id == defaultID ? nil : "AppIcon-\(id)"
    }

    /// What a theme's icon is called in the catalogue.
    ///
    /// **Only the presets have one.** A theme the user built exists on this
    /// device and in this board file; nothing was compiled into the bundle for
    /// it, and iOS can only wear an icon that was. So a custom theme resolves
    /// to `nil` — the built-in icon — on the phone, and is drawn properly on
    /// the desk, where the icon is rendered at run time rather than looked up.
    static func assetName(theme: Theme) -> String? {
        theme.isPreset ? "AppIcon-theme-\(theme.id)" : nil
    }

    /// Every icon the asset catalogue holds, which is what
    /// `Tools/make-app-icon.swift` writes and what iOS can be asked for by name.
    ///
    /// **Thirty sets, not thirty-one.** The built-in `AppIcon` *is* `4g`, so the
    /// ten grounds contribute nine alternates and the twenty presets twenty
    /// more. A theme the user made contributes none — see
    /// ``assetName(theme:)``.
    ///
    /// Derived here rather than listed in the tool, so the icon compiled into
    /// the bundle and the icon drawn in the picker are the same drawing from
    /// the same numbers.
    static var catalogue: [AppIconAsset] {
        [AppIconAsset(assetName: "AppIcon", art: fallback.art, isDefault: true)]
            + all.compactMap { icon in
                assetName(gradient: icon.id).map {
                    AppIconAsset(assetName: $0, art: icon.art, isDefault: false)
                }
            }
            + ThemePresets.all.compactMap { theme in
                assetName(theme: theme).map {
                    AppIconAsset(assetName: $0, art: art(matching: theme), isDefault: false)
                }
            }
    }
}

/// One entry of `Resources/Assets.xcassets`: what it is called and what is
/// drawn in it. `isDefault` is the one the app ships wearing, which is the only
/// one that needs the macOS slots — the desk renders its icon at run time and
/// never looks an alternate up.
struct AppIconAsset: Hashable, Sendable {
    var assetName: String
    var art: AppIconArt
    var isDefault: Bool
}

// MARK: - The mark

/// The nine rectangles, and the box they are measured in.
///
/// Straight off `little-kanban-icon-4f.svg`: three columns at x = 20, 41 and
/// 62, each 18 wide, each led by a 5-tall header rule at y = 24 with 13-tall
/// cards under it. The stacks are **2, 3 and 1** rather than a tidy descent,
/// which is the whole point of the drawing — a board is not a staircase, it is
/// work piled unevenly across the middle of it.
///
/// Derived rather than transcribed: the columns and rows are an arithmetic
/// progression in the design's own script, and nine literals are nine chances
/// to typo one. Shared with `Tools/make-app-icon.swift`, which compiles this
/// file, so the icon in the picker and the icon in the bundle cannot disagree.
enum AppIconArtwork {
    /// The SVG's box. Every number below is in it, and the drawing scales.
    static let unit: Double = 100

    struct Bar: Hashable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
        var radius: Double
    }

    static let columnCount = 3
    static let cardCounts = [2, 3, 1]

    private static func columnX(_ column: Int) -> Double { 20 + Double(column) * 21 }

    static let headers: [Bar] = (0..<columnCount).map {
        Bar(x: columnX($0), y: 24, width: 18, height: 5, radius: 2.5)
    }

    static let cards: [Bar] = (0..<columnCount).flatMap { column in
        (0..<cardCounts[column]).map { row in
            Bar(x: columnX(column), y: 35 + Double(row) * 16, width: 18, height: 13, radius: 3.6)
        }
    }

    /// The three stacks as single capsules, for the sizes the cards cannot
    /// survive.
    ///
    /// A 16pt icon is about nine points of artwork: a 13-unit card is a pixel
    /// and a bit, the 3-unit gaps close up entirely, and the header rule lands
    /// under half a pixel. What is left of the full drawing at that size is a
    /// smudge in three bands — so the small sizes are drawn *as* three bands,
    /// which is the same silhouette with the detail taken out. The header rules
    /// go with the gaps, and the capsules take the card colour: at that size an
    /// accent rule five units tall is a haze over the top of the mark.
    static let stacks: [Bar] = (0..<columnCount).map { column in
        let top = 35.0
        let bottom = 35 + Double(cardCounts[column] - 1) * 16 + 13
        return Bar(x: columnX(column), y: top, width: 18, height: bottom - top, radius: 9)
    }

    /// Where the full drawing stops being legible, in pixels. The tool draws
    /// the simplified mark at or below it; nothing in the app is this small.
    static let simplifiedBelow = 33

    /// A superellipse, which is what an Apple icon's corners actually are — a
    /// rounded rect with circular corners reads visibly tighter beside them.
    /// `n = 5` is the exponent that matches the system's continuous curvature
    /// closely enough that the two sit together in the Dock.
    static func squircle(in rect: CGRect, exponent n: Double = 5) -> CGPath {
        let path = CGMutablePath()
        let a = rect.width / 2, b = rect.height / 2
        let cx = rect.midX, cy = rect.midY
        let steps = 720
        for step in 0...steps {
            let t = Double(step) / Double(steps) * 2 * .pi
            let c = cos(t), s = sin(t)
            let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
            let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
}
