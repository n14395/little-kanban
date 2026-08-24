import SwiftUI

/// The small card that says what has just gone in the trash.
///
/// **Why anything says it at all.** Trashing has no confirmation and never had
/// one — the act happens and ⌘Z is behind it — so until now the only sign that
/// a board had gone was that it was no longer there. That is fine for a card
/// clicked in a column and thin for a board deleted out of a menu, and it is
/// the only place in the app where something sizeable can leave without the
/// screen saying so. It also, quietly, teaches the trash exists.
///
/// **It is a message rather than a control.** No Undo button: ⌘Z is the undo, it
/// is on the Edit menu naming the exact step, and a button that appears for
/// three seconds and then does not is a worse promise than a keystroke that is
/// always there. Nothing here is hit-testable, so it can never take a click
/// meant for the board underneath it.
///
/// The timer lives here rather than in the store, because how long a sentence
/// stays on a screen is a fact about the screen.
struct TrashToast: View {
    struct Metrics {
        var font: CGFloat
        var glyph: CGFloat
        var horizontalPadding: CGFloat
        var verticalPadding: CGFloat
        var radius: CGFloat
        /// How far off the bottom edge it floats. The desk clears its 34pt
        /// status bar; touch clears the home indicator and the tab bar.
        var bottomInset: CGFloat

        static let desk = Metrics(
            font: 12, glyph: 12, horizontalPadding: 14, verticalPadding: 9,
            radius: 10, bottomInset: 14
        )
        /// The iPad's, and the shape the phone starts from.
        static let sheet = Metrics(
            font: 14, glyph: 14, horizontalPadding: 16, verticalPadding: 12,
            radius: 12, bottomInset: 18
        )
        /// The phone's, which has a tab bar in the way: 52pt of button plus its
        /// 12pt of padding, and then the card's own gap above that.
        static let phone = Metrics(
            font: 14, glyph: 14, horizontalPadding: 16, verticalPadding: 12,
            radius: 12, bottomInset: 52 + 12 + 14
        )
    }

    /// How long the card stays. Long enough to read a name in, short enough not
    /// to be sitting there when the next thing is trashed.
    static let duration: Duration = .seconds(3.5)

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var metrics: Metrics = .desk

    var body: some View {
        ZStack(alignment: .bottom) {
            if let announcement = store.trashAnnouncement {
                card(announcement.text)
                    .padding(.bottom, metrics.bottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // A message, not a target: it must never take a click aimed at the card
        // that is still under it.
        .allowsHitTesting(false)
        .motionAnimation(.easeOut(duration: 0.18), value: store.trashAnnouncement)
        // Keyed on the id rather than on the text, so trashing two cards with
        // the same title in a row restarts the clock instead of letting the
        // first one's timer dismiss the second — see `TrashAnnouncement.id`.
        .task(id: store.trashAnnouncement?.id) {
            guard let announcement = store.trashAnnouncement else { return }
            // Nothing draws a sentence for VoiceOver: the card is out of the
            // tree below, because an element that appears for three seconds and
            // then is not there is worse to meet than one that was never there.
            // An announcement is how a transient message is meant to reach a
            // reader.
            AccessibilityNotification.Announcement(announcement.text).post()
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            store.trashAnnouncement = nil
        }
    }

    private func card(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .symbolSize(metrics.glyph, weight: .semibold, relativeTo: .caption)
                .foregroundStyle(palette.inkText(0.5))
            Text(text)
                .font(palette.ui(metrics.font, .semibold, relativeTo: .footnote))
                .foregroundStyle(palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .background {
            RoundedRectangle(cornerRadius: metrics.radius)
                .fill(palette.card)
                .shadow(color: palette.shadow(0.22), radius: 10, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius)
                .strokeBorder(palette.ink(0.08), lineWidth: 1)
        }
        // Spoken through `AccessibilityNotification.Announcement` above rather
        // than published as an element.
        .accessibilityHidden(true)
    }
}

extension View {
    /// Floats the trash card over this surface, along its bottom edge.
    func trashToast(metrics: TrashToast.Metrics = .desk) -> some View {
        overlay { TrashToast(metrics: metrics) }
    }
}
