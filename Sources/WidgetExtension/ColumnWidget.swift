import SwiftUI
import WidgetKit

/// The cards in one column of one board.
///
/// **The same widget with more room**, which is the Inbox widget's rule and the
/// reason the two sizes share a heading rather than each getting a layout of
/// their own: somebody who resizes a column widget should get more of what they
/// had. Medium is the top four, large is the top seven, and both carry the due
/// chips and priority dots — a column is where a date means something, so the
/// bullet treatment the saved-view widget uses at this size would be dropping
/// the half of a card that a board column is read for.
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
    @Environment(\.widgetFamily) private var family

    let entry: ConfiguredEntry<ColumnWidgetIntent>

    private var rows: Int {
        family == .systemMedium ? WidgetRowCount.medium : WidgetRowCount.large
    }

    /// Resolved by column id alone, so a column moved to another board keeps
    /// drawing and simply says it is on the other board now. Falling back to
    /// the first board's landing column is what an unedited widget shows.
    private var found: (board: WidgetBoard, column: WidgetColumn)? {
        if let named = entry.digest.column(id: entry.configuration.column?.id) { return named }
        guard let board = entry.digest.boards.first, let column = board.columns.first else { return nil }
        return (board, column)
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
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(column.tasks.prefix(rows)) { task in
                        WidgetTaskRow(task: task, today: entry.digest.today)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(AppLink.url(.column(column.id)))
    }
}
