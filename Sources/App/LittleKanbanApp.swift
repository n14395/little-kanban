import SwiftUI
#if os(macOS)
import AppKit
import Combine
#else
import UIKit
#endif

@main
struct LittleKanbanApp: App {
    /// Named here rather than at both ends: the app menu opens it and the scene
    /// declares it, and a typo in either is a menu item that does nothing.
    static let aboutWindowID = "about"
    /// The theme browser's window. Same reason as ``aboutWindowID``: Settings
    /// opens it and the scene declares it.
    static let themesWindowID = "themes"

    @State private var store: BoardStore
    /// Owned here so it lives as long as the app does: everything that renders
    /// a due chip or a relative timestamp reads it, and one clock keeps them
    /// all rolling over together.
    @State private var dayClock = DayClock()
    /// Owned here rather than in a root view because the menu bar is outside
    /// every window's view tree and still has to toggle the source list. On both
    /// platforms now that the iPad has a menu bar of ours — see ``BoardCommands``.
    @State private var window = AppWindowState()

    /// The store is built here rather than in a property initialiser because an
    /// App Intent can run in a process the user never brought to the front, and
    /// perform before the first scene exists. Registering the store as the app
    /// is constructed is what keeps `AddTaskIntent` from failing with "still
    /// starting up" on a cold launch.
    init() {
        // A first launch starts on nothing rather than on the seed: `FirstRunView`
        // asks which board to start from, and folds the answer in. `restored()`
        // would have seeded the sample before anybody was asked (7.5). It gets
        // the records all the same — a first session that could not write them
        // was a first session the next launch threw away.
        // The records the board syncs through. Local-only until the build
        // carries the iCloud entitlement — see `project.yml` — and `nil` if the
        // store cannot be opened at all, which leaves `board.json` in charge
        // rather than handing anybody an empty board.
        let sync = try? BoardSyncStore.app(syncing: SyncPreference.isOn, at: BoardSyncStore.defaultURL)
        let store = FirstRun.isPending
            ? FirstRun.emptyStore(sync: sync)
            : BoardStore.restored(sync: sync)
        _store = State(initialValue: store)
        TaskIntentBridge.adopt(store)
        #if os(macOS)
        // The terminate flush is the *app's*, not a window's. macOS does not
        // move any scene out of `.active` before terminating, so ⌘Q inside
        // the save debounce would drop the last edit — and for a while the
        // flush rode the board window's view tree, which is a window the
        // menu bar extra lets the app outlive: a quick-add capture within
        // 500 ms of Quit, with the board window closed, was lost with the
        // debounce, and the Settings scene's imports and theme edits rode
        // the same debounce with no flush of their own. An observer on the
        // process covers every scene, open or closed, and is never removed
        // because the moment it fires is the process ending. iOS needs none
        // of this — backgrounding is covered by `ScenePhaseWork`.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { store.saveNow() }
        }
        #endif
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
        Window("Little Kanban", id: "board") {
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

        // About. A scene rather than a sheet for the reason in `AboutView`,
        // and because it is the app talking about itself rather than about
        // this board. Like `Settings`, it inherits nothing from the window and
        // resolves its own palette.
        Window("About Little Kanban", id: Self.aboutWindowID) {
            AboutWindow()
                .environment(store)
        }
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        // Nobody wants an About panel greeting them because it happened to be
        // open when they last quit.
        .restorationBehavior(.disabled)

        // **A window rather than a sheet over Settings.** The browser is a grid
        // of pictures of the app, and comparing two of them is what it is for —
        // which means it wants to be as big as the screen allows and to stay put
        // while the theme it is choosing repaints the board behind it. A sheet
        // is neither: it is pinned to the width of the pane it hangs off, it
        // cannot be resized, and it blocks the window it is attached to. Like
        // About and Settings, this scene is a root of its own and resolves its
        // own palette.
        Window("Themes", id: Self.themesWindowID) {
            ThemesWindow()
                .environment(store)
        }
        .defaultSize(width: 900, height: 720)
        .defaultPosition(.center)
        // `.contentMinSize` rather than `.contentSize`: the grid is adaptive, so
        // a wider window is more columns, and pinning the maximum would take
        // that away.
        .windowResizability(.contentMinSize)
        // Nobody wants the theme browser greeting them because it happened to be
        // open when they last quit.
        .restorationBehavior(.disabled)

        MenuBarQuickAdd(store: store)
        #else
        WindowGroup {
            root.environment(window)
        }
        // **iPadOS draws a menu bar too.** Without this the app got the system's
        // default one — File, Edit and View with nothing of this app's in any of
        // them — and every key the shortcuts sheet teaches went nowhere. The same
        // `Commands` the desk declares, from the same vocabulary: see
        // `AppCommand.platforms` for the two items that are one platform's only.
        //
        // The iPhone has no menu bar to draw them on and loses nothing by their
        // being declared: a `Commands` body it cannot show is a set of key
        // equivalents for a hardware keyboard, which is exactly what an iPhone
        // with one attached should have.
        .commands { BoardCommands(store: store, window: window) }
        #endif
    }

    private var root: some View {
        RootView()
            .environment(store)
            .environment(\.dayClock, dayClock)
            .onAppear {
                dayClock.start()
                // Another device's edit arrives as a store notification rather
                // than as anything the app asked for, so the listener goes up
                // once and stays up.
                store.beginObservingRemoteChanges()
                // Anything shared while the app was not running. Here as well
                // as on `.active` because a launch is not a foregrounding on
                // either platform: the scene comes up already active and the
                // change never fires.
                store.adoptPendingCaptures()
            }
            .modifier(ScenePhaseWork(store: store, dayClock: dayClock))
    }
}

/// What the app does at the edges of a session — and at the edge of a day.
/// On the view rather than on the scene so both platforms' scenes carry it
/// without a second copy.
private struct ScenePhaseWork: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let store: BoardStore
    let dayClock: DayClock

    func body(content: Content) -> some View {
        content
            // The auto-archive sweep reads calendar days, so midnight is the
            // one moment it can find new work in a session that is already
            // running — and it used to run at launch alone, which on a Mac
            // that stays open for a week meant Done quietly stopped emptying
            // until the next relaunch. `refresh()` below moves the clock on a
            // machine that slept through midnight, so the wake lands here too.
            .onChange(of: dayClock.today) { _, _ in
                store.sweepDone()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    // A machine that slept through midnight never got its wake.
                    dayClock.refresh()
                    // Coming forward is the moment to collect whatever the
                    // share extension left in the App Group while this process
                    // was suspended — it cannot write to the board itself, so
                    // this is the only path a shared item takes onto it. Cheap
                    // and silent with nothing waiting.
                    store.adoptPendingCaptures()
                } else {
                    // Edits are written on a short debounce; leaving the
                    // foreground is one of the moments that debounce would not
                    // survive.
                    //
                    // Unless this is a first run whose picker is still up. The
                    // flush writes `board.json`, and "the file exists" is
                    // exactly what `FirstRun.isPending` reads as *not* a first
                    // run — so backgrounding mid-picker quietly made the
                    // empty-board choice on the user's behalf: the next launch
                    // had no picker, no starter templates and no
                    // Sync-from-iCloud row. There is nothing worth flushing in
                    // that state — the board is empty by construction, and the
                    // choice is what writes first. The moment one is made,
                    // `FirstRun.storageKey` flips and every later backgrounding
                    // flushes as normal.
                    guard !FirstRun.isPending
                            || UserDefaults.standard.bool(forKey: FirstRun.storageKey) else { return }
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
        Palette(theme: store.theme(for: (appearance.colorScheme ?? colorScheme).themeAppearance))
    }

    var body: some View {
        // Taken once: `palette` is computed, and each read below re-resolved
        // the theme and rebuilt the struct.
        let palette = self.palette
        return platformRoot
            .environment(\.palette, palette)
            .tint(palette.accent)
            .foregroundStyle(palette.ink)
            // Below the palette, so the system's own controls — menus, fields,
            // the sheets they open — follow the override too.
            .preferredColorScheme(appearance.colorScheme)
            .modifier(SaveFailureBanner())
            .modifier(SettingsSheet())
            .modifier(BoardSettingsSheet())
            // Last of the presentations, so it covers the lot: nothing else has
            // anything to say until there is a board to say it about.
            .modifier(FirstRunChoice())
            // Inside `RootView.body` and not on `root`: it reads the store out
            // of the environment, and a modifier applied above `.environment`
            // sits above it in the tree and would never see one.
            .systemEntryPoints()
            // Above `preferredColorScheme` in the tree, so the appearance it
            // reads is the system's and the override is applied on top of it
            // here — the same expression `palette` is built from. Inside
            // `RootView.body` for `systemEntryPoints`' reason.
            .keepsTheAppIconInStep()
            // Beside the icon keeper because it is the same kind of thing: a
            // fact about the app that is kept in step with the board from the
            // one place that can see the store, the clock and the appearance at
            // once. See ``WidgetKeeper``.
            .keepsTheWidgetsInStep()
            .modifier(LoadFailureAlert())
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
        // Bounded because every step holds a snapshot of the whole board (see
        // `BoardStore.undoable`) — snapshots share unchanged cards, but an
        // unlimited stack still grows for as long as a session lasts. A
        // hundred steps is more ⌘Z than anyone walks back, for megabytes less.
        undoManager.levelsOfUndo = 100
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
/// inspector and the column controls — and took away the three-up landscape
/// board `PhoneRootView` lays out for exactly those devices (5.5). The idiom
/// alone is not the window: an iPad in Slide Over or in a narrow split has a
/// phone's worth of width, and the split view has nowhere to put a sidebar.
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
        Palette(theme: store.theme(for: (appearance.colorScheme ?? colorScheme).themeAppearance))
    }

    var body: some View {
        let palette = self.palette
        return SettingsView(metrics: .desk)
            .environment(\.palette, palette)
            .tint(palette.accent)
            .foregroundStyle(palette.ink)
            .preferredColorScheme(appearance.colorScheme)
            // A second copy, because on the desk these are two scenes and the
            // board window can be closed with Settings still open — which is
            // exactly when somebody is most likely to be changing the icon.
            // Applying twice costs nothing; see ``AppIconInstaller``.
            .keepsTheAppIconInStep()
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

    private var palette: Palette {
        Palette(theme: store.theme(for: (appearance.colorScheme ?? colorScheme).themeAppearance))
    }

    var body: some View {
        let palette = self.palette
        return AboutView(metrics: .desk)
            .environment(\.palette, palette)
            .tint(palette.accent)
            .foregroundStyle(palette.ink)
            .preferredColorScheme(appearance.colorScheme)
    }
}

/// The theme browser's own window: the store, and a palette resolved the way
/// ``AboutWindow`` resolves one, because a `Window` scene inherits nothing from
/// the board.
private struct ThemesWindow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BoardStore.self) private var store
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    private var palette: Palette {
        Palette(theme: store.theme(for: (appearance.colorScheme ?? colorScheme).themeAppearance))
    }

    var body: some View {
        let palette = self.palette
        return ThemeBrowserView(metrics: .window)
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
        Palette(theme: store.theme(for: (appearance.colorScheme ?? colorScheme).themeAppearance))
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

/// A board's own settings, on every platform — see ``BoardSettingsView``.
///
/// Presented here rather than by whatever raised it, because what raises it is
/// usually a menu: a sidebar row's context menu on the desk and the iPad, the
/// phone's board menu, the drawer's board row, a column chip. A menu can set a
/// flag and cannot present a sheet, which is the same split the Trash makes.
///
/// The chrome is the platform's. iOS holds it at `.large` for
/// `PhoneDetailSheet`'s reason — a sheet at a smaller detent is scaled to fit
/// its inset, and every 44pt control in there would render under the touch
/// minimum. The desk gets a fixed frame instead, sized to the widest thing in
/// it: a column row with its role, its marker and its chevron.
private struct BoardSettingsSheet: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BoardStore.self) private var store
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    /// Resolved here for `SettingsSheet`'s reason: a modifier sits above the
    /// root's own `.environment(\.palette,)` and would otherwise read the
    /// default light palette.
    private var palette: Palette {
        Palette(theme: store.theme(for: (appearance.colorScheme ?? colorScheme).themeAppearance))
    }

    func body(content: Content) -> some View {
        @Bindable var store = store

        return content.sheet(item: $store.boardSettings) { request in
            settings(request)
                .environment(store)
                .environment(\.palette, palette)
                .tint(palette.accent)
                .foregroundStyle(palette.ink)
        }
    }

    @ViewBuilder private func settings(_ request: BoardSettingsRequest) -> some View {
        #if os(iOS)
        BoardSettingsView(
            boardID: request.board,
            metrics: .sheet,
            focusesName: request.focusesName,
            addsColumn: request.addsColumn,
            namesNewBoard: request.namesNewBoard,
            expandsColumn: request.column
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(palette.windowFill)
        #else
        BoardSettingsView(
            boardID: request.board,
            metrics: .desk,
            focusesName: request.focusesName,
            addsColumn: request.addsColumn,
            namesNewBoard: request.namesNewBoard,
            expandsColumn: request.column
        )
        .frame(width: 420, height: 560)
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
        Palette(theme: store.theme(for: (appearance.colorScheme ?? colorScheme).themeAppearance))
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
            return String(localized: "Saving is paused so the unreadable board file is not written over. Export keeps a copy of what you do meanwhile.",
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
                    .font(palette.ui(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The one action that rescues a blocked session: everything made
            // while saving is paused exists in memory and the records only,
            // and an export is the copy the user can put somewhere they chose.
            if store.isSaveBlocked {
                BlockedSessionExportButton(palette: palette)
            }
            Button { store.dismissError() } label: {
                Image(systemName: "xmark")
                    .font(palette.ui(11, .bold, relativeTo: .caption2))
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

/// The banner's **Export…**, as its own view so the snapshot it exports is
/// read in the smallest body there is — `BoardTransfer` says why reading
/// `exportedSnapshot` any higher up costs a whole-window re-render per
/// keystroke.
private struct BlockedSessionExportButton: View {
    @Environment(BoardStore.self) private var store
    let palette: Palette
    @State private var isExporting = false
    @State private var failure: String?

    var body: some View {
        Button {
            isExporting = true
        } label: {
            Text("Export…", comment: "Banner button that saves a copy of the board while saving is paused")
                .font(palette.ui(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(palette.accent)
                .frame(minHeight: 44)
        }
        .buttonStyle(.bare)
        .fileExporter(
            isPresented: $isExporting,
            document: BoardTransferDocument(store.exportedSnapshot),
            contentType: .simpleKanbanBoard,
            defaultFilename: BoardTransferDocument.filename(on: .today())
        ) { result in
            if case .failure(let error) = result { failure = error.localizedDescription }
        }
        .alert(
            String(localized: "The board could not be exported.",
                   comment: "Alert title when the blocked-session export fails"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
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
        Palette(theme: store.theme(for: (appearance.colorScheme ?? colorScheme).themeAppearance))
    }

    /// Written only by the choice. The getter is what closes the cover once the
    /// preference lands, and the setter exists because a presentation binding
    /// must have one — nothing else can reach it.
    ///
    /// **And the picker yields to a board that arrives.** A fresh install on a
    /// device whose account already has a board is not a first run — it only
    /// looks like one because CloudKit has not finished delivering yet. If the
    /// person picks a starter inside that window, the template mints a whole
    /// second identity for boards they already have, and the two copies then
    /// fight on every device — the twin-boards disaster. So the moment a merge
    /// puts boards on the store while the cover is still up, the cover goes:
    /// the account has answered the question the picker was asking.
    private var isPresented: Binding<Bool> {
        Binding(get: { FirstRun.isPending && !hasChosen && store.boards.isEmpty },
                set: { if !$0 { hasChosen = true } })
    }

    func body(content: Content) -> some View {
        content.starterPicker(
            isPresented: isPresented, occasion: .firstLaunch, palette: palette,
            // The account's own answer, offered only when the build can hear
            // it. Choosing it imports nothing — bare is the starting state —
            // and nudges a merge so anything the mirror has already brought
            // down lands now rather than at the next notification; the rest
            // arrives the way every remote change does.
            syncFromICloud: store.isSyncing ? {
                hasChosen = true
                store.mergeRemoteChanges()
            } : nil
        ) { template in
            store.importBoard(template.snapshot)
            hasChosen = true
        }
    }
}

/// Settings, with the version underneath it.
///
/// The desk shows the version in the About panel the app menu opens; the phone
/// has no menu bar, so the footer of the settings sheet is where the app says
/// what it is — and it is a row rather than a label, so the About sheet is
/// reachable from somewhere.
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
                    .font(palette.ui(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink(0.75))
                Text(AboutView.versionLine)
                    .font(palette.ui(12.5, .medium, relativeTo: .caption))
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
                .fill(palette.windowFill)
                .hairline(.top, color: palette.ink(0.08))
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
