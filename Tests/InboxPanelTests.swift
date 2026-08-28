import Foundation
import Testing
@testable import Simple_Kanban

/// The Inbox as a panel beside the board rather than a page in place of it.
///
/// It used to be a `BoardSurface` case: picking Inbox took the board away, and
/// the one list you reach for *while* working on a board was the one list you
/// had to leave the board to see. It is now a toggle — the same source-list row,
/// clicked again to put it away — and the surface enum is down to two cases,
/// which is what stops the old page coming back by accident.
@MainActor
@Suite struct InboxPanelTests {
    @Test func theRowIsASwitchRatherThanADestination() {
        let store = TestBoard.store()
        #expect(store.isInboxOpen == false)

        store.toggleInbox()
        #expect(store.isInboxOpen)
        #expect(store.isInboxShowing)
        // And the board never went anywhere, which is the point of the change.
        #expect(store.surface == .board)

        store.toggleInbox()
        #expect(store.isInboxOpen == false)
        #expect(store.isInboxShowing == false)
    }

    /// The toolbar's button and the panel are the same rule: on Today there is
    /// nothing for a toggle to open, so it is not there to be clicked. The tap
    /// that proves it is `UITests/InboxDragTests`.
    @Test func theToggleIsOnlyThereBesideABoard() {
        let store = TestBoard.store()
        #expect(store.showsInboxToggle)

        store.selectSurface(.view(SavedView.today.id))
        #expect(store.showsInboxToggle == false)
        #expect(store.isInboxShowing == false)

        store.selectSurface(.board)
        #expect(store.showsInboxToggle)
    }

    /// **The setting is a standing rule, not something that happened at launch.**
    /// "Open the Inbox with the board unless it's empty" is a sentence about
    /// arriving at the board, and picking another board — or coming back from
    /// Today — is arriving at the board. So shutting the panel answers for the
    /// board in front of you and not for the rest of the session, which is what
    /// a button that says "hide this" means.
    @Test func theSettingBringsThePanelBackOnEveryArrivalAtTheBoard() throws {
        let store = TestBoard.store(boards: TestBoard.boards)
        store.opensInboxWithTheBoard = true
        #expect(!store.inboxTasks.isEmpty, "the rule is 'unless it's empty', so the fixture needs a card in it")

        store.isInboxOpen = true
        store.toggleInbox()
        #expect(store.isInboxOpen == false, "shut, and shut it stays while the board under it does not change")

        // Another board is another arrival — and the one `surface` cannot see,
        // because it was `.board` before and after.
        let other = try #require(TestBoard.boards.last?.id)
        store.selectBoard(other)
        // The rest of the rule is a sentence about a panel beside the board.
        // The phone's Inbox is a sheet *over* it, so the setting deliberately
        // never raises one there — see `inboxOpensBesideTheBoard`, which is
        // also why Settings does not offer the switch on the phone — and an
        // arrival must change nothing.
        guard BoardStore.inboxOpensBesideTheBoard else {
            #expect(store.isInboxOpen == false,
                    "an arrival covered the phone's board with the Inbox sheet")
            return
        }
        #expect(store.isInboxOpen, "picking another board left the Inbox shut")

        // So is coming back from a saved view.
        store.toggleInbox()
        store.selectSurface(.view(SavedView.today.id))
        #expect(store.isInboxShowing == false, "the panel is beside a board that is not there")
        store.selectSurface(.board)
        #expect(store.isInboxOpen, "coming back to the board left the Inbox shut")
    }

    /// The other half, and the half a rule that only ever opens has to be held
    /// to: with the switch off, or with nothing in the Inbox to stand there,
    /// arriving at the board changes nothing.
    @Test func nothingReopensAPanelTheSettingDidNotAskFor() throws {
        let other = try #require(TestBoard.boards.last?.id)

        let off = TestBoard.store(boards: TestBoard.boards)
        off.opensInboxWithTheBoard = false
        off.selectBoard(other)
        #expect(off.isInboxOpen == false, "a switch that is off opened the Inbox anyway")

        let empty = TestBoard.store(
            tasks: TestBoard.tasks(on: SeedData.defaultBoard).filter { !$0.isUnfiled },
            boards: TestBoard.boards
        )
        empty.opensInboxWithTheBoard = true
        #expect(empty.inboxTasks.isEmpty)
        empty.selectSurface(.view(SavedView.today.id))
        empty.selectSurface(.board)
        #expect(empty.isInboxOpen == false, "an empty Inbox was raised over the board to say so")
    }

    /// A saved view takes the board's place, and the panel stands beside the
    /// *board*. It is hidden rather than switched off, so coming back does not
    /// cost a second click — picking Today was never a decision about the Inbox.
    @Test func aSavedViewHidesThePanelWithoutClosingIt() {
        let store = TestBoard.store()
        store.toggleInbox()

        store.selectSurface(.view(SavedView.today.id))
        #expect(store.isInboxShowing == false, "the panel is beside a board that is not there")
        #expect(store.isInboxOpen, "picking a view switched the Inbox off rather than hiding it")

        store.selectSurface(.board)
        #expect(store.isInboxShowing, "the panel did not come back with the board")
    }

    /// What a deep link, an intent or Spotlight asks for when the card it names
    /// is filed nowhere: the panel is beside the board, so the board has to
    /// come back too.
    @Test func showingTheInboxPutsTheBoardBackUnderIt() {
        let store = TestBoard.store()
        store.selectSurface(.view(SavedView.archive.id))

        store.showInbox()
        #expect(store.surface == .board)
        #expect(store.isInboxShowing)
    }

    @Test func showingItTwiceLeavesItOpen() {
        let store = TestBoard.store()
        store.showInbox()
        store.showInbox()
        #expect(store.isInboxShowing)
    }

    /// The panel is a column's width because that is what it reads as, and the
    /// two constants are one so they cannot drift: a panel half a column wide
    /// would be visible from across the room.
    @Test func thePanelIsExactlyAColumnWide() {
        #expect(InboxPanel.Metrics.desk.width == BoardColumnView.Metrics.desk.width)
        #expect(InboxPanel.Metrics.pad.width == BoardColumnView.Metrics.pad.width)
    }

    /// A finger needs 44 on the one control the panel has of its own.
    @Test func theCaptureButtonIsBigEnoughForAFinger() {
        #expect(InboxPanel.Metrics.pad.button >= 44)
    }

    /// The cards in it keep a column's gutter and a column's gap, so a card in
    /// the panel sits on the same grid as a card in the column beside it.
    @Test func theCardsSitOnTheColumnGrid() {
        #expect(TaskListMetrics.panel.horizontalPadding == BoardColumnView.Metrics.desk.horizontalPadding)
        #expect(TaskListMetrics.panel.rowSpacing == BoardColumnView.Metrics.desk.cardSpacing)
        #expect(TaskListMetrics.panelPad.horizontalPadding == BoardColumnView.Metrics.pad.horizontalPadding)
        #expect(TaskListMetrics.panelPad.rowSpacing == BoardColumnView.Metrics.pad.cardSpacing)
        // No cap: the panel is the cap. A row capped at the desk's 620 inside a
        // 272pt panel would be capped by the wrong number and read as centred.
        #expect(TaskListMetrics.panel.maxRowWidth == .infinity)
    }

    /// The window's floor has to grow with the panel, or opening it squeezes the
    /// board below the width one column needs.
    #if os(macOS)
    @Test func theWindowFloorGrowsWithThePanel() {
        let bare = MacRootView.floor(sidebar: false, inbox: false)
        #expect(MacRootView.floor(sidebar: false, inbox: true)
                == bare + InboxPanel.Metrics.desk.width)
        #expect(MacRootView.floor(sidebar: true, inbox: true)
                > MacRootView.floor(sidebar: true, inbox: false))
    }
    #endif

    // MARK: Dragging

    /// A card dropped on the panel from a column lands in the Inbox. The drag
    /// itself is `UITests/InboxDragTests`; this is what the drop calls.
    @Test func aCardDroppedOnThePanelIsUnfiled() throws {
        let (store, undo) = TestBoard.undoing()
        let filed = try #require(store.tasks.first { !$0.isUnfiled })

        step(undo) { store.unfile(filed.id) }
        #expect(store[filed.id]?.isUnfiled == true)
        #expect(undo.actionNames.count == 1)
    }

    /// And a card dropped on the panel it is *already in* has landed on empty
    /// space rather than on one of its neighbours. That is not a move: without
    /// this it would cost a ⌘Z and leave "Moved to Inbox" in the card's history
    /// for a card that never went anywhere.
    @Test func aCardDroppedOnTheInboxItIsAlreadyInCostsNothing() throws {
        let (store, undo) = TestBoard.undoing()
        let unfiled = try #require(store.tasks.first { $0.isUnfiled })
        let historyBefore = store[unfiled.id]?.activity.count

        step(undo) { store.unfile(unfiled.id) }

        // `canUndo` cannot answer this: `UndoManager` keeps a group it was
        // handed whether or not anything registered into it. The action name is
        // what a step actually leaves behind, and what the Edit menu would show.
        #expect(undo.actionNames.isEmpty, "a card that did not move registered an undo step")
        #expect(store[unfiled.id]?.activity.count == historyBefore)
    }

    /// The panel starts shut, and the launch argument that opens it is the only
    /// way a harness can see it — a simulator takes no taps from outside.
    @Test func thePanelStartsShut() {
        #expect(BoardStore.inboxOpensAtLaunch == false, "a test run opened the panel")
        #expect(TestBoard.store().isInboxOpen == false)
    }
}
