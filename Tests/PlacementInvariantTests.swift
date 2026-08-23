import Foundation
import Testing
@testable import Simple_Kanban

/// The one rule the whole of D2 rests on, asked as a property rather than at a
/// call site: **a task is unfiled, or it is on a board in one of *that board's*
/// columns.** `boardID == nil` if and only if `columnID == nil`.
///
/// It is asked after every operation that can touch either field, after each of
/// those operations taken on its own, and after undoing each of them — because
/// the way an invariant like this rots is not that somebody breaks it head-on,
/// it is that one path out of twenty forgets it, or that an undo puts back a
/// half-placement the forward path never produced.
///
/// The codes ride along in the same checks. A code is a label a person may have
/// pasted into a commit message, so no operation that moves a card may change
/// it, and no two cards may ever carry the same one.
@MainActor
@Suite struct PlacementInvariantTests {
    private static func uuid(_ a: UInt8, _ b: UInt8, _ n: UInt8) -> UUID {
        UUID(uuid: (a, b, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, n))
    }

    private static func column(_ n: UInt8, _ name: String) -> BoardColumn {
        BoardColumn(id: uuid(0xC0, 0x1F, n), name: name, short: name, dot: .hex(0xA8A29A))
    }

    private static let alphaTodo = column(1, "To do")
    private static let alphaDoing = column(2, "Doing")
    private static let alphaDone = column(3, "Shipped")
    private static let betaQueue = column(4, "Queue")
    private static let betaDone = column(5, "Closed")

    private static let alphaID = uuid(0xB0, 0x1E, 1)
    private static let betaID = uuid(0xB0, 0x1E, 2)

    private static let alpha = Board(
        id: alphaID, name: "Alpha", dot: .accent, createdAt: TestBoard.at(90_000),
        columns: [alphaTodo, alphaDoing, alphaDone], codePrefix: "AL"
    )
    private static let beta = Board(
        id: betaID, name: "Beta", dot: .hex(0x1F6F63), createdAt: TestBoard.at(80_000),
        columns: [betaQueue, betaDone], codePrefix: "BE"
    )

    private static func taskID(_ n: UInt8) -> TaskItem.ID { uuid(0x7A, 0x5D, n) }

    private static let ready = taskID(1)      // Alpha / To do, with an outstanding sub-task
    private static let stray = taskID(2)      // Alpha / Doing — the column a delete removes
    private static let shipped = taskID(3)    // Alpha / Shipped, so `reopen` has something to do
    private static let filed = taskID(4)      // Alpha / To do, archived, so `unarchive` has something
    private static let onBeta = taskID(5)     // Beta / Queue
    private static let captured = taskID(6)   // unfiled
    private static let spare = taskID(7)      // Alpha / To do, deleted by nothing else

    private static func task(
        _ id: TaskItem.ID, _ code: String, _ placement: TaskPlacement,
        subtasks: [SubTask] = [], archived: Bool = false, at seconds: Int
    ) -> TaskItem {
        var task = TaskItem(
            id: id, code: code, title: "Card \(code)", subtasks: subtasks,
            activity: [ActivityEntry(.created, when: TestBoard.at(seconds))],
            createdAt: TestBoard.at(seconds), updatedAt: TestBoard.at(seconds)
        )
        task.placement = placement
        if archived { task.archivedAt = TestBoard.at(seconds / 2) }
        return task
    }

    private static func tasks() -> [TaskItem] {
        [
            task(ready, "AL-140", .column(board: alphaID, column: alphaTodo.id),
                 subtasks: [SubTask(text: "Write it", done: true), SubTask(text: "Test it")], at: 10_000),
            task(stray, "AL-141", .column(board: alphaID, column: alphaDoing.id), at: 9_000),
            task(shipped, "AL-142", .column(board: alphaID, column: alphaDone.id), at: 8_000),
            task(filed, "AL-143", .column(board: alphaID, column: alphaTodo.id), archived: true, at: 7_000),
            task(onBeta, "BE-144", .column(board: betaID, column: betaQueue.id), at: 6_000),
            task(captured, "IN-145", .inbox, at: 5_000),
            task(spare, "AL-146", .column(board: alphaID, column: alphaTodo.id), at: 4_000),
        ]
    }

    private static func store(file: BoardFile? = nil) -> BoardStore {
        let store = BoardStore(
            tasks: tasks(), boards: [alpha, beta], activeBoardID: alphaID, labels: LabelDef.seed,
            accentTheme: .ember, nextSerial: BoardSnapshot.baseSerial + 7, file: file
        )
        // The pager starts on a real column of the active board, so the phone's
        // "add here" is a board placement rather than falling through to the Inbox.
        store.mobileColumnID = alphaDoing.id
        return store
    }

    private static func undoing() -> (store: BoardStore, undo: RecordingUndoManager) {
        let undo = RecordingUndoManager()
        undo.groupsByEvent = false
        let store = store()
        store.undoManager = undo
        return (store, undo)
    }

    private func board(_ store: BoardStore) -> BoardMutation {
        BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash)
    }

    // MARK: The property

    /// Every clause of the invariant, plus the two derived lists that would
    /// disagree with it if a card were placed in a way nothing can draw.
    private func expectInvariant(_ store: BoardStore, _ label: String) {
        var seen: Set<TaskItem.ID> = []
        var codes: Set<String> = []
        for task in store.tasks {
            #expect(seen.insert(task.id).inserted, "\(label): \(task.code) is on the board twice")
            #expect(codes.insert(task.code).inserted, "\(label): two cards are both called \(task.code)")
            #expect((task.boardID == nil) == (task.columnID == nil),
                    "\(label): \(task.code) has half a placement")
            #expect(task.isUnfiled == (task.boardID == nil),
                    "\(label): \(task.code) disagrees with itself about being unfiled")
            guard let boardID = task.boardID, let columnID = task.columnID else { continue }
            #expect(store.board(id: boardID)?.column(id: columnID) != nil,
                    "\(label): \(task.code) names a column its own board has not got")
            // Column ids are unique across boards, so the column alone has to
            // resolve to the same board the card claims.
            #expect(store.board(ofColumn: columnID)?.id == boardID,
                    "\(label): \(task.code) is on a board that is not the one holding its column")
        }

        // The Inbox is exactly the cards on no board — not a list kept beside them.
        let unfiled = Set(store.tasks.filter { $0.isUnfiled && !$0.isArchived }.map(\.id))
        #expect(Set(store.inboxTasks.map(\.id)) == unfiled, "\(label): the Inbox list has drifted")
        #expect(store.inboxCount == unfiled.count, "\(label): the Inbox count has drifted")
        for board in store.boards {
            let mine = store.tasks.count(where: { $0.boardID == board.id && !$0.isArchived })
            #expect(store.taskCount(for: board.id) == mine, "\(label): \(board.name)'s count has drifted")
        }
    }

    /// No card that was already there has been renumbered.
    private func expectCodesUnchanged(
        _ store: BoardStore, from minted: [TaskItem.ID: String], _ label: String
    ) {
        for task in store.tasks {
            guard let original = minted[task.id] else { continue }
            #expect(task.code == original, "\(label): \(original) was renumbered to \(task.code)")
        }
    }

    /// Every mutation that can touch a placement, or that changes the boards a
    /// placement is checked against. Each one changes the board it is handed,
    /// and each one registers an undo step.
    private var mutations: [(name: String, run: (BoardStore) -> Void)] {
        [
            ("addTask onto a board", { $0.addTask(to: Self.alphaTodo.id, title: "Filed straight away") }),
            ("addTask into the Inbox", { $0.addTask(to: .inbox, title: "Captured") }),
            ("addTaskToCurrentMobileColumn", { $0.selectTab(.board); $0.addTaskToCurrentMobileColumn() }),
            ("quickCapture", { $0.quickCapture() }),
            ("commitDraft", { store in
                store.beginAdding(in: .column(board: Self.betaID, column: Self.betaQueue.id))
                store.draft = "Composed"
                store.commitDraft()
            }),
            ("file onto a board and a column", { $0.file(Self.captured, onto: Self.betaID, column: Self.betaDone.id) }),
            ("file onto a board", { $0.file(Self.captured, onto: Self.betaID) }),
            ("unfile", { $0.unfile(Self.ready) }),
            ("move between columns", { $0.move(Self.ready, to: Self.alphaDoing.id) }),
            ("move between boards", { $0.move(Self.onBeta, to: Self.alphaDone.id) }),
            ("move to the Inbox", { $0.move(Self.onBeta, to: .inbox) }),
            ("complete", { $0.complete(Self.ready) }),
            ("reopen", { $0.reopen(Self.shipped) }),
            ("archive", { $0.archive(Self.spare) }),
            ("unarchive", { $0.unarchive(Self.filed) }),
            ("deleteTask", { $0.deleteTask(Self.spare) }),
            ("deleteColumn", { $0.deleteColumn(Self.alphaDoing.id) }),
            ("createBoard", { $0.createBoard(named: "Gamma") }),
            ("renameBoard", { $0.renameBoard(Self.betaID, to: "Support") }),
            ("recolorBoard", { $0.recolorBoard(Self.betaID, to: .accent) }),
            ("moveBoard", { $0.moveBoard(fromOffsets: [1], toOffset: 0) }),
            ("deleteBoard", { $0.deleteBoard(Self.betaID) }),
        ]
    }

    @Test func theInvariantHoldsAfterEachOperationTakenOnItsOwn() {
        for mutation in mutations {
            let store = Self.store()
            let minted = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.id, $0.code) })
            let before = board(store)
            expectInvariant(store, "before \(mutation.name)")

            mutation.run(store)
            #expect(board(store) != before, "\(mutation.name) changed nothing — the probe is wrong")
            expectInvariant(store, "after \(mutation.name)")
            expectCodesUnchanged(store, from: minted, "after \(mutation.name)")
        }
    }

    @Test func theInvariantHoldsAfterEveryOperationInOneLongSequence() {
        let store = Self.store()
        let minted = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.id, $0.code) })
        for mutation in mutations {
            mutation.run(store)
            expectInvariant(store, "in sequence, after \(mutation.name)")
            expectCodesUnchanged(store, from: minted, "in sequence, after \(mutation.name)")
        }
        // The sequence really did move the board about: the two boards it
        // started with are down to one, and cards have been through the Inbox.
        #expect(store.boards.map(\.name) == ["Alpha", "Gamma"])
        #expect(store.inboxCount > 0)
    }

    /// The undo half, which is where a placement invariant is likeliest to rot:
    /// a forward path that is careful and a restore that puts back whatever it
    /// happens to be holding.
    @Test func undoingEveryOperationWalksTheInvariantBackToWhereItStarted() {
        let (store, undo) = Self.undoing()
        let minted = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.id, $0.code) })
        let original = board(store)

        for mutation in mutations {
            step(undo) { mutation.run(store) }
            #expect(undo.undoActionName != "", "\(mutation.name) registered no undo step")
        }

        var undone = 0
        while undo.canUndo {
            undo.undo()
            undone += 1
            expectInvariant(store, "after undo #\(undone)")
            expectCodesUnchanged(store, from: minted, "after undo #\(undone)")
        }
        #expect(undone == mutations.count)
        #expect(board(store) == original, "draining the stack did not land back on the board it started from")
    }

    @Test func eachOperationUndoneOnItsOwnLeavesTheInvariantAndThePlacementsExact() {
        for mutation in mutations {
            let (store, undo) = Self.undoing()
            let placements = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.id, $0.placement) })
            let before = board(store)

            step(undo) { mutation.run(store) }
            undo.undo()

            expectInvariant(store, "after undoing \(mutation.name)")
            #expect(board(store) == before, "\(mutation.name) did not undo cleanly")
            for task in store.tasks {
                #expect(task.placement == placements[task.id],
                        "\(mutation.name): \(task.code) came back somewhere else")
            }
        }
    }

    // MARK: What the invariant is for

    @Test func deletingABoardUnfilesItsCardsAndKeepsEveryOneOfThem() {
        let (store, undo) = Self.undoing()
        let codes = store.tasks.map(\.code)
        let onAlpha = store.tasks.filter { $0.boardID == Self.alphaID }.map(\.id)

        step(undo) { store.deleteBoard(Self.alphaID) }

        #expect(store.tasks.map(\.code) == codes, "a card went missing with the board")
        for id in onAlpha {
            #expect(store[id]?.isUnfiled == true)
            #expect(store[id]?.columnID == nil)
            #expect(store[id]?.activity.first?.kind == .unfiled)
        }
        expectInvariant(store, "after deleting a board")

        undo.undo()
        #expect(store[Self.ready]?.placement == .column(board: Self.alphaID, column: Self.alphaTodo.id))
        #expect(store[Self.shipped]?.placement == .column(board: Self.alphaID, column: Self.alphaDone.id))
        expectInvariant(store, "after undoing a board delete")
    }

    /// `file` is one of the two doors the invariant is kept behind, so it has
    /// to refuse a pair `TaskPlacement` can spell but no board can draw: this
    /// board, that board's column.
    @Test func filingOntoABoardWithAnotherBoardsColumnIsRefusedRatherThanStored() {
        let store = Self.store()
        store.file(Self.captured, onto: Self.alphaID, column: Self.betaQueue.id)
        #expect(store[Self.captured]?.isUnfiled == true, "the card was filed somewhere nothing can draw")
        expectInvariant(store, "after filing onto a board with another board's column")

        // A board that is not there at all is the same answer.
        store.file(Self.captured, onto: UUID(), column: Self.alphaTodo.id)
        #expect(store[Self.captured]?.isUnfiled == true)
        store.file(Self.captured, onto: UUID())
        #expect(store[Self.captured]?.isUnfiled == true)
        expectInvariant(store, "after filing onto a board that is not there")

        // And the same call naming a column the board really has does move it,
        // so the refusals above are not a method that never works.
        store.file(Self.captured, onto: Self.alphaID, column: Self.alphaTodo.id)
        #expect(store[Self.captured]?.placement == .column(board: Self.alphaID, column: Self.alphaTodo.id))
        expectInvariant(store, "after a filing that makes sense")
    }

    /// The same pair at the other two doors. `file` is not the only entry point
    /// a placement arrives at from outside — `move` takes one and so does
    /// `addTask` — and the two answer it differently on purpose.
    @Test func movingAndAddingBothRefuseAPlacementNoBoardCanDraw() {
        let store = Self.store()
        let nowhere = TaskPlacement.column(board: Self.alphaID, column: Self.betaQueue.id)
        #expect(store.isPlaceable(nowhere) == false)
        #expect(store.isPlaceable(.column(board: Self.alphaID, column: Self.alphaTodo.id)))
        #expect(store.isPlaceable(.inbox), "the Inbox always exists")

        // `move` leaves the card where it is: it is already somewhere real.
        let filed = store[Self.ready]?.placement
        store.move(Self.ready, to: nowhere)
        #expect(store[Self.ready]?.placement == filed, "a card moved somewhere nothing can draw")
        store.move(Self.captured, to: .column(board: Self.betaID, column: Self.alphaDone.id))
        #expect(store[Self.captured]?.isUnfiled == true)
        expectInvariant(store, "after moving to a placement no board can draw")

        // `addTask` makes the card anyway, in the Inbox. It returns a
        // non-optional id and the caller asked for a card, so losing it would
        // be worse than landing it somewhere findable — and the code is minted
        // from where it actually landed.
        let made = store.addTask(to: nowhere, title: "Aimed at nowhere")
        #expect(store[made]?.isUnfiled == true)
        #expect(store[made]?.code == "IN-147", "a card in the Inbox took a board's prefix")
        expectInvariant(store, "after adding to a placement no board can draw")
    }

    /// And the bulk move, which is a fourth door and the only one that does not
    /// go through the singular `move`: it calls `performMove` directly so the
    /// whole selection lands in one undo step, and `performMove` does not check
    /// the pairing. Without a guard of its own a selection is written "on board
    /// A, in board B's column" — the one shape the invariant forbids, and the
    /// three tests above would all still pass.
    @Test func theBulkMoveRefusesThePlacementItsSingularSiblingRefuses() {
        let (store, undo) = Self.undoing()
        let nowhere = TaskPlacement.column(board: Self.alphaID, column: Self.betaQueue.id)
        #expect(store.isPlaceable(nowhere) == false)

        let before = store.tasks
        step(undo) { store.move([Self.ready, Self.spare, Self.captured], to: nowhere) }
        #expect(store.tasks == before, "a selection moved somewhere no board can draw")
        // And no step for it either: a ⌘Z that undoes nothing reads as broken.
        #expect(undo.actionNames.isEmpty)
        expectInvariant(store, "after a bulk move to a placement no board can draw")

        // The same call naming a column the board really has does move them, so
        // the refusal above is not a method that never works.
        let real = TaskPlacement.column(board: Self.alphaID, column: Self.alphaDoing.id)
        step(undo) { store.move([Self.ready, Self.spare], to: real) }
        #expect(undo.actionNames == ["Move Tasks"])
        #expect(store[Self.ready]?.placement == real)
        #expect(store[Self.spare]?.placement == real)
        expectInvariant(store, "after a bulk move that makes sense")
    }

    /// A card that once lived on another board still names that board's columns
    /// in its own history. `reopen` reads that history against the card's *own*
    /// board's columns, so an id it recognises from somewhere else cannot pull
    /// it onto a board the user was not looking at and did not ask about.
    @Test func reopeningACardKeepsItOnItsOwnBoard() {
        var wanderer = Self.task(Self.spare, "AL-146",
                                 .column(board: Self.alphaID, column: Self.alphaDone.id), at: 4_000)
        // Newest first, the way the store writes them: Beta's column is the
        // most recent move this card carries.
        wanderer.activity.insert(
            ActivityEntry(.moved(columnID: Self.betaQueue.id.uuidString, columnName: "Queue")),
            at: 0
        )
        let store = BoardStore(tasks: [wanderer], boards: [Self.alpha, Self.beta],
                               activeBoardID: Self.alphaID)
        #expect(store[Self.spare].map { store.isDone($0) } == true)

        store.reopen(Self.spare)
        #expect(store[Self.spare]?.boardID == Self.alphaID, "reopening carried the card to another board")
        // Nothing in Alpha's history to go back to, so it starts Alpha's
        // workflow again rather than resolving Beta's id.
        #expect(store[Self.spare]?.columnID == Self.alphaTodo.id)
        expectInvariant(store, "after reopening a card whose history names another board")
    }

    /// The return journey has a record of its own. It is not a `.moved`: the
    /// Inbox is not a column, and its name is the app's rather than the user's,
    /// so there is no column name to store.
    @Test func aCardTakenBackToTheInboxSaysSoInItsOwnHistory() {
        let store = Self.store()
        let before = store[Self.ready]?.activity.count ?? 0

        store.unfile(Self.ready)
        #expect(store[Self.ready]?.activity.first?.kind == .unfiled)
        #expect(store[Self.ready]?.activity.count == before + 1)

        // Going back onto a board names the column, the way every move does.
        store.move(Self.ready, to: Self.alphaDoing.id)
        #expect(store[Self.ready]?.activity.first?.kind
                == .moved(columnID: Self.alphaDoing.id.uuidString, columnName: "Doing"))

        // Unfiling something that is already unfiled is not an event.
        let captured = store[Self.captured]?.activity.count ?? 0
        store.unfile(Self.captured)
        #expect(store[Self.captured]?.activity.count == captured)
    }

    @Test func aCardWhoseBoardAndColumnDisagreeIsPlacedByItsColumn() {
        // The memberwise initialiser can spell what `TaskPlacement` cannot, and
        // decoding is where that arrives from. Alpha's id with Beta's column.
        let confused = TaskItem(
            id: Self.ready, code: "AL-140", boardID: Self.alphaID, columnID: Self.betaQueue.id,
            title: "Confused"
        )
        let store = BoardStore(
            tasks: [confused], boards: [Self.alpha, Self.beta], activeBoardID: Self.alphaID
        )
        #expect(store[Self.ready]?.boardID == Self.betaID)
        expectInvariant(store, "adopted with a board and a column that disagree")
    }

    /// Two cards under one id is something a file can carry and nothing on the
    /// board can address: `self[id]`, `deleteTask`, `move` and every editing
    /// session reach only the first, so the second would be drawn, addressed by
    /// nothing, and impossible to delete. First one wins — the same rule that
    /// settles two boards claiming one column.
    @Test func aFileWithTwoCardsUnderOneIdLoadsWithTheSecondDropped() throws {
        let temp = TempBoard()
        let store = Self.store(file: temp.file)
        store.saveNow()

        var object = try #require(try JSONSerialization.jsonObject(with: try temp.bytes()) as? [String: Any])
        var tasks = try #require(object["tasks"] as? [[String: Any]])
        var twin = try #require(tasks.first { $0["code"] as? String == "AL-140" })
        twin["code"] = "AL-999"
        twin["title"] = "The twin"
        tasks.append(twin)
        object["tasks"] = tasks
        try temp.put(try JSONSerialization.data(withJSONObject: object))

        let relaunched = BoardStore.restored(file: temp.file)
        #expect(relaunched.tasks.count == store.tasks.count)
        #expect(relaunched.tasks.filter { $0.id == Self.ready }.count == 1)
        #expect(relaunched[Self.ready]?.title == "Card AL-140", "the later card won")
        #expect(relaunched.tasks.contains { $0.code == "AL-999" } == false)
        expectInvariant(relaunched, "adopted from a file with two cards under one id")
    }

    // MARK: Codes

    @Test func aCodeSurvivesEveryJourneyACardCanTake() {
        let (store, undo) = Self.undoing()
        var minted: TaskItem.ID?
        step(undo) { minted = store.addTask(to: .inbox, title: "Captured") }
        guard let id = minted else {
            Issue.record("the capture was not made")
            return
        }
        #expect(store[id]?.code == "IN-147")

        func expectStillCalled(_ what: String, _ label: String) {
            #expect(store[id]?.code == what, "renumbered by \(label)")
        }

        step(undo) { store.file(id, onto: Self.alphaID, column: Self.alphaTodo.id) }
        expectStillCalled("IN-147", "filing onto a board")
        step(undo) { store.move(id, to: Self.betaQueue.id) }
        expectStillCalled("IN-147", "moving to another board")
        step(undo) { store.complete(id) }
        expectStillCalled("IN-147", "completing")
        step(undo) { store.archive(id) }
        expectStillCalled("IN-147", "archiving")
        step(undo) { store.unarchive(id) }
        expectStillCalled("IN-147", "restoring")
        step(undo) { store.deleteBoard(Self.betaID) }
        expectStillCalled("IN-147", "deleting the board it was on")
        #expect(store[id]?.isUnfiled == true)
        undo.undo()
        expectStillCalled("IN-147", "undoing the board delete")
    }

    /// The prefix is the *destination's*, not the board the user is looking at
    /// and not the board the composer was opened from.
    @Test func aCodeIsMintedFromWhereTheCardIsGoingRatherThanWhereTheUserIs() {
        let store = Self.store()
        #expect(store.activeBoardID == Self.alphaID)

        let ontoBeta = store.addTask(to: Self.betaQueue.id, title: "On the other board")
        #expect(store[ontoBeta]?.code == "BE-147")

        store.selectBoard(Self.betaID)
        let ontoAlpha = store.addTask(to: Self.alphaTodo.id, title: "Back on the first one")
        #expect(store[ontoAlpha]?.code == "AL-148")

        // And the Inbox, which is nobody's board, has a prefix of its own.
        let unfiled = store.addTask(to: .inbox, title: "Captured")
        #expect(store[unfiled]?.code == "IN-149")
        #expect(store[unfiled]?.isUnfiled == true)
    }

    @Test func aRenamedBoardGoesOnMintingUnderThePrefixItsCardsAlreadyCarry() {
        let store = Self.store()
        store.renameBoard(Self.alphaID, to: "Something else entirely")
        let id = store.addTask(to: Self.alphaTodo.id, title: "After the rename")
        #expect(store[id]?.code == "AL-147")
        #expect(store[Self.ready]?.code == "AL-140")
    }
}
