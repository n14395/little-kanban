import SwiftUI

/// File ▸ Restore from a Backup…, which is the rolling copies the app keeps
/// beside the board file, offered where a menu can reach them.
///
/// **A sheet rather than a submenu of dates**, which is the shape it looks like
/// it wants. The list is a *directory listing*, and a `Commands` body is
/// re-evaluated whenever anything it reads changes — which on this app is every
/// keystroke typed into a card. `SettingsView` reads the same list once when its
/// row is opened and says so where it does it; a submenu would read it a hundred
/// times a minute for a menu nobody had opened. The sheet reads it once, when it
/// appears.
///
/// **The confirmation is the point of the ellipsis.** A restore replaces
/// everything on the board, so the item promises a question and this asks it —
/// the same question, in the same words, that the settings row asks, because
/// they do the same thing to the same file. `BoardStore.restore(fromBackup:)`
/// keeps a copy of the board as it stands before it disturbs anything, and files
/// the whole restore as one ⌘Z.
struct BackupSheet: View {
    struct Metrics {
        var width: CGFloat?
        var titleSize: CGFloat
        var rowFont: CGFloat
        var noteFont: CGFloat
        /// The floor under a row. A pointer needs none; a finger needs 44.
        var rowHit: CGFloat
        var rowRadius: CGFloat
        var padding: CGFloat

        static let desk = Metrics(
            width: 360, titleSize: 14, rowFont: 12.5, noteFont: 11.5,
            rowHit: 0, rowRadius: 8, padding: 18
        )
        static let sheet = Metrics(
            width: nil, titleSize: 17, rowFont: 15, noteFont: 13,
            rowHit: 44, rowRadius: 10, padding: 20
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store

    var metrics: Metrics = .desk

    /// Read once, when the sheet appears — see the note above this type. A
    /// computed property would run the listing on every render of the list it
    /// is drawing.
    @State private var backups: [BoardBackup] = []
    /// The one being asked about, and the reason a failed restore has to say
    /// something rather than close on a board that has not changed.
    @State private var pending: BoardBackup?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore from a backup", comment: "Title of the sheet that lists the rolling backups")
                .font(palette.ui(metrics.titleSize, .extraBold, relativeTo: .headline))
                .foregroundStyle(palette.ink)

            Text("The board is copied here every 15 minutes as you work. Restoring replaces everything on the board — a copy of it as it stands is kept first, and ⌘Z takes the restore back.")
                .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                .foregroundStyle(palette.inkText(0.45))
                .fixedSize(horizontal: false, vertical: true)

            if backups.isEmpty {
                Text("No backups yet. One is taken the first time the board is saved after fifteen minutes' work.")
                    .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(backups) { backup in
                            row(backup)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Text("Close", comment: "Button that closes the backup sheet without restoring anything")
                        .font(palette.ui(metrics.rowFont, .bold, relativeTo: .footnote))
                        .foregroundStyle(palette.inkText(0.55))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                }
                .bareButton()
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(metrics.padding)
        .frame(width: metrics.width)
        .background(palette.windowFill)
        .presentationBackground(palette.windowFill)
        .onAppear { backups = store.availableBackups() }
        .alert(
            "Restore this backup?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { backup in
            Button("Cancel", role: .cancel) {}
            Button("Restore") { restore(backup) }
        } message: { backup in
            Text("Everything on the board is replaced by the board as it stood \(Self.stamp(backup)). A copy of the board as it is now is kept first, and ⌘Z takes the restore back.")
        }
        .alert(
            String(localized: "That backup could not be restored.",
                   comment: "Alert title when a backup could not be read"),
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private func row(_ backup: BoardBackup) -> some View {
        Button { pending = backup } label: {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(minHeight: metrics.rowHit)
            .hoverBackground(palette.ink(0.05), radius: metrics.rowRadius)
        }
        .bareButton()
    }

    /// The restore itself. A failure leaves the board exactly as it was — see
    /// `BoardStore.restore(fromBackup:)`, which reads the file before it
    /// disturbs anything — so the sheet stays open to say so.
    private func restore(_ backup: BoardBackup) {
        do {
            try store.restore(fromBackup: backup.url)
            dismiss()
        } catch {
            failure = [error.localizedDescription,
                       String(localized: "Your board has not been changed.",
                              comment: "Reassurance after a failed import")]
                .joined(separator: "\n\n")
        }
    }

    /// How long ago, and when — the settings row's own wording, because the two
    /// lists are the same list.
    private static func stamp(_ backup: BoardBackup) -> String {
        guard let takenAt = backup.takenAt else { return backup.url.lastPathComponent }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .abbreviated
        return "\(formatter.localizedString(for: takenAt, relativeTo: .now)) · \(takenAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
