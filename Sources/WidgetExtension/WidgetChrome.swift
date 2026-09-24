// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import WidgetKit

/// The ground every widget stands on, in the theme the app is wearing.
///
/// **Which of the two theme slots is not the widget's decision alone.** The
/// system hands the extension a colour scheme, and that is the answer whenever
/// Settings ▸ Appearance is on *System* — but somebody who has pinned the app
/// to Dark has pinned the app, and a widget that went light at sunrise would be
/// the only part of it that did. ``AppAppearance/slot(under:)`` is where the two
/// are reconciled, and it is the same expression `RootView` builds its palette
/// from.
///
/// The palette is put into the environment as well as handed to the closure, so
/// that a row three levels down asks for a colour the way every row in the app
/// does rather than having one threaded to it.
struct WidgetSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    private let digest: WidgetDigest
    private let content: (Palette) -> Content

    init(_ digest: WidgetDigest, @ViewBuilder content: @escaping (Palette) -> Content) {
        self.digest = digest
        self.content = content
    }

    var body: some View {
        let palette = Palette(theme: digest.themes.theme(for: digest.appearance.slot(under: colorScheme)))
        content(palette)
            .environment(\.palette, palette)
            .foregroundStyle(palette.ink)
            // The window's own gradient, run across the tile. `containerBackground`
            // rather than a `.background`: it is what lets the system inset,
            // mask and — on the desktop — de-saturate the widget without the
            // fill being clipped at the wrong radius.
            .containerBackground(for: .widget) { palette.windowFill }
    }
}

// MARK: - Rows

/// One card, as a widget draws it: its priority, its title, and its due chip.
///
/// The three the board's own card leads with. Everything else a card has —
/// labels, the note, sub-task progress — needs room this does not have, and a
/// row that tried to show them would show none of them legibly.
struct WidgetTaskRow: View {
    @Environment(\.palette) private var palette

    let task: WidgetTask
    let today: CalendarDay

    var body: some View {
        Link(destination: AppLink.url(.task(task.id))) {
            HStack(spacing: 7) {
                Circle()
                    .fill(palette.priorityColor(task.priority))
                    .frame(width: 6, height: 6)
                Text(task.title)
                    .font(palette.ui(13, .medium, relativeTo: .subheadline))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Finished work reads as finished rather than disappearing:
                    // a column widget on Done is a widget of nothing else.
                    .strikethrough(task.isDone, color: palette.inkText(0.5))
                    .foregroundStyle(task.isDone ? palette.inkText(0.5) : palette.ink)
                Spacer(minLength: 4)
                if let due = task.due {
                    WidgetDueChip(day: due, today: today, isDone: task.isDone)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A title and nothing else, for the medium tile that shows a few of something
/// beside a title block and has no room for a chip.
struct WidgetBulletRow: View {
    @Environment(\.palette) private var palette

    let task: WidgetTask

    var body: some View {
        Link(destination: AppLink.url(.task(task.id))) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(palette.inkText(0.45))
                    .frame(width: 3, height: 3)
                Text(task.title)
                    .font(palette.ui(12, .medium, relativeTo: .caption))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(task.isDone ? palette.inkText(0.5) : palette.ink)
                    .strikethrough(task.isDone, color: palette.inkText(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The board's due chip, at widget size.
struct WidgetDueChip: View {
    @Environment(\.palette) private var palette

    let day: CalendarDay
    /// The day the *digest* was written against, not the day it is now — see
    /// ``WidgetDigest/today``. A chip drawn against a different day from the
    /// list it sits in would say "Today" beside a card the app has already
    /// stopped counting as due.
    let today: CalendarDay
    let isDone: Bool

    var body: some View {
        let tone = palette.dueTone(due: day, today: today, isDone: isDone)
        Text(DueDate.label(day, from: today))
            .font(palette.ui(10, .semibold, relativeTo: .caption2))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(tone.foreground)
            .background(tone.background, in: .rect(cornerRadius: 4))
    }
}

// MARK: - Headings

/// A widget's heading: a mark, a name, and how many things are under it.
///
/// The mark is either an SF Symbol — a saved view's or a board's own, so the
/// widget's heading is the glyph the row is picked by in the sidebar — or a
/// coloured dot, which is how the app marks a column.
struct WidgetHeading: View {
    @Environment(\.palette) private var palette

    enum Mark {
        case symbol(String)
        case dot(SwatchColor)
    }

    let mark: Mark
    let title: String
    var subtitle: String?
    var count: Int?
    /// Only the column widget passes one: a board's total and a saved view's
    /// are counts of things gathered from everywhere, and neither has a limit
    /// to be over.
    var limit: Int?

    var body: some View {
        HStack(spacing: 6) {
            switch mark {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.accent)
            case .dot(let swatch):
                Circle()
                    .fill(palette.resolve(swatch))
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .font(palette.ui(13, .bold, relativeTo: .subheadline))
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(palette.ui(11, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.6))
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 4)
            if let count {
                WidgetCountPill(count: count, limit: limit)
            }
        }
    }
}

/// The sidebar's count pill.
struct WidgetCountPill: View {
    @Environment(\.palette) private var palette

    let count: Int
    /// The column's WIP limit, when it has one — see ``BoardColumn/limit``. The
    /// app's own `CountPill` reads exactly the same way, through exactly the
    /// same `Palette.loadTone(_:)`, which is the point: a column drawn `4/3` in
    /// hot on the board must not be a plain `4` on the home screen.
    var limit: Int?

    var body: some View {
        let tone = palette.loadTone(ColumnLoad(count: count, limit: limit))
        return label
            .font(palette.ui(10, .bold, relativeTo: .caption2))
            .monospacedDigit()
            .foregroundStyle(tone?.foreground ?? palette.inkText(0.6))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tone?.background ?? palette.wash, in: Capsule())
    }

    /// The limited spelling is the catalogue key the app's own `CountPill`
    /// writes, deliberately: one entry, one translation, and the two pills
    /// cannot drift into two ideas of what a pair of numbers looks like.
    @ViewBuilder private var label: some View {
        if let limit {
            Text("\(count)/\(limit)", comment: "A column's card count against its WIP limit, as in 4/3")
        } else {
            Text(count.formatted())
        }
    }
}

// MARK: - Capture

/// The `+`.
///
/// A `Link` rather than a `Button(intent:)`, and ``AppLink`` says why at length:
/// a task added in the background with no title and no way to type one is
/// litter the user has to go and find. This opens the app on a fresh Inbox
/// capture with its title field waiting.
struct WidgetNewTaskTile: View {
    @Environment(\.palette) private var palette

    /// How big the glyph is drawn. The small tile leads with it and the medium
    /// tile stands it beside a list, where the same size would shout.
    var glyphSize: CGFloat = 28
    var showsLabel = true

    var body: some View {
        Link(destination: AppLink.url(.newTask)) {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .frame(width: glyphSize * 1.9, height: glyphSize * 1.9)
                    .background(palette.accent, in: .rect(cornerRadius: glyphSize * 0.55))
                if showsLabel {
                    Text("New task", comment: "Widget button: capture a task into the Inbox")
                        .font(palette.ui(11, .semibold, relativeTo: .caption))
                        .foregroundStyle(palette.inkText(0.7))
                }
            }
        }
    }
}

/// The `+` as a corner button, for a tile whose body is already a list.
struct WidgetNewTaskCorner: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Link(destination: AppLink.url(.newTask)) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.onAccent)
                .frame(width: 24, height: 24)
                .background(palette.accent, in: Circle())
        }
        .accessibilityLabel(Text("New task", comment: "Widget button: capture a task into the Inbox"))
    }
}

// MARK: - When there is nothing

/// What a list with nothing in it says.
///
/// A sentence rather than an empty tile, for the reason a deep link that goes
/// nowhere gets an alert: a widget drawing nothing at all is indistinguishable
/// from a widget that has failed.
struct WidgetEmptyNote: View {
    @Environment(\.palette) private var palette

    let text: String

    var body: some View {
        Text(text)
            .font(palette.ui(12, .medium, relativeTo: .caption))
            .foregroundStyle(palette.inkText(0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// What a widget says when the thing it was set up with is not there any more.
///
/// A board, a column and a saved view can all be deleted while a widget goes on
/// naming one, and there is nothing the extension can do about it — but there is
/// something it can *say*. A tile that went blank would read as the widget
/// having broken, and the fix is in the widget's own editor, which is where this
/// sends the reader.
struct WidgetMissingNote: View {
    @Environment(\.palette) private var palette

    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(palette.inkText(0.5))
            Text(text)
                .font(palette.ui(12, .medium, relativeTo: .caption))
                .foregroundStyle(palette.inkText(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// How many rows a list has room for on the tile it is actually on.
///
/// **Worked out from the tile, not from the family.** The family says medium or
/// large; it does not say how tall that is. A medium tile is 138pt of content on
/// a 6.7" phone and 116pt on an SE, and a large one runs from 292pt to 350pt —
/// so a single number per family has to be the smallest phone's number, and the
/// phone most people are holding then loses a fifth of its tile to white space.
/// That is what it did: four rows on a medium tile with room for five, and four
/// bullets in a box with room for six.
///
/// **It is still not `ViewThatFits`.** The count comes from the tile's height
/// and the design's own point sizes — a row is 16pt on a 5pt gap, a bullet 15pt
/// on a 6pt gap, both measured — and never from the height the text happened to
/// render at. So it changes when the tile changes, which is once, when the
/// widget is placed; it does not change because somebody turned the type size up
/// in Settings, which was the whole objection to measuring. A reader whose text
/// is large sees the same number of rows as everyone else on that phone, drawn
/// larger, with the last one clipped at the margin rather than the list quietly
/// becoming a different length.
///
/// The floor is one row — a list widget drawing nothing reads as broken — and
/// the ceiling is what the digest carries, since asking for more than that draws
/// short with nothing on either side saying so. See ``WidgetDigest/listLength``.
enum WidgetRowCount {
    /// The two shapes a list row comes in, and what each one measures.
    ///
    /// A bullet is the shorter of the two and sits on the wider gap, which is
    /// very nearly a wash: both pitch at 21pt. What actually makes a bullet list
    /// longer is that nothing stands above it — the saved-view medium draws its
    /// name in a block to the left rather than in a heading — so it has the
    /// whole tile to spend.
    enum Shape {
        case task
        case bullet

        var height: CGFloat {
            switch self {
            case .task: 16
            case .bullet: 15
            }
        }

        var gap: CGFloat {
            switch self {
            case .task: 5
            case .bullet: 6
            }
        }
    }

    /// The most any widget may draw, which is what crossed the fence.
    static let ceiling = WidgetDigest.listLength

    /// How many rows of `shape` fit in `height` points.
    ///
    /// `height` is the space *left for the rows* — a heading and its gap are
    /// already off it, because ``WidgetRowSpace`` is asked for the leftover
    /// rather than for the tile.
    static func fitting(_ height: CGFloat, shape: Shape = .task) -> Int {
        let pitch = shape.height + shape.gap
        // The last row spends no gap, so it is the gap-inclusive height that
        // divides evenly: 5 rows of 16 on 4 gaps of 5 is 100, which is
        // (100 + 5) / 21.
        let fits = Int(((height + shape.gap) / pitch).rounded(.down))
        return min(ceiling, max(1, fits))
    }
}

/// The room under a heading, and how many rows fit in it.
///
/// A `GeometryReader` standing where the list stands: in a stack it takes
/// whatever height the things above it left, which is exactly the number
/// ``WidgetRowCount/fitting(_:shape:)`` wants. Putting it here rather than
/// around the whole tile means no widget has to know its own margins or subtract
/// its own heading — the layout has already done both by the time this is
/// measured.
struct WidgetRowSpace<Content: View>: View {
    var shape: WidgetRowCount.Shape = .task
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        GeometryReader { proxy in
            content(WidgetRowCount.fitting(proxy.size.height, shape: shape))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
