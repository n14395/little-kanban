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

/// A title and nothing else, for the medium tiles that show four of something
/// beside a heading and have no room for a chip.
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
/// The mark is either an SF Symbol — a saved view's own, so the widget's
/// heading is the glyph the row is picked by in the sidebar — or a coloured dot,
/// which is how the app marks a board and a column.
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
                WidgetCountPill(count: count)
            }
        }
    }
}

/// The sidebar's count pill.
struct WidgetCountPill: View {
    @Environment(\.palette) private var palette

    let count: Int

    var body: some View {
        Text(count.formatted())
            .font(palette.ui(10, .bold, relativeTo: .caption2))
            .monospacedDigit()
            .foregroundStyle(palette.inkText(0.6))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(palette.wash, in: Capsule())
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

/// How many rows each family has room for, once its heading is drawn.
///
/// Fixed rather than measured. `ViewThatFits` would find the largest number
/// that fits the tile it is *on*, which sounds better and is not: the answer
/// then changes with the type size, so the same widget shows five rows on one
/// machine and seven on another, and the list a person reads every morning is a
/// different length each time they change a setting somewhere else. A fixed
/// count that occasionally leaves a gap at the foot is the steadier reading.
enum WidgetRowCount {
    static let medium = 4
    static let large = 7
}
