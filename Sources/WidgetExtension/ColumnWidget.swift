import SwiftUI
import WidgetKit

/// The cards in one column of one board.
///
/// **The same widget with more room**, which is the Inbox widget's rule and the
/// reason the two sizes share a heading rather than each getting a layout of
/// their own: somebody who resizes a column widget should get more of what they
/// had. Neither size names a number of rows — ``WidgetRowSpace`` hands the list
/// however many the tile turned out to have room for — and both carry the due
/// chips and priority dots, because a column is where a date means something and
/// the bullet treatment the saved-view widget uses at this size would drop the
/// half of a card that a board column is read for.
struct ColumnWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetShare.Kind.column,
            intent: ColumnWidgetIntent.self,
            provider: ConfiguredTimelineProvider<ColumnWidgetIntent>()
        ) { entry in
            ColumnWidgetView(entry: entry)
        }
        .configurationDisplayName(
            Text("Column", comment: "What a board column is called when configuring a widget")
        )
        .description(
            Text("The cards in one column of a board.",
                 comment: "What the column widget is for, in the widget gallery")
        )
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ColumnWidgetView: View {
    let entry: ConfiguredEntry<ColumnWidgetIntent>

    /// Resolved by column id alone, so a column moved to another board keeps
    /// drawing and simply says it is on the other board now. The fallback to
    /// the first board's first column belongs to the *unconfigured* widget
    /// alone: a widget somebody pointed at a column that has since been
    /// deleted shows the missing note instead, because quietly redrawing some
    /// other column under the same frame is a widget lying about what it is —
    /// and was what left the note below effectively unreachable.
    private var found: (board: WidgetBoard, column: WidgetColumn)? {
        guard let picked = entry.configuration.column else {
            guard let board = entry.digest.boards.first, let column = board.columns.first
            else { return nil }
            return (board, column)
        }
        return entry.digest.column(id: picked.id)
    }

    var body: some View {
        WidgetSurface(entry.digest) { _ in
            if let found {
                content(board: found.board, column: found.column)
            } else {
                WidgetMissingNote(
                    text: String(localized: "That column is not on this device any more.",
                                 comment: "Widget: the column it was set up with has been deleted")
                )
            }
        }
    }

    private func content(board: WidgetBoard, column: WidgetColumn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(
                mark: .dot(column.dot), title: column.name,
                subtitle: board.name, count: column.count
            )
            if column.tasks.isEmpty {
                WidgetEmptyNote(
                    text: String(localized: "Nothing in this column",
                                 comment: "Widget: the column it is showing has no cards in it")
                )
            } else {
                WidgetRowSpace { rows in
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(column.tasks.prefix(rows)) { task in
                            WidgetTaskRow(task: task, today: entry.today)
                        }
                    }
                }
            }
        }
        .widgetURL(AppLink.url(.column(column.id)))
    }
}
