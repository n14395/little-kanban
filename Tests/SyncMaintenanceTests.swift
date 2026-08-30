import CoreData
import Foundation
import SwiftData
import Testing
@testable import Simple_Kanban

/// The pass that keeps the store a board rather than an archive.
///
/// CloudKit sync runs on persistent history, and nothing on any layer deletes
/// it — measured after a week on a real device, the log was 476,096
/// transactions and the file 149 MB for a 110 KB board. `sweepHistory` is the
/// answer: history past the window goes, and a reopen with the vacuum option
/// hands the pages back. See it for why the window is a week.
///
/// These stores are file-backed on purpose — history lives in the file — but
/// local-only, in a directory the test throws away: the same standing rule as
/// everywhere else, a suite must never reach iCloud.
@MainActor
@Suite struct SyncMaintenanceTests {
    private func filed() throws -> (TempBoard, URL, BoardSyncStore) {
        let temp = TempBoard()
        let url = temp.directory.appending(path: "board.store")
        let sync = try BoardSyncStore.app(syncing: false, at: url)
        try sync.apply(BoardSnapshot(
            tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: SeedData.boards,
            labels: LabelDef.seed, nextSerial: 100
        ))
        return (temp, url, sync)
    }

    @Test func theSweepDropsHistoryPastTheWindow() throws {
        let (temp, url, sync) = try filed()
        #expect(try BoardSyncStore.historyRemains(at: url), "the write left no history to sweep")

        // A zero-day window against a cutoff just ahead of the clock: every
        // transaction the write above made is past it.
        BoardSyncStore.sweepHistory(at: url, olderThan: 0, now: Date.now.addingTimeInterval(60))
        #expect(try BoardSyncStore.historyRemains(at: url) == false, "the sweep left the log standing")
        _ = (temp, sync)
    }

    @Test func theSweepKeepsHistoryTheWindowStillCovers() throws {
        let (temp, url, sync) = try filed()

        // The default week: everything just written is younger than it.
        BoardSyncStore.sweepHistory(at: url)
        #expect(try BoardSyncStore.historyRemains(at: url),
                "the sweep took history the mirror may still need")
        _ = (temp, sync)
    }

    /// The whole point of the sweep is that the board it leaves is
    /// indistinguishable from the board it found.
    @Test func theBoardSurvivesTheSweepUntouched() throws {
        let (temp, url, sync) = try filed()
        let before = try #require(try sync.load())

        BoardSyncStore.sweepHistory(at: url, olderThan: 0, now: Date.now.addingTimeInterval(60))

        let reopened = try BoardSyncStore.app(syncing: false, at: url)
        let after = try #require(try reopened.load())
        #expect(after.boards == before.boards)
        #expect(after.tasks == before.tasks)
        #expect(after.labels == before.labels)
        _ = temp
    }

    /// Loading a store creates its file, and a first launch must keep meaning
    /// "the store is empty" — so a sweep aimed at nothing does nothing.
    @Test func theSweepDoesNotConjureAStore() throws {
        let temp = TempBoard()
        let url = temp.directory.appending(path: "board.store")
        BoardSyncStore.sweepHistory(at: url)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == false,
                "the sweep created the store it was meant to be sweeping")
    }
}
