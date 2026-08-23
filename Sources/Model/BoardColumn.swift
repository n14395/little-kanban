import Foundation

/// One column of the board. `short` is the abbreviated name used by the
/// "move to" segmented control, where horizontal room is tight.
///
/// Columns are board data rather than a fixed set: they are carried in
/// `BoardSnapshot` and can be added, renamed, recoloured, reordered and deleted
/// through `BoardStore`. The statics below are what a board is *seeded* with,
/// and what the v3 → v4 migration maps a legacy string id onto.
///
/// Which is why the seed names are the only ones translated: a name is user
/// content the moment a board exists, and rewriting it under a language change
/// would be editing somebody's board. Seeding is the one moment there is no
/// user content to overwrite.
///
/// **There is nothing here that says what a column is *for*.** Up to v8 there
/// was: a `ColumnRole` of `backlog`, `active` or `done`, stored per column. Two
/// of the three never did anything — nothing in the app branched on `backlog`
/// or `active` — and the third is now answered by position instead. Done is the
/// board's **last** column, always, and `Board.doneColumn` is the only place
/// that is written down. See ``Board/doneColumn`` for why position rather than a
/// stored id.
struct BoardColumn: Identifiable, Hashable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var short: String
    var dot: SwatchColor
}

extension BoardColumn {
    /// Seed column ids are fixed rather than fresh for the same reason
    /// `SeedData`'s task ids are: the migration, the seed and the tests all have
    /// to name the same column, across relaunches and across machines.
    private static func seedID(_ n: UInt8) -> UUID {
        UUID(uuid: (0xC0, 0x1D, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    /// The column the Inbox used to be, kept only so the v3 → v4 step has an
    /// id to map `"inbox"` onto and the v4 → v5 step has one to recognise.
    ///
    /// **It is not a column any more.** Since v5 the Inbox is global and a card
    /// is in it by being on no board at all — see `TaskPlacement`. No board
    /// holds this column, nothing draws it, and a task filed into it would be
    /// unfiled again by `BoardStore` on the way in.
    static let inbox = BoardColumn(
        id: seedID(1), name: Board.inboxName, short: Board.inboxName,
        dot: .ink(opacity: 0.35)
    )

    static let backlog = BoardColumn(
        id: seedID(2),
        name: String(localized: "Backlog", comment: "Seed column: work not started"),
        short: String(localized: "Backlog", comment: "Seed column: work not started"),
        dot: .hex(0xA8A29A)
    )
    static let upNext = BoardColumn(
        id: seedID(3),
        name: String(localized: "Up Next", comment: "Seed column: work queued to start"),
        short: String(localized: "Up Next", comment: "Seed column: work queued to start"),
        dot: .hex(0xC98A16)
    )
    static let inProgress = BoardColumn(
        id: seedID(4),
        name: String(localized: "In Progress", comment: "Seed column: work in flight"),
        short: String(localized: "Doing",
                      comment: "Abbreviated seed column name for the \"move to\" control, where room is tight"),
        dot: .hex(0xC2532F)
    )
    static let done = BoardColumn(
        id: seedID(5),
        name: String(localized: "Done", comment: "Seed column: finished work"),
        short: String(localized: "Done", comment: "Seed column: finished work"),
        dot: .hex(0x1F6F63)
    )

    /// The four workflow columns, in board order — what a fresh board's
    /// `BoardStore.columns` starts as. **Done is last**, which since v9 is what
    /// makes it Done; every starter template in `SeedData` ends the same way.
    static let workflow: [BoardColumn] = [backlog, upNext, inProgress, done]

    /// A Done column with a **fresh id**, for a board being made now.
    ///
    /// The statics above carry fixed ids and two boards may not share a column
    /// id — the store resolves a card's board *from* its column, so a shared id
    /// would put one card on two boards. `SeedData.column(like:)` exists for the
    /// same reason and this is its one-column case, kept here because every
    /// board is created holding this column and `SeedData` is only about
    /// starters.
    static func freshDone() -> BoardColumn {
        BoardColumn(name: done.name, short: done.short, dot: done.dot)
    }

    /// The string ids columns had up to snapshot v3, when there were only ever
    /// these five. The v3 → v4 step maps them; `BoardStore` never sees them.
    static let legacyIDs: [String: BoardColumn.ID] = [
        "inbox": inbox.id,
        "backlog": backlog.id,
        "next": upNext.id,
        "doing": inProgress.id,
        "done": done.id,
    ]
}
