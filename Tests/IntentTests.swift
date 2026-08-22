import AppIntents
import Foundation
import Testing
@testable import Simple_Kanban

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
            #expect(store.tasks.first { $0.title == "Due from Shortcuts" }?.due == TestBoard.laterDay)
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
        store.selectSurface(.inbox)
        try await borrowing(store) {
            _ = try await ShowTodayIntent().perform()
            #expect(store.activeView == .today)
            #expect(store.query.isEmpty)
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
