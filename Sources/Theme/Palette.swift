import SwiftUI

/// Every colour, face and corner in the app, asked of the theme in force.
///
/// **The palette used to be the theme.** Two columns of literals — one under
/// `[data-theme="light"]`, one under `[data-theme="dark"]` — and a `colorScheme`
/// to pick between them. It holds a ``Theme`` now, and every one of these
/// properties is a question put to it, so switching theme is an assignment and
/// nothing has to be invalidated, re-registered or told.
///
/// What is *not* in the theme is still here, and deliberately: the contrast
/// floor under text (``inkText(_:)``), the scrim behind a panel, and the rule
/// for which of black or white can be read on an arbitrary colour. Those are not
/// taste, and a theme that could set them could produce an app that cannot be
/// read.
struct Palette: Equatable, Sendable {
    /// Read-only from outside: everything below that ends in `…Resolved` is a
    /// pure function of the theme, worked out once here, and a theme assigned
    /// past the initialiser would leave the app drawing another theme's fonts.
    private(set) var theme: Theme

    // What the hot paths ask for on every body evaluation, resolved once per
    // palette rather than once per ask. A palette is built when the theme, the
    // appearance or the store's theme list changes — a handful of times a
    // session — and read hundreds of times per frame.
    private let uiFace: ResolvedThemeFace
    private let displayFace: ResolvedThemeFace
    private let windowGradient: Gradient
    private let windowPoints: (start: UnitPoint, end: UnitPoint)
    private let groundResolved: Color
    private let panelSolidResolved: Color
    private let cardSolidResolved: Color

    init(theme: Theme) {
        self.theme = theme
        self.uiFace = ResolvedThemeFace(theme.uiFont)
        self.displayFace = ResolvedThemeFace(theme.displayFont)
        let background = theme.windowBackground
        self.windowGradient = background.gradient
        self.windowPoints = background.points
        let representative = background.representative
        self.groundResolved = representative.color
        self.panelSolidResolved = theme.panelOverlay.composited(over: representative).color
        self.cardSolidResolved = theme.card.fill.composited(over: representative).color
    }

    /// The resolutions are functions of the theme, so the theme is the whole
    /// of the identity — and the environment's own equality check on a write
    /// stays one struct comparison rather than a walk of the font tables.
    static func == (lhs: Palette, rhs: Palette) -> Bool { lhs.theme == rhs.theme }

    /// Which way round the app is, for the handful of things that ask the
    /// question rather than take a colour: the system's own chrome, the
    /// keyboard, and the two places a scrim has to be heavier in the dark.
    var colorScheme: ColorScheme { theme.appearance.colorScheme }

    var isDark: Bool { theme.appearance == .dark }

    // MARK: Type

    /// The UI face, `step` from its baseline. See ``ThemeFont/weight``.
    /// Through the resolved face — no catalogue lookup on this path.
    func ui(
        _ size: CGFloat, _ step: SimpleKanbanFont.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        uiFace.font(size, step, relativeTo: textStyle)
    }

    /// The display face — board titles and the task title in the inspector, and
    /// nothing else. The design is emphatic about the "and nothing else": a
    /// display face used for a fourth thing stops being the thing that marks the
    /// other three.
    func display(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        displayFace.font(size, relativeTo: textStyle)
    }

    // MARK: Ink & shadow

    private var inkHex: UInt32 { theme.ink.base.hex }

    var ink: Color { theme.ink.base.color }
    func ink(_ opacity: Double) -> Color { Color(hex: inkHex, opacity: opacity) }

    /// Ink at the theme's own two quieter weights, for the things that are not
    /// text: a hairline, a dot, an empty meter track. Text goes through
    /// ``inkText(_:)`` and gets a floor.
    var inkMuted: Color { ink(theme.ink.muted) }
    var inkFaint: Color { ink(theme.ink.faint) }

    /// Not the theme's ink. A shadow is the *absence* of what is behind it, and
    /// in a dark theme that is black rather than the near-white the text is
    /// drawn in — see ``scrim(_:)`` for what happened the last time these two
    /// were the same colour.
    func shadow(_ opacity: Double) -> Color {
        Color(hex: isDark ? 0x000000 : inkHex, opacity: opacity)
    }

    // MARK: Surfaces

    /// The window's ground. Every theme but the flattest carries a gradient, so
    /// this is a `LinearGradient` rather than a `Color` — it is a `ShapeStyle`
    /// either way and goes into `.background(_:)` unchanged.
    var windowFill: LinearGradient {
        LinearGradient(
            gradient: windowGradient,
            startPoint: windowPoints.start,
            endPoint: windowPoints.end
        )
    }

    /// The one flat colour that stands for the window, for the places a gradient
    /// cannot go: a colour being interpolated towards transparent, a menu-bar
    /// popover with no window behind it, a thumbnail. See
    /// ``ThemeGradient/representative``.
    var ground: Color { groundResolved }

    /// The wash a sidebar or an inspector lays over the window.
    ///
    /// **Translucent, and that is the point.** The design draws one ground for
    /// the whole window and darkens or lightens the panels over it, so the
    /// gradient runs *through* the sidebar rather than stopping at its edge. A
    /// panel that painted an opaque colour would cut the window in three.
    var panelOverlay: Color { theme.panelOverlay.color }

    /// The same wash with the window's own colour already behind it, for a panel
    /// that has no window behind it to be washed over: the menu-bar popover.
    var panelSolid: Color { panelSolidResolved }

    /// The window's ground with the panel wash already on it, as a view, for a
    /// panel that covers rather than sits beside: the iPhone's navigation
    /// drawer. Layered rather than flattened so the gradient still runs through
    /// it — a drawer painted one flat colour is a slab across a window that is
    /// not flat anywhere else.
    var panelBackdrop: some View { windowFill.overlay(panelOverlay) }

    var card: Color { theme.card.fill.color }
    /// A card standing on its own — a popover, a sheet's backing — where the
    /// window is not behind it to show through.
    var cardSolid: Color { cardSolidResolved }
    var cardBorder: Color { theme.card.border.color }
    var cardRadius: CGFloat { theme.card.radius }

    /// The design's `wash`: the search field, count pills, the segmented
    /// control's track, an empty meter.
    var wash: Color { theme.wash.color }

    // MARK: Accent

    var accent: Color { theme.highlight.accent.color }
    var accentSoft: Color { theme.highlight.soft.color }

    /// The accent as a number, for the places that need the *value* and not the
    /// colour: deriving a label's chip from it, ringing it in a picker, deciding
    /// what can be read on it.
    var accentValue: UInt32 { theme.highlight.accent.hex }

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

extension ColorScheme {
    /// Which of a board's two theme slots this scheme asks for. Anything the
    /// framework adds beyond light and dark reads as light, which is the safe
    /// half: a light theme on a dark system is legible, and the reverse is a
    /// window nobody can see.
    var themeAppearance: ThemeAppearance { self == .dark ? .dark : .light }
}

extension EnvironmentValues {
    @Entry var palette = Palette(theme: ThemePresets.fallback(for: .light))
}
