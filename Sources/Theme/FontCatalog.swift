import CoreText
import Foundation
import Synchronization

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Registers the bundled faces once, and answers "what is this family called at
/// this weight?".
///
/// **Why the question is not obvious.** Fifteen of the seventeen families ship
/// as *variable* fonts — one file with a weight axis rather than five files —
/// and SwiftUI's `Font.custom` takes a PostScript name, not a family and a
/// weight. CoreText fabricates a name for each named instance of a variable
/// font, and it is not a name anybody would guess: Work Sans at 800 is
/// `WorkSansRoman-ExtraBold`, Space Grotesk at 700 is `SpaceGrotesk-Light_Bold`,
/// and DM Sans at 500 is `DMSans-9ptRegular_Medium`. So the family and the
/// weight are handed to the font matcher and the name it comes back with is
/// cached.
///
/// One file per family is also why the bundle is 5.6 MB rather than 20: five
/// static weights of seventeen families would be eighty-five files.
enum FontCatalog {
    /// Registration, run exactly once under the runtime's own lock, hung off the
    /// first read of anything here. A `static let` is the only initialiser in
    /// the language with that guarantee and no lock of its own.
    static let bundledFamilies: [String] = {
        register()
        // Asked of CoreText rather than listed by hand: the answer is then the
        // set of faces actually in the bundle, so a font that failed to copy in
        // shows up as a missing name in the picker rather than as a theme that
        // silently draws in the system face.
        var found = Set<String>()
        for url in bundledFontURLs {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                    as? [CTFontDescriptor] else { continue }
            for descriptor in descriptors {
                let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute)
                if let name = name as? String { found.insert(name) }
            }
        }
        return found.sorted()
    }()

    private static var bundledFontURLs: [URL] {
        Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
    }

    private static func register() {
        let urls = bundledFontURLs
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, false, nil)
    }

    /// Every family a theme may name: the bundled seventeen first, then whatever
    /// else is installed on this machine.
    ///
    /// The installed ones are offered because a theme is the user's own — if
    /// they have bought a face they should be able to set the app in it — and
    /// they come second because a theme built on one is a theme that will not
    /// travel: exported to another machine it falls back. See ``resolve(_:_:_:)``.
    ///
    /// A `let`, taken once per launch: the list sits inside the theme editor's
    /// font menus, whose builders run with every render of the form — dragging
    /// a colour slider was re-enumerating and re-sorting several hundred
    /// installed families per frame. A font installed mid-session appears on
    /// the next launch, which is when most apps notice one anyway.
    static let installedFamilies: [String] = {
        #if os(macOS)
        let system = NSFontManager.shared.availableFontFamilies
        #else
        let system = UIFont.familyNames
        #endif
        let bundled = Set(bundledFamilies)
        return system.filter { !bundled.contains($0) && !$0.hasPrefix(".") }.sorted()
    }()

    static func isBundled(_ family: String) -> Bool { bundledFamilies.contains(family) }

    /// The PostScript name for a family at a weight, or `nil` when this machine
    /// has no such family — which is the signal to fall back to the system face.
    ///
    /// Slant is asked for rather than synthesised here: only Instrument Serif
    /// and Newsreader ship an italic, and for every other family the matcher
    /// returns the upright, which the caller then slants. A real italic and a
    /// sheared roman are different things and the difference belongs at the top,
    /// where it can be seen — see ``hasItalic(_:)``.
    static func postScriptName(family: String, weight: Int, italic: Bool) -> String? {
        let key = Key(family: family, weight: weight, italic: italic)
        return cache.withLock { store in
            if let cached = store[key] { return cached }
            let resolved = match(key)
            store[key] = resolved
            return resolved
        }
    }

    /// Whether the family has a real slanted face, so a caller knows if the
    /// slant it is about to ask for will be drawn or sheared.
    static func hasItalic(_ family: String) -> Bool {
        guard let upright = postScriptName(family: family, weight: 400, italic: false),
              let slanted = postScriptName(family: family, weight: 400, italic: true)
        else { return false }
        return upright != slanted
    }

    // MARK: Matching

    private struct Key: Hashable {
        var family: String
        var weight: Int
        var italic: Bool
    }

    /// `nil` is a real answer and is cached as one, so a theme naming a font
    /// nobody has does not re-run the matcher on every frame it is drawn in.
    private static let cache = Mutex<[Key: String?]>([:])

    private static func match(_ key: Key) -> String? {
        _ = bundledFamilies   // Forces registration before the first match.
        var traits: [CFString: Any] = [kCTFontWeightTrait: coreTextWeight(key.weight)]
        if key.italic {
            traits[kCTFontSymbolicTrait] = CTFontSymbolicTraits.traitItalic.rawValue
        }
        let wanted = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: key.family,
            kCTFontTraitsAttribute: traits,
        ] as CFDictionary)
        guard let matched = CTFontDescriptorCreateMatchingFontDescriptor(wanted, nil) else {
            return nil
        }
        let font = CTFontCreateWithFontDescriptor(matched, 12, nil)
        // The matcher will happily hand back *something* for a family it has
        // never heard of, so the family it actually found is checked against the
        // family that was asked for.
        guard (CTFontCopyFamilyName(font) as String) == key.family else { return nil }
        return CTFontCopyPostScriptName(font) as String
    }

    /// CSS weights out to the −1…1 scale `kCTFontWeightTrait` is on. The five
    /// the app asks for are Apple's own constants for regular, medium,
    /// semibold, bold and heavy; the rest of the scale is interpolated so a
    /// hand-written theme asking for 300 gets light rather than regular.
    private static func coreTextWeight(_ weight: Int) -> Double {
        let stops: [(Int, Double)] = [
            (100, -0.8), (200, -0.6), (300, -0.4), (400, 0.0), (500, 0.23),
            (600, 0.3), (700, 0.4), (800, 0.56), (900, 0.62),
        ]
        if let exact = stops.first(where: { $0.0 == weight })?.1 { return exact }
        guard let upper = stops.first(where: { $0.0 > weight }) else { return stops.last!.1 }
        guard let lower = stops.last(where: { $0.0 < weight }) else { return stops.first!.1 }
        let t = Double(weight - lower.0) / Double(upper.0 - lower.0)
        return lower.1 + (upper.1 - lower.1) * t
    }
}
