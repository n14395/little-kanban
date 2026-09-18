import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// The subjects Settings is divided into, in the order they are shown.
///
/// One list, read by both platforms, so that a subject cannot exist on one and
/// go missing on the other — which is exactly what had happened. **System** was
/// in the macOS `TabView` with no `.tabItem` on it, and a tab with no label is a
/// blank slot in the toolbar: the pane was reachable only by clicking the gap
/// where its name should have been. The title and the symbol now come from here,
/// once, rather than from a `Label` in one place and a `section(_:)` string in
/// another.
///
/// **Four, where there were eight.** Trash, Appearance, Board, Notifications,
/// Sync, System, Labels and Data was a list long enough that finding a setting
/// meant reading every name on the way to it — and on a phone, where three chips
/// fit across the strip, most of those names were off the side of the screen. A
/// subject that holds one switch is not a subject; it is a row that has been
/// given a tab of its own. So the four that are left are the questions somebody
/// actually arrives with:
///
/// - **General** — what the app looks like and how it comes up: the accent, the
///   light/dark override, and what is on screen at launch. The desk's two —
///   login registration and the menu bar item — are rows in here now rather than
///   a **System** pane of their own, which is also the end of the one case that
///   had to be compiled out on iOS.
/// - **Board** — how a board behaves: the order cards sit in, how much a card
///   shows, where new ones land and when they are due, when Done is swept, what
///   a week means, and the label vocabulary the cards are tagged from.
/// - **Notifications** — due-date reminders, which is the one subject that was
///   already the right size.
/// - **Data** — where the board lives and how to get it back: iCloud, how long
///   things are kept, export, import, the file itself, the backups, and starting
///   over.
///
/// **The Trash is not here at all** — it never belonged in a preferences
/// surface. It is the user's own work rather than a setting about the app, so it
/// has a door of its own: the Trash row under Views in the source list on macOS
/// and iPad, and the board menu on the phone. See **The trash** in the README.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general, board, notifications, data

    var id: String { rawValue }

    /// The chip's identifier on iOS, shared with `UITests/SettingsTabsTests`
    /// through the source rather than by both spelling the same string — the
    /// same arrangement `BoardToolbar.inboxToggleID` has. The name alone would
    /// not do: "Board" is a word the board behind the sheet uses for its own
    /// controls, and a query by label picks whichever it reaches first.
    var chipID: String { "SettingsTab.\(rawValue)" }

    var title: String {
        switch self {
        case .general: String(localized: "General", comment: "Settings section heading")
        case .board: String(localized: "Board", comment: "Settings section heading")
        case .notifications: String(localized: "Notifications", comment: "Settings section heading")
        case .data: String(localized: "Data", comment: "Settings section heading")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .board: "square.grid.2x2"
        case .notifications: "bell"
        case .data: "externaldrive"
        }
    }
}

/// Everything global, in one place: the accent and the appearance, how the
/// board orders its cards, the label vocabulary, and the board file itself.
///
/// One view for both platforms — the macOS `Settings { }` scene hosts it at
/// `.desk` and the iOS sheet at `.sheet`, which is the difference between a
/// pane inside a window that already has a title bar and a sheet that has to
/// draw its own header and 44pt rows.
///
/// Four subjects — see ``SettingsTab`` for what is in each and why there are
/// four. The Trash is not one of them: it is the user's own work rather than a
/// setting, and it has a door of its own.
///
/// Notifications bind straight to ``NotificationScheduler/shared`` rather than
/// to `@AppStorage`: the scheduler has to *act* on a change — moving the time of
/// day moves every pending request — so it owns the values and writes them to
/// `UserDefaults` itself.
struct SettingsView: View {
    struct Metrics {
        /// A fixed pane on the desk, the whole sheet on a phone — hence optional.
        var width: CGFloat?
        var minHeight: CGFloat?
        var padding: CGFloat
        var sectionSpacing: CGFloat
        var rowSpacing: CGFloat
        var panelRadius: CGFloat
        var titleSize: CGFloat
        var rowFont: CGFloat
        var noteFont: CGFloat
        /// The height a row claims. A settings row is a line of text and a
        /// control, which is nowhere near 44pt on its own.
        var rowHit: CGFloat
        var controlRadius: CGFloat
        var labelManager: LabelManagerView.Metrics
        var appIconPicker: AppIconPickerView.Metrics
        /// Whether the surface draws its own header. The desk's pane sits in a
        /// window that already has a title bar and a close button.
        var showsHeader: Bool

        static let desk = Metrics(
            width: 520, minHeight: 460, padding: 20, sectionSpacing: 22, rowSpacing: 8,
            panelRadius: 12, titleSize: 15, rowFont: 12.5, noteFont: 11.5, rowHit: 0,
            controlRadius: 8, labelManager: .desk, appIconPicker: .desk,
            showsHeader: false
        )
        static let sheet = Metrics(
            width: nil, minHeight: nil, padding: 18, sectionSpacing: 26, rowSpacing: 10,
            panelRadius: 14, titleSize: 17, rowFont: 15, noteFont: 13, rowHit: 44,
            controlRadius: 10, labelManager: .sheet, appIconPicker: .sheet,
            showsHeader: true
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store

    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    @AppStorage(CardDensity.storageKey) private var density = CardDensity.fallback
    @AppStorage(Preferences.cardTickKey) private var showsCardTick = false
    @AppStorage(DefaultDueDate.storageKey) private var defaultDue = DefaultDueDate.fallback
    @AppStorage(AutoArchive.storageKey) private var autoArchive = AutoArchive.fallback
    @AppStorage(WeekMeaning.storageKey) private var weekMeaning = WeekMeaning.fallback
    @AppStorage(Preferences.completionSoundKey) private var playsCompletionSound = true
    @AppStorage(CompletionSound.storageKey) private var completionSound = CompletionSound.fallback
    @AppStorage(Preferences.subtaskSoundKey) private var playsSubtaskSound = true
    @AppStorage(Preferences.interpretsCaptureKey) private var interpretsCapture = true
    @AppStorage(CompletionSound.subtaskStorageKey) private var subtaskSound = CompletionSound.subtaskFallback
    @AppStorage(TrashRetention.storageKey) private var trashRetention = TrashRetention.fallback
    @AppStorage(BackupsKept.storageKey) private var backupsKept = BackupsKept.fallback
    @AppStorage(Preferences.resumeKey) private var resumesLastPlace = false
    @AppStorage(Preferences.inboxAtLaunchKey) private var opensInboxAtLaunch = false
    @AppStorage(Preferences.appIconKey) private var appIconID = AppIcon.defaultID
    @AppStorage(Preferences.appIconFollowsThemeKey) private var appIconFollowsTheme = false
    #if os(macOS)
    @AppStorage(Preferences.menuBarExtraKey) private var showsMenuBarExtra = true
    @State private var launchesAtLogin = LaunchAtLogin.isOn
    #endif
    /// The switch is this device's intent; whether it takes is `store.isSyncing`.
    /// Changing it needs a relaunch, which `syncExplanation` says rather than
    /// pretending the container can be swapped underneath a running store.
    @AppStorage(SyncPreference.storageKey) private var isSyncOn = true

    var metrics: Metrics = .desk

    @State private var isExportingBoard = false
    @State private var isExportingMarkdown = false
    @State private var isImporting = false
    @State private var isManagingLabels = false
    @State private var isPickingAppIcon = false
    @State private var isConfirmingReset = false
    /// Raised by the warning, and the only thing that mutates the board is a
    /// row in it — see `BoardStore.startOver(with:)` for why nothing is thrown
    /// away before then.
    @State private var isPickingStarter = false
    /// Read once, when the list is opened: it is a directory listing, and a
    /// computed property would run it on every render.
    @State private var backups: [BoardBackup] = []
    @State private var isShowingBackups = false
    @State private var pendingRestore: BoardBackup?
    @State private var notice: SettingsNotice?
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    @State private var isBrowsingThemes = false
    #endif
    #if os(iOS)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which subject the strip is showing. iOS only: the desk's `TabView` keeps
    /// its own selection, and keeps it across openings of the window, which a
    /// `@State` on a sheet that is rebuilt every time it is raised cannot.
    /// Starting at `.general` each time is the same choice as putting it first.
    @State private var selection: SettingsTab = .general
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if metrics.showsHeader {
                header.hairline(.bottom, color: palette.ink(0.08))
            }
            subjects
        }
        .frame(width: metrics.width)
        .frame(minHeight: metrics.minHeight)
        .background(palette.windowFill)
        .presentationBackground(palette.windowFill)
        // The app never asks at launch, so the answer can have changed in
        // System Settings since it started.
        .task { await NotificationScheduler.shared.refreshAuthorization() }
        .labelManagerSheet(isPresented: $isManagingLabels, metrics: metrics.labelManager)
        // A sheet on both platforms, where the theme browser is a window on the
        // desk — see ``AppIconPickerView`` for why this one is not.
        .sheet(isPresented: $isPickingAppIcon) {
            AppIconPickerView(metrics: metrics.appIconPicker)
                .environment(\.palette, palette)
                .environment(store)
        }
        // iOS only. The desk opens the browser as a window of its own — see the
        // `themes` scene in `LittleKanbanApp` for why — and a phone has no such
        // thing to open.
        #if os(iOS)
        .sheet(isPresented: $isBrowsingThemes) {
            ThemeBrowserView(metrics: .sheet)
                .environment(\.palette, palette)
                .environment(store)
        }
        #endif
        .modifier(BoardTransfer(
            isExportingBoard: $isExportingBoard,
            isExportingMarkdown: $isExportingMarkdown,
            isImporting: $isImporting,
            today: dayClock.today,
            onImport: importBoard,
            onFailure: { notice = SettingsNotice(title: exportFailedTitle, message: $0) }
        ))
        .alert(
            notice?.title ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
            presenting: notice
        ) { _ in
            Button("OK") { notice = nil }
        } message: { notice in
            Text(notice.message)
        }
        .alert(
            "Delete everything on this board?",
            isPresented: $isConfirmingReset
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) { isPickingStarter = true }
        } message: {
            Text("Every board, card and label goes, and you pick what to start from next. A copy of the board as it stands is kept in the backups folder first, and the change can be undone.")
        }
        .starterPicker(
            isPresented: $isPickingStarter, occasion: .startingOver, palette: palette,
            choose: startOver, cancel: { isPickingStarter = false }
        )
        .alert(
            "Restore this backup?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { backup in
            Button("Cancel", role: .cancel) {}
            Button("Restore") { restore(backup) }
        } message: { backup in
            Text("Everything on the board is replaced by the board as it stood \(Self.stamp(backup)). A copy of the board as it is now is kept first, and ⌘Z takes the restore back.")
        }
    }

    // MARK: The subjects

    #if os(macOS)
    /// The desk: one subject at a time, chosen from the window's toolbar, which
    /// is what a macOS settings window *is*.
    private var subjects: some View {
        TabView {
            ForEach(SettingsTab.allCases) { tab in
                pane(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
            }
        }
    }
    #else
    /// iOS: the same subjects, reached from a strip under the sheet's header
    /// instead of one long scroll through all of them.
    ///
    /// **The strip is at the top, and it is not a `TabView`.** A tab bar on iOS
    /// is at the bottom, and it would land on top of the version row this sheet
    /// already puts in its bottom safe area. A row of chips under the title is
    /// both the thing that fits and the closer likeness to the desk, whose
    /// subjects are also along the top. It kept its sideways scroll and its
    /// fade after the eight subjects became four — four chips fit across a
    /// phone at the system type size and stop fitting a size or two up, and a
    /// strip that can scroll costs nothing on the day it does not need to.
    ///
    /// `pane` is rebuilt on `.id(selection)` so a new subject opens at its own
    /// top rather than at the offset the last one was left at.
    private var subjects: some View {
        VStack(spacing: 0) {
            strip
            pane(selection).id(selection)
        }
    }

    private var strip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(SettingsTab.allCases) { tab in
                        chip(tab)
                    }
                }
                .padding(.horizontal, metrics.padding)
                .padding(.vertical, 8)
                .motionAnimation(.snappy(duration: 0.2), value: selection)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            // A chip cut off by a fade reads as "there is more this way"; one
            // cut off by the sheet's own edge reads as the end of the list —
            // which is what the strip looked like when it held eight and the
            // fifth finished a few points short of the iPad's edge, leaving the
            // last two invisible with nothing to say they were there.
            // `.leading`/`.trailing` are semantic, so unlike `UIRectEdge` in
            // `EdgeSwipe` this mirrors itself.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            // Centring the chip that was chosen is what brings the next one
            // within reach — a phone shows about three at a time — and it is
            // also what keeps the chosen chip on screen at all, since the
            // strip otherwise stays wherever the last flick left it.
            .onChange(of: selection) { _, tab in
                Motion.run(.easeOut(duration: 0.25), reduceMotion: reduceMotion) {
                    proxy.scrollTo(tab.id, anchor: .center)
                }
            }
        }
        .hairline(.bottom, color: palette.ink(0.08))
    }

    /// One subject, as a chip. The whole 44pt is the target — a chip is a word
    /// and a glyph, which is around 20pt of drawn height on its own.
    private func chip(_ tab: SettingsTab) -> some View {
        let isCurrent = tab == selection
        return Button { selection = tab } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(palette.ui(metrics.noteFont, .semibold, relativeTo: .caption))
                Text(tab.title)
                    .font(palette.ui(metrics.rowFont - 1.5, .bold, relativeTo: .subheadline))
                    .lineLimit(1)
            }
            .foregroundStyle(isCurrent ? palette.onAccent : palette.inkText(0.55))
            .padding(.horizontal, 13)
            .frame(minHeight: metrics.rowHit)
            .background {
                Capsule().fill(isCurrent ? palette.accent : palette.card)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.bare)
        .accessibilityIdentifier(tab.chipID)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
    #endif

    /// One subject's worth. Scrolling inside the pane rather than resizing the
    /// window past it: Data grows with what the user has — four groups, and a
    /// backup list under one of them — and a settings window that grows to a
    /// thousand points because somebody has a fortnight of backups is a window
    /// that has stopped being a settings window.
    private func pane(_ tab: SettingsTab) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                content(of: tab)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(metrics.padding)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func content(of tab: SettingsTab) -> some View {
        switch tab {
        case .general: generalSection
        case .board: boardSection
        case .notifications: notificationsSection
        case .data: dataSection
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Settings")
                .font(palette.ui(metrics.titleSize, .bold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Done")
                    .font(palette.ui(metrics.rowFont, .bold, relativeTo: .footnote))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .frame(minHeight: max(metrics.rowHit, 30))
            }
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.06), radius: 8)
            // Escape on a hardware keyboard — the sheet's spelling of the
            // desk's Escape-closes-the-window, which `SettingsWindow` carries.
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, metrics.padding)
        .padding(.vertical, metrics.padding * 0.7)
    }

    // MARK: Sections

    /// What the app looks like and how it comes up.
    ///
    /// The desk's two rows are the whole of what used to be a **System** pane —
    /// a subject with two switches in it, which is a group and not a subject.
    /// They are still the desk's alone, but the `#if` is now around two rows
    /// rather than around a case of `SettingsTab`, so `allCases` is the same
    /// list on both platforms and nothing has to remember to filter it.
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            group(String(localized: "Appearance", comment: "Settings group heading")) {
                // The appearance chooses *which* of the two themes is showing,
                // so it comes first: the row under it names both, and which one
                // you are looking at is this row's answer.
                row {
                    choice(
                        String(localized: "Appearance", comment: "Settings row: light, dark or system"),
                        value: appearance.label,
                        note: String(localized: "Which of the two themes below is showing.",
                                     comment: "Note under the light/dark/system row")
                    ) {
                        ForEach(AppAppearance.allCases) { option in
                            pick(option.label, isCurrent: option == appearance) { appearance = option }
                        }
                    }
                }
                rule
                action(
                    String(localized: "Themes…", comment: "Settings row: opens the theme browser"),
                    note: themeNote
                ) {
                    #if os(macOS)
                    openWindow(id: LittleKanbanApp.themesWindowID)
                    #else
                    isBrowsingThemes = true
                    #endif
                }
                rule
                // Under *Themes…* because the switch on the page it opens defers
                // to the theme, so the two rows are one subject read downwards:
                // which theme, then whether the icon follows it.
                action(
                    String(localized: "App icon…", comment: "Settings row: opens the app icon picker"),
                    note: appIconNote
                ) {
                    isPickingAppIcon = true
                }
            }

            group(String(localized: "At launch", comment: "Settings group heading")) {
                row {
                    Toggle(isOn: $resumesLastPlace) {
                        Text("Reopen the view I was on")
                            .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                    }
                }
                // Desk and iPad only — see ``BoardStore/inboxOpensBesideTheBoard``.
                // A runtime check rather than an `#if`, because the two iOS
                // idioms are one build: the phone hides the row, the iPad in the
                // same binary shows it.
                if BoardStore.inboxOpensBesideTheBoard {
                    rule
                    row {
                        // Written through to the store as well as to the
                        // defaults, the way the login switch reads `SMAppService`
                        // back: the store carries this one for a test's sake and
                        // would otherwise go on answering with what was stored at
                        // launch, so a switch flipped here would do nothing until
                        // the app was quit.
                        Toggle(isOn: Binding(get: { opensInboxAtLaunch }, set: { wanted in
                            opensInboxAtLaunch = wanted
                            store.opensInboxWithTheBoard = wanted
                        })) {
                            Text("Open the Inbox with the board unless it's empty")
                                .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                        }
                    }
                }
            }

            #if os(macOS)
            macSystemGroup
            #endif
        }
    }

    #if os(macOS)
    /// The two things this app asks of the Mac rather than of the board.
    ///
    /// Login registration is read back from `SMAppService` rather than from the
    /// stored key, because System Settings can revoke it and a switch that
    /// reads on while nothing happens at login is worse than no switch at all.
    private var macSystemGroup: some View {
        group(String(localized: "This Mac", comment: "Settings group heading over the desk-only rows")) {
            row {
                Toggle(isOn: Binding(get: { launchesAtLogin }, set: { wanted in
                    LaunchAtLogin.set(wanted)
                    launchesAtLogin = LaunchAtLogin.isOn
                })) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Open at login")
                            .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                        if LaunchAtLogin.needsApproval {
                            Text("Waiting to be allowed in System Settings ▸ General ▸ Login Items.")
                                .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                                .foregroundStyle(palette.inkText(0.45))
                        }
                    }
                }
            }
            rule
            row {
                Toggle(isOn: $showsMenuBarExtra) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Show the menu bar item")
                            .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                        Text("Quick capture from any app, without leaving it.")
                            .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                            .foregroundStyle(palette.inkText(0.45))
                    }
                }
            }
        }
    }
    #endif

    /// How a board behaves — and, at the foot of it, the vocabulary its cards
    /// are tagged from. Labels were a subject of their own holding a single row
    /// that opens a sheet; the labels are the board's, so the row is here.
    private var boardSection: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            group(String(localized: "Cards", comment: "Settings group heading")) {
                row {
                    choice(
                        String(localized: "Order cards by", comment: "Settings row: how a column sorts its cards"),
                        value: store.sortOrder.label,
                        note: store.sortOrder == .manual
                            ? nil
                            : String(localized: "Cards cannot be dragged while another order is deciding where they sit.",
                                     comment: "Settings note explaining why drag is off")
                    ) {
                        ForEach(BoardSortOrder.allCases) { option in
                            pick(option.label, isCurrent: option == store.sortOrder) { store.sortOrder = option }
                        }
                    }
                }
                rule
                row {
                    choice(String(localized: "Card detail", comment: "Settings row: how much a card shows"),
                           value: density.label,
                           note: String(localized: "Compact keeps the title and the due date and drops the rest.",
                                        comment: "Settings note under the card detail row")) {
                        ForEach(CardDensity.allCases) { option in
                            pick(option.label, isCurrent: option == density) { density = option }
                        }
                    }
                }
                rule
                row {
                    Toggle(isOn: $showsCardTick) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Tick cards off from the board")
                                .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                            Text("The circle in a card's leading corner. Turned off, cards close the gutter up; the tick beside the title in the detail panel still finishes one.")
                                .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                                .foregroundStyle(palette.inkText(0.45))
                        }
                    }
                }
                rule
                row {
                    choice(String(localized: "New tasks are due", comment: "Settings row: a new task's due date"),
                           value: defaultDue.label) {
                        ForEach(DefaultDueDate.allCases) { option in
                            // Written to the store as well as to defaults. The
                            // store reads this preference once, at init — see
                            // `BoardStore.defaultDueDate`, which is a stored
                            // property so a parallel test can set it — so
                            // without this line the choice made here did not
                            // reach the next card minted until the app was
                            // relaunched.
                            pick(option.label, isCurrent: option == defaultDue) {
                                defaultDue = option
                                store.defaultDueDate = option
                            }
                        }
                    }
                }
                rule
                row {
                    Toggle(isOn: $interpretsCapture) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Read dates and tags in a typed title")
                                .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                            Text("“Ship the beta next friday !high #bug” becomes a card due Friday, marked High and labelled Bug. Whatever it is about to take is shown under the field first, and any of it can be handed back.")
                                .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                                .foregroundStyle(palette.inkText(0.45))
                        }
                    }
                    // The same reason the row above writes the store: the store
                    // holds its own copy so a test can set it.
                    .onChange(of: interpretsCapture) { _, isOn in store.interpretsCapture = isOn }
                }
                rule
                row {
                    choice(String(localized: "Archive finished cards",
                                  comment: "Settings row: when Done cards are archived"),
                           value: autoArchive.label,
                           note: String(localized: "Done is the one column that only grows.",
                                        comment: "Settings note under the auto-archive row")) {
                        ForEach(AutoArchive.allCases) { option in
                            pick(option.label, isCurrent: option == autoArchive) {
                                autoArchive = option
                                store.sweepDone()
                            }
                        }
                    }
                }
                rule
                row {
                    choice(String(localized: "A week means", comment: "Settings row: what this week means"),
                           value: weekMeaning.label,
                           note: String(localized: "What Due this week counts, and where the week turns over.",
                                        comment: "Settings note under the week row")) {
                        ForEach(WeekMeaning.allCases) { option in
                            pick(option.label, isCurrent: option == weekMeaning) { weekMeaning = option }
                        }
                    }
                }
            }

            // **The two chimes, in the order the work happens in**: a sub-task
            // is ticked on the way to a card being finished, so its pair of
            // rows sits under the card's rather than in a group of its own.
            // Each is a switch and the chime it plays, and the two switches are
            // named for what they answer to — "Play a sound" was unambiguous
            // while there was one sound to play, and is not now.
            group(String(localized: "Completing", comment: "Settings group heading over the completion feedback rows")) {
                row {
                    Toggle(isOn: $playsCompletionSound) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Play a sound when a card is finished")
                                .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                            Text("A short chime when a card reaches Done, however it got there. The haptic tap stays either way, on hardware that has one.")
                                .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                                .foregroundStyle(palette.inkText(0.45))
                        }
                    }
                }
                rule
                row {
                    choice(String(localized: "Sound", comment: "Settings row: which completion chime plays"),
                           value: completionSound.label,
                           note: String(localized: "Picking one plays it.",
                                        comment: "Settings note under the completion sound row")) {
                        ForEach(CompletionSound.allCases) { option in
                            pick(option.label, isCurrent: option == completionSound) {
                                completionSound = option
                                // The audition: hearing the choice is the only
                                // way to make it.
                                CompletionFeedback.shared.preview(option)
                            }
                        }
                    }
                }
                rule
                row {
                    Toggle(isOn: $playsSubtaskSound) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Play a sound when a sub-task is ticked")
                                .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                            Text("The same chimes, chosen separately — a step finished is not the card finished, and the two should not sound alike. Un-ticking one is silent.")
                                .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                                .foregroundStyle(palette.inkText(0.45))
                        }
                    }
                }
                rule
                row {
                    choice(String(localized: "Sub-task sound",
                                  comment: "Settings row: which chime a ticked sub-task plays"),
                           value: subtaskSound.label,
                           note: String(localized: "Picking one plays it.",
                                        comment: "Settings note under the completion sound row")) {
                        ForEach(CompletionSound.allCases) { option in
                            pick(option.label, isCurrent: option == subtaskSound) {
                                subtaskSound = option
                                CompletionFeedback.shared.preview(option)
                            }
                        }
                    }
                }
            }

            group(String(localized: "Labels", comment: "Settings group heading")) {
                action(
                    String(localized: "Manage labels", comment: "Settings row that opens the label manager"),
                    note: String(localized: "Rename, recolour and delete the board's labels.",
                                 comment: "Settings note under the label manager row"),
                    trailing: "\(store.labels.count)"
                ) {
                    isManagingLabels = true
                }
            }
        }
    }

    private var notificationsSection: some View {
        @Bindable var scheduler = NotificationScheduler.shared

        return panel {
            row {
                Toggle(isOn: $scheduler.isEnabled) {
                    Text("Remind me on the due date")
                        .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                }
            }
            rule
            row {
                DatePicker(selection: $scheduler.reminderTime, displayedComponents: .hourAndMinute) {
                    Text("At")
                        .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                }
                .disabled(!scheduler.isEnabled)
                .opacity(scheduler.isEnabled ? 1 : 0.4)
            }
            rule
            row {
                Toggle(isOn: $scheduler.remindsTheDayBefore) {
                    Text("Also remind me the day before")
                        .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                }
                .disabled(!scheduler.isEnabled)
                .opacity(scheduler.isEnabled ? 1 : 0.4)
            }
            rule
            row {
                Toggle(isOn: $scheduler.nagsWhileOverdue) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tell me daily while anything is overdue")
                            .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                        Text("One notice with a count, not one per card.")
                            .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                            .foregroundStyle(palette.inkText(0.45))
                    }
                }
                .disabled(!scheduler.isEnabled)
                .opacity(scheduler.isEnabled ? 1 : 0.4)
            }
            if let explanation = scheduler.explanation {
                rule
                row {
                    Text(explanation)
                        .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                        .foregroundStyle(palette.inkText(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // A denial is final as far as the app is concerned — asking again
            // returns `false` without showing the user anything — so the only
            // useful offer at that point is the trip to System Settings.
            if scheduler.needsSystemSettings {
                rule
                action(String(localized: "Open System Settings",
                              comment: "Settings row that opens the system's notification preferences")) {
                    scheduler.openSystemSettings()
                }
            } else if scheduler.authorization == .notDetermined {
                rule
                action(String(localized: "Allow Notifications",
                              comment: "Settings row that asks for notification permission")) {
                    Task { await scheduler.requestAuthorization() }
                }
            }
        }
    }

    /// Where the board lives and every way of getting it back. Sync was a
    /// subject of its own holding one switch and a paragraph explaining it;
    /// "is this board on my other devices" is the same question as "where is
    /// this board kept", so it leads this one.
    private var dataSection: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            group(String(localized: "iCloud", comment: "Settings group heading")) {
                row {
                    Toggle(isOn: $isSyncOn) {
                        Text("Keep this board on my other devices")
                            .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                    }
                    // A build with no iCloud entitlement cannot sync whatever
                    // this says, and a switch that flips with nothing behind it
                    // is worse than one that admits it. The note underneath
                    // says why.
                    .disabled(!SyncPreference.isAvailable)
                }
                rule
                row {
                    Text(syncExplanation)
                        .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                        .foregroundStyle(palette.inkText(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            group(String(localized: "Kept copies", comment: "Settings group heading")) {
                row {
                    choice(String(localized: "The Trash keeps things for",
                                  comment: "Settings row: how long deleted items are kept"),
                           value: trashRetention.label) {
                        ForEach(TrashRetention.allCases) { option in
                            pick(option.label, isCurrent: option == trashRetention) {
                                trashRetention = option
                                store.sweepTrash()
                            }
                        }
                    }
                }
                rule
                row {
                    choice(String(localized: "Backups to keep",
                                  comment: "Settings row: how many board backups are retained"),
                           value: backupsKept.label,
                           note: String(localized: "Each one is a whole copy of the board.",
                                        comment: "Settings note under the backup count row")) {
                        ForEach(BackupsKept.allCases) { option in
                            pick(option.label, isCurrent: option == backupsKept) { backupsKept = option }
                        }
                    }
                }
                rule
                backupsRow
                if isShowingBackups { backupList }
            }

            group(String(localized: "The board file", comment: "Settings group heading")) {
                transferRows
                rule
                boardFileRow
            }

            group(String(localized: "Starting over", comment: "Settings group heading")) {
                action(String(localized: "Delete everything…", comment: "Settings row that throws the board away"),
                       note: String(localized: "Throws away every board, card and label, then asks what to start from again.",
                                    comment: "Settings note under the delete-everything row"),
                       isDestructive: true) {
                    isConfirmingReset = true
                }
            }
        }
    }

    /// Says which of the four states the app is actually in, because "on" and
    /// "working" are not the same thing here: the switch is this device's
    /// intent, iCloud can decline it, and a build that was never signed for the
    /// container cannot even ask.
    private var syncExplanation: String {
        guard SyncPreference.isAvailable else {
            return String(
                localized: "This copy of Little Kanban was not built for iCloud, so your board stays on this device. Everything still saves locally, and you can export it at any time.",
                comment: "Settings note when the build carries no iCloud entitlement"
            )
        }
        guard isSyncOn else {
            return String(
                localized: "Your board stays on this device. Everything still saves locally, and you can export it at any time.",
                comment: "Settings note when sync is switched off"
            )
        }
        guard store.isSyncing else {
            return String(
                localized: "Not syncing right now — sign in to iCloud and relaunch. Your board is saved on this device either way.",
                comment: "Settings note when sync is on but iCloud is unavailable"
            )
        }
        // A standing condition, not an error to report once — see
        // `BoardStore.isSyncReadBlocked` for what is being withheld and why.
        if store.isSyncReadBlocked {
            return String(
                localized: "iCloud's copy of the board could not be read when the app opened, so changes are staying on this device for now. Reading is retried with every save — Sync Now retries it too.",
                comment: "Settings note when the record store could not be read and pushes are withheld"
            )
        }
        guard let when = store.lastSyncedAt else {
            return String(
                localized: "Changes go to iCloud as you make them, and arrive on your other devices signed in to the same account.",
                comment: "Settings note when sync is on and nothing has arrived yet"
            )
        }
        return String(
            localized: "Last change from another device: \(when.formatted(.relative(presentation: .numeric))).",
            comment: "Settings note naming when another device's change last arrived"
        )
    }

    @ViewBuilder
    private var transferRows: some View {
        action(String(localized: "Export board…", comment: "Settings row that writes the board out as a file"),
               note: String(localized: "One .littlekanban document holding every board, task and label.",
                            comment: "Settings note under the board export row")) {
            isExportingBoard = true
        }
        rule
        action(String(localized: "Export as Markdown…", comment: "Settings row that writes the board out as text"),
               note: String(localized: "Something to paste into a note or an issue.",
                            comment: "Settings note under the Markdown export row")) {
            isExportingMarkdown = true
        }
        rule
        action(String(localized: "Import…", comment: "Settings row that reads a board in from a file"),
               note: String(localized: "Merged in, never written over: a task already here is left alone, and one arriving under an id this board already uses is kept alongside it.",
                            comment: "Settings note under the import row")) {
            isImporting = true
        }
    }

    /// Where the board lives. The desk can open the folder; the phone has no
    /// Finder to open it in, so it shows the path and nothing else.
    @ViewBuilder
    private var boardFileRow: some View {
        let path = store.boardFileURL?.path(percentEncoded: false)
            ?? String(localized: "Not saved to a file", comment: "Settings value for an in-memory board")
        #if os(macOS)
        action(String(localized: "Reveal board file", comment: "Settings row that opens the board's folder in Finder"),
               note: path) {
            guard let url = store.boardFileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        #else
        row {
            VStack(alignment: .leading, spacing: 3) {
                Text("Board file", comment: "Settings row naming where the board is stored")
                    .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink)
                Text(path)
                    .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.45))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        #endif
    }

    private var backupsRow: some View {
        action(
            String(localized: "Restore from a backup", comment: "Settings row that lists the rolling backups"),
            note: String(localized: "The board is copied here every 15 minutes as you work; the newest are kept, as many as \"Backups to keep\" says.",
                         comment: "Settings note under the restore row"),
            trailing: isShowingBackups ? nil : "\(backups.count)"
        ) {
            backups = store.availableBackups()
            isShowingBackups.toggle()
        }
        .onAppear { backups = store.availableBackups() }
    }

    @ViewBuilder
    private var backupList: some View {
        if backups.isEmpty {
            row {
                Text("No backups yet. One is taken the first time the board is saved after fifteen minutes' work.")
                    .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ForEach(backups) { backup in
                rule
                Button { pendingRestore = backup } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .imageScale(.small)
                            .foregroundStyle(palette.inkText(0.4))
                            .accessibilityHidden(true)
                        Text(Self.stamp(backup))
                            .font(palette.ui(metrics.rowFont, .medium, relativeTo: .subheadline))
                            .foregroundStyle(palette.ink(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Restore")
                            .font(palette.ui(metrics.noteFont, .bold, relativeTo: .caption))
                            .foregroundStyle(palette.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(minHeight: metrics.rowHit)
                    .hoverBackground(palette.ink(0.05), radius: metrics.controlRadius)
                }
                .buttonStyle(.bare)
            }
        }
    }

    // MARK: Building blocks

    /// A panel of rows under a heading — what a pane holding more than one of
    /// them is built from.
    ///
    /// **The rule is: a heading only where there is something to separate.** A
    /// pane with a single panel in it gets none, because the desk's toolbar has
    /// just said the word and the window title says it again above that, and the
    /// sheet's chosen chip is sitting directly over the panel with the same word
    /// in it — three copies of "Notifications" down the left of a pane is how a
    /// settings surface looks when it was a scroll last week. A pane holding
    /// four groups is the other case: with four subjects where there were eight,
    /// a pane is a page rather than a list, and a page without headings is one
    /// long strip of switches to read from the top every time.
    private func group<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .sectionLabelStyle(size: metrics.noteFont - 1.5, opacity: Palette.readableInk)
                .padding(.horizontal, 2)
                .accessibilityAddTraits(.isHeader)
            panel { content() }
        }
    }

    /// A panel of rows, and no heading over it — see ``group(_:content:)`` for
    /// when each is right.
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            VStack(spacing: 0) { content() }
                .background {
                    RoundedRectangle(cornerRadius: metrics.panelRadius)
                        .fill(palette.card)
                        .shadow(color: palette.shadow(0.05), radius: 6, y: 2)
                }
        }
    }

    /// One row of a panel.
    ///
    /// **Full width, leading-aligned.** A `Toggle` and a `DatePicker` are as
    /// wide as their own label and no wider, so left to themselves they *centre*
    /// in a panel whose width some other row decided — which nothing shows while
    /// a pane is one long list of `choice` rows holding the panel open, and
    /// which is glaring the moment a group holds two switches and nothing else.
    /// Measured: **At launch**'s two sat in the middle of the panel with a
    /// finger's width of nothing either side of them.
    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: metrics.rowHit)
    }

    private var rule: some View {
        Rectangle().fill(palette.ink(0.06)).frame(height: 1)
    }

    /// A row that does something when pressed.
    private func action(
        _ title: String, note: String? = nil, trailing: String? = nil,
        isDestructive: Bool = false, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(isDestructive ? palette.accent : palette.ink)
                        .multilineTextAlignment(.leading)
                    if let note {
                        Text(note)
                            .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                            .foregroundStyle(palette.inkText(0.45))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing)
                        .font(palette.ui(metrics.noteFont, .bold, relativeTo: .caption))
                        .foregroundStyle(palette.inkText(0.4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: metrics.rowHit)
            .hoverBackground(palette.ink(0.05), radius: metrics.controlRadius)
        }
        .buttonStyle(.bare)
    }

    /// A row whose value is picked from a menu — the same vocabulary
    /// `PriorityPicker` uses, for the same reason: three segments do not fit
    /// beside a label in a 460pt pane.
    private func choice<Content: View>(
        _ title: String, value: String, note: String? = nil,
        @ViewBuilder options: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink)
                if let note {
                    Text(note)
                        .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                        .foregroundStyle(palette.inkText(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                options()
            } label: {
                HStack(spacing: 6) {
                    Text(value)
                        .font(palette.ui(metrics.rowFont, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.ink)
                    Image(systemName: "chevron.down")
                        .font(palette.ui(metrics.rowFont - 4, .bold, relativeTo: .caption2))
                        .foregroundStyle(palette.inkText(0.35))
                }
                .frame(minHeight: metrics.rowHit)
                .contentShape(.rect)
            }
            .modifier(BorderlessMenu())
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(title)
            .accessibilityValue(value)
        }
    }

    /// One row of a `choice` menu. A menu row cannot tint anything, so the tick
    /// carries the state — as every other menu in this app does.
    private func pick(_ title: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isCurrent {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    // MARK: Actions

    /// Both slots named at once, because both are set from the one row and only
    /// one of them is on screen to be seen.
    private var themeNote: String {
        String(
            localized: "\(store.theme(for: .light).name) in light, \(store.theme(for: .dark).name) in dark.",
            comment: "Settings note naming the theme in each of the two slots"
        )
    }

    /// The icon as it resolves, so the row says what the app is actually
    /// wearing rather than which of the ten was last pressed — with the switch
    /// on, that is a theme's name and not a gradient's.
    private var appIconNote: String {
        let resolved = AppIcon.resolve(
            AppIconSelection(gradientID: appIconID, followsTheme: appIconFollowsTheme),
            themes: store.themes,
            appearance: palette.theme.appearance
        )
        // The bare name when it is one of the ten: a `String(localized:)` whose
        // whole content is an interpolation and a full stop is a translation
        // unit that says nothing to a translator.
        guard appIconFollowsTheme else { return resolved.name }
        return String(localized: "\(resolved.name), following the theme.",
                      comment: "Settings note naming the theme-matched app icon")
    }

    private var exportFailedTitle: String {
        String(localized: "That export could not be written.",
               comment: "Alert title when saving an exported file failed")
    }

    private func importBoard(_ url: URL) {
        notice = .importing(url, into: store)
    }

    /// The one place the board is actually replaced, and the picker closes and
    /// takes Settings with it — what somebody wants to look at after starting
    /// over is the board they just chose, not the screen they left.
    private func startOver(with template: BoardTemplate) {
        store.startOver(with: template.snapshot)
        isPickingStarter = false
        dismiss()
    }

    private func restore(_ backup: BoardBackup) {
        do {
            try store.restore(fromBackup: backup.url)
        } catch {
            notice = SettingsNotice(
                title: String(localized: "That backup could not be restored.",
                              comment: "Alert title when a backup could not be read"),
                message: [error.localizedDescription,
                          String(localized: "Your board has not been changed.",
                                 comment: "Reassurance after a failed import")]
                    .joined(separator: "\n\n")
            )
        }
        backups = store.availableBackups()
    }

    /// A backup's moment, as both "2 hr ago" and the date it was taken — the
    /// first is what tells one apart from the next, the second is what tells it
    /// apart from last week's.
    private static func stamp(_ backup: BoardBackup) -> String {
        guard let takenAt = backup.takenAt else { return backup.url.lastPathComponent }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .abbreviated
        return "\(formatter.localizedString(for: takenAt, relativeTo: .now)) · \(takenAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
