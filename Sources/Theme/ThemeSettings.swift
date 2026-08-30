import Foundation

/// Which theme fills each slot, and the ones the user made.
///
/// **Two slots rather than one active theme.** Every one of the twenty is
/// absolutely light or absolutely dark — Ember has no light values behind it and
/// Porcelain has no dark ones — so a single choice would mean either abandoning
/// the system's light/dark switch or inventing values no designer wrote. The app
/// keeps one theme of each kind and the appearance setting picks between them,
/// which is the same arrangement macOS itself uses for wallpaper.
///
/// A theme is only ever assigned to the slot its own ``Theme/appearance`` names,
/// so it is not possible to put a dark theme in the light slot and find the app
/// unreadable at noon.
struct ThemeSettings: Hashable, Codable, Sendable {
    var lightID: Theme.ID
    var darkID: Theme.ID
    /// The themes the user made or imported, in the order they were made.
    /// Presets are not in here — they are in the source, and a copy of one that
    /// could go stale is worse than no copy.
    var custom: [Theme]

    static let seed = ThemeSettings(
        lightID: ThemePresets.porcelainID, darkID: ThemePresets.auroraID, custom: []
    )

    init(lightID: Theme.ID, darkID: Theme.ID, custom: [Theme] = []) {
        self.lightID = lightID
        self.darkID = darkID
        self.custom = custom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Lenient throughout: a slot naming a theme this machine has never heard
        // of resolves to the fallback rather than throwing, because the alternative
        // is a board file that will not open on the machine it was copied to.
        self.init(
            lightID: try container.decodeIfPresent(String.self, forKey: .lightID) ?? Self.seed.lightID,
            darkID: try container.decodeIfPresent(String.self, forKey: .darkID) ?? Self.seed.darkID,
            custom: try container.decodeIfPresent([Theme].self, forKey: .custom) ?? []
        )
    }

    /// Everything a picker can offer: the twenty in the document's own order,
    /// then the user's own.
    var all: [Theme] { ThemePresets.all + custom }

    func theme(id: Theme.ID) -> Theme? {
        ThemePresets.theme(id) ?? custom.first { $0.id == id }
    }

    func id(for appearance: ThemeAppearance) -> Theme.ID {
        appearance == .dark ? darkID : lightID
    }

    /// The theme in force for an appearance.
    ///
    /// Falls back rather than fails, twice over: a slot may name a theme that is
    /// not installed — a board file copied from a machine that had a custom
    /// theme this one does not — and a theme may have been edited into the wrong
    /// kind. Either way the app comes up in something readable.
    func theme(for appearance: ThemeAppearance) -> Theme {
        guard let found = theme(id: id(for: appearance)), found.appearance == appearance else {
            return ThemePresets.fallback(for: appearance)
        }
        return found
    }

    /// Puts a theme in the slot it belongs to, and nowhere else.
    mutating func select(_ theme: Theme) {
        switch theme.appearance {
        case .light: lightID = theme.id
        case .dark: darkID = theme.id
        }
    }

    /// Adds a theme, or replaces the one with the same id. Presets are refused:
    /// they are the reference points, and one that could be overwritten is not
    /// one. The editor offers a copy instead.
    @discardableResult
    mutating func save(_ theme: Theme) -> Bool {
        guard !theme.isPreset else { return false }
        if let index = custom.firstIndex(where: { $0.id == theme.id }) {
            custom[index] = theme
        } else {
            custom.append(theme)
        }
        // A slot pointing at this theme now shows the edit. A slot pointing at
        // it that no longer *can* — because the theme was flipped from dark to
        // light — is emptied back to the fallback by `theme(for:)`.
        return true
    }

    /// Removes a custom theme. Any slot wearing it falls back to the preset for
    /// that slot, which is what ``theme(for:)`` already does for a name it
    /// cannot resolve — so there is nothing to repoint here.
    @discardableResult
    mutating func delete(_ id: Theme.ID) -> Bool {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return false }
        custom.remove(at: index)
        return true
    }

    /// A name that is not already taken, for a duplicate or an import. "Ember",
    /// then "Ember 2", then "Ember 3" — the shape every document-based app uses,
    /// rather than a UUID nobody can read in a list.
    func unusedName(basedOn name: String) -> String {
        let taken = Set(all.map(\.name))
        guard taken.contains(name) else { return name }
        var suffix = 2
        while taken.contains("\(name) \(suffix)") { suffix += 1 }
        return "\(name) \(suffix)"
    }
}
