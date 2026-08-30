import Foundation
import Testing
@testable import Simple_Kanban

/// The trash: what goes in, what comes back out, and what the thirty days do.
///
/// The three kinds are not one kind with three names — a card comes back whole,
/// a column comes back as a container whose cards were never in danger, and a
/// board comes back with every card that was on it — so almost everything here
/// is asked three times.
@MainActor
@Suite struct TrashTests {
    private static let backlog = BoardColumn.backlog.id
    private static let upNext = BoardColumn.upNext.id

    private func store(file: BoardFile? = nil) -> BoardStore {
        TestBoard.store(boards: TestBoard.boards, file: file)
    }

    // MARK: A task

    @Test func trashingATaskTakesItOffTheBoardAndPutsItInTheTrash() throws {
        let store = store()
        let before = store.tasks.count

        store.trashTask(TestBoard.cafe)

        #expect(store[TestBoard.cafe] == nil)
        #expect(store.tasks.count == before - 1)
        let item = try #require(store.trashedItems.first)
        #expect(item.kind == .task)
        #expect(item.code == "NW-122")
        #expect(store.trashCount == 1)
    }

    @Test func restoringATaskPutsItBackWhereItWasAndSaysSoInItsHistory() throws {
        let store = store()
        let placement = try #require(store[TestBoard.cafe]?.placement)
        store.trashTask(TestBoard.cafe)

        let item = try #require(store.trashedItems.first)
        #expect(store.restoreFromTrash(item.id) == nil)

        let back = try #require(store[TestBoard.cafe])
        #expect(back.placement == placement)
        #expect(back.activity.first?.kind == .restoredFromTrash)
        // The row is gone from the trash: it came back, it is not in two places.
        #expect(store.trashedItems.isEmpty)
    }

    /// A card is the user's. Refusing to hand one back because the column it
    /// used to sit in has since been deleted would be holding it hostage to a
    /// container it never belonged to — so it lands in the Inbox, which is where
    /// every other card that cannot find its column lands.
    @Test func aTaskWhoseColumnHasGoneComesBackToTheInbox() throws {
        let store = store()
        store.trashTask(TestBoard.offline)             // was in Up Next
        store.trashColumn(Self.upNext)

        let task = try #require(store.trashedItems.first { $0.kind == .task })
        #expect(store.restoreFromTrash(task.id) == nil)
        #expect(store[TestBoard.offline]?.isUnfiled == true)
    }

    @Test func trashingASelectionIsOneStepAndKeepsTheBoardsOrder() throws {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.trashTasks([TestBoard.cafe, TestBoard.dragDrop]) }

        #expect(undo.actionNames == ["Trash Tasks"])
        #expect(store.trashCount == 2)
        #expect(store[TestBoard.cafe] == nil)
        #expect(store[TestBoard.dragDrop] == nil)
    }

    // MARK: A column

    /// The cards were never in danger and are not waiting in the trash for
    /// anybody: deleting a column has always moved them to the first column
    /// left, and trashing it does exactly the same thing.
    @Test func trashingAColumnKeepsItsCardsAndTrashesOnlyTheColumn() throws {
        let store = store()
        let moved = store.visibleTasks(in: Self.upNext).map(\.id)
        #expect(!moved.isEmpty)

        #expect(store.trashColumn(Self.upNext) == nil)

        #expect(store.columns.contains { $0.id == Self.upNext } == false)
        for id in moved { #expect(store[id]?.columnID == Self.backlog) }
        let item = try #require(store.trashedItems.first)
        #expect(item.kind == .column)
        #expect(item.name == BoardColumn.upNext.name)
    }

    @Test func restoringAColumnPutsItBackWhereItSat() throws {
        let store = store()
        let position = try #require(store.columns.firstIndex { $0.id == Self.upNext })
        store.trashColumn(Self.upNext)

        let item = try #require(store.trashedItems.first)
        #expect(store.restoreFromTrash(item.id) == nil)
        #expect(store.columns.firstIndex { $0.id == Self.upNext } == position)
    }

    /// The one restore that cannot be honoured, because there is nowhere to put
    /// it and inventing a board to hold it would be inventing a board.
    @Test func aColumnWhoseBoardHasGoneIsRefusedAndSaysWhy() throws {
        let store = store()
        let boardID = try #require(store.activeBoardID)
        store.trashColumn(Self.upNext)
        store.trashBoard(boardID)

        let column = try #require(store.trashedItems.first { $0.kind == .column })
        #expect(store.restoreFromTrash(column.id) == .boardIsGone)
        // Refused, not consumed: it is still there to try again after the board.
        #expect(store.trashedItems.contains { $0.id == column.id })

        let board = try #require(store.trashedItems.first { $0.kind == .board })
        #expect(store.restoreFromTrash(board.id) == nil)
        #expect(store.restoreFromTrash(column.id) == nil)
        #expect(store.board(id: boardID)?.columns.contains { $0.id == Self.upNext } == true)
    }

    /// A refusal is not a mutation, so it must not cost a ⌘Z either — an undo
    /// stack with a step on it that changed nothing is a stack the user presses
    /// ⌘Z at and watches do nothing.
    @Test func aRefusedRestoreRegistersNoStep() throws {
        let (store, undo) = TestBoard.undoing(boards: TestBoard.boards)
        let boardID = try #require(store.activeBoardID)
        step(undo) { store.trashColumn(Self.upNext) }
        step(undo) { store.trashBoard(boardID) }
        let column = try #require(store.trashedItems.first { $0.kind == .column })

        let before = undo.actionNames.count
        step(undo) { #expect(store.restoreFromTrash(column.id) == .boardIsGone) }
        #expect(undo.actionNames.count == before)
    }

    // MARK: A board

    /// **The cards go with it.** They used to be scattered into the Inbox and
    /// the board went into the trash on its own, which made Trash Board a move
    /// wearing a delete's clothes — and made Restore unable to give the board
    /// back the way it was.
    @Test func trashingABoardTakesItsCardsWithItAndTrashesTheBoardWithItsColumns() throws {
        let store = store()
        let boardID = try #require(store.activeBoardID)
        let onIt = store.tasks.filter { $0.boardID == boardID }.map(\.id)
        #expect(!onIt.isEmpty)
        let inbox = store.inboxCount

        store.trashBoard(boardID)

        #expect(store.board(id: boardID) == nil)
        // Gone from the board file entirely, rather than loose in the Inbox.
        for id in onIt { #expect(store[id] == nil) }
        // The Inbox is global and was never this board's: its own cards are
        // untouched, and none of the board's were tipped into it.
        #expect(store.inboxCount == inbox, "the board's cards were left behind in the Inbox")

        let item = try #require(store.trashedItems.first)
        guard case .board(let board, _, let cards) = item.contents else {
            Issue.record("expected a board in the trash, got \(item.contents)")
            return
        }
        // Its columns travel inside it, the way they do everywhere else, and
        // its cards travel beside it.
        #expect(board.columns.count == BoardColumn.workflow.count)
        #expect(cards.map(\.id) == onIt, "the cards did not go in with the board, in its order")
        #expect(item.taskCount == onIt.count, "the row cannot say how many came with it")
    }

    /// Archived cards are on the board too, and a restore that left them out
    /// would quietly lose the work somebody filed away rather than finished.
    @Test func trashingABoardTakesItsArchivedCardsTooAndGivesThemBack() throws {
        let store = store()
        let boardID = try #require(store.activeBoardID)
        let filed = try #require(store.tasks.first { $0.boardID == boardID })
        store.archive(filed.id)
        #expect(store[filed.id]?.isArchived == true)

        store.trashBoard(boardID)
        #expect(store[filed.id] == nil)

        let item = try #require(store.trashedItems.first)
        #expect(store.restoreFromTrash(item.id) == nil)
        // Back, and still filed away: restoring is not unarchiving.
        #expect(store[filed.id]?.isArchived == true)
        #expect(store[filed.id]?.boardID == boardID)
    }

    @Test func restoringABoardPutsItBackInTheSidebarWhereItSatWithItsCards() throws {
        let store = store()
        let boardID = try #require(store.activeBoardID)
        let position = try #require(store.boards.firstIndex { $0.id == boardID })
        let before = store.tasks.filter { $0.boardID == boardID }
        #expect(!before.isEmpty)
        store.trashBoard(boardID)

        let item = try #require(store.trashedItems.first)
        #expect(store.restoreFromTrash(item.id) == nil)
        #expect(store.boards.firstIndex { $0.id == boardID } == position)

        // Every card back, in the column it was in rather than in the Inbox.
        for card in before {
            let now = store[card.id]
            #expect(now?.placement == card.placement, "\(card.code) did not come back where it was")
            #expect(now?.activity.first?.kind == .restoredFromTrash)
        }
        #expect(store.trashCount == 0, "the row outlived the restore")
    }

    // MARK: Undo

    /// The point of `BoardMutation.trash`. Without it, ⌘Z would put the card
    /// back on the board *and* leave the copy sitting in the trash, and the user
    /// would have one card twice.
    @Test func undoingATrashTakesTheRowBackOutOfTheTrashToo() throws {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.trashTask(TestBoard.cafe) }
        #expect(undo.actionNames == ["Trash Task"])
        #expect(store.trashCount == 1)

        undo.undo()
        #expect(store[TestBoard.cafe] != nil)
        #expect(store.trashCount == 0)
    }

    @Test func undoingARestorePutsTheRowBackInTheTrash() throws {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.trashTask(TestBoard.cafe) }
        let item = try #require(store.trashedItems.first)

        step(undo) { store.restoreFromTrash(item.id) }
        #expect(undo.actionNames.last == "Restore from Trash")
        #expect(store.trashCount == 0)

        undo.undo()
        #expect(store.trashCount == 1)
        #expect(store[TestBoard.cafe] == nil)
    }

    @Test func undoingAnEmptyTrashBringsEverythingBackIntoIt() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.trashTask(TestBoard.cafe) }
        step(undo) { store.trashTask(TestBoard.dragDrop) }

        step(undo) { store.emptyTrash() }
        #expect(undo.actionNames.last == "Empty Trash")
        #expect(store.trashCount == 0)

        undo.undo()
        #expect(store.trashCount == 2)
    }

    // MARK: The card that says so

    /// Trashing has no confirmation, so the card is the only thing on screen
    /// that says a board has gone rather than merely stopped being there.
    @Test func trashingRaisesACardNamingWhatWent() throws {
        let store = store()
        let title = try #require(store[TestBoard.cafe]?.displayTitle)

        store.trashTask(TestBoard.cafe)
        #expect(store.announcement?.text == "Moved \(title) to the trash")

        store.trashColumn(Self.upNext)
        #expect(store.announcement?.text == "Moved \(BoardColumn.upNext.name) to the trash")

        let boardID = try #require(store.activeBoardID)
        let name = try #require(store.board(id: boardID)?.name)
        store.trashBoard(boardID)
        #expect(store.announcement?.text == "Moved \(name) to the trash")
    }

    /// One card for a selection, not one per task: four in a row would each
    /// replace the last too quickly to read, and the last would name a card at
    /// random out of the four.
    @Test func aSelectionGetsOneCardCountingThemRatherThanFour() {
        let store = store()
        store.trashTasks([TestBoard.cafe, TestBoard.dragDrop, TestBoard.offline])
        #expect(store.announcement?.text == "Moved 3 tasks to the trash")

        // A selection of one is still a name, because there is a name to give.
        store.trashTasks([TestBoard.sync])
        #expect(store.announcement?.text == "Moved Sync engine to the trash")
    }

    /// Two cards with one title, one after the other. The ids differ, which is
    /// what lets the surface restart its dismissal timer instead of leaving the
    /// first one's running under the second.
    @Test func twoTrashesRunningReadTheSameAndAreNotTheSameAnnouncement() throws {
        let store = store()
        store.trashTask(TestBoard.cafe)
        let first = try #require(store.announcement)
        store.trashTask(TestBoard.dragDrop)
        let second = try #require(store.announcement)
        #expect(first.id != second.id)
        #expect(first != second)
    }

    /// A refusal changed nothing, so there is nothing to say about it.
    @Test func aRefusedColumnTrashSaysNothing() {
        let store = TestBoard.store(boards: [SeedData.defaultBoard])
        let done = BoardColumn.done.id
        #expect(store.trashColumn(done) == .doneColumn)
        #expect(store.announcement == nil)
    }

    /// ⌘Z takes the sentence away with the act it describes. A card still
    /// reading "Moved Sync engine to the trash" over a board that has Sync
    /// tokens back on it is the app contradicting itself.
    @Test func undoingTakesTheCardAwayWithTheAct() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.trashTask(TestBoard.cafe) }
        #expect(store.announcement != nil)

        undo.undo()
        #expect(store.announcement == nil)
    }

    // MARK: Deleting for good

    @Test func deletingFromTheTrashTakesOnlyThatRow() throws {
        let store = store()
        store.trashTask(TestBoard.cafe)
        store.trashTask(TestBoard.dragDrop)
        let first = try #require(store.trashedItems.first { $0.code == "NW-122" })

        store.deleteFromTrash(first.id)
        #expect(store.trashCount == 1)
        #expect(store.trashedItems.contains { $0.code == "NW-122" } == false)
        // And the card does not come back: this is the one delete with nothing
        // behind it but ⌘Z.
        #expect(store[TestBoard.cafe] == nil)
    }

    @Test func emptyingTakesTheLot() {
        let store = store()
        store.trashTask(TestBoard.cafe)
        store.trashColumn(Self.upNext)
        #expect(store.trashCount == 2)

        store.emptyTrash()
        #expect(store.trashCount == 0)
        #expect(store.trashedItems.isEmpty)
    }

    // MARK: The thirty days

    /// The countdown the row draws. Elapsed time would floor to 29 within a
    /// second of the first trash, contradicting the "kept here for 30 days"
    /// sentence under the empty list.
    @Test func theCountdownReadsThirtyOnTheDaySomethingIsThrownAway() {
        let item = TrashedItem(contents: .task(TestBoard.tasks[0]))
        #expect(item.daysLeft() == TrashedItem.retentionDays)

        let calendar = Calendar.current
        let yesterday = try! #require(calendar.date(byAdding: .day, value: -1, to: .now))
        #expect(TrashedItem(trashedAt: yesterday, contents: .task(TestBoard.tasks[0])).daysLeft() == 29)

        // The last day reads zero rather than going negative, and the row says
        // "deleted today" for it.
        let expiring = try! #require(calendar.date(byAdding: .day, value: -30, to: .now))
        #expect(TrashedItem(trashedAt: expiring, contents: .task(TestBoard.tasks[0])).daysLeft() == 0)
    }

    @Test func thirtyDaysIsCountedOffTheCalendarRatherThanInSeconds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar = { var c = calendar; c.timeZone = TimeZone(identifier: "Europe/London")! ; return c }()
        // 15 March: the thirty days run across the spring clock change, which
        // costs an hour and would put a seconds-based expiry a day early.
        let trashedAt = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
        let item = TrashedItem(trashedAt: trashedAt, contents: .task(TestBoard.tasks[0]))

        let expiry = item.expiry(from: calendar)
        #expect(calendar.dateComponents([.day], from: trashedAt, to: expiry).day == 30)
        #expect(calendar.component(.hour, from: expiry) == 12)
    }

    /// The session that was left open across the thirtieth day. Nothing has
    /// swept, so the row is still in `trash` — and the list the user is looking
    /// at must not be showing it anyway, because reading a list is not allowed
    /// to write to the file.
    @Test func anItemPastItsThirtyDaysIsNeitherListedNorCounted() throws {
        let fresh = TrashedItem(contents: .task(TestBoard.tasks[0]))
        let stale = TrashedItem(
            trashedAt: Date.now.addingTimeInterval(-31 * 86_400),
            contents: .task(TestBoard.tasks[1])
        )
        let store = BoardStore(tasks: TestBoard.tasks, boards: TestBoard.boards,
                               trash: [fresh, stale])

        #expect(store.trashCount == 1)
        #expect(store.trashedItems.map(\.id) == [fresh.id])
        #expect(store.trash.count == 2)

        // Sweeping is the write, and it takes exactly the one.
        store.sweepTrash()
        #expect(store.trash.map(\.id) == [fresh.id])
    }

    /// And the launch after that: swept on the way in, so the file stops
    /// carrying what is no longer offered.
    @Test func aStaleRowIsGoneBeforeTheStoreEvenOpens() throws {
        let temp = TempBoard()
        let seeded = BoardStore(
            tasks: TestBoard.tasks, boards: TestBoard.boards,
            trash: [
                TrashedItem(contents: .task(TestBoard.tasks[0])),
                TrashedItem(trashedAt: Date.now.addingTimeInterval(-40 * 86_400),
                            contents: .task(TestBoard.tasks[1])),
            ],
            file: temp.file
        )
        seeded.saveNow()
        #expect(try temp.snapshot().trash.count == 2)

        let relaunched = BoardStore.restored(file: temp.file)
        #expect(relaunched.trash.count == 1)
    }

    // MARK: The file

    @Test func theTrashSurvivesAWriteAndARead() throws {
        let temp = TempBoard()
        let store = store(file: temp.file)
        let boardID = try #require(store.activeBoardID)
        store.trashTask(TestBoard.cafe)
        store.trashColumn(Self.upNext)
        store.trashBoard(boardID)
        store.saveNow()

        let read = try temp.snapshot()
        #expect(read.version == BoardSnapshot.currentVersion)
        #expect(read.trash.count == 3)
        #expect(Set(read.trash.map(\.kind)) == [.task, .column, .board])

        let relaunched = BoardStore.restored(file: temp.file)
        #expect(relaunched.trashCount == 3)
        // And it is still restorable on the other side of the launch.
        let task = try #require(relaunched.trashedItems.first { $0.kind == .task })
        #expect(relaunched.restoreFromTrash(task.id) == nil)
        #expect(relaunched[TestBoard.cafe] != nil)
    }

    /// A v6 file has no `trash` key at all, and the current decoder has to read
    /// it rather than set the user's board aside as corrupt.
    @Test func aFileFromBeforeTheTrashReadsWithAnEmptyOne() throws {
        let temp = TempBoard()
        try temp.put(#"""
        { "version": 6, "tasks": [], "boards": [], "labels": [],
          "nextSerial": 100, "accentTheme": "ember" }
        """#)

        let result = temp.file.load()
        let snapshot = try #require(result.snapshot)
        #expect(result.failure == nil)
        #expect(result.migratedFromVersion == 6)
        #expect(snapshot.version == BoardSnapshot.currentVersion)
        #expect(snapshot.trash.isEmpty)
    }

    // MARK: The shape on disk

    /// **A board trashed before the cards travelled with it still reads.**
    ///
    /// The `.board` case grew a third associated value, and the synthesised
    /// decoder demands every key it knows about — so without the hand-written
    /// one in `TrashedItem`, every board already sitting in somebody's trash
    /// would fail to decode and take the whole board file down as corrupt with
    /// it. This is that entry, in the exact shape the compiler used to write.
    ///
    /// It comes back with no cards, which is the truth about it: those cards
    /// went to the Inbox when it was trashed and are still there.
    @Test func aBoardTrashedBeforeItsCardsTravelledWithItStillReads() throws {
        let board = TestBoard.support
        let old = """
        {"board":{"_0":\(String(data: try JSONEncoder().encode(board), encoding: .utf8)!),"position":2}}
        """
        let decoded = try JSONDecoder().decode(
            TrashedItem.Contents.self, from: Data(old.utf8)
        )
        guard case .board(let read, let position, let cards) = decoded else {
            Issue.record("an old board entry did not read back as a board: \(decoded)")
            return
        }
        #expect(read.id == board.id)
        #expect(read.columns.count == board.columns.count)
        #expect(position == 2)
        #expect(cards.isEmpty, "cards were invented for an entry that never had any")
    }

    /// And the shape written today is the same one, plus the cards — so a board
    /// file stays readable by the decoder that wrote it.
    @Test func theShapeOnDiskIsTheOneTheCompilerUsedToWriteWithTheCardsAdded() throws {
        let contents = TrashedItem.Contents.board(
            TestBoard.support, position: 1, tasks: [TestBoard.tasks[0]]
        )
        let data = try JSONEncoder().encode(contents)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let board = try #require(json["board"] as? [String: Any])
        // `_0` is the synthesised spelling for an unlabelled associated value,
        // and the reason this is asserted rather than assumed: rename it and
        // every trash entry on disk stops reading.
        #expect(board["_0"] != nil, "the board is no longer under the key the old files use")
        #expect(board["position"] as? Int == 1)
        #expect((board["tasks"] as? [Any])?.count == 1)

        // And it round-trips.
        let back = try JSONDecoder().decode(TrashedItem.Contents.self, from: data)
        #expect(back == contents)
    }

    /// The other two cases are on disk too, and are just as easy to break by
    /// hand-writing the coder: their keys are asserted for the same reason.
    @Test func theTaskAndColumnShapesOnDiskAreUnchanged() throws {
        let task = TrashedItem.Contents.task(TestBoard.tasks[0])
        let taskJSON = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any]
        )
        #expect((taskJSON["task"] as? [String: Any])?["_0"] != nil)
        #expect(try JSONDecoder().decode(
            TrashedItem.Contents.self, from: JSONEncoder().encode(task)) == task)

        let column = TrashedItem.Contents.column(
            BoardColumn.backlog, boardID: TestBoard.support.id, position: 3
        )
        let columnJSON = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(column)) as? [String: Any]
        )
        let nested = try #require(columnJSON["column"] as? [String: Any])
        #expect(nested["_0"] != nil)
        #expect(nested["boardID"] != nil)
        #expect(nested["position"] as? Int == 3)
        #expect(try JSONDecoder().decode(
            TrashedItem.Contents.self, from: JSONEncoder().encode(column)) == column)
    }
}
