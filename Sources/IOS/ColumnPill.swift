#if os(iOS)

import SwiftUI

/// A column's name and how much is in it, in a capsule.
///
/// **One shape, drawn by both orientations.** Portrait's header draws a strip of
/// these as the column switcher — tap one to page to that column. Landscape has
/// no switcher, because three pages are side by side and most of a board is
/// already there; what it has instead is a caption over each page saying which
/// column it is. Those were two different drawings
/// of the same fact — a capsule with a count in one orientation, a coloured dot
/// and a caption in the other — and turning the phone changed what a column
/// looked like for no reason the user could name.
///
/// So the caption is this capsule too, and the pill lives in one place rather
/// than being spelled out twice.
///
/// **`isCurrent` is portrait's alone.** Accent means *this is the column you are
/// looking at*, which is a true and useful thing to say when one column fills
/// the screen and the rest are off the side of it. In landscape every column
/// with a pill over it is on screen, so there is nothing for the accent to pick
/// out and every pill is drawn plain.
struct ColumnPill: View {
    @Environment(\.palette) private var palette

    let name: String
    let count: Int
    var isCurrent: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(palette.ui(12.5, .bold, relativeTo: .footnote))
            Text("\(count)")
                .font(palette.ui(10.5, .extraBold, relativeTo: .caption2))
                .opacity(0.65)
        }
        .foregroundStyle(isCurrent ? palette.onAccent : palette.inkText(0.6))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isCurrent ? palette.accent : palette.ink(0.055), in: .capsule)
    }
}

#endif
