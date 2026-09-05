import Foundation
import Testing
@testable import LittleKanban

/// The chain, asked of every fixture on disk at once.
///
/// `MigrationTests` walks the links one at a time and `BoardTests` /
/// `ColumnTests` each assert one step's output field by field. This suite asks
/// the question those cannot: does *everything* in `Tests/Fixtures/` still come
/// all the way forward, and does it arrive as a board the store can use without
/// repairing it on the way in?
///
/// The fixture list is read out of the bundle rather than written down here, so
/// the fixture somebody adds for v5 → v6 is covered the day it lands.
@Suite struct MigrationChainTests {
    private func load(_ name: String) throws -> BoardLoadResult {
        let temp = TempBoard()
        try temp.put(try Fixture.data(name))
        // The result is read before `temp` goes out of scope and takes the
        // directory with it.
        return temp.file.load()
    }

    /// The `version` the bytes actually declare, which is what the loader has to
    /// route on. Absent means v1 — the shape that predates versioning.
    private func declaredVersion(_ name: String) throws -> Int {
        let object = try JSONSerialization.jsonObject(with: try Fixture.data(name)) as? [String: Any]
        return object?["version"] as? Int ?? 1
    }

    private func movedColumnIDs(_ snapshot: BoardSnapshot) -> [String] {
        snapshot.tasks.flatMap(\.activity).compactMap { entry -> String? in
            guard case .moved(let columnID, _) = entry.kind else { return nil }
            return columnID
        }
    }

    // MARK: Every fixture, all the way forward

    @Test func everyFixtureInTheBundleReachesTheCurrentVersion() throws {
        let names = Fixture.names()
        // A listing that came back empty would make every loop below vacuous.
        #expect(names.count >= 5, "the fixtures did not make it into the test bundle: \(names)")

        for name in names {
            let declared = try declaredVersion(name)
            let expectedMigration: Int? = declared == BoardSnapshot.currentVersion ? nil : declared
            let result = try load(name)
            let snapshot = try #require(result.snapshot, "\(name) did not load")

            #expect(result.failure == nil, "\(name) failed to load")
            #expect(snapshot.version == BoardSnapshot.currentVersion, "\(name) did not reach the current version")
            // Routed to the decoder that wrote it, and only migrated when it
            // had to be: a file already at the current version is left alone.
            #expect(result.migratedFromVersion == expectedMigration,
                    "\(name) was read as version \(String(describing: result.migratedFromVersion)), not \(declared)")

            // One board, made for a file written before there were boards.
            #expect(snapshot.boards.count == 1, "\(name) arrived with \(snapshot.boards.count) boards")
            let board = try #require(snapshot.boards.first)
            #expect(board.name == "Northwind iOS 3.0", "\(name) named its board \(board.name)")
            // The mark the v15 → v16 step deals the first board. A file this old
            // never carried one — see `BoardMigration.migrate(v15:)`, which
            // deals rather than converts, because a colour is not an icon.
            #expect(board.symbol == Board.startingSymbols[0],
                    "\(name) did not come out of the chain with a mark")
            #expect(board.codePrefix == "NW", "\(name) lost the board's code prefix")
            #expect(snapshot.activeBoardID == board.id, "\(name) arrived with no active board")
            #expect(board.columns.isEmpty == false, "\(name) arrived with no columns")
            // One Done column, and it is the **last** — which since v9 is what
            // makes it one. `board-v8-done-adrift` is the fixture that can fail
            // this: it is a v8 file whose Done column sits second, and the step
            // that brings it forward has to move it to the end.
            let done = try #require(board.doneColumn, "\(name) arrived with no Done column")
            #expect(done.name == "Done", "\(name) ends on \(done.name), not its Done column")
            #expect(board.columns.map(\.name) == ["Backlog", "Up Next", "In Progress", "Done"],
                    "\(name) arrived as \(board.columns.map(\.name))")
            // The board is at least as old as the oldest thing on it.
            for task in snapshot.tasks {
                #expect(board.createdAt <= task.createdAt, "\(name): the board is younger than \(task.code)")
            }

            #expect(snapshot.tasks.isEmpty == false, "\(name) arrived with no tasks")
            #expect(Set(snapshot.tasks.map(\.code)).count == snapshot.tasks.count,
                    "\(name) has two cards under one code")
            // The next code it mints is one it has not already handed out.
            let highest = snapshot.tasks.compactMap { BoardSnapshot.serial(ofCode: $0.code) }.max() ?? 0
            #expect(snapshot.nextSerial > highest, "\(name) would mint a code it already carries")

            // Placements: legal, and on the board this file has.
            let known = Set(board.columns.map(\.id))
            for task in snapshot.tasks {
                #expect((task.boardID == nil) == (task.columnID == nil),
                        "\(name): \(task.code) has half a placement")
                if let columnID = task.columnID {
                    #expect(task.boardID == board.id, "\(name): \(task.code) is on a board this file has not got")
                    #expect(known.contains(columnID), "\(name): \(task.code) names a column the board has not got")
                }
            }

            // Nothing in the feed is still naming a column by its pre-v4 string.
            // `reopen` parses these, so one left behind sends a completed card
            // back to Backlog on every migrated board.
            for columnID in movedColumnIDs(snapshot) {
                #expect(UUID(uuidString: columnID) != nil,
                        "\(name): a legacy column id survived in the activity feed: \(columnID)")
                #expect(BoardColumn.legacyIDs[columnID] == nil,
                        "\(name): the v4 step did not run over the activity feed")
            }
        }
    }

    /// Item 4.2's stated acceptance criterion, asked of every fixture: the
    /// tasks are split between the default board and the Inbox rather than all
    /// landing on one side.
    @Test func everyFixtureSplitsItsTasksBetweenTheDefaultBoardAndTheInbox() throws {
        for name in Fixture.names() {
            let snapshot = try #require(try load(name).snapshot, "\(name) did not load")
            let unfiled = snapshot.tasks.filter(\.isUnfiled)
            let filed = snapshot.tasks.filter { !$0.isUnfiled }

            #expect(unfiled.isEmpty == false, "\(name): nothing landed in the Inbox")
            #expect(filed.isEmpty == false, "\(name): nothing landed on the board")
            let boardID = snapshot.boards.first?.id
            let inboxKeptAColumn = unfiled.contains { $0.columnID != nil }
            let filedElsewhere = filed.contains { $0.boardID != boardID }
            // Codes are untouched by the split — an Inbox card keeps the board
            // prefix it was minted under, because somebody may have pasted it
            // into a commit message.
            let renumbered = unfiled.contains { !$0.code.hasPrefix("NW-") }
            #expect(inboxKeptAColumn == false, "\(name): an Inbox card kept a column")
            #expect(filedElsewhere == false, "\(name): a filed card is on the wrong board")
            #expect(renumbered == false, "\(name): an Inbox card was renumbered")
        }
    }

    /// The split named exactly, for the two fixtures whose contents are known
    /// card for card. This is the criterion the item is written around.
    @Test func theV3AndV4FixturesSplitTheirSixCardsTheSameWay() throws {
        for name in ["board-v3", "board-v4"] {
            let snapshot = try #require(try load(name).snapshot, "\(name) did not load")
            let board = try #require(snapshot.boards.first)

            #expect(snapshot.tasks.map(\.code) == [
                "NW-120", "NW-121", "NW-122", "NW-123", "NW-124", "NW-125",
            ], "\(name): the cards are not the ones the fixture holds")
            // The card that was in the old Inbox column is on no board; the
            // other five are on the migrated one, in the columns they were in.
            #expect(snapshot.tasks.map(\.boardID) == [nil] + Array(repeating: board.id, count: 5),
                    "\(name): the board split is wrong")
            #expect(snapshot.tasks.map(\.columnID) == [
                nil, BoardColumn.backlog.id, BoardColumn.backlog.id,
                BoardColumn.upNext.id, BoardColumn.inProgress.id, BoardColumn.done.id,
            ], "\(name): the column split is wrong")
        }
    }

    // MARK: Each link leaves its own mark

    /// A v1 board has to show all four steps ran over it. A skipped link is
    /// otherwise invisible: the file still decodes, and every field it dropped
    /// has a plausible default sitting behind it.
    @Test func everyLinkInTheChainLeavesItsOwnMarkOnAV1Board() throws {
        let snapshot = try #require(try load("board-v1").snapshot)

        // v1 → v2: instants became calendar days, and the rendered English
        // sentences became `.legacy` entries.
        let keptADueDate = snapshot.tasks.contains { $0.due != nil }
        let keptItsProse = snapshot.tasks.flatMap(\.activity).contains {
            if case .legacy = $0.kind { return true }
            return false
        }
        #expect(keptADueDate, "the v1 step did not run: no due date survived")
        #expect(keptItsProse, "the v1 step did not run: no legacy entry")

        // v2 → v3: the archive exists and nothing written before it is in it.
        let inventedAnArchive = snapshot.tasks.contains { $0.archivedAt != nil }
        #expect(inventedAnArchive == false, "the v2 step invented an archive")

        // v3 → v4: the five compiled-in string ids became the seed columns'
        // UUIDs, on the card and inside the feed.
        let board = try #require(snapshot.boards.first)
        #expect(board.columns == BoardColumn.workflow, "the v3 step did not run: no columns")
        let homeless = snapshot.tasks.compactMap(\.columnID).contains { id in
            !BoardColumn.workflow.contains { $0.id == id }
        }
        #expect(homeless == false, "the v3 step did not run: a card names something that is not a column")

        // v4 → v5: a board, an active board, and a card that is on neither.
        #expect(snapshot.activeBoardID == board.id, "the v4 step did not run: no active board")
        let unfiledSomething = snapshot.tasks.contains { $0.isUnfiled }
        #expect(unfiledSomething, "the v4 step did not run: nothing was unfiled")
    }

    /// The same bytes read twice name the same board. The id is fixed rather
    /// than fresh precisely so a file restored from the copy kept beside it
    /// does not arrive as somebody else's board.
    @Test func theSameBytesMigrateToTheSameBoardEveryTime() throws {
        let first = try #require(try load("board-v3").snapshot)
        let second = try #require(try load("board-v3").snapshot)
        #expect(first.boards.map(\.id) == second.boards.map(\.id))
        #expect(first.activeBoardID == second.activeBoardID)
        #expect(first.tasks.map(\.placement) == second.tasks.map(\.placement))
    }

    // MARK: The store adopts a migrated board without repairing it

    /// `BoardStore` puts every set of tasks it adopts back through
    /// `TaskPlacement`, which would quietly paper over a migration that placed a
    /// card badly. Comparing what the store holds with what the migration
    /// produced is what stops that repair from hiding the defect.
    @MainActor
    @Test func noFixtureNeedsRepairingOnTheWayIntoTheStore() throws {
        for name in Fixture.names() {
            let temp = TempBoard()
            try temp.put(try Fixture.data(name))
            let migrated = try #require(temp.file.load().snapshot, "\(name) did not load")
            let store = BoardStore.restored(file: temp.file)

            // Compared by code rather than by identity: the v1 step mints fresh
            // task ids — nothing in a v1 file referred to them — so migrating
            // the same bytes twice legitimately gives two different sets.
            #expect(store.tasks.map(\.code) == migrated.tasks.map(\.code),
                    "\(name)'s cards were reordered or dropped on the way in")
            let asMigrated = Dictionary(uniqueKeysWithValues: migrated.tasks.map { ($0.code, $0.placement) })
            for task in store.tasks {
                #expect(task.placement == asMigrated[task.code],
                        "\(name): \(task.code) had to be repaired on the way in")
            }
            #expect(store.boards == migrated.boards, "\(name)'s boards were not adopted as they arrived")
            #expect(store.activeBoardID == migrated.activeBoardID, "\(name) lost its active board")
            #expect(store.columns == migrated.boards.first?.columns, "\(name) lost its columns")
            let unfiled = migrated.tasks.count { $0.isUnfiled && !$0.isArchived }
            #expect(store.inboxCount == unfiled, "\(name)'s Inbox count disagrees with the file")
        }
    }

    // MARK: The version after this one

    /// Written against `currentVersion + 1` rather than a literal, so the guard
    /// goes on being tested at the boundary after the next schema bump instead
    /// of testing a version that is by then readable.
    @Test func aFileOneVersionNewerThanThisBuildIsRefusedAndPutSomewhereSafe() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(
            BoardSnapshot(version: BoardSnapshot.currentVersion + 1, tasks: TestBoard.tasks,
                          labels: LabelDef.seed, nextSerial: 100)
        )
        let temp = TempBoard()
        try temp.put(bytes)

        let result = temp.file.load()
        #expect(result.snapshot == nil, "a file from a newer build was decoded anyway")
        #expect(result.migratedFromVersion == nil)
        guard case .newerVersion(let version, let quarantinedAt) = result.failure else {
            Issue.record("expected .newerVersion, got \(String(describing: result.failure))")
            return
        }
        #expect(version == BoardSnapshot.currentVersion + 1)
        let moved = try #require(quarantinedAt, "the file was refused but not preserved")
        #expect(try Data(contentsOf: moved) == bytes, "the quarantined bytes are not the file's")
        #expect(temp.exists == false, "the unreadable file is still where a fresh board would be written")
    }

    // MARK: The active board is board data

    /// `activeBoardID` is the one piece of "where the user was" that is saved,
    /// so it has to be *in the bytes* — a store-level round trip would still
    /// pass if the field never reached the file and the fallback happened to
    /// pick the same board.
    @Test func theActiveBoardIsWrittenIntoTheFileItself() throws {
        // Columns of its own, spelled here rather than taken from a helper: a
        // board made in the app has none to start with — see
        // `BoardStore.createBoard` — and this test wants a second board that is
        // *furnished*, so that a file which dropped a board's columns would be
        // caught by the round trip below.
        let second = Board(
            id: UUID(uuid: (0xB0, 0xA4, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 9)),
            name: "Second", symbol: "chart.bar",
            columns: BoardColumn.workflow.map { column in
                var column = column
                column.id = UUID()
                return column
            },
            codePrefix: "SE"
        )
        let temp = TempBoard()
        let written = BoardSnapshot(
            tasks: TestBoard.tasks, boards: SeedData.boards + [second], labels: LabelDef.seed,
            nextSerial: 121, activeBoardID: second.id
        )
        try temp.file.write(written, generation: temp.file.nextWriteGeneration())

        // Named in the JSON, not inferred from the board list — `second` is the
        // *last* board, so a file that dropped the key would fall back to the
        // first one and read as a different board.
        #expect(try temp.text().contains(second.id.uuidString))
        let read = try temp.snapshot()
        #expect(read.activeBoardID == second.id)
        #expect(read.boards == written.boards)
    }
}

/// The eras only real bytes can speak for. Everything from v9 up used to be
/// exercised against snapshots synthesized in memory, which proves the
/// *migration functions* and nothing about the *files*: `version(of:)`'s
/// routing, the current decoder's leniency about each era's missing keys, and
/// `legacyAccent(in:)` — the one function that preserves a user's chosen
/// colour across the v11 → v12 upgrade — all ran for the first time on a real
/// file on some user's disk. These fixtures are those files:
/// `board-v12`…`board-v9` are the current encoder's bytes with each era's
/// keys stripped (which is what the decode chain claims those eras are), and
/// `board-v7` is the v6 fixture plus the trash v7 introduced.
/// `MigrationChainTests` above covers them wholesale the moment they land in
/// the bundle; what is asserted here is each era's own furniture.
@Suite struct EraFixtureTests {
    private func snapshot(_ name: String) throws -> BoardSnapshot {
        let temp = TempBoard()
        try temp.put(try Fixture.data(name))
        return try #require(temp.file.load().snapshot, "\(name) did not load")
    }

    @Test func theV7TrashComesForwardWholeAndOffTheBoard() throws {
        let v7 = try snapshot("board-v7")
        #expect(v7.trash.count == 1)
        if case .task(let task) = v7.trash.first?.contents {
            #expect(task.id == UUID(uuidString: "7E570000-0000-4000-8000-000000000006"))
            #expect(v7.tasks.contains { $0.id == task.id } == false,
                    "a trashed card must not also be on the board")
        } else {
            Issue.record("the v7 trash arrived holding something other than its card")
        }
    }

    /// v9 predates the palette, the editable views and the themes, and chose
    /// pine — the accent whose migration has to *build* themes rather than
    /// fall back to the seed pair.
    @Test func aV9FileArrivesWithDefaultsAndItsPineAccentKept() throws {
        let v9 = try snapshot("board-v9")
        #expect(v9.palette == PaletteSwatch.seed)
        #expect(v9.views == SavedView.seededAll)
        #expect(v9.themes != .seed, "the pine accent should have seeded migrated themes")
    }

    @Test func eachLaterEraKeepsItsOwnFurniture() throws {
        let v10 = try snapshot("board-v10")
        #expect(v10.palette.first?.name == "Fixture Rust")
        #expect(v10.views == SavedView.seededAll)

        let v11 = try snapshot("board-v11")
        #expect(v11.views.first?.name == "Fixture Inbox")
        #expect(v11.themes != .seed, "the v11 pine accent should have seeded migrated themes")

        let v12 = try snapshot("board-v12")
        #expect(v12.palette.first?.name == "Fixture Rust")
        #expect(v12.views.first?.name == "Fixture Inbox")
        #expect(v12.themes != .seed, "v12 themes are file content and must arrive as written")
    }

    /// The v14 step's fixture: a real v13 file, written by a build that had
    /// never heard of WIP limits. Every column has to arrive **unlimited** —
    /// the field is optional and absent, and a step that invented a default
    /// would be a step that put a cap on everybody's board.
    ///
    /// It carries v13's own furniture too, which no other fixture does: an
    /// Inbox card completed where it lies rather than filed onto a board. A
    /// bare stamp is exactly the kind of step that can quietly drop something,
    /// and this is what would notice.
    @Test func aV13FileArrivesWithEveryColumnUnlimited() throws {
        let v13 = try snapshot("board-v13")
        #expect(v13.version == BoardSnapshot.currentVersion)

        let board = try #require(v13.boards.first)
        #expect(board.columns.isEmpty == false)
        #expect(board.columns.allSatisfy { $0.limit == nil },
                "a file written before WIP limits arrived carrying one")

        let completed = try #require(v13.tasks.first { $0.isUnfiled && $0.inboxCompletedAt != nil },
                                     "the v13 Inbox completion did not survive the step to v14")
        #expect(completed.code == "NW-120")
    }

    /// The v15 step's fixture: a real v14 file, written by a build that had
    /// nowhere to record *when* its views, its palette or its themes were last
    /// changed. All three have to arrive **undated** — `nil` rather than a date
    /// this step invented — because that is what makes the first merge between
    /// two upgraded devices keep both sides' work instead of picking one. A
    /// step that stamped `.now` here would hand whichever device launched first
    /// the right to overwrite the other. See ``SharedList``.
    ///
    /// Its WIP limit is carried through as well: v14's own furniture, and a
    /// bare stamp is exactly the kind of step that can quietly drop a field
    /// added by the version before it.
    @Test func aV14FileArrivesWithItsThreeListsUndated() throws {
        let v14 = try snapshot("board-v14")
        #expect(v14.version == BoardSnapshot.currentVersion)

        #expect(v14.viewsChangedAt == nil, "the step invented a date for the saved views")
        #expect(v14.paletteChangedAt == nil, "the step invented a date for the palette")
        #expect(v14.themesChangedAt == nil, "the step invented a date for the themes")

        // And the three lists themselves came across whole, which is what the
        // dates are about in the first place.
        #expect(v14.views.count == 7)
        #expect(v14.palette.count == 6)

        let board = try #require(v14.boards.first)
        #expect(board.columns.contains { $0.limit == 3 }, "v14's own WIP limit was dropped")
    }

    /// The v16 step's fixture: a real v15 file, whose board wears a colour and
    /// has never heard of a mark. It has to arrive wearing one — the first of
    /// ``Board/startingSymbols``, because it is the first board in the file —
    /// and the colour has to be gone rather than carried as a field nothing
    /// draws.
    @Test func aV15FileArrivesWearingAMarkInsteadOfAColour() throws {
        let v15 = try snapshot("board-v15")
        #expect(v15.version == BoardSnapshot.currentVersion)

        let board = try #require(v15.boards.first)
        #expect(board.symbol == Board.startingSymbols[0])
        #expect(SymbolMark.resolved(board.symbol) == board.symbol,
                "the mark it was dealt is not one this system draws")

        // v15's own furniture came across whole. A bare-looking step is exactly
        // the kind that quietly drops a field the version before it added.
        #expect(v15.viewsChangedAt != nil, "v15's own dates were dropped by the step past them")
        #expect(board.columns.contains { $0.limit == 3 }, "v14's WIP limit was dropped")

        // And nothing wrote the colour back out under a name of its own.
        let json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(v15)
        ) as? [String: Any]
        let written = (json?["boards"] as? [[String: Any]])?.first
        #expect(written?["dot"] == nil, "a v16 board still writes a colour")
        #expect(written?["symbol"] as? String == board.symbol)
    }

    /// **Every board is dealt a mark of its own**, cycling once there are more
    /// boards than glyphs — which is what the colours did for a sidebar and the
    /// only part of them worth keeping. A step that gave them all the default
    /// would upgrade a legible sidebar into a column of identical rows.
    @Test func theV16StepDealsEveryBoardAMarkOfItsOwn() {
        var v15 = BoardSnapshot(
            tasks: [], boards: TestBoard.boards, labels: LabelDef.seed,
            nextSerial: BoardSnapshot.baseSerial
        )
        v15.version = 15
        let dealt = BoardSnapshot.migrate(v15: v15).boards.map(\.symbol)
        #expect(dealt == Array(Board.startingSymbols.prefix(dealt.count)))
        #expect(Set(dealt).count == dealt.count, "two boards were dealt one mark")

        // More boards than there are marks: the list wraps rather than running
        // out, because a board with no mark at all is not a state any surface
        // knows how to draw.
        let many = Board.startingSymbols.count + 2
        v15.boards = (0..<many).map { index in
            Board(name: "Board \(index)", columns: [BoardColumn.freshDone()], codePrefix: "B\(index)")
        }
        let wrapped = BoardSnapshot.migrate(v15: v15).boards.map(\.symbol)
        #expect(wrapped.count == many)
        #expect(wrapped.last == Board.startingSymbols[1])
    }

    /// `legacyAccent(in:)` had no test at all — and it is the whole of what
    /// keeps a v11 user's chosen colour across the upgrade that removes the
    /// field it lives in.
    @Test func theLegacyAccentIsReadOutOfTheBytes() {
        func bytes(_ accent: String?) -> Data {
            guard let accent else { return Data(#"{"version": 11}"#.utf8) }
            return Data(#"{"version": 11, "accentTheme": "\#(accent)"}"#.utf8)
        }
        #expect(BoardFile.legacyAccent(in: bytes("ember")) == 0xC2532F)
        #expect(BoardFile.legacyAccent(in: bytes("pine")) == 0x1F6F63)
        #expect(BoardFile.legacyAccent(in: bytes("indigo")) == 0x3B5BA9)
        // `ink` was the theme's own text colour; no hex can mean it.
        #expect(BoardFile.legacyAccent(in: bytes("ink")) == nil)
        #expect(BoardFile.legacyAccent(in: bytes(nil)) == nil)
        #expect(BoardFile.legacyAccent(in: Data("not json".utf8)) == nil)
    }
}
