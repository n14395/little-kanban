import SwiftUI
#if os(macOS)
import AppKit
import Combine
#endif

@main
struct SimpleKanbanApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = BoardStore.restored()
    /// Owned here so it lives as long as the app does: everything that renders
    /// a due chip or a relative timestamp reads it, and one clock keeps them
    /// all rolling over together.
    @State private var dayClock = DayClock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(\.dayClock, dayClock)
                .onAppear { dayClock.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // A machine that slept through midnight never got its wake.
                dayClock.refresh()
            } else {
                // Edits are written on a short debounce; leaving the foreground
                // is one of the moments that debounce would not survive.
                store.saveNow()
            }
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
/// blocks, so the app simply follows the system appearance; the accent is the
/// one colour choice the design leaves to the user.
struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BoardStore.self) private var store

    private var palette: Palette {
        Palette(colorScheme: colorScheme, accentTheme: store.accentTheme)
    }

    var body: some View {
        platformRoot
            .environment(\.palette, palette)
            .tint(palette.accent)
            .foregroundStyle(palette.ink)
            .modifier(LoadFailureAlert())
            .modifier(FlushOnTerminate())
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

/// A board that could not be read is the one failure the user has to be told
/// about before they touch anything. The damaged file is still on disk under
/// another name, and when it could not even be moved aside, acknowledging this
/// alert is what allows the app to start writing again — over it.
private struct LoadFailureAlert: ViewModifier {
    @Environment(BoardStore.self) private var store

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(
                get: { store.loadFailure != nil },
                set: { if !$0 { store.acknowledgeLoadFailure() } }
            )
        ) {
            Button("OK") { store.acknowledgeLoadFailure() }
        } message: {
            Text(message)
        }
    }

    /// Built from `loadFailure` rather than `lastError` so a write that fails
    /// while the alert is up cannot rewrite what it says.
    private var failure: BoardStoreError? {
        store.loadFailure.map(BoardStoreError.load)
    }

    private var title: String {
        failure?.errorDescription
            ?? String(localized: "Your board could not be read.",
                      comment: "Alert title when the saved board is unusable")
    }

    private var message: String {
        [failure?.recoverySuggestion, store.quarantinedBoardURL?.path(percentEncoded: false)]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }
}

/// macOS does not move the scene out of `.active` before terminating, so ⌘Q
/// within the debounce window would drop the last edit. iOS backgrounding is
/// already covered by `scenePhase`.
private struct FlushOnTerminate: ViewModifier {
    @Environment(BoardStore.self) private var store

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            store.saveNow()
        }
        #else
        content
        #endif
    }
}
