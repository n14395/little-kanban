import SwiftUI

/// The placeholder a list surface draws instead of blank space: a symbol, a
/// serif headline, one line of body copy, and — where there is something worth
/// doing — a single button.
///
/// The copy is the point of it. "Nothing here yet" is an invitation and offers
/// to add a task; "nothing matched" is a dead end and offers to drop the query.
/// One sentence written to cover both tells the person with an empty column to
/// check their spelling and the person with a bad search to start typing, so
/// the callers pass their own words rather than choosing from a menu of moods.
///
/// The named cases every surface needs are the static factories below; a caller
/// with copy of its own uses the initialiser directly.
struct EmptyStateView: View {
    struct Metrics {
        var symbol: CGFloat
        var symbolOpacity: Double
        /// Between the symbol and the headline. The text block has its own,
        /// tighter, spacing.
        var symbolSpacing: CGFloat
        var headline: CGFloat
        var message: CGFloat
        var textSpacing: CGFloat
        /// Where the body copy wraps. The desk preset has to sit inside a 272pt
        /// board column as well as the 336pt inspector, so it is sized for the
        /// narrower of the two.
        var maxTextWidth: CGFloat
        var horizontalPadding: CGFloat
        var verticalPadding: CGFloat
        var actionSpacing: CGFloat
        var actionFont: CGFloat
        var actionHorizontalPadding: CGFloat
        var actionVerticalPadding: CGFloat
        var actionRadius: CGFloat
        /// The button's floor. A finger needs 44; the pointer preset claims
        /// nothing, and `frame(minHeight: 0)` is the exact no-op that keeps the
        /// drawn pill the size the design asks for.
        var actionHit: CGFloat

        static let desk = Metrics(
            symbol: 24, symbolOpacity: 0.22, symbolSpacing: 10,
            headline: 17, message: 11.5, textSpacing: 3,
            maxTextWidth: 210, horizontalPadding: 10, verticalPadding: 22,
            actionSpacing: 12, actionFont: 11.5,
            actionHorizontalPadding: 11, actionVerticalPadding: 6, actionRadius: 9,
            actionHit: 0
        )
        static let sheet = Metrics(
            symbol: 32, symbolOpacity: 0.22, symbolSpacing: 12,
            headline: 24, message: 14, textSpacing: 5,
            maxTextWidth: 280, horizontalPadding: 20, verticalPadding: 44,
            actionSpacing: 16, actionFont: 14.5,
            actionHorizontalPadding: 16, actionVerticalPadding: 10, actionRadius: 12,
            actionHit: 44
        )
    }

    @Environment(\.palette) private var palette

    let symbol: String
    let headline: String
    let message: String
    /// Both or neither: a button with no action is a lie, and an action with no
    /// name is invisible.
    var actionTitle: String?
    var action: (() -> Void)?
    /// Last so a caller can hand the action in as a trailing closure.
    var metrics: Metrics = .desk

    var body: some View {
        VStack(spacing: metrics.actionSpacing) {
            VStack(spacing: metrics.textSpacing) {
                Image(systemName: symbol)
                    .font(SimpleKanbanFont.ui(metrics.symbol, .medium, relativeTo: .title2))
                    .foregroundStyle(palette.ink(metrics.symbolOpacity))
                    .padding(.bottom, metrics.symbolSpacing)

                Text(headline)
                    .font(SimpleKanbanFont.serif(metrics.headline))
                    .foregroundStyle(palette.ink(0.75))

                Text(message)
                    .font(SimpleKanbanFont.ui(metrics.message, .medium, relativeTo: .footnote))
                    .foregroundStyle(palette.inkText(0.45))
                    .lineSpacing(2)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: metrics.maxTextWidth)
            // One sentence to VoiceOver rather than three fragments — and, more
            // to the point, no symbol. `.combine` left the glyph published as a
            // sibling under Apple's catalogue name, so an empty Backlog drew
            // `tray` and announced an element called "Inbox", which is a word
            // from a different part of the app entirely; `.accessibilityHidden`
            // on the image did not remove it either. Substituting the subtree
            // outright is what works, as it was for the drawer's rows.
            .accessibilityRepresentation {
                Text(verbatim: "\(headline). \(message)")
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(SimpleKanbanFont.ui(metrics.actionFont, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, metrics.actionHorizontalPadding)
                        .padding(.vertical, metrics.actionVerticalPadding)
                        .background(palette.accentSoft, in: .rect(cornerRadius: metrics.actionRadius))
                        // Outside the fill, so the target grows and the pill does
                        // not — see README's Touch targets.
                        .frame(minHeight: metrics.actionHit)
                }
                .buttonStyle(.bare)
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(maxWidth: .infinity)
    }
}

/// The cases both platforms need, so the wording of each is written once.
///
/// Most of them offer no button, and the ones that do are not offering the same
/// kind of thing: an empty place offers to fill it, an empty *result* offers to
/// stop filtering, and a board with no columns offers a column, because a card
/// has nowhere to go until there is one. A saved view gets nothing — it is a
/// filter over the board rather than somewhere a card can be put, so "add a
/// task" there would add it somewhere else.
extension EmptyStateView {
    /// A board column with no cards in it.
    static func column(
        _ column: BoardColumn, metrics: Metrics = .desk, add: (() -> Void)? = nil
    ) -> EmptyStateView {
        EmptyStateView(
            symbol: "tray",
            headline: String(localized: "Nothing in \(column.name)",
                             comment: "Empty state headline for a board column with no cards"),
            message: String(localized: "Drag a card here, or start one.",
                            comment: "Empty state body copy for a board column with no cards"),
            actionTitle: add == nil ? nil : Self.addTitle,
            action: add,
            metrics: metrics
        )
    }

    /// A board with no columns at all — which is what every board made from now
    /// on starts as, and what the seed board would be if its columns were
    /// deleted (they cannot be; see `BoardStore.deleteColumn`).
    ///
    /// The one empty state whose offer is not a card. A board with no columns
    /// has nowhere to put one, so "add a task" would either be dead or file the
    /// card somewhere the reader is not looking; the way out of a blank board is
    /// a column.
    static func noColumns(metrics: Metrics = .desk, add: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            symbol: "rectangle.split.3x1",
            headline: String(localized: "No columns yet",
                             comment: "Empty state headline for a board that has no columns"),
            message: String(localized: "A board is its columns — Backlog, Doing, Done, or whatever this one needs. Add the first and cards can go in it.",
                            comment: "Empty state body copy for a board that has no columns"),
            actionTitle: add == nil
                ? nil
                : String(localized: "Add a column",
                         comment: "Empty state button that starts the first column on a board"),
            action: add,
            metrics: metrics
        )
    }

    /// Every column empty at once — a new install, or one the user has cleared.
    static func board(metrics: Metrics = .desk, add: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            symbol: "square.stack.3d.up",
            headline: String(localized: "This board is empty",
                             comment: "Empty state headline for a board with no tasks at all"),
            message: String(localized: "Start with one thing you have to do today. Cards move between columns by dragging.",
                            comment: "Empty state body copy for a board with no tasks at all"),
            actionTitle: add == nil ? nil : Self.addTitle,
            action: add,
            metrics: metrics
        )
    }

    /// A query that found nothing. The one state whose way out is backwards.
    static func noResults(
        query: String, metrics: Metrics = .desk, clear: @escaping () -> Void
    ) -> EmptyStateView {
        EmptyStateView(
            symbol: "magnifyingglass",
            headline: String(localized: "No matches",
                             comment: "Empty state headline when a search finds nothing"),
            message: query.isEmpty
                ? String(localized: "Nothing here matches your search.",
                         comment: "Empty state body copy when a search finds nothing")
                : String(localized: "Nothing here matches “\(query)”.",
                         comment: "Empty state body copy naming the search that found nothing"),
            actionTitle: String(localized: "Clear search",
                                comment: "Empty state button that drops the search query"),
            action: clear,
            metrics: metrics
        )
    }

    /// A saved view whose predicate matched nothing. Each says what would land
    /// in it, because "no results" here is usually good news and always means
    /// something different from the last one.
    static func savedView(_ view: SavedView, metrics: Metrics = .desk) -> EmptyStateView {
        EmptyStateView(
            symbol: view.symbol,
            headline: headline(for: view),
            message: message(for: view),
            metrics: metrics
        )
    }

    /// The phone's Inbox tab with nothing captured.
    static func inbox(metrics: Metrics = .sheet, add: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            symbol: "tray",
            headline: Self.inboxHeadline,
            message: Self.inboxMessage,
            actionTitle: add == nil ? nil : Self.addTitle,
            action: add,
            metrics: metrics
        )
    }

    /// The macOS inspector with no card selected. It has no action because the
    /// action is on the board: the panel is waiting to be pointed at something.
    static func noSelection(metrics: Metrics = .desk) -> EmptyStateView {
        EmptyStateView(
            symbol: "sidebar.right",
            headline: String(localized: "No task selected",
                             comment: "Empty macOS inspector headline"),
            message: String(localized: "Pick a card to read its description, dates, checklist and history here.",
                            comment: "Empty macOS inspector body copy"),
            metrics: metrics
        )
    }

    /// No boards at all, which the user reaches by deleting the last one. Not a
    /// dead end and not an error: the Inbox is global, so everything those
    /// boards held is still there, and a new board is one tap away.
    static func noBoards(metrics: Metrics = .desk, add: (() -> Void)? = nil) -> EmptyStateView {
        EmptyStateView(
            symbol: "square.stack.3d.up.slash",
            headline: String(localized: "No boards",
                             comment: "Empty state headline when every board has been deleted"),
            message: String(localized: "Everything you had is waiting in the Inbox. Make a board to file it onto.",
                            comment: "Empty state body copy when every board has been deleted"),
            actionTitle: add == nil ? nil : String(localized: "New board",
                                                   comment: "Empty state button that creates a board"),
            action: add,
            metrics: metrics
        )
    }

    private static var addTitle: String {
        String(localized: "Add a task", comment: "Empty state button that starts a new task")
    }

    /// The Inbox is empty in three places now — the panel beside the board, the
    /// saved view in the source list and the phone's tab — and an empty Inbox
    /// is the same fact in all three. Said once so the three cannot drift into
    /// three different sentences about one state.
    private static var inboxHeadline: String {
        String(localized: "Inbox is clear", comment: "Empty state headline for the Inbox")
    }

    private static var inboxMessage: String {
        String(localized: "Everything captured has been filed onto a board.",
               comment: "Empty state body copy for the Inbox")
    }

    private static func headline(for view: SavedView) -> String {
        switch view {
        case .inbox:
            Self.inboxHeadline
        case .today:
            String(localized: "Nothing due today", comment: "Empty Today view headline")
        case .upcoming:
            String(localized: "Nothing coming up", comment: "Empty Upcoming view headline")
        case .highPriority:
            String(localized: "No high-priority work", comment: "Empty High priority view headline")
        case .dueThisWeek:
            String(localized: "Nothing due this week", comment: "Empty Due this week view headline")
        case .recentlyUpdated:
            String(localized: "Nothing has changed yet", comment: "Empty Recently updated view headline")
        case .archive:
            String(localized: "Nothing archived", comment: "Empty Archive view headline")
        }
    }

    private static func message(for view: SavedView) -> String {
        switch view {
        case .inbox:
            Self.inboxMessage
        case .today:
            String(localized: "Nothing is due today, and nothing has slipped past its date.",
                   comment: "Empty Today view body copy")
        case .upcoming:
            String(localized: "No task on the board is dated beyond today.",
                   comment: "Empty Upcoming view body copy")
        case .highPriority:
            String(localized: "Nothing on the board is marked high priority.",
                   comment: "Empty High priority view body copy")
        case .dueThisWeek:
            String(localized: "Nothing falls in the next seven days.",
                   comment: "Empty Due this week view body copy")
        case .recentlyUpdated:
            String(localized: "Edit a card and it will show up here.",
                   comment: "Empty Recently updated view body copy")
        case .archive:
            String(localized: "Work you file away from the board waits here.",
                   comment: "Empty Archive view body copy")
        }
    }
}
