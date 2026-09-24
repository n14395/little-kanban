// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The three things the menu bar asks for that have nowhere of their own to
/// appear.
///
/// A menu item is outside every view tree: it cannot present a sheet, and the
/// view it would borrow one from — a column header, the trash popover, a
/// settings pane — may not be on screen at all, which is exactly when the menu
/// item is most useful. So the item raises a flag on ``AppWindowState`` and the
/// window's root presents it, which is the bargain `isPickingDueDate` and
/// `isManagingLabels` already make beside these.
///
/// **One modifier rather than a copy in each root**, unlike those two. Each of
/// these carries *words* — a question about throwing thirty days of second
/// chances away, and the reason a column would not go — and two copies of a
/// question is how the desk and the iPad come to ask it differently. The sheet's
/// metrics are the only thing that differs between the platforms, so that is the
/// only thing passed in.
struct MenuPresentations: ViewModifier {
    @Environment(BoardStore.self) private var store

    let window: AppWindowState
    let backupMetrics: BackupSheet.Metrics

    func body(content: Content) -> some View {
        @Bindable var window = window

        return content
            // File ▸ Restore from a Backup…
            .sheet(isPresented: $window.isRestoringBackup) {
                BackupSheet(metrics: backupMetrics)
            }
            // Edit ▸ Empty Trash…. The same question the trash popover's own
            // button asks, in the same words, because it is the same act — and
            // the popover is not open when the menu item is used.
            .alert("Empty the trash?", isPresented: $window.isConfirmingEmptyTrash) {
                Button("Cancel", role: .cancel) {}
                Button("Empty Trash", role: .destructive) { store.emptyTrash() }
            } message: {
                Text("All \(store.trashCount) items go for good, now rather than when their thirty days are up. ⌘Z takes them back, and nothing else does.")
            }
            // Column ▸ Trash Column, refused. `trashColumn` changed nothing and
            // handed back the reason; a refusal nobody can read is a menu item
            // that appears to do nothing.
            .alert(
                window.columnRefusal?.errorDescription ?? "",
                isPresented: Binding(
                    get: { window.columnRefusal != nil },
                    set: { if !$0 { window.columnRefusal = nil } }
                ),
                presenting: window.columnRefusal
            ) { _ in
                Button("OK", role: .cancel) { window.columnRefusal = nil }
            } message: { refusal in
                if let suggestion = refusal.recoverySuggestion { Text(suggestion) }
            }
    }
}

extension View {
    /// What the menu bar raises on this window — see ``MenuPresentations``.
    func menuPresentations(
        window: AppWindowState, backups: BackupSheet.Metrics
    ) -> some View {
        modifier(MenuPresentations(window: window, backupMetrics: backups))
    }
}
