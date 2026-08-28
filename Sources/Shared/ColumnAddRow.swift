import SwiftUI

/// The dashed "+ Add task to <column>" row that sits under the last card of a
/// column.
///
/// **One view for all three platforms.** It was the phone's for as long as it
/// existed — drawn inline in `PhoneRootView`, where a column is a page and its
/// foot is where a thumb already is. The desk and the iPad had nothing there:
/// the way to add to a column was the `+` in its heading, at the far end of a
/// strip that is taller than the window as often as not, so on a column you had
/// scrolled to the bottom of the control was off screen. This is that offer,
/// where the reading of the column ends.
///
/// Drawn from one set of numbers rather than a preset per platform, because the
/// three are meant to be the same row: 13.5 bold at 45% ink, 14 of padding, and
/// a 1.5pt dash on a 16pt corner. It is the type that grows with the reader, not
/// the box — the dashes are furniture and the words are the control.
struct ColumnAddRow: View {
    @Environment(\.palette) private var palette

    /// What the row names as the destination. The column on a board; on the
    /// phone's flat list, the column the pager is on — which is the same
    /// answer, arrived at from the surface rather than from a column in hand.
    let name: String
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            // The whole label, so the button publishes "+ Add task to Backlog"
            // rather than a glyph and a name a reader has to put together.
            Text("+ Add task to \(name)")
                .font(palette.ui(13.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.inkText(0.45))
                .frame(maxWidth: .infinity)
                .padding(14)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            palette.ink(0.18),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                }
        }
        .buttonStyle(.bare)
    }
}
