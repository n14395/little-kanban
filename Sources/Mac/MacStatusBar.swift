#if os(macOS)

import SwiftUI

/// The 34pt footer strip.
struct MacStatusBar: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    /// Set while a check the user asked for is in flight, so the button can say
    /// so and cannot be pressed twice into two overlapping reads.
    @State private var isChecking = false

    var body: some View {
        HStack(spacing: 14) {
            Text("\(store.totalCount) tasks")
            Text("·")
            // The sidebar half is the part nothing else teaches: the Inbox
            // stopped being a column, so dropping a card on its row is the only
            // way back to it by pointer.
            Text("Drag a card between columns, or onto a board in the sidebar")
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                saveState
                syncNow
            }
        }
        .font(palette.ui(11, .semibold, relativeTo: .caption2))
        .foregroundStyle(palette.inkText(0.4))
        .padding(.horizontal, 18)
        .frame(minHeight: 34)
        .hairline(.top, color: palette.ink(0.07))
    }

    /// What the store last managed to do with the file. The design says "Synced
    /// just now"; nothing syncs, and a write that fails has nowhere else to be
    /// seen, so a failure takes the whole slot rather than sitting behind it.
    @ViewBuilder
    private var saveState: some View {
        if let error = store.lastError {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text(error.errorDescription ?? String(
                    localized: "The board could not be saved.",
                    comment: "Status bar text for a write failure with no message"
                ))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            }
            .help(error.recoverySuggestion ?? error.errorDescription ?? "")
        } else if store.isSaveBlocked {
            Text("Saving paused", comment: "Status bar text while writes are held back to protect an unreadable board file")
        } else {
            // Only this label ages, so only this label re-renders. Half a minute
            // is finer than the text it drives, which never says "31 seconds".
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(savedText(now: context.date))
            }
        }
    }

    // MARK: Sync now

    /// **A button, because the desk has no pull.** iPhone and iPad ask for a
    /// sync by pulling a list of cards past its top — see ``PullToSync`` — and a
    /// window that is already in front of you has no such gesture to borrow. The
    /// same request belongs in the same strip as the sentence about what the
    /// board last managed to do with itself, at the end of it, where a footer's
    /// controls go.
    ///
    /// **Drawn only where the question can be asked, and disabled rather than
    /// hidden when the answer is "not right now".** A build with no entitlement
    /// cannot reach a container at all, and a control that could never do
    /// anything is worse than no control — that case is Settings' to explain, so
    /// nothing is drawn here. Sync switched off, or iCloud unavailable this
    /// launch, is a different thing: the button is a legitimate thing to want,
    /// so it stays where it was and says through its tooltip why it cannot go.
    /// (The touch platforms hide the gesture in that state instead, because a
    /// pull that spins and does nothing is a promise, where a greyed button is a
    /// sentence.)
    ///
    /// The spinner is not decoration either: ``BoardStore/syncNow(settling:)``
    /// holds for a beat precisely so a change this push provokes can land under
    /// it.
    @ViewBuilder
    private var syncNow: some View {
        if SyncPreference.isAvailable {
            Button(action: check) {
                HStack(spacing: 5) {
                    // One slot, whichever is in it, so the strip does not shift
                    // sideways when the spinner replaces the glyph.
                    ZStack {
                        if isChecking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .symbolSize(11, weight: .semibold, relativeTo: .caption2)
                        }
                    }
                    .frame(width: 14, height: 14)
                    Text("Sync Now", comment: "Status bar button that sends this device's changes to iCloud and takes in the other devices'")
                }
                .foregroundStyle(palette.inkText(store.isSyncing ? 0.55 : 0.28))
                .padding(.horizontal, 8)
                .frame(minHeight: 22)
            }
            .bareButton()
            .hoverBackground(palette.ink(0.06), radius: 8)
            .disabled(!store.isSyncing || isChecking)
            .help(syncHelp)
        }
    }

    private func check() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            await store.syncNow()
            isChecking = false
        }
    }

    /// Why the button is greyed, when it is — the same four states Settings
    /// distinguishes, minus the one that draws no button at all.
    private var syncHelp: String {
        guard store.isSyncing else {
            guard SyncPreference.isOn else {
                return String(
                    localized: "Sync is off. Your board stays on this device — turn sync on in Settings.",
                    comment: "Status bar tooltip on the sync button while sync is switched off"
                )
            }
            return String(
                localized: "Not syncing right now — sign in to iCloud and relaunch. Your board is saved on this device either way.",
                comment: "Status bar tooltip on the sync button while iCloud is unavailable"
            )
        }
        return String(
            localized: "Send this device's changes and take in anything waiting from your other devices.",
            comment: "Status bar tooltip on the sync button when it can be pressed"
        )
    }

    private func savedText(now: Date) -> String {
        guard let savedAt = store.lastSavedAt else {
            return String(localized: "Not saved yet",
                          comment: "Status bar text before this session has written the board")
        }
        let elapsed = max(0, now.timeIntervalSince(savedAt))
        switch elapsed {
        case ..<45:
            return String(localized: "Saved just now", comment: "Status bar text for a very recent save")
        case ..<3_600:
            return String(localized: "Saved \(Int(elapsed / 60))m ago", comment: "Status bar text, minutes since the last save")
        case ..<86_400:
            return String(localized: "Saved \(Int(elapsed / 3_600))h ago", comment: "Status bar text, hours since the last save")
        default:
            return String(localized: "Saved \(Int(elapsed / 86_400))d ago", comment: "Status bar text, days since the last save")
        }
    }
}

#endif
