// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

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
/// *column* is a container whose cards are not thrown away with it — they move
/// to the first column left, saying so in their own history — so what is kept
/// is the column alone. A **board** takes its cards with it: throwing one away
/// is throwing away the work on it, and the cards ride inside the entry so that
/// one Restore brings back the board, its columns and everything that was on
/// them.
///
/// **The board used to scatter its cards into the Inbox** and keep only itself
/// in here. That made "Trash Board" a move dressed as a delete: a board with
/// forty cards on it left forty loose cards behind, and Restore could not put
/// the board back the way it was because the cards were no longer its to give.
struct TrashedItem: Identifiable, Hashable, Codable, Sendable {
    /// What was thrown away, and enough about where it was to put it back.
    ///
    /// The positions are carried rather than looked up on the way out: a board
    /// restored to the end of the list has visibly moved, and the user did not
    /// move it. They are a *hope* rather than a guarantee — the list will have
    /// changed shape in thirty days — so restoring clamps them.
    enum Contents: Hashable, Sendable {
        /// A card, with the placement it had. `TaskItem` carries its own board
        /// and column, so there is nothing extra to keep.
        case task(TaskItem)
        /// A column, the board it was on, and where it sat among that board's
        /// columns. Its cards are not in here — see the note above.
        case column(BoardColumn, boardID: Board.ID, position: Int)
        /// A board, where it sat in the sidebar, and every card that was on it —
        /// archived ones included. Its columns travel inside it, the way they do
        /// everywhere else; the cards travel beside it because they are stored
        /// beside it, in `BoardStore.tasks`, rather than within.
        case board(Board, position: Int, tasks: [TaskItem])
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
    /// What the Trash keeps things for when nobody has said otherwise. The
    /// setting is ``TrashRetention``; this is its `.month`.
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
        case .board(let board, _, _): board.name
        }
    }

    /// The card's code, which is the one thing in the trash a person may have
    /// written down somewhere else. `nil` for the two kinds that have none.
    var code: String? {
        if case .task(let task) = contents { return task.code }
        return nil
    }

    /// How many cards come back with this row, which is only ever a board's.
    ///
    /// The row says it because Restore is a promise about them: a board that
    /// went in with forty cards has to be visibly the thing that brings forty
    /// back, and a person deciding whether to empty the trash is deciding about
    /// the cards rather than about the board's name. Zero for the other two
    /// kinds, and for a board trashed before the cards travelled with it.
    var taskCount: Int {
        if case .board(_, _, let tasks) = contents { return tasks.count }
        return 0
    }

    /// When this is thrown away for good, counted in *days* off the calendar
    /// rather than in seconds off the clock: thirty × 86,400 lands an hour out
    /// either side of a daylight-saving boundary, and "kept for 30 days" is a
    /// promise about days.
    ///
    /// Falls back to the arithmetic only if the calendar refuses, which it does
    /// not for an offset this size.
    /// `days` is a **setting** now — see ``TrashRetention`` — and is passed in
    /// rather than read here: this type is decoded off the main actor inside
    /// `BoardFile`, and a model that reaches for app-global state makes the
    /// same bytes mean different things on two machines. `retentionDays` is
    /// still the default, so a caller that has no opinion gets the promise the
    /// empty list makes.
    func expiry(from calendar: Calendar = .current, days: Int = TrashedItem.retentionDays) -> Date {
        calendar.date(byAdding: .day, value: days, to: trashedAt)
            ?? trashedAt.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    /// Whether the days are up. Asked with an explicit `now` so a test can
    /// stand on either side of the boundary without waiting a month.
    func isExpired(
        at now: Date = .now, calendar: Calendar = .current, days: Int = TrashedItem.retentionDays
    ) -> Bool {
        expiry(from: calendar, days: days) <= now
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
    func daysLeft(
        at now: Date = .now, calendar: Calendar = .current, days: Int = TrashedItem.retentionDays
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let last = calendar.startOfDay(for: expiry(from: calendar, days: days))
        return max(0, calendar.dateComponents([.day], from: today, to: last).day ?? 0)
    }
}

/// Written out rather than synthesised, for one key.
///
/// **Board files already on disk carry boards with no cards beside them.** The
/// synthesised conformance spelled this enum as `{"board": {"_0": …,
/// "position": 3}}`, and adding an associated value to a case adds a key the
/// synthesised *decoder* then demands — so every board trashed before the cards
/// travelled with it would fail to read, and a board file is quarantined whole
/// when any part of it will not. What is below is byte for byte what the
/// compiler was writing, `tasks` apart.
///
/// **Only `tasks` is lenient**, and its absence says something true about those
/// older entries rather than papering over them: that board's cards went to the
/// Inbox when it was trashed, they are still there, and restoring it now brings
/// back the board alone. Everything else stays strict, for the reason
/// `BoardSnapshot` gives about its own keys — a `position` that has gone
/// missing is not a zero, it is a damaged file, and reading it as a zero would
/// put a board at the top of somebody's sidebar and call that a restore.
extension TrashedItem.Contents: Codable {
    private enum CodingKeys: String, CodingKey { case task, column, board }
    private enum TaskKeys: String, CodingKey { case _0 }
    private enum ColumnKeys: String, CodingKey { case _0, boardID, position }
    private enum BoardKeys: String, CodingKey { case _0, position, tasks }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.task) {
            let nested = try container.nestedContainer(keyedBy: TaskKeys.self, forKey: .task)
            self = .task(try nested.decode(TaskItem.self, forKey: ._0))
        } else if container.contains(.column) {
            let nested = try container.nestedContainer(keyedBy: ColumnKeys.self, forKey: .column)
            self = .column(
                try nested.decode(BoardColumn.self, forKey: ._0),
                boardID: try nested.decode(Board.ID.self, forKey: .boardID),
                position: try nested.decode(Int.self, forKey: .position)
            )
        } else if container.contains(.board) {
            let nested = try container.nestedContainer(keyedBy: BoardKeys.self, forKey: .board)
            self = .board(
                try nested.decode(Board.self, forKey: ._0),
                position: try nested.decode(Int.self, forKey: .position),
                tasks: try nested.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
            )
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "a trashed item that is not a task, a column or a board"
                )
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .task(let task):
            var nested = container.nestedContainer(keyedBy: TaskKeys.self, forKey: .task)
            try nested.encode(task, forKey: ._0)
        case .column(let column, let boardID, let position):
            var nested = container.nestedContainer(keyedBy: ColumnKeys.self, forKey: .column)
            try nested.encode(column, forKey: ._0)
            try nested.encode(boardID, forKey: .boardID)
            try nested.encode(position, forKey: .position)
        case .board(let board, let position, let tasks):
            var nested = container.nestedContainer(keyedBy: BoardKeys.self, forKey: .board)
            try nested.encode(board, forKey: ._0)
            try nested.encode(position, forKey: .position)
            try nested.encode(tasks, forKey: .tasks)
        }
    }
}
