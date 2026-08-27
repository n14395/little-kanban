import SwiftUI

/// Which of the two slots a theme can sit in.
///
/// A theme is not a colour scheme that happens to be dark; it is a set of
/// literal colours with no second set behind them. Ember has no light values
/// and Porcelain has no dark ones, which is why the app keeps one of each and
/// the system's appearance chooses between them rather than each theme carrying
/// both. See ``BoardStore/theme(for:)``.
enum ThemeAppearance: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }

    var label: String {
        switch self {
        case .light: String(localized: "Light", comment: "Which slot a theme fills")
        case .dark: String(localized: "Dark", comment: "Which slot a theme fills")
        }
    }
}

/// A face, at a weight, upright or slanted.
///
/// `weight` means two different things depending on which of a theme's two
/// fonts it is on, and both are the useful meaning:
///
/// - On the **display font** it is the weight titles are drawn at, flat. A
///   display face is used at one weight in one place, and the difference
///   between Spectral at 400 and Spectral at 600 is most of what picking
///   Spectral was for.
/// - On the **ui font** it is the *baseline*: the app asks for regular through
///   extra-bold at some two hundred call sites, and those requests are shifted
///   by however far this sits from 400. A face that reads thin can be lifted
///   everywhere by one number, and 400 leaves every call site exactly where it
///   was written.
struct ThemeFont: Hashable, Codable, Sendable {
    var family: String
    var weight: Int
    var isItalic: Bool

    init(_ family: String, weight: Int = 400, italic: Bool = false) {
        self.family = family
        self.weight = min(max(weight, 100), 900)
        self.isItalic = italic
    }

    enum CodingKeys: String, CodingKey { case family, weight, isItalic = "italic" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(String.self, forKey: .family),
            weight: try container.decodeIfPresent(Int.self, forKey: .weight) ?? 400,
            italic: try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        )
    }
}

/// The window's ground, as the design writes it: an angle and a run of stops.
///
/// Every theme but one carries a gradient rather than a flat colour, and a flat
/// colour is a gradient with one stop — so there is no second case to hold and
/// no branch at the point of use.
struct ThemeGradient: Hashable, Codable, Sendable {
    struct Stop: Hashable, Codable, Sendable {
        var color: ThemeColor
        /// 0 at the start of the gradient line, 1 at the end.
        var location: Double
    }

    /// CSS degrees: 0 points at the top of the window and the angle runs
    /// clockwise, which is the spelling the twenty themes are written in.
    var angle: Double
    var stops: [Stop]

    init(angle: Double, stops: [Stop]) {
        self.angle = angle
        self.stops = stops.isEmpty ? [Stop(color: ThemeColor(0x000000), location: 0)] : stops
    }

    /// `linear-gradient(160deg, #2A1E15 0%, #17110D 55%, #0D0A08 100%)`,
    /// transcribed.
    init(_ angle: Double, _ stops: (ThemeColor, Double)...) {
        self.init(angle: angle, stops: stops.map { Stop(color: $0.0, location: $0.1) })
    }

    static func flat(_ color: ThemeColor) -> ThemeGradient {
        ThemeGradient(angle: 180, stops: [Stop(color: color, location: 0)])
    }

    /// Where the gradient line enters and leaves the frame.
    ///
    /// CSS measures its gradient line so that the first and last stops sit on
    /// the corners of the box; `UnitPoint` is a fraction of the frame and has no
    /// way to say "as long as the diagonal", so the length is scaled for a
    /// **square** frame and points outside 0…1 are allowed to fall where they
    /// fall. Exact on the axes, and within a few percent on the diagonals of
    /// anything close to square — which is what a window is, and the error on a
    /// long thin sidebar is a stop or two of a slow gradient.
    var startPoint: UnitPoint { points.start }
    var endPoint: UnitPoint { points.end }

    /// Both ends from one trigonometric pass. `startPoint` and `endPoint` each
    /// computed the vector on their own, so a caller reading the pair — every
    /// `LinearGradient` built from a theme — paid the sines twice.
    var points: (start: UnitPoint, end: UnitPoint) {
        let (dx, dy) = vector
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    private var vector: (dx: Double, dy: Double) {
        let radians = angle * .pi / 180
        let x = sin(radians), y = -cos(radians)
        let reach = (abs(x) + abs(y)) / 2
        return (x * reach, y * reach)
    }

    var gradient: Gradient {
        // One stop is a fill, and `Gradient` needs two ends to interpolate
        // between; a run of stops that all sit at 0 is a fill as well.
        guard stops.count > 1 else {
            let only = stops[0].color.color
            return Gradient(stops: [.init(color: only, location: 0), .init(color: only, location: 1)])
        }
        return Gradient(stops: stops.map { .init(color: $0.color.color, location: $0.location) })
    }

    /// The one colour to use where a gradient cannot be drawn: a menu-bar
    /// popover with the window nowhere near it, a sheet's own backing, the tile
    /// in the preset picker at thumbnail size. The stop nearest the middle of
    /// the run, because that is the colour most of the window is wearing.
    var representative: ThemeColor {
        stops.min { abs($0.location - 0.5) < abs($1.location - 0.5) }?.color
            ?? ThemeColor(0x000000)
    }
}

/// A task card: what it is filled with, what its hairline is, and how round it
/// is. The one size the design varies from theme to theme.
struct ThemeCard: Hashable, Codable, Sendable {
    var fill: ThemeColor
    var border: ThemeColor
    var radius: Double
}

/// Text, and the two tints of it the design draws everything quieter in.
///
/// `muted` and `faint` are the design's own numbers and are kept as written,
/// but text does not get them raw: ``Palette/inkText(_:)`` holds a floor under
/// anything that has to be *read*, for the contrast reason documented there.
/// A rule, a dot or a meter track takes the number exactly.
struct ThemeInk: Hashable, Codable, Sendable {
    var base: ThemeColor
    var muted: Double
    var faint: Double
}

/// The accent, the tint of it a selected row sits on, and what can be read on
/// top of it.
struct ThemeHighlight: Hashable, Codable, Sendable {
    var accent: ThemeColor
    var soft: ThemeColor
    var onAccent: ThemeColor
}

/// The two hues that mean something rather than decorate: work that is finished,
/// and work that wants attention but is not late.
///
/// There is no third for *late*: the overdue red is the due chip's own, so it is
/// said once — see ``ThemeDueChips/hot`` and ``Palette/priorityColor(_:)``.
struct ThemeStatus: Hashable, Codable, Sendable {
    var done: ThemeColor
    var medium: ThemeColor
}

/// How a label's colour becomes a chip.
///
/// **The theme owns the recipe, not the colours.** The design document fixes
/// four chips per theme — `HEALTH` is one teal in every dark theme and another
/// in every light one — but a label in this app is not one of four fixed things:
/// you make labels and give each one a colour from the picker. So what the
/// theme carries is the three numbers that turn any colour into a ground and a
/// text, and the document's four pairs come out as examples of it.
///
/// Dark themes lift the colour before tinting it, because a low-opacity wash of
/// `#1F6F63` over a near-black card is very nearly the card. See
/// ``LabelTone/pair(from:rule:)``.
struct ThemeChipRule: Hashable, Codable, Sendable {
    /// How far towards white the ground's colour is taken before it is tinted.
    var backgroundLift: Double
    /// What the lifted colour is drawn at, over the card.
    var backgroundOpacity: Double
    /// How far the text is taken from the colour — positive towards white.
    var foregroundShade: Double

    static let light = ThemeChipRule(backgroundLift: 0, backgroundOpacity: 0.13, foregroundShade: -0.2)
    static let dark = ThemeChipRule(backgroundLift: 0.45, backgroundOpacity: 0.19, foregroundShade: 0.78)
}

/// One chip's two colours, stated rather than derived — the due chips are the
/// app's alarm and its warning, and neither is a tint of anything the user
/// chose.
struct ThemeChip: Hashable, Codable, Sendable {
    var background: ThemeColor
    var foreground: ThemeColor
}

/// The date chips on a card.
///
/// Two are here and two are not, exactly as the document has it: anything
/// further out than `warm` "uses wash / muted", and a finished task's chip takes
/// ``ThemeStatus/done`` through the label chip rule. Four literals where two
/// would do is four things to keep in agreement.
struct ThemeDueChips: Hashable, Codable, Sendable {
    /// Overdue, and today.
    var hot: ThemeChip
    /// Due soon — the next couple of days.
    var warm: ThemeChip
}

/// Everything the app's appearance is made of, in one value.
///
/// The parameters are the design document's, in its order and under its names,
/// because that document is the thing this is answerable to and a reader with
/// both open should not have to translate. What the app adds is the *shape* of
/// the two that could not be transcribed literally — see ``ThemeChipRule`` for
/// the label chips, and ``ThemeFont`` for what a weight means on each of the two
/// faces.
///
/// A theme is a value: `Palette` holds one, every colour in the app is a
/// question asked of it, and switching themes is an assignment. There is no
/// registry to keep in step and nothing to invalidate.
struct Theme: Identifiable, Hashable, Codable, Sendable {
    /// The document's own reference for a preset (`1a`, `2j`), or a UUID string
    /// for one the user made. Stable across renames, which is what the two slots
    /// store and what an import has to avoid colliding with.
    var id: String
    var name: String
    /// Which slot this theme can fill. Not derived from the ink: a theme is
    /// entitled to be a dark theme with pale cards if that is what it is, and
    /// the slot decides which system appearance shows it.
    var appearance: ThemeAppearance

    var displayFont: ThemeFont
    var uiFont: ThemeFont
    var windowBackground: ThemeGradient
    var panelOverlay: ThemeColor
    var card: ThemeCard
    var ink: ThemeInk
    var wash: ThemeColor
    var highlight: ThemeHighlight
    var status: ThemeStatus
    var labelChips: ThemeChipRule
    var dueChips: ThemeDueChips

    /// True for one of the twenty the app ships with. A preset cannot be edited
    /// in place or deleted — editing one offers to make a copy — because a
    /// reference point that can be overwritten is not one.
    var isPreset: Bool { ThemePresets.isPresetID(id) }

    /// "Instrument Serif · Manrope", or the family once when both are the same
    /// face. The document's own subtitle for a theme, worked out from the fonts
    /// rather than stored beside them where the two could disagree.
    var fontSummary: String {
        displayFont.family == uiFont.family
            ? displayFont.family
            : "\(displayFont.family) · \(uiFont.family)"
    }

    /// A copy that belongs to the user: new identity, and a name that says it is
    /// theirs. What the editor makes when you change a preset.
    func duplicated(named name: String) -> Theme {
        var copy = self
        copy.id = UUID().uuidString
        copy.name = name
        return copy
    }
}
