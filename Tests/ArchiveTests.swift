import Foundation
import Testing
@testable import Simple_Kanban

/// Filing a task away: what it leaves, what it keeps, and what one ⌘Z has to
/// bring back.
///
/// The claim under test is narrow and total — an archived task is out of the
/// board, out of every board count and out of every search, and still in the
/// file. Each half of that is asked separately, because a build that merely
/// hid the card from the board would pass a test that only looked at the board.
@MainActor
@Suite struct ArchiveTests {
    private let done = BoardColumn.done.id

    private func board(_ store: BoardStore) -> BoardMutation {
        BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash, views: store.views, savedColors: store.savedColors)
    }

    // MARK: What archiving takes away

    @Test func anArchivedTaskLeavesTheBoardAndEveryCount() {
        let store = TestBoard.store()
        let today = TestBoard.dueDay
        #expect(store.totalCount == 6)
        #expect(store.count(of: .today, today: today) == 1)
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-121", "NW-122"])

        store.archive(TestBoard.dragDrop)

        #expect(store.totalCount == 5)
        #expect(store.count(of: .today, today: today) == 0)
        #expect(store.searchResults.contains { $0.id == TestBoard.dragDrop } == false)
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-122"])
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-122"])
        // Every saved view but the Archive, including the ones it would have
        // been in: NW-121 is due today and high priority.
        for view in SavedView.filters {
            #expect(store.tasks(in: view, today: today).contains { $0.id == TestBoard.dragDrop } == false,
                    "\(view.rawValue) still lists an archived task")
            #expect(store.count(of: view, today: today) == store.tasks(in: view, today: today).count)
        }
        #expect(store.count(of: .archive, today: today) == 1)
        #expect(store.tasks(in: .archive, today: today).map(\.code) == ["NW-121"])

        // …and the phone's lists, which read a different path to the board's.
        store.tab = .board
        store.mobileColumnID = BoardColumn.backlog.id
        #expect(store.mobileTasks(today: today).map(\.code) == ["NW-122"])
    }

    @Test func archivingKeepsTheTaskAndRecordsWhen() throws {
        let store = TestBoard.store()
        let before = try #require(store[TestBoard.palette]?.updatedAt)
        store.archive(TestBoard.palette)

        let filed = try #require(store[TestBoard.palette])
        #expect(filed.isArchived)
        #expect(filed.archivedAt != nil)
        #expect(filed.columnID == done)                       // it keeps where it was
        // …and it keeps when it was last worked on. Filing is a change to where
        // a task lives, not to the task, and `updatedAt` is what the weekly
        // meter reads — see `archivingDoesNotMoveUpdatedAt`.
        #expect(filed.updatedAt == before)
        #expect(filed.activity.first?.kind == .archived)      // newest entry, at index 0
        #expect(filed.activity.count == 4)
        // The board still holds it; it is the *board's* views that do not.
        #expect(store.tasks.contains { $0.id == TestBoard.palette })
    }

    @Test func archivingSomethingAlreadyFiledChangesNothing() throws {
        let stamp = TestBoard.at(300)
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.palette: 300]))
        let before = board(store)
        store.archive(TestBoard.palette)
        #expect(board(store) == before)
        #expect(store[TestBoard.palette]?.archivedAt == stamp)   // not re-stamped
        // …and an id that names nothing is not a crash either.
        store.archive(UUID())
        #expect(board(store) == before)
    }

    @Test func archivingMovesTheSurfacesOffTheCardWithoutLosingIt() throws {
        let store = TestBoard.store()
        store.move(TestBoard.cafe, to: done)          // Done now reads NW-125, NW-122
        store.selectedID = TestBoard.cafe
        store.sheetID = TestBoard.cafe

        store.archive(TestBoard.cafe)
        // The inspector lands on the neighbour that is still on the board.
        #expect(store.selectedID == TestBoard.palette)
        #expect(store.sheetID == nil)
        #expect(store[TestBoard.cafe]?.isArchived == true)
    }

    // MARK: Restoring

    @Test func unarchivingPutsTheTaskBackWhereItWas() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.dragDrop: 300]))
        let today = TestBoard.dueDay
        #expect(store.totalCount == 5)
        #expect(store.count(of: .archive, today: today) == 1)

        store.unarchive(TestBoard.dragDrop)

        let restored = try #require(store[TestBoard.dragDrop])
        #expect(restored.isArchived == false)
        #expect(restored.archivedAt == nil)
        #expect(restored.columnID == BoardColumn.backlog.id)   // not back at the start of the workflow
        #expect(restored.activity.first?.kind == .unarchived)
        #expect(store.totalCount == 6)
        #expect(store.count(of: .today, today: today) == 1)
        #expect(store.count(of: .archive, today: today) == 0)
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-121", "NW-122"])

        // Restoring something that is already on the board is a no-op.
        let after = board(store)
        store.unarchive(TestBoard.dragDrop)
        #expect(board(store) == after)
    }

    // MARK: Archive completed — one act, one step

    @Test func archivingTheDoneColumnIsASingleUndoableStep() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.move(TestBoard.cafe, to: done) }
        let beforeFiling = board(store)
        #expect(store.visibleTasks(in: done).count == 2)

        step(undo) { store.archiveCompleted() }
        #expect(undo.undoActionName == "Archive Completed")
        #expect(store.visibleTasks(in: done).isEmpty)
        #expect(store.totalCount == 4)
        #expect(store.count(of: .archive, today: TestBoard.dueDay) == 2)
        // One act, one instant — which is what the Archive's tie-break then
        // needs in order to keep the board's own order underneath.
        #expect(Set(store.tasks.compactMap(\.archivedAt)).count == 1)

        // One ⌘Z, both cards back.
        undo.undo()
        #expect(board(store) == beforeFiling)
        #expect(store.visibleTasks(in: done).count == 2)
        // …and the step before it is still there, untouched by the collapse.
        #expect(undo.canUndo)
        undo.undo()
        #expect(store[TestBoard.cafe]?.columnID == BoardColumn.backlog.id)
    }

    @Test func archivingCompletedInboxTasksLeavesOpenInboxTasks() throws {
        let store = TestBoard.store()
        let inbox = try #require(store.inboxTasks.first)
        store.complete(inbox.id)
        store.archiveInboxCompleted()

        #expect(store[inbox.id]?.isArchived == true)
        #expect(store.inboxCompletedCount == 0)
        #expect(store.inboxTasks.contains { $0.id == inbox.id } == false)
    }

    @Test func archivingAnEmptyDoneColumnRegistersNothing() {
        let (store, undo) = TestBoard.undoing(tasks: TestBoard.tasks(archiving: [TestBoard.palette: 300]))
        let before = board(store)
        step(undo) { store.archiveCompleted() }
        #expect(undo.undoActionName == "")
        #expect(board(store) == before)
        #expect(undoEverything(undo, on: store) == 0)
    }

    @Test func archivingCompletedLeavesAlreadyFiledCardsAlone() throws {
        let stamp = TestBoard.at(300)
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.palette: 300]))
        store.move(TestBoard.cafe, to: done)
        store.archiveCompleted()

        // The card filed a week ago keeps its own date, so the Archive's order
        // still says when each thing actually went in.
        #expect(store[TestBoard.palette]?.archivedAt == stamp)
        #expect(store[TestBoard.cafe]?.archivedAt != stamp)
        #expect(store[TestBoard.cafe]?.isArchived == true)
        #expect(store.tasks(in: .archive, today: TestBoard.dueDay).map(\.code) == ["NW-122", "NW-125"])
    }

    // MARK: It survives a relaunch

    @Test func anArchivedTaskIsStillArchivedAfterARelaunch() throws {
        let temp = TempBoard()
        let today = TestBoard.dueDay
        let store = TestBoard.store(file: temp.file)
        store.archive(TestBoard.dragDrop)
        let filedAt = try #require(store[TestBoard.dragDrop]?.archivedAt)
        store.saveNow()

        let relaunched = BoardStore.restored(file: temp.file)
        #expect(relaunched.loadFailure == nil)
        let task = try #require(relaunched[TestBoard.dragDrop])
        #expect(task.isArchived)
        #expect(task.archivedAt == filedAt)
        #expect(task.columnID == BoardColumn.backlog.id)
        #expect(relaunched.totalCount == 5)
        #expect(relaunched.searchResults.contains { $0.id == TestBoard.dragDrop } == false)
        #expect(relaunched.tasks(in: .archive, today: today).map(\.code) == ["NW-121"])
        // The rest of the board came back unarchived, rather than everything
        // being read as filed or nothing being read at all.
        #expect(relaunched.tasks.count == 6)
        #expect(relaunched.tasks.count { $0.isArchived } == 1)

        // …and a restore of the archive is itself saved and read back.
        relaunched.unarchive(TestBoard.dragDrop)
        relaunched.saveNow()
        #expect(try temp.snapshot().tasks.allSatisfy { $0.archivedAt == nil })
    }

    // MARK: The weekly meter

    /// A board whose `updatedAt` stamps sit at known day distances from
    /// `meterDay`, which is the only thing the meter reads.
    private static let meterDay = CalendarDay(year: 2026, month: 6, day: 15)

    private static func touched(_ code: String, _ column: BoardColumn.ID, daysAgo: Int) -> TaskItem {
        let when = meterDay.adding(days: -daysAgo).date()
        return TaskItem(code: code, columnID: column, title: "Meter \(code)",
                        createdAt: when, updatedAt: when)
    }

    private static let meterTasks: [TaskItem] = [
        touched("NW-401", BoardColumn.done.id, daysAgo: 0),
        touched("NW-402", BoardColumn.done.id, daysAgo: 6),      // the last day inside
        touched("NW-403", BoardColumn.done.id, daysAgo: 7),      // the first day outside
        touched("NW-404", BoardColumn.done.id, daysAgo: 30),
        touched("NW-405", BoardColumn.backlog.id, daysAgo: 3),   // touched, not shipped
        touched("NW-406", BoardColumn.backlog.id, daysAgo: 8),
        touched("NW-407", BoardColumn.backlog.id, daysAgo: -1),  // stamped tomorrow
    ]

    @Test func theWeeklyMeterIsARollingSevenDaysAndNotAllTime() {
        let store = TestBoard.store(tasks: Self.meterTasks)
        let day = Self.meterDay
        // Four tasks have reached Done. Two of them did it this week.
        #expect(store.tasks.count { $0.columnID == BoardColumn.done.id } == 4)
        #expect(store.weeklyShippedCount(today: day) == 2)
        // Shipped over touched: NW-401, NW-402 and NW-405 were touched inside
        // the window; NW-407's stamp is in the future and is in neither half.
        #expect(store.weeklyProgressFraction(today: day) == 2.0 / 3.0)

        // A day on, the window has moved: the six-day-old shipment has aged out
        // and the stamp that was a day ahead has become today's.
        let tomorrow = day.adding(days: 1)
        #expect(store.weeklyShippedCount(today: tomorrow) == 1)
        #expect(store.weeklyProgressFraction(today: tomorrow) == 1.0 / 3.0)

        // A month of nothing reads as nothing, rather than drifting toward full
        // the way a count over all time did.
        let later = day.adding(days: 30)
        #expect(store.weeklyShippedCount(today: later) == 0)
        #expect(store.weeklyProgressFraction(today: later) == 0)
    }

    /// The meter reads when a card was last worked on, not when it was first
    /// written down. A ticket opened in February and finished on Tuesday is
    /// this week's work; one opened on Tuesday and untouched since is not.
    /// Every other board here stamps the two fields alike, so this is the only
    /// place the difference between them can fail.
    @Test func theWeeklyMeterReadsUpdatedAtAndNotCreatedAt() {
        let day = Self.meterDay
        func card(_ code: String, _ column: BoardColumn.ID, created: Int, updated: Int) -> TaskItem {
            TaskItem(code: code, columnID: column, title: "Stamp \(code)",
                     createdAt: day.adding(days: -created).date(),
                     updatedAt: day.adding(days: -updated).date())
        }
        let store = TestBoard.store(tasks: [
            card("NW-420", done, created: 200, updated: 2),                   // old, shipped this week
            card("NW-421", done, created: 1, updated: 200),                   // new, shipped long ago
            card("NW-422", BoardColumn.backlog.id, created: 300, updated: 3), // touched, not shipped
            card("NW-423", done, created: 300, updated: 5),                   // old, shipped this week
        ])
        // Read off `createdAt` instead, this board ships one and touches one.
        #expect(store.weeklyShippedCount(today: day) == 2)
        #expect(store.weeklyProgressFraction(today: day) == 2.0 / 3.0)
    }

    @Test func theWeeklyMeterKeepsWhatWasArchived() throws {
        // The one place the archive is deliberately not subtracted. Archiving is
        // filing, not un-shipping, and "Archive completed" sits on the Done
        // column header — a meter that fell to zero the moment the user tidied
        // up would punish the action standing next to it.
        //
        // Filed by the call the user makes rather than by hand: archiving no
        // longer moves `updatedAt`, so the card stays inside the injected
        // window, and this reads the real path instead of a board shaped like
        // the one the real path would have produced.
        let store = TestBoard.store(tasks: Self.meterTasks)
        let day = Self.meterDay
        store.archive(try #require(store.tasks.first { $0.code == "NW-401" }).id)

        #expect(store.totalCount == 6)                          // out of the board's count
        #expect(store.weeklyShippedCount(today: day) == 2)      // still in the meter's
        #expect(store.weeklyProgressFraction(today: day) == 2.0 / 3.0)
        // …and it is genuinely archived, not merely still on the board.
        #expect(store.count(of: .archive, today: day) == 1)
        #expect(store.searchResults.contains { $0.code == "NW-401" } == false)
    }

    // MARK: Filing is not touching

    /// A card that reached Done a month ago, filed away today.
    ///
    /// The real clock is read here, deliberately and in this one helper: the
    /// defect is the store writing `Date.now` into `updatedAt` on the way into
    /// the archive, and a stamp written from the real clock is only visible from
    /// the week that instant lands in. Everything measured off it is thirty days
    /// away from the window, so the assertions have four weeks of slack.
    private static func shippedLastMonth(_ code: String) -> (task: TaskItem, today: CalendarDay) {
        let today = CalendarDay(Date())
        let when = today.adding(days: -30).date()
        return (TaskItem(code: code, columnID: BoardColumn.done.id, title: "Shipped last month",
                         createdAt: when, updatedAt: when), today)
    }

    /// `updatedAt` is the only evidence the weekly meter has, so a filing that
    /// stamped it rewrote history: a board where nothing had been finished in a
    /// month reported a week's work the moment the user pressed "Archive
    /// completed" — the button standing directly beside the meter.
    @Test func archivingDoesNotMoveUpdatedAt() throws {
        let (stale, today) = Self.shippedLastMonth("NW-410")
        let store = TestBoard.store(tasks: [stale])
        #expect(store.weeklyShippedCount(today: today) == 0)

        store.archive(stale.id)

        let filed = try #require(store[stale.id])
        #expect(filed.updatedAt == stale.updatedAt)
        #expect(filed.archivedAt != nil)                    // the stamp a filing *is* for
        #expect(store.weeklyShippedCount(today: today) == 0)
        #expect(store.weeklyProgressFraction(today: today) == 0)
    }

    @Test func unarchivingDoesNotMoveUpdatedAtEither() throws {
        var (stale, today) = Self.shippedLastMonth("NW-411")
        stale.archivedAt = today.adding(days: -20).date()
        let store = TestBoard.store(tasks: [stale])
        #expect(store.count(of: .archive, today: today) == 1)

        store.unarchive(stale.id)

        let restored = try #require(store[stale.id])
        #expect(restored.archivedAt == nil)
        #expect(restored.updatedAt == stale.updatedAt)
        #expect(store.weeklyShippedCount(today: today) == 0)
        #expect(store.weeklyProgressFraction(today: today) == 0)
    }

    @Test func filingAWholeColumnMovesNoStampEither() throws {
        let (first, today) = Self.shippedLastMonth("NW-412")
        let (second, _) = Self.shippedLastMonth("NW-413")
        let store = TestBoard.store(tasks: [first, second])
        #expect(store.weeklyShippedCount(today: today) == 0)

        store.archiveCompleted()

        #expect(store.tasks.map(\.updatedAt) == [first.updatedAt, second.updatedAt])
        #expect(store.tasks.allSatisfy { $0.isArchived })
        #expect(store.weeklyShippedCount(today: today) == 0)
        #expect(store.weeklyProgressFraction(today: today) == 0)
    }

    /// The other half of the same fix, and the one it could have traded away: a
    /// filing that stops stamping must not also stop invalidating.
    ///
    /// Two memos hang off a mutation. The column grouping is keyed on the query,
    /// the task count and the board's revision — archiving moves neither of the
    /// first two, so the revision is the only thing that can drop the stale
    /// group. The search haystack is keyed on a per-task counter, which is what
    /// keeps a card findable by text edited after it was filed.
    @Test func archivingStillInvalidatesTheGroupingAndTheSearch() throws {
        let store = TestBoard.store()
        let today = TestBoard.dueDay
        // Prime both memos while everything is still on the board.
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-121", "NW-122"])
        store.query = "cafe"
        #expect(store.searchResults.map(\.code) == ["NW-122"])
        store.clearQuery()

        store.archive(TestBoard.cafe)

        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-121"])
        store.query = "cafe"
        #expect(store.searchResults.isEmpty)
        #expect(store.tasks(in: .archive, today: today).map(\.code) == ["NW-122"])
        store.clearQuery()

        store.unarchive(TestBoard.cafe)
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-121", "NW-122"])

        // …and text edited on the far side of the round trip is findable, which
        // is the per-task stamp rather than the board-wide one.
        store.setText("Bistro menu polish", field: .title, on: TestBoard.cafe)
        store.query = "bistro"
        #expect(store.searchResults.map(\.code) == ["NW-122"])
        store.query = "cafe"
        #expect(store.searchResults.isEmpty)
    }

    // MARK: The Archive's verb is Restore, and it is the only one

    /// An archived row offers one thing. Completion is not it: ticking a filed
    /// card moves it out of the column it was filed from and closes its
    /// sub-tasks on the way, from a list whose only button says Restore.
    @Test func anArchivedTaskCannotBeCompleted() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.dragDrop: 300]))
        let before = try #require(store[TestBoard.dragDrop])
        #expect(before.columnID == BoardColumn.backlog.id)
        #expect(before.subtasks.count { !$0.done } == 2)

        store.complete(TestBoard.dragDrop)

        let after = try #require(store[TestBoard.dragDrop])
        #expect(after.columnID == BoardColumn.backlog.id)    // not moved to Done
        #expect(after.subtasks == before.subtasks)           // and nothing auto-ticked
        #expect(after.activity == before.activity)
        #expect(after.updatedAt == before.updatedAt)
        #expect(after.isArchived)
    }

    @Test func anArchivedTaskInDoneCannotBeReopened() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.palette: 300]))
        let before = try #require(store[TestBoard.palette])
        store.reopen(TestBoard.palette)
        let after = try #require(store[TestBoard.palette])
        #expect(after.columnID == done)                      // not sent back to Up Next
        #expect(after.activity == before.activity)
        #expect(after.isArchived)
    }

    @Test func neitherVerbCostsAnUndoStepOnAnArchivedTask() {
        let (store, undo) = TestBoard.undoing(
            tasks: TestBoard.tasks(archiving: [TestBoard.dragDrop: 300, TestBoard.palette: 400])
        )
        let before = board(store)
        step(undo) { store.complete(TestBoard.dragDrop) }
        #expect(undo.undoActionName == "")
        step(undo) { store.reopen(TestBoard.palette) }
        #expect(undo.undoActionName == "")
        #expect(board(store) == before)
        #expect(undoEverything(undo, on: store) == 0)
    }

    /// Restore restores rather than reopens: the card comes back to the column
    /// it was filed from, with nothing ticked and nothing else moved.
    @Test func restoringIsNotReopening() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.dragDrop: 300]))
        let before = try #require(store[TestBoard.dragDrop])

        store.unarchive(TestBoard.dragDrop)

        let after = try #require(store[TestBoard.dragDrop])
        #expect(after.columnID == before.columnID)
        #expect(after.subtasks == before.subtasks)
        #expect(after.activity.first?.kind == .unarchived)
        #expect(Array(after.activity.dropFirst()) == before.activity)
    }
}

/// What the Task menu is allowed to do to a card that is filed away.
///
/// ⌘A on the Archive surface selects filed cards — that is what the surface is
/// showing — so a selection of archived cards is one keystroke away, and every
/// item on the Task menu is then aimed at cards that are off the board. Two of
/// the five would silently do nothing and three would happen: Move to Column
/// would drag a filed card back into a column the user is not looking at, and
/// the two pickers would edit a record. In the Archive the verb is Restore and
/// only Restore, which the card's own context menu has always known.
///
/// Asked of `AppCommand.applies(to:in:)` — the predicate the menu's enabled
/// state and its target list both read — so an item cannot be live and useless,
/// or live and destructive, without this failing.
@MainActor
@Suite struct ArchivedSelectionTests {
    private let filed: [TaskItem.ID] = [TestBoard.cafe, TestBoard.offline]

    private func store() -> BoardStore {
        TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.cafe: 300, TestBoard.offline: 400]))
    }

    /// The surface really does hand the menu a selection of filed cards.
    @Test func selectAllOnTheArchiveSelectsTheFiledCards() {
        let store = store()
        store.selectSurface(.view(SavedView.archive.id))
        store.selectAllVisible(today: TestBoard.dueDay)
        #expect(store.selection == Set(filed))
    }

    /// Every item on the Task menu, dead — bar the one whose whole purpose is a
    /// filed card. Task ▸ Restore Task is the Archive's own verb on the menu
    /// bar, the same one the card's context menu has always offered there, and
    /// it is live exactly where the others are not.
    @Test func everyTaskCommandIsDisabledForASelectionOfFiledCards() {
        let store = store()
        let cards = filed.compactMap { store[$0] }
        #expect(cards.count == 2)
        #expect(cards.map(\.isArchived) == [true, true])

        #expect(AppCommand.unarchiveTask.isEnabled(for: cards, in: store))
        #expect(cards.allSatisfy { AppCommand.unarchiveTask.applies(to: $0, in: store) })

        for command in AppCommand.commands(in: .task) where command != .unarchiveTask {
            #expect(command.isEnabled(for: cards, in: store) == false,
                    "Task ▸ \(command.title) is live on a selection that is off the board")
            // And nothing for it to act on, so the menu passes the store
            // nothing even if a press reaches the item anyway.
            let applies = cards.filter { command.applies(to: $0, in: store) }
            #expect(applies.isEmpty, "Task ▸ \(command.title) would act on a filed card")
        }
    }

    /// And none of the store calls behind them touches a filed card. The two
    /// the store guards itself are asked directly, because the card's own keys
    /// reach them without going past the menu.
    @Test func noTaskCommandMutatesAFiledCard() {
        let (store, undo) = TestBoard.undoing(
            tasks: TestBoard.tasks(archiving: [TestBoard.cafe: 300, TestBoard.offline: 400])
        )
        let ids = Set(filed)
        let before = store.tasks

        let filings = registrations(undo) {
            store.complete(ids)
            store.archive(ids)
            // What the menu would hand over, which is nothing at all.
            store.move(applicable(.moveToColumn, ids, store), to: BoardColumn.inProgress.id)
            store.setPriority(.high, on: applicable(.setPriority, ids, store))
            store.setDue(TestBoard.laterDay, on: applicable(.setDueDate, ids, store))
        }
        #expect(filings.isEmpty, "a filed card took a step on the undo stack")
        #expect(store.tasks == before)
        #expect(store[TestBoard.cafe]?.archivedAt == TestBoard.at(300), "a filed card was restamped")
    }

    /// The contrast that makes the rule a decision rather than "disable
    /// everything": four commands still apply to a filed card, because reading
    /// one, copying its code or throwing it away are all things a person does
    /// in an archive.
    @Test func theCommandsThatStillApplyToAFiledCardAreTheOnesWeNamed() throws {
        let store = store()
        let card = try #require(store[TestBoard.cafe])
        let live = AppCommand.allCases.filter { $0.needsSelection && $0.applies(to: card, in: store) }
        #expect(Set(live) == [.trashTask, .copyTask, .deselect, .openTask, .unarchiveTask])
    }

    /// The rule has to live in the store, not in the menu that usually asks it.
    /// A rotor action, a drag and a card's own keys all reach `move` without
    /// passing an enabled state, and a card moved out of the Archive would not
    /// visibly move at all — the list is ordered by `archivedAt`.
    @Test func aFiledCardRefusesAMoveAskedForDirectly() {
        let (store, undo) = TestBoard.undoing(
            tasks: TestBoard.tasks(archiving: [TestBoard.cafe: 300, TestBoard.offline: 400])
        )
        let before = store.tasks

        let filings = registrations(undo) {
            store.move(TestBoard.cafe, to: BoardColumn.inProgress.id)
            store.move(Set(filed), to: BoardColumn.inProgress.id)
            store.move(Set(filed), to: .inbox)
            store.move(TestBoard.cafe, to: .inbox)
        }
        #expect(filings.isEmpty, "a filed card took a step on the undo stack")
        #expect(store.tasks == before)
        #expect(store[TestBoard.cafe]?.isArchived == true)
    }

    /// And a mixed selection moves the cards that are still on the board while
    /// leaving the filed one where it is — one step, named for what moved.
    @Test func aMixedSelectionMovesOnlyTheCardsStillOnTheBoard() throws {
        let (store, undo) = TestBoard.undoing(
            tasks: TestBoard.tasks(archiving: [TestBoard.cafe: 300])
        )
        let live = try #require(store.tasks.first { !$0.isArchived && !$0.isUnfiled }).id

        let filings = registrations(undo) {
            store.move([TestBoard.cafe, live], to: BoardColumn.inProgress.id)
        }
        #expect(filings.count == 1)
        #expect(store[live]?.columnID == BoardColumn.inProgress.id)
        #expect(store[TestBoard.cafe]?.columnID != BoardColumn.inProgress.id)
        #expect(store[TestBoard.cafe]?.archivedAt == TestBoard.at(300))
    }
}

/// The ids a menu item would actually hand the store: the ones the command
/// applies to, which on a selection of filed cards is none.
@MainActor
private func applicable(
    _ command: AppCommand, _ ids: Set<TaskItem.ID>, _ store: BoardStore
) -> Set<TaskItem.ID> {
    Set(ids.compactMap { store[$0] }.filter { command.applies(to: $0, in: store) }.map(\.id))
}

/// One user action's worth of registrations, by name and in order — see
/// `SelectionTests`, where the same helper explains itself.
@MainActor
private func registrations(_ undo: RecordingUndoManager, _ body: () -> Void) -> [String] {
    let before = undo.actionNames.count
    step(undo) { body() }
    return Array(undo.actionNames[before...])
}
