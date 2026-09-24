// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftData

/// The board as CloudKit sees it: one record per task, sub-task, activity
/// entry, board, column, label and trashed item.
///
/// The granularity is the whole point. A single JSON document is the wrong
/// shape for sync — two devices editing different cards would conflict on the
/// document — whereas per-record storage lets CloudKit merge them without
/// either device losing an edit. Nothing else about the app changes shape:
/// ``BoardStore`` still holds value types and still undoes by snapshot, and
/// these models exist only at the persistence boundary.
///
/// **CloudKit constrains what a schema may say**, and every rule below is one
/// the framework cannot enforce once the data is on a server it does not
/// exclusively own:
///
/// - No `@Attribute(.unique)`. Changes sync concurrently, so uniqueness cannot
///   be guaranteed; ``BoardSyncStore`` deduplicates on the way out instead.
/// - Every relationship is optional, because iCloud does not process
///   relationship changes atomically.
/// - Every inverse is stated explicitly rather than inferred, because CloudKit
///   applies changes in an indeterminate order.
/// - No `.deny` delete rule, which needs a synchronous view of the graph.
/// - Every attribute has a default, so a record written by a build that did not
///   know about a property still decodes.
///
/// A CloudKit schema is **additive only** once promoted to production: a model
/// type cannot be removed and an existing attribute cannot change type. Add
/// rather than alter, and treat this file the way `BoardMigration.swift` treats
/// the JSON shape.
enum SyncSchema {
    /// Every model in the graph, for the container and for the development
    /// schema initialiser.
    static let models: [any PersistentModel.Type] = [
        StoredTask.self,
        StoredSubtask.self,
        StoredActivity.self,
        StoredBoard.self,
        StoredColumn.self,
        StoredLabel.self,
        StoredTrash.self,
        StoredMeta.self,
    ]

    /// The board's ubiquity container. Derived from the bundle identifier the
    /// same way Apple's tooling derives it, so the two cannot drift.
    static let cloudContainerID = "iCloud.com.n14395.LittleKanban"
}

// MARK: - Tasks

@Model
final class StoredTask {
    /// The task's own id, which is also its identity across devices. Not a
    /// `unique` attribute — CloudKit cannot enforce one — so two records may
    /// briefly share it and the reader settles them.
    var id: UUID = UUID()
    var code: String = ""
    var boardID: UUID?
    var columnID: UUID?
    var title: String = ""
    var note: String = ""
    var labelKeys: [String] = []
    /// The due day as `"2026-08-20"` — `CalendarDay.description`, which is also
    /// the form `board.json` carries, and which `CalendarDay(exactly:)` parses
    /// back strictly.
    ///
    /// A `String` rather than the `CalendarDay` itself because SwiftData reads
    /// a `Codable` value's shape from the type and `CalendarDay` encodes
    /// through a *single-value* container: the store allocates for the struct's
    /// three `Int`s and then trips over the string that arrives, which surfaces
    /// as `Could not cast __NSCFNumber to NSString` at read time rather than at
    /// build time. Every value type in this schema is stored as something
    /// CloudKit has natively, for that reason — and it keeps the record legible
    /// in the CloudKit dashboard, which `Data` would not.
    var dueDay: String?
    /// `medium` rather than `Priority.default`, and deliberately: a SwiftData
    /// column default is what a record that arrived *without* the field means,
    /// which is a record written before this field existed — and back then a
    /// card with no priority was a medium one. Every write sets it explicitly.
    /// `BoardMigration` keeps the same distinction for the same reason.
    var priorityKey: String = Priority.medium.rawValue
    var createdAt: Date = Date.distantPast
    /// The field last-writer-wins is decided on. Every mutation advances it.
    var updatedAt: Date = Date.distantPast
    /// The task's place in the board's manual order. SwiftData and CloudKit do
    /// not preserve relationship-array order, so a drag must write it explicitly.
    var position: Int?
    /// Inbox completion is separate from a board's Done-column placement.
    var inboxCompletedAt: Date?
    var archivedAt: Date?
    /// The repeat rule — ``TaskItem/recurrence`` — as JSON, for
    /// `StoredActivity.kind`'s reason: the rule's own decoder is lenient, so
    /// keeping the encoded form means a field this build has never heard of
    /// survives a round trip through a device that knows it. `nil` is the
    /// ordinary, non-repeating kind of card — which is also what a record
    /// written before this attribute existed means.
    ///
    /// **There is no version to refuse on**, exactly as `StoredColumn.limit`
    /// says: a device on an older build reads a repeating card as ordinary and
    /// writes that back if it edits the card. The board *file* is where the
    /// guarantee lives.
    var recurrence: Data?

    /// Owned children, so a deleted card takes its checklist and its history
    /// with it. `.cascade` rather than `.deny`, which CloudKit cannot support.
    @Relationship(deleteRule: .cascade, inverse: \StoredSubtask.task)
    var subtasks: [StoredSubtask]?

    @Relationship(deleteRule: .cascade, inverse: \StoredActivity.task)
    var activity: [StoredActivity]?

    init(id: UUID = UUID()) {
        self.id = id
    }
}

@Model
final class StoredSubtask {
    var id: UUID = UUID()
    var text: String = ""
    var done: Bool = false
    /// Position within the checklist. Held as a number rather than implied by
    /// array order, which CloudKit does not preserve.
    var position: Int = 0
    var task: StoredTask?

    init(id: UUID = UUID()) {
        self.id = id
    }
}

/// One line of history. Append-only, and so the one part of the board that can
/// never conflict: two devices adding entries produce two records and the
/// reader orders them by `when`.
@Model
final class StoredActivity {
    var id: UUID = UUID()
    /// The `ActivityEntry.Kind` as JSON. A `Kind` is an enum with associated
    /// values and its shape is already versioned by `BoardMigration`; keeping
    /// the encoded form means a case this build does not know about survives a
    /// round trip through a device that does.
    var kind: Data = Data()
    var when: Date = Date.distantPast
    var task: StoredTask?

    init(id: UUID = UUID()) {
        self.id = id
    }
}

// MARK: - Boards

@Model
final class StoredBoard {
    var id: UUID = UUID()
    var name: String = ""
    /// **v15's dot, kept and no longer read.**
    ///
    /// A CloudKit schema is additive only, so the attribute stays whatever the
    /// app does with it — the same bargain `StoredColumn.roleKey` struck. This
    /// one is neither read nor *written* any more: a board's mark is a glyph
    /// since v16, there is no colour to derive from one, and leaving the field
    /// untouched means a build from before v16 syncing against this one still
    /// finds the last colour it wrote rather than a board that has gone
    /// colourless.
    var dot: Data?
    /// The SF Symbol the board wears — ``Board/symbol``. A plain attribute
    /// rather than the JSON blob the dot needed: a symbol is a string, which is
    /// a shape both SwiftData and CloudKit lay out on their own.
    ///
    /// **Optional so that "written before there were marks" is a different
    /// answer from "wearing the default one"** — the same distinction
    /// `StoredTask.position` draws, and for the same reason. A record from
    /// before v16 has no mark, the file beside it has the one the migration
    /// dealt, and a defaulted attribute would report the fallback and win:
    /// every board on a synced install would arrive wearing one glyph, which is
    /// exactly what the migration exists to prevent. See
    /// ``BoardSyncStore/hasStoredBoardSymbols()``.
    var symbol: String?
    var createdAt: Date = Date.distantPast
    var codePrefix: String = Board.defaultCodePrefix
    /// Where the board sits in the source list. Same reason as
    /// `StoredSubtask.position`.
    var position: Int = 0
    /// When this *record's* content last changed — the writer's clock, not
    /// the board's, stamped by `BoardSyncStore.applyBoards` only when the
    /// value it is writing differs from its diff base. Duplicate records
    /// under one id used to be settled by `createdAt`, which never moves on
    /// an edit, so two devices holding different copies tied on it forever
    /// and each read kept whichever its fetch happened to return first — a
    /// rename that never converged. Optional so a record written before the
    /// attribute existed says so; the reader falls back to `createdAt` for
    /// those, which is exactly the old rule for exactly the old records.
    var updatedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \StoredColumn.board)
    var columns: [StoredColumn]?

    init(id: UUID = UUID()) {
        self.id = id
    }
}

@Model
final class StoredColumn {
    var id: UUID = UUID()
    var name: String = ""
    var short: String = ""
    /// The column's colour — ``BoardColumn/dot`` — as JSON, for the reason
    /// `StoredLabel.light` is: a `SwatchColor` has no attribute layout
    /// SwiftData can store.
    ///
    /// **Live, unlike `StoredBoard.dot`**, and this pair is easy to read the
    /// wrong way round. A *board* wears a glyph since v16 and its colour is
    /// dead weight; a *column* is still recoloured from board settings, so this
    /// is written on every column (``BoardSyncStore``'s `record.dot =`) and
    /// read back on the way in. Optional because a record written before the
    /// field existed has none, and the reader falls back to the accent.
    var dot: Data?
    /// **v8's `ColumnRole`, kept and no longer read.**
    ///
    /// A CloudKit schema is additive only, so the attribute stays whatever the
    /// app does with it. Nothing decodes it — since v9 a column is the Done one
    /// by being its board's last, see ``Board/doneColumn`` — but
    /// ``BoardSyncStore`` still *writes* it, `"done"` for the last column and
    /// `"backlog"` for the rest, so a build from before v9 syncing against this
    /// one still finds exactly one Done column and finds it in the right place.
    var roleKey: String = "backlog"
    var position: Int = 0
    /// The column's WIP limit — ``BoardColumn/limit`` — or `nil` for none,
    /// which is also what a record written before this attribute existed
    /// decodes as. Optional and defaulted for the reason every attribute here
    /// is: a record written by a build that did not know about a property still
    /// has to decode.
    ///
    /// **There is no version to refuse on.** The board *file* refuses a v13
    /// build outright; a CloudKit record carries no stamp, so a device on an
    /// older build reads a limited column as unlimited and writes that back if
    /// it edits the column. That is the bargain `Priority.max` already made —
    /// see `StoredTask.priorityKey` and the README's v7 → v8 note — and it is
    /// why the guarantee lives in `board.json`.
    var limit: Int?
    var board: StoredBoard?

    init(id: UUID = UUID()) {
        self.id = id
    }
}

@Model
final class StoredLabel {
    /// The label's slug, which is what tasks carry. Not `unique`, for the
    /// reason `StoredTask.id` is not.
    var key: String = ""
    var name: String = ""
    /// The two tone pairs as JSON, for `StoredBoard.dot`'s reason: a
    /// `LabelTone` is two `SwatchColor`s and neither has an attribute layout.
    var light: Data?
    var dark: Data?
    var position: Int = 0
    /// `StoredBoard.updatedAt`'s clock on this record, and even more needed
    /// here: a label had *no* date at all, so duplicate records under one key
    /// were settled purely by fetch order — two devices each kept their own
    /// copy, and a recolour or rename flip-flopped between them forever.
    /// Stamped by `BoardSyncStore.applyLabels` when this record's value moved
    /// against the diff base; `nil` on records older than the attribute,
    /// which the reader treats as "has said nothing since always".
    var updatedAt: Date?

    init(key: String = "") {
        self.key = key
    }
}

// MARK: - The trash

/// One thrown-away thing, so the trash is one bin across every device — see
/// `BoardStore.trash` for what that promise replaced.
///
/// An entry is **written once and never edited**: a ``TrashedItem`` is a thing
/// that happened, not a row that changes, which makes this the simplest record
/// in the schema. Two devices can only ever agree about one — the writer skips
/// a record that already exists — so there is no clock to argue with and no
/// field-level merge to run. What there *is* to decide is deletion: a restore,
/// a by-hand delete, an Empty Trash and the thirty-day sweep all take the row
/// out, and each travels by the same deletion licence a task's does — see
/// ``SyncIDs``.
@Model
final class StoredTrash {
    /// The trash entry's own id — ``TrashedItem/id`` — not the id of what is
    /// inside it, so a card trashed, restored and trashed again is two records
    /// the way it is two entries.
    var id: UUID = UUID()
    /// Unpacked from the payload so the reader can settle duplicate records by
    /// it without decoding every payload first.
    var trashedAt: Date = Date.distantPast
    /// The whole ``TrashedItem`` as JSON, for `StoredActivity.kind`'s reason: a
    /// `Contents` is an enum with associated values, its shape is already
    /// versioned by the board file's own coding, and keeping the encoded form
    /// means an entry kind this build has never heard of survives a round trip
    /// through a device that knows it. A payload this build cannot read is left
    /// out of the value and **kept in the store** — deleting it would throw
    /// away a newer build's trash for good, which is the one thing the trash
    /// exists not to do.
    var payload: Data?

    init(id: UUID = UUID()) {
        self.id = id
    }
}

// MARK: - Board-wide settings

/// The handful of facts that belong to the board rather than to anything on it.
///
/// A single record, found by its fixed id. It is the one place the schema wants
/// a uniqueness guarantee and cannot have one, so two devices that both seed
/// produce two — and ``BoardSyncStore`` settles them by `updatedAt`, exactly as
/// it settles a duplicated task.
@Model
final class StoredMeta {
    var id: UUID = StoredMeta.singletonID
    var nextSerial: Int = BoardSnapshot.baseSerial
    /// ``ThemeSettings`` as JSON, for `StoredBoard.dot`'s reason: a theme is a
    /// tree of structs and none of them has an attribute layout SwiftData can
    /// store. Optional, and read leniently, so a record written by a build
    /// before there were themes syncs into one that has them.
    var themesJSON: Data?
    /// The saved views and the palette, as JSON, for `themesJSON`'s reason: a
    /// `SavedView` carries a rule tree and a `PaletteSwatch` an enum with
    /// associated values, and SwiftData can lay out neither.
    ///
    /// **`nil` is "no device has ever written one"**, which is not the same as
    /// an empty list and must never be read as one: it is what every record
    /// written before this attribute existed says, and the only honest answer
    /// to it is to keep whatever the reading device already has. That mistake
    /// is exactly how a saved view used to be lost on the launch after it was
    /// made — see ``SharedList`` for the rule that replaced the guesswork.
    var viewsJSON: Data?
    var paletteJSON: Data?
    /// When the user last changed each of those three, or `nil` for a list
    /// nobody could date — a record written before these attributes existed,
    /// and a list nobody has touched since. Not `updatedAt`, which moves every
    /// time anything in this record is written and so says nothing about who
    /// last edited a view. See ``BoardSnapshot/viewsChangedAt``.
    var viewsChangedAt: Date?
    var paletteChangedAt: Date?
    var themesChangedAt: Date?
    var activeBoardID: UUID?
    var updatedAt: Date = Date.distantPast

    init(id: UUID = StoredMeta.singletonID) {
        self.id = id
    }

    /// Fixed rather than random so every device looks for the same record. A
    /// second one is a duplicate to be resolved, not a second board.
    static let singletonID = UUID(uuidString: "5EEDDA7A-0000-4000-8000-000000000001")!
}
