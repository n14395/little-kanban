import SwiftUI
#if os(macOS)
import AppKit
import Combine
#else
import UIKit
#endif

@main
struct SimpleKanbanApp: App {
    /// Named here rather than at both ends: the app menu opens it and the scene
    /// declares it, and a typo in either is a menu item that does nothing.
    static let aboutWindowID = "about"

    @State private var store: BoardStore
    /// Owned here so it lives as long as the app does: everything that renders
    /// a due chip or a relative timestamp reads it, and one clock keeps them
    /// all rolling over together.
    @State private var dayClock = DayClock()
    #if os(macOS)
    /// Owned here rather than in `MacRootView` because the menu bar is outside
    /// every window's view tree and still has to toggle the sidebar.
    @State private var window = MacWindowState()
    #endif

    /// The store is built here rather than in a property initialiser because an
    /// App Intent can run in a process the user never brought to the front, and
    /// perform before the first scene exists. Registering the store as the app
    /// is constructed is what keeps `AddTaskIntent` from failing with "still
    /// starting up" on a cold launch.
    init() {
        // A first launch starts on nothing rather than on the seed: `FirstRunView`
        // asks which board to start from, and folds the answer in. `restored()`
        // would have seeded the sample before anybody was asked (7.5).
        let store = FirstRun.isPending ? FirstRun.emptyStore() : BoardStore.restored()
        _store = State(initialValue: store)
        TaskIntentBridge.adopt(store)
    }

    var body: some Scene {
        #if os(macOS)
        // `Window` rather than `WindowGroup`: every piece of per-window state
        // this app has — the selection, the surface, the inspector, the open
        // composer — lives in the one shared `BoardStore`, so a second window
        // would not be a second view of the board but a mirror of the first,
        // scrolling and selecting in lockstep. Making two windows genuinely
        // independent means lifting that state out of the store, which is a
        // bigger change than this phase is for. One window also takes New
        // Window off the File menu, which is where ⌘N's ambiguity started.
        //
        // The frame is still restored: AppKit autosaves it against the scene's
        // id, and `.defaultSize` applies only to a window it has never seen.
        Window("Simple Kanban", id: "board") {
            root.environment(window)
        }
        .defaultSize(width: 1240, height: 812)
        .windowStyle(.hiddenTitleBar)
        // The board has a floor of its own — see `MacRootView` — and the
        // content is what it is measured against. `.contentSize` would also pin
        // the maximum, and a board is a surface people want as wide as the
        // screen.
        .windowResizability(.contentMinSize)
        .commands { BoardCommands(store: store, window: window) }

        // Which is where ⌘, comes from — SwiftUI puts Settings… on the app menu
        // itself, so the vocabulary in `AppCommand` neither declares it nor has
        // to. The scene is a root of its own and inherits nothing from the
        // window, so everything the pane reads is handed to it here.
        Settings {
            SettingsWindow()
                .environment(store)
                .environment(\.dayClock, dayClock)
        }

        // About, and the update check with it. A scene rather than a sheet for
        // the reason in `AboutView`, and because it is the app talking about
        // itself rather than about this board. Like `Settings`, it inherits
        // nothing from the window and resolves its own palette.
        Window("About Simple Kanban", id: Self.aboutWindowID) {
            AboutWindow(startsCheck: window.aboutStartsCheck)
                .environment(store)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        // Nobody wants an About panel greeting them because it happened to be
        // open when they last quit.
        .restorationBehavior(.disabled)

        MenuBarQuickAdd(store: store)
        #else
        WindowGroup {
            root
        }
        #endif
    }

    private var root: some View {
        RootView()
            .environment(store)
            .environment(\.dayClock, dayClock)
            .onAppear { dayClock.start() }
            .modifier(ScenePhaseWork(store: store, dayClock: dayClock))
    }
}

/// The two things the app does at the edges of a session. On the view rather
/// than on the scene so both platforms' scenes carry it without a second copy.
private struct ScenePhaseWork: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let store: BoardStore
    let dayClock: DayClock

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // A machine that slept through midnight never got its wake.
                dayClock.refresh()
            } else {
                // Edits are written on a short debounce; leaving the foreground
                // is one of the moments that debounce would not survive.
                store.saveNow()
            }
        }
    }
}

/// Resolves the palette for the active colour scheme and picks the platform's
/// root surface. Light and dark both come straight from the design's theme
/// blocks; the app follows the system appearance unless Settings ▸ Appearance
/// says otherwise, and the accent is the other colour choice the design leaves
/// to the user.
struct RootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BoardStore.self) private var store
    /// The one appearance preference. `nil` from `.system`, which is what
    /// `preferredColorScheme` wants and what leaves the app following the OS.
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    /// The window's undo manager. The store cannot reach the environment, so
    /// this is where the two are introduced — without it every mutation still
    /// works and ⌘Z simply does nothing.
    @Environment(\.undoManager) private var undoManager

    /// The override, or the system's answer. Resolved here rather than left to
    /// `preferredColorScheme` alone: that propagates *downwards*, so the view
    /// that sets it does not see it, and the palette is built in this body.
    private var palette: Palette {
        Palette(colorScheme: appearance.colorScheme ?? colorScheme, accentTheme: store.accentTheme)
    }

    var body: some View {
        platformRoot
            .environment(\.palette, palette)
            .tint(palette.accent)
            .foregroundStyle(palette.ink)
            // Below the palette, so the system's own controls — menus, fields,
            // the sheets they open — follow the override too.
            .preferredColorScheme(appearance.colorScheme)
            .modifier(SaveFailureBanner())
            .modifier(SettingsSheet())
            // Last of the presentations, so it covers the lot: nothing else has
            // anything to say until there is a board to say it about.
            .modifier(FirstRunChoice())
            // Inside `RootView.body` and not on `root`: it reads the store out
            // of the environment, and a modifier applied above `.environment`
            // sits above it in the tree and would never see one.
            .systemEntryPoints()
            .modifier(LoadFailureAlert())
            .modifier(FlushOnTerminate())
            .onAppear { adoptUndoManager() }
            // `UndoManager` is a class and not `Equatable`, so the identity of
            // the one in the environment is what the change is watched on.
            .onChange(of: undoManagerID) { _, _ in adoptUndoManager() }
    }

    private var undoManagerID: ObjectIdentifier? {
        undoManager.map { ObjectIdentifier($0) }
    }

    /// Never handed a `nil`: the environment can go quiet for a beat while a
    /// window is being replaced, and clearing the reference then would leave the
    /// Edit menu registering against nothing. The store holds it weakly, so a
    /// manager that really has gone away drops out on its own.
    private func adoptUndoManager() {
        guard let undoManager, store.undoManager !== undoManager else { return }
        store.undoManager = undoManager
    }

    @ViewBuilder
    private var platformRoot: some View {
        #if os(macOS)
        MacRootView()
        #else
        SizeClassRoot()
        #endif
    }
}

#if os(iOS)
/// Which of the two iOS surfaces the app draws.
///
/// Two facts decide it, and each answers a different question. The **idiom**
/// says which device this is; the **horizontal size class** says how much of it
/// this window has. The desk's layout needs both — it is the iPad's, and only
/// when the window is wide enough to hold three panes.
///
/// The size class alone is not the iPad. A regular horizontal size class is
/// also what a Max- or Plus-class iPhone reports in landscape, so asking it on
/// its own handed a phone at 956×440 the split view, the sidebar toggle, the
/// inspector and the column controls — and took away the two-up landscape board
/// `PhoneRootView` lays out for exactly those devices (5.5). The idiom alone is
/// not the window: an iPad in Slide Over or in a narrow split has a phone's
/// worth of width, and the split view has nowhere to put a sidebar.
///
/// A value rather than a branch in the body so the rule can be held up to a
/// test — `RootSurfaceTests` walks the four combinations that reach it.
enum RootSurface: Equatable {
    case pad, phone

    static func resolve(
        idiom: UIUserInterfaceIdiom, horizontalSizeClass: UserInterfaceSizeClass?
    ) -> RootSurface {
        idiom == .pad && horizontalSizeClass == .regular ? .pad : .phone
    }
}

private struct SizeClassRoot: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        switch RootSurface.resolve(
            idiom: UIDevice.current.userInterfaceIdiom, horizontalSizeClass: horizontalSizeClass
        ) {
        case .pad: PadRootView()
        case .phone: PhoneRootView()
        }
    }
}
#endif

#if os(macOS)
/// The `Settings` scene's root.
///
/// A scene of its own, so nothing reaches it: the palette, the tint and the
/// appearance override all have to be resolved here rather than inherited from
/// the window the way every other surface inherits them.
private struct SettingsWindow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BoardStore.self) private var store
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    private var palette: Palette {
        Palette(colorScheme: appearance.colorScheme ?? colorScheme, accentTheme: store.accentTheme)
    }

    var body: some View {
        SettingsView(metrics: .desk)
            .environment(\.palette, palette)
            .tint(palette.accent)
            .foregroundStyle(palette.ink)
            .preferredColorScheme(appearance.colorScheme)
    }
}
#endif

#if os(macOS)
/// The About scene's root.
///
/// A scene of its own, so — exactly as with `SettingsWindow` — nothing reaches
/// it: the palette, the tint and the appearance override are all resolved here
/// rather than inherited from the board window.
private struct AboutWindow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BoardStore.self) private var store
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    /// Whether the item that opened the window was Check for Updates…
    let startsCheck: Bool

    private var palette: Palette {
        Palette(colorScheme: appearance.colorScheme ?? colorScheme, accentTheme: store.accentTheme)
    }

    var body: some View {
        AboutView(metrics: .desk, startsCheck: startsCheck)
            .environment(\.palette, palette)
            .tint(palette.accent)
            .foregroundStyle(palette.ink)
            .preferredColorScheme(appearance.colorScheme)
    }
}
#endif

/// The iOS half of Settings. macOS has the `Settings` scene and ⌘, ; the phone
/// and the iPad get the same view as a sheet, raised by `store.isShowingSettings`
/// — which is on the store because the row that sets it is in the drawer and the
/// sheet is presented from the root.
private struct SettingsSheet: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    /// Resolved here rather than read out of the environment, for the reason
    /// `FirstRunChoice` gives: a modifier sits *above* the
    /// `.environment(\.palette,)` the root applies below it, so what it reads is
    /// the default light palette — and this sheet then opened cream-coloured
    /// over a dark board, with the default accent rather than the user's.
    private var palette: Palette {
        Palette(colorScheme: appearance.colorScheme ?? colorScheme, accentTheme: store.accentTheme)
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        @Bindable var store = store
        return content.sheet(isPresented: $store.isShowingSettings) {
            SettingsWithAbout()
                .environment(store)
                .environment(\.palette, palette)
                .environment(\.dayClock, dayClock)
                .tint(palette.accent)
                .foregroundStyle(palette.ink)
        }
        #else
        content
        #endif
    }
}

/// The phone's answer to the macOS status bar.
///
/// A write that fails has nowhere else to be seen on iOS: there is no footer
/// strip, and an app that has silently stopped saving looks exactly like one
/// that is working. The banner takes a safe-area inset rather than an overlay
/// on purpose — it must not sit on top of the header it is warning about, and a
/// failure the user can scroll under is one they will not read.
///
/// Dismissible, because the error is a fact about the last write and not a
/// modal state: clearing it leaves the board exactly as it was, and the next
/// failed write puts it straight back.
private struct SaveFailureBanner: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BoardStore.self) private var store
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    /// The same resolution `SettingsSheet` does, and for the same reason: a
    /// modifier reads the environment from above the root that publishes the
    /// palette, so the banner was drawing itself out of the light theme on a
    /// dark board.
    private var palette: Palette {
        Palette(colorScheme: appearance.colorScheme ?? colorScheme, accentTheme: store.accentTheme)
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let message {
                banner(message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: message)
        #else
        content
        #endif
    }

    /// Only a *write* failure: a load failure already has the launch alert, and
    /// saying it twice would leave a banner behind the sheet that explains it.
    private var message: String? {
        if case .save(let detail) = store.lastError {
            return String(localized: "The board could not be saved. \(detail)",
                          comment: "iOS banner text for a failed write")
        }
        if store.isSaveBlocked {
            return String(localized: "Saving is paused so the unreadable board file is not written over.",
                          comment: "iOS banner text while writes are held back")
        }
        return nil
    }

    private func banner(_ message: String) -> some View {
        HStack(spacing: 4) {
            // The glyph tracks the first line rather than the middle of a
            // message that has wrapped; the dismiss button is centred on the
            // whole row, which is why the two alignments are nested.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text(message)
                    .font(SimpleKanbanFont.ui(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { store.dismissError() } label: {
                Image(systemName: "xmark")
                    .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .caption2))
                    .foregroundStyle(palette.ink(0.55))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bare)
            .accessibilityLabel("Dismiss")
            // The blocked-saving message is a standing state rather than one
            // failure, and there is nothing to dismiss it to.
            .opacity(store.lastError == nil ? 0 : 1)
            .disabled(store.lastError == nil)
        }
        .padding(.leading, 16)
        .padding(.vertical, 6)
        .background {
            Rectangle()
                .fill(palette.card)
                .shadow(color: palette.shadow(0.12), radius: 8, y: 3)
                .ignoresSafeArea(edges: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isSummaryElement)
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

/// The first-launch board picker (7.5).
///
/// A cover rather than a sheet on the phone and a sheet on the desk, which is
/// each platform's answer to "there is nothing behind this worth looking at
/// yet". It is dismissed by choosing, and by nothing else — `FirstRunView`
/// disables interactive dismissal, and the empty board is one of the choices.
///
/// The template is folded in with `importBoard` rather than written over the
/// top of anything, because the board it is folding into is empty: the app
/// launched on `FirstRun.emptyStore()`. That also makes the choice a single ⌘Z.
private struct FirstRunChoice: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BoardStore.self) private var store
    @AppStorage(FirstRun.storageKey) private var hasChosen = false
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    /// Resolved here rather than read out of the environment. A modifier sits
    /// *above* the `.environment(\.palette,)` the root applies below it, so what
    /// it would read is the default light palette — which is how a picker comes
    /// to open cream-coloured over a dark board.
    private var palette: Palette {
        Palette(colorScheme: appearance.colorScheme ?? colorScheme, accentTheme: store.accentTheme)
    }

    private static var metrics: FirstRunView.Metrics {
        #if os(macOS)
        .desk
        #else
        .sheet
        #endif
    }

    /// Written only by the choice. The getter is what closes the cover once the
    /// preference lands, and the setter exists because a presentation binding
    /// must have one — nothing else can reach it.
    private var isPresented: Binding<Bool> {
        Binding(get: { FirstRun.isPending && !hasChosen }, set: { if !$0 { hasChosen = true } })
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: isPresented) { picker }
        #else
        content.sheet(isPresented: isPresented) { picker }
        #endif
    }

    private var picker: some View {
        FirstRunView(metrics: Self.metrics, templates: SeedData.starters) { template in
            store.importBoard(template.snapshot)
            hasChosen = true
        }
        .environment(\.palette, palette)
        .tint(palette.accent)
        .foregroundStyle(palette.ink)
    }
}

/// Settings, with the version underneath it.
///
/// The desk shows the version in the About panel the app menu opens; the phone
/// has no menu bar, so the footer of the settings sheet is where the app says
/// what it is — and it is a row rather than a label, because the update check
/// has to be reachable from somewhere.
private struct SettingsWithAbout: View {
    @Environment(\.palette) private var palette
    @State private var isShowingAbout = false

    var body: some View {
        SettingsView(metrics: .sheet)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .sheet(isPresented: $isShowingAbout) {
                AboutView(metrics: .sheet)
                    .environment(\.palette, palette)
                    .tint(palette.accent)
                    .foregroundStyle(palette.ink)
            }
    }

    private var footer: some View {
        Button { isShowingAbout = true } label: {
            HStack(spacing: 8) {
                Text(AboutView.displayName)
                    .font(SimpleKanbanFont.ui(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink(0.75))
                Text(AboutView.versionLine)
                    .font(SimpleKanbanFont.ui(12.5, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.ink(0.4))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(palette.ink(0.3))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .accessibilityLabel(Text("About \(AboutView.displayName)",
                                 comment: "Settings footer row that opens the About surface"))
        .accessibilityValue(AboutView.versionLine)
        .background {
            Rectangle()
                .fill(palette.sheet)
                .hairline(.top, color: palette.ink(0.08))
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
