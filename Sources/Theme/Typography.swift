import CoreText
import SwiftUI

/// Registers the bundled Manrope / Instrument Serif faces at launch.
///
/// Registering at runtime (rather than via `UIAppFonts` / `ATSApplicationFontsPath`)
/// keeps one code path for both platforms and lets ``SimpleKanbanFont`` fall back to the
/// system faces if the `Resources/Fonts` folder is ever removed.
enum FontRegistry {
    private(set) nonisolated(unsafe) static var hasCustomFonts = false

    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        hasCustomFonts = isRegistered(SimpleKanbanFont.Weight.bold.postScriptName)
            && isRegistered(SimpleKanbanFont.serifPostScriptName)
    }

    private static func isRegistered(_ postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }
}

/// The design's two families: Manrope for UI text, Instrument Serif for display
/// headings. Sizes are the spec's pixel values used directly as points, but they
/// stay Dynamic Type responsive by being declared relative to a text style.
enum SimpleKanbanFont {
    enum Weight: Int, Sendable {
        case regular = 400
        case medium = 500
        case semibold = 600
        case bold = 700
        case extraBold = 800

        var postScriptName: String {
            switch self {
            case .regular: "Manrope-Regular"
            case .medium: "Manrope-Medium"
            case .semibold: "Manrope-SemiBold"
            case .bold: "Manrope-Bold"
            case .extraBold: "Manrope-ExtraBold"
            }
        }

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

    static let serifPostScriptName = "InstrumentSerif-Regular"

    /// Manrope at `size`, scaling with Dynamic Type relative to `textStyle`.
    static func ui(_ size: CGFloat, _ weight: Weight = .regular, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        guard FontRegistry.hasCustomFonts else {
            return .system(size: size, weight: weight.systemEquivalent)
        }
        return .custom(weight.postScriptName, size: size, relativeTo: textStyle)
    }

    /// Instrument Serif at `size` — the display face for board and task titles.
    static func serif(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        guard FontRegistry.hasCustomFonts else {
            return .system(size: size, design: .serif)
        }
        return .custom(serifPostScriptName, size: size, relativeTo: textStyle)
    }
}

extension View {
    /// Applies the design's uppercase micro-label treatment:
    /// `11px / 800 / 0.1em tracking / uppercase`.
    func sectionLabelStyle(size: CGFloat = 11, tracking: CGFloat = 0.1, opacity: Double = 0.38) -> some View {
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
            .font(SimpleKanbanFont.ui(size, .extraBold, relativeTo: .caption2))
            .tracking(size * tracking)
            .textCase(.uppercase)
            .foregroundStyle(palette.ink(opacity))
    }
}
