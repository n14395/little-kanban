import Foundation
import Testing
@testable import Simple_Kanban

/// What a brand-new install is handed.
///
/// It used to be `SeedData`: fifteen cards about building this app, on a board
/// called "Northwind iOS 3.0". A good demo, and somebody else's todo list. 7.5
/// replaced that with a picker — five starters, one of which is empty and one of
/// which is still the sample — so the two claims worth pinning are that nothing
/// is chosen *for* the user, and that whatever they do choose is a board the app
/// can actually draw.
///
/// The second half is the one with teeth. A template is written by hand, and a
/// hand-written board can name a column that is on no board, reuse a code, or
/// carry a label key with no definition behind it — all of which produce a board
/// that loads, looks fine, and has cards nothing can reach.
@MainActor
@Suite struct FirstRunTests {
    // MARK: Nothing is chosen for anybody

    /// The board a first launch builds before the picker is answered: empty.
    /// Not the seed, and not `restored()` — which seeds.
    @Test func aFirstLaunchStartsOnNothingAtAll() {
        let temp = TempBoard()
        let store = FirstRun.emptyStore(file: temp.file)

        #expect(store.tasks.isEmpty, "a first launch was handed somebody else's cards")
        #expect(store.boards.isEmpty, "a first launch was handed somebody else's board")
        #expect(store.labels.isEmpty)
        #expect(store.activeBoardID == nil)
        #expect(store.inboxCount == 0)
    }

    /// `restored()` still seeds, because that is what a *reinstall over an
    /// existing preference* wants — but a fresh install goes through the picker
    /// instead, and the two must not be confused.
    @Test func restoringWithNoFileStillSeedsForEverybodyElse() {
        let temp = TempBoard()
        let store = BoardStore.restored(file: temp.file)
        #expect(store.tasks.count == SeedData.tasks.count)
        #expect(store.boards.map(\.id) == SeedData.boards.map(\.id))
    }

    /// The picker never stands in front of the suite. `isPending` is a
    /// `static let` answered once per process, and a build that dropped the
    /// test-host guard would hang every run behind a modal with no board on it.
    @Test func thePickerNeverBlocksTheTestHost() {
        #expect(FirstRun.isPending == false)
    }

    /// The sample is offered rather than imposed, and it is not the first thing
    /// offered: the picker's job is to ask, and a list whose first row is the
    /// developer's own board is a list most people will accept without reading.
    @Test func theSampleIsOfferedRatherThanImposed() throws {
        let ids = SeedData.starters.map(\.id)
        #expect(ids.contains("sample"), "the sample board is no longer reachable at all")
        #expect(ids.first != "sample", "the sample is the first row of the picker")
        #expect(ids.contains("blank"), "there is no way to start with an empty board")
        #expect(SeedData.starters.count >= 4, "7.5 asks for three starters plus the sample")
        #expect(Set(ids).count == ids.count, "two templates share an id")

        let sample = try #require(SeedData.starters.first { $0.id == "sample" })
        #expect(sample.tasks.map(\.id) == SeedData.tasks.map(\.id),
                "the sample no longer holds the sample board")
    }

    /// And the three real starters are about the person choosing rather than
    /// about this app: none of them carries a card from the sample board.
    @Test func theStartersAreNotTheDevelopersTodoList() {
        let sampleTitles = Set(SeedData.tasks.map(\.title))
        for template in SeedData.starters where template.id != "sample" {
            for task in template.tasks {
                #expect(!sampleTitles.contains(task.title),
                        "\(template.id) carries \(task.title) from the sample board")
            }
        }
    }

    /// Every row of the picker says what it is and how big it is. A template
    /// with no blurb draws a name and a blank line.
    @Test func everyTemplateIsDescribedInThePicker() {
        for template in SeedData.starters {
            #expect(!template.name.isEmpty, "\(template.id) has no name")
            #expect(!template.blurb.isEmpty, "\(template.id) has no blurb")
            #expect(!template.symbol.isEmpty, "\(template.id) has no symbol")
            #expect(!FirstRunView.summary(template).isEmpty, "\(template.id) summarises to nothing")
            #expect(template.columns.count >= 3, "\(template.id) is not a board")
        }
        let names = SeedData.starters.map(\.name)
        #expect(Set(names).count == names.count, "two templates are called the same thing")
    }

    /// The template's own cards, before anything imports them: unique codes,
    /// each minted under its board's prefix.
    ///
    /// The claim has to be made about the *template* rather than about the store
    /// it lands in, because `BoardSnapshot.merging` re-mints a code collision —
    /// so a template whose cards all carry one code still loads perfectly, with
    /// every card silently renumbered on the way in, and every store-side
    /// assertion passes.
    @Test func everyTemplateMintsItsOwnCodes() throws {
        for template in SeedData.starters {
            let board = try #require(template.boards.first)
            var codes: Set<String> = []
            for task in template.tasks {
                #expect(codes.insert(task.code).inserted,
                        "\(template.id): two cards are both called \(task.code)")
                #expect(task.code.hasPrefix(board.codePrefix + "-"),
                        "\(template.id): \(task.code) is not minted under \(board.codePrefix)")
            }
        }
    }

    // MARK: Every template produces a board the app can draw

    /// The property, over all five: fold the template into the empty board a
    /// first launch actually starts on, and the result satisfies the placement
    /// invariant and everything hanging off it.
    @Test func everyTemplateProducesAValidBoard() {
        for template in SeedData.starters {
            let temp = TempBoard()
            let store = FirstRun.emptyStore(file: temp.file)
            store.importBoard(template.snapshot)
            expectStarterIsUsable(store, template.id)
        }
    }

    /// The same, through the file. A template is only ever chosen once, so a
    /// card it places somewhere unplaceable would be silently unfiled by the
    /// *next* launch rather than by the one that chose it — which is a card that
    /// moves to the Inbox overnight.
    @Test func everyTemplateSurvivesARelaunch() throws {
        for template in SeedData.starters {
            let temp = TempBoard()
            let store = FirstRun.emptyStore(file: temp.file)
            store.importBoard(template.snapshot)
            let placements = store.tasks.map { ($0.code, $0.placement) }
            store.saveNow()

            let reopened = BoardStore.restored(file: temp.file)
            expectStarterIsUsable(reopened, "\(template.id) after a relaunch")
            #expect(reopened.tasks.count == store.tasks.count,
                    "\(template.id) lost a card across a relaunch")
            for (code, placement) in placements {
                let after = reopened.tasks.first { $0.code == code }
                #expect(after?.placement == placement, "\(template.id): \(code) moved across a relaunch")
            }
        }
    }

    /// A chosen template is a board somebody can work on: a card can be added
    /// to its landing column, given a due date, moved to Done and archived — the
    /// whole first session, on every starter.
    @Test func everyTemplateIsABoardSomebodyCanWorkOn() throws {
        for template in SeedData.starters {
            let temp = TempBoard()
            let store = FirstRun.emptyStore(file: temp.file)
            store.importBoard(template.snapshot)

            let board = try #require(store.boards.first, "\(template.id) has no board")
            let landing = try #require(board.landingColumn, "\(template.id) has nowhere to land a card")
            let done = try #require(board.doneColumn, "\(template.id) has no Done column")

            let existing = Set(store.tasks.map(\.code))
            let id = store.addTask(to: landing.id, title: "First thing")
            let made = try #require(store[id])
            #expect(!existing.contains(made.code),
                    "\(template.id) minted \(made.code), which is already on the board")
            #expect(made.columnID == landing.id)

            store.move(id, to: done.id)
            #expect(store.isDone(try #require(store[id])), "\(template.id): a card could not reach Done")
            store.archive(id)
            #expect(try #require(store[id]).isArchived)
            expectStarterIsUsable(store, "\(template.id) after a first session")
        }
    }

    /// Choosing is one ⌘Z. The picker folds the template in with `importBoard`
    /// rather than replacing the store, so somebody who picked the wrong row
    /// gets back to the empty board rather than to a second copy of it.
    @Test func choosingATemplateIsOneUndoStep() throws {
        let (store, undo) = TestBoard.undoing(tasks: [], boards: [])
        #expect(store.boards.isEmpty)

        step(undo) { store.importBoard(SeedData.personal.snapshot) }
        #expect(store.boards.count == 1)
        #expect(store.tasks.count == SeedData.personal.tasks.count)

        undo.undo()
        #expect(store.boards.isEmpty, "undoing the choice left the board behind")
        #expect(store.tasks.isEmpty, "undoing the choice left the cards behind")
    }

    // MARK: The invariant, stated once

    /// Every clause a starter board has to satisfy to be one.
    ///
    /// The placement half is `PlacementInvariantTests`' property restated
    /// against a board nothing has mutated yet — which is exactly where a
    /// hand-written template breaks it, because the store's own mutations are
    /// what usually maintain it.
    private func expectStarterIsUsable(_ store: BoardStore, _ label: String) {
        var ids: Set<TaskItem.ID> = []
        var codes: Set<String> = []
        let keys = Set(store.labels.map(\.key))

        #expect(!store.boards.isEmpty, "\(label): no board")
        #expect(store.activeBoardID != nil, "\(label): no board is active")
        #expect(store.boards.contains { $0.id == store.activeBoardID }, "\(label): the active board is gone")

        var columnIDs: Set<BoardColumn.ID> = []
        for board in store.boards {
            #expect(!board.columns.isEmpty, "\(label): \(board.name) has no columns")
            #expect(board.landingColumn != nil, "\(label): \(board.name) has nowhere to land a card")
            #expect(!board.codePrefix.isEmpty, "\(label): \(board.name) mints codes with no prefix")
            for column in board.columns {
                #expect(columnIDs.insert(column.id).inserted,
                        "\(label): column \(column.name) is on two boards")
                #expect(!column.name.isEmpty, "\(label): a column has no name")
                #expect(!column.short.isEmpty, "\(label): \(column.name) has no short name")
            }
        }

        for task in store.tasks {
            #expect(ids.insert(task.id).inserted, "\(label): \(task.code) is on the board twice")
            #expect(codes.insert(task.code).inserted, "\(label): two cards are both called \(task.code)")
            #expect(!task.title.isEmpty, "\(label): \(task.code) has no title")
            #expect((task.boardID == nil) == (task.columnID == nil),
                    "\(label): \(task.code) has half a placement")
            for key in task.labelKeys {
                #expect(keys.contains(key), "\(label): \(task.code) wears \(key), which nothing defines")
            }
            guard let boardID = task.boardID, let columnID = task.columnID else { continue }
            #expect(store.board(id: boardID)?.column(id: columnID) != nil,
                    "\(label): \(task.code) names a column its own board has not got")
            #expect(store.board(ofColumn: columnID)?.id == boardID,
                    "\(label): \(task.code) is on a board that is not the one holding its column")
        }

        // The counts every surface draws, against the cards themselves.
        let unfiled = store.tasks.count { $0.isUnfiled && !$0.isArchived }
        #expect(store.inboxCount == unfiled, "\(label): the Inbox count has drifted")
        #expect(store.totalCount == store.tasks.count { !$0.isArchived },
                "\(label): the total count has drifted")
        for board in store.boards {
            #expect(store.taskCount(for: board.id) == store.tasks.count(where: {
                $0.boardID == board.id && !$0.isArchived
            }), "\(label): \(board.name)'s count has drifted")
        }
    }
}
