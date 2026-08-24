#if os(macOS)

import SwiftUI

/// The 34pt footer strip.
struct MacStatusBar: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            Text("\(store.totalCount) tasks")
            Text("·")
            // The sidebar half is the part nothing else teaches: the Inbox
            // stopped being a column, so dropping a card on its row is the only
            // way back to it by pointer.
            Text("Drag a card between columns, or onto a board in the sidebar")
            Spacer(minLength: 0)
            saveState
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
