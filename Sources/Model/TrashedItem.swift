import Foundation

/// Something the user threw away, kept for thirty days so they can change their
/// mind about it.
///
/// **Why this exists beside ⌘Z rather than instead of it.** Undo is the answer
/// to "I did not mean that", and it is a better one: it puts the board back
/// exactly, cards and all. It is also gone the moment the app is quit, and it
/// walks backwards — getting a board back that was deleted three edits ago costs
/// the three edits as well. The trash answers the other question, "I meant it at
/// the time and I do not any more", which nothing here used to answer at all.
///
/// **The three things that can be thrown away are not the same shape**, which is
/// what the payload is for. A task is the whole card and comes back whole. A
/// column and a board are containers, and deleting either has never taken its
/// cards with it — a column's cards move to the first column left and a board's
/// go to the global Inbox, each saying so in its own history. So what is kept
/// here is the container, and restoring one brings back the container. The cards
/// were never in danger and are not waiting in here for anybody.
struct TrashedItem: Identifiable, Hashable, Codable, Sendable {
    /// What was thrown away, and enough about where it was to put it back.
    ///
    /// The positions are carried rather than looked up on the way out: a board
    /// restored to the end of the list has visibly moved, and the user did not
    /// move it. They are a *hope* rather than a guarantee — the list will have
    /// changed shape in thirty days — so restoring clamps them.
    enum Contents: Hashable, Codable, Sendable {
        /// A card, with the placement it had. `TaskItem` carries its own board
        /// and column, so there is nothing extra to keep.
        case task(TaskItem)
        /// A column, the board it was on, and where it sat among that board's
        /// columns.
        case column(BoardColumn, boardID: Board.ID, position: Int)
        /// A board and where it sat in the sidebar. Its columns travel inside
        /// it, the way they do everywhere else.
        case board(Board, position: Int)
    }

    /// Which kind of thing this is, without unwrapping the payload — the row
    /// says it, and the sort groups by it.
    enum Kind: String, Hashable, Codable, Sendable, CaseIterable {
        case task, column, board

        var label: String {
            switch self {
            case .task:
                String(localized: "Task", comment: "What kind of thing a trashed item is")
            case .column:
                String(localized: "Column", comment: "What kind of thing a trashed item is")
            case .board:
                String(localized: "Board", comment: "What kind of thing a trashed item is")
            }
        }

        var symbol: String {
            switch self {
            case .task: "square.text.square"
            case .column: "rectangle.split.3x1"
            case .board: "square.grid.2x2"
            }
        }
    }

    /// The trash entry's own id, not the id of what is in it. A task can be
    /// trashed, restored and trashed again, and the two entries are two things
    /// that happened rather than one row that moved.
    var id: UUID = UUID()
    var trashedAt: Date = .now
    var contents: Contents

    /// How long a thrown-away thing is kept. Thirty days, as a count of days
    /// rather than a number of seconds, because the interval is what the user
    /// was promised and calendars are not uniform — see ``expiry(from:)``.
    static let retentionDays = 30

    var kind: Kind {
        switch contents {
        case .task: .task
        case .column: .column
        case .board: .board
        }
    }

    /// What the row calls it. A card with no title of its own is drawn on the
    /// board as "Untitled", and reads the same in here.
    var name: String {
        switch contents {
        case .task(let task): task.displayTitle
        case .column(let column, _, _): column.name
        case .board(let board, _): board.name
        }
    }

    /// The card's code, which is the one thing in the trash a person may have
    /// written down somewhere else. `nil` for the two kinds that have none.
    var code: String? {
        if case .task(let task) = contents { return task.code }
        return nil
    }

    /// When this is thrown away for good, counted in *days* off the calendar
    /// rather than in seconds off the clock: thirty × 86,400 lands an hour out
    /// either side of a daylight-saving boundary, and "kept for 30 days" is a
    /// promise about days.
    ///
    /// Falls back to the arithmetic only if the calendar refuses, which it does
    /// not for an offset this size.
    func expiry(from calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: Self.retentionDays, to: trashedAt)
            ?? trashedAt.addingTimeInterval(TimeInterval(Self.retentionDays) * 86_400)
    }

    /// Whether the thirty days are up. Asked with an explicit `now` so a test
    /// can stand on either side of the boundary without waiting a month.
    func isExpired(at now: Date = .now, calendar: Calendar = .current) -> Bool {
        expiry(from: calendar) <= now
    }

    /// How many days the row has left, counted in **calendar days rather than
    /// elapsed time**, and never below zero. The row says a number of days
    /// rather than a date, because a date is only meaningful measured against
    /// today and what the user is being told is how long they have.
    ///
    /// Measured start-of-day to start-of-day, which is the difference between a
    /// promise and a stopwatch. Elapsed time floors: a card thrown away thirty
    /// seconds ago has 29 days and 23-something hours left on it, so
    /// `dateComponents` reports **29** and the row contradicts the sentence
    /// under the empty list — "kept here for 30 days" — within a minute of the
    /// feature being used for the first time. Counting the days themselves says
    /// 30 today, 29 tomorrow, and 0 on the day it goes, which is what "days
    /// left" means to a person reading it.
    func daysLeft(at now: Date = .now, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let last = calendar.startOfDay(for: expiry(from: calendar))
        return max(0, calendar.dateComponents([.day], from: today, to: last).day ?? 0)
    }
}
