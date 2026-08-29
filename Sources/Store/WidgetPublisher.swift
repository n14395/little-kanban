import Foundation
import WidgetKit

/// Writes the widgets' digest, and wakes them when it has changed.
///
/// The fourth of the followers a save carries — see
/// `BoardStore.reconcileSystemsAndSync`, where the reminders, the Spotlight
/// index and the synced records are the other three. It rides the same debounce
/// for the same reason: it is O(board), and a burst of keystrokes should pay it
/// once.
///
/// **Nothing is drawn here.** The digest is a rendering of the app's answers,
/// not of its pixels: which cards are in a column, how many are in a view, what
/// the theme is. See ``WidgetDigest`` for why the extension is given answers
/// rather than the board.
@MainActor
enum WidgetPublisher {
    /// What was last written, so an edit that changes nothing a widget draws
    /// does not wake every widget on the machine.
    ///
    /// A board is saved on every keystroke of a title and on every drag of a
    /// card, and most of those change no count, no order and no row inside the
    /// first eight — `reloadAllTimelines` on each of them would be the app
    /// asking the system to re-render four widgets a character.
    private static var lastPublished: WidgetDigest?

    /// Publishes if there is anything new to publish.
    ///
    /// `today` is passed in rather than read here for `DayClock`'s reason: the
    /// day is what the saved views are evaluated against, and the caller that
    /// knows the day has rolled over is the one that has to be able to say so.
    static func publish(_ store: BoardStore, today: CalendarDay) {
        // The suite's stores are file-backed under the app's own bundle
        // identifier — see `BoardFile.isRunningTests` — so without this a test
        // run would publish its fixtures to the developer's own widgets.
        guard !BoardFile.isRunningTests else { return }
        let next = digest(of: store, today: today)
        // Compared with the stamp set aside, because the stamp is the one field
        // that differs on every pass by construction. Everything else is what
        // the widgets actually draw.
        if var previous = lastPublished {
            previous.writtenAt = next.writtenAt
            guard previous != next else { return }
        }
        guard let data = WidgetDigestFile.encoded(next), WidgetDigestFile.write(data) else { return }
        lastPublished = next
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The digest for a board, without writing it anywhere.
    ///
    /// Separate from ``publish(_:today:)`` so that what crosses the fence can be
    /// asserted about without a container, an entitlement or a second process —
    /// which is the whole of what `WidgetDigestTests` needs.
    static func digest(of store: BoardStore, today: CalendarDay) -> WidgetDigest {
        WidgetDigest(
            writtenAt: .now,
            today: today,
            themes: store.themes,
            appearance: Preferences.appearance,
            inbox: inbox(of: store),
            boards: store.boards.map { board(from: $0, in: store) },
            views: store.views.map { list(from: $0, in: store, today: today) }
        )
    }

    // MARK: The three kinds of list

    /// The Inbox as the *panel* draws it, minus the cards that have been ticked
    /// off in it.
    ///
    /// Completed Inbox cards sit at the foot of the panel and are deliberately
    /// not thrown away — but "3 tasks in the Inbox" means three things left to
    /// do, and a widget whose number counted work already finished would be
    /// answering a question nobody asked it. Dropping them here also makes this
    /// list exactly the seeded Inbox view's membership, so the two numbers the
    /// app shows for the Inbox agree with the one the widget shows.
    private static func inbox(of store: BoardStore) -> WidgetList {
        let seeded = SavedView.seeded(.inbox)
        let open = store.inboxTasks.filter { !$0.isInboxCompleted }
        return WidgetList(
            id: seeded.id, name: Board.inboxName, symbol: seeded.symbol,
            preset: seeded.preset?.rawValue, count: open.count, tasks: rows(open, in: store)
        )
    }

    private static func board(from board: Board, in store: BoardStore) -> WidgetBoard {
        WidgetBoard(
            id: board.id, name: board.name, dot: board.dot,
            columns: board.columns.map { column in
                // `visibleTasks(in:)` rather than a filter of `tasks`: it is
                // the board's own grouping, so a column's rows here are in the
                // order and under the sort preference the board draws them in.
                let cards = store.visibleTasks(in: column.id)
                return WidgetColumn(
                    id: column.id, name: column.name, short: column.short, dot: column.dot,
                    limit: column.limit,
                    count: cards.count, tasks: rows(cards, in: store)
                )
            }
        )
    }

    /// A saved view, evaluated by the store that owns the rule — never by the
    /// extension. ``WidgetDigest`` says why at length.
    private static func list(
        from view: SavedView, in store: BoardStore, today: CalendarDay
    ) -> WidgetList {
        WidgetList(
            id: view.id, name: view.name, symbol: view.symbol, preset: view.preset?.rawValue,
            // The view's own count, which is capped by its `limit` and is what
            // the sidebar row's pill shows. Taking `members.count` instead
            // would report the eight this digest carries.
            count: store.count(of: view, today: today),
            tasks: rows(store.tasks(in: view, today: today), in: store)
        )
    }

    private static func rows(_ tasks: [TaskItem], in store: BoardStore) -> [WidgetTask] {
        tasks.prefix(WidgetDigest.listLength).map { task in
            WidgetTask(
                id: task.id, title: task.displayTitle, due: task.due, priority: task.priority,
                // Asked of the store: whether a card is finished is a question
                // about its board's last column, or about the Inbox's own
                // completion, and not a field on the card.
                isDone: store.isDone(task)
            )
        }
    }
}
