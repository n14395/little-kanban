import SwiftUI

/// The inline "Task title, then ⏎" field.
///
/// One view rather than one per surface: a board column and the Inbox both open
/// it, and the fiddly part — the three ways out, and taking focus the moment it
/// appears — is the same on both.
struct BoardTaskComposer: View {
    struct Metrics {
        var font: CGFloat
        var horizontalPadding: CGFloat
        var verticalPadding: CGFloat
        var cornerRadius: CGFloat
        /// The row's floor. A `TextField`'s own hit area is the height of the
        /// text it draws — around 21pt — so on touch the row claims the
        /// minimum and hands the field the whole of it.
        var minHeight: CGFloat

        static let desk = Metrics(
            font: 13.5, horizontalPadding: 12, verticalPadding: 10, cornerRadius: 12, minHeight: 0
        )
        static let pad = Metrics(
            font: 15, horizontalPadding: 14, verticalPadding: 11, cornerRadius: 14, minHeight: 44
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    /// The board's scrollers, where this field is drawn on one. Absent in the
    /// Inbox panel, which is a flat list with nothing to scroll a card into.
    @Environment(BoardFocusRelay.self) private var relay: BoardFocusRelay?
    @FocusState private var isFocused: Bool

    /// Where this one is adding, which it needs only to tell its own loss of
    /// focus from being replaced by a composer somewhere else.
    let placement: TaskPlacement
    var metrics: Metrics = .desk

    var body: some View {
        @Bindable var store = store

        // The placeholder doubles as the field's accessibility label unless one
        // is given, and "⏎" is a hint aimed at people who can see the key.
        return TextField("Task title, then ⏎", text: $store.draft)
            .accessibilityLabel("Task title")
            .textFieldStyle(.plain)
            .font(palette.ui(metrics.font, .bold, relativeTo: .subheadline))
            .foregroundStyle(palette.ink)
            .focused($isFocused)
            .onSubmit {
                // The card is appended, so it arrives at the foot of the column
                // however far from the foot this field was drawn. Nothing else
                // moves the board here — a commit is not a click and not a key
                // — so a card made from the head of a long column would land
                // off the bottom of it, unseen. `intoView` is the smallest ask
                // there is: nothing at all happens when the card is already
                // whole on screen, which is the common case.
                guard let made = store.commitDraft() else { return }
                relay?.reveal = .intoView(made)
            }
            .onKeyPress(.escape) {
                store.cancelDraft()
                return .handled
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .fieldHitArea(minHeight: metrics.minHeight) { isFocused = true }
            .background {
                RoundedRectangle(cornerRadius: metrics.cornerRadius)
                    .fill(palette.card)
                    .shadow(color: palette.shadow(0.1), radius: 1, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: metrics.cornerRadius)
                    .strokeBorder(palette.accent.opacity(0.35), lineWidth: 2)
            }
            .focusWhenReady($isFocused)
            // Clicking away is the third way out, alongside ⏎ and Escape.
            // Only an empty draft goes: losing a half-typed title to a stray
            // click costs the user more than a stray open row does.
            //
            // The placement check is what makes "add to another column" work:
            // that closes this composer and opens one there, and without it
            // this one's parting focus change would cancel the new one's draft.
            .onChange(of: isFocused) { _, focused in
                guard !focused, store.addingPlacement == placement,
                      store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return }
                store.cancelDraft()
            }
    }
}
