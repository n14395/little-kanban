import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Simple_Kanban

/// Getting a board out of the app and back in.
///
/// The round trip is the easy half — `BoardSnapshot` was already `Codable`. The
/// half worth this many probes is the *merge*: an import folds a second board
/// into the one already here, and every way of getting that wrong destroys work
/// without saying anything. Replacing instead of merging loses the board being
/// imported into; resolving an id collision by overwriting loses one card and
/// leaves no trace that there ever were two.
@MainActor
@Suite struct ExportImportTests {
    /// A board with every field on it filled in, for the round trip. Two boards,
    /// an unfiled card, a filed-away one, every activity kind, sub-tasks in both
    /// states, both due dates, every priority and a serial that is not the base.
    private var everything: BoardSnapshot {
        var loaded = TestBoard.tasks[1]
        loaded.activity = TestBoard.everyActivityKind.enumerated().map { index, kind in
            ActivityEntry(id: TestBoard.entryID(UInt8(140 + index)), kind, when: TestBoard.at(index * 60))
        }
        var filed = TestBoard.tasks[5]
        filed.archivedAt = TestBoard.at(90)
        let tasks = TestBoard.tasks(on: SeedData.defaultBoard)
        return BoardSnapshot(
            tasks: [loaded, filed] + tasks[2..<5] + [tasks[0]],
            boards: TestBoard.boards, labels: LabelDef.seed, nextSerial: 187,
            accentTheme: .indigo, activeBoardID: TestBoard.support.id
        )
    }

    private func expectSame(_ read: BoardSnapshot, _ written: BoardSnapshot, _ what: Comment) {
        #expect(read.version == written.version, what)
        #expect(read.tasks == written.tasks, what)
        #expect(read.boards == written.boards, what)
        #expect(read.labels == written.labels, what)
        #expect(read.nextSerial == written.nextSerial, what)
        #expect(read.accentTheme == written.accentTheme, what)
        #expect(read.activeBoardID == written.activeBoardID, what)
    }

    // MARK: The document

    @Test func everyFieldSurvivesTheRoundTripThroughAnExportedFile() throws {
        let written = everything
        let read = try BoardSnapshot.decoding(try written.encoded())
        expectSame(read, written, "a field went missing between the exporter and the importer")
        // Field by field is not enough on its own: a field added to the struct
        // and forgotten here would pass. The bytes have to agree too.
        #expect(try read.encoded() == written.encoded())
    }

    @Test func theDocumentIsTheSameFormatTheAppAlreadyWrites() throws {
        let temp = TempBoard()
        let snapshot = everything
        try temp.file.write(snapshot, generation: temp.file.nextWriteGeneration())
        // One format, not two: a `board.json` copied off another machine is a
        // file this can import, and an export is a file that can be dropped in
        // as a board file.
        #expect(try temp.bytes() == snapshot.encoded())
        expectSame(try BoardSnapshot.decoding(try temp.bytes()), snapshot, "an export and a board file have drifted")
    }

    /// What the exporter is handed and what the app saves have to be the same
    /// board. They are assembled in two different places, and an export built
    /// from anything narrower — the active board, the visible tasks — would
    /// produce a file that reads back as a board with things missing.
    @MainActor
    @Test func theExportedSnapshotIsExactlyWhatTheAppWouldSave() throws {
        let temp = TempBoard()
        let store = TestBoard.store(
            tasks: TestBoard.tasks(on: SeedData.defaultBoard, archiving: [TestBoard.palette: 300]),
            boards: TestBoard.boards, file: temp.file
        )
        store.selectSurface(.inbox)
        store.query = "sync"
        store.saveNow()

        #expect(try store.exportedSnapshot.encoded() == temp.bytes())
        #expect(store.boardFileURL == temp.file.url)
        // Including the cards the surface is currently hiding.
        #expect(store.exportedSnapshot.tasks.count == 6)
        #expect(store.exportedSnapshot.tasks.contains { $0.isArchived })
        #expect(store.exportedSnapshot.boards.count == 2)
    }

    @Test func anExportedBoardLandsWholeInAnEmptyOne() throws {
        let store = BoardStore(tasks: [], boards: [], labels: [], nextSerial: BoardSnapshot.baseSerial)
        let summary = store.importBoard(try BoardSnapshot.decoding(try everything.encoded()))

        #expect(summary.tasksAdded == everything.tasks.count)
        #expect(summary.boardsAdded == everything.boards.count)
        #expect(summary.labelsAdded == LabelDef.seed.count)
        #expect(store.tasks.map(\.id) == everything.tasks.map(\.id))
        #expect(store.tasks.map(\.code) == everything.tasks.map(\.code))
        #expect(store.boards == everything.boards)
        #expect(store.labels == LabelDef.seed)
        #expect(store.tasks.first { $0.id == TestBoard.palette }?.archivedAt == TestBoard.at(90))
        #expect(store.tasks.first { $0.id == TestBoard.dragDrop }?.activity.map(\.kind) == TestBoard.everyActivityKind)
    }

    @Test func aCorruptFileIsRefusedRatherThanImportedAsAnEmptyBoard() {
        #expect(throws: BoardFileError.unreadable) {
            try BoardSnapshot.decoding(Data("half a file".utf8))
        }
    }

    @Test func aFileFromANewerBuildIsRefusedByVersion() {
        let future = BoardSnapshot.currentVersion + 1
        let bytes = Data("{\"version\":\(future),\"tasks\":[],\"labels\":[],\"nextSerial\":100,\"accentTheme\":\"ember\"}".utf8)
        #expect(throws: BoardFileError.newerVersion(future)) { try BoardSnapshot.decoding(bytes) }
    }

    @Test func aFileFromAnOlderBuildIsMigratedOnTheWayIn() throws {
        let old = try BoardSnapshot.decoding(try Fixture.data("board-v2"))
        #expect(old.version == BoardSnapshot.currentVersion)
        let store = TestBoard.store(tasks: [], boards: [])
        let summary = store.importBoard(old)
        #expect(summary.tasksAdded == old.tasks.count)
        #expect(store.tasks.isEmpty == false)
    }

    // MARK: Merging, not replacing

    @Test func importingIntoANonEmptyBoardKeepsBothSetsOfTasks() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let mine = store.tasks

        let summary = store.importBoard(ForeignBoard.snapshot())

        #expect(summary.tasksAdded == 3)
        #expect(summary.tasksCopied == 0)
        // Everything that was here is still here, byte for byte and in order.
        #expect(Array(store.tasks.prefix(mine.count)) == mine)
        // …and everything that arrived is here too.
        #expect(store.tasks.count == mine.count + 3)
        #expect(store.tasks.map(\.title).contains("Rewrite the brief"))
        #expect(store.tasks.map(\.title).contains("Hero image"))
        #expect(store.tasks.map(\.title).contains("Somebody's stray thought"))
    }

    @Test func theImportedBoardArrivesBesideTheOneAlreadyHere() {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        store.importBoard(ForeignBoard.snapshot())

        #expect(store.boards.map(\.name) == [SeedData.defaultBoard.name, "Website refresh"])
        #expect(store.boards.first == SeedData.defaultBoard)
        let arrived = store.boards.last
        #expect(arrived?.codePrefix == "WR")
        #expect(arrived?.columns.map(\.name) == ["Triage", "Shipped"])
        // The arriving board's cards are on the arriving board.
        #expect(store.tasks.first { $0.title == "Rewrite the brief" }?.boardID == ForeignBoard.board.id)
        #expect(store.tasks.first { $0.title == "Somebody's stray thought" }?.isUnfiled == true)
    }

    /// The active board is where the user is looking, and the accent is a
    /// preference they set on this machine. Neither is the arriving file's to
    /// change, and both are in the document the file carries.
    @Test func theActiveBoardAndTheAccentAreNotTheFilesToChange() {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let wasActive = store.activeBoardID
        let wasAccent = store.accentTheme
        #expect(ForeignBoard.snapshot().activeBoardID != wasActive)
        #expect(ForeignBoard.snapshot().accentTheme != wasAccent)

        store.importBoard(ForeignBoard.snapshot())
        #expect(store.activeBoardID == wasActive)
        #expect(store.accentTheme == wasAccent)
    }

    /// The same claim of `merging` itself rather than of the store.
    ///
    /// `adoptContent` takes neither field off the snapshot it is handed, so a
    /// merge that copied them across is invisible from outside today — and a
    /// trap for the first caller that writes a merged snapshot straight to disk
    /// or hands it anywhere else.
    @Test func theMergeItselfLeavesTheAccentAndTheActiveBoardAlone() {
        let mine = BoardSnapshot(
            tasks: TestBoard.tasks(on: SeedData.defaultBoard), boards: [SeedData.defaultBoard],
            labels: LabelDef.seed, nextSerial: 100, accentTheme: .ember,
            activeBoardID: SeedData.defaultBoard.id
        )
        let incoming = ForeignBoard.snapshot(includingCollision: true)
        #expect(incoming.accentTheme != mine.accentTheme)
        #expect(incoming.activeBoardID != mine.activeBoardID)

        let merged = mine.merging(incoming).snapshot
        #expect(merged.accentTheme == mine.accentTheme)
        #expect(merged.activeBoardID == mine.activeBoardID)
        #expect(merged.version == BoardSnapshot.currentVersion)
    }

    @Test func theLabelVocabularyGrowsWithoutBeingRewritten() {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let summary = store.importBoard(ForeignBoard.snapshot())

        #expect(summary.labelsAdded == 1)
        #expect(store.labels.map(\.key) == LabelDef.seed.map(\.key) + ["seo"])
        // The arriving file calls `design` something else and colours it
        // differently. Taking its word for it would rename every chip on the
        // importing board's cards.
        #expect(store.label(forKey: "design") == LabelDef.seed[0])
        #expect(store.label(forKey: "seo")?.name == "SEO")
        // Every key any task now refers to resolves.
        let used = Set(store.tasks.flatMap(\.labelKeys))
        #expect(used.allSatisfy { store.label(forKey: $0) != nil })
    }

    // MARK: The collision

    /// The case item 3.7 moved ids to UUIDs for. Two installs can still mint the
    /// same id — one board copied and then edited on both machines is the
    /// ordinary way — and picking a winner throws a card away silently.
    @Test func aCollidingTaskIdKeepsBothCardsRatherThanOverwriting() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let mine = try #require(store[TestBoard.cafe])

        let summary = store.importBoard(ForeignBoard.snapshot(includingCollision: true))

        #expect(summary.tasksCopied == 1)
        #expect(summary.tasksAdded == 3)
        #expect(store.tasks.count == 6 + 4)

        // The card that was here is untouched, under the id it has always had.
        #expect(store[TestBoard.cafe] == mine)
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")

        // The one that arrived is here too, under an id of its own.
        let arrived = try #require(store.tasks.first { $0.title == "A different card entirely" })
        #expect(arrived.id != TestBoard.cafe)
        #expect(arrived.note == "Nothing to do with a café.")
        #expect(arrived.priority == .high)
        #expect(arrived.boardID == ForeignBoard.board.id)

        // Two cards, two ids, and nothing addressed by an id that names two
        // things — which is the state `BoardStore.placed` drops the second of.
        #expect(Set(store.tasks.map(\.id)).count == store.tasks.count)
    }

    @Test func aCollisionDoesNotHandTwoCardsOneCode() {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        store.importBoard(ForeignBoard.snapshot(includingCollision: true))
        #expect(Set(store.tasks.map(\.code)).count == store.tasks.count)
        // A code is a label somebody may have pasted into a commit message, so
        // nothing already here is renumbered to make room.
        #expect(store.tasks.prefix(6).map(\.code) == TestBoard.tasks.map(\.code))
    }

    /// The same file twice is what a user does when they are not sure the first
    /// one worked. It must not double the board, and it must not leave a ⌘Z
    /// behind that does nothing.
    @Test func importingTheSameFileTwiceChangesNothingTheSecondTime() async throws {
        let temp = TempBoard()
        let (store, undo) = TestBoard.undoing(tasks: TestBoard.tasks(on: SeedData.defaultBoard), file: temp.file)

        step(undo) { store.importBoard(ForeignBoard.snapshot()) }
        let afterFirst = store.tasks
        store.saveNow()
        let bytes = try temp.bytes()
        let writes = temp.file.writeCount

        var summary = BoardImportSummary()
        step(undo) { summary = store.importBoard(ForeignBoard.snapshot()) }

        #expect(summary.changedAnything == false)
        #expect(summary.tasksUnchanged == 3)
        #expect(store.tasks == afterFirst)
        #expect(undo.undoActionName == "", "a no-op import left a ⌘Z that undoes nothing")

        try await Task.sleep(for: .milliseconds(900))
        // Not even a write: an import that changed nothing has nothing to say
        // to the disk, and a rewrite of identical bytes is invisible in the
        // file and visible in the backup rotation.
        #expect(temp.file.writeCount == writes, "a no-op import wrote the board again")
        #expect(try temp.bytes() == bytes)
    }

    /// The same claim for the file that collided.
    ///
    /// A colliding card is kept under a *fresh* id, so on a second import the
    /// arriving card no longer matches anything by id and the "already here,
    /// byte for byte" test that makes a re-import free cannot see it. Left
    /// unhandled, every re-import of that file grows the board by another copy
    /// of the same card — and a user who is not sure the first import worked
    /// re-importing is exactly how this is found.
    @Test func reImportingAFileThatCollidedDoesNotGrowTheBoardAgain() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        store.importBoard(ForeignBoard.snapshot(includingCollision: true))
        let afterFirst = store.tasks

        let summary = store.importBoard(ForeignBoard.snapshot(includingCollision: true))

        #expect(store.tasks.count == afterFirst.count,
                "a third copy of the collided card arrived: \(store.tasks.filter { $0.title == "A different card entirely" }.count) of it now")
        #expect(summary.changedAnything == false)
        #expect(store.tasks == afterFirst)
    }

    /// A *code* collision is not an id collision. Two installs mint `NW-122`
    /// as a matter of course, because a code is minted per board from a
    /// per-file counter — so an import has to re-mint the arriving one rather
    /// than leaving two cards answering to the same label.
    @Test func aCodeAlreadyOnTheBoardIsRemintedOnTheArrivingCard() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        store.importBoard(ForeignBoard.snapshot(includingCodeCollision: true))

        #expect(Set(store.tasks.map(\.code)).count == store.tasks.count,
                "two cards answer to one code: \(store.tasks.map(\.code).sorted())")
        // The card already here keeps the code somebody may have pasted into a
        // commit message; the arriving one takes a new one.
        #expect(store[TestBoard.cafe]?.code == "NW-122")
        let arrived = try #require(store.tasks.first { $0.title == "Their NW-122" })
        #expect(arrived.code != "NW-122")
        #expect(arrived.code.hasPrefix("WR-"), "the new code is minted from the board it landed on")
    }

    /// The counter has to end up above both files' — otherwise the next task
    /// the user adds on the arriving board is minted a code the import has just
    /// brought in.
    ///
    /// The importing board's own counter says nothing about the arriving one:
    /// it is at 100 here, which mints `-140`, and `WR-140` came in with the
    /// file. Re-minting inside the merge is not enough on its own, because the
    /// serial it climbs through has to be *kept*.
    @Test func theSerialClimbsAboveBothFilesSoTheNextCodeIsFree() throws {
        let temp = TempBoard()
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard), file: temp.file)
        let incoming = ForeignBoard.snapshot(includingCodeCollision: true)
        store.importBoard(incoming)
        let taken = Set(store.tasks.map(\.code))

        // On the arriving board, whose prefix is the one the imported codes
        // were minted under.
        let id = store.addTask(
            to: .column(board: ForeignBoard.board.id, column: ForeignBoard.triage.id),
            title: "Minted after the import"
        )
        let minted = try #require(store[id]?.code)
        #expect(!taken.contains(minted), "\(minted) was already on the board")
        #expect(Set(store.tasks.map(\.code)).count == store.tasks.count)

        // And the counter that says so is the one written down, so the next
        // session starts above the imported codes rather than back at them.
        store.saveNow()
        #expect(try temp.snapshot().nextSerial > incoming.nextSerial)
    }

    // MARK: What an import costs

    @Test func anImportIsOneUndoStepAndComesOffCleanly() throws {
        let (store, undo) = TestBoard.undoing(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let before = BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0, boards: store.boards)

        step(undo) { store.importBoard(ForeignBoard.snapshot(includingCollision: true)) }
        #expect(undo.undoActionName == "Import Board")

        undo.undo()
        let after = BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0, boards: store.boards)
        #expect(after == before)
    }

    @Test func anImportReachesTheDisk() async throws {
        let temp = TempBoard()
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard), file: temp.file)
        store.importBoard(ForeignBoard.snapshot())

        try await Task.sleep(for: .milliseconds(900))
        #expect(temp.file.writeCount == 1)
        #expect(try temp.snapshot().tasks.count == 9)
        #expect(try temp.snapshot().boards.count == 2)
    }

    // MARK: Ids that clash below the task level

    /// Column ids have to be unique across boards, because the store resolves a
    /// card's board from its column. A file arriving with a *new* board that
    /// reuses a column id already in use here would otherwise hand two boards
    /// one column and start drawing each other's cards.
    @Test func aColumnIdAlreadyInUseIsRemintedOnTheArrivingBoard() throws {
        var clashing = ForeignBoard.board
        clashing.columns = [
            BoardColumn(id: BoardColumn.backlog.id, name: "Their backlog", short: "Backlog",
                        dot: .hex(0xA8A29A), role: .backlog),
        ]
        var arriving = TaskItem(
            id: ForeignBoard.taskID(9), code: "WR-150", title: "On their backlog",
            createdAt: ForeignBoard.at(10), updatedAt: ForeignBoard.at(10)
        )
        arriving.placement = .column(board: clashing.id, column: BoardColumn.backlog.id)
        let incoming = BoardSnapshot(tasks: [arriving], boards: [clashing], labels: [],
                                     nextSerial: 200, accentTheme: .ember)

        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        store.importBoard(incoming)

        let theirs = try #require(store.boards.first { $0.id == clashing.id })
        let column = try #require(theirs.columns.first)
        #expect(column.id != BoardColumn.backlog.id, "two boards were handed one column")
        #expect(column.name == "Their backlog")
        // The card followed its column onto the right board.
        #expect(store[ForeignBoard.taskID(9)]?.placement == .column(board: clashing.id, column: column.id))
        // …and the importing board's own backlog still holds exactly its own cards.
        #expect(store.boardTasks(in: BoardColumn.backlog.id).map(\.id) == [TestBoard.dragDrop, TestBoard.cafe])
    }

    /// A column added to a board that is already here is folded in rather than
    /// replacing the arrangement the user made.
    @Test func aBoardAlreadyHereKeepsItsNameAndGainsOnlyMissingColumns() throws {
        var incomingBoard = SeedData.defaultBoard
        incomingBoard.name = "Renamed elsewhere"
        incomingBoard.codePrefix = "XX"
        incomingBoard.columns = [BoardColumn.backlog, TestBoard.queue]
        let incoming = BoardSnapshot(tasks: [], boards: [incomingBoard], labels: [],
                                     nextSerial: 200, accentTheme: .ember)

        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let summary = store.importBoard(incoming)

        let board = try #require(store.boards.first { $0.id == SeedData.defaultBoard.id })
        #expect(board.name == SeedData.defaultBoard.name)
        #expect(board.codePrefix == SeedData.defaultBoard.codePrefix)
        #expect(board.columns.map(\.name) == SeedData.defaultBoard.columns.map(\.name) + ["Queue"])
        #expect(summary.columnsAdded == 1)
        #expect(summary.boardsAdded == 0)
    }

    /// The invariant the whole model exists to keep, asked of a board that has
    /// just had a stranger's file folded into it — the one door into the store
    /// that does not go through a single-task mutation.
    @Test func everyCardIsStillUnfiledOrOnABoardInOneOfItsColumns() {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        var stray = ForeignBoard.tasks[0]
        stray.placement = .column(board: UUID(), column: UUID())
        var incoming = ForeignBoard.snapshot(includingCollision: true)
        incoming.tasks.append(stray)
        store.importBoard(incoming)

        for task in store.tasks {
            switch task.placement {
            case .inbox:
                #expect(task.boardID == nil && task.columnID == nil)
            case .column(let boardID, let columnID):
                let board = store.board(id: boardID)
                #expect(board != nil, "\(task.code) is on a board that does not exist")
                #expect(board?.column(id: columnID) != nil, "\(task.code) is in a column its board does not have")
            }
        }
        // The card whose column came from nowhere is in the Inbox rather than
        // dropped: it is still the user's.
        #expect(store.tasks.contains { $0.title == stray.title && $0.isUnfiled })
    }

    // MARK: Markdown

    @Test func theMarkdownExportReadsAsTheBoardLooks() {
        let snapshot = BoardSnapshot(
            tasks: TestBoard.tasks(on: SeedData.defaultBoard, archiving: [TestBoard.palette: 300]),
            boards: [SeedData.defaultBoard], labels: LabelDef.seed,
            nextSerial: 100, accentTheme: .ember
        )
        let markdown = BoardMarkdown.render(snapshot, today: TestBoard.dueDay)

        #expect(markdown.contains("## \(Board.inboxName)"))
        #expect(markdown.contains("## \(SeedData.defaultBoard.name)"))
        #expect(markdown.contains("### Backlog"))
        #expect(markdown.contains("## Archive"))
        // Every live card is in it, under its code.
        for task in snapshot.tasks where !task.isArchived {
            #expect(markdown.contains("`\(task.code)`"), "\(task.code) is missing from the export")
        }
        // Sub-tasks keep their state, and a label reads as its name rather than
        // its slug.
        #expect(markdown.contains("  - [x] Lift and shadow states"))
        #expect(markdown.contains("  - [ ] Column drop targets"))
        #expect(markdown.contains("Design"))
        #expect(markdown.contains("due 2026-08-20"))
        // A multi-line note stays one block quote.
        #expect(markdown.contains("  > Captured from the menu bar."))
    }

    /// An export is a moment rather than a thing: two exports of one board on
    /// different days are different files and must not collide.
    @Test func theExportIsNamedForTheDayItWasTaken() {
        let name = BoardTransferDocument.filename(on: TestBoard.dueDay)
        #expect(name.contains("2026-08-20"))
        #expect(name != BoardTransferDocument.filename(on: TestBoard.laterDay))
        #expect(!name.contains("/"))
    }

    @Test func markdownIsExportOnly() {
        // Lossy in one direction on purpose: ids, timestamps and activity are
        // all gone, so a round trip through it would quietly discard history.
        #expect(BoardMarkdownDocument.readableContentTypes.isEmpty)
        #expect(BoardTransferDocument.readableContentTypes.contains(.json))
    }

    // MARK: The declared type

    @Test func theBoardDocumentTypeMatchesWhatTheBundleDeclares() throws {
        let declared = try #require(
            Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]],
            "the test host declares no exported types at all"
        )
        let entry = try #require(
            declared.first { $0["UTTypeIdentifier"] as? String == UTType.simpleKanbanBoard.identifier },
            "\(UTType.simpleKanbanBoard.identifier) is used in code but not declared in project.yml"
        )
        // JSON rather than plain data: an exported board genuinely is JSON, and
        // saying so is what lets somebody open one in a text editor.
        #expect((entry["UTTypeConformsTo"] as? [String])?.contains(UTType.json.identifier) == true)
        #expect((entry["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] != nil,
                "the board type declares no file extension, so an exported file has none")
    }
}
