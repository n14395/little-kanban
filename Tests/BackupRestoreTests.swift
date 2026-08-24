import Foundation
import Testing
@testable import Simple_Kanban

/// Restoring a backup, and the one way it can be silently undone.
///
/// `BoardFile.restore(from:)` shipped with the rolling backups in 1.21 and had
/// no caller until the settings surface grew one. The interesting half is not
/// the decode — `PersistenceTests` already round-trips a backup — but what
/// happens to the *live* board around it: a restore is an edit, so it has to
/// reach the disk, be undoable, and survive the debounced write that was
/// already armed when the user pressed the button.
@Suite struct BackupRestoreTests {
    /// A board file with one backup already taken, and the snapshot that backup
    /// holds. The backup is deliberately unlike the store's board in every
    /// field an assertion later reads, so "restored" cannot be confused with
    /// "never changed".
    private func backedUp(_ temp: TempBoard, nextSerial: Int = 111) throws -> (backup: URL, snapshot: BoardSnapshot) {
        let good = BoardSnapshot(tasks: TestBoard.tasks, labels: LabelDef.seed,
                                 nextSerial: nextSerial, accentTheme: .pine)
        try temp.file.write(good, generation: temp.file.nextWriteGeneration())
        temp.file.backupIfDue()
        return (try #require(temp.file.backups().first), good)
    }

    /// A backup sitting in `backups/` as though it were taken `secondsAgo`,
    /// without going through `backupIfDue` — which names a file for the second
    /// it runs in and so cannot make two that a test can tell apart.
    ///
    /// A minute old rather than a week: the age is what the rolling interval is
    /// measured against, so a restore that asked for the *ordinary* fifteen
    /// minutes rather than for a copy right now would decline to keep the board
    /// it is about to replace, and nothing would notice.
    private func aged(
        _ temp: TempBoard, secondsAgo: TimeInterval = 60, nextSerial: Int
    ) throws -> URL {
        let snapshot = BoardSnapshot(tasks: TestBoard.tasks, labels: LabelDef.seed,
                                     nextSerial: nextSerial, accentTheme: .pine)
        try FileManager.default.createDirectory(at: temp.file.backupsDirectory, withIntermediateDirectories: true)
        let stamp = BoardFile.stamp(Date.now.addingTimeInterval(-secondsAgo))
        let url = temp.file.backupsDirectory.appending(path: "board-\(stamp).json")
        try snapshot.encoded().write(to: url)
        return url
    }

    // MARK: Reading one back

    @Test func aBackupWrittenByAnOlderBuildIsMigratedOnTheWayIn() throws {
        let temp = TempBoard()
        try FileManager.default.createDirectory(at: temp.file.backupsDirectory, withIntermediateDirectories: true)
        let backup = temp.file.backupsDirectory.appending(path: "board-20260101T000000Z.json")
        try Fixture.data("board-v2").write(to: backup)

        let restored = try temp.file.restore(from: backup)
        // A backup is only ever as new as the build that took it, so a restore
        // that skipped the migration chain would hand the store a v2 board and
        // write it back out claiming to be v5.
        #expect(restored.version == BoardSnapshot.currentVersion)
        #expect(restored.tasks.isEmpty == false)
        #expect(restored.boards.isEmpty == false)
    }

    @Test func aDamagedBackupFailsLoudlyRatherThanReturningAnEmptyBoard() throws {
        let temp = TempBoard()
        try FileManager.default.createDirectory(at: temp.file.backupsDirectory, withIntermediateDirectories: true)
        let backup = temp.file.backupsDirectory.appending(path: "board-20260101T000000Z.json")
        try Data("{ this is not a board".utf8).write(to: backup)

        // `load()` swallows a bad file and seeds; a restore the user asked for
        // must not, because the board it would replace is still fine.
        #expect(throws: BoardFileError.unreadable) { try temp.file.restore(from: backup) }
    }

    @Test func aBackupFromANewerBuildIsRefusedByVersion() throws {
        let temp = TempBoard()
        try FileManager.default.createDirectory(at: temp.file.backupsDirectory, withIntermediateDirectories: true)
        let backup = temp.file.backupsDirectory.appending(path: "board-20260101T000000Z.json")
        let future = BoardSnapshot.currentVersion + 1
        try Data("{\"version\":\(future),\"tasks\":[],\"labels\":[],\"nextSerial\":100,\"accentTheme\":\"ember\"}".utf8)
            .write(to: backup)

        #expect(throws: BoardFileError.newerVersion(future)) { try temp.file.restore(from: backup) }
    }

    @Test func aBackupThatIsNoLongerThereThrows() throws {
        let temp = TempBoard()
        let missing = temp.file.backupsDirectory.appending(path: "board-20260101T000000Z.json")
        #expect(throws: (any Error).self) { try temp.file.restore(from: missing) }
    }

    // MARK: Putting one back

    @MainActor
    @Test func aRestoreReplacesTheLiveBoard() throws {
        let temp = TempBoard()
        let store = TestBoard.store(file: temp.file)
        let (backup, _) = try backedUp(temp)

        store.setText("Mangled", field: .title, on: TestBoard.cafe)
        store.deleteTask(TestBoard.sync)
        #expect(store.tasks.count == 5)

        try store.restore(fromBackup: backup)

        #expect(store.tasks.map(\.id) == TestBoard.tasks.map(\.id))
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
        #expect(store[TestBoard.sync] != nil)
    }

    @MainActor
    @Test func aRestoreIsOneUndoStepAndComesOffCleanly() throws {
        let temp = TempBoard()
        let (store, undo) = TestBoard.undoing(file: temp.file)
        let (backup, _) = try backedUp(temp)

        step(undo) { store.deleteTask(TestBoard.sync) }
        let damaged = BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash, views: store.views, savedColors: store.savedColors)

        var restoreError: (any Error)?
        step(undo) {
            do { try store.restore(fromBackup: backup) } catch { restoreError = error }
        }
        #expect(restoreError == nil)
        #expect(undo.undoActionName == "Restore Backup")
        #expect(store[TestBoard.sync] != nil)

        undo.undo()
        let after = BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash, views: store.views, savedColors: store.savedColors)
        #expect(after == damaged, "⌘Z after a restore did not put the board back the way it was")
    }

    /// A restore is the one action that leaves the board as it stands reachable
    /// only through the undo stack, and an undo stack does not survive a quit.
    @MainActor
    @Test func theBoardAsItStandsIsKeptBeforeItIsReplaced() throws {
        let temp = TempBoard()
        let store = TestBoard.store(file: temp.file)
        // Placed a minute ago rather than taken now: a backup's name carries the
        // second it was made, and two in one second would collide.
        let backup = try aged(temp, nextSerial: 111)
        store.setText("About to be replaced", field: .title, on: TestBoard.cafe)

        try store.restore(fromBackup: backup)

        let backups = temp.file.backups()
        #expect(backups.count == 2, "the board as it stood was not kept")
        let kept = try #require(backups.first { $0 != backup })
        #expect(try temp.file.restore(from: kept).tasks.first { $0.id == TestBoard.cafe }?.title
                == "About to be replaced")
    }

    @MainActor
    @Test func aBackupThatCannotBeReadLeavesTheBoardExactlyAsItWas() throws {
        let temp = TempBoard()
        let (store, undo) = TestBoard.undoing(file: temp.file)
        _ = try backedUp(temp)
        try FileManager.default.createDirectory(at: temp.file.backupsDirectory, withIntermediateDirectories: true)
        let broken = temp.file.backupsDirectory.appending(path: "board-20250101T000000Z.json")
        try Data("{ not a board".utf8).write(to: broken)
        let before = BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash, views: store.views, savedColors: store.savedColors)

        #expect(throws: BoardFileError.unreadable) { try store.restore(fromBackup: broken) }

        let after = BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash, views: store.views, savedColors: store.savedColors)
        #expect(after == before)
        #expect(undo.canUndo == false, "a restore that failed still filed a ⌘Z")
    }

    @MainActor
    @Test func anInMemoryStoreHasNothingToRestoreFrom() {
        let store = TestBoard.store()
        #expect(store.availableBackups().isEmpty)
        #expect(throws: (any Error).self) {
            try store.restore(fromBackup: URL(filePath: "/nowhere/board-20260101T000000Z.json"))
        }
    }

    @MainActor
    @Test func theRestoreListIsNewestFirstAndSaysWhenEachWasTaken() throws {
        let temp = TempBoard()
        let store = TestBoard.store(file: temp.file)
        store.saveNow()
        temp.file.backupIfDue(interval: 0)
        // A second one a moment later; the stamp in the name is what sorts them.
        try FileManager.default.copyItem(
            at: try #require(temp.file.backups().first),
            to: temp.file.backupsDirectory.appending(path: "board-20991231T235959Z.json")
        )

        let listed = store.availableBackups()
        #expect(listed.count == 2)
        #expect(listed.first?.url.lastPathComponent == "board-20991231T235959Z.json")
        #expect(listed.allSatisfy { $0.takenAt != nil })
    }

    // MARK: The write that was already armed

    /// The user edits — arming a 500ms write holding the *damaged* board — then
    /// restores. Half a second later that armed write comes due, and if it is
    /// allowed to land the restore is silently undone and the file is back to
    /// the board the user was trying to get away from.
    ///
    /// Two things stop it, and this asks for the outcome rather than for
    /// either: `restore` calls `saveNow()`, which cancels the store's own
    /// pending write, and the file's write ordering drops anything older that
    /// escapes anyway. The probe below takes the second mechanism on its own.
    @MainActor
    @Test func aRestoreIsNotClobberedByAWriteArmedBeforeIt() async throws {
        let temp = TempBoard()
        let store = TestBoard.store(file: temp.file)
        let (backup, _) = try backedUp(temp)

        store.setText("Mangled", field: .title, on: TestBoard.cafe)
        #expect(temp.file.writeCount == 1, "only the backup's own write so far")

        try store.restore(fromBackup: backup)

        try await Task.sleep(for: .milliseconds(900))
        let onDisk = try temp.snapshot()
        #expect(onDisk.nextSerial == 111)
        #expect(onDisk.tasks.first { $0.id == TestBoard.cafe }?.title == "Café menu polish")
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
    }

    /// The same race across two stores over one path — a window replaced, or a
    /// restore performed by a store built to read the backup. This is the case
    /// Phase A's *per-URL* write ordering exists for, and the only one that
    /// cannot be answered by cancelling: the store holding the armed write is
    /// not the store doing the restore, so nothing can reach in and cancel it.
    /// A generation counter kept per store rather than per file would start the
    /// second one at zero, and its restore would look *older* than the write it
    /// is racing.
    @MainActor
    @Test func aRestoreFromASecondStoreOverOnePathStillWins() async throws {
        let temp = TempBoard()
        let damaged = TestBoard.store(file: temp.file)
        let (backup, _) = try backedUp(temp, nextSerial: 222)

        damaged.setText("Mangled", field: .title, on: TestBoard.cafe)

        let fresh = BoardStore(tasks: try temp.file.restore(from: backup).tasks,
                               labels: LabelDef.seed, nextSerial: 222, file: temp.file)
        fresh.saveNow()

        try await Task.sleep(for: .milliseconds(900))
        #expect(try temp.snapshot().tasks.first { $0.id == TestBoard.cafe }?.title == "Café menu polish")
        #expect(try temp.snapshot().nextSerial == 222)
    }

    /// The converse, so the guard cannot be "drop everything after the first
    /// write". An edit made *after* the restore is newer and must land.
    @MainActor
    @Test func anEditMadeAfterARestoreStillReachesTheDisk() async throws {
        let temp = TempBoard()
        let store = TestBoard.store(file: temp.file)
        let (backup, _) = try backedUp(temp)

        try temp.file.write(try temp.file.restore(from: backup), generation: temp.file.nextWriteGeneration())
        store.setText("Typed after the restore", field: .title, on: TestBoard.cafe)

        try await Task.sleep(for: .milliseconds(900))
        #expect(try temp.snapshot().tasks.first { $0.id == TestBoard.cafe }?.title == "Typed after the restore")
    }
}
