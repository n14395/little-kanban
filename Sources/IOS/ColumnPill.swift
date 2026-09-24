// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

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
///
/// **The limit is drawn in the text on both states and in the capsule on only
/// one.** `4/3` is the fact, and it is said whether or not this is the column
/// on screen. The warning fill is not: `isCurrent` already fills the capsule
/// with the accent, and a hot capsule underneath the accent one would be two
/// meanings fighting over the same fifty points — with the one that says *where
/// you are* losing. The column you are looking at is the one whose cards are in
/// front of you anyway; the pills worth colouring are the other ones.
struct ColumnPill: View {
    @Environment(\.palette) private var palette

    let name: String
    let count: Int
    /// The column's WIP limit, when it has one. See ``BoardColumn/limit``.
    var limit: Int?
    var isCurrent: Bool = false

    private var load: ColumnLoad { ColumnLoad(count: count, limit: limit) }

    var body: some View {
        let tone = isCurrent ? nil : palette.loadTone(load)
        HStack(spacing: 6) {
            Text(name)
                .font(palette.ui(12.5, .bold, relativeTo: .footnote))
            countLabel
                .font(palette.ui(10.5, .extraBold, relativeTo: .caption2))
                // Full strength once it is carrying a warning: the count is the
                // half of the pill that has something to say, and 65% is the
                // opacity of a detail nobody needs to read.
                .opacity(tone == nil ? 0.65 : 1)
        }
        .foregroundStyle(tone?.foreground ?? (isCurrent ? palette.onAccent : palette.inkText(0.6)))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            tone?.background ?? (isCurrent ? palette.accent : palette.ink(0.055)), in: .capsule
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    @ViewBuilder private var countLabel: some View {
        if let limit {
            Text("\(count)/\(limit)", comment: "A column's card count against its WIP limit, as in 4/3")
        } else {
            Text("\(count)")
        }
    }

    /// The name and the count as one phrase, because they are one control: a
    /// chip in portrait's strip is a button that pages to its column, and
    /// VoiceOver reading "Backlog" and "4 slash 3" as two elements says less
    /// than either half on its own.
    private var spokenLabel: Text {
        guard let limit else {
            // What `children: .combine` already spoke before there were limits,
            // said explicitly because the branch below has to override it.
            return Text("\(name), \(count)",
                        comment: "VoiceOver label for a column chip: the column's name and how many cards are in it")
        }
        return switch load {
        case .over:
            Text("\(name), \(count) of \(limit), over the column limit",
                 comment: "VoiceOver label for a column chip past its WIP limit")
        case .at:
            Text("\(name), \(count) of \(limit), at the column limit",
                 comment: "VoiceOver label for a column chip exactly at its WIP limit")
        case .under, .unlimited:
            Text("\(name), \(count) of \(limit)",
                 comment: "VoiceOver label for a column chip below its WIP limit")
        }
    }
}

#endif
