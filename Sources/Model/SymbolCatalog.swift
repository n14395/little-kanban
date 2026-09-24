// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Every SF Symbol a board's or a saved view's icon can be picked from, read
/// off a generated list.
///
/// **There is no API that enumerates SF Symbols**, so the names have to be
/// shipped. `Resources/SFSymbols.txt` is written by `Tools/make-symbol-catalogue`
/// out of the system's own CoreGlyphs bundle — filtered to what the deployment
/// target can actually draw, with Apple's restricted marks and the localized
/// numeral variants left out. See the tool for why each of those goes.
///
/// It is a resource rather than a Swift literal because it is 7,000 lines of
/// data and none of it is code: nothing here is referred to by name from
/// anywhere in the app, the file is regenerated wholesale after an OS upgrade,
/// and a 300KB string literal is 300KB the compiler has to lex on every build.
///
/// **Nothing is loaded until a picker opens.** `entries` is a `static let`, so
/// the read and the parse happen once, on the first browse, and never on a
/// launch that does not open one. The rest of the app — the sidebar, the
/// widgets, the destination pill — draws a board's mark without touching this:
/// they have a name and hand it to ``SymbolMark``.
enum SymbolCatalog {
    /// One symbol: what to draw, what it is of, and what a person might call it.
    struct Entry: Identifiable, Hashable, Sendable {
        var name: String
        var categories: Set<Category>
        /// The system's own search terms for the symbol, space separated and
        /// already lowercased — "date" for `1.calendar`, "running sports" for
        /// `1.lane`. Most symbols have none, and are found by their name.
        var terms: String

        var id: String { name }
    }

    /// What a symbol is *of*. CoreGlyphs' own categories, minus the four that
    /// describe how a glyph can be drawn rather than what it shows — see the
    /// generator.
    ///
    /// Raw values are the system's keys, because the generated file carries
    /// them; the names are ours, because the system's are not localized and are
    /// not words ("objectsandtools").
    enum Category: String, CaseIterable, Identifiable, Sendable {
        case communication, weather, maps, objectsandtools, devices
        case cameraandphotos, gaming, connectivity, transportation, automotive
        case accessibility, privacyandsecurity, human, home, fitness
        case nature, editing, textformatting, media, keyboard
        case commerce, time, health, shapes, arrows
        case indices, math

        var id: String { rawValue }

        /// The row's name in the picker's category menu.
        var label: String {
            switch self {
            case .communication: String(localized: "Communication", comment: "A group of icons in the icon picker")
            case .weather: String(localized: "Weather", comment: "A group of icons in the icon picker")
            case .maps: String(localized: "Maps", comment: "A group of icons in the icon picker")
            case .objectsandtools: String(localized: "Objects and Tools", comment: "A group of icons in the icon picker")
            case .devices: String(localized: "Devices", comment: "A group of icons in the icon picker")
            case .cameraandphotos: String(localized: "Camera and Photos", comment: "A group of icons in the icon picker")
            case .gaming: String(localized: "Gaming", comment: "A group of icons in the icon picker")
            case .connectivity: String(localized: "Connectivity", comment: "A group of icons in the icon picker")
            case .transportation: String(localized: "Transport", comment: "A group of icons in the icon picker")
            case .automotive: String(localized: "Automotive", comment: "A group of icons in the icon picker")
            case .accessibility: String(localized: "Accessibility", comment: "A group of icons in the icon picker")
            case .privacyandsecurity: String(localized: "Privacy and Security", comment: "A group of icons in the icon picker")
            case .human: String(localized: "People", comment: "A group of icons in the icon picker")
            case .home: String(localized: "Home", comment: "A group of icons in the icon picker")
            case .fitness: String(localized: "Fitness", comment: "A group of icons in the icon picker")
            case .nature: String(localized: "Nature", comment: "A group of icons in the icon picker")
            case .editing: String(localized: "Editing", comment: "A group of icons in the icon picker")
            case .textformatting: String(localized: "Text Formatting", comment: "A group of icons in the icon picker")
            case .media: String(localized: "Media", comment: "A group of icons in the icon picker")
            case .keyboard: String(localized: "Keyboard", comment: "A group of icons in the icon picker")
            case .commerce: String(localized: "Commerce", comment: "A group of icons in the icon picker")
            case .time: String(localized: "Time", comment: "A group of icons in the icon picker")
            case .health: String(localized: "Health", comment: "A group of icons in the icon picker")
            case .shapes: String(localized: "Shapes", comment: "A group of icons in the icon picker")
            case .arrows: String(localized: "Arrows", comment: "A group of icons in the icon picker")
            case .indices: String(localized: "Letters and Numbers", comment: "A group of icons in the icon picker")
            case .math: String(localized: "Maths", comment: "A group of icons in the icon picker")
            }
        }

        /// The glyph beside the name in the menu — the system's own mark for
        /// the category, so the row is recognisable to anyone who has met the
        /// SF Symbols app.
        var symbol: String {
            switch self {
            case .communication: "message"
            case .weather: "cloud.sun"
            case .maps: "map"
            case .objectsandtools: "folder"
            case .devices: "desktopcomputer"
            case .cameraandphotos: "camera"
            case .gaming: "gamecontroller"
            case .connectivity: "antenna.radiowaves.left.and.right"
            case .transportation: "car.fill"
            case .automotive: "steeringwheel"
            case .accessibility: "accessibility"
            case .privacyandsecurity: "lock"
            case .human: "person.crop.circle"
            case .home: "house"
            case .fitness: "figure.run"
            case .nature: "leaf"
            case .editing: "slider.horizontal.3"
            case .textformatting: "textformat"
            case .media: "playpause"
            case .keyboard: "command"
            case .commerce: "cart"
            case .time: "timer"
            case .health: "heart"
            case .shapes: "square.on.circle"
            case .arrows: "arrow.forward"
            case .indices: "a.circle"
            case .math: "plusminus"
            }
        }
    }

    /// The whole catalogue, in the order the file carries — which is
    /// alphabetical, so a browse is predictable and a symbol's variants
    /// (`flag`, `flag.fill`, `flag.slash`) sit together.
    static let entries: [Entry] = parse(contents() ?? "")

    /// The symbols in one category, or all of them.
    static func entries(in category: Category?) -> [Entry] {
        guard let category else { return entries }
        return entries.filter { $0.categories.contains(category) }
    }

    /// What a query finds, within a category or across the lot.
    ///
    /// Matched against the name *and* the system's search terms, because the
    /// name is often not the word anybody would think of: "fire" finds `flame`,
    /// "date" finds `1.calendar`, "search" finds `magnifyingglass`. Dots in a
    /// name are
    /// treated as spaces, so "square split" finds `square.split.2x1` — a symbol
    /// whose name nobody types in the order it is spelled.
    static func search(_ query: String, in category: Category? = nil) -> [Entry] {
        let words = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "." })
            .map(String.init)
        let pool = entries(in: category)
        guard !words.isEmpty else { return pool }
        return pool.filter { entry in
            let haystack = entry.name.replacingOccurrences(of: ".", with: " ") + " " + entry.terms
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    // MARK: Reading the file

    /// The generated list's name in the bundle. `Bundle.main` rather than a
    /// module bundle: this is an app target, and inside the test host it is the
    /// app that carries the resource.
    static let resourceName = "SFSymbols"

    private static func contents() -> String? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return text
    }

    /// `name<TAB>categories<TAB>terms`, one per line, `#` for a comment.
    ///
    /// Lenient about the two trailing fields and strict about the first: a line
    /// with no name is not a symbol, and a symbol with no category is simply one
    /// the system files under nothing — it is still browsable under All and
    /// still findable by name.
    static func parse(_ text: String) -> [Entry] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard let name = fields.first, !name.isEmpty else { return nil }
            let categories = fields.count > 1
                ? Set(fields[1].split(separator: ",").compactMap { Category(rawValue: String($0)) })
                : []
            return Entry(
                name: String(name),
                categories: categories,
                terms: fields.count > 2 ? String(fields[2]) : ""
            )
        }
    }
}
