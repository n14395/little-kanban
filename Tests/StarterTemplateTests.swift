import Foundation
import Testing
@testable import Simple_Kanban

/// The starters offered on first launch (7.5), and the shape a template has to
/// be in for `BoardStore.importBoard` to be able to take it.
@MainActor
struct StarterTemplateTests {
    @Test func offersTheThreeStartersPlusTheSampleAndAnEmptyBoard() {
        #expect(SeedData.starters.map(\.id) == ["personal", "sprint", "content", "sample", "blank"])
        // Seed task t6 asks for Personal, Sprint and Content calendar by name.
        #expect(SeedData.starters.count { $0.tasks.isEmpty } == 1)
    }

    @Test func everyTemplateHasABoardWithAColumnWorkCanStartInAndOneItFinishesIn() throws {
        for template in SeedData.starters {
            let board = try #require(template.boards.first, "\(template.id) has no board")
            #expect(board.columns.count >= 4)
            #expect(board.landingColumn != nil)
            // The *last* column, which is what makes it the Done one — see
            // `Board.doneColumn`. A template that ended on a working column
            // would hand a new board a Done column called "Drafting".
            #expect(board.doneColumn != nil, "\(template.id) has nowhere to finish")
            #expect(board.landingColumn?.id != board.doneColumn?.id,
                    "\(template.id) lands new cards in its Done column")
            #expect(!board.codePrefix.isEmpty)
        }
    }

    /// Column ids are unique across *boards*, because the store resolves a
    /// card's board from its column. Two starters sharing one would put both
    /// boards' cards on whichever came first.
    @Test func noTwoTemplatesShareAColumnID() {
        var seen: Set<BoardColumn.ID> = []
        for template in SeedData.starters {
            for column in template.boards.flatMap(\.columns) {
                #expect(seen.insert(column.id).inserted, "\(template.id) reuses a column id")
            }
        }
    }

    @Test func everyCardLandsOnItsOwnBoardAndCarriesAUniqueCodeUnderItsPrefix() throws {
        for template in SeedData.starters where template.id != "sample" {
            let board = try #require(template.boards.first)
            let columns = Set(board.columns.map(\.id))
            var codes: Set<String> = []
            for task in template.tasks {
                #expect(task.boardID == board.id)
                #expect(task.columnID.map(columns.contains) == true, "\(task.code) is on no column")
                #expect(task.code.hasPrefix("\(board.codePrefix)-"))
                #expect(codes.insert(task.code).inserted, "\(task.code) twice in \(template.id)")
            }
            // The counter has to sit above every code already minted, or the
            // first task added lands on one of them.
            #expect(template.nextSerial == BoardSnapshot.baseSerial + template.tasks.count)
        }
    }

    @Test func everyLabelACardWearsIsOneTheTemplateShipsWith() {
        for template in SeedData.starters {
            let keys = Set(template.labels.map(\.key))
            for task in template.tasks {
                for key in task.labelKeys {
                    #expect(keys.contains(key), "\(template.id) has no label '\(key)'")
                }
            }
        }
    }

    /// The whole first-run mechanism: the app launches on nothing and folds the
    /// chosen template into it. Merging into an empty board has to reproduce
    /// the template exactly — anything less and the picker hands out a board
    /// that is not the one it drew.
    @Test func choosingATemplateFillsAnEmptyBoardWithExactlyIt() throws {
        for template in SeedData.starters {
            let store = BoardStore(tasks: [], boards: [], labels: [], file: nil)
            store.importBoard(template.snapshot)

            #expect(store.boards.map(\.name) == template.boards.map(\.name), "\(template.id)")
            #expect(store.tasks.count == template.tasks.count, "\(template.id)")
            #expect(store.labels.map(\.key) == template.labels.map(\.key), "\(template.id)")
            // `adoptContent` does not take the file's `activeBoardID`, so the
            // store has to have settled on the one board it now holds itself.
            #expect(store.activeBoardID == template.boards.first?.id, "\(template.id)")
            #expect(store.columns.count == template.columns.count, "\(template.id)")
            let unfiled = store.tasks.count(where: \.isUnfiled)
            #expect(unfiled == template.tasks.count { $0.isUnfiled }, "\(template.id)")
        }
    }

    /// The empty board is a real board rather than the absence of one: an app
    /// with no boards at all shows a sidebar with nothing to click.
    @Test func theEmptyStarterStillLeavesABoardToTypeInto() {
        let store = BoardStore(tasks: [], boards: [], labels: [], file: nil)
        store.importBoard(SeedData.blank.snapshot)
        #expect(store.boards.count == 1)
        #expect(store.tasks.isEmpty)
        #expect(store.columns.count == 4)
    }

    @Test func theSampleStarterIsTheBoardTheAppHasAlwaysShipped() {
        #expect(SeedData.sample.tasks.count == SeedData.tasks.count)
        #expect(SeedData.sample.boards == SeedData.boards)
        #expect(SeedData.sample.labels == LabelDef.seed)
    }

    /// The picker's own line under each row. It says what choosing does, so it
    /// has to count what is actually there.
    @Test func theSummaryCountsWhatTheTemplateHolds() {
        let summary = FirstRunView.summary(SeedData.sprint)
        #expect(summary.contains("\(SeedData.sprint.columns.count)"))
        #expect(summary.contains("\(SeedData.sprint.tasks.count)"))
        #expect(!FirstRunView.summary(SeedData.blank).contains("0 cards"))
    }

    /// The suite launches the app as its test host. A host that stopped at a
    /// modal picker would be a host with no board on it.
    @Test func theFirstRunPickerNeverStandsInFrontOfATestHost() {
        #expect(FirstRun.isPending == false)
    }
}
