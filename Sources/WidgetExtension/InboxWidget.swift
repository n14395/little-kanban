import SwiftUI
import WidgetKit

/// The Inbox, at all three sizes, and the app's `+` at every one of them.
///
/// One widget rather than three, because the three sizes the brief asks for are
/// the same widget with more room: a capture button and a count, a capture
/// button and the first few cards, and the list with the button moved into the
/// corner. Somebody who resizes it should get more of what they had, not a
/// different widget.
struct InboxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShare.Kind.inbox, provider: InboxTimelineProvider()) { entry in
            InboxWidgetView(entry: entry)
        }
        .configurationDisplayName(
            Text("Inbox", comment: "The global capture list, shown above the boards")
        )
        .description(
            Text("Capture a task, and see what is waiting in the Inbox.",
                 comment: "What the Inbox widget is for, in the widget gallery")
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct InboxWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: DigestEntry

    private var inbox: WidgetList { entry.digest.inbox }

    var body: some View {
        WidgetSurface(entry.digest) { _ in
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            default: large
            }
        }
    }

    // MARK: Small — the capture button, and how much is waiting

    /// `widgetURL` rather than a `Link`, and it has to be: the small family
    /// takes exactly one tap target for the whole tile. That makes the choice of
    /// destination the whole design — and a tile whose front is a `+` opens the
    /// `+`.
    private var small: some View {
        VStack(spacing: 10) {
            WidgetNewTaskTile(glyphSize: 26, showsLabel: false)
            InboxCountLine(count: inbox.count, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(AppLink.url(.newTask))
    }

    // MARK: Medium — the capture button beside the first few cards

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            // Centred against the whole tile rather than sitting at the top of
            // it. The list beside it starts at a heading and ends wherever it
            // runs out, so there is nothing on that side for the button to line
            // up *with* — level with the middle is the one position that looks
            // deliberate at every length of list.
            WidgetNewTaskTile(glyphSize: 18)
                .frame(width: 78)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                WidgetHeading(mark: .symbol(inbox.symbol), title: inbox.name, count: inbox.count)
                WidgetRowSpace { rows in
                    InboxRows(list: inbox, today: entry.today, limit: rows)
                }
            }
        }
        // The tile's own tap opens the Inbox rather than the capture: the `+`
        // is already a target of its own here, and a person who taps the list
        // means the list.
        .widgetURL(AppLink.url(.inbox))
    }

    // MARK: Large — the list, with the button in the corner

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                WidgetHeading(mark: .symbol(inbox.symbol), title: inbox.name, count: inbox.count)
                WidgetNewTaskCorner()
            }
            WidgetRowSpace { rows in
                InboxRows(list: inbox, today: entry.today, limit: rows)
            }
        }
        .widgetURL(AppLink.url(.inbox))
    }
}

/// "3 tasks in the Inbox", or what to say when there are none.
///
/// Branched in code rather than left to a plural rule with a `zero` case,
/// because English has no zero category — "0 tasks in the Inbox" is what the
/// catalogue would produce, and an empty Inbox is the one state worth a sentence
/// of its own.
private struct InboxCountLine: View {
    @Environment(\.palette) private var palette

    let count: Int
    var alignment: TextAlignment = .leading

    var body: some View {
        Text(text)
            .font(palette.ui(11, .semibold, relativeTo: .caption))
            .foregroundStyle(palette.inkText(0.7))
            .multilineTextAlignment(alignment)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    private var text: String {
        count == 0
            ? String(localized: "Nothing in the Inbox",
                     comment: "Widget: the Inbox has no tasks waiting in it")
            : String(localized: "\(count) tasks in the Inbox",
                     comment: "Widget: how many tasks are waiting in the Inbox")
    }
}

/// The Inbox's rows, or the sentence that stands in for them.
private struct InboxRows: View {
    let list: WidgetList
    let today: CalendarDay
    let limit: Int

    var body: some View {
        if list.tasks.isEmpty {
            WidgetEmptyNote(
                text: String(localized: "Nothing in the Inbox",
                             comment: "Widget: the Inbox has no tasks waiting in it")
            )
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(list.tasks.prefix(limit)) { task in
                    WidgetTaskRow(task: task, today: today)
                }
            }
        }
    }
}
