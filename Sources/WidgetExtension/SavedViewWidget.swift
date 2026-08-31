import SwiftUI
import WidgetKit

/// One saved view — Today, Due this week, or one the user wrote.
///
/// Two sizes, and they answer different questions. The medium tile is a glance:
/// the view's name and glyph on the left, the first few as bullets beside them,
/// which is what "is there anything I should know about" looks like. The large
/// tile is the list itself, with due chips and priorities, which is what
/// "what am I doing today" looks like. How many "a few" is comes from the tile
/// rather than from a constant — see ``WidgetRowCount``.
struct SavedViewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetShare.Kind.savedView,
            intent: SavedViewWidgetIntent.self,
            provider: ConfiguredTimelineProvider<SavedViewWidgetIntent>()
        ) { entry in
            SavedViewWidgetView(entry: entry)
        }
        .configurationDisplayName(
            Text("Saved view", comment: "Widget name in the gallery: the cards in a saved view")
        )
        .description(
            Text("The cards in one of your saved views.",
                 comment: "What the saved view widget is for, in the widget gallery")
        )
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SavedViewWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: ConfiguredEntry<SavedViewWidgetIntent>

    /// The configured view; failing that Today, which is what the widget's own
    /// picker defaults to and what the app opens on.
    private var list: WidgetList? {
        if let named = entry.digest.view(id: entry.configuration.savedView?.id) { return named }
        let views = entry.digest.views
        return views.first { $0.preset == WidgetList.todayPreset } ?? views.first
    }

    var body: some View {
        WidgetSurface(entry.digest) { _ in
            if let list {
                if family == .systemMedium {
                    medium(list)
                } else {
                    large(list)
                }
            } else {
                WidgetMissingNote(
                    text: String(localized: "That view is not on this device any more.",
                                 comment: "Widget: the saved view it was set up with has been deleted")
                )
            }
        }
    }

    // MARK: Medium — the name on the left, the first few bullets beside it

    private func medium(_ list: WidgetList) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ViewTitleBlock(list: list)
                .frame(width: 96, alignment: .leading)
            if list.tasks.isEmpty {
                emptyNote(list)
            } else {
                WidgetRowSpace(shape: .bullet) { rows in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(list.tasks.prefix(rows)) { task in
                            WidgetBulletRow(task: task)
                        }
                    }
                }
            }
        }
        .widgetURL(AppLink.url(.view(list.id)))
    }

    // MARK: Large — the list

    private func large(_ list: WidgetList) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeading(mark: .symbol(list.symbol), title: list.name, count: list.count)
            if list.tasks.isEmpty {
                emptyNote(list)
            } else {
                WidgetRowSpace { rows in
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(list.tasks.prefix(rows)) { task in
                            WidgetTaskRow(task: task, today: entry.digest.today)
                        }
                    }
                }
            }
        }
        .widgetURL(AppLink.url(.view(list.id)))
    }

    /// One sentence for every view, rather than the app's hand-written empty
    /// state per preset. The app can afford those because it knows which view
    /// it is drawing and has a paragraph of room; a widget has a line, and
    /// "Nothing in Today" is already the whole of what that line can say.
    private func emptyNote(_ list: WidgetList) -> some View {
        WidgetEmptyNote(
            text: String(localized: "Nothing in \(list.name)",
                         comment: "Widget: the saved view it is showing has no cards in it")
        )
    }
}

/// The view's glyph, its name and its count, stacked — the left third of the
/// medium tile.
private struct ViewTitleBlock: View {
    @Environment(\.palette) private var palette

    let list: WidgetList

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: list.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text(list.name)
                // The display face, which the app uses for a board's title and
                // for a task's in the inspector — and for nothing else. A saved
                // view's name standing alone as the subject of a tile is the
                // same job those two do.
                .font(palette.display(17, relativeTo: .title3))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            WidgetCountPill(count: list.count)
            Spacer(minLength: 0)
        }
    }
}
