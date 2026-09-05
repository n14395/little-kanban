import SwiftUI

/// Light, dark, or whatever the system says.
///
/// This is the spec's `state.dark`, the one state field deliberately dropped
/// during the port because the design only ever followed the system appearance.
/// It comes back as a *preference*, which is why it is in `@AppStorage` and not
/// in `BoardSnapshot`: it belongs to this machine and this person, not to the
/// board — copy the board to another Mac and the override should not travel
/// with it. See **Settings** in the README for why the accent, which *is* in the
/// snapshot, was left there rather than moved half-way.
///
/// **In `Theme/` rather than beside the settings row that sets it**, because
/// the widgets read it too and they cannot have `SettingsView.swift`: a widget
/// draws in whichever theme slot the app would be wearing, so the override that
/// decides which slot has to travel into the extension. See ``WidgetDigest``.
enum AppAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    static let storageKey = "LittleKanbanAppearance"

    var label: String {
        switch self {
        case .system: String(localized: "System", comment: "Appearance setting: follow the system")
        case .light: String(localized: "Light", comment: "Appearance setting: always light")
        case .dark: String(localized: "Dark", comment: "Appearance setting: always dark")
        }
    }

    /// `nil` means "do not override", which is what `preferredColorScheme`
    /// wants and what `RootView` falls back on.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Which theme slot to draw in, given the appearance the surroundings are
    /// already in. The override wins where there is one; otherwise the
    /// surroundings decide — which on a widget is the system's own scheme, and
    /// is the whole of why a widget can follow light and dark without the app
    /// running.
    func slot(under scheme: ColorScheme) -> ThemeAppearance {
        (colorScheme ?? scheme).themeAppearance
    }
}
