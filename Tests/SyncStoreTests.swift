import Foundation
import SwiftData
import Testing
@testable import LittleKanban

/// The SwiftData store the board syncs through.
///
/// Every store here is `BoardSyncStore.inMemory()`, which is `.none` for
/// CloudKit and stored nowhere — the same rule as `BoardFile(file: nil)`, and
/// for a sharper reason: a suite that reached iCloud would edit the developer's
/// own board on every device they own.
@MainActor
@Suite struct SyncStoreTests {
    private func store() throws -> BoardSyncStore { try BoardSyncStore.inMemory() }

    /// Filed onto the seed board, not `TestBoard.tasks` raw: those carry a
    /// column and no board, an illegal pair `BoardStore.placed(_:on:)` repairs
    /// on adoption. Handing them straight to the sync store would test the
    /// half-written-pair rule by accident and nothing else.
    private static let filed = TestBoard.tasks(on: SeedData.defaultBoard)

    private func snapshot(
        tasks: [TaskItem] = SyncStoreTests.filed,
        boards: [Board] = SeedData.boards,
        nextSerial: Int = 344,
        themes: ThemeSettings = TestBoard.otherThemes
    ) -> BoardSnapshot {
        BoardSnapshot(
            tasks: tasks, boards: boards, labels: LabelDef.seed,
            nextSerial: nextSerial, activeBoardID: boards.first?.id, themes: themes
        )
    }

    // MARK: Round trip

    @Test func anEmptyStoreHasNoBoardRatherThanAnEmptyOne() throws {
        // The difference decides whether the caller seeds or wipes.
        #expect(try store().load() == nil)
    }

    @Test func everyFieldSurvivesTheRoundTrip() throws {
        let sync = try store()
        var completedInbox = TaskItem(code: "IN-400", title: "Keep this in Inbox")
        completedInbox.inboxCompletedAt = TestBoard.at(120)
        let written = snapshot(tasks: [completedInbox] + Self.filed)
        try sync.apply(written)

        let read = try #require(try sync.load())
        #expect(read.nextSerial == written.nextSerial)
        #expect(read.themes == written.themes)
        #expect(read.activeBoardID == written.activeBoardID)
        #expect(read.boards == written.boards)
        #expect(read.labels == written.labels)
        #expect(Set(read.tasks.map(\.id)) == Set(written.tasks.map(\.id)))

        for expected in written.tasks {
            let actual = try #require(read.tasks.first { $0.id == expected.id })
            #expect(actual == expected, "\(expected.code) did not survive")
        }
    }

    /// A WIP limit is an attribute added to a schema that already existed, so
    /// it is exactly the shape `SyncSchema`'s additive-only rule is about:
    /// optional, defaulted, and `nil` on every record a build without it wrote.
    ///
    /// There is no version stamp on a record to refuse on — see
    /// `StoredColumn.limit` — so this round trip is the whole of the guarantee
    /// sync can offer about the field.
    @Test func aColumnsWipLimitSurvivesTheRoundTrip() throws {
        let sync = try store()
        var boards = SeedData.boards
        boards[0].columns[0].limit = 3
        try sync.apply(snapshot(boards: boards))

        let read = try #require(try sync.load())
        let board = try #require(read.boards.first { $0.id == boards[0].id })
        #expect(board.columns.first?.limit == 3)
        #expect(board.columns.dropFirst().allSatisfy { $0.limit == nil },
                "a limit set on one column reached the others")
        // The whole board, field for field, which is what says the limit did
        // not arrive at the cost of something else on the record.
        #expect(board == boards[0])
    }

    /// A board's mark is v16's new attribute, and the same additive-only shape:
    /// a `String` with a default, `SymbolMark.boardFallback` on every record a
    /// build without it wrote.
    ///
    /// **The colour it replaced is left alone rather than cleared.** A CloudKit
    /// schema is additive only, so `StoredBoard.dot` stays — and this build
    /// neither reads nor writes it, which is what lets a device on an older
    /// build go on finding the last colour it wrote instead of a board that has
    /// gone colourless. `StoredColumn.roleKey` made the same bargain at v9.
    @Test func aBoardsMarkSurvivesTheRoundTripAndLeavesTheOldColourAlone() throws {
        let sync = try store()
        var boards = SeedData.boards
        boards[0].symbol = "paintbrush"
        try sync.apply(snapshot(boards: boards))

        let context = sync.container.mainContext
        let record = try #require(
            try context.fetch(FetchDescriptor<StoredBoard>()).first { $0.id == boards[0].id }
        )
        // A colour an older build had written, which this one must not touch.
        record.dot = try JSONEncoder().encode(SwatchColor.hex(0xC2532F))
        boards[0].symbol = "leaf"
        try sync.apply(snapshot(boards: boards))

        let read = try #require(try sync.load())
        let board = try #require(read.boards.first { $0.id == boards[0].id })
        #expect(board.symbol == "leaf")
        // The whole board, field for field, which is what says the mark did not
        // arrive at the cost of something else on the record.
        #expect(board == boards[0])
        #expect(BoardSyncStore.decoded(record.dot) == SwatchColor.hex(0xC2532F),
                "the board's old colour was overwritten by a build that does not read it")
    }

    /// **The upgrade with sync on.** Board records written before v16 carry no
    /// mark at all, and the file beside them has been through `migrate(v15:)`
    /// and carries the one each board was *dealt*. The records are what put a
    /// board on screen, so without the backfill every board would arrive
    /// wearing the fallback and the whole point of the step — a sidebar that
    /// stays legible across the upgrade — would be lost on exactly the installs
    /// most likely to have several boards.
    ///
    /// This is `StoredTask.position`'s problem one version later, and it is
    /// solved the same way: the record's attribute is optional so "never had
    /// one" and "has the default" are different answers, and the file fills the
    /// gap without touching anything else.
    @Test func boardsUpgradedWithSyncOnKeepTheMarksTheFileDealtThem() throws {
        let sync = try store()
        var boards = SeedData.boards
        boards.append(TestBoard.support)
        try sync.apply(snapshot(boards: boards))

        // The records as a pre-v16 build wrote them: no mark on any of them.
        let context = sync.container.mainContext
        for record in try context.fetch(FetchDescriptor<StoredBoard>()) { record.symbol = nil }
        try context.save()
        #expect(try sync.hasStoredBoardSymbols() == false)

        // And the file as the migration left it.
        var dealt = boards
        for index in dealt.indices { dealt[index].symbol = Board.startingSymbols[index] }
        let temp = TempBoard()
        try temp.file.write(
            BoardSnapshot(tasks: [], boards: dealt, labels: LabelDef.seed,
                          nextSerial: 100, activeBoardID: dealt[0].id),
            generation: temp.file.nextWriteGeneration()
        )

        let store = BoardStore.restored(file: temp.file, sync: sync)
        #expect(store.boards.map(\.symbol) == dealt.map(\.symbol),
                "a synced upgrade lost the marks the migration dealt")
        #expect(try sync.hasStoredBoardSymbols(), "the records were left without marks")

        // A mark a record *does* carry is never overwritten by the file.
        var theirs = boards
        theirs[0].symbol = "paintbrush"
        try sync.apply(snapshot(boards: theirs))
        let second = BoardStore.restored(file: temp.file, sync: sync)
        #expect(second.boards.first?.symbol == "paintbrush",
                "the file overwrote a mark another device had chosen")
    }

    /// Task order is the order a manual drag writes. Unlike a Swift array,
    /// SwiftData's fetch order has no ordering contract, so the record stores
    /// it and the reader must use that position rather than fetch order.
    @Test func taskOrderSurvivesTheRoundTrip() throws {
        let sync = try store()
        let written = snapshot(tasks: Array(Self.filed.reversed()))
        try sync.apply(written)

        let read = try #require(try sync.load())
        #expect(read.tasks.map(\.id) == written.tasks.map(\.id))
    }

    @Test func unrankedTasksCanBeBackfilledWithoutChangingTheirContent() throws {
        let sync = try store()
        let written = snapshot(tasks: Array(Self.filed.reversed()))
        try sync.apply(written)

        let records = try sync.container.mainContext.fetch(FetchDescriptor<StoredTask>())
        for record in records { record.position = nil }
        try sync.container.mainContext.save()
        #expect(try sync.hasStoredTaskOrder() == false)

        try sync.backfillTaskPositions(from: written.tasks.map(\.id))
        let read = try #require(try sync.load())
        #expect(read.tasks.map(\.id) == written.tasks.map(\.id))
        #expect(read.tasks.allSatisfy { task in written.tasks.contains(task) })
    }

    /// The order a checklist is in is the user's, and CloudKit does not
    /// preserve array order — hence `StoredSubtask.position`.
    @Test func subTasksComeBackInTheOrderTheyWentIn() throws {
        let sync = try store()
        try sync.apply(snapshot())
        let read = try #require(try sync.load())
        let card = try #require(read.tasks.first { $0.id == TestBoard.dragDrop })
        #expect(card.subtasks.map(\.id) == [TestBoard.lift, TestBoard.dropTargets, TestBoard.keyboard])
        #expect(card.subtasks.map(\.done) == [true, false, false])
    }

    /// The feed reads newest first, and `when` is the only ordering a record
    /// carries.
    @Test func activityComesBackNewestFirst() throws {
        let sync = try store()
        // `at(_:)` counts seconds *backwards*, so at(900) is the oldest of the
        // three and at(100) the newest. Written here out of order on purpose:
        // a record carries no array position, so the sort is the only thing
        // putting them back.
        var card = Self.filed[1]
        card.activity = [
            ActivityEntry(id: TestBoard.entryID(80), .created, when: TestBoard.at(900)),
            ActivityEntry(id: TestBoard.entryID(81), .renamed, when: TestBoard.at(100)),
            ActivityEntry(id: TestBoard.entryID(82), .descriptionUpdated, when: TestBoard.at(500)),
        ]
        try sync.apply(snapshot(tasks: [card]))

        let read = try #require(try sync.load())
        let stored = try #require(read.tasks.first)
        #expect(stored.activity.map(\.when) == [TestBoard.at(100), TestBoard.at(500), TestBoard.at(900)])
        #expect(stored.activity.map(\.kind) == [.renamed, .descriptionUpdated, .created])
    }

    @Test func everyActivityKindSurvivesEncoding() throws {
        let sync = try store()
        var card = Self.filed[1]
        card.activity = TestBoard.everyActivityKind.enumerated().map { index, kind in
            ActivityEntry(id: TestBoard.entryID(UInt8(120 + index)), kind, when: TestBoard.at(index * 60))
        }
        try sync.apply(snapshot(tasks: [card]))

        let read = try #require(try sync.load())
        let stored = try #require(read.tasks.first)
        #expect(Set(stored.activity.map(\.kind)) == Set(TestBoard.everyActivityKind))
    }

    // MARK: The invariant

    /// CloudKit does not apply relationship changes atomically, so a record can
    /// arrive with one id of the pair and not the other. An unfiled card is the
    /// only reading of that which does not put a card somewhere nobody can
    /// find.
    @Test func aHalfWrittenPlacementReadsAsUnfiled() throws {
        let sync = try store()
        try sync.apply(snapshot())

        let context = sync.container.mainContext
        let records = try context.fetch(FetchDescriptor<StoredTask>())
        let filed = try #require(records.first { $0.boardID != nil && $0.columnID != nil })
        filed.columnID = nil            // the half-written pair
        try context.save()

        let read = try #require(try sync.load())
        let card = try #require(read.tasks.first { $0.id == filed.id })
        #expect(card.isUnfiled)
        #expect(card.boardID == nil)
        #expect(card.columnID == nil)
    }

    // MARK: Duplicates

    /// Uniqueness is the one guarantee CloudKit cannot give, so it is settled
    /// on the way out instead: last writer wins, by `updatedAt`.
    @Test func twoRecordsUnderOneIdKeepTheNewer() throws {
        let sync = try store()
        try sync.apply(snapshot(tasks: [Self.filed[1]]))

        let context = sync.container.mainContext
        let original = try #require(try context.fetch(FetchDescriptor<StoredTask>()).first)
        let rival = StoredTask(id: original.id)
        rival.code = original.code
        rival.title = "The newer one"
        rival.updatedAt = original.updatedAt.addingTimeInterval(60)
        context.insert(rival)
        try context.save()

        let read = try #require(try sync.load())
        #expect(read.tasks.count == 1)
        #expect(read.tasks.first?.title == "The newer one")
    }

    @Test func twoSettingsRecordsKeepTheNewerAndDropTheOther() throws {
        let sync = try store()
        try sync.apply(snapshot(nextSerial: 200))

        let context = sync.container.mainContext
        let rival = StoredMeta()
        rival.nextSerial = 999
        rival.updatedAt = .now.addingTimeInterval(60)
        context.insert(rival)
        try context.save()

        #expect(try sync.load()?.nextSerial == 999)
        // The loser is deleted rather than left for the next device to settle.
        #expect(try context.fetch(FetchDescriptor<StoredMeta>()).count == 1)
    }

    // MARK: Writing only what changed

    /// The reason this layer exists. Rewriting every card on every keystroke
    /// would hand CloudKit the whole board to reconcile and undo the
    /// granularity the schema was designed for.
    @Test func editingOneCardTouchesOneRecord() throws {
        let sync = try store()
        try sync.apply(snapshot())

        let context = sync.container.mainContext
        let before = try context.fetch(FetchDescriptor<StoredTask>())
            .reduce(into: [UUID: Date]()) { $0[$1.id] = $1.updatedAt }

        var edited = Self.filed
        edited[1].title = "Renamed on this device"
        edited[1].updatedAt = .now
        try sync.apply(snapshot(tasks: edited))

        let after = try context.fetch(FetchDescriptor<StoredTask>())
        let moved = after.filter { before[$0.id] != $0.updatedAt }
        #expect(moved.count == 1)
        #expect(moved.first?.id == edited[1].id)
        #expect(moved.first?.title == "Renamed on this device")
    }

    @Test func applyingTheSameBoardTwiceWritesNothingTheSecondTime() throws {
        let sync = try store()
        let board = snapshot()
        try sync.apply(board)
        let context = sync.container.mainContext
        let identities = try context.fetch(FetchDescriptor<StoredTask>()).map(\.persistentModelID)

        try sync.apply(board)
        #expect(try context.fetch(FetchDescriptor<StoredTask>()).map(\.persistentModelID) == identities)
    }

    /// A merge from another device leaves the store holding something this
    /// device never wrote, so the diff it was keeping is a lie.
    @Test func invalidatingTheDiffMakesTheNextWriteComplete() throws {
        let sync = try store()
        try sync.apply(snapshot())

        let context = sync.container.mainContext
        for record in try context.fetch(FetchDescriptor<StoredTask>()) { record.title = "clobbered" }
        try context.save()

        // Without the invalidation the diff says nothing changed, so nothing is
        // written and the board stays clobbered.
        sync.invalidateDiff()
        try sync.apply(snapshot())
        #expect(try context.fetch(FetchDescriptor<StoredTask>()).allSatisfy { $0.title != "clobbered" })
    }

    // MARK: Deletion

    @Test func aDeletedCardTakesItsChecklistAndHistoryWithIt() throws {
        let sync = try store()
        try sync.apply(snapshot())
        let context = sync.container.mainContext
        #expect(try context.fetch(FetchDescriptor<StoredSubtask>()).isEmpty == false)

        // The tombstones are the licence — a snapshot merely missing the tasks
        // deletes nothing. `DeletionLicenseTests` holds that side.
        try sync.apply(snapshot(tasks: []),
                       deleting: SyncIDs(tasks: Set(Self.filed.map(\.id))))
        #expect(try context.fetch(FetchDescriptor<StoredTask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredSubtask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredActivity>()).isEmpty)
    }

    @Test func aDeletedBoardTakesItsColumnsWithIt() throws {
        let sync = try store()
        try sync.apply(snapshot())
        let context = sync.container.mainContext
        #expect(try context.fetch(FetchDescriptor<StoredColumn>()).isEmpty == false)

        try sync.apply(snapshot(tasks: [], boards: []),
                       deleting: SyncIDs(boards: Set(SeedData.boards.map(\.id)),
                                         tasks: Set(Self.filed.map(\.id))))
        #expect(try context.fetch(FetchDescriptor<StoredBoard>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredColumn>()).isEmpty)
    }

    // MARK: The schema CloudKit will accept

    /// Every rule here is one the framework cannot enforce once the data is on
    /// a server it does not exclusively own, and every one of them fails at
    /// container-open time rather than at compile time — which is to say, on
    /// somebody's device rather than here, unless this asks.
    @Test func theSchemaIsOneCloudKitCanTake() throws {
        let schema = Schema(SyncSchema.models)
        for entity in schema.entities {
            for attribute in entity.attributes {
                #expect(attribute.isUnique == false,
                        "\(entity.name).\(attribute.name) is unique, which CloudKit cannot enforce")
            }
            for relationship in entity.relationships {
                #expect(relationship.deleteRule != .deny,
                        "\(entity.name).\(relationship.name) denies deletion, which CloudKit cannot support")
                #expect(relationship.isOptional,
                        "\(entity.name).\(relationship.name) is required; CloudKit needs every relationship optional")
            }
        }
    }

    @Test func theContainerIsNamedAfterTheBundle() {
        // The entitlement and the code have to agree, and nothing at build time
        // says so.
        #expect(SyncSchema.cloudContainerID == "iCloud.com.n14395.LittleKanban")
    }

    @Test func anInMemoryStoreNeverReachesICloud() throws {
        #expect(try store().isSyncing == false)
    }

    /// The suite runs as the app's own test host, under the app's own bundle
    /// identifier. Without this guard it would sync the fixtures to whatever
    /// iCloud account the machine is signed in to — and then to every device on
    /// it. Same rule as `BoardFile.default`, with more at stake.
    @Test func theSuiteNeverAsksForICloud() {
        #expect(SyncPreference.isOn == false)
    }
}

/// How ``BoardStore`` and the two stores underneath it fit together.
@MainActor
@Suite struct SyncWiringTests {
    /// The records are asked first, because they are the ones another device
    /// can have written since this one last looked.
    @Test func aBoardInTheRecordsIsPreferredToTheOneInTheFile() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()

        // The file says one thing…
        var fromFile = TestBoard.tasks(on: SeedData.defaultBoard)[1]
        fromFile.title = "What the file says"
        try temp.file.write(
            BoardSnapshot(tasks: [fromFile], boards: SeedData.boards, labels: LabelDef.seed,
                          nextSerial: 100,
            activeBoardID: SeedData.defaultBoard.id),
            generation: temp.file.nextWriteGeneration()
        )
        // …and the records another.
        var fromSync = fromFile
        fromSync.title = "What the records say"
        try sync.apply(BoardSnapshot(tasks: [fromSync], boards: SeedData.boards, labels: LabelDef.seed,
                                     nextSerial: 100,
            activeBoardID: SeedData.defaultBoard.id))

        let store = BoardStore.restored(file: temp.file, sync: sync)
        #expect(store.tasks.first?.title == "What the records say")
    }

    @Test func anExistingSyncStoreTakesTaskOrderFromTheFile() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let tasks = Array(TestBoard.tasks(on: SeedData.defaultBoard).reversed())
        let board = BoardSnapshot(
            tasks: tasks, boards: SeedData.boards, labels: LabelDef.seed,
            nextSerial: 100, activeBoardID: SeedData.defaultBoard.id
        )
        try temp.file.write(board, generation: temp.file.nextWriteGeneration())
        try sync.apply(board)

        for record in try sync.container.mainContext.fetch(FetchDescriptor<StoredTask>()) {
            record.position = nil
        }
        try sync.container.mainContext.save()

        let store = BoardStore.restored(file: temp.file, sync: sync)
        #expect(store.tasks.map(\.id) == tasks.map(\.id))
        #expect(try sync.hasStoredTaskOrder())
    }

    /// CloudKit can import task records before the columns they name. That is a
    /// temporary incomplete snapshot, not a deliberate move to the Inbox; if it
    /// were adopted, the next save would make the temporary state permanent on
    /// every device.
    @Test func anIncompleteSyncImportDoesNotUnfileTasks() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let tasks = TestBoard.tasks(on: SeedData.defaultBoard)
        let board = BoardSnapshot(
            tasks: tasks, boards: SeedData.boards, labels: LabelDef.seed,
            nextSerial: 100, activeBoardID: SeedData.defaultBoard.id
        )
        try temp.file.write(board, generation: temp.file.nextWriteGeneration())
        try sync.apply(board)

        let task = try #require(tasks.first { $0.columnID != nil })
        let column = try #require(
            sync.container.mainContext.fetch(FetchDescriptor<StoredColumn>()).first {
                $0.id == task.columnID
            }
        )
        sync.container.mainContext.delete(column)
        try sync.container.mainContext.save()

        let store = BoardStore.restored(file: temp.file, sync: sync)
        #expect(store[task.id]?.placement == task.placement)
        let stored = try #require(
            sync.container.mainContext.fetch(FetchDescriptor<StoredTask>()).first { $0.id == task.id }
        )
        #expect(stored.boardID == task.boardID)
        #expect(stored.columnID == task.columnID)
    }

    @Test func anIncompleteRemoteUpdateDoesNotUnfileTasks() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let tasks = TestBoard.tasks(on: SeedData.defaultBoard)
        let board = BoardSnapshot(
            tasks: tasks, boards: SeedData.boards, labels: LabelDef.seed,
            nextSerial: 100, activeBoardID: SeedData.defaultBoard.id
        )
        try temp.file.write(board, generation: temp.file.nextWriteGeneration())
        try sync.apply(board)
        let store = BoardStore.restored(file: temp.file, sync: sync)

        let task = try #require(tasks.first { $0.columnID != nil })
        let column = try #require(
            sync.container.mainContext.fetch(FetchDescriptor<StoredColumn>()).first {
                $0.id == task.columnID
            }
        )
        sync.container.mainContext.delete(column)
        try sync.container.mainContext.save()

        store.mergeRemoteChanges()
        #expect(store[task.id]?.placement == task.placement)
    }

    /// The upgrade path: a board that only exists as JSON is folded into the
    /// records on the launch that first has them, rather than being lost or
    /// duplicated.
    @Test func aFileOnlyBoardIsMigratedIntoTheRecords() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let board = BoardSnapshot(
            tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: SeedData.boards,
            labels: LabelDef.seed, nextSerial: 210,
            activeBoardID: SeedData.defaultBoard.id, themes: TestBoard.otherThemes
        )
        try temp.file.write(board, generation: temp.file.nextWriteGeneration())
        #expect(try sync.load() == nil)

        let store = BoardStore.restored(file: temp.file, sync: sync)
        #expect(store.tasks.count == board.tasks.count)

        let records = try #require(try sync.load())
        #expect(Set(records.tasks.map(\.id)) == Set(board.tasks.map(\.id)))
        #expect(records.nextSerial == 210)
        #expect(records.themes == TestBoard.otherThemes)
    }

    /// A store that cannot be opened at all must not read as a board with
    /// nothing on it — that is the whole reason `board.json` stays.
    @Test func noRecordsAtAllFallsBackToTheFileRatherThanToAnEmptyBoard() throws {
        let temp = TempBoard()
        let board = BoardSnapshot(
            tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: SeedData.boards,
            labels: LabelDef.seed, nextSerial: 100,
            activeBoardID: SeedData.defaultBoard.id
        )
        try temp.file.write(board, generation: temp.file.nextWriteGeneration())

        let store = BoardStore.restored(file: temp.file, sync: nil)
        #expect(store.tasks.count == board.tasks.count)
        #expect(store.isSyncing == false)
    }

    /// Every save reaches both, or the two drift and the next launch picks the
    /// stale one.
    @Test func aMutationReachesTheRecordsAsWellAsTheFile() async throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = BoardStore.restored(file: temp.file, sync: sync)
        store.addTask(to: .inbox, title: "Written on this device")

        // `saveNow` is the synchronous path; the debounced one goes through the
        // same `pushToSync`.
        store.saveNow()
        let records = try #require(try sync.load())
        #expect(records.tasks.contains { $0.title == "Written on this device" })
    }

    /// What arrives from another device replaces this one's copy, because
    /// CloudKit has already merged the two — and it does so without pushing a
    /// step onto the undo stack, since undoing somebody else's edit on their
    /// behalf is worse than not offering to.
    @Test func aRemoteChangeIsAdoptedWithoutAnUndoStep() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let undo = RecordingUndoManager()
        // Grouping is done by `step` rather than by the run loop — see there.
        undo.groupsByEvent = false
        let store = BoardStore.restored(file: temp.file, sync: sync)
        store.undoManager = undo
        step(undo) { store.addTask(to: .inbox, title: "Mine") }
        store.saveNow()
        undo.removeAllActions()

        // Another device renames it, straight into the records — through a
        // *second* store over the same container, the way a CloudKit import
        // arrives: this device's own diff base must not hear about it, or the
        // merge's flush would treat the remote edit as something local to
        // write back over.
        var theirs = try #require(try sync.load())
        theirs.tasks = theirs.tasks.map { task in
            var edited = task
            if edited.title == "Mine" { edited.title = "Theirs" }
            return edited
        }
        try BoardSyncStore(container: sync.container, isSyncing: false).apply(theirs)

        store.mergeRemoteChanges()
        #expect(store.tasks.contains { $0.title == "Theirs" })
        #expect(store.tasks.contains { $0.title == "Mine" } == false)
        #expect(undo.canUndo == false, "a remote change put a step on the undo stack")
    }

    // MARK: The three lists CloudKit cannot merge

    /// **The upgrade guard.** A record set written before there was anywhere to
    /// put the views, the palette or the themes carries none of them, and
    /// `load()` cannot say so: it hands back a `BoardSnapshot`, whose lists are
    /// not optional, so what comes out is the seeded seven and the seed six.
    /// Adopting that is adopting a silence — and it is what used to take a
    /// saved view away on the launch after it was made.
    @Test func aRecordSetFromBeforeTheseFieldsExistedTakesNothingAway() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let mine = Self.boardOfItsOwn()
        try temp.file.write(mine, generation: temp.file.nextWriteGeneration())
        try sync.apply(mine)
        try Self.forgetTheNewFields(in: sync)

        let store = BoardStore.restored(file: temp.file, sync: sync)
        #expect(store.views == mine.views, "the launch dropped the views the file carried")
        #expect(store.savedColors == mine.palette, "the launch dropped the saved colours")
        #expect(store.themes == mine.themes, "the launch dropped the themes")
        #expect(store.mergeRemoteChanges() == false, "a silence read as news from another device")
        #expect(store.views == mine.views, "a pull dropped the views")
        #expect(store.savedColors == mine.palette, "a pull dropped the saved colours")
    }

    /// And they do travel now. A view made on another device arrives — which is
    /// the whole feature, and what `SyncSchema` had no room for until
    /// `StoredMeta` grew `viewsJSON` and `paletteJSON`.
    @Test func aViewAndAColourMadeOnAnotherDeviceArrive() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        try sync.apply(Self.boardOfItsOwn(changedAt: TestBoard.epoch))
        let store = BoardStore.restored(file: temp.file, sync: sync)

        #expect(store.views.contains { $0.name == "Ship this week" },
                "a view made on another device did not arrive")
        #expect(store.savedColors.contains { $0.swatch == .hex(0x123456) },
                "a colour saved on another device did not arrive")
        #expect(store.themes.custom.contains { $0.id == Self.theirTheme.id },
                "a theme made on another device did not arrive")
    }

    /// Every field of all three, through the records and back.
    @Test func theThreeListsSurviveTheRoundTrip() throws {
        let sync = try BoardSyncStore.inMemory()
        let written = Self.boardOfItsOwn(changedAt: TestBoard.epoch)
        try sync.apply(written)

        let read = try #require(try sync.load())
        #expect(read.views == written.views)
        #expect(read.palette == written.palette)
        #expect(read.themes == written.themes)
        #expect(read.viewsChangedAt == TestBoard.epoch)
        #expect(read.paletteChangedAt == TestBoard.epoch)
        #expect(read.themesChangedAt == TestBoard.epoch)
        #expect(try sync.carriedLists() == [.themes, .views, .palette])
    }

    /// The dated case: the records were edited after this device was, so the
    /// records win — and the reverse holds too, which is the half a clock buys
    /// that last-writer-wins never did.
    @Test func theNewerEditWinsWhicheverSideMadeIt() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        var mine = Self.boardOfItsOwn(changedAt: TestBoard.epoch)
        mine.views = SavedView.seededAll + [SavedView.blank(named: "Mine")]
        try temp.file.write(mine, generation: temp.file.nextWriteGeneration())
        try sync.apply(Self.boardOfItsOwn(changedAt: TestBoard.epoch.addingTimeInterval(60)))

        let later = BoardStore.restored(file: temp.file, sync: sync)
        #expect(later.views.contains { $0.name == "Ship this week" },
                "the newer list did not win")
        #expect(later.views.contains { $0.name == "Mine" } == false,
                "the older list survived a merge it should have lost")

        // The same two boards with the dates the other way round.
        let other = TempBoard()
        let secondSync = try BoardSyncStore.inMemory()
        mine.viewsChangedAt = TestBoard.epoch.addingTimeInterval(120)
        try other.file.write(mine, generation: other.file.nextWriteGeneration())
        try secondSync.apply(Self.boardOfItsOwn(changedAt: TestBoard.epoch.addingTimeInterval(60)))

        let earlier = BoardStore.restored(file: other.file, sync: secondSync)
        #expect(earlier.views.contains { $0.name == "Mine" }, "this device's newer list lost")
    }

    /// The undated case, and the reason the dates were worth a migration: two
    /// devices that both made views before there was a date to make them under
    /// **keep both lists**, because picking between two things nobody can date
    /// is picking whose afternoon to throw away.
    @Test func twoUndatedListsAreMergedRatherThanChosenBetween() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        var mine = Self.boardOfItsOwn()
        mine.views = SavedView.seededAll + [SavedView.blank(named: "Mine")]
        try temp.file.write(mine, generation: temp.file.nextWriteGeneration())
        try sync.apply(Self.boardOfItsOwn())

        let store = BoardStore.restored(file: temp.file, sync: sync)
        #expect(store.views.contains { $0.name == "Mine" }, "this device's undated view was thrown away")
        #expect(store.views.contains { $0.name == "Ship this week" },
                "the other device's undated view was thrown away")
        #expect(store.viewsChangedAt == nil, "a merge of two undated lists invented a date")
    }

    /// A board that arrives from a **file** is dated now, whatever the bytes
    /// say. A restored backup is a decision somebody is making this afternoon,
    /// and carrying the backup's own three-month-old stamp would let any other
    /// device overrule it the moment it synced.
    @Test func anImportedBoardIsDatedNowRatherThanWhenItWasWritten() throws {
        let store = TestBoard.store()
        var arriving = Self.boardOfItsOwn(changedAt: TestBoard.epoch)
        // One card this board has not got, so the import has something to do:
        // an import that changes nothing files no step and adopts nothing.
        arriving.tasks = [TaskItem(code: "IM-400", title: "Arrived in the import")]
        store.importBoard(arriving)

        let stamped = try #require(store.viewsChangedAt)
        #expect(stamped > TestBoard.epoch, "the import carried the file's own date across")
    }

    /// A theme somebody made, a view and a colour, on a board that is otherwise
    /// the fixture's. `changedAt` dates all three; `nil` is a board from before
    /// there were dates.
    private static func boardOfItsOwn(changedAt: Date? = nil) -> BoardSnapshot {
        BoardSnapshot(
            tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: SeedData.boards,
            labels: LabelDef.seed, nextSerial: 340,
            activeBoardID: SeedData.defaultBoard.id,
            views: SavedView.seededAll + [SavedView.blank(named: "Ship this week")],
            palette: PaletteSwatch.seed + [PaletteSwatch(.hex(0x123456), name: "Slate")],
            themes: ThemeSettings(
                lightID: ThemePresets.porcelainID, darkID: ThemePresets.emberID,
                custom: [theirTheme]
            ),
            viewsChangedAt: changedAt, paletteChangedAt: changedAt, themesChangedAt: changedAt
        )
    }

    private static let theirTheme: Theme = {
        var theme = ThemePresets.fallback(for: .light)
        theme.id = "theirs"
        theme.name = "Theirs"
        return theme
    }()

    /// Turns a record set into one written by a build that had never heard of
    /// these three attributes, which is what every device's records look like
    /// the first time it runs this version.
    private static func forgetTheNewFields(in sync: BoardSyncStore) throws {
        let meta = try #require(
            sync.container.mainContext.fetch(FetchDescriptor<StoredMeta>()).first
        )
        meta.themesJSON = nil
        meta.viewsJSON = nil
        meta.paletteJSON = nil
        meta.themesChangedAt = nil
        meta.viewsChangedAt = nil
        meta.paletteChangedAt = nil
        try sync.container.mainContext.save()
    }

    /// The race the debounce opened, which is what made a just-made board
    /// flash into the sidebar and vanish: the push to the records rides the
    /// save debounce, so a change notification processed inside that window
    /// found records without the board and the merge adopted them. The merge
    /// flushes what is pending before it reads, so the read returns the union.
    @Test func aMergeKeepsAnEditTheDebounceHasNotPushedYet() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = BoardStore.restored(file: temp.file, sync: sync)
        store.saveNow()

        // The click: a board is made, its settings sheet is about to open, and
        // its push is still riding the debounce when the notification lands.
        let made = try #require(store.createBoard(named: "Fresh"))
        store.mergeRemoteChanges()

        #expect(store.boards.contains { $0.id == made }, "the merge swallowed the pending board")
        #expect(try #require(try sync.load()).boards.contains { $0.id == made },
                "the merge read the records without flushing the pending board into them")
    }
}

/// A record store that fails to read on command, wrapping a real one — the
/// launch-time failure `BoardSyncStore` cannot be made to produce on purpose,
/// and the seam `SyncStoring` exists for. Writes are counted so a test can
/// state "nothing was pushed" rather than inferring it.
@MainActor
private final class FlakySyncStore: SyncStoring {
    let wrapped: BoardSyncStore
    var loadFails = false
    private(set) var applyCount = 0

    init(wrapping wrapped: BoardSyncStore) { self.wrapped = wrapped }

    var isSyncing: Bool { wrapped.isSyncing }
    func load() throws -> BoardSnapshot? {
        if loadFails { throw CocoaError(.fileReadUnknown) }
        return try wrapped.load()
    }
    func carriedLists() throws -> SyncedLists { try wrapped.carriedLists() }
    func hasStoredTaskOrder() throws -> Bool { try wrapped.hasStoredTaskOrder() }
    func backfillTaskPositions(from taskIDs: [TaskItem.ID]) throws {
        try wrapped.backfillTaskPositions(from: taskIDs)
    }
    func hasStoredBoardSymbols() throws -> Bool { try wrapped.hasStoredBoardSymbols() }
    func backfillBoardSymbols(from boards: [Board]) throws {
        try wrapped.backfillBoardSymbols(from: boards)
    }
    func apply(_ snapshot: BoardSnapshot, deleting: SyncIDs) throws {
        applyCount += 1
        try wrapped.apply(snapshot, deleting: deleting)
    }
    func reconnect() { wrapped.reconnect() }
}

/// What a read failure at launch must and must not do.
///
/// The hazard these pin: `restored` used to read the records through `try?`,
/// which makes "the store held nothing" and "the read failed" the same `nil` —
/// and the file path below both ends in a push that rewrites every record. A
/// transient failure therefore handed another device's newer board a stale
/// overwrite. Now the failure blocks every push until a read succeeds, and the
/// first successful read merges the two sides task by task.
@MainActor
@Suite struct SyncReadFailureTests {
    /// The board both sides start from, filed onto the seed board so the
    /// placements are legal — see `SyncStoreTests.filed`.
    private static let filed = TestBoard.tasks(on: SeedData.defaultBoard)

    private func snapshot(tasks: [TaskItem]) -> BoardSnapshot {
        BoardSnapshot(tasks: tasks, boards: SeedData.boards, labels: LabelDef.seed,
                      nextSerial: 100, activeBoardID: SeedData.defaultBoard.id)
    }

    @Test func aFailedReadFallsBackToTheFileWithoutPushingOverTheRecords() throws {
        let temp = TempBoard()
        let real = try BoardSyncStore.inMemory()
        var theirs = Self.filed[0]
        theirs.title = "What the records say"
        try real.apply(snapshot(tasks: [theirs]))

        var mine = theirs
        mine.title = "What the file says"
        try temp.file.write(snapshot(tasks: [mine]), generation: temp.file.nextWriteGeneration())

        let flaky = FlakySyncStore(wrapping: real)
        flaky.loadFails = true
        let store = BoardStore.restored(file: temp.file, sync: flaky)

        #expect(store.tasks.first?.title == "What the file says",
                "the file is still what puts a board on screen")
        #expect(store.isSyncReadBlocked)
        #expect(flaky.applyCount == 0, "a failed read pushed the file over the records")
        #expect(try #require(try real.load()).tasks.first?.title == "What the records say")
    }

    @Test func aBlockedStoreStillSavesTheFileAndPushesNothing() throws {
        let temp = TempBoard()
        let real = try BoardSyncStore.inMemory()
        try real.apply(snapshot(tasks: [Self.filed[0]]))
        try temp.file.write(snapshot(tasks: [Self.filed[0]]),
                            generation: temp.file.nextWriteGeneration())

        let flaky = FlakySyncStore(wrapping: real)
        flaky.loadFails = true
        let store = BoardStore.restored(file: temp.file, sync: flaky)

        store.addTask(to: .inbox, title: "Made while blocked")
        store.saveNow()

        #expect(store.isSyncReadBlocked, "a save must not unblock a read that is still failing")
        #expect(flaky.applyCount == 0)
        let onDisk = try #require(temp.file.load().snapshot)
        #expect(onDisk.tasks.contains { $0.title == "Made while blocked" },
                "blocking the records must not block the file")
    }

    @Test func theFirstSuccessfulReadMergesBothSidesAndUnblocks() throws {
        let temp = TempBoard()
        let real = try BoardSyncStore.inMemory()
        let old = Date(timeIntervalSinceNow: -7200)
        let newer = Date(timeIntervalSinceNow: -3600)

        // The records hold a later edit of a shared task, and a task this
        // device has never seen.
        var theirs = Self.filed[0]
        theirs.title = "Theirs, newer"
        theirs.updatedAt = newer
        var arrived = Self.filed[2]
        arrived.title = "Arrived remotely"
        arrived.updatedAt = newer
        try real.apply(snapshot(tasks: [theirs, arrived]))

        // The file holds the stale edit of the shared task, and a task the
        // records used to hold and no longer do — deleted on another device.
        var mine = theirs
        mine.title = "Mine, stale"
        mine.updatedAt = old
        var deletedRemotely = Self.filed[1]
        deletedRemotely.updatedAt = old
        try temp.file.write(snapshot(tasks: [mine, deletedRemotely]),
                            generation: temp.file.nextWriteGeneration())

        let flaky = FlakySyncStore(wrapping: real)
        flaky.loadFails = true
        let store = BoardStore.restored(file: temp.file, sync: flaky)
        store.addTask(to: .inbox, title: "Made while blocked")

        flaky.loadFails = false
        #expect(store.mergeRemoteChanges(), "the recovery read adopted nothing")

        #expect(store.isSyncReadBlocked == false)
        #expect(store[theirs.id]?.title == "Theirs, newer", "the stale side won a shared task")
        #expect(store.tasks.contains { $0.title == "Arrived remotely" })
        #expect(store.tasks.contains { $0.title == "Made while blocked" },
                "recovery dropped a task made while blocked")
        #expect(store[deletedRemotely.id] == nil, "recovery resurrected a remotely deleted task")

        let records = try #require(try real.load())
        #expect(records.tasks.contains { $0.title == "Made while blocked" },
                "recovery did not push the task the records never saw")
        #expect(records.tasks.first { $0.id == theirs.id }?.title == "Theirs, newer")
    }

    @Test func aStoreThatReadsBackEmptyIsSeededRatherThanStayingBlocked() throws {
        let temp = TempBoard()
        let real = try BoardSyncStore.inMemory()
        try temp.file.write(snapshot(tasks: [Self.filed[0]]),
                            generation: temp.file.nextWriteGeneration())

        let flaky = FlakySyncStore(wrapping: real)
        flaky.loadFails = true
        let store = BoardStore.restored(file: temp.file, sync: flaky)
        #expect(store.isSyncReadBlocked)

        flaky.loadFails = false
        #expect(store.mergeRemoteChanges() == false, "an empty store is not something arriving")
        #expect(store.isSyncReadBlocked == false)
        #expect(try #require(try real.load()).tasks.map(\.id) == [Self.filed[0].id],
                "an empty readable store should have been seeded from this device")
    }

    @Test func theMergeRuleKeepsTheNewerSideOfEachTask() {
        let old = Date(timeIntervalSinceNow: -7200)
        let blockedSince = Date(timeIntervalSinceNow: -3600)
        let newer = Date(timeIntervalSinceNow: -60)

        var localWins = Self.filed[0]
        localWins.title = "Local, newer"
        localWins.updatedAt = newer
        var localWinsRemote = localWins
        localWinsRemote.title = "Remote, older"
        localWinsRemote.updatedAt = old

        var remoteWins = Self.filed[1]
        remoteWins.title = "Local, older"
        remoteWins.updatedAt = old
        var remoteWinsRemote = remoteWins
        remoteWinsRemote.title = "Remote, newer"
        remoteWinsRemote.updatedAt = newer

        var staleLocalOnly = Self.filed[2]
        staleLocalOnly.updatedAt = old
        var freshLocalOnly = Self.filed[3]
        freshLocalOnly.updatedAt = newer

        let merged = BoardStore.merging(
            localTasks: [localWins, remoteWins, staleLocalOnly, freshLocalOnly],
            intoRemote: [localWinsRemote, remoteWinsRemote],
            keepingLocalOnlyTouchedSince: blockedSince
        )
        #expect(merged.map(\.title) == ["Local, newer", "Remote, newer", freshLocalOnly.title],
                "order is the records', with kept local-only tasks at the end")

        // With no moment to compare against, keeping is the answer: a
        // resurrected card can be deleted again, a lost one is gone.
        let keptAnyway = BoardStore.merging(
            localTasks: [staleLocalOnly], intoRemote: [],
            keepingLocalOnlyTouchedSince: nil
        )
        #expect(keptAnyway.map(\.id) == [staleLocalOnly.id])
    }
}

/// The encode and decode failure paths in `BoardSyncStore` — unreachable with
/// the real coders and the values the app writes, so the encode side runs
/// through `encodingFailsForTesting` and the decode side through a
/// hand-corrupted record. What they pin: a value that will not encode must
/// never poison the store or reset another device, and a record this build
/// cannot read must never be deleted by it.
@MainActor
@Suite struct SyncEncodingFailureTests {
    private static let filed = TestBoard.tasks(on: SeedData.defaultBoard)

    private func snapshot(tasks: [TaskItem], themes: ThemeSettings = .seed) -> BoardSnapshot {
        BoardSnapshot(tasks: tasks, boards: SeedData.boards, labels: LabelDef.seed,
                      nextSerial: 100, activeBoardID: SeedData.defaultBoard.id, themes: themes)
    }

    /// The old behaviour wrote `Data()` instead — a row that satisfied the
    /// already-written skip on every later pass, was never repaired, and was
    /// silently dropped by `value(of:)` on every other device.
    @Test func aKindThatWillNotEncodeIsSkippedAndWrittenOnceItCan() throws {
        let sync = try BoardSyncStore.inMemory()
        var task = Self.filed[0]
        task.activity = [ActivityEntry(.created, when: Date(timeIntervalSinceNow: -60)),
                         ActivityEntry(.archived)]

        sync.encodingFailsForTesting = true
        try sync.apply(snapshot(tasks: [task]))
        #expect(try sync.container.mainContext.fetch(FetchDescriptor<StoredActivity>()).isEmpty,
                "an unencodable kind reached the store anyway")

        // The rows are written the next time the task changes.
        sync.encodingFailsForTesting = false
        task.title = "Edited"
        task.updatedAt = .now
        try sync.apply(snapshot(tasks: [task]))
        #expect(try #require(try sync.load()).tasks.first?.activity.count == 2)
    }

    @Test func themesThatWillNotEncodeLeaveThePreviousThemesStanding() throws {
        let sync = try BoardSyncStore.inMemory()
        try sync.apply(snapshot(tasks: [Self.filed[0]], themes: TestBoard.otherThemes))

        sync.encodingFailsForTesting = true
        try sync.apply(snapshot(tasks: [Self.filed[0]], themes: .seed))

        // Read through a second store over the same container: the first one's
        // diff base believes the write landed, which is the staleness the
        // comment in `applyMeta` accepts. What may not happen is `nil` landing
        // in the record — the next device would read it as `.seed`.
        let other = BoardSyncStore(container: sync.container, isSyncing: false)
        #expect(try #require(try other.load()).themes == TestBoard.otherThemes)
    }

    /// `StoredActivity.kind` keeps the encoded form precisely so a case this
    /// build does not know survives a round trip through a device that does —
    /// which the orphan rule in `applyTask` used to defeat by deleting any row
    /// the value did not carry.
    @Test func aRowThisBuildCannotReadIsLeftOutOfTheValueButKeptInTheStore() throws {
        let sync = try BoardSyncStore.inMemory()
        var task = Self.filed[0]
        task.activity = [ActivityEntry(.created)]
        try sync.apply(snapshot(tasks: [task]))

        // A newer build's entry: a kind this build's decoder has never heard of.
        let record = try #require(
            sync.container.mainContext.fetch(FetchDescriptor<StoredTask>()).first { $0.id == task.id }
        )
        let foreign = StoredActivity(id: UUID())
        foreign.kind = Data(#"{"sentToMars":{}}"#.utf8)
        foreign.when = .now
        sync.container.mainContext.insert(foreign)
        foreign.task = record
        try sync.container.mainContext.save()

        // Left out of the value…
        let other = BoardSyncStore(container: sync.container, isSyncing: false)
        #expect(try #require(try other.load()).tasks.first?.activity.count == 1)

        // …and not deleted as an orphan when the task next changes.
        task.title = "Edited"
        task.updatedAt = .now
        try other.apply(snapshot(tasks: [task]))
        let rows = try sync.container.mainContext.fetch(FetchDescriptor<StoredActivity>())
        #expect(rows.count == 2, "the apply deleted a newer build's activity record")
    }
}


/// The rule that settles the three lists CloudKit cannot merge, asked as
/// arithmetic rather than through a store.
///
/// `SyncStoreTests` and `SyncWiringTests` drive it through real records, which
/// is what proves it is *wired up*; this is where the rule itself is pinned,
/// one row of the table in ``SharedList`` at a time. A rule this small is
/// cheap to state and expensive to get wrong: every branch of it is somebody's
/// afternoon of work either kept or thrown away.
@MainActor
@Suite struct SharedListTests {
    private let mine = [SavedView.blank(named: "Mine")]
    private let theirs = [SavedView.blank(named: "Theirs")]
    private let monday = TestBoard.epoch
    private var tuesday: Date { monday.addingTimeInterval(86_400) }

    private func resolve(
        _ local: [SavedView], _ localStamp: Date?,
        _ remote: [SavedView]?, _ remoteStamp: Date?
    ) -> (list: [SavedView], changedAt: Date?) {
        SharedList.resolve(local: local, changedAt: localStamp, remote: remote, changedAt: remoteStamp)
    }

    /// Row one: the records have never been written with one. Not an empty
    /// list, not the defaults — no answer, which is what every record set
    /// written before the field existed says.
    @Test func nothingWrittenLeavesThisDeviceAlone() {
        #expect(resolve(mine, tuesday, nil, nil).list == mine)
        #expect(resolve(mine, tuesday, nil, nil).changedAt == tuesday)
        // And with nothing on this side either, still nothing invented.
        #expect(resolve([], nil, nil, nil).changedAt == nil)
    }

    /// Row two, both directions.
    @Test func betweenTwoDatedListsTheNewerStands() {
        #expect(resolve(mine, monday, theirs, tuesday).list == theirs)
        #expect(resolve(mine, monday, theirs, tuesday).changedAt == tuesday)
        #expect(resolve(mine, tuesday, theirs, monday).list == mine)
        #expect(resolve(mine, tuesday, theirs, monday).changedAt == tuesday)
    }

    /// A tie between two dated lists keeps this device's, which is the answer
    /// that changes nothing — two lists stamped at the same instant are the
    /// same edit arriving twice far more often than they are two.
    @Test func aTieOnTheDateChangesNothing() {
        #expect(resolve(mine, monday, theirs, monday).list == mine)
    }

    /// Row three, and the reason the dates were worth a migration: where either
    /// side is undated, **both** lists stand. Order is this device's first, so
    /// a merge never reshuffles a sidebar somebody has arranged.
    @Test func anUndatedListIsMergedRatherThanOverwritten() {
        #expect(resolve(mine, nil, theirs, tuesday).list == mine + theirs)
        #expect(resolve(mine, tuesday, theirs, nil).list == mine + theirs)
        #expect(resolve(mine, nil, theirs, nil).list == mine + theirs)
    }

    /// The merge is by id, so the same view held by both devices is not doubled
    /// — which is every one of the seeded seven, on every pair of devices.
    @Test func aMergeDoesNotDoubleWhatBothSidesHold() {
        let shared = SavedView.seededAll
        #expect(resolve(shared + mine, nil, shared + theirs, nil).list == shared + mine + theirs)
    }

    /// A merge carries whichever date there was, and invents none where there
    /// was none: the pair stays undated until somebody actually edits it, and
    /// only then does the clock start deciding.
    @Test func aMergeKeepsTheDateItWasGiven() {
        #expect(resolve(mine, nil, theirs, tuesday).changedAt == tuesday)
        #expect(resolve(mine, tuesday, theirs, nil).changedAt == tuesday)
        #expect(resolve(mine, nil, theirs, nil).changedAt == nil)
    }

    /// Themes are a list *and* two scalars. The custom themes merge like any
    /// other list; the two slots do not — an undated pair keeps this machine's,
    /// because which theme is showing is a fact about the screen in front of
    /// you rather than about the work.
    @Test func themesMergeTheirCustomsAndKeepThisMachinesSlots() {
        let local = ThemeSettings(lightID: "a", darkID: "b", custom: [Self.theme("mine")])
        let remote = ThemeSettings(lightID: "c", darkID: "d", custom: [Self.theme("theirs")])

        let undated = SharedList.resolve(local: local, changedAt: nil, remote: remote, changedAt: nil)
        #expect(undated.themes.custom.map(\.id) == ["mine", "theirs"], "a theme somebody made was lost")
        #expect(undated.themes.lightID == "a", "an undated merge repainted the window")
        #expect(undated.themes.darkID == "b")

        // Dated, and theirs is newer: the slots travel with the decision.
        let dated = SharedList.resolve(local: local, changedAt: monday, remote: remote, changedAt: tuesday)
        #expect(dated.themes.lightID == "c")
        #expect(dated.themes.custom.map(\.id) == ["theirs"])
    }

    private static func theme(_ id: Theme.ID) -> Theme {
        var theme = ThemePresets.fallback(for: .light)
        theme.id = id
        return theme
    }
}
