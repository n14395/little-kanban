import Foundation
import Testing
@testable import Cardstock

/// The starters offered on first launch (7.5), and the shape a template has to
/// be in for `BoardStore.importBoard` to be able to take it.
@MainActor
struct StarterTemplateTests {
    @Test func offersTheThreeStartersPlusTheSampleAndABareStart() {
        #expect(SeedData.starters.map(\.id) == ["personal", "sprint", "content", "sample", "blank"])
        // Seed task t6 asks for Personal, Sprint and Content calendar by name.
        #expect(SeedData.starters.count { $0.tasks.isEmpty } == 1)
    }

    @Test func everyTemplateHasABoardWithAColumnWorkCanStartInAndOneItFinishesIn() throws {
        // Except the no-content starter, whose whole promise is the absence
        // of a board — see `theNoContentStarterLeavesTheAppCompletelyBare`.
        for template in SeedData.starters where !template.boards.isEmpty {
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
        for template in SeedData.starters where template.id != "sample" && !template.boards.isEmpty {
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

    /// "No Content" means it: not a board named by the app, not the app's six
    /// labels — nothing. The absence of a board is a state the app already
    /// stands in (it is what deleting the last board leaves), and the person
    /// who picked this row asked for exactly that.
    @Test func theNoContentStarterLeavesTheAppCompletelyBare() {
        let store = BoardStore(tasks: [], boards: [], labels: [], file: nil)
        store.importBoard(SeedData.blank.snapshot)
        #expect(store.boards.isEmpty, "No Content seeded a board")
        #expect(store.labels.isEmpty, "No Content seeded labels")
        #expect(store.tasks.isEmpty)
    }

    /// And through Settings ▸ Delete everything, the same row is the way to a
    /// truly bare app — replacing, not merging, so nothing survives it.
    @Test func startingOverWithNoContentBaresTheWholeApp() {
        let store = TestBoard.store()
        store.startOver(with: SeedData.blank.snapshot)
        #expect(store.boards.isEmpty)
        #expect(store.labels.isEmpty)
        #expect(store.tasks.isEmpty)
        #expect(store.activeBoardID == nil)
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
        // The no-content row counts nothing, not "0" of anything.
        let bare = FirstRunView.summary(SeedData.blank)
        #expect(!bare.contains("0"), "the bare row is counting absences: \(bare)")
    }

    /// The suite launches the app as its test host. A host that stopped at a
    /// modal picker would be a host with no board on it.
    @Test func theFirstRunPickerNeverStandsInFrontOfATestHost() {
        #expect(FirstRun.isPending == false)
    }
}
