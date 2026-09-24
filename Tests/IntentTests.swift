// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import AppIntents
import Foundation
import Testing
@testable import LittleKanban

/// Shortcuts, Siri and the Spotlight action row, all of which reach the board
/// through `TaskIntentBridge` rather than through a view.
///
/// An intent can run in a process the user never brought to the front, so the
/// interesting question is not what the parameters look like but *which board
/// it writes to*: there is exactly one store in this app, and an intent that
/// made its own would be writing a board of its own over the real one.
@MainActor
@Suite struct IntentTests {
    /// The bridge is a global, so a probe borrows it and puts back whatever the
    /// host app left there.
    private func borrowing(_ store: BoardStore, _ body: () async throws -> Void) async rethrows {
        let previous = TaskIntentBridge.store
        TaskIntentBridge.adopt(store)
        defer { previous.map(TaskIntentBridge.adopt) }
        try await body()
    }

    @Test func addingWithNoDestinationLandsInTheInbox() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let intent = AddTaskIntent()
            intent.taskTitle = "From Shortcuts"

            _ = try await intent.perform()

            // A capture that had to pick a board first would not be a capture.
            let added = try #require(store.tasks.first { $0.title == "From Shortcuts" })
            #expect(added.isUnfiled)
            #expect(added.code.hasPrefix("\(Board.inboxCodePrefix)-"))
        }
    }

    @Test func addingToANamedColumnLandsThere() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: TestBoard.boards)
        try await borrowing(store) {
            let intent = AddTaskIntent()
            intent.taskTitle = "Triaged by Siri"
            intent.column = ColumnEntity(id: TestBoard.queue.id, name: "Queue", boardName: "Support triage")

            _ = try await intent.perform()

            let added = try #require(store.tasks.first { $0.title == "Triaged by Siri" })
            #expect(added.placement == .column(board: TestBoard.support.id, column: TestBoard.queue.id))
            // The code is minted from the board it landed on, not from the one
            // that happened to be on screen.
            #expect(added.code.hasPrefix("ST-"))
        }
    }

    @Test func addingToABoardLandsInItsLandingColumn() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: TestBoard.boards)
        try await borrowing(store) {
            let intent = AddTaskIntent()
            intent.taskTitle = "Onto the board"
            intent.board = BoardEntity(id: TestBoard.support.id, name: "Support triage")

            _ = try await intent.perform()

            let added = try #require(store.tasks.first { $0.title == "Onto the board" })
            #expect(added.boardID == TestBoard.support.id)
            #expect(added.columnID == TestBoard.support.landingColumn?.id)
        }
    }

    @Test func aDueDateGivenToTheIntentReachesTheCard() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let intent = AddTaskIntent()
            intent.taskTitle = "Due from Shortcuts"
            intent.due = TestBoard.laterDay.date()

            _ = try await intent.perform()
            let added = try #require(store.tasks.first { $0.title == "Due from Shortcuts" })
            #expect(added.due == TestBoard.laterDay)
            // Part of the card as it arrives, not an edit to it: no `.dueSet`
            // line in a history one act old — see `addTaskFromIntent`.
            #expect(!added.activity.contains { entry in
                if case .dueSet = entry.kind { return true } else { return false }
            }, "a card arriving with a date logged an edit to itself")
        }
    }

    /// The one save path with no lifecycle flush behind it: a Shortcut can
    /// run against an app the system background-launched and jetsam-kills
    /// moments after the dialog is spoken — inside the 500 ms debounce, which
    /// no scene phase will flush for a process the user never foregrounded.
    @Test func anIntentsMutationReachesTheDiskBeforeItReturns() async throws {
        let temp = TempBoard()
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard), file: temp.file)
        try await borrowing(store) {
            let intent = AddTaskIntent()
            intent.taskTitle = "Written before the dialog"

            _ = try await intent.perform()

            let onDisk = try #require(temp.file.load().snapshot)
            #expect(onDisk.tasks.contains { $0.title == "Written before the dialog" },
                    "the intent's card was still waiting out the save debounce")
        }
    }

    /// A background intent must not move anything under the user's hands: the
    /// interactive `addTask` empties the composer's draft, closes the
    /// composer, moves the selection and remembers an untitled card for later
    /// discarding — all right for a surface, all wrong for a Shortcut.
    @Test func anIntentTouchesNothingTheUserIsInTheMiddleOf() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        store.beginAdding(in: BoardColumn.backlog.id)
        store.draft = "half a thought"
        let selected = store.selection
        try await borrowing(store) {
            let intent = AddTaskIntent()
            intent.taskTitle = "From the background"

            _ = try await intent.perform()

            #expect(store.draft == "half a thought", "the intent wiped the composer's draft")
            #expect(store.addingPlacement != nil, "the intent closed the composer")
            #expect(store.selection == selected, "the intent moved the selection")
            let added = try #require(store.tasks.first { $0.title == "From the background" })
            #expect(store.sheetID != added.id, "the intent opened a sheet nobody asked for")
        }
    }

    @Test func aColumnNoBoardHasIsRefusedRatherThanGuessedAt() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        await borrowing(store) {
            let intent = AddTaskIntent()
            intent.taskTitle = "Nowhere to go"
            intent.column = ColumnEntity(id: UUID(), name: "Gone", boardName: "Gone")

            await #expect(throws: TaskIntentError.noSuchColumn) { _ = try await intent.perform() }
            #expect(store.tasks.contains { $0.title == "Nowhere to go" } == false)
        }
    }

    @Test func showingTodayOpensTheViewAndClearsWhatWouldHideIt() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        store.query = "café"
        store.showInbox()
        try await borrowing(store) {
            _ = try await ShowTodayIntent().perform()
            #expect(store.activeView == .today)
            #expect(store.query.isEmpty)
        }
    }

    /// Somebody who deleted Today gets the board — asked, not assumed. The
    /// intent used to park the surface on the missing id, and only the phone
    /// happened to fall back; the Mac and the iPad drew nothing at all.
    @Test func showingTodayWhenItHasBeenDeletedLandsOnTheBoard() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        store.deleteView(SavedView.id(of: .today))
        try await borrowing(store) {
            _ = try await ShowTodayIntent().perform()
            #expect(store.surface == .board, "the surface was parked on a view that no longer exists")
        }
    }

    @Test func theIntentWritesToTheOneBoardTheAppIsShowing() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let before = store.tasks.count
        try await borrowing(store) {
            let intent = AddTaskIntent()
            intent.taskTitle = "Written from outside"
            _ = try await intent.perform()
        }
        // Not to a board of its own: the card is on the store the app is
        // holding, which is the whole reason the bridge exists.
        #expect(store.tasks.count == before + 1)
        #expect(store.tasks.contains { $0.title == "Written from outside" })
    }

    // MARK: The verbs

    /// The entity is how a Shortcut names a card, so it is the first thing that
    /// has to work: `TaskEntityQuery` is an `EntityStringQuery`, and what a
    /// person types is as likely to be "NW-121" as a word from the title.
    @Test func theTaskQueryFindsACardByItsCodeAndByItsTitle() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let query = TaskEntityQuery()
            // Hoisted rather than written inside `#expect`: the macro evaluates
            // its expression in a closure of its own, which a `try await` in
            // the middle of a comparison cannot throw out of.
            let byCode = try await query.entities(matching: "NW-121")
            let byTitle = try await query.entities(matching: "drag")
            // The panel's folding, which the entity gets for free by asking the
            // store rather than filtering itself.
            let folded = try await query.entities(matching: "cafe")
            let nothing = try await query.entities(matching: "nothing here at all")

            #expect(byCode.map(\.id) == [TestBoard.dragDrop])
            #expect(byTitle.map(\.id) == [TestBoard.dragDrop])
            #expect(folded.map(\.id) == [TestBoard.cafe])
            #expect(nothing.isEmpty)
        }
    }

    @Test func completingThroughShortcutsSendsTheCardToDone() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let intent = CompleteTaskIntent()
            intent.task = TaskEntity(try #require(store[TestBoard.sync]), in: store)

            _ = try await intent.perform()

            let done = try #require(store[TestBoard.sync])
            #expect(store.isDone(done))
            #expect(done.columnID == store.doneColumnID)
        }
    }

    /// An Inbox card is completed where it lies — v13's own feature — so the
    /// intent must not need a board to send it to.
    @Test func completingAnInboxCardCompletesItWhereItIs() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let intent = CompleteTaskIntent()
            intent.task = TaskEntity(try #require(store[TestBoard.widget]), in: store)

            _ = try await intent.perform()

            let card = try #require(store[TestBoard.widget])
            #expect(card.isUnfiled, "an Inbox card was filed onto a board to complete it")
            #expect(card.isInboxCompleted)
        }
    }

    /// **Not an error.** A Shortcut that runs nightly over everything overdue
    /// would fail on its second run, and "it is finished" is what the caller
    /// asked for either way.
    @Test func completingSomethingAlreadyDoneSaysSoRatherThanFailing() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let intent = CompleteTaskIntent()
            intent.task = TaskEntity(try #require(store[TestBoard.palette]), in: store)
            let before = store[TestBoard.palette]

            _ = try await intent.perform()
            #expect(store[TestBoard.palette] == before, "a second completion changed the card")
        }
    }

    @Test func reopeningTakesACardBackOutOfDone() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let intent = ReopenTaskIntent()
            intent.task = TaskEntity(try #require(store[TestBoard.palette]), in: store)

            _ = try await intent.perform()
            #expect(store.isDone(try #require(store[TestBoard.palette])) == false)
        }
    }

    /// Every verb here starts by resolving its entity, and a card deleted since
    /// the Shortcut was built is the likeliest failure of any of them. Silence
    /// is the one answer that must not happen: it is indistinguishable from a
    /// Shortcut that ran.
    @Test func aVerbAimedAtADeletedCardSaysSoRatherThanDoingNothing() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let ghost = TaskEntity(try #require(store[TestBoard.sync]), in: store)
        _ = store.deleteTask(TestBoard.sync)

        await borrowing(store) {
            let complete = CompleteTaskIntent()
            complete.task = ghost
            await #expect(throws: TaskIntentError.noSuchTask) { _ = try await complete.perform() }

            let move = MoveTaskIntent()
            move.task = ghost
            await #expect(throws: TaskIntentError.noSuchTask) { _ = try await move.perform() }

            let due = SetDueDateIntent()
            due.task = ghost
            await #expect(throws: TaskIntentError.noSuchTask) { _ = try await due.perform() }
        }
    }

    @Test func movingThroughShortcutsLandsInTheNamedColumn() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: TestBoard.boards)
        try await borrowing(store) {
            let intent = MoveTaskIntent()
            intent.task = TaskEntity(try #require(store[TestBoard.dragDrop]), in: store)
            intent.column = ColumnEntity(id: TestBoard.queue.id, name: "Queue", boardName: "Support triage")

            _ = try await intent.perform()

            #expect(store[TestBoard.dragDrop]?.placement
                    == .column(board: TestBoard.support.id, column: TestBoard.queue.id))
        }
    }

    @Test func movingWithNoDestinationGivenGoesToTheInbox() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let intent = MoveTaskIntent()
            intent.task = TaskEntity(try #require(store[TestBoard.dragDrop]), in: store)

            _ = try await intent.perform()
            #expect(store[TestBoard.dragDrop]?.isUnfiled == true)
        }
    }

    // MARK: Reading the board

    /// **The session's search field is not disturbed.** An intent can run while
    /// somebody is typing in it, and one that set `query` to do its own
    /// searching would rewrite what they were looking at.
    @Test func findingTasksAnswersWithoutTouchingTheSearchField() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        store.query = "café"
        try await borrowing(store) {
            let intent = FindTasksIntent()
            intent.text = "drag"

            let result = try await intent.perform()
            #expect(result.value?.map(\.id) == [TestBoard.dragDrop])
            #expect(store.query == "café", "the intent rewrote the user's search")
        }
    }

    @Test func findingTasksIsScopedByTheColumnItIsGiven() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let intent = FindTasksIntent()
            intent.column = ColumnEntity(id: BoardColumn.backlog.id, name: "Backlog",
                                         boardName: SeedData.defaultBoard.name)

            let result = try await intent.perform()
            let found = try #require(result.value)
            #expect(found.isEmpty == false)
            #expect(found.allSatisfy { store[$0.id]?.columnID == BoardColumn.backlog.id })
        }
    }

    @Test func theViewIntentReturnsExactlyWhatTheViewGathers() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let inbox = try #require(store.views.first { $0.id == SavedView.id(of: .inbox) })
            let intent = TasksInViewIntent()
            intent.view = ViewEntity(id: inbox.id, name: inbox.name)

            let result = try await intent.perform()
            #expect(result.value?.map(\.id) == store.tasks(in: inbox, today: TestBoard.dueDay).map(\.id))
        }
    }

    @Test func aViewThatHasBeenDeletedIsRefusedRatherThanEmpty() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        await borrowing(store) {
            let intent = TasksInViewIntent()
            intent.view = ViewEntity(id: UUID(), name: "Gone")
            await #expect(throws: TaskIntentError.noSuchView) { _ = try await intent.perform() }
        }
    }

    // MARK: Setting one field

    @Test func aDueDateIsSetAndAnAbsentOneClearsIt() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let card = TaskEntity(try #require(store[TestBoard.cafe]), in: store)

            let set = SetDueDateIntent()
            set.task = card
            set.due = TestBoard.laterDay.date()
            _ = try await set.perform()
            #expect(store[TestBoard.cafe]?.due == TestBoard.laterDay)

            let clear = SetDueDateIntent()
            clear.task = card
            _ = try await clear.perform()
            #expect(store[TestBoard.cafe]?.due == nil)
        }
    }

    @Test func aPriorityIsSetThroughItsOwnEnum() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let intent = SetPriorityIntent()
            intent.task = TaskEntity(try #require(store[TestBoard.cafe]), in: store)
            intent.priority = .max

            _ = try await intent.perform()
            #expect(store[TestBoard.cafe]?.priority == .max)
        }
    }

    /// **Add means add, not toggle.** A rule that says *put the Urgent label on
    /// this* has to mean that whether or not the label is already there — a
    /// Shortcut run twice must not undo itself.
    @Test func addingALabelTwiceLeavesItOnAndRemovingTwiceLeavesItOff() async throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        try await borrowing(store) {
            let card = TaskEntity(try #require(store[TestBoard.cafe]), in: store)
            let design = try #require(store.labels.first { $0.key == "design" })
            let label = LabelEntity(id: design.key, name: design.name)

            func run(_ change: LabelChange) async throws {
                let intent = ChangeLabelIntent()
                intent.task = card
                intent.change = change
                intent.label = label
                _ = try await intent.perform()
            }

            try await run(.add)
            try await run(.add)
            #expect(store[TestBoard.cafe]?.labelKeys.filter { $0 == "design" }.count == 1)

            try await run(.remove)
            try await run(.remove)
            #expect(store[TestBoard.cafe]?.labelKeys.contains("design") == false)
        }
    }

    @Test func theEntityQueriesOfferWhatTheBoardActuallyHas() async throws {
        let store = TestBoard.store(boards: TestBoard.boards)
        try await borrowing(store) {
            let boards = try await BoardEntityQuery().suggestedEntities()
            #expect(boards.map(\.name) == TestBoard.boards.map(\.name))

            let columns = try await ColumnEntityQuery().suggestedEntities()
            #expect(columns.count == TestBoard.boards.reduce(0) { $0 + $1.columns.count })
            // Two boards can both have a "Done", so a picker showing nothing but
            // the name would be a coin toss.
            #expect(columns.allSatisfy { !$0.boardName.isEmpty })

            let byID = try await ColumnEntityQuery().entities(for: [TestBoard.queue.id])
            #expect(byID.map(\.name) == ["Queue"])
            #expect(byID.first?.boardName == "Support triage")
        }
    }
}
