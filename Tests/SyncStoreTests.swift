// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

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

    /// The repeat rule travels as an encoded blob — `StoredTask.recurrence` —
    /// and clearing it has to clear it on every device rather than leaving the
    /// last synced rule standing.
    @Test func aRepeatRuleRoundTripsAndItsClearingSticks() throws {
        let sync = try store()
        var card = Self.filed[1]
        let rule = RecurrenceRule(interval: 2, unit: .week, weekdays: [2, 6],
                                  basis: .completion,
                                  until: CalendarDay(year: 2027, month: 3, day: 1))
        card.recurrence = rule
        card.updatedAt = TestBoard.at(500)
        try sync.apply(snapshot(tasks: [card]))
        let read = try #require(try sync.load())
        #expect(read.tasks.first { $0.id == card.id }?.recurrence == rule)

        card.recurrence = nil
        card.updatedAt = TestBoard.at(100)
        try sync.apply(snapshot(tasks: [card]))
        let reread = try #require(try sync.load())
        #expect(reread.tasks.first { $0.id == card.id }?.recurrence == nil)
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

    /// **Scenario 6 of the two-device checklist, which used to fail.**
    ///
    /// One device moves a card to another column; the other renames it before
    /// the move arrives. Both edits must stand. They did not: a push carries
    /// this device's whole view of a card, so the rename wrote back the column
    /// it still believed the card was in and put it back — the move was not
    /// merged and lost, it was overwritten by a device that had not heard of
    /// it. Found by hand on a Mac and an iPhone; this is so it is never found
    /// that way again.
    ///
    /// The other device's edit is made directly on the record, which is what a
    /// merge from CloudKit amounts to. The base is left alone deliberately —
    /// `invalidateDiff()` is *not* called — because the failure needs a device
    /// that thinks it is still in step, which is the ordinary case.
    @Test func aRenameDoesNotDragACardBackFromAnotherDevicesMove() throws {
        let sync = try store()
        try sync.apply(snapshot())

        let context = sync.container.mainContext
        let moved = try #require(Self.filed.first)
        let destination = try #require(
            SeedData.defaultBoard.columns.last { $0.id != moved.columnID }?.id
        )
        let record = try #require(
            try context.fetch(FetchDescriptor<StoredTask>()).first { $0.id == moved.id }
        )
        #expect(record.columnID == moved.columnID, "the fixture is already in the destination")
        record.columnID = destination
        try context.save()

        // This device only ever touched the title, and its view of the card
        // still carries the old column.
        var renamed = Self.filed
        renamed[0].title = "Renamed on the phone"
        renamed[0].updatedAt = .now
        try sync.apply(snapshot(tasks: renamed))

        let after = try #require(
            try context.fetch(FetchDescriptor<StoredTask>()).first { $0.id == moved.id }
        )
        #expect(after.title == "Renamed on the phone", "this device's own edit was dropped")
        #expect(after.columnID == destination,
                "the rename dragged the card back out of the other device's column")
    }

    /// The same rule one level down: a tick on one device and a rename on the
    /// other are two edits to one checklist row, and neither may undo the other.
    @Test func aSubtaskRenameDoesNotUntickAnotherDevicesTick() throws {
        let sync = try store()
        try sync.apply(snapshot())

        let context = sync.container.mainContext
        // An *unticked* row, so the other device's tick is a change rather than
        // a restatement — picked by its state rather than by its index, which
        // the fixture is free to reorder.
        let carrier = try #require(Self.filed.firstIndex { $0.subtasks.contains { !$0.done } })
        let at = try #require(Self.filed[carrier].subtasks.firstIndex { !$0.done })
        let row = Self.filed[carrier].subtasks[at]
        let record = try #require(
            try context.fetch(FetchDescriptor<StoredSubtask>()).first { $0.id == row.id }
        )
        record.done = true
        try context.save()

        var edited = Self.filed
        edited[carrier].subtasks[at].text = "Reworded on the phone"
        edited[carrier].updatedAt = .now
        try sync.apply(snapshot(tasks: edited))

        let after = try #require(
            try context.fetch(FetchDescriptor<StoredSubtask>()).first { $0.id == row.id }
        )
        #expect(after.text == "Reworded on the phone")
        #expect(after.done, "the rewording unticked what the other device ticked")
    }

    /// **Scenario 10's other half: the row that is *added*.** B puts a new row
    /// on X's checklist; A retitles X before hearing about it. The orphan
    /// sweep used to read the unfamiliar record as "not in my snapshot, so
    /// deleted" and threw B's work away with A's push — deletion now requires
    /// the diff base to have named the row, the same licence-shaped question
    /// every other writer asks.
    @Test func aSubtaskAddedOnAnotherDeviceSurvivesThisDevicesEdit() throws {
        let sync = try store()
        try sync.apply(snapshot())

        let context = sync.container.mainContext
        let carrier = try #require(Self.filed.first { !$0.subtasks.isEmpty })
        let record = try #require(
            try context.fetch(FetchDescriptor<StoredTask>()).first { $0.id == carrier.id }
        )
        let added = StoredSubtask(id: UUID())
        added.text = "Added on the phone"
        added.position = carrier.subtasks.count
        context.insert(added)
        added.task = record
        try context.save()

        var edited = Self.filed
        let at = try #require(edited.firstIndex { $0.id == carrier.id })
        edited[at].title = "Retitled on the Mac"
        edited[at].updatedAt = .now
        try sync.apply(snapshot(tasks: edited))

        #expect(try context.fetch(FetchDescriptor<StoredSubtask>()).contains { $0.id == added.id },
                "a retitle here deleted the checklist row another device had just added")
    }

    /// And the same again for the history: an entry another device has just
    /// written is not "undone" merely because this device's snapshot has not
    /// heard of it. Append-only cuts both ways — the base has to have named an
    /// entry before its absence can mean an undo.
    @Test func anActivityEntryMadeOnAnotherDeviceSurvivesThisDevicesEdit() throws {
        let sync = try store()
        try sync.apply(snapshot())

        let context = sync.container.mainContext
        let carrier = try #require(Self.filed.first)
        let record = try #require(
            try context.fetch(FetchDescriptor<StoredTask>()).first { $0.id == carrier.id }
        )
        let made = StoredActivity(id: UUID())
        made.kind = try JSONEncoder().encode(ActivityEntry.Kind.archived)
        made.when = .now
        context.insert(made)
        made.task = record
        try context.save()

        var edited = Self.filed
        edited[0].title = "Retitled here"
        edited[0].updatedAt = .now
        try sync.apply(snapshot(tasks: edited))

        #expect(try context.fetch(FetchDescriptor<StoredActivity>()).contains { $0.id == made.id },
                "an edit here deleted the history another device had just written")
    }

    /// **Scenario 8 of the two-device checklist.** Two devices reorder the same
    /// board's columns differently. A column's position carries no clock, so
    /// nobody's order is defended — the records settle on whichever push came
    /// last, and every read after that hands back the one order, which is the
    /// whole of the row's promise: convergence, not a winner on the merits.
    @Test func competingColumnReordersConvergeOnTheLastPush() throws {
        let sync = try store()
        try sync.apply(snapshot())

        // The other device establishes its own diff base before either moves.
        let other = BoardSyncStore(container: sync.container, isSyncing: false)
        var theirs = try #require(try other.load())

        var mine = snapshot()
        mine.boards[0].columns.reverse()
        try sync.apply(mine)

        let rotated = Array(theirs.boards[0].columns.dropFirst())
            + Array(theirs.boards[0].columns.prefix(1))
        theirs.boards[0].columns = rotated
        try other.apply(theirs)

        let read = try #require(
            try BoardSyncStore(container: sync.container, isSyncing: false).load()
        )
        #expect(read.boards[0].columns.map(\.id) == rotated.map(\.id),
                "the records did not settle on the last push's order")
        // And both writers read the same answer back — the convergence itself.
        let mineAfter = try #require(try sync.load())
        let theirsAfter = try #require(try other.load())
        #expect(mineAfter.boards[0].columns.map(\.id) == theirsAfter.boards[0].columns.map(\.id))
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

    /// **A merge that adopts nothing still advances the watermark.** Device A
    /// makes a view and pulls its own echo — a merge with nothing to adopt —
    /// and device B then deletes that view. Advanced by the echo, the mark
    /// stands at the view's own stamp and the deletion reads as the deletion
    /// it is. Left behind — which is what only advancing on *adopting* merges
    /// came to — the view's stamp stood ahead of the mark, read as an
    /// addition A had never heard, and came back; A's next push then taught
    /// the device that deleted it to take it back too, and the two never
    /// converged again. See `BoardStore.advanceWatermarks(to:)`.
    @Test func aMergeWithNothingToAdoptStillAdvancesTheWatermark() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = BoardStore.restored(file: temp.file, sync: sync)
        store.saveNow()

        let made = store.addView(named: "Made here")
        store.saveNow()

        // The echo: this device's own push coming back as a change
        // notification, which is most merges on a board one person works.
        #expect(store.mergeRemoteChanges() == false, "an echo counted as news")
        #expect(store.viewsSyncedAt == store.viewsChangedAt,
                "the echo consumed the records' stamp without moving the watermark")

        // The other device deletes the view. Two applies for the fresh-device
        // rule in `applyMeta`: the first establishes the writer's base, the
        // second is the edit.
        var theirs = try #require(try sync.load())
        let writer = BoardSyncStore(container: sync.container, isSyncing: false)
        try writer.apply(theirs)
        theirs.views.removeAll { $0.id == made.id }
        theirs.viewsChangedAt = .now
        try writer.apply(theirs)

        store.mergeRemoteChanges()
        #expect(store.views.contains { $0.id == made.id } == false,
                "the deleted view resurrected against a stale watermark")
    }

    /// The marks live in `board.json` and nowhere else, and the launch path
    /// with no records to ask — which is also where a *failed* record read
    /// lands — used to leave them behind: the session then merged its first
    /// recovery against "never heard anything" and could resurrect once
    /// before self-correcting.
    @Test func aLaunchWithoutRecordsKeepsTheWatermarksFromTheFile() throws {
        let temp = TempBoard()
        let heard = TestBoard.at(500)
        let board = BoardSnapshot(
            tasks: [], labels: LabelDef.seed, nextSerial: 100,
            activeBoardID: SeedData.defaultBoard.id,
            viewsSyncedAt: heard, paletteSyncedAt: heard, themesSyncedAt: heard
        )
        try temp.file.write(board, generation: temp.file.nextWriteGeneration())

        let store = BoardStore.restored(file: temp.file)
        #expect(store.viewsSyncedAt == heard)
        #expect(store.paletteSyncedAt == heard)
        #expect(store.themesSyncedAt == heard)
    }

    /// The other launch path that reads the file: records held back because a
    /// task arrived before its column. The local board stays visible and so
    /// do its watermarks — the session merges the moment the records complete,
    /// and it must not do so as a device that has never heard anything.
    @Test func anIncompleteSyncLaunchKeepsTheWatermarksFromTheFile() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let heard = TestBoard.at(500)
        let tasks = TestBoard.tasks(on: SeedData.defaultBoard)
        let board = BoardSnapshot(
            tasks: tasks, labels: LabelDef.seed, nextSerial: 100,
            activeBoardID: SeedData.defaultBoard.id,
            viewsSyncedAt: heard, paletteSyncedAt: heard, themesSyncedAt: heard
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
        // The held-back path, proven the way its own suite proves it: the
        // incomplete records were not adopted.
        #expect(store[task.id]?.placement == task.placement)
        #expect(store.viewsSyncedAt == heard)
        #expect(store.paletteSyncedAt == heard)
        #expect(store.themesSyncedAt == heard)
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

    /// **The push writes only the meta fields this device changed.** The one
    /// meta record carries the serial, the active board and the three lists,
    /// and its writer used to be all-or-nothing: any difference rewrote every
    /// field. So a device that had merely handed out a task code overwrote
    /// the themes another device had just delivered — before its own read
    /// ever saw them — and scenario 17 read as "themes don't sync". The
    /// question is now asked field by field, exactly as it is for a card's.
    @Test func aPushLeavesTheMetaAnotherDeviceWroteAlone() throws {
        let sync = try BoardSyncStore.inMemory()
        var mine = Self.boardOfItsOwn(changedAt: TestBoard.epoch)
        try sync.apply(mine)

        // Another device saves a theme, straight into the records.
        let writer = BoardSyncStore(container: sync.container, isSyncing: false)
        var theirs = try #require(try writer.load())
        var made = ThemePresets.fallback(for: .light)
        made.id = "made-on-the-other-device"
        made.changedAt = TestBoard.epoch.addingTimeInterval(60)
        theirs.themes.custom.append(made)
        theirs.themesChangedAt = made.changedAt
        try writer.apply(theirs)

        // This device pushes an unrelated change: a task code handed out.
        mine.nextSerial += 1
        try sync.apply(mine)

        let read = try #require(
            try BoardSyncStore(container: sync.container, isSyncing: false).load()
        )
        #expect(read.themes.custom.contains { $0.id == made.id },
                "a push that changed only the serial overwrote the other device's theme")
        #expect(read.nextSerial == mine.nextSerial)

        // And the serial itself is a field no push may pull backwards: two
        // devices handing out one task code is the one disagreement no later
        // merge can undo.
        theirs.nextSerial = 500
        try writer.apply(theirs)
        mine.nextSerial += 1
        try sync.apply(mine)
        #expect(try #require(try writer.load()).nextSerial == 500,
                "a push pulled the shared serial back behind another device's")
    }

    /// **The launch pushes what its merge decided**, rather than waiting for
    /// the next edit. A union that stayed on this machine while its watermark
    /// moved on read, at the next merge, as a list of things the other side
    /// had deleted.
    @Test func theLaunchPushesTheMergedListsBackToTheRecords() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        var mine = Self.boardOfItsOwn()
        mine.views = SavedView.seededAll + [SavedView.blank(named: "Mine")]
        try temp.file.write(mine, generation: temp.file.nextWriteGeneration())
        try sync.apply(Self.boardOfItsOwn())

        _ = BoardStore.restored(file: temp.file, sync: sync)
        let read = try #require(
            try BoardSyncStore(container: sync.container, isSyncing: false).load()
        )
        #expect(read.views.contains { $0.name == "Mine" },
                "the merged union waited on this machine for an edit that never came")
        #expect(read.views.contains { $0.name == "Ship this week" },
                "the push sent this device's list rather than the union")
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

    /// `syncedAt` defaults to `nil` — "this device has never merged" — which
    /// is what the rows below are all about: they describe the rule *between
    /// two lists*, and the watermark only enters where an item is held by one
    /// side alone. The two tests that turn on it pass their own.
    private func resolve(
        _ local: [SavedView], _ localStamp: Date?,
        _ remote: [SavedView]?, _ remoteStamp: Date?, syncedAt: Date? = nil
    ) -> (list: [SavedView], changedAt: Date?) {
        SharedList.resolve(local: local, changedAt: localStamp, syncedAt: syncedAt,
                           remote: remote, changedAt: remoteStamp)
    }

    /// **Scenario 15 of the two-device checklist, which used to fail.**
    ///
    /// Both devices add a view before either syncs. Both additions must stand.
    /// They did not: two dated lists were settled by replacing the older with
    /// the newer wholesale, so the device that saved second deleted the other's
    /// view from both machines. A list is not a scalar — two additions are two
    /// additions, not competing claims to one value.
    @Test func twoDevicesEachAddingAViewKeepBoth() {
        let agreed = monday
        let mineNew = SavedView.blank(named: "Made on the Mac").dated(tuesday)
        let theirsNew = SavedView.blank(named: "Made on the phone")
            .dated(tuesday.addingTimeInterval(60))

        let out = resolve([mineNew], tuesday, [theirsNew], tuesday.addingTimeInterval(60),
                          syncedAt: agreed)
        #expect(Set(out.list.map(\.id)) == Set([mineNew.id, theirsNew.id]),
                "a view somebody made was deleted by the other device's save")
    }

    /// And the other half, which union alone would break: an item the other
    /// device no longer holds and which has not changed since the two last
    /// agreed is one **they deleted**, not one they have yet to see. Without
    /// this a deleted view returns on every sync, forever.
    @Test func aViewDeletedOnTheOtherDeviceStaysDeleted() {
        let agreed = tuesday
        let doomed = SavedView.blank(named: "Deleted over there").dated(monday)

        let out = resolve([doomed], monday, [], tuesday.addingTimeInterval(60), syncedAt: agreed)
        #expect(out.list.isEmpty, "a deletion made on the other device came back")
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

    /// **The watermark comes out of the merge at the stamp it consumed** —
    /// never the clock, never backwards, and only for a list the records
    /// actually carried. Stamped `.now` instead, an unrelated merge ran the
    /// watermark past every item still crossing, and each landed wearing a
    /// `changedAt` behind it — the shape of a deletion. See
    /// `SharedList.heard(_:consuming:)`.
    @Test func theWatermarkStandsWhereTheMergeActuallyHeard() {
        let local = BoardSnapshot(
            tasks: [], labels: [], nextSerial: 1,
            viewsChangedAt: monday, paletteChangedAt: monday, themesChangedAt: monday,
            viewsSyncedAt: monday, paletteSyncedAt: tuesday, themesSyncedAt: monday
        )
        let remote = BoardSnapshot(
            tasks: [], labels: [], nextSerial: 1,
            viewsChangedAt: tuesday,   // newer: the watermark advances to it
            paletteChangedAt: monday,  // older than the palette's mark: it stands
            themesChangedAt: tuesday   // newer, but not carried: it cannot count
        )
        let out = SharedList.resolve(local: local, remote: remote, carried: [.views, .palette])
        #expect(out.viewsSyncedAt == tuesday,
                "the watermark did not advance to the stamp it consumed")
        #expect(out.paletteSyncedAt == tuesday, "a watermark moved backwards")
        #expect(out.themesSyncedAt == monday,
                "a list the records never carried moved its watermark anyway")

        // An undated list consumed advances nothing either: nothing on it
        // says when it was heard from.
        let undated = SharedList.resolve(
            local: local, remote: BoardSnapshot(tasks: [], labels: [], nextSerial: 1),
            carried: [.views]
        )
        #expect(undated.viewsSyncedAt == monday,
                "consuming an undated list invented a watermark")
    }

    /// Themes are a list *and* two scalars. The custom themes merge like any
    /// other list; the two slots do not — an undated pair keeps this machine's,
    /// because which theme is showing is a fact about the screen in front of
    /// you rather than about the work.
    @Test func themesMergeTheirCustomsAndKeepThisMachinesSlots() {
        let local = ThemeSettings(lightID: "a", darkID: "b", custom: [Self.theme("mine")])
        let remote = ThemeSettings(lightID: "c", darkID: "d", custom: [Self.theme("theirs")])

        let undated = SharedList.resolve(local: local, changedAt: nil, syncedAt: nil,
                                         remote: remote, changedAt: nil)
        #expect(undated.themes.custom.map(\.id) == ["mine", "theirs"], "a theme somebody made was lost")
        #expect(undated.themes.lightID == "a", "an undated merge repainted the window")
        #expect(undated.themes.darkID == "b")

        // Dated, and theirs is newer: the slots travel with the decision.
        let dated = SharedList.resolve(local: local, changedAt: monday, syncedAt: nil,
                                       remote: remote, changedAt: tuesday)
        #expect(dated.themes.lightID == "c")
        #expect(dated.themes.custom.map(\.id) == ["theirs"])
    }

    private static func theme(_ id: Theme.ID) -> Theme {
        var theme = ThemePresets.fallback(for: .light)
        theme.id = id
        return theme
    }
}


/// The trash as records — one bin across every device, since ``StoredTrash``.
///
/// One verb per test: a row travels; a restore returns the card and takes the
/// row away everywhere; an emptied trash stays empty; the upgrade keeps each
/// device's local-only rows and sends them up; a deletion made elsewhere is
/// not pushed back by an unrelated write; a shared bin meeting a card the
/// board already has refuses to make two of it; and a row made while the
/// records stood unread survives the recovery.
@MainActor
@Suite struct TrashSyncTests {
    private func board(_ sync: BoardSyncStore, on temp: TempBoard) -> BoardStore {
        let store = BoardStore.restored(file: temp.file, sync: sync)
        store.saveNow()
        return store
    }

    private func snapshot(trash: [TrashedItem] = []) -> BoardSnapshot {
        BoardSnapshot(tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: SeedData.boards,
                      labels: LabelDef.seed, nextSerial: 340,
                      activeBoardID: SeedData.defaultBoard.id, trash: trash)
    }

    private static func row(_ title: String) -> TrashedItem {
        TrashedItem(contents: .task(TaskItem(code: "TR-400", title: title)))
    }

    /// The whole feature in one line: a card trashed on one device shows up in
    /// the other's bin, and not on its board.
    @Test func aTrashedCardArrivesInTheOtherDevicesTrash() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        store.addTask(to: .inbox, title: "Doomed")
        let card = try #require(store.tasks.first { $0.title == "Doomed" })
        store.trashTask(card.id)
        store.saveNow()

        let tempB = TempBoard()
        let other = board(BoardSyncStore(container: sync.container, isSyncing: false), on: tempB)
        #expect(other.trash.contains { $0.name == "Doomed" },
                "a trashed card did not reach the other device's bin")
        #expect(other.tasks.contains { $0.id == card.id } == false,
                "the trashed card is still on the other device's board")
    }

    /// A restore is two travelling facts — the card is back, the row is gone —
    /// and both must land on the device that trashed it.
    @Test func aRestoreReturnsTheCardAndEmptiesTheBinEverywhere() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        store.addTask(to: .inbox, title: "Doomed")
        let card = try #require(store.tasks.first { $0.title == "Doomed" })
        store.trashTask(card.id)
        store.saveNow()

        let tempB = TempBoard()
        let other = board(BoardSyncStore(container: sync.container, isSyncing: false), on: tempB)
        let rowID = try #require(other.trash.first { $0.name == "Doomed" }).id
        #expect(other.restoreFromTrash(rowID) == nil, "the restore itself was refused")
        other.saveNow()

        store.mergeRemoteChanges()
        #expect(store.tasks.contains { $0.id == card.id },
                "the restored card did not come back to the device that trashed it")
        #expect(store.trash.isEmpty, "the restored row stayed in this device's bin")
    }

    /// Empty Trash is the one act in the app that is meant to stick, and now it
    /// has to stick everywhere.
    @Test func anEmptiedTrashStaysEmptyEverywhere() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        store.addTask(to: .inbox, title: "Doomed")
        let card = try #require(store.tasks.first { $0.title == "Doomed" })
        store.trashTask(card.id)
        store.saveNow()

        let tempB = TempBoard()
        let other = board(BoardSyncStore(container: sync.container, isSyncing: false), on: tempB)
        other.emptyTrash()
        other.saveNow()

        store.mergeRemoteChanges()
        #expect(store.trash.isEmpty, "an Empty Trash on the other device did not land here")

        // And an unrelated push from this device must not refill the records.
        store.addTask(to: .inbox, title: "Unrelated")
        store.saveNow()
        let read = try #require(try BoardSyncStore(container: sync.container, isSyncing: false).load())
        #expect(read.trash.isEmpty, "an unrelated push resurrected the emptied bin")
    }

    /// The upgrade path: records from before there was a `StoredTrash` carry no
    /// bin at all, and the launch must read that as "nothing has been written"
    /// rather than "the bin is empty" — the same distinction the shared lists
    /// draw, answered here by the union.
    @Test func theUpgradeKeepsEachDevicesLocalOnlyRows() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        try sync.apply(snapshot())
        try temp.file.write(snapshot(trash: [Self.row("Kept from before")]),
                            generation: temp.file.nextWriteGeneration())

        let store = BoardStore.restored(file: temp.file, sync: sync)
        #expect(store.trash.contains { $0.name == "Kept from before" },
                "the upgrade emptied the local bin")
        let read = try #require(try BoardSyncStore(container: sync.container, isSyncing: false).load())
        #expect(read.trash.contains { $0.name == "Kept from before" },
                "the launch did not send the local-only row up")
    }

    /// The diff-base skip in `applyTrash`: a row this device still carries but
    /// whose record another device deleted is absent-but-seen, and writing it
    /// back would undo an Empty Trash from the far side.
    @Test func aRowAnotherDeviceDeletedIsNotPushedBack() throws {
        let sync = try BoardSyncStore.inMemory()
        let doomed = Self.row("Deleted over there")
        var mine = snapshot(trash: [doomed])
        try sync.apply(mine)

        let writer = BoardSyncStore(container: sync.container, isSyncing: false)
        var theirs = try #require(try writer.load())
        theirs.trash = []
        try writer.apply(theirs, deleting: SyncIDs(trash: [doomed.id]))

        // This device trashes something else before it hears; its push
        // carries the whole bin, the deleted row included.
        mine.trash.append(Self.row("Fresh here"))
        try sync.apply(mine)

        let read = try #require(try writer.load())
        #expect(read.trash.contains { $0.name == "Fresh here" }, "the new row did not travel")
        #expect(read.trash.contains { $0.id == doomed.id } == false,
                "a push reinserted a row another device had deleted")
    }

    /// Scenario 7's crossing: an unsynced edit on one device resurrects a card
    /// the other has trashed, so the board holds the card *and* the bin holds
    /// its row. Restore must refuse rather than make two of it — the guard
    /// `restoreFromTrash` grew the day the bin became shared.
    @Test func restoringACardTheBoardAlreadyHasRefuses() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        store.addTask(to: .inbox, title: "Twice")
        let card = try #require(store.tasks.first { $0.title == "Twice" })
        store.trashTask(card.id)
        store.saveNow()

        // The other device never heard about the trashing and writes the card
        // back, staged straight into the records.
        let writer = BoardSyncStore(container: sync.container, isSyncing: false)
        var theirs = try #require(try writer.load())
        theirs.tasks.append(card)
        try writer.apply(theirs)

        store.mergeRemoteChanges()
        #expect(store.tasks.contains { $0.id == card.id }, "the resurrection never landed")
        let rowID = try #require(store.trash.first { $0.name == "Twice" }).id
        #expect(store.restoreFromTrash(rowID) == .alreadyThere,
                "restoring made a second copy of a card the board already has")
        #expect(store.tasks.count { $0.id == card.id } == 1)
        #expect(store.trash.contains { $0.id == rowID }, "the refusal took the row anyway")
    }

    /// A card trashed while the records stood unread lives only in the bin —
    /// dropped by the recovery, it would be gone from the board *and* the
    /// trash, which is the loss the whole recovery exists to prevent.
    @Test func aCardTrashedWhileBlockedKeepsItsRowThroughRecovery() throws {
        let temp = TempBoard()
        let real = try BoardSyncStore.inMemory()
        try real.apply(snapshot())
        try temp.file.write(snapshot(), generation: temp.file.nextWriteGeneration())

        let flaky = FlakySyncStore(wrapping: real)
        flaky.loadFails = true
        let store = BoardStore.restored(file: temp.file, sync: flaky)
        #expect(store.isSyncReadBlocked)

        store.addTask(to: .inbox, title: "Trashed while blocked")
        let card = try #require(store.tasks.first { $0.title == "Trashed while blocked" })
        store.trashTask(card.id)

        flaky.loadFails = false
        store.mergeRemoteChanges()

        #expect(store.isSyncReadBlocked == false)
        #expect(store.trash.contains { $0.name == "Trashed while blocked" },
                "recovery dropped a row made while the records stood unread")
        let records = try #require(try real.load())
        #expect(records.trash.contains { $0.name == "Trashed while blocked" },
                "recovery did not push the row the records never saw")
    }
}
