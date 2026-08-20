import SwiftUI

@main
struct SimpleKanbanApp: App {
    @State private var store = BoardStore()

    init() {
        FontRegistry.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        #if os(macOS)
        .defaultSize(width: 1240, height: 812)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        #endif
    }
}

/// Resolves the palette for the active colour scheme and picks the platform's
/// root surface. Light and dark both come straight from the design's theme
/// blocks, so the app simply follows the system appearance.
struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: Palette { Palette(colorScheme: colorScheme) }

    var body: some View {
        platformRoot
            .environment(\.palette, palette)
            .tint(palette.accent)
            .foregroundStyle(palette.ink)
    }

    @ViewBuilder
    private var platformRoot: some View {
        #if os(macOS)
        MacRootView()
        #else
        PhoneRootView()
        #endif
    }
}
