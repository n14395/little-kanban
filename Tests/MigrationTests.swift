import Foundation
import Testing
@testable import LittleKanban

/// The migration chain, one link at a time.
///
/// A migration test that only asks "did it decode" is the test that lets a
/// board through with its due dates dropped, so everything here is checked
/// field by field. The v1 fixtures are covered in `PersistenceTests`; this
/// suite is about the shape of the *chain* — that a v1 board and a v3 board
/// arrive at the same v5 through the same code, and that the version a build
/// cannot read is refused rather than guessed at.
@Suite struct MigrationTests {
    private func isLegacy(_ kind: ActivityEntry.Kind) -> Bool {
        if case .legacy = kind { return true }
        return false
    }

    private func encode(_ snapshot: BoardSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    // MARK: v2 → v3 → v4

    @Test func theV2FixtureArrivesAsV5WithNothingArchived() throws {
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v2"))
        let result = temp.file.load()
        let snapshot = try #require(result.snapshot)

        #expect(result.failure == nil)
        #expect(result.migratedFromVersion == 2)
        #expect(snapshot.version == BoardSnapshot.currentVersion)
        #expect(snapshot.nextSerial == BoardSnapshot.baseSerial)
        #expect(snapshot.themes == .seed)
        #expect(snapshot.labels == LabelDef.seed)

        // Nothing written before v3 was ever archived, and the step says so
        // rather than leaving it to a property default.
        #expect(snapshot.tasks.allSatisfy { $0.archivedAt == nil })
        #expect(snapshot.tasks.allSatisfy { !$0.isArchived })

        // The fixture is `TestBoard` written out, so this is a field-for-field
        // comparison of ids, codes, placements, titles, notes, labels, dues,
        // priorities, sub-tasks, activity and both timestamps at once.
        #expect(snapshot.tasks == TestBoard.tasks(on: try #require(snapshot.boards.first)))
    }

    @Test func theV2FixtureKeepsEveryFieldOfATaskThatHasThemAll() throws {
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v2"))
        let snapshot = try #require(temp.file.load().snapshot)
        let task = try #require(snapshot.tasks.first { $0.code == "NW-121" })

        #expect(task.id == TestBoard.dragDrop)
        #expect(task.columnID == BoardColumn.backlog.id)
        #expect(task.title == "Drag and drop between columns")
        #expect(task.note == "Card follows the pointer with a lifted shadow.")
        #expect(task.labelKeys == ["design", "ios"])
        #expect(task.due == TestBoard.dueDay)
        #expect(task.priority == .high)
        #expect(task.subtasks.map(\.id) == [TestBoard.lift, TestBoard.dropTargets, TestBoard.keyboard])
        #expect(task.subtasks.map(\.done) == [true, false, false])
        #expect(task.activity.map(\.kind) == [.created])
        #expect(task.activity.map(\.id) == [TestBoard.entryID(2)])
        #expect(task.createdAt == TestBoard.at(7_200))
        #expect(task.updatedAt == TestBoard.at(7_200))
        #expect(task.archivedAt == nil)

        // A v2 board carries no structured activity a v3 board cannot read, so
        // the feed comes across as itself rather than as `.legacy` text.
        #expect(snapshot.tasks.flatMap(\.activity).contains { isLegacy($0.kind) } == false)
    }

    // MARK: v1 → v2 → v3 → v4, through the same later steps

    @Test func bothV1FixturesReachV5ThroughTheWholeChain() throws {
        for name in ["board-v1", "board-v1-minted"] {
            let temp = TempBoard()
            try temp.put(try Fixture.data(name))
            let result = temp.file.load()
            let snapshot = try #require(result.snapshot, "\(name) did not load")

            #expect(result.failure == nil)
            #expect(result.migratedFromVersion == 1, "\(name) was not seen as v1")
            #expect(snapshot.version == BoardSnapshot.currentVersion)
            #expect(snapshot.tasks.allSatisfy { $0.archivedAt == nil }, "\(name) invented an archive")
            #expect(snapshot.tasks.isEmpty == false)
            // The v1 step is what turns instants into days and sentences into
            // `.legacy` entries; the v3 file has to show both were run.
            #expect(snapshot.tasks.contains { $0.due != nil })
            #expect(snapshot.tasks.flatMap(\.activity).contains { isLegacy($0.kind) })
        }
    }

    @Test func aV1BoardAndAV2BoardTakeTheSameLastStep() throws {
        // `migrate(v1:)` stops at v2 on purpose: the step after it is the one a
        // v2 file on disk takes too. Walking a v1 file by hand and comparing it
        // with what `load()` produced is what says the chain is a chain rather
        // than two decoders that happen to agree today.
        let data = try Fixture.data("board-v1")
        let v1 = try JSONDecoder().decode(BoardSnapshotV1.self, from: data)
        let walked = BoardSnapshot.migrate(
            v4: BoardSnapshot.migrate(v3: BoardSnapshot.migrate(v2: BoardSnapshot.migrate(v1: v1)))
        )

        let temp = TempBoard()
        try temp.put(data)
        let loaded = try #require(temp.file.load().snapshot)

        #expect(walked.version == loaded.version)
        #expect(walked.nextSerial == loaded.nextSerial)
        // Not the themes: `migrate(v4:)` is the last *shape* change and stamps
        // the current version, so a hand-walk stops before the v12 step, which
        // is the only one that needs the raw bytes — the old accent is not on
        // the decoded value any more. `theV1FixtureStillLoads` is where that
        // step is asked about.
        #expect(walked.labels == loaded.labels)
        // Task ids are minted fresh by the v1 step — nothing in a v1 file
        // referred to them — so everything else is compared instead.
        #expect(walked.tasks.map(\.code) == loaded.tasks.map(\.code))
        #expect(walked.tasks.map(\.columnID) == loaded.tasks.map(\.columnID))
        #expect(walked.tasks.map(\.title) == loaded.tasks.map(\.title))
        #expect(walked.tasks.map(\.due) == loaded.tasks.map(\.due))
        #expect(walked.tasks.map(\.priority) == loaded.tasks.map(\.priority))
        #expect(walked.tasks.map(\.createdAt) == loaded.tasks.map(\.createdAt))
        #expect(walked.tasks.map(\.updatedAt) == loaded.tasks.map(\.updatedAt))
        #expect(walked.tasks.map(\.archivedAt) == loaded.tasks.map(\.archivedAt))
        #expect(walked.tasks.map { $0.activity.map(\.kind) } == loaded.tasks.map { $0.activity.map(\.kind) })
        #expect(walked.tasks.map { $0.subtasks.map(\.id) } == loaded.tasks.map { $0.subtasks.map(\.id) })
    }

    // MARK: v4 itself

    @Test func aV5FileIsReadBackWithoutBeingMigratedAgain() throws {
        let temp = TempBoard()
        var filed = TestBoard.tasks[5]
        filed.archivedAt = TestBoard.at(1_500)
        let written = BoardSnapshot(
            tasks: Array(TestBoard.tasks.dropLast()) + [filed],
            labels: LabelDef.seed, nextSerial: 121, themes: TestBoard.otherThemes
        )
        try temp.file.write(written, generation: temp.file.nextWriteGeneration())

        let result = temp.file.load()
        let read = try #require(result.snapshot)
        #expect(result.failure == nil)
        #expect(result.migratedFromVersion == nil)
        #expect(read.version == BoardSnapshot.currentVersion)
        #expect(read.tasks == written.tasks)
        #expect(read.tasks.last?.archivedAt == TestBoard.at(1_500))
        #expect(read.tasks.dropLast().allSatisfy { $0.archivedAt == nil })
        // Nothing was migrated, so nothing was set aside for a migration.
        #expect(temp.siblings().contains { $0.hasPrefix("board.v") } == false)
    }

    @Test func anUnarchivedV5BoardWritesNoArchiveKeyAtAll() throws {
        // `archivedAt` is `Optional`, so it is written with `encodeIfPresent`
        // and left out when it is nil. That is what makes a board nobody has
        // archived anything on byte-identical to the v2 it replaces — and it is
        // what lets the v2 decoder go on reading a file it never wrote.
        let temp = TempBoard()
        try temp.file.write(
            BoardSnapshot(tasks: TestBoard.tasks, labels: LabelDef.seed,
                          nextSerial: 100),
            generation: temp.file.nextWriteGeneration()
        )
        #expect(try temp.text().contains("archivedAt") == false)
        #expect(try temp.text().contains("\"version\" : \(BoardSnapshot.currentVersion)"))

        let filed = TestBoard.tasks(archiving: [TestBoard.palette: 900])
        try temp.file.write(
            BoardSnapshot(tasks: filed, labels: LabelDef.seed, nextSerial: 100),
            generation: temp.file.nextWriteGeneration()
        )
        #expect(try temp.text().contains("\"archivedAt\""))
    }

    @Test func aV12BoardKeepsItsThemesWhenMigratedToV13() throws {
        var v12 = BoardSnapshot(
            tasks: TestBoard.tasks, labels: LabelDef.seed, nextSerial: 100, themes: TestBoard.otherThemes
        )
        v12.version = 12
        let temp = TempBoard()
        try temp.put(try encode(v12))

        let result = temp.file.load()
        let read = try #require(result.snapshot)
        #expect(result.migratedFromVersion == 12)
        #expect(read.version == BoardSnapshot.currentVersion)
        #expect(read.themes == TestBoard.otherThemes)
        #expect(read.tasks.allSatisfy { $0.inboxCompletedAt == nil })
    }

    // MARK: The version after this one

    @Test func aFileFromTheVersionAfterThisOneIsRefusedAndPutSomewhereSafe() throws {
        // 99 is already covered; the version one past the current one is what
        // matters, because it is what an off-by-one in the "newer than me"
        // guard would wave through and then mis-decode. The file has to
        // survive that refusal intact.
        let temp = TempBoard()
        var object = try #require(
            try JSONSerialization.jsonObject(with: try encode(
                BoardSnapshot(tasks: TestBoard.tasks, labels: LabelDef.seed,
                              nextSerial: 100)
            )) as? [String: Any]
        )
        object["version"] = BoardSnapshot.currentVersion + 1
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try temp.put(bytes)

        let result = temp.file.load()
        #expect(result.snapshot == nil)
        #expect(result.migratedFromVersion == nil)
        guard case .newerVersion(let version, let quarantinedAt) = result.failure else {
            Issue.record("expected .newerVersion, got \(String(describing: result.failure))")
            return
        }
        #expect(version == BoardSnapshot.currentVersion + 1)
        let moved = try #require(quarantinedAt)
        #expect(moved.lastPathComponent.hasPrefix("board.from-newer-version-\(BoardSnapshot.currentVersion + 1)-"))
        // Moved aside, not deleted, and the board's own URL is now free for a
        // fresh board to be written to without landing on the user's work.
        #expect(FileManager.default.fileExists(atPath: moved.path(percentEncoded: false)))
        #expect(try Data(contentsOf: moved) == bytes)
        #expect(temp.exists == false)
    }

    @MainActor
    @Test func aStoreOverAFileFromTheVersionAfterThisOneSaysSoAndDoesNotWriteOverIt() throws {
        // Built from `currentVersion` rather than written out, so the bump that
        // ships the next format does not leave this suite asserting that the
        // present is the future.
        let ahead = BoardSnapshot.currentVersion + 1
        let temp = TempBoard()
        try temp.put(#"{ "version": \#(ahead), "tasks": [], "labels": [], "nextSerial": 100, "accentTheme": "ember" }"#)
        let store = BoardStore.restored(file: temp.file)
        guard case .newerVersion(let version, _) = store.loadFailure else {
            Issue.record("expected .newerVersion, got \(String(describing: store.loadFailure))")
            return
        }
        #expect(version == ahead)
        #expect(store.lastError != nil)
        #expect(store.quarantinedBoardURL != nil)
        #expect(store.isSaveBlocked == false)      // the original is out of the way
    }
}
