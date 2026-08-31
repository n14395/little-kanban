import Foundation

/// A board to draw when there is no real one to draw.
///
/// Three situations reach this, and all three want the same thing — something
/// that looks like the app rather than an apology:
///
/// - The **gallery**, where the system renders every widget at a size the user
///   is browsing before they have placed one. There is a configuration but no
///   data yet, and the tile has to sell what the widget is for.
/// - A **fresh install**, before the app has been opened for long enough to
///   publish a digest.
/// - A build that is **not entitled to the App Group** — a developer build
///   signed without it — where `WidgetShare.container` is `nil` and there is
///   nowhere for a digest to be.
///
/// The seed themes, because there is no board file to read a chosen one from,
/// and they are what a first launch wears.
extension WidgetDigest {
    static let sample: WidgetDigest = {
        let today = CalendarDay.today()
        return WidgetDigest(
            writtenAt: .now,
            today: today,
            themes: .seed,
            appearance: .system,
            inbox: WidgetList(
                id: UUID(), name: String(localized: "Inbox", comment: "The global capture list, shown above the boards"),
                symbol: "tray", preset: "inbox", count: 3,
                tasks: [
                    task(String(localized: "Ring the framer back", comment: "Sample task in the widget gallery"),
                         due: today, priority: .high),
                    task(String(localized: "Read the draft brief", comment: "Sample task in the widget gallery"),
                         priority: .medium),
                    task(String(localized: "Book the rehearsal room", comment: "Sample task in the widget gallery"),
                         due: today.adding(days: 2)),
                ]
            ),
            boards: [
                WidgetBoard(
                    id: UUID(),
                    name: String(localized: "Studio", comment: "Sample board name in the widget gallery"),
                    symbol: "paintbrush",
                    columns: [
                        column(String(localized: "Backlog", comment: "Seed column: work not started"),
                               dot: .hex(0xA8A29A), count: 7,
                               tasks: [
                                   task(String(localized: "Rebuild the print rack", comment: "Sample task in the widget gallery")),
                                   task(String(localized: "Photograph the back room", comment: "Sample task in the widget gallery")),
                               ]),
                        column(String(localized: "Up Next", comment: "Seed column: work queued to start"),
                               dot: .hex(0xC98A16), count: 3),
                        column(String(localized: "In Progress", comment: "Seed column: work in flight"),
                               short: String(localized: "Doing",
                                             comment: "Abbreviated seed column name for the \"move to\" control, where room is tight"),
                               dot: .hex(0xC2532F), count: 2,
                               tasks: [
                                   task(String(localized: "Frame the new prints", comment: "Sample task in the widget gallery"),
                                        due: today, priority: .high),
                                   task(String(localized: "Write the studio notes", comment: "Sample task in the widget gallery"),
                                        due: today.adding(days: 3)),
                               ]),
                        column(String(localized: "Done", comment: "Seed column: finished work"),
                               dot: .hex(0x1F6F63), count: 11),
                    ]
                ),
            ],
            views: [
                WidgetList(
                    id: UUID(),
                    name: String(localized: "Today", comment: "Saved view: tasks due today or overdue"),
                    symbol: "sun.max", preset: WidgetList.todayPreset, count: 4,
                    tasks: [
                        task(String(localized: "Send the quote", comment: "Sample task in the widget gallery"),
                             due: today, priority: .max),
                        task(String(localized: "Frame the new prints", comment: "Sample task in the widget gallery"),
                             due: today, priority: .high),
                        task(String(localized: "Order more card stock", comment: "Sample task in the widget gallery"),
                             due: today.adding(days: -1)),
                        task(String(localized: "Update the price list", comment: "Sample task in the widget gallery"),
                             due: today, priority: .medium),
                    ]
                ),
            ]
        )
    }()

    private static func task(
        _ title: String, due: CalendarDay? = nil, priority: Priority = .low
    ) -> WidgetTask {
        WidgetTask(id: UUID(), title: title, due: due, priority: priority, isDone: false)
    }

    /// A column with a plausible count, and rows on the two a column widget is
    /// most likely to be placed on. The board-overview widget draws the count
    /// rather than the rows, so the other two carry none.
    private static func column(
        _ name: String, short: String? = nil, dot: SwatchColor, count: Int,
        tasks: [WidgetTask] = []
    ) -> WidgetColumn {
        WidgetColumn(id: UUID(), name: name, short: short ?? name, dot: dot, count: count, tasks: tasks)
    }
}
