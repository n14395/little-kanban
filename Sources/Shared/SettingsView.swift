import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// Light, dark, or whatever the system says.
///
/// This is the spec's `state.dark`, the one state field deliberately dropped
/// during the port because the design only ever followed the system appearance.
/// It comes back as a *preference*, which is why it is in `@AppStorage` and not
/// in `BoardSnapshot`: it belongs to this machine and this person, not to the
/// board — copy the board to another Mac and the override should not travel
/// with it. See **Settings** in the README for why the accent, which *is* in the
/// snapshot, was left there rather than moved half-way.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    static let storageKey = "SimpleKanbanAppearance"

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
}

/// Everything global, in one place: the accent and the appearance, how the
/// board orders its cards, the label vocabulary, and the board file itself.
///
/// One view for both platforms — the macOS `Settings { }` scene hosts it at
/// `.desk` and the iOS sheet at `.sheet`, which is the difference between a
/// pane inside a window that already has a title bar and a sheet that has to
/// draw its own header and 44pt rows.
///
/// Notifications sit under **Board** and bind straight to
/// ``NotificationScheduler/shared`` rather than to `@AppStorage`: the scheduler
/// has to *act* on a change — moving the time of day moves every pending
/// request — so it owns the values and writes them to `UserDefaults` itself.
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
        var accent: AccentPicker.Metrics
        var labelManager: LabelManagerView.Metrics
        /// Whether the surface draws its own header. The desk's pane sits in a
        /// window that already has a title bar and a close button.
        var showsHeader: Bool

        static let desk = Metrics(
            width: 460, minHeight: 520, padding: 20, sectionSpacing: 22, rowSpacing: 8,
            panelRadius: 12, titleSize: 15, rowFont: 12.5, noteFont: 11.5, rowHit: 0,
            controlRadius: 8, accent: .desk, labelManager: .desk, showsHeader: false
        )
        static let sheet = Metrics(
            width: nil, minHeight: nil, padding: 18, sectionSpacing: 26, rowSpacing: 10,
            panelRadius: 14, titleSize: 17, rowFont: 15, noteFont: 13, rowHit: 44,
            controlRadius: 10, accent: .drawer, labelManager: .sheet, showsHeader: true
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store

    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    /// The switch is this device's intent; whether it takes is `store.isSyncing`.
    /// Changing it needs a relaunch, which `syncExplanation` says rather than
    /// pretending the container can be swapped underneath a running store.
    @AppStorage(SyncPreference.storageKey) private var isSyncOn = true

    var metrics: Metrics = .desk

    @State private var isExportingBoard = false
    @State private var isExportingMarkdown = false
    @State private var isImporting = false
    @State private var isManagingLabels = false
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if metrics.showsHeader {
                header.hairline(.bottom, color: palette.ink(0.08))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    appearanceSection
                    boardSection
                    notificationsSection
                    syncSection
                    labelsSection
                    dataSection
                }
                .padding(metrics.padding)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: metrics.width)
        .frame(minHeight: metrics.minHeight)
        .background(palette.sheet)
        .presentationBackground(palette.sheet)
        // The app never asks at launch, so the answer can have changed in
        // System Settings since it started.
        .task { await NotificationScheduler.shared.refreshAuthorization() }
        .labelManagerSheet(isPresented: $isManagingLabels, metrics: metrics.labelManager)
        .modifier(BoardTransfer(
            isExportingBoard: $isExportingBoard,
            isExportingMarkdown: $isExportingMarkdown,
            isImporting: $isImporting,
            snapshot: store.exportedSnapshot,
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

    private var header: some View {
        HStack(spacing: 8) {
            Text("Settings")
                .font(SimpleKanbanFont.ui(metrics.titleSize, .bold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Done")
                    .font(SimpleKanbanFont.ui(metrics.rowFont, .bold, relativeTo: .footnote))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .frame(minHeight: max(metrics.rowHit, 30))
            }
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.06), radius: 8)
        }
        .padding(.horizontal, metrics.padding)
        .padding(.vertical, metrics.padding * 0.7)
    }

    // MARK: Sections

    private var appearanceSection: some View {
        section(String(localized: "Appearance", comment: "Settings section heading")) {
            row {
                AccentPicker(metrics: metrics.accent)
            }
            rule
            row {
                choice(
                    String(localized: "Theme", comment: "Settings row: light, dark or system"),
                    value: appearance.label
                ) {
                    ForEach(AppAppearance.allCases) { option in
                        pick(option.label, isCurrent: option == appearance) { appearance = option }
                    }
                }
            }
        }
    }

    private var boardSection: some View {
        section(String(localized: "Board", comment: "Settings section heading")) {
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
        }
    }

    private var notificationsSection: some View {
        @Bindable var scheduler = NotificationScheduler.shared

        return section(String(localized: "Notifications", comment: "Settings section heading")) {
            row {
                Toggle(isOn: $scheduler.isEnabled) {
                    Text("Remind me on the due date")
                        .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                }
            }
            rule
            row {
                DatePicker(selection: $scheduler.reminderTime, displayedComponents: .hourAndMinute) {
                    Text("At")
                        .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                }
                .disabled(!scheduler.isEnabled)
                .opacity(scheduler.isEnabled ? 1 : 0.4)
            }
            if let explanation = scheduler.explanation {
                rule
                row {
                    Text(explanation)
                        .font(SimpleKanbanFont.ui(metrics.noteFont, .medium, relativeTo: .caption))
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

    private var syncSection: some View {
        section(String(localized: "Sync", comment: "Settings section heading")) {
            row {
                Toggle(isOn: $isSyncOn) {
                    Text("Keep this board on my other devices")
                        .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                }
                // A build with no iCloud entitlement cannot sync whatever this
                // says, and a switch that flips with nothing behind it is worse
                // than one that admits it. The note underneath says why.
                .disabled(!SyncPreference.isAvailable)
            }
            rule
            row {
                Text(syncExplanation)
                    .font(SimpleKanbanFont.ui(metrics.noteFont, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                localized: "This copy of Simple Kanban was not built for iCloud, so your board stays on this device. Everything still saves locally, and you can export it at any time.",
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

    private var labelsSection: some View {
        section(String(localized: "Labels", comment: "Settings section heading")) {
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

    private var dataSection: some View {
        section(String(localized: "Data", comment: "Settings section heading")) {
            transferRows
            rule
            boardFileRow
            rule
            backupsRow
            if isShowingBackups { backupList }
            rule
            action(String(localized: "Delete everything…", comment: "Settings row that throws the board away"),
                   note: String(localized: "Throws away every board, card and label, then asks what to start from again.",
                                comment: "Settings note under the delete-everything row"),
                   isDestructive: true) {
                isConfirmingReset = true
            }
        }
    }

    @ViewBuilder
    private var transferRows: some View {
        action(String(localized: "Export board…", comment: "Settings row that writes the board out as a file"),
               note: String(localized: "One .simplekanban document holding every board, task and label.",
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
                    .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink)
                Text(path)
                    .font(SimpleKanbanFont.ui(metrics.noteFont, .medium, relativeTo: .caption))
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
            note: String(localized: "The board is copied here every 15 minutes as you work; the ten newest are kept.",
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
                    .font(SimpleKanbanFont.ui(metrics.noteFont, .medium, relativeTo: .caption))
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
                            .font(SimpleKanbanFont.ui(metrics.rowFont, .medium, relativeTo: .subheadline))
                            .foregroundStyle(palette.ink(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Restore")
                            .font(SimpleKanbanFont.ui(metrics.noteFont, .bold, relativeTo: .caption))
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

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            Text(title).sectionLabelStyle(opacity: Palette.readableInk)
            VStack(spacing: 0) { content() }
                .background {
                    RoundedRectangle(cornerRadius: metrics.panelRadius)
                        .fill(palette.card)
                        .shadow(color: palette.shadow(0.05), radius: 6, y: 2)
                }
        }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
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
                        .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(isDestructive ? palette.accent : palette.ink)
                        .multilineTextAlignment(.leading)
                    if let note {
                        Text(note)
                            .font(SimpleKanbanFont.ui(metrics.noteFont, .medium, relativeTo: .caption))
                            .foregroundStyle(palette.inkText(0.45))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing)
                        .font(SimpleKanbanFont.ui(metrics.noteFont, .bold, relativeTo: .caption))
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
                    .font(SimpleKanbanFont.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink)
                if let note {
                    Text(note)
                        .font(SimpleKanbanFont.ui(metrics.noteFont, .medium, relativeTo: .caption))
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
                        .font(SimpleKanbanFont.ui(metrics.rowFont, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.ink)
                    Image(systemName: "chevron.down")
                        .font(SimpleKanbanFont.ui(metrics.rowFont - 4, .bold, relativeTo: .caption2))
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
