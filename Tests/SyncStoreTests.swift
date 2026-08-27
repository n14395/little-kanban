import Foundation
import SwiftData
import Testing
@testable import Simple_Kanban

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
        let written = snapshot()
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

        try sync.apply(snapshot(tasks: []))
        #expect(try context.fetch(FetchDescriptor<StoredTask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredSubtask>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StoredActivity>()).isEmpty)
    }

    @Test func aDeletedBoardTakesItsColumnsWithIt() throws {
        let sync = try store()
        try sync.apply(snapshot())
        let context = sync.container.mainContext
        #expect(try context.fetch(FetchDescriptor<StoredColumn>()).isEmpty == false)

        try sync.apply(snapshot(tasks: [], boards: []))
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
        #expect(SyncSchema.cloudContainerID == "iCloud.com.n14395.SimpleKanban")
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
