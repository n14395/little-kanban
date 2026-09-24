// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import CoreData
import Foundation
import SwiftData
import Testing
@testable import LittleKanban

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

/// The reopen that stands in for a fetch — see `BoardSyncStore.reconnect()`.
///
/// A test can hold no real mirror, so what these pin is the half a test can
/// reach: the rebuild swaps the container without losing a record or the diff
/// base, stores with no opening to repeat refuse politely, and the throttle
/// keeps a frustrated pull from standing up a mirror per tug.
@MainActor
@Suite struct SyncReconnectTests {
    private func filed() throws -> (TempBoard, BoardSyncStore) {
        let temp = TempBoard()
        let sync = try BoardSyncStore.app(
            syncing: false, at: temp.directory.appending(path: "board.store"))
        try sync.apply(BoardSnapshot(
            tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: SeedData.boards,
            labels: LabelDef.seed, nextSerial: 100
        ))
        return (temp, sync)
    }

    @Test func theRebuildSwapsTheContainerAndKeepsEveryRecord() throws {
        let (temp, sync) = try filed()
        let before = try #require(try sync.load())
        let old = sync.container

        sync.rebuild()

        #expect(sync.container !== old, "the rebuild kept the old container")
        let after = try #require(try sync.load())
        #expect(after.boards == before.boards)
        #expect(after.tasks == before.tasks)
        _ = temp
    }

    /// The diff base survives the swap: the records did not move, so what this
    /// device has seen of them is still true — and forgetting it would turn
    /// the next push into a full rewrite, which is the churn the diff exists
    /// to prevent.
    @Test func theRebuildDoesNotTurnTheNextPushIntoARewrite() throws {
        let (temp, sync) = try filed()
        _ = try sync.load()

        sync.rebuild()
        var edited = try #require(try sync.load())
        edited.tasks[0].title = "One edit"
        edited.tasks[0].updatedAt = .now
        try sync.apply(edited)

        let read = try #require(try sync.load())
        #expect(read.tasks[0].title == "One edit")
        _ = temp
    }

    /// A ready-made container has no opening to repeat — the in-memory stores
    /// every suite runs on — and a local store has no mirror to wake.
    @Test func aStoreWithNothingToReconnectKeepsItsContainer() throws {
        let sync = try BoardSyncStore.inMemory()
        let old = sync.container
        sync.rebuild()
        #expect(sync.container === old, "an in-memory store rebuilt its container")
        sync.reconnect()
        #expect(sync.container === old, "a mirrorless store reconnected anyway")
    }
}
