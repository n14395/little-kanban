import Foundation
import Testing
@testable import Simple_Kanban

/// C6's first half, asked of the store rather than read out of it: every public
/// method that changes board data has to reach the disk.
///
/// One store per mutation, each with a file of its own, so a save that never
/// happened cannot hide behind a neighbour's — the debounce coalesces within a
/// file and only within a file. They all wait out one interval together, which
/// is why this costs a single sleep rather than one per mutation.
@MainActor
@Suite struct SaveContractTests {
    private struct Case {
        var label: String
        var board: TempBoard
        var store: BoardStore
    }

    @Test func everyPublicBoardMutationSchedulesASave() async throws {
        var cases: [Case] = []
        func mutate(
            _ label: String, tasks: [TaskItem] = TestBoard.tasks,
            boards: [Board] = SeedData.boards, _ body: (BoardStore) -> Void
        ) {
            let board = TempBoard()
            let store = TestBoard.store(tasks: tasks, boards: boards, file: board.file)
            body(store)
            cases.append(Case(label: label, board: board, store: store))
        }

        let doing = BoardColumn.inProgress.id
        mutate("move") { $0.move(TestBoard.dragDrop, to: doing) }
        mutate("complete") { $0.complete(TestBoard.sync) }
        mutate("reopen") { $0.reopen(TestBoard.palette) }
        mutate("deleteTask") { $0.deleteTask(TestBoard.cafe) }
        mutate("addTask") { $0.addTask(to: .inbox, title: "Added") }
        mutate("commitDraft") { store in
            store.beginAdding(in: .inbox)
            store.draft = "Composed"
            store.commitDraft()
        }
        mutate("quickCapture") { $0.quickCapture() }
        mutate("addTaskToCurrentMobileColumn") { $0.addTaskToCurrentMobileColumn() }
        mutate("setPriority") { $0.setPriority(.low, on: TestBoard.dragDrop) }
        mutate("setDue") { $0.setDue(TestBoard.laterDay, on: TestBoard.cafe) }
        mutate("setText") { $0.setText("Typed", field: .note, on: TestBoard.cafe) }
        mutate("addSubtask") { $0.addSubtask(to: TestBoard.cafe, text: "New row") }
        mutate("commitSubtaskDraft") { store in
            store.setSubtaskDraft("Drafted", for: .desk, task: TestBoard.cafe)
            store.commitSubtaskDraft(for: .desk, task: TestBoard.cafe)
        }
        mutate("toggleSubtask") { $0.toggleSubtask(TestBoard.dropTargets, on: TestBoard.dragDrop) }
        mutate("updateSubtask") { $0.updateSubtask(TestBoard.lift, text: "Renamed row", on: TestBoard.dragDrop) }
        mutate("deleteSubtask") { $0.deleteSubtask(TestBoard.dropTargets, from: TestBoard.dragDrop) }
        mutate("moveSubtask") { $0.moveSubtask(fromOffsets: [0], toOffset: 3, on: TestBoard.dragDrop) }
        mutate("toggleLabel") { $0.toggleLabel("design", on: TestBoard.cafe) }
        mutate("createLabel") { $0.createLabel(named: "Brand new", on: TestBoard.cafe) }
        mutate("commitLabelDraft") { store in
            store.setLabelDraft("Another one", for: .desk, task: TestBoard.cafe)
            store.commitLabelDraft(for: .desk, task: TestBoard.cafe)
        }
        mutate("renameLabel") { $0.renameLabel("design", to: "Visual design") }
        mutate("recolorLabel") { $0.recolorLabel("design", to: .hex(0xBE2828)) }
        mutate("deleteLabel") { $0.deleteLabel("design") }
        mutate("selectTheme") { $0.selectTheme(TestBoard.otherDarkTheme) }
        mutate("archive") { $0.archive(TestBoard.palette) }
        mutate("archiveCompleted") { $0.archiveCompleted() }
        // A board that starts with something already filed away: archiving first
        // would coalesce into the same debounce window and hide a restore that
        // never scheduled a write of its own.
        mutate("unarchive", tasks: TestBoard.tasks(archiving: [TestBoard.palette: 300])) {
            $0.unarchive(TestBoard.palette)
        }
        mutate("endEditing restoring an emptied title") { store in
            store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
            store.setText("", field: .title, on: TestBoard.cafe)
            store.endEditing(.title, on: TestBoard.cafe, scope: .desk)
        }

        // Columns and boards became data in Phase D, so managing either is a
        // change to the board like any other and owes the disk a write.
        mutate("addColumn") { $0.addColumn(named: "Blocked") }
        mutate("renameColumn") { $0.renameColumn(BoardColumn.upNext.id, to: "Later") }
        mutate("recolorColumn") { $0.recolorColumn(BoardColumn.backlog.id, to: .accent) }
        mutate("moveColumn") { $0.moveColumn(fromOffsets: [1], toOffset: 0) }
        mutate("deleteColumn") { $0.deleteColumn(BoardColumn.upNext.id) }
        // The saved views, which became board data in v11: making, editing,
        // duplicating, reordering and deleting one are edits to the file like a
        // column's, and each owes the disk a write and costs exactly one ⌘Z.
        mutate("addView") { $0.addView(named: "Blocked work") }
        mutate("updateView") { store in
            guard var view = store.views.first else { return }
            view.name = "Renamed"
            store.updateView(view)
        }
        mutate("duplicateView") { store in
            guard let id = store.views.first?.id else { return }
            store.duplicateView(id)
        }
        mutate("moveView") { $0.moveView(fromOffsets: [1], toOffset: 0) }
        mutate("deleteView") { store in
            guard let id = store.views.first?.id else { return }
            store.deleteView(id)
        }
        mutate("restoreSeededViews") { store in
            guard let id = store.views.first?.id else { return }
            store.deleteView(id)
            store.restoreSeededViews()
        }
        // The placement pair, and the board list — both need a second board to
        // be capable of failing.
        mutate("file", boards: TestBoard.boards) {
            $0.file(TestBoard.widget, onto: TestBoard.support.id, column: TestBoard.queue.id)
        }
        mutate("unfile") { $0.unfile(TestBoard.dragDrop) }
        mutate("createBoard") { $0.createBoard(named: "Website refresh") }
        mutate("renameBoard") { $0.renameBoard(SeedData.defaultBoard.id, to: "Northwind iOS 4.0") }
        mutate("recolorBoard") { $0.recolorBoard(SeedData.defaultBoard.id, to: .hex(0x1F6F63)) }
        mutate("moveBoard", boards: TestBoard.boards) { $0.moveBoard(fromOffsets: [1], toOffset: 0) }
        mutate("deleteBoard", boards: TestBoard.boards) { $0.deleteBoard(TestBoard.support.id) }
        // Navigation, and the one thing here that registers no undo step — but
        // which board you are on is where your work is, so it is still saved.
        mutate("selectBoard", boards: TestBoard.boards) { $0.selectBoard(TestBoard.support.id) }

        // The bulk commands multi-select exists for. Several cards each, and
        // one debounce window, so a bulk path that forgot the disk shows up
        // here as a store that never wrote at all.
        mutate("move (several)") { $0.move([TestBoard.dragDrop, TestBoard.cafe], to: doing) }
        mutate("complete (several)") { $0.complete([TestBoard.sync, TestBoard.offline]) }
        mutate("archive (several)") { $0.archive([TestBoard.palette, TestBoard.cafe]) }
        mutate("deleteTasks") { $0.deleteTasks([TestBoard.cafe, TestBoard.offline]) }
        mutate("toggleLabel (several)") { $0.toggleLabel("design", on: [TestBoard.cafe, TestBoard.sync]) }
        mutate("setPriority (several)") { $0.setPriority(.low, on: [TestBoard.dragDrop, TestBoard.sync]) }
        mutate("setDue (several)") { $0.setDue(TestBoard.laterDay, on: [TestBoard.cafe, TestBoard.sync]) }

        // Phase F: a whole board folded in from a file is a change like any
        // other and owes the disk a write.
        mutate("importBoard") { $0.importBoard(ForeignBoard.snapshot(includingCollision: true)) }

        // Past the 500ms debounce, with slack for a loaded machine.
        try await Task.sleep(for: .milliseconds(900))
        for item in cases {
            #expect(item.board.file.writeCount == 1, "\(item.label) never reached the disk")
        }

        // The discard has to be measured on its own: the capture that sets it up
        // is itself a save, and inside one debounce window the two coalesce.
        let board = TempBoard()
        let store = TestBoard.store(file: board.file)
        let captured = store.addTask(to: .inbox, title: "")
        try await Task.sleep(for: .milliseconds(900))
        #expect(board.file.writeCount == 1)
        store.discardIfBlank(captured)
        try await Task.sleep(for: .milliseconds(900))
        #expect(board.file.writeCount == 2, "discardIfBlank never reached the disk")
    }

    /// The two mutations that replace the whole board. Both write *twice* on
    /// purpose — the board as it stands is flushed and copied into `backups/`
    /// before it is thrown away, because a restore or a start-over leaves it
    /// reachable only through an undo stack that does not survive a quit — so
    /// neither fits the one-write probe above.
    @Test func replacingTheWholeBoardKeepsTheOldOneAndWritesTheNew() async throws {
        for (label, act) in [
            ("startOver", { (store: BoardStore, _: URL) in store.startOver(with: SeedData.blank.snapshot) }),
            ("restore(fromBackup:)", { (store: BoardStore, url: URL) in try? store.restore(fromBackup: url) }),
        ] {
            let temp = TempBoard()
            let store = TestBoard.store(file: temp.file)
            try FileManager.default.createDirectory(
                at: temp.file.backupsDirectory, withIntermediateDirectories: true
            )
            let backup = temp.file.backupsDirectory.appending(path: "board-20260814T090000Z.json")
            try BoardSnapshot(tasks: [TestBoard.tasks[0]], boards: [], labels: LabelDef.seed,
                              nextSerial: 100).encoded().write(to: backup)

            act(store, backup)
            try await Task.sleep(for: .milliseconds(900))

            #expect(temp.file.writeCount >= 2, "\(label) did not both keep the old board and write the new one")
            #expect(try temp.snapshot().tasks.map(\.id) == store.tasks.map(\.id),
                    "\(label) left the file disagreeing with the board")
            // The board as it stood was copied aside before it went.
            #expect(temp.file.backups().count == 2, "\(label) threw the old board away without keeping it")
        }
    }
}
