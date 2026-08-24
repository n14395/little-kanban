import SwiftUI

/// The two faces a theme is set in, and the five weights the app asks of them.
///
/// Sizes are the design's pixel values used directly as points, and stay Dynamic
/// Type responsive by being declared relative to a text style.
///
/// **Nothing here knows which theme is in force.** The faces arrive as
/// arguments, from ``Palette/ui(_:_:relativeTo:)`` and
/// ``Palette/display(_:relativeTo:)``, because the palette is the one value that
/// travels down the environment and a font that came from a global would go on
/// drawing in the old face for a frame after the theme changed.
enum SimpleKanbanFont {
    /// The weights the app asks for, as CSS numbers so that they add to a
    /// theme's baseline without a table in between. See ``ThemeFont/weight``.
    enum Weight: Int, Sendable {
        case regular = 400
        case medium = 500
        case semibold = 600
        case bold = 700
        case extraBold = 800

        var systemEquivalent: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .extraBold: .heavy
            }
        }
    }

    /// `face` at `size`, `step` heavier or lighter than the face's own baseline.
    ///
    /// The step is *added* to the face's weight rather than replacing it: a
    /// theme that sets its UI font at 500 because the face reads thin gets every
    /// one of the app's two hundred call sites lifted by the same amount, and a
    /// theme that leaves it at 400 — which is all twenty of the presets — gets
    /// exactly the weights the call sites were written with.
    static func font(
        _ face: ThemeFont, size: CGFloat, step: Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        let weight = min(max(face.weight + step.rawValue - Weight.regular.rawValue, 100), 900)
        guard let name = FontCatalog.postScriptName(
            family: face.family, weight: weight, italic: face.isItalic
        ) else {
            return fallback(face, size: size, weight: weight)
        }
        let font = Font.custom(name, size: size, relativeTo: textStyle)
        // A family with no slanted face gets a sheared upright rather than
        // nothing. Worse than a drawn italic and better than a theme that asks
        // for italic Sora and silently gets roman.
        return face.isItalic && !FontCatalog.hasItalic(face.family) ? font.italic() : font
    }

    /// What a face nobody has resolves to. The design is guessed from the
    /// family — see ``FontCatalog/isSerif(_:)`` — because a theme built on a
    /// font the user bought should still read as the *kind* of face it was set
    /// in when it is opened on a machine that does not have it.
    private static func fallback(_ face: ThemeFont, size: CGFloat, weight: Int) -> Font {
        let system = Font.system(
            size: size,
            weight: Weight(rawValue: weight)?.systemEquivalent ?? .regular,
            design: FontCatalog.isSerif(face.family) ? .serif : .default
        )
        return face.isItalic ? system.italic() : system
    }
}

extension FontCatalog {
    /// Whether a family is a serif, for the one case where it matters: choosing
    /// a system face to stand in for one that is not installed.
    ///
    /// The seventeen the app ships with are named, because they are known. Every
    /// other family is guessed from its name, which is right often enough for a
    /// fallback and wrong in no way anybody can be hurt by.
    static func isSerif(_ family: String) -> Bool {
        if bundledSerifs.contains(family) { return true }
        if bundledFamilies.contains(family) { return false }
        let name = family.lowercased()
        return ["serif", "times", "georgia", "caslon", "garamond", "baskerville", "roman"]
            .contains { name.contains($0) }
    }

    private static let bundledSerifs: Set<String> = [
        "Instrument Serif", "Newsreader", "IBM Plex Serif", "Spectral",
        "Crimson Pro", "Libre Caslon Text",
    ]
}

extension View {
    /// Applies the design's uppercase micro-label treatment:
    /// `11px / 800 / 0.1em tracking / uppercase`.
    ///
    /// The default opacity is the readable floor rather than the design's 0.38.
    /// 0.38 of ink under 11pt uppercase type is the single most common finding
    /// the accessibility audit made — it resolves to about 2.4:1 — and every one
    /// of the twenty-six call sites had to pass the floor by hand to get out of
    /// it. A default that has to be overridden everywhere is not a default; this
    /// is the same number said once.
    func sectionLabelStyle(
        size: CGFloat = 11, tracking: CGFloat = 0.1, opacity: Double = Palette.readableInk
    ) -> some View {
        modifier(SectionLabelStyle(size: size, tracking: tracking, opacity: opacity))
    }
}

private struct SectionLabelStyle: ViewModifier {
    @Environment(\.palette) private var palette
    let size: CGFloat
    let tracking: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .font(palette.ui(size, .extraBold, relativeTo: .caption2))
            .tracking(size * tracking)
            .textCase(.uppercase)
            // `inkText` rather than `ink`: the floor belongs to the tone, so a
            // call site that passes the design's own lighter number still gets
            // text that can be read.
            .foregroundStyle(palette.inkText(opacity))
    }
}
