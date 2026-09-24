// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

/// What the menu bar grew, and the three kinds of thing that can go wrong with a
/// menu item: it acts on nothing, it is live when it cannot act, or it raises a
/// flag that nothing on this platform presents.
///
/// The vocabulary's own consistency is `ShortcutTests`; this is the behaviour
/// underneath the new items.
@MainActor
@Suite struct MenuActionTests {
    /// ⌥⌘↑ and ⌥⌘↓ wrap, so neither key needs the user to know which end of the
    /// list they are at before pressing it.
    @Test func steppingThroughTheBoardsWrapsAtBothEnds() {
        let boards = TestBoard.boards
        let first = boards[0].id
        let last = boards[boards.count - 1].id

        #expect(BoardCommands.board(1, from: first, in: boards) == boards[1].id)
        #expect(BoardCommands.board(-1, from: boards[1].id, in: boards) == first)
        #expect(BoardCommands.board(1, from: last, in: boards) == first)
        #expect(BoardCommands.board(-1, from: first, in: boards) == last)
    }

    /// A surface that is not a board at all — the Inbox, a saved view — still
    /// has to answer both keys, and it lands at the near end of the list.
    @Test func steppingFromNoBoardLandsAtTheEndYouPressedTowards() {
        let boards = TestBoard.boards
        #expect(BoardCommands.board(1, from: nil, in: boards) == boards.first?.id)
        #expect(BoardCommands.board(-1, from: nil, in: boards) == boards.last?.id)
    }

    /// One board is nowhere to go, and the item is disabled to match — the two
    /// answers come from the same fact rather than from two readings of it.
    @Test func oneBoardHasNoNextBoard() {
        let boards = SeedData.boards
        #expect(boards.count == 1)
        #expect(BoardCommands.board(1, from: boards[0].id, in: boards) == nil)

        let store = TestBoard.store(boards: boards)
        #expect(AppCommand.nextBoard.isAvailable(in: store) == false)
        #expect(AppCommand.previousBoard.isAvailable(in: store) == false)
        #expect(AppCommand.nextBoard.isEnabled(for: [], in: store) == false)
    }

    /// The items aimed at the board rather than at a card. Each is disabled
    /// exactly when pressing it would do nothing, which is the rule the Task
    /// menu already followed one level down.
    @Test func anItemThatCouldNotActIsDeadRatherThanSilent() {
        let store = TestBoard.store()
        #expect(AppCommand.newColumn.isAvailable(in: store))
        #expect(AppCommand.boardSettings.isAvailable(in: store))
        // Nothing in this suite syncs: `BoardSyncStore` is not attached, so the
        // item that would send changes has nowhere to send them.
        #expect(store.isSyncing == false)
        #expect(AppCommand.syncNow.isAvailable(in: store) == false)

        let empty = TestBoard.store(tasks: [], boards: [])
        #expect(AppCommand.newColumn.isAvailable(in: empty) == false)
        #expect(AppCommand.boardSettings.isAvailable(in: empty) == false)
        // And the ones that are always live stay live on a board with nothing
        // on it: making something is what an empty board is for.
        #expect(AppCommand.newBoard.isEnabled(for: [], in: empty))
        #expect(AppCommand.saveBoard.isEnabled(for: [], in: empty))
        #expect(AppCommand.toggleInbox.isEnabled(for: [], in: empty))
    }

    /// Reopen is Complete's mirror and answers to the opposite cards: the one in
    /// Done can be reopened and not completed, and every other one the other way
    /// about.
    @Test func reopenAndCompleteAreLiveOnOppositeCards() {
        let store = TestBoard.store()
        let done = try? #require(store[TestBoard.palette])
        let doing = try? #require(store[TestBoard.sync])
        guard let done, let doing else { return }

        #expect(AppCommand.reopenTask.applies(to: done, in: store))
        #expect(AppCommand.completeTask.applies(to: done, in: store) == false)
        #expect(AppCommand.reopenTask.applies(to: doing, in: store) == false)
        #expect(AppCommand.completeTask.applies(to: doing, in: store))
    }

    /// Restore is Archive's mirror, and the whole Task menu still stands aside
    /// for a card that is off the board — `ArchiveTests` says that half at
    /// length; this is the one item that is the exception to it.
    @Test func restoreIsTheOneTaskItemAnArchivedCardAnswersTo() {
        let store = TestBoard.store()
        store.archive(TestBoard.cafe)
        let card = try? #require(store[TestBoard.cafe])
        guard let card else { return }

        #expect(store.canUnarchive(card.id))
        #expect(AppCommand.unarchiveTask.applies(to: card, in: store))
        #expect(AppCommand.archiveTask.applies(to: card, in: store) == false)
        for command in [AppCommand.moveToColumn, .moveToBoard, .setPriority, .setDueDate, .showInBoard] {
            #expect(command.applies(to: card, in: store) == false,
                    "\(command.rawValue) would edit a card the user is looking at as a record")
        }
    }

    /// A menu item aimed at three cards is one act, so it is one press of ⌘Z.
    @Test func reopeningSeveralCardsIsOneStep() {
        let (store, undo) = TestBoard.undoing()
        // Every mutation inside a group of its own: `groupsByEvent` is off under
        // `xcodebuild test`, and a registration outside one throws.
        step(undo) { store.complete(TestBoard.cafe) }
        step(undo) { store.complete(TestBoard.sync) }

        step(undo) { store.reopen([TestBoard.cafe, TestBoard.sync, TestBoard.dragDrop]) }
        #expect(store.isDone(store[TestBoard.cafe]!) == false)
        #expect(store.isDone(store[TestBoard.sync]!) == false)
        #expect(undo.undoActionName == "Reopen Tasks")

        undo.undo()
        #expect(store.isDone(store[TestBoard.cafe]!))
        #expect(store.isDone(store[TestBoard.sync]!))
    }

    /// And the cards it cannot act on are left alone rather than the whole item
    /// going dead — the rule `applicable(_:)` follows for every bulk command.
    @Test func restoringSeveralLeavesTheCardsThatAreNotArchived() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.archive(TestBoard.cafe) }
        step(undo) { store.archive(TestBoard.offline) }

        step(undo) { store.unarchive([TestBoard.cafe, TestBoard.offline, TestBoard.sync]) }
        #expect(store[TestBoard.cafe]?.isArchived == false)
        #expect(store[TestBoard.offline]?.isArchived == false)
        #expect(store[TestBoard.sync]?.isArchived == false)
        #expect(undo.undoActionName == "Restore Tasks")

        undo.undo()
        #expect(store[TestBoard.cafe]?.isArchived == true)
        #expect(store[TestBoard.offline]?.isArchived == true)
    }

    /// One card, singular name — the same distinction every other bulk command
    /// makes, so the undo item reads like the menu item that filed it.
    @Test func oneCardFilesASingularUndoName() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.archive(TestBoard.cafe) }
        step(undo) { store.unarchive([TestBoard.cafe]) }
        #expect(undo.undoActionName == "Restore Task")

        let (other, otherUndo) = TestBoard.undoing()
        step(otherUndo) { other.reopen([TestBoard.palette]) }
        #expect(otherUndo.undoActionName == "Reopen Task")
    }

    /// A bulk command with nothing to act on files no step at all, so ⌘Z after
    /// a dead press does not undo whatever came before it.
    @Test func aBulkCommandWithNothingToDoFilesNoStep() {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.reopen([TestBoard.sync]) }       // not in Done
        step(undo) { store.unarchive([TestBoard.sync]) }    // not archived
        #expect(undo.actionNames.isEmpty)
    }
}

/// The other half of a menu item working: something on this platform has to
/// present what it raises.
///
/// Every one of these is a flag set by a `Button` in a `Commands` body, and a
/// flag whose presenter is missing is an item that is live, enabled, and does
/// nothing at all — the exact failure the menu bar's own rules exist to prevent,
/// and one no unit test can see by running the app, because a `Commands` body
/// cannot be built outside a scene. So they are read out of the source.
@Suite struct MenuPresentationTests {
    private func source(_ path: String) -> String? {
        SourceTree.files().first { $0.path == path }.map { String($0.code) }
    }

    /// The sheets the menu bar opens, on every root the menu can be up over.
    /// The phone root is not exempt: the `Commands` are declared into every iOS
    /// scene, an iPhone with a hardware keyboard answers their keys, and an
    /// iPad in Slide Over or a narrow split draws the phone root with the menu
    /// bar still up — which is exactly how File ▸ Import… came to be live,
    /// enabled and dead there once already.
    @Test func everyRootPresentsEverythingTheMenuRaises() throws {
        guard SourceTree.isReachable else { return }
        for path in ["Mac/MacRootView.swift", "IOS/PadRootView.swift", "IOS/PhoneRootView.swift"] {
            let text = try #require(source(path), "\(path) is missing")
            #expect(text.contains("ShortcutsSheet()"), "\(path) does not present Help ▸ Keyboard Shortcuts")
            #expect(text.contains("DueDateSheet()"), "\(path) does not present Task ▸ Set Due Date…")
            #expect(text.contains("SavedViewEditor(viewID:"), "\(path) does not present File ▸ New View…")
            #expect(text.contains("isPresented: $window.isManagingLabels"),
                    "\(path) does not present View ▸ Labels…")
            #expect(text.contains(".modifier(BoardTransfer("),
                    "\(path) does not present File ▸ Import… / Export…")
            #expect(text.contains(".menuPresentations(window:"),
                    "\(path) does not present the backup sheet and the two menu alerts")
            // And the state the menu writes has to reach the subtree, or the
            // source list never learns that File ▸ New Board wants its field.
            #expect(text.contains(".environment(resolvedWindow)"), "\(path) keeps the window state to itself")
        }
    }

    /// The compact root's own half of the contract, where the wide surfaces'
    /// answer does not exist to be presented: the composer request becomes a
    /// made card with its editor open, File ▸ New Board becomes the naming
    /// alert, and the keyboard-focus mirror the wide root kept for the menu is
    /// cleared rather than left aiming ⌘⌫ at a card no longer on screen.
    @Test func theCompactRootAnswersTheMenuInItsOwnIdiom() throws {
        guard SourceTree.isReachable else { return }
        let text = try #require(source("IOS/PhoneRootView.swift"))
        #expect(text.contains("of: store.addingPlacement"),
                "⌘N and a capture's composer request go unanswered on the compact root")
        #expect(text.contains("of: window.isNamingNewBoard"),
                "File ▸ New Board goes unanswered on the compact root")
        #expect(text.contains("focusedTaskID = nil"),
                "the wide root's focus mirror survives the swap to the compact root")
    }

    /// The board publishes which card has the keyboard, and both roots hand it
    /// on to the window state — ⌘⌫ names the neighbour of the card it deleted,
    /// so the mirror has to run in both directions.
    @Test func bothMenuBarRootsMirrorTheBoardsFocus() throws {
        guard SourceTree.isReachable else { return }
        for path in ["Mac/MacRootView.swift", "IOS/PadRootView.swift"] {
            let text = try #require(source(path))
            #expect(text.contains("of: focusRelay.focusedTaskID) { _, id in window.focusedTaskID = id }"))
            #expect(text.contains("of: window.focusedTaskID) { _, id in focusRelay.focusedTaskID = id }"))
            #expect(text.contains("of: focusRelay.focusedColumnID) { _, id in window.focusedColumnID = id }"))
        }
    }

    /// The iPad's source list is a split view column rather than a child of the
    /// root, so View ▸ Toggle Sidebar cannot hide a view: the flag has to be
    /// mapped onto `columnVisibility`, and — because the button, the edge swipe
    /// and the system all move that column without asking — read back the other
    /// way as well.
    @Test func theIPadMapsTheSidebarFlagOntoItsSplitViewColumn() throws {
        guard SourceTree.isReachable else { return }
        let text = try #require(source("IOS/PadRootView.swift"))
        #expect(text.contains("of: window.isSidebarVisible)"))
        #expect(text.contains("of: columnVisibility)"))
        #expect(text.contains("window.isSidebarVisible = visibility != .detailOnly"))
    }

    /// Both sheets the menu bar opens are shared now. They were the desk's, in
    /// `Sources/Mac`, under `#if os(macOS)` — which is exactly what an item
    /// declared on both platforms cannot afford.
    @Test func theSheetsTheMenuOpensAreNotTheDesksAlone() throws {
        guard SourceTree.isReachable else { return }
        for path in ["Shared/ShortcutsSheet.swift", "Shared/DueDateSheet.swift"] {
            let text = try #require(source(path), "\(path) is missing")
            #expect(!text.contains("#if os(macOS)"), "\(path) is still the desk's alone")
        }
    }
}
