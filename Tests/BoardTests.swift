import Foundation
import Testing
@testable import Cardstock

/// Boards, and the one global Inbox.
///
/// Two boards throughout, each with columns of its own, because almost
/// everything here — a count, a code prefix, a column lookup, a delete — is only
/// capable of failing when there is more than one board to get wrong.
@MainActor
@Suite struct BoardTests {
    private static func uuid(_ a: UInt8, _ b: UInt8, _ n: UInt8) -> UUID {
        UUID(uuid: (a, b, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    private static func column(_ n: UInt8, _ name: String) -> BoardColumn {
        BoardColumn(id: uuid(0xC0, 0x1B, n), name: name, short: name, dot: .hex(0xA8A29A))
    }

    private static let alphaTodo = column(1, "To do")
    private static let alphaDone = column(2, "Shipped")
    private static let betaTodo = column(3, "Queue")
    private static let betaDone = column(4, "Closed")

    private static let alphaID = uuid(0xB0, 0x1D, 1)
    private static let betaID = uuid(0xB0, 0x1D, 2)

    private static let alpha = Board(
        id: alphaID, name: "Alpha", symbol: "house", createdAt: TestBoard.at(90_000),
        columns: [alphaTodo, alphaDone], codePrefix: "AL"
    )
    private static let beta = Board(
        id: betaID, name: "Beta", symbol: "briefcase", createdAt: TestBoard.at(80_000),
        columns: [betaTodo, betaDone], codePrefix: "BE"
    )

    private static let onAlpha = uuid(0x7A, 0x5C, 1)
    private static let onBeta = uuid(0x7A, 0x5C, 2)
    private static let captured = uuid(0x7A, 0x5C, 3)

    private static func tasks() -> [TaskItem] {
        [
            TaskItem(
                id: onAlpha, code: "AL-140", boardID: alphaID, columnID: alphaTodo.id,
                title: "Ship the thing",
                subtasks: [SubTask(text: "Write it")],
                activity: [ActivityEntry(.created, when: TestBoard.at(10_000))],
                createdAt: TestBoard.at(10_000), updatedAt: TestBoard.at(10_000)
            ),
            TaskItem(
                id: onBeta, code: "BE-141", boardID: betaID, columnID: betaTodo.id,
                title: "Answer the ticket",
                activity: [ActivityEntry(.created, when: TestBoard.at(9_000))],
                createdAt: TestBoard.at(9_000), updatedAt: TestBoard.at(9_000)
            ),
            TaskItem(
                id: captured, code: "IN-142", title: "Something someone said",
                activity: [ActivityEntry(.captured, when: TestBoard.at(8_000))],
                createdAt: TestBoard.at(8_000), updatedAt: TestBoard.at(8_000)
            ),
        ]
    }

    private static func store(file: BoardFile? = nil) -> BoardStore {
        BoardStore(
            tasks: tasks(), boards: [alpha, beta], activeBoardID: alphaID, labels: LabelDef.seed,
             nextSerial: BoardSnapshot.baseSerial + 3, file: file
        )
    }

    private static func undoing() -> (store: BoardStore, undo: RecordingUndoManager) {
        let undo = RecordingUndoManager()
        undo.groupsByEvent = false
        let store = store()
        store.undoManager = undo
        return (store, undo)
    }

    /// The whole board including its boards, so a board mutation is visible to
    /// an "exactly as it was" assertion.
    private func board(_ store: BoardStore) -> BoardMutation {
        BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash, views: store.views, savedColors: store.savedColors)
    }

    // MARK: The invariant

    /// Unfiled, or on a board in one of *that* board's columns. Never one of
    /// the two fields without the other, whatever route the card took.
    private func checkPlacements(_ store: BoardStore, _ label: String) {
        for task in store.tasks {
            #expect((task.boardID == nil) == (task.columnID == nil), "\(label): \(task.code) has half a placement")
            guard let boardID = task.boardID, let columnID = task.columnID else { continue }
            #expect(store.board(id: boardID)?.column(id: columnID) != nil,
                    "\(label): \(task.code) names a column its board has not got")
        }
    }

    @Test func everyPlacementRouteLeavesATaskUnfiledOrProperlyFiled() {
        let store = Self.store()
        checkPlacements(store, "as built")

        store.unfile(Self.onAlpha)
        #expect(store[Self.onAlpha]?.isUnfiled == true)
        checkPlacements(store, "after unfile")

        store.file(Self.captured, onto: Self.betaID, column: Self.betaTodo.id)
        #expect(store[Self.captured]?.columnID == Self.betaTodo.id)
        checkPlacements(store, "after file")

        store.file(Self.captured, onto: Self.alphaID)
        #expect(store[Self.captured]?.columnID == Self.alphaTodo.id)   // the board's landing column
        checkPlacements(store, "after filing onto a board without naming a column")

        store.move(Self.onBeta, to: Self.alphaDone.id)
        #expect(store[Self.onBeta]?.boardID == Self.alphaID)           // the move carried the board
        checkPlacements(store, "after a cross-board move")

        store.complete(Self.onAlpha)
        checkPlacements(store, "after completing a card that was in the Inbox")

        store.quickCapture()
        checkPlacements(store, "after a quick capture")

        store.deleteBoard(Self.alphaID)
        checkPlacements(store, "after deleting a board")
    }

    @Test func aCardArrivingWithHalfAPlacementIsFiledByItsColumn() {
        let filed = TaskItem(id: Self.onBeta, code: "BE-141", columnID: Self.betaTodo.id, title: "No board")
        let strayColumn = TaskItem(id: Self.onAlpha, code: "AL-140", columnID: UUID(), title: "No column")
        let store = BoardStore(
            tasks: [filed, strayColumn], boards: [Self.alpha, Self.beta], activeBoardID: Self.alphaID
        )
        // The column is the fact that decides: it names Beta's, so that is the
        // board it joins, whatever it did or did not arrive with.
        #expect(store[Self.onBeta]?.boardID == Self.betaID)
        #expect(store[Self.onBeta]?.columnID == Self.betaTodo.id)
        // A column no board has is not a placement at all.
        #expect(store[Self.onAlpha]?.isUnfiled == true)
        #expect(store[Self.onAlpha]?.columnID == nil)
        checkPlacements(store, "adopted")
    }

    @Test func aCardOnABoardThatIsNotThereLandsInTheInbox() {
        let orphan = TaskItem(
            id: Self.onAlpha, code: "AL-140", boardID: UUID(), columnID: UUID(), title: "Homeless"
        )
        let store = BoardStore(tasks: [orphan], boards: [Self.alpha], activeBoardID: Self.alphaID)
        #expect(store[Self.onAlpha]?.isUnfiled == true)
        #expect(store.inboxCount == 1)
    }

    // MARK: The Inbox is global

    @Test func theInboxIsTheSameListWhicheverBoardIsActive() {
        let store = Self.store()
        #expect(store.inboxTasks.map(\.code) == ["IN-142"])
        store.selectBoard(Self.betaID)
        #expect(store.inboxTasks.map(\.code) == ["IN-142"])
        store.unfile(Self.onAlpha)
        #expect(Set(store.inboxTasks.map(\.code)) == ["IN-142", "AL-140"])
        store.selectBoard(Self.alphaID)
        #expect(Set(store.inboxTasks.map(\.code)) == ["IN-142", "AL-140"])
    }

    @Test func aQuickCaptureNeverHasToPickABoard() throws {
        let store = Self.store()
        store.selectBoard(Self.betaID)
        store.quickCapture()
        let fresh = try #require(store.sheetTask)
        #expect(fresh.isUnfiled)
        #expect(fresh.boardID == nil)
        // And it raises nothing: the Inbox panel used to come up behind the
        // sheet, where it could not be seen and had to be put away afterwards.
        #expect(!store.isInboxOpen)
    }

    @Test func theInboxAndEachBoardCountOnlyTheirOwn() {
        let store = Self.store()
        #expect(store.inboxCount == 1)
        #expect(store.taskCount(for: Self.alphaID) == 1)
        #expect(store.taskCount(for: Self.betaID) == 1)

        store.unfile(Self.onBeta)
        #expect(store.inboxCount == 2)
        #expect(store.taskCount(for: Self.betaID) == 0)

        // Archived cards are out of both, the way they are out of `totalCount`.
        store.archive(Self.onAlpha)
        #expect(store.taskCount(for: Self.alphaID) == 0)
        store.archive(Self.captured)
        #expect(store.inboxCount == 1)
    }

    /// The phone's list is the board's; the Inbox is a panel over it with a list
    /// of its own, and the two do not draw each other's cards.
    @Test func theInboxPanelShowsUnfiledCardsAndTheBoardTabDoesNot() {
        let store = Self.store()
        store.showInbox()
        #expect(store.inboxTasks.map(\.code) == ["IN-142"])
        #expect(store.surface == .board, "a tab is not a surface any more")
        store.selectTab(.board)
        store.mobileColumnID = Self.alphaTodo.id
        #expect(store.mobileTasks(today: TestBoard.dueDay).map(\.code) == ["AL-140"])
        #expect(store.surface == .board)
    }

    // MARK: Switching boards

    @Test func switchingBoardsChangesTheColumnsTheTitleAndTheCounts() {
        let store = Self.store()
        #expect(store.activeBoard?.name == "Alpha")
        #expect(store.columns == [Self.alphaTodo, Self.alphaDone])
        #expect(store.doneColumnID == Self.alphaDone.id)

        store.selectBoard(Self.betaID)
        #expect(store.activeBoard?.name == "Beta")
        #expect(store.columns == [Self.betaTodo, Self.betaDone])
        #expect(store.doneColumnID == Self.betaDone.id)
        // The pager was on a column of the board just left.
        #expect(store.mobileColumnID == Self.betaTodo.id)
    }

    @Test func aCardKnowsItsOwnColumnWhicheverBoardIsOnScreen() throws {
        let store = Self.store()
        let beta = try #require(store[Self.onBeta])
        #expect(store.column(for: beta)?.name == "Queue")
        #expect(store.board(for: beta)?.name == "Beta")
    }

    @Test func completingACardUsesItsOwnBoardsDoneColumn() {
        let store = Self.store()                       // Alpha is on screen
        store.complete(Self.onBeta)
        #expect(store[Self.onBeta]?.columnID == Self.betaDone.id)
        #expect(store[Self.onBeta]?.boardID == Self.betaID)
    }

    @Test func completingAnInboxCardKeepsItInTheInboxAndReopensInPlace() {
        let store = Self.store()
        store.selectBoard(Self.betaID)
        store.unfile(Self.onAlpha)
        store.complete(Self.captured)
        #expect(store[Self.captured]?.isUnfiled == true)
        #expect(store.isDone(store[Self.captured]!))
        #expect(store.inboxTasks.map(\.id) == [Self.onAlpha, Self.captured])
        store.reopen(Self.captured)
        #expect(store[Self.captured]?.isUnfiled == true)
        #expect(store.isDone(store[Self.captured]!) == false)
    }

    @Test func filingACompletedInboxCardMakesItActiveOnItsBoard() {
        let store = Self.store()
        store.complete(Self.captured)
        store.file(Self.captured, onto: Self.betaID, column: Self.betaTodo.id)

        #expect(store[Self.captured]?.placement == .column(board: Self.betaID, column: Self.betaTodo.id))
        #expect(store.isDone(store[Self.captured]!) == false)
    }

    // MARK: Following a card to where it went

    /// The board menu on a detail surface goes where it sends the card, so the
    /// panel and the board behind it cannot disagree about where it is.
    @Test func filingACardFromADetailSurfaceOpensTheBoardItWentTo() {
        let store = Self.store()
        store.select(Self.onAlpha)
        store.selectSurface(.view(SavedView.today.id))

        store.file(Self.onAlpha, onto: Self.betaID)
        store.showPlace(of: Self.onAlpha)

        #expect(store.activeBoardID == Self.betaID)
        // A saved view was standing in for the board, and the card is not on it.
        #expect(store.activeView == nil)
        // The card stays open in front of the user as it moves.
        #expect(store.selectedID == Self.onAlpha)
    }

    /// The Inbox is a panel beside the board rather than a place of its own, so
    /// going there is opening it — and putting the board back under it.
    @Test func sendingACardToTheInboxOpensThePanelBesideTheBoard() {
        let store = Self.store()
        store.isInboxOpen = false
        store.selectSurface(.view(SavedView.today.id))

        store.unfile(Self.onAlpha)
        store.showPlace(of: Self.onAlpha)

        #expect(store.isInboxOpen)
        #expect(store.surface == .board)
        #expect(store.isInboxShowing)
    }

    /// An archived card is on the Archive view, which is not a board, so there
    /// is nowhere to take the user that the card is drawn on.
    @Test func followingAnArchivedCardLeavesTheUserWhereTheyAre() {
        let store = Self.store()
        store.isInboxOpen = false
        store.file(Self.captured, onto: Self.betaID)
        store.archive(Self.captured)

        store.showPlace(of: Self.captured)

        #expect(store.activeBoardID == Self.alphaID)
        #expect(!store.isInboxOpen)
    }

    // MARK: Where a card can be moved to

    /// **Move Column** offers the card's *own* board's columns, not the board on
    /// screen. A card met in a saved view or a search result can be on any board
    /// — filing it into a column of whichever board happens to be open would be
    /// putting it somewhere nobody named.
    @Test func theColumnsACardCanMoveToAreItsOwnBoards() throws {
        let store = Self.store()
        #expect(store.activeBoardID == Self.alphaID)

        let onBeta = try #require(store[Self.onBeta])
        #expect(store.moveDestinations(for: onBeta).map(\.id) == [Self.betaTodo.id, Self.betaDone.id])

        let onAlpha = try #require(store[Self.onAlpha])
        #expect(store.moveDestinations(for: onAlpha).map(\.id) == [Self.alphaTodo.id, Self.alphaDone.id])
    }

    /// Two cards have nowhere to go, and the menu is then not drawn at all
    /// rather than drawn with every row inert: one in the Inbox, which is on no
    /// board, and an archived one, which has left the workflow — the Archive is
    /// not a column.
    @Test func aCardOnNoBoardAndAnArchivedOneHaveNoColumnsToMoveTo() throws {
        let store = Self.store()

        let captured = try #require(store[Self.captured])
        #expect(captured.isUnfiled)
        #expect(store.moveDestinations(for: captured).isEmpty)

        store.archive(Self.onAlpha)
        let archived = try #require(store[Self.onAlpha])
        #expect(archived.isArchived)
        #expect(store.moveDestinations(for: archived).isEmpty)
    }

    // MARK: Codes

    @Test func aCodeIsMintedFromTheDestinationBoardsPrefix() {
        let store = Self.store()
        let onAlpha = store.addTask(to: Self.alphaTodo.id, title: "New on Alpha")
        #expect(store[onAlpha]?.code == "AL-143")
        let onBeta = store.addTask(to: Self.betaTodo.id, title: "New on Beta")
        #expect(store[onBeta]?.code == "BE-144")
    }

    @Test func aCodeMintedInTheInboxUsesTheConstantPrefix() {
        let store = Self.store()
        let id = store.addTask(to: .inbox, title: "Captured")
        #expect(store[id]?.code == "IN-143")
    }

    @Test func aCodeNeverChangesOnceMinted() {
        let store = Self.store()
        let id = store.addTask(to: .inbox, title: "Captured")
        #expect(store[id]?.code == "IN-143")
        store.file(id, onto: Self.alphaID, column: Self.alphaTodo.id)
        #expect(store[id]?.code == "IN-143")           // not renumbered to AL-143
        store.move(id, to: Self.betaTodo.id)
        #expect(store[id]?.code == "IN-143")
        store.unfile(id)
        #expect(store[id]?.code == "IN-143")
    }

    /// The serial is the file's, not a board's, so two boards cannot hand out
    /// the same number under different prefixes.
    @Test func theSerialClimbsAcrossBoardsAndTheInbox() {
        let store = Self.store()
        let codes = [
            store.addTask(to: Self.alphaTodo.id, title: "One"),
            store.addTask(to: .inbox, title: "Two"),
            store.addTask(to: Self.betaTodo.id, title: "Three"),
        ].compactMap { store[$0]?.code }
        #expect(codes == ["AL-143", "IN-144", "BE-145"])
    }

    @Test func aDiscardedCaptureHandsBackItsSerialWhateverPrefixItCarried() {
        let store = Self.store()
        let id = store.addTask(to: .inbox, title: "", fromPhone: true, log: .captured)
        #expect(store[id]?.code == "IN-143")
        store.discardIfBlank(id)
        let next = store.addTask(to: Self.alphaTodo.id, title: "Real")
        #expect(store[next]?.code == "AL-143")
    }

    // MARK: Managing boards

    @Test func aBoardCanBeCreatedRenamedRemarkedReorderedAndDeleted() throws {
        let store = Self.store()
        let id = try #require(store.createBoard(named: "Gamma", symbol: "leaf", codePrefix: "gm"))
        #expect(store.boards.map(\.name) == ["Alpha", "Beta", "Gamma"])
        #expect(store.board(id: id)?.codePrefix == "GM")
        // Creating a board moves to it — it is the one place the user is going.
        #expect(store.activeBoardID == id)

        store.renameBoard(id, to: "  Gamma   Ray  ")
        #expect(store.board(id: id)?.name == "Gamma Ray")
        #expect(store.board(id: id)?.symbol == "leaf")
        store.setBoardSymbol(id, to: "flame")
        #expect(store.board(id: id)?.symbol == "flame")
        // Trimmed, and an empty one is refused in favour of the fallback: a row
        // with no mark at all is a row that looks broken.
        store.setBoardSymbol(id, to: "   ")
        #expect(store.board(id: id)?.symbol == SymbolMark.boardFallback)

        store.moveBoard(fromOffsets: [2], toOffset: 0)
        #expect(store.boards.map(\.name) == ["Gamma Ray", "Alpha", "Beta"])

        store.deleteBoard(id)
        #expect(store.boards.map(\.name) == ["Alpha", "Beta"])
    }

    @Test func aBoardWithNoNameIsRefused() {
        let store = Self.store()
        #expect(store.createBoard(named: "   ") == nil)
        #expect(store.boards.count == 2)
    }

    /// **A new board arrives with its Done column and nothing else.**
    ///
    /// It used to hold a copy of the seed workflow, and the first thing anyone
    /// making a board of their own did was delete four columns they had not
    /// asked for. Then it held none at all, which left the one column every
    /// board is *required* to have — see `Board.doneColumn` — as something the
    /// app added behind the user's back along with their first real one.
    @Test func aNewBoardStartsWithItsDoneColumnAndNothingElse() throws {
        let store = Self.store()
        let id = try #require(store.createBoard(named: "Gamma"))
        let fresh = try #require(store.board(id: id))
        #expect(fresh.columns.count == 1)
        #expect(fresh.doneColumn?.id == fresh.columns.first?.id)
        #expect(fresh.workingColumns.isEmpty, "a new board has somewhere to finish, not somewhere to work")
        // Its own column, not the seed's: two boards may not share a column id.
        #expect(fresh.columns.first?.id != BoardColumn.done.id)
        // …and the store is *on* it, which is what makes the blank board
        // surface — and its offer of a first column — the thing on screen.
        #expect(store.activeBoardID == id)
        #expect(store.workingColumns.isEmpty)
    }

    /// When the strip steps aside for the blank-board state, spelled out —
    /// `BoardScrollView.showsBlankState`, the rule the phone has always
    /// applied. The line that pins the bug: a column added to a blank board
    /// used to stay invisible behind "This board is empty" until the first
    /// card materialised it, because the old rule read the cards and never
    /// the columns.
    @Test func aBoardWithAWorkingColumnShowsItsColumnsHoweverEmpty() {
        // The fix: structure on a cardless board is drawn, not announced away.
        #expect(!BoardScrollView.showsBlankState(
            hasWorkingColumns: true, hasAnyVisibleCard: false, isComposing: false
        ), "a freshly added column hid behind the blank-board state")
        // A board with only its Done column and nothing in it is blank.
        #expect(BoardScrollView.showsBlankState(
            hasWorkingColumns: false, hasAnyVisibleCard: false, isComposing: false
        ))
        // A card completed onto a Done-only board must stay reachable.
        #expect(!BoardScrollView.showsBlankState(
            hasWorkingColumns: false, hasAnyVisibleCard: true, isComposing: false
        ))
        // A column being composed is in the strip; the strip stays.
        #expect(!BoardScrollView.showsBlankState(
            hasWorkingColumns: false, hasAnyVisibleCard: false, isComposing: true
        ))
    }

    /// The other half of blank: a card added on the phone while a board has no
    /// columns goes to the Inbox rather than onto whichever board the pager was
    /// last pointed at.
    ///
    /// `mobileColumnID` is session state that outlives the board switch, and
    /// `placement(forColumn:)` resolves an id against *every* board — so the
    /// stale id names a real, placeable column on the board before this one.
    /// Without the guard in `mobileAddPlacement` the card lands there: on a
    /// board the user is not looking at, with nothing on screen to say so.
    @Test func aCardAddedOnABlankBoardGoesToTheInboxRatherThanTheLastBoard() throws {
        let store = Self.store()
        let firstColumn = try #require(store.columns.first?.id)
        store.mobileColumnID = firstColumn

        let blank = try #require(store.createBoard(named: "Gamma"))
        #expect(store.mobileColumnID == firstColumn, "the stale id is the premise of this test")
        #expect(store.mobileAddPlacement == .inbox)

        store.addTaskToCurrentMobileColumn()
        let added = try #require(store.sheetTask)
        #expect(added.isUnfiled, "a card added on a blank board landed on another board")
        #expect(store.board(id: blank)?.workingColumns.isEmpty == true)
        // And **not** in the new board's Done column, which is the one column it
        // does have: a first card that arrived already complete would be worse
        // than one that went to the Inbox.
        #expect(store.isDone(added) == false)
    }

    @Test func aBoardWithNoPrefixTakesItsInitials() throws {
        let store = Self.store()
        let id = try #require(store.createBoard(named: "Website refresh"))
        #expect(store.board(id: id)?.codePrefix == "WR")
        // A new board is blank, so it is given a column before it is given a
        // card — which is the order the surfaces put the user through too.
        store.addColumn(named: "Doing")
        let added = store.addTask(to: .column(board: id, column: try #require(store.columns.first?.id)), title: "First")
        #expect(store[added]?.code.hasPrefix("WR-") == true)
    }

    /// **The cards go with the board.** They used to be tipped into the Inbox,
    /// which made deleting a board a move rather than a delete and left the
    /// user to clear up after it one card at a time. They are handed back to
    /// the caller instead, which is how `trashBoard` puts the whole board — its
    /// columns and its cards — into one trash row that restores as one thing.
    @Test func deletingABoardTakesItsCardsWithItAndHandsThemBack() throws {
        let store = Self.store()
        store.archive(Self.onBeta)                      // archived cards come too
        let onBeta = store.tasks.filter { $0.boardID == Self.betaID }.map(\.id)
        #expect(onBeta.contains(Self.onBeta))

        let gone = try #require(store.deleteBoard(Self.betaID))

        #expect(store.boards.map(\.name) == ["Alpha"])
        #expect(gone.board.id == Self.betaID)
        // Off the board file, and not loose in the Inbox.
        #expect(store[Self.onBeta] == nil)
        #expect(store.tasks.count == 3 - onBeta.count)
        // Handed back whole, still filed away, still knowing where it sat — so
        // the trash can put it back exactly there.
        #expect(gone.tasks.map(\.id) == onBeta)
        let kept = try #require(gone.tasks.first { $0.id == Self.onBeta })
        #expect(kept.isArchived)
        #expect(kept.columnID == Self.betaTodo.id)
    }

    @Test func deletingTheActiveBoardMovesToItsNeighbour() {
        let store = Self.store()
        store.deleteBoard(Self.alphaID)
        #expect(store.activeBoardID == Self.betaID)
        #expect(store.columns == [Self.betaTodo, Self.betaDone])
    }

    /// The Inbox is global and was never one board's, so deleting the last
    /// board leaves somewhere to be rather than nowhere.
    ///
    /// **A card captured to the Inbox is the proof of that**, and is the one
    /// card here that survives every board going away: the two that were *on*
    /// boards go with them now, which is what makes this a delete rather than a
    /// mass move into the list that is meant to stay short.
    @Test func theLastBoardCanBeDeletedAndTheInboxSurvivesIt() {
        let store = Self.store()
        store.deleteBoard(Self.alphaID)
        store.deleteBoard(Self.betaID)
        #expect(store.boards.isEmpty)
        #expect(store.activeBoardID == nil)
        #expect(store.activeBoard == nil)
        #expect(store.columns.isEmpty)
        #expect(store.inboxCount == 1, "the Inbox's own card went with a board it was never on")
        #expect(store[Self.captured] != nil)
        #expect(store.createBoard(named: "Again") != nil)
    }

    @Test func deletingABoardIsUndoneWholeCardsAndAll() {
        let (store, undo) = Self.undoing()
        let before = board(store)
        step(undo) { store.deleteBoard(Self.betaID) }
        #expect(board(store) != before)
        undo.undo()
        #expect(board(store) == before)
        #expect(store[Self.onBeta]?.columnID == Self.betaTodo.id)
    }

    // MARK: C6 — every new mutation saves and undoes

    /// The board half of `SaveContractTests`, kept here because the mutations
    /// are new. One store per mutation, each with a file of its own.
    @Test func everyBoardMutationSchedulesASave() async throws {
        var cases: [(label: String, board: TempBoard)] = []
        func mutate(_ label: String, _ body: (BoardStore) -> Void) {
            let board = TempBoard()
            body(Self.store(file: board.file))
            cases.append((label, board))
        }

        mutate("createBoard") { $0.createBoard(named: "Gamma") }
        mutate("renameBoard") { $0.renameBoard(Self.betaID, to: "Support") }
        mutate("setBoardSymbol") { $0.setBoardSymbol(Self.betaID, to: "flame") }
        mutate("moveBoard") { $0.moveBoard(fromOffsets: [1], toOffset: 0) }
        mutate("deleteBoard") { $0.deleteBoard(Self.betaID) }
        mutate("selectBoard") { $0.selectBoard(Self.betaID) }
        mutate("file") { $0.file(Self.captured, onto: Self.betaID, column: Self.betaTodo.id) }
        mutate("unfile") { $0.unfile(Self.onAlpha) }

        try await Task.sleep(for: .milliseconds(900))
        for item in cases {
            #expect(item.board.file.writeCount == 1, "\(item.label) never reached the disk")
        }
    }

    /// The board half of `UndoHarnessTests`. `selectBoard` is deliberately not
    /// here: it is navigation, like the selection, and registers nothing.
    @Test func everyBoardMutationRegistersAStep() {
        func check(_ label: String, _ body: (BoardStore) -> Void) {
            let (store, undo) = Self.undoing()
            let before = board(store)
            step(undo) { body(store) }
            #expect(board(store) != before, "\(label) changed nothing — the probe is wrong")
            #expect(undo.undoActionName != "", "\(label) registered no undo step")
            undo.undo()
            #expect(board(store) == before, "\(label) did not undo cleanly")
        }

        check("createBoard") { $0.createBoard(named: "Gamma") }
        check("renameBoard") { $0.renameBoard(Self.betaID, to: "Support") }
        check("setBoardSymbol") { $0.setBoardSymbol(Self.betaID, to: "flame") }
        check("moveBoard") { $0.moveBoard(fromOffsets: [1], toOffset: 0) }
        check("deleteBoard") { $0.deleteBoard(Self.betaID) }
        check("file") { $0.file(Self.captured, onto: Self.betaID, column: Self.betaTodo.id) }
        check("unfile") { $0.unfile(Self.onAlpha) }
    }

    @Test func selectingABoardRegistersNoStep() {
        let (store, undo) = Self.undoing()
        step(undo) { store.selectBoard(Self.betaID) }
        #expect(undo.undoActionName == "")
    }

    // MARK: Persistence

    @Test func theActiveBoardSurvivesARelaunchAndTheSurfaceDoesNot() throws {
        let temp = TempBoard()
        // A swapped-in suite, because both halves of this test otherwise reach
        // the developer's real preferences: `selectSurface` *writes* the last
        // surface there, and the relaunch *reads* "reopen the view I was on" —
        // so the test failed on any machine whose owner had turned that on,
        // and quietly edited their stored surface on every machine besides.
        let suite = try #require(UserDefaults(suiteName: "CardstockTests-\(UUID().uuidString)"))
        Preferences.reading(suite) {
            let store = Self.store(file: temp.file)
            store.selectBoard(Self.betaID)
            // Not Today: the phone *lands* on Today — see `landingSurface` —
            // so a session left there cannot tell "not resumed" from "landed".
            store.selectSurface(.view(SavedView.upcoming.id))
            store.saveNow()

            let relaunched = BoardStore.restored(file: temp.file)
            #expect(relaunched.activeBoardID == Self.betaID)
            #expect(relaunched.activeBoard?.name == "Beta")
            // Where they were looking is not board data: the relaunch lands
            // wherever this platform lands — the board on the desk and the
            // iPad, Today on the phone — never where the session left off.
            #expect(relaunched.surface == BoardStore.landingSurface)
            #expect(relaunched.activeView?.id != SavedView.upcoming.id)
        }
    }

    @Test func theBoardsAndTheInboxAreWrittenAndReadBack() throws {
        let temp = TempBoard()
        let store = Self.store(file: temp.file)
        store.unfile(Self.onAlpha)
        store.saveNow()

        let read = try temp.snapshot()
        #expect(read.version == BoardSnapshot.currentVersion)
        #expect(read.boards == store.boards)
        #expect(read.activeBoardID == Self.alphaID)
        #expect(read.tasks.first { $0.code == "AL-140" }?.boardID == nil)

        let relaunched = BoardStore.restored(file: temp.file)
        // Board order: unfiling moves the card to the end, like every other move.
        #expect(relaunched.inboxTasks.map(\.code) == ["IN-142", "AL-140"])
        #expect(relaunched.taskCount(for: Self.betaID) == 1)
    }

    /// A file with no boards opens with no boards. It is not damage — it is
    /// what `deleteBoard` leaves — so seeding one back would hand somebody who
    /// emptied their board list a board they did not make, carrying sample
    /// cards that are not theirs. A file damaged past decoding takes the other
    /// path entirely: `load` quarantines it and reports a failure, so "empty"
    /// never has to stand in for "broken".
    @Test func aFileWithNoBoardsIsAdoptedRatherThanReseeded() throws {
        let temp = TempBoard()
        let store = Self.store(file: temp.file)
        store.saveNow()
        var object = try #require(try JSONSerialization.jsonObject(with: try temp.bytes()) as? [String: Any])
        object["boards"] = []
        try temp.put(try JSONSerialization.data(withJSONObject: object))

        let relaunched = BoardStore.restored(file: temp.file)
        #expect(relaunched.boards.isEmpty)
        #expect(relaunched.activeBoard == nil)
        #expect(relaunched.activeBoardID == nil, "a board id left pointing at a board that is gone")
        // Nothing goes with the boards: the cards that named their columns are
        // in the Inbox alongside the one that was already there.
        #expect(relaunched.inboxCount == 3)
        #expect(relaunched.tasks.count == 3)
    }

    /// The same state, reached the way a user reaches it. `deleteBoard` allows
    /// emptying the list; this is the round trip that says the emptiness is
    /// what comes back, and that it is a state they can leave again.
    @Test func deletingEveryBoardSurvivesARelaunchAndLeavesAWayBack() throws {
        let temp = TempBoard()
        let store = Self.store(file: temp.file)
        store.deleteBoard(Self.alphaID)
        store.deleteBoard(Self.betaID)
        #expect(store.boards.isEmpty)
        #expect(store.activeBoardID == nil)
        store.saveNow()

        let relaunched = BoardStore.restored(file: temp.file)
        #expect(relaunched.boards.isEmpty)
        #expect(relaunched.activeBoardID == nil)
        // The card captured straight to the Inbox, which was on no board and so
        // went with none of them. The other two left with theirs.
        #expect(relaunched.inboxTasks.count == 1, "the Inbox's own card went missing with a board")

        let made = relaunched.createBoard(named: "Fresh")
        #expect(relaunched.boards.map(\.name) == ["Fresh"])
        #expect(relaunched.activeBoardID == made)
        // Blank, and deliberately: the board surface's own offer is a first
        // column rather than a first card. See
        // `aNewBoardStartsWithItsDoneColumnAndNothingElse`.
        #expect(relaunched.workingColumns.isEmpty)
    }

    // MARK: Migration — v4 → v5

    @Test func aVersionFourFileSplitsBetweenTheDefaultBoardAndTheInbox() throws {
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v4"))
        let result = temp.file.load()
        let snapshot = try #require(result.snapshot)

        #expect(result.failure == nil)
        #expect(result.migratedFromVersion == 4)
        #expect(snapshot.version == BoardSnapshot.currentVersion)

        // One board, made for a file that predates boards, adopting the columns
        // v4 kept in a flat array.
        #expect(snapshot.boards.count == 1)
        let board = try #require(snapshot.boards.first)
        #expect(board.name == "Northwind iOS 3.0")
        // The mark the v15 → v16 step deals the first board — see
        // `MigrationChainTests`, which is where the dealing is described.
        #expect(board.symbol == Board.startingSymbols[0])
        #expect(board.codePrefix == "NW")
        #expect(board.columns == BoardColumn.workflow)
        #expect(snapshot.activeBoardID == board.id)

        // The split, which is the whole point of the step: the card in the old
        // Inbox column is unfiled, and every other card joins the board in the
        // column it was already in.
        #expect(snapshot.tasks.map(\.boardID) == [nil] + Array(repeating: board.id, count: 5))
        #expect(snapshot.tasks.map(\.columnID) == [
            nil, BoardColumn.backlog.id, BoardColumn.backlog.id,
            BoardColumn.upNext.id, BoardColumn.inProgress.id, BoardColumn.done.id,
        ])
        // Codes are left exactly as they are — NW-120 is in the Inbox and is
        // still called NW-120, because somebody may have pasted it somewhere.
        #expect(snapshot.tasks.map(\.code) == TestBoard.tasks.map(\.code))
        // And nothing else about the tasks moved.
        #expect(snapshot.tasks.map(\.title) == TestBoard.tasks.map(\.title))
        #expect(snapshot.tasks.map(\.activity) == TestBoard.tasks(archiving: [TestBoard.palette: 900]).map(\.activity))
        #expect(snapshot.tasks.map(\.archivedAt) == TestBoard.tasks(archiving: [TestBoard.palette: 900]).map(\.archivedAt))
    }

    @Test func aMigratedBoardIsUsableWithoutBeingRepairedOnTheWayIn() throws {
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v4"))
        let store = BoardStore.restored(file: temp.file)

        checkPlacements(store, "migrated from v4")
        #expect(store.activeBoard?.name == "Northwind iOS 3.0")
        #expect(store.inboxTasks.map(\.code) == ["NW-120"])
        // Five of the six cards are on the board; the sixth is in the Inbox.
        // One of the five is archived, which `taskCount` leaves out.
        #expect(store.taskCount(for: try #require(store.activeBoardID)) == 4)
        #expect(store.tasks.count { $0.boardID != nil } == 5)
        // The Done behaviours still find their column through the new placement.
        #expect(store.isDone(try #require(store[TestBoard.palette])))
    }

    /// The v4 fixture is the v3 one carried forward a step by hand, so both
    /// must arrive at exactly the same board — which is also what says the
    /// fixture is a real v4 file rather than an approximation of one.
    @Test func theV3AndV4FixturesReachTheSameBoard() throws {
        func snapshot(_ name: String) throws -> BoardSnapshot {
            let temp = TempBoard()
            try temp.put(try Fixture.data(name))
            return try #require(temp.file.load().snapshot)
        }
        let fromV3 = try snapshot("board-v3")
        let fromV4 = try snapshot("board-v4")
        #expect(fromV3.tasks == fromV4.tasks)
        #expect(fromV3.boards == fromV4.boards)
        #expect(fromV3.activeBoardID == fromV4.activeBoardID)
        #expect(fromV3.nextSerial == fromV4.nextSerial)
        #expect(fromV3.labels == fromV4.labels)
        #expect(fromV3.themes == fromV4.themes)
    }

    @Test func everyFixtureStillLoadsAllTheWayForwardOntoABoard() throws {
        for name in ["board-v1", "board-v1-minted", "board-v2", "board-v3", "board-v4"] {
            let temp = TempBoard()
            try temp.put(try Fixture.data(name))
            let result = temp.file.load()
            let snapshot = try #require(result.snapshot, "\(name) did not load")
            #expect(result.failure == nil, "\(name) failed to load")
            #expect(snapshot.version == BoardSnapshot.currentVersion, "\(name) did not reach v5")
            let board = try #require(snapshot.boards.first, "\(name) arrived without a board")
            #expect(snapshot.activeBoardID == board.id, "\(name) arrived with no active board")
            let known = Set(board.columns.map(\.id))
            for task in snapshot.tasks {
                #expect((task.boardID == nil) == (task.columnID == nil),
                        "\(name): \(task.code) has half a placement")
                if let columnID = task.columnID {
                    #expect(task.boardID == board.id, "\(name): \(task.code) is on no board this file has")
                    #expect(known.contains(columnID), "\(name): \(task.code) names a column the board has not got")
                }
            }
        }
    }
}
