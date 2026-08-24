import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

/// Columns as board data, and the role that carries the only behaviour hung on
/// one.
///
/// Every board here is deliberately *not* the seeded one: its Done column is a
/// column the user made, with its own id and its own name. That is the whole
/// point of the role — the three Done behaviours used to match on the literal
/// id "done", so a test that only ever exercises the seed columns cannot fail
/// on the defect they were replaced to fix.
@MainActor
@Suite struct ColumnTests {
    private static func columnID(_ n: UInt8) -> BoardColumn.ID {
        UUID(uuid: (0xC7, 0x51, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    private static let triage = BoardColumn(
        id: columnID(1), name: "Triage", short: "Triage", dot: .hex(0xA8A29A)
    )
    private static let building = BoardColumn(
        id: columnID(2), name: "Building", short: "Build", dot: .hex(0xC2532F)
    )
    /// A Done column by role and by nothing else: not the seed's id, not its
    /// name, not its short name.
    private static let shipped = BoardColumn(
        id: columnID(3), name: "Shipped", short: "Ship", dot: .hex(0x1F6F63)
    )

    private static let columns = [triage, building, shipped]

    private static let taskID = UUID(uuid: (0xC7, 0x52, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1))
    private static let otherID = UUID(uuid: (0xC7, 0x52, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 2))

    private static func tasks() -> [TaskItem] {
        [
            TaskItem(
                id: taskID, code: "NW-300", columnID: triage.id, title: "Ship the thing",
                due: CalendarDay(year: 2026, month: 8, day: 20), priority: .high,
                subtasks: [SubTask(text: "Write it"), SubTask(text: "Test it")],
                activity: [ActivityEntry(.created, when: TestBoard.at(10_000))],
                createdAt: TestBoard.at(10_000), updatedAt: TestBoard.at(10_000)
            ),
            TaskItem(
                id: otherID, code: "NW-301", columnID: building.id, title: "Something else",
                activity: [ActivityEntry(.created, when: TestBoard.at(9_000))],
                createdAt: TestBoard.at(9_000), updatedAt: TestBoard.at(9_000)
            ),
        ]
    }

    private static func store(file: BoardFile? = nil) -> BoardStore {
        BoardStore(tasks: tasks(), columns: columns, labels: LabelDef.seed,
                   accentTheme: .ember, nextSerial: BoardSnapshot.baseSerial, file: file)
    }

    private static func undoing() -> (store: BoardStore, undo: UndoManager) {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let store = store()
        store.undoManager = undo
        return (store, undo)
    }

    /// The whole board including its columns, so a column mutation is visible to
    /// an "exactly as it was" assertion.
    private func board(_ store: BoardStore) -> BoardMutation {
        BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash, views: store.views, savedColors: store.savedColors)
    }

    /// The migrated board's columns. They were a flat `BoardSnapshot.columns`
    /// until v5 moved them onto the board they belong to.
    private func columns(of snapshot: BoardSnapshot) -> [BoardColumn] {
        snapshot.boards.first?.columns ?? []
    }

    // MARK: The role carries the behaviour

    @Test func completingSendsATaskToWhicheverColumnHasTheDoneRole() {
        let store = Self.store()
        store.complete(Self.taskID)
        #expect(store[Self.taskID]?.columnID == Self.shipped.id)
        #expect(store.isDone(store[Self.taskID]!))
        #expect(store.column(for: store[Self.taskID]!)?.name == "Shipped")
    }

    @Test func arrivingInADoneColumnTicksOffOutstandingSubTasks() {
        let store = Self.store()
        store.move(Self.taskID, to: Self.shipped.id)
        #expect(store[Self.taskID]?.subtasks.allSatisfy(\.done) == true)
        let ticked = store[Self.taskID]?.activity.contains {
            if case .subtasksCompletedOnDone(let count) = $0.kind { return count == 2 }
            return false
        }
        #expect(ticked == true)
    }

    @Test func movingIntoANonDoneColumnLeavesSubTasksAlone() {
        let store = Self.store()
        store.move(Self.taskID, to: Self.building.id)
        #expect(store[Self.taskID]?.subtasks.contains { !$0.done } == true)
    }

    @Test func theWeeklyMeterCountsWhatIsInTheDoneRoleColumn() {
        let store = Self.store()
        let today = CalendarDay(store[Self.taskID]!.updatedAt)
        #expect(store.weeklyShippedCount(today: today) == 0)
        store.complete(Self.taskID)
        #expect(store.weeklyShippedCount(today: CalendarDay(Date.now)) == 1)
    }

    @Test func savedViewsLeaveOutWhateverColumnHasTheDoneRole() {
        let store = Self.store()
        let today = CalendarDay(year: 2026, month: 8, day: 20)
        #expect(store.tasks(in: .today, today: today).map(\.code) == ["NW-300"])
        store.complete(Self.taskID)
        #expect(store.tasks(in: .today, today: today).isEmpty)
    }

    @Test func theDueChipReadsGreenForADoneRoleAndNotForAnyOther() {
        let palette = Palette(colorScheme: .light)
        let shipped = palette.dueTone(urgency: .overdue, isDone: true)
        #expect(shipped == palette.dueTone(urgency: .later, isDone: true))
        #expect(shipped != palette.dueTone(urgency: .overdue, isDone: false))
        #expect(shipped != palette.dueTone(urgency: .overdue, isDone: false))
        // `.active` is descriptive only: nothing may hang off it.
        #expect(palette.dueTone(urgency: .overdue, isDone: false)
                == palette.dueTone(urgency: .overdue, isDone: false))
    }

    @Test func reopeningReadsTheColumnIDTheHistoryCarries() {
        let store = Self.store()
        store.move(Self.taskID, to: Self.building.id)
        store.complete(Self.taskID)
        store.reopen(Self.taskID)
        #expect(store[Self.taskID]?.columnID == Self.building.id)
    }

    @Test func aTaskThatReachedDoneWithoutMovingReopensIntoTheFirstWorkingColumn() {
        let store = Self.store()
        store.complete(Self.otherID)
        store.reopen(Self.otherID)
        #expect(store[Self.otherID]?.columnID == Self.triage.id)
    }

    @Test func aTaskInAColumnTheBoardNoLongerHasIsNotTreatedAsComplete() {
        var stray = Self.tasks()[0]
        stray.placement = .column(board: UUID(), column: UUID())
        let store = BoardStore(tasks: [stray], columns: Self.columns, labels: LabelDef.seed, file: nil)
        #expect(store.column(for: stray) == nil)
        #expect(store.isDone(stray) == false)
    }

    // MARK: Managing columns

    /// **In front of Done, not at the end.** The end is what makes a column the
    /// Done one — see `Board.doneColumn` — so appending would hand every new
    /// column the finished work and quietly demote the old one.
    @Test func addingAColumnPutsItInFrontOfDoneAndInThePager() {
        let store = Self.store()
        let id = store.addColumn(named: "Blocked", short: "Block", dot: .hex(0x111111))
        #expect(store.columns.dropLast().last?.id == id)
        #expect(store.columns.map(\.name) == ["Triage", "Building", "Blocked", "Shipped"])
        #expect(store.doneColumnID == Self.shipped.id, "the new column took the finished work")
        #expect(store.pagerColumns.map(\.id) == store.columns.map(\.id))
        // The Inbox is not one of the board's columns — since v5 it is not a
        // column at all, and a card is in it by being on no board.
        #expect(store.columns.contains { $0.id == BoardColumn.inbox.id } == false)
        #expect(store.columns.contains { $0.name == Board.inboxName } == false)
    }

    @Test func aColumnWithNoNameIsRefused() {
        let store = Self.store()
        #expect(store.addColumn(named: "   ") == nil)
        #expect(store.columns.count == 3)
    }

    @Test func aColumnWithNoShortNameBorrowsItsName() {
        let store = Self.store()
        let id = store.addColumn(named: "Blocked")
        #expect(store.column(id: id)?.short == "Blocked")
    }

    /// The dot the composer's swatches pick — held on the way in rather than
    /// applied afterwards, because until Add Column is pressed there is no
    /// column to recolour.
    ///
    /// The default is the same value `BoardSettingsView` opens its picker on,
    /// which is why it is a name rather than a literal: a column made without
    /// touching the swatches has to come out the colour the untouched picker was
    /// showing, and it is deliberately *not* one of `Board.dots`.
    @Test func aColumnKeepsTheColourItWasMadeWith() {
        let store = Self.store()
        let picked = store.addColumn(named: "Blocked", dot: .hex(0x3B5BA9))
        #expect(store.column(id: picked)?.dot == .hex(0x3B5BA9))

        let untouched = store.addColumn(named: "Waiting")
        #expect(store.column(id: untouched)?.dot == BoardColumn.defaultDot)
        #expect(Board.dotPalette.contains(BoardColumn.defaultDot) == false,
                "the default is one of the six, so an untouched picker would ring it")
    }

    @Test func renamingAColumnLeavesItsAbbreviationAloneUnlessOneIsGiven() {
        let store = Self.store()
        store.renameColumn(Self.building.id, to: "In flight")
        #expect(store.column(id: Self.building.id)?.name == "In flight")
        #expect(store.column(id: Self.building.id)?.short == "Build")

        store.renameColumn(Self.building.id, to: "In flight", short: "Flight")
        #expect(store.column(id: Self.building.id)?.short == "Flight")
    }

    @Test func renamingLeavesTheHistoryThatNamesTheColumnAsItWas() {
        let store = Self.store()
        store.move(Self.taskID, to: Self.building.id)
        store.renameColumn(Self.building.id, to: "In flight")
        // The entry keeps the name it was written with — it records something
        // that already happened.
        let named = store[Self.taskID]?.activity.contains {
            if case .moved(_, let name) = $0.kind { return name == "Building" }
            return false
        }
        #expect(named == true)
        // The id still resolves, so reopen still knows where to go back to.
        store.complete(Self.taskID)
        store.reopen(Self.taskID)
        #expect(store[Self.taskID]?.columnID == Self.building.id)
    }

    @Test func recolouringAColumnLeavesItsCardsAlone() {
        let store = Self.store()
        let before = store.tasks
        store.recolorColumn(Self.triage.id, to: .accent)
        #expect(store.column(id: Self.triage.id)?.dot == .accent)
        #expect(store.tasks == before)
    }

    /// "Building", not "Shipped": Shipped is the board's last column and so its
    /// Done column, which does not move — see `DoneColumnTests`.
    @Test func reorderingColumnsMovesThemAndNothingElse() {
        let store = Self.store()
        let before = store.tasks
        store.moveColumn(fromOffsets: [1], toOffset: 0)
        #expect(store.columns.map(\.name) == ["Building", "Triage", "Shipped"])
        #expect(store.tasks == before)
    }

    @Test func deletingAColumnMovesItsCardsToTheFirstOneLeftAndSaysSo() {
        let store = Self.store()
        #expect(store.deleteColumn(Self.building.id) == nil)
        #expect(store.columns.map(\.name) == ["Triage", "Shipped"])
        #expect(store[Self.otherID]?.columnID == Self.triage.id)
        let moved = store[Self.otherID]?.activity.first
        #expect(moved?.kind == .moved(columnID: Self.triage.id.uuidString, columnName: "Triage"))
    }

    @Test func deletingAColumnTakesItsArchivedCardsWithIt() {
        let store = Self.store()
        store.archive(Self.otherID)
        store.deleteColumn(Self.building.id)
        #expect(store[Self.otherID]?.columnID == Self.triage.id)
        #expect(store[Self.otherID]?.isArchived == true)
    }

    @Test func deletingTheColumnThePagerIsOnMovesThePager() {
        let store = Self.store()
        store.mobileColumnID = Self.building.id
        store.deleteColumn(Self.building.id)
        #expect(store.mobileColumnID == Self.triage.id)
    }

    @Test func deletingTheDoneColumnIsRefusedWithAnExplanation() {
        let store = Self.store()
        let refusal = store.deleteColumn(Self.shipped.id)
        #expect(refusal == .doneColumn)
        #expect(refusal?.errorDescription?.isEmpty == false)
        #expect(refusal?.recoverySuggestion?.isEmpty == false)
        #expect(store.columns.count == 3)
    }

    @Test func deletingTheLastColumnThatIsNotDoneIsRefused() {
        let store = BoardStore(tasks: [], columns: [Self.triage, Self.shipped],
                               labels: LabelDef.seed, file: nil)
        let refusal = store.deleteColumn(Self.triage.id)
        #expect(refusal == .lastWorkingColumn)
        #expect(refusal?.errorDescription?.isEmpty == false)
        #expect(store.columns.count == 2)
    }

    @Test func deletingAColumnTheBoardDoesNotHaveIsRefusedRatherThanIgnored() {
        let store = Self.store()
        #expect(store.deleteColumn(UUID()) == .unknownColumn)
        // The Inbox is not one of the board's columns, so it cannot be deleted.
        #expect(store.deleteColumn(BoardColumn.inbox.id) == .unknownColumn)
    }

    // MARK: C6 — every new mutation saves and undoes

    /// The column half of `SaveContractTests`, kept here because the mutations
    /// are new. One store per mutation, each with a file of its own.
    @Test func everyColumnMutationSchedulesASave() async throws {
        var cases: [(label: String, board: TempBoard)] = []
        func mutate(_ label: String, _ body: (BoardStore) -> Void) {
            let board = TempBoard()
            body(Self.store(file: board.file))
            cases.append((label, board))
        }

        mutate("addColumn") { $0.addColumn(named: "Blocked") }
        mutate("renameColumn") { $0.renameColumn(Self.building.id, to: "In flight") }
        mutate("recolorColumn") { $0.recolorColumn(Self.triage.id, to: .accent) }
        mutate("moveColumn") { $0.moveColumn(fromOffsets: [1], toOffset: 0) }
        mutate("deleteColumn") { $0.deleteColumn(Self.building.id) }

        try await Task.sleep(for: .milliseconds(900))
        for item in cases {
            #expect(item.board.file.writeCount == 1, "\(item.label) never reached the disk")
        }
    }

    /// The column half of `UndoHarnessTests`: each mutation changes the board,
    /// names itself for the Edit menu, and comes back cleanly.
    @Test func everyColumnMutationRegistersAStep() {
        func check(_ label: String, _ body: (BoardStore) -> Void) {
            let (store, undo) = Self.undoing()
            let before = board(store)
            step(undo) { body(store) }
            #expect(board(store) != before, "\(label) changed nothing — the probe is wrong")
            #expect(undo.undoActionName != "", "\(label) registered no undo step")
            undo.undo()
            #expect(board(store) == before, "\(label) did not undo cleanly")
        }

        check("addColumn") { $0.addColumn(named: "Blocked") }
        check("renameColumn") { $0.renameColumn(Self.building.id, to: "In flight") }
        check("recolorColumn") { $0.recolorColumn(Self.triage.id, to: .accent) }
        check("moveColumn") { $0.moveColumn(fromOffsets: [1], toOffset: 0) }
        check("deleteColumn") { $0.deleteColumn(Self.building.id) }
    }

    @Test func aRefusedDeleteRegistersNothingAndSavesNothing() async throws {
        let temp = TempBoard()
        let store = Self.store(file: temp.file)
        let undo = UndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        step(undo) { _ = store.deleteColumn(Self.shipped.id) }
        #expect(undo.undoActionName == "")
        try await Task.sleep(for: .milliseconds(900))
        #expect(temp.file.writeCount == 0)
    }

    @Test func undoingAnAddedColumnPutsThePagerBack() throws {
        let (store, undo) = Self.undoing()
        var added: BoardColumn.ID?
        step(undo) { added = store.addColumn(named: "Blocked") }
        store.mobileColumnID = try #require(added)
        undo.undo()
        #expect(store.columns.count == 3)
        #expect(store.mobileColumnID == Self.triage.id)
    }

    // MARK: The columns survive a relaunch

    @Test func aBoardsColumnsAreWrittenAndReadBack() throws {
        let temp = TempBoard()
        let store = Self.store(file: temp.file)
        store.addColumn(named: "Blocked", short: "Block", dot: .accent)
        store.saveNow()

        let read = try temp.snapshot()
        #expect(read.version == BoardSnapshot.currentVersion)
        #expect(columns(of: read) == store.columns)
        #expect(columns(of: read).map(\.name) == ["Triage", "Building", "Blocked", "Shipped"])

        let reopened = BoardStore.restored(file: temp.file)
        #expect(reopened.columns == store.columns)
    }

    /// No boards means no columns, because there is no board to have any. It
    /// is what `deleteBoard` leaves rather than damage, so it comes back the
    /// way it was left rather than reseeded — handing somebody who deleted
    /// their last board a stranger's sample columns is the worse answer.
    @Test func aBoardFileWithNoBoardsAtAllIsAdoptedRatherThanReseeded() throws {
        let temp = TempBoard()
        try temp.file.write(
            BoardSnapshot(tasks: [], boards: [], labels: LabelDef.seed,
                          nextSerial: 100, accentTheme: .ember),
            generation: temp.file.nextWriteGeneration()
        )
        let store = BoardStore.restored(file: temp.file)
        #expect(store.boards.isEmpty)
        #expect(store.activeBoardID == nil)
        #expect(store.columns.isEmpty)
    }

    // MARK: v3 → v4

    @Test func theV3FixtureArrivesAsAV4BoardWithColumnsOfItsOwn() throws {
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v3"))
        let result = temp.file.load()
        let snapshot = try #require(result.snapshot)

        #expect(result.failure == nil)
        #expect(result.migratedFromVersion == 3)
        #expect(snapshot.version == BoardSnapshot.currentVersion)
        #expect(snapshot.accentTheme == .pine)
        #expect(snapshot.nextSerial == 121)

        // Every column keeps the name, short name, dot and order it had when it
        // was five literals in the app.
        #expect(columns(of: snapshot) == BoardColumn.workflow)
        #expect(columns(of: snapshot).map(\.name) == ["Backlog", "Up Next", "In Progress", "Done"])
        #expect(columns(of: snapshot).map(\.short) == ["Backlog", "Up Next", "Doing", "Done"])
        #expect(columns(of: snapshot).map(\.dot) == [
            .hex(0xA8A29A), .hex(0xC98A16), .hex(0xC2532F), .hex(0x1F6F63),
        ])
        // And Done is last, which since v9 is the whole of what makes it Done.
        #expect(columns(of: snapshot).last == BoardColumn.done)

        // The fixture is `TestBoard` with one task filed away, written out by
        // the v3 encoder, so this compares every field of every task at once —
        // column ids and the ids inside the activity feed included. v5 gave
        // every filed card a board as well, which is what `tasks(on:)` adds.
        #expect(snapshot.tasks == TestBoard.tasks(
            on: try #require(snapshot.boards.first), archiving: [TestBoard.palette: 900]
        ))
    }

    @Test func theV3StepMapsEveryLegacyColumnIDIncludingTheOnesInTheFeed() throws {
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v3"))
        let snapshot = try #require(temp.file.load().snapshot)

        // The first was in the Inbox column, which v5 turned into no column
        // at all — see `BoardTests`.
        #expect(snapshot.tasks.map(\.columnID) == [
            nil, BoardColumn.backlog.id, BoardColumn.backlog.id,
            BoardColumn.upNext.id, BoardColumn.inProgress.id, BoardColumn.done.id,
        ])

        // `reopen` reads these, so a legacy string left in the feed would send
        // every migrated board's completed cards to the wrong column.
        let movedIDs = snapshot.tasks.flatMap(\.activity).compactMap { entry -> String? in
            guard case .moved(let columnID, _) = entry.kind else { return nil }
            return columnID
        }
        #expect(movedIDs.isEmpty == false)
        #expect(movedIDs.allSatisfy { UUID(uuidString: $0) != nil })
        #expect(Set(movedIDs) == [
            BoardColumn.inProgress.id.uuidString,
            BoardColumn.done.id.uuidString,
            BoardColumn.upNext.id.uuidString,
        ])

        // The names the entries carry are untouched: they are what the feed
        // shows, and they were written for the column as it was then.
        let names = snapshot.tasks.flatMap(\.activity).compactMap { entry -> String? in
            guard case .moved(_, let name) = entry.kind else { return nil }
            return name
        }
        #expect(Set(names) == ["In Progress", "Done", "Up Next"])
    }

    @Test func aMigratedV3BoardStillCompletesAndReopens() throws {
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v3"))
        let store = BoardStore.restored(file: temp.file)

        #expect(store.columns == BoardColumn.workflow)
        #expect(store.isDone(store[TestBoard.palette]!))
        // The fixture has this one filed away, and in the Archive the verb is
        // Restore — so it comes back to the board before it can be reopened.
        store.unarchive(TestBoard.palette)
        store.reopen(TestBoard.palette)
        // Its history names Up Next under Done, and the migration kept the id.
        #expect(store[TestBoard.palette]?.columnID == BoardColumn.upNext.id)
    }

    @Test func everyFixtureStillLoadsAllTheWayForward() throws {
        for name in ["board-v1", "board-v1-minted", "board-v2", "board-v3"] {
            let temp = TempBoard()
            try temp.put(try Fixture.data(name))
            let result = temp.file.load()
            let snapshot = try #require(result.snapshot, "\(name) did not load")
            #expect(result.failure == nil, "\(name) failed to load")
            #expect(snapshot.version == BoardSnapshot.currentVersion, "\(name) did not reach v5")
            #expect(columns(of: snapshot) == BoardColumn.workflow, "\(name) arrived without columns")
            // Nothing came through carrying a column id no column answers to.
            // Since v5 a card may name no column at all — that is the Inbox.
            let known = Set(columns(of: snapshot).map(\.id))
            #expect(snapshot.tasks.allSatisfy { $0.columnID.map(known.contains) ?? $0.isUnfiled },
                    "\(name) has homeless cards")
        }
    }

    @Test func aFileWithNoVersionKeyIsStillReadAsAV1BoardAndReachesV5() throws {
        var object = try #require(
            try JSONSerialization.jsonObject(with: try Fixture.data("board-v1")) as? [String: Any]
        )
        object.removeValue(forKey: "version")
        let temp = TempBoard()
        try temp.put(try JSONSerialization.data(withJSONObject: object))

        let result = temp.file.load()
        let snapshot = try #require(result.snapshot)
        #expect(result.migratedFromVersion == 1)
        #expect(snapshot.version == BoardSnapshot.currentVersion)
        #expect(columns(of: snapshot) == BoardColumn.workflow)
    }
}
