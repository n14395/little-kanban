// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Puts the chosen icon on the app, which the two platforms mean differently.
///
/// **macOS draws it; iOS names it.** The desk can be handed a picture at run
/// time — `NSApplication.applicationIconImage` is the Dock icon of the running
/// app — so it renders ``AppIconMark`` and hands that over, and every icon
/// works, including one matching a theme the user built this morning. iOS has
/// no such call: `setAlternateIconName(_:)` takes the *name* of an icon already
/// compiled into the bundle, so the ten grounds and the twenty preset themes
/// are baked by `Tools/make-app-icon.swift` and anything else falls back to the
/// icon the app shipped with. See ``AppIcon/assetName(theme:)``.
///
/// **What macOS cannot do is change the icon in Finder**, or in a Dock the app
/// is not running in: that is the bundle's own `.icns`, and this app is
/// sandboxed and does not rewrite its own bundle. The Dock icon while the app
/// is running is the whole of the promise, which is the same promise every
/// other sandboxed Mac app with an icon picker makes.
@MainActor
enum AppIconInstaller {
    /// What is on the app now, so an unchanged choice costs nothing.
    ///
    /// Not decoration on iOS: `setAlternateIconName(_:)` puts a system alert on
    /// screen every time it changes the icon, so calling it with the name it is
    /// already wearing would raise one for nothing. `UIApplication` is asked as
    /// well — this is only what *this* run of the app has set.
    private static var applied: ResolvedAppIcon?

    static func apply(_ icon: ResolvedAppIcon) {
        guard applied != icon else { return }
        applied = icon
        #if os(macOS)
        NSApplication.shared.applicationIconImage = render(icon.art)
        #else
        let application = UIApplication.shared
        guard application.supportsAlternateIcons,
              application.alternateIconName != icon.assetName else { return }
        application.setAlternateIconName(icon.assetName) { error in
            // Nothing to show the user and nothing to retry: a name that is not
            // in the bundle is a build that did not compile the alternates, and
            // the icon simply stays as it was.
            if let error { print("app icon: \(error.localizedDescription)") }
        }
        #endif
    }

    #if os(macOS)
    /// The Dock's own grid: the artwork occupies 824 of a 1024 canvas and the
    /// space around it is where the shadow goes. The same numbers
    /// `Tools/make-app-icon.swift` writes the `.icns` with, so the icon does not
    /// jump the first time the app is launched.
    private static func render(_ art: AppIconArt) -> NSImage? {
        let canvas: CGFloat = 512
        let inset = canvas * (100.0 / 1024.0)
        let plate = canvas - inset * 2
        let renderer = ImageRenderer(
            content: AppIconMark(art: art)
                .frame(width: plate, height: plate)
                .clipShape(IconSquircle())
                .shadow(color: .black.opacity(0.3), radius: canvas * 0.035, y: canvas * 0.015)
                .frame(width: canvas, height: canvas)
        )
        // 1024 pixels from a 512-point drawing, which is the largest slot the
        // catalogue holds and what the Dock asks for on a Retina display.
        renderer.scale = 2
        return renderer.nsImage
    }
    #endif
}

/// Keeps the running app wearing whatever the two switches in Settings, the
/// theme slots and the appearance add up to.
///
/// **On the view rather than in the store.** Which icon to wear is a question
/// about preferences, the theme *and* the appearance on screen, and the last of
/// those is an environment value that only a view can read. The store carries
/// no AppKit and no UIKit, and this keeps it that way.
///
/// It is attached in two places — the board and the Settings scene — because on
/// the desk they are separate scenes and the board window can be closed with
/// Settings still open. Applying twice costs nothing: ``AppIconInstaller``
/// holds what it last set.
struct AppIconKeeper: ViewModifier {
    @Environment(BoardStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(Preferences.appIconKey) private var gradientID = AppIcon.defaultID
    @AppStorage(Preferences.appIconFollowsThemeKey) private var followsTheme = false

    private var resolved: ResolvedAppIcon {
        AppIcon.resolve(
            AppIconSelection(gradientID: gradientID, followsTheme: followsTheme),
            themes: store.themes,
            appearance: (appearance.colorScheme ?? colorScheme).themeAppearance
        )
    }

    func body(content: Content) -> some View {
        content
            .onAppear { AppIconInstaller.apply(resolved) }
            // One `onChange` for all four inputs, because they are read through
            // one value: a theme edited in the browser, the system going dark,
            // and either switch in Settings all arrive here as a different
            // `ResolvedAppIcon` or as nothing at all.
            .onChange(of: resolved) { _, icon in AppIconInstaller.apply(icon) }
    }
}

extension View {
    /// See ``AppIconKeeper``.
    func keepsTheAppIconInStep() -> some View { modifier(AppIconKeeper()) }
}
