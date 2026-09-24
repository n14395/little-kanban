// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The Trash: what has been thrown away, how long is left on it, and the two
/// things that can still be done about it.
///
/// **A surface of its own, not a tab of Settings.** It was one, and it was the
/// wrong shelf: everything else in there is a preference about how the app
/// behaves, and this is the user's own work sitting out a thirty-day countdown.
/// A preference can wait; a card thrown away on Tuesday cannot wait past the
/// thirtieth day. So it hangs off a **Trash** row in the source list on macOS
/// and iPad, under Views and below the Archive — a popover beside the row, which
/// is where the list it is about already is — and off the board menu on the
/// phone, which is that surface's drawer for everything with no other home. See ``TrashedItem`` for what is
/// kept and why the three kinds are not the same shape.
///
/// **Restore is the ordinary button and Delete is the guarded one**, which is
/// the reverse of the rest of the app. Everywhere else a delete happens and ⌘Z
/// is the safety net; here there is nothing behind it, and "Delete" in a window
/// whose whole subject is second chances is the one press that has to mean it.
/// So Delete asks. The app's only other confirmations are the two in front of
/// throwing away a whole column or a whole board — the acts that take somebody
/// else's cards with them.
///
/// **A board's row is the board and everything that was on it.** Restoring one
/// brings back its columns and its tasks, in the places they were; deleting one
/// from here takes the lot. The row says how many, because Restore and Delete
/// are both promises about them — see ``subtitle(_:)``.
struct TrashView: View {
    struct Metrics {
        var rowFont: CGFloat
        var noteFont: CGFloat
        var rowHit: CGFloat
        var buttonHit: CGFloat
        var rowRadius: CGFloat
        var glyph: CGFloat
        var spacing: CGFloat

        static let desk = Metrics(
            rowFont: 12.5, noteFont: 11.5, rowHit: 0, buttonHit: 0,
            rowRadius: 8, glyph: 15, spacing: 10
        )
        static let sheet = Metrics(
            rowFont: 15, noteFont: 13, rowHit: 44, buttonHit: 44,
            rowRadius: 10, glyph: 18, spacing: 12
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var metrics: Metrics = .desk

    /// Which row's Delete is being confirmed. The item rather than a flag, so
    /// the warning can name what it is about to destroy — "Delete this?" over a
    /// list of seven is a question the user cannot answer.
    @State private var confirmingDelete: TrashedItem?
    @State private var isConfirmingEmpty = false
    /// A restore that could not be honoured. Carried as the refusal itself so
    /// the alert can say both halves — what stopped it, and the way past.
    @State private var refusal: TrashRefusal?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            if store.trashedItems.isEmpty {
                empty
            } else {
                list
                emptyTrashButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The one write the surface makes on its own: what the thirty days have
        // run out on goes when the user comes to look, so the list they are
        // reading and the file underneath it agree. See `BoardStore.sweepTrash`.
        .onAppear { store.sweepTrash() }
        .alert(
            "Delete this for good?",
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            presenting: confirmingDelete
        ) { item in
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
            Button("Delete", role: .destructive) {
                store.deleteFromTrash(item.id)
                confirmingDelete = nil
            }
        } message: { item in
            Text("\(item.name) goes for good, now rather than in \(item.daysLeft()) days. ⌘Z takes it back, and nothing else does.")
        }
        .alert("Empty the trash?", isPresented: $isConfirmingEmpty) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Trash", role: .destructive) { store.emptyTrash() }
        } message: {
            Text("All \(store.trashCount) items go for good, now rather than when their thirty days are up. ⌘Z takes them back, and nothing else does.")
        }
        .alert(
            refusal?.errorDescription ?? "",
            isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } }),
            presenting: refusal
        ) { _ in
            Button("OK") { refusal = nil }
        } message: { refusal in
            if let suggestion = refusal.recoverySuggestion { Text(suggestion) }
        }
    }

    // MARK: The list

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.trashedItems.enumerated()), id: \.element.id) { index, item in
                if index > 0 { rule }
                row(item)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: metrics.rowRadius + 4)
                .fill(palette.card)
                .shadow(color: palette.shadow(0.05), radius: 6, y: 2)
        }
    }

    private func row(_ item: TrashedItem) -> some View {
        HStack(spacing: metrics.spacing) {
            Image(systemName: item.kind.symbol)
                .imageScale(.small)
                .foregroundStyle(palette.inkText(0.45))
                .frame(width: metrics.glyph)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(palette.ui(metrics.rowFont, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle(item))
                    .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.45))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            rowButton(String(localized: "Restore", comment: "Trash row button that puts a thrown-away thing back")) {
                refusal = store.restoreFromTrash(item.id)
            }
            rowButton(
                String(localized: "Delete", comment: "Trash row button that throws something away for good"),
                isDestructive: true
            ) {
                confirmingDelete = item
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: metrics.rowHit)
        // One element per row, with the two buttons put back as actions: a row
        // published as four siblings makes a reader swipe four times to pass
        // something they are not interested in, and the name — the one part
        // that says which row this is — is only the second of the four.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(subtitle(item))
        .accessibilityActions {
            Button(String(localized: "Restore", comment: "Trash row button that puts a thrown-away thing back")) {
                refusal = store.restoreFromTrash(item.id)
            }
            Button(String(localized: "Delete", comment: "Trash row button that throws something away for good")) {
                confirmingDelete = item
            }
        }
    }

    /// What kind of thing it was, and how long is left. Both halves matter: the
    /// kind because a board and a card can carry the same name, and the countdown
    /// because it is the promise the trash makes.
    ///
    /// A board also says **how many tasks came with it**, because that is what
    /// its Restore is offering back and what its Delete would take for good. A
    /// row reading "Board · 30 days left" beside one reading "Board · 24 tasks ·
    /// 30 days left" is the difference between an empty board and a quarter of
    /// somebody's work. Boards trashed before the cards travelled with them say
    /// nothing, which is true of them: their cards went to the Inbox at the time
    /// and are not in here. See ``TrashedItem/taskCount``.
    private func subtitle(_ item: TrashedItem) -> String {
        let days = item.daysLeft()
        // The singular is the catalogue's, not a ternary's: "%lld days left"
        // carries a plural variation, like every other count string.
        let left = days == 0
            ? String(localized: "deleted today", comment: "Trash row: the last day before something is thrown away for good")
            : String(localized: "\(days) days left", comment: "Trash row: how long is left before something is thrown away for good")
        if let code = item.code {
            return "\(item.kind.label) · \(code) · \(left)"
        }
        if item.taskCount > 0 {
            let carried = String(
                localized: "\(item.taskCount) tasks",
                comment: "Trash row: how many tasks went into the trash inside a board"
            )
            return "\(item.kind.label) · \(carried) · \(left)"
        }
        return "\(item.kind.label) · \(left)"
    }

    private func rowButton(
        _ title: String, isDestructive: Bool = false, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            Text(title)
                .font(palette.ui(metrics.noteFont, .bold, relativeTo: .caption))
                .foregroundStyle(isDestructive ? palette.accent : palette.ink(0.66))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minHeight: metrics.buttonHit)
                .background(palette.ink(0.06), in: .rect(cornerRadius: 7))
        }
        .bareButton()
        // The row carries both of these as actions; a reader meeting them twice
        // is a reader reading the same button twice.
        .accessibilityHidden(true)
    }

    private var rule: some View {
        Rectangle().fill(palette.ink(0.06)).frame(height: 1)
    }

    // MARK: The two ends of the list

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The trash is empty")
                .font(palette.ui(metrics.rowFont, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink(0.66))
            Text("Tasks, columns and boards you throw away are kept here for 30 days, then deleted. A board keeps its tasks with it.")
                .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption))
                .foregroundStyle(palette.inkText(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: metrics.rowRadius + 4)
                .fill(palette.card)
                .shadow(color: palette.shadow(0.05), radius: 6, y: 2)
        }
    }

    private var emptyTrashButton: some View {
        Button { isConfirmingEmpty = true } label: {
            Text("Empty Trash")
                .font(palette.ui(metrics.rowFont, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: metrics.buttonHit)
                .background(palette.accentSoft, in: .rect(cornerRadius: metrics.rowRadius))
        }
        .bareButton()
    }
}

/// The Trash as a sheet, which is the phone's shape for it: no source list to
/// hang a popover off, and a board menu that can only raise something.
///
/// The header is `SettingsView`'s — a title and a Done — because the two are the
/// same kind of surface from the outside, and a second spelling of the same bar
/// is how two surfaces start to drift.
struct TrashSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store

    var metrics: TrashView.Metrics = .sheet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.hairline(.bottom, color: palette.ink(0.08))
            ScrollView {
                TrashView(metrics: metrics)
                    .padding(18)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.windowFill)
        .presentationBackground(palette.windowFill)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Trash")
                .font(palette.ui(17, .bold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            CountPill(count: store.trashCount)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Done")
                    .font(palette.ui(metrics.rowFont, .bold, relativeTo: .footnote))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .frame(minHeight: max(metrics.rowHit, 30))
            }
            .bareButton()
            .hoverBackground(palette.ink(0.06), radius: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}
