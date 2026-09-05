import Foundation
import Testing
@testable import LittleKanban

/// Everything about the board file. A bug here loses the user's work, so the
/// v1 fixtures are checked field by field rather than merely "it decoded", and
/// each unusable file is checked to have been moved aside before the fresh
/// board is allowed anywhere near the disk.
@Suite struct PersistenceTests {
    private func encode(_ snapshot: BoardSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    // MARK: v3 round trip

    @Test func everyFieldSurvivesAWriteAndARead() throws {
        let temp = TempBoard()
        var task = TestBoard.tasks[1]
        task.activity = TestBoard.everyActivityKind.enumerated().map { index, kind in
            ActivityEntry(id: TestBoard.entryID(UInt8(100 + index)), kind, when: TestBoard.at(index * 60))
        }
        // One of them filed away, so `archivedAt` is a field this covers too —
        // and the rest still absent, which is what keeps an unarchived v3 board
        // byte-identical to the v2 one it replaces.
        var filed = TestBoard.tasks[5]
        filed.archivedAt = TestBoard.at(90)
        var completedInbox = TestBoard.tasks[0]
        completedInbox.placement = .inbox
        completedInbox.inboxCompletedAt = TestBoard.at(120)
        let written = BoardSnapshot(
            tasks: [completedInbox, task] + TestBoard.tasks[2..<5] + [filed],
            labels: LabelDef.seed,
            nextSerial: 137,
            themes: TestBoard.otherThemes
        )
        try temp.file.write(written, generation: temp.file.nextWriteGeneration())

        let result = temp.file.load()
        let read = try #require(result.snapshot)
        #expect(result.failure == nil)
        #expect(result.migratedFromVersion == nil)
        #expect(read.version == BoardSnapshot.currentVersion)
        #expect(read.nextSerial == 137)
        #expect(read.themes == TestBoard.otherThemes)
        #expect(read.labels == LabelDef.seed)
        #expect(read.tasks == written.tasks)
        // Looked up by id rather than by index. It was `read.tasks[0]`, and
        // `tasks[0]` stopped being the card carrying the activity the day
        // `completedInbox` was written in front of it — so the assertion moved
        // to a card with one entry on it and passed for years by reading
        // nothing. An index into a fixture is a claim about the fixture's
        // *order*, which is not what any of this is about.
        let readTask = try #require(read.tasks.first { $0.id == task.id })
        #expect(readTask.activity.map(\.kind) == TestBoard.everyActivityKind)
        #expect(read.tasks.last?.archivedAt == TestBoard.at(90))
        #expect(read.tasks.dropLast().allSatisfy { $0.archivedAt == nil })
        #expect(read.tasks.first?.inboxCompletedAt == TestBoard.at(120))
    }

    @Test func aDueDateIsStoredAsAReadableDay() throws {
        let temp = TempBoard()
        let snapshot = BoardSnapshot(tasks: TestBoard.tasks, labels: LabelDef.seed,
                                     nextSerial: 100)
        try temp.file.write(snapshot, generation: temp.file.nextWriteGeneration())
        #expect(try temp.text().contains("\"due\" : \"2026-08-20\""))
    }

    // MARK: v1 migration

    @Test func theV1FixtureStillLoads() throws {
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v1"))
        let result = temp.file.load()
        let snapshot = try #require(result.snapshot)

        #expect(result.migratedFromVersion == 1)
        #expect(result.failure == nil)
        #expect(snapshot.version == BoardSnapshot.currentVersion)
        // The fixture chose Pine, which is not any of the twenty themes' accent,
        // so the v12 step carries it across on a copy of each default rather
        // than repainting a board that has been green since v1. See
        // `BoardMigration.migrate(v11:accent:)`.
        #expect(snapshot.themes.custom.count == 2)
        #expect(snapshot.themes.custom.allSatisfy { $0.highlight.accent.hex == 0x1F6F63 })
        #expect(snapshot.themes.theme(for: .dark).highlight.accent.hex == 0x1F6F63)
        #expect(snapshot.themes.theme(for: .light).highlight.accent.hex == 0x1F6F63)
        #expect(snapshot.nextSerial == 100)
        #expect(snapshot.labels.map(\.key) == ["design", "ios", "api", "bug", "polish", "release-1-2"])
        #expect(snapshot.labels.last?.name == "Release 1.2")
        #expect(snapshot.tasks.map(\.code) == ["NW-136", "NW-118", "NW-104", "NW-113", "NW-90"])
        // The card that was in the Inbox column is unfiled — since v5 the
        // Inbox is global and is not a column at all.
        #expect(snapshot.tasks.map(\.columnID) == [
            nil, BoardColumn.inProgress.id, BoardColumn.upNext.id,
            BoardColumn.backlog.id, BoardColumn.done.id,
        ])
        #expect(snapshot.tasks.map(\.priority) == [.medium, .high, .high, .low, .medium])
        #expect(snapshot.tasks.map(\.labelKeys) == [[], ["ios", "design"], ["api", "release-1-2"], ["bug"], ["design", "polish"]])

        let dragDrop = snapshot.tasks[1]
        #expect(dragDrop.title == "Drag-and-drop between columns")
        #expect(dragDrop.note == "Card follows the pointer with a lifted shadow; columns highlight on hover.")
        // The v1 instant 777337200 is a day in the reader's own calendar.
        #expect(dragDrop.due == CalendarDay(Date(timeIntervalSinceReferenceDate: 777_337_200)))
        #expect(dragDrop.subtasks.map(\.text) == ["Lift + shadow states", "Column drop targets", "Keyboard fallback"])
        #expect(dragDrop.subtasks.map(\.done) == [true, true, false])
        // Sub-task and activity ids are carried across, so a migration whose
        // save never lands cannot re-identify the feed on the next launch.
        #expect(dragDrop.subtasks[0].id == UUID(uuidString: "B1000000-0000-4000-8000-000000000001"))
        #expect(dragDrop.activity.map(\.id) == [
            UUID(uuidString: "A1000000-0000-4000-8000-000000000002"),
            UUID(uuidString: "A1000000-0000-4000-8000-000000000003"),
            UUID(uuidString: "A1000000-0000-4000-8000-000000000004"),
        ])
        #expect(dragDrop.activity.map(\.kind) == [
            .legacy("Moved to In Progress"),
            .legacy("Comment added on spacing"),
            .legacy("Created"),
        ])
        // The 3.3 timestamps are backfilled from the only evidence v1 carries.
        #expect(dragDrop.createdAt == Date(timeIntervalSinceReferenceDate: 776_593_800))
        #expect(dragDrop.updatedAt == Date(timeIntervalSinceReferenceDate: 777_310_882))

        #expect(snapshot.tasks[0].due == nil)
        #expect(snapshot.tasks[0].subtasks.isEmpty)
        #expect(Set(snapshot.tasks.map(\.id)).count == 5)      // fresh ids, all distinct
    }

    @Test func theMintedV1FixtureKeepsItsSerialAboveItsOwnCodes() throws {
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v1-minted"))
        let snapshot = try #require(temp.file.load().snapshot)

        #expect(snapshot.tasks.count == 8)
        #expect(snapshot.tasks.suffix(3).map(\.code) == ["NW-140", "NW-141", "NW-142"])
        // NW-142 is the last code minted, so the next one must be NW-143.
        #expect(BoardSnapshot.code(forSerial: snapshot.nextSerial) == "NW-143")
        #expect(snapshot.nextSerial == 103)
        #expect(snapshot.tasks.last?.subtasks.map(\.done) == [true, false])
        #expect(snapshot.tasks.last?.activity.first?.kind == .legacy("Moved to In Progress"))
    }

    @Test func aSerialThatHasFallenBehindItsCodesIsRaised() throws {
        // A hand-edited or truncated file: minting from 100 would hand out
        // NW-140 a second time.
        let temp = TempBoard()
        var object = try #require(try JSONSerialization.jsonObject(with: try Fixture.data("board-v1-minted")) as? [String: Any])
        object["nextSerial"] = 42
        try temp.put(try JSONSerialization.data(withJSONObject: object))
        let snapshot = try #require(temp.file.load().snapshot)
        #expect(BoardSnapshot.code(forSerial: snapshot.nextSerial) == "NW-143")
    }

    @Test func aBoardWithNoVersionAtAllIsReadAsV1() throws {
        // Versioning was added *to* v1, so the oldest boards on disk carry no
        // `version` key. The absent key has to mean 1: reading it as the current
        // version decodes a shape that file never wrote, which fails, which
        // quarantines the board and hands the user an empty one.
        let temp = TempBoard()
        var object = try #require(try JSONSerialization.jsonObject(with: try Fixture.data("board-v1")) as? [String: Any])
        object.removeValue(forKey: "version")
        try temp.put(try JSONSerialization.data(withJSONObject: object))

        let result = temp.file.load()
        let snapshot = try #require(result.snapshot)
        #expect(result.failure == nil)
        #expect(temp.siblings().contains { $0.hasPrefix("board.corrupt-") } == false)
        #expect(result.migratedFromVersion == 1)
        #expect(snapshot.version == BoardSnapshot.currentVersion)
        #expect(snapshot.tasks.map(\.code) == ["NW-136", "NW-118", "NW-104", "NW-113", "NW-90"])
        #expect(snapshot.nextSerial == 100)
    }

    @Test func migratingKeepsThePreMigrationBytes() throws {
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v1"))
        _ = temp.file.load()
        #expect(temp.siblings().contains { $0.hasPrefix("board.v1-") })
        #expect(temp.exists)      // the board itself is untouched until it is saved
    }

    // MARK: Files that cannot be used

    @Test func corruptJSONFallsBackAndIsMovedAside() throws {
        let temp = TempBoard()
        try temp.put("{ this is not a board")
        let result = temp.file.load()

        #expect(result.snapshot == nil)
        guard case .unreadable(let quarantinedAt) = result.failure else {
            Issue.record("expected .unreadable, got \(String(describing: result.failure))")
            return
        }
        let moved = try #require(quarantinedAt)
        #expect(moved.lastPathComponent.hasPrefix("board.corrupt-"))
        #expect(FileManager.default.fileExists(atPath: moved.path(percentEncoded: false)))
        #expect(temp.exists == false)      // nothing is left at the board's URL to be written over
    }

    @Test func truncatedJSONFallsBackAndIsMovedAside() throws {
        let temp = TempBoard()
        let whole = try encode(BoardSnapshot(tasks: TestBoard.tasks, labels: LabelDef.seed,
                                             nextSerial: 100))
        try temp.put(whole.prefix(whole.count / 2))
        let result = temp.file.load()
        #expect(result.snapshot == nil)
        guard case .unreadable(let quarantinedAt) = result.failure else {
            Issue.record("expected .unreadable, got \(String(describing: result.failure))")
            return
        }
        #expect(quarantinedAt != nil)
        #expect(temp.exists == false)
    }

    @Test func validJSONOfTheWrongShapeIsNotABoard() throws {
        let temp = TempBoard()
        try temp.put(#"{ "version": 2, "tasks": "not an array" }"#)
        guard case .unreadable = temp.file.load().failure else {
            Issue.record("a board-shaped file it is not should not decode")
            return
        }
        try temp.put("[1, 2, 3]")
        guard case .unreadable = temp.file.load().failure else {
            Issue.record("a top-level array should not decode")
            return
        }
    }

    @Test func aFileFromANewerBuildIsNotGuessedAt() throws {
        let temp = TempBoard()
        try temp.put(#"{ "version": 99, "tasks": [], "labels": [], "nextSerial": 100, "accentTheme": "ember" }"#)
        let result = temp.file.load()
        #expect(result.snapshot == nil)
        guard case .newerVersion(let version, let quarantinedAt) = result.failure else {
            Issue.record("expected .newerVersion, got \(String(describing: result.failure))")
            return
        }
        #expect(version == 99)
        let moved = try #require(quarantinedAt)
        #expect(moved.lastPathComponent.hasPrefix("board.from-newer-version-99-"))
        #expect(temp.exists == false)
    }

    @Test func aBoardThatWasNeverSavedIsNotAFailure() {
        let temp = TempBoard()
        let result = temp.file.load()
        #expect(result.snapshot == nil)
        #expect(result.failure == nil)
        #expect(result.migratedFromVersion == nil)
        #expect(temp.siblings().isEmpty)       // no quarantine copy of a file that never existed
    }

    // MARK: The store's side of it

    @MainActor
    @Test func aStoreOverAnUnreadableFileSaysSoAndKeepsSaving() throws {
        let temp = TempBoard()
        try temp.put("{ this is not a board")
        let store = BoardStore.restored(file: temp.file)

        #expect(store.loadFailure != nil)
        #expect(store.lastError != nil)
        #expect(store.quarantinedBoardURL != nil)
        // The original was moved aside, so writing over the board's URL is safe.
        #expect(store.isSaveBlocked == false)
        store.saveNow()
        #expect(store.lastSavedAt != nil)

        store.acknowledgeLoadFailure()
        #expect(store.loadFailure == nil)
        #expect(store.lastError == nil)
    }

    /// The other arm: when the unreadable file cannot even be moved aside —
    /// here, a directory nothing can write into — writing stops to protect it,
    /// and **only** writing. The record store is not the file being protected,
    /// and a blocked session's edits exist nowhere else, so the sync follower
    /// keeps running; off the test host the reminders, the Spotlight index and
    /// the widgets ride the same funnel. The old behaviour returned before all
    /// of them, and a blocked session's work died with the quit.
    @MainActor
    @Test func aBlockedSaveStillReachesTheRecords() throws {
        let temp = TempBoard()
        try temp.put("{ this is not a board")
        let manager = FileManager.default
        let directory = temp.file.url.deletingLastPathComponent().path(percentEncoded: false)
        try manager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory)
        defer { try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory) }

        let sync = try BoardSyncStore.inMemory()
        let store = BoardStore.restored(file: temp.file, sync: sync)
        #expect(store.isSaveBlocked,
                "the read-only directory should have kept the quarantine from moving the file aside")

        store.addTask(to: .inbox, title: "Made while saving is paused")
        store.saveNow()

        #expect(store.isSaveBlocked, "a blocked save must stay blocked until the user acknowledges")
        let records = try #require(try sync.load())
        #expect(records.tasks.contains { $0.title == "Made while saving is paused" },
                "a blocked file write must not block the record store")
        // The protected file holds exactly the bytes it was being protected for.
        #expect(try String(contentsOf: temp.file.url, encoding: .utf8) == "{ this is not a board")
    }

    @MainActor
    @Test func serialsKeepClimbingAcrossSessions() throws {
        let temp = TempBoard()
        let first = TestBoard.store(file: temp.file)
        // Into the Inbox, so the codes carry its constant prefix rather than a
        // board's — the serial underneath them is the file's either way.
        let a = first.addTask(to: .inbox, title: "One")
        let b = first.addTask(to: .inbox, title: "Two")
        #expect(first[a]?.code == "IN-140")
        #expect(first[b]?.code == "IN-141")
        first.saveNow()

        let second = BoardStore.restored(file: temp.file)
        #expect(second.tasks.count == TestBoard.tasks.count + 2)
        let c = second.addTask(to: .inbox, title: "Three")
        #expect(second[c]?.code == "IN-142")
        #expect(Set(second.tasks.map(\.code)).count == second.tasks.count)
        second.saveNow()
    }

    @MainActor
    @Test func saveNowWritesStraightAway() async throws {
        let temp = TempBoard()
        let store = TestBoard.store(file: temp.file)
        store.setText("Written at once", field: .title, on: TestBoard.cafe)
        #expect(temp.file.writeCount == 0)

        store.saveNow()
        // Synchronously, with nothing awaited: that is the whole point of it at
        // quit, and it is what tells a bypassed debounce from a lucky one.
        #expect(temp.file.writeCount == 1)
        #expect(temp.exists)
        #expect(store.lastSavedAt != nil)
        let snapshot = try temp.snapshot()
        #expect(snapshot.tasks.first { $0.id == TestBoard.cafe }?.title == "Written at once")

        // The debounced write it replaced is cancelled, not merely overtaken.
        try await Task.sleep(for: .milliseconds(900))
        #expect(temp.file.writeCount == 1)
    }

    @MainActor
    @Test func aBurstOfEditsBecomesOneWrite() async throws {
        let temp = TempBoard()
        let store = TestBoard.store(file: temp.file)
        // Typed at a plausible speed, yielding the main actor between
        // keystrokes. A burst that never suspends cannot tell a 500ms debounce
        // from no debounce at all: the write it schedules has had no chance to
        // run either way, so every assertion after it holds for both. The gap
        // is also the bound on how short a debounce this can catch — anything
        // that fires within it lands mid-burst and is seen.
        for text in ["W", "Wr", "Wri", "Writ", "Write"] {
            store.setText(text, field: .title, on: TestBoard.cafe)
            try await Task.sleep(for: .milliseconds(150))
        }
        // Five keystrokes, and the debounce has not fired for any of them.
        #expect(temp.file.writeCount == 0)
        #expect(temp.exists == false)

        try await Task.sleep(for: .milliseconds(900))
        #expect(temp.file.writeCount == 1)
        #expect(try temp.snapshot().tasks.first { $0.id == TestBoard.cafe }?.title == "Write")

        // …and nothing from the burst arrives late on top of it.
        try await Task.sleep(for: .milliseconds(700))
        #expect(temp.file.writeCount == 1)
    }

    @MainActor
    @Test func anEditMadeJustBeforeTheStoreGoesAwayStillLands() async throws {
        let temp = TempBoard()
        do {
            let store = TestBoard.store(file: temp.file)
            store.setText("Last words", field: .title, on: TestBoard.cafe)
        }
        try await Task.sleep(for: .milliseconds(900))
        #expect(temp.exists)
        #expect(try temp.snapshot().tasks.first { $0.id == TestBoard.cafe }?.title == "Last words")
    }

    // MARK: Backups

    @Test func aBackupCanBeReadBackAsABoard() throws {
        let temp = TempBoard()
        let snapshot = BoardSnapshot(tasks: TestBoard.tasks, labels: LabelDef.seed,
                                     nextSerial: 111)
        try temp.file.write(snapshot, generation: temp.file.nextWriteGeneration())
        temp.file.backupIfDue()

        let backups = temp.file.backups()
        #expect(backups.count == 1)
        let restored = try temp.file.restore(from: try #require(backups.first))
        #expect(restored.nextSerial == 111)
        #expect(restored.tasks.map(\.code) == TestBoard.tasks.map(\.code))
    }

    @Test func aSecondBackupWaitsForTheInterval() throws {
        let temp = TempBoard()
        try temp.file.write(BoardSnapshot(tasks: [], labels: [], nextSerial: 100),
                            generation: temp.file.nextWriteGeneration())
        temp.file.backupIfDue()
        temp.file.backupIfDue()
        #expect(temp.file.backups().count == 1)
    }

    @Test func aBoardThatWasNeverWrittenIsNotBackedUp() {
        let temp = TempBoard()
        temp.file.backupIfDue()
        #expect(temp.file.backups().isEmpty)
    }

    // MARK: Write ordering

    @Test func anOvertakenWriteIsDroppedRatherThanUndoingTheNewerOne() throws {
        let temp = TempBoard()
        let stale = temp.file.nextWriteGeneration()
        let fresh = temp.file.nextWriteGeneration()

        let newer = BoardSnapshot(tasks: TestBoard.tasks, labels: LabelDef.seed, nextSerial: 200)
        let older = BoardSnapshot(tasks: [], labels: [], nextSerial: 100)
        #expect(try temp.file.write(newer, generation: fresh) == true)
        #expect(try temp.file.write(older, generation: stale) == false)
        #expect(try temp.snapshot().nextSerial == 200)
    }

    // MARK: The suite's own blast radius

    /// `xcodebuild test` launches the app as the test host under its real bundle
    /// identifier, so an unguarded `.default` hands the suite the developer's own
    /// board — which it will read, migrate, and quarantine the moment the tree is
    /// briefly on an older schema. This has already happened once.
    @Test func theSuiteCanNeverBeHandedTheRealBoard() {
        let path = BoardFile.default.url.path(percentEncoded: false)
        #expect(path.hasPrefix(URL.temporaryDirectory.path(percentEncoded: false)),
                "BoardFile.default resolved to \(path) while running under a test runner")
        #expect(!path.contains("Application Support/LittleKanban/board.json"))
    }
}
