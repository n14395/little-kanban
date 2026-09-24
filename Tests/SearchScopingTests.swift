// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

/// Where the one search query is allowed to act.
///
/// `query` is a single field bound by both platforms and every tab, and
/// `PhoneHeader` only puts the field on screen for Search. Filtering everything
/// through it left a Board that had silently lost most of its cards with
/// nothing on screen to explain why or to undo it. The rule that replaced it —
/// the query applies to the Search tab and to a saved view, and says so when
/// its field is not visible — is what this suite pins, at the corners of the
/// truth table rather than in the middle of it.
@MainActor
@Suite struct SearchScopingTests {
    private let backlog = BoardColumn.backlog.id
    private let today = TestBoard.dueDay

    private func codes(_ store: BoardStore) -> [String] {
        store.mobileTasks(today: today).map(\.code)
    }

    // MARK: The tabs that ignore it

    @Test func theBoardTabIgnoresAQueryTypedOnSearch() {
        let store = TestBoard.store()
        store.tab = .search
        store.query = "cafe"
        #expect(codes(store) == ["NW-122"])

        // Switching away must not carry the filter with it. A filtered board
        // would be missing most of its cards here, which is exactly what the
        // user saw.
        store.tab = .board
        store.mobileColumnID = backlog
        #expect(codes(store) == ["NW-121", "NW-122"])

        // …and coming back to Search finds the query where it was left.
        store.tab = .search
        #expect(store.query == "cafe")
        #expect(codes(store) == ["NW-122"])
    }

    /// The Inbox is a slide-over rather than a tab, and it draws `inboxTasks`
    /// directly — so a query typed on Search cannot reach it whatever the tab
    /// underneath happens to be.
    @Test func theInboxPanelIgnoresTheQueryWhicheverTabIsUnderIt() {
        let store = TestBoard.store()
        store.query = "cafe"
        for tab in PhoneTab.allCases {
            store.tab = tab
            #expect(store.inboxTasks.map(\.code) == ["NW-120"])
        }
    }

    @Test func theBoardTabIgnoresEvenAQueryThatMatchesNothing() {
        let store = TestBoard.store()
        store.query = "zzzz"
        store.tab = .board
        store.mobileColumnID = backlog
        #expect(codes(store) == ["NW-121", "NW-122"])
        store.tab = .search
        #expect(codes(store) == [])
    }

    // MARK: The surfaces that honour it

    @Test func aSavedViewIsNarrowedByTheQueryOnWhicheverTabItIsOpenedFrom() {
        let store = TestBoard.store()
        store.activeView = .highPriority
        #expect(codes(store) == ["NW-121", "NW-124"])

        store.query = "sync"
        for tab in PhoneTab.allCases {
            store.tab = tab
            #expect(codes(store) == ["NW-124"], "the query missed a saved view on \(tab.rawValue)")
        }
        // Leaving the view puts the Board back to ignoring it.
        store.activeView = nil
        store.tab = .board
        store.mobileColumnID = backlog
        #expect(codes(store) == ["NW-121", "NW-122"])
    }

    // MARK: The truth table

    @Test func onlySearchAndASavedViewApplyTheQuery() {
        let store = TestBoard.store()
        for tab in PhoneTab.allCases {
            store.tab = tab
            store.activeView = nil
            #expect(store.mobileAppliesQuery == (tab == .search), "no view, \(tab.rawValue)")
            store.activeView = .today
            #expect(store.mobileAppliesQuery, "saved view, \(tab.rawValue)")
        }
    }

    @Test func aFilterTheUserCannotSeeIsAlwaysAnnounced() {
        let store = TestBoard.store()
        // Nothing typed: nothing to announce anywhere.
        for tab in PhoneTab.allCases {
            store.tab = tab
            for view in [SavedView?.none, .some(.today)] {
                store.activeView = view
                #expect(store.showsMobileFilterNotice == false, "announced an empty query")
            }
        }

        store.query = "cafe"
        for tab in PhoneTab.allCases {
            store.tab = tab
            store.activeView = nil
            // Off a saved view the query only acts on Search, where its own
            // field is on screen — so there is never anything to announce.
            #expect(store.showsMobileFilterNotice == false, "no view, \(tab.rawValue)")
            store.activeView = .today
            // In a view it acts everywhere, and only Search shows the field.
            #expect(store.showsMobileFilterNotice == (tab != .search), "saved view, \(tab.rawValue)")
        }
    }

    @Test func whitespaceIsNotAFilterAndIsNotAnnounced() {
        let store = TestBoard.store()
        store.activeView = .today
        store.tab = .board
        store.query = "   "
        #expect(store.isFiltering == false)
        #expect(store.showsMobileFilterNotice == false)
        store.query = " cafe "
        #expect(store.isFiltering)
        #expect(store.showsMobileFilterNotice)
    }

    @Test func theAddRowIsHiddenWhereACardCannotBePut() {
        let store = TestBoard.store()
        for tab in PhoneTab.allCases {
            store.tab = tab
            store.activeView = nil
            #expect(store.showsMobileAddRow == (tab != .search), "no view, \(tab.rawValue)")
            store.activeView = .today
            // A saved view is a filter over the board, not a place to put a card.
            #expect(store.showsMobileAddRow == false, "saved view, \(tab.rawValue)")
        }
    }

    /// The chip answers "which column is this?", which only the Board tab has
    /// already answered — its pager names the column directly above the list.
    @Test func aCardNamesItsColumnWhereverTheListIsFlat() {
        let store = TestBoard.store()
        for tab in PhoneTab.allCases {
            store.tab = tab
            store.activeView = nil
            #expect(store.showsMobileColumnChips == (tab != .board), "no view, \(tab.rawValue)")
            store.activeView = .today
            // A saved view draws no pager at all, whatever the tab bar says.
            #expect(store.showsMobileColumnChips, "saved view, \(tab.rawValue)")
        }
    }

    // MARK: Picking a place

    /// Picking a tab leaves the saved view, because `mobileTasks` lets a view
    /// outrank the tab — so without this, tapping "Board" showed Today.
    @Test func pickingATabLeavesTheSavedViewBehind() {
        let store = TestBoard.store()
        store.activeView = .today
        store.mobileColumnID = backlog
        store.selectTab(.board)
        #expect(store.tab == .board)
        #expect(store.activeView == nil)
        #expect(store.mobileTasks(today: today).map(\.code) == ["NW-121", "NW-122"])

        // Including the tab the user is already on: the view is what they are
        // asking to leave.
        store.activeView = .highPriority
        store.selectTab(.board)
        #expect(store.activeView == nil)
    }

    /// **The Search slot is a switch**, which the drawer's destination rows are
    /// deliberately not: it is the phone's only way back out of search now that
    /// the Board slot is gone, and the alternative was opening the drawer and
    /// picking the board you were already looking at.
    @Test func theSearchSlotPutsAwayTheSearchItOpened() {
        let store = TestBoard.store()
        store.toggleSearch()
        #expect(store.tab == .search)
        #expect(store.isSearching)

        store.query = "cafe"
        store.mobileColumnID = backlog
        store.toggleSearch()

        #expect(store.tab == .board)
        #expect(!store.isSearching)
        // Closing is a cancel, query and all: the field goes with the tab, so
        // anything left in it would be text nothing on screen shows — waiting
        // to narrow the next saved view, and to be typed into the middle of.
        #expect(store.query == "")
        #expect(codes(store) == ["NW-121", "NW-122"])
    }

    /// A saved view outranks the tab, so with Today in front of the board the
    /// slot is not lit and a tap on it is a request to *go* to search rather
    /// than to leave it. One predicate answers both questions — what is lit and
    /// what a second tap puts away — so the two cannot come apart.
    @Test func aSavedViewOverTheSearchTabIsNotASearchToPutAway() {
        let store = TestBoard.store()
        store.tab = .search
        store.activeView = .today
        #expect(!store.isSearching)

        store.toggleSearch()

        #expect(store.activeView == nil)
        #expect(store.isSearching)
    }

    /// A quick capture leaves the saved view — the card it makes lands in the
    /// Inbox, and a filter it is unlikely to match is not where the user should
    /// be left looking once the sheet closes.
    ///
    /// **It does not raise the Inbox**, which it used to. The panel came up
    /// behind the detail sheet, so it was never seen while it mattered and was
    /// left standing over the board once the sheet was dismissed. Leaving the
    /// view and opening a panel were one line together and are not the same
    /// decision; only the second was wrong.
    @Test func aQuickCaptureLeavesTheSavedViewBehindWithoutRaisingTheInbox() {
        let store = TestBoard.store()
        store.activeView = .today
        store.quickCapture()
        #expect(!store.isInboxOpen)
        #expect(store.activeView == nil)
        #expect(store.inboxTasks.count == 2)
    }

    // MARK: Clearing

    @Test func clearingTheQueryCostsNoUndoStepAndNoSave() async throws {
        let temp = TempBoard()
        let (store, undo) = TestBoard.undoing(file: temp.file)
        store.activeView = .today
        store.tab = .board
        store.query = "cafe"
        #expect(store.showsMobileFilterNotice)
        let before = BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash, views: store.views, savedColors: store.savedColors)

        step(undo) { store.clearQuery() }

        #expect(store.query == "")
        #expect(store.isFiltering == false)
        #expect(store.showsMobileFilterNotice == false)
        #expect(store.activeView == .today)     // clearing the search is not leaving the view
        #expect(undo.undoActionName == "")
        #expect(BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash, views: store.views, savedColors: store.savedColors) == before)

        // Session state reaches no file: a query is not part of the board.
        try await Task.sleep(for: .milliseconds(900))
        #expect(temp.file.writeCount == 0)
    }

    // MARK: The board's own slice, and the desk's

    @Test func theUnfilteredColumnSliceStillLeavesTheArchiveOut() {
        let store = TestBoard.store()
        store.query = "drag"
        // `boardTasks` is the path the tabs with no field on them read, so it
        // ignores the query — but an archived card is gone from it either way.
        #expect(store.visibleTasks(in: backlog).map(\.code) == ["NW-121", "NW-122"])
        store.archive(TestBoard.dragDrop)
        #expect(store.visibleTasks(in: backlog).map(\.code) == ["NW-122"])
        store.clearQuery()
        #expect(store.visibleTasks(in: backlog).map(\.code) == ["NW-122"])
    }

    /// The drop that `allowsCardDrag` exists for. A saved view draws no columns
    /// and two of them impose an ordering of their own, so "put this card before
    /// that one" resolves against a board array the rows on screen bear no
    /// relation to — a silent cross-column move aimed at a position nobody can
    /// see.
    ///
    /// **A query is not one of the reasons any more.** It was, while the board
    /// was drawn from the search's answer. The search opens a panel over the
    /// board now, the rows underneath are untouched, and a card the user can
    /// see is a card they can move.
    @Test func aCardOnlyDragsWhereTheRowsAreTheBoardsOwnOrder() {
        let store = TestBoard.store()
        #expect(store.allowsCardDrag)

        store.query = "cafe"
        #expect(store.allowsCardDrag)

        store.clearQuery()
        for view in SavedView.allCases {
            store.activeView = view
            #expect(store.allowsCardDrag == false, "\(view.rawValue)")
        }

        store.activeView = nil
        #expect(store.allowsCardDrag)
    }

    /// **And the Inbox is not the board.** It is drawn from `inboxTasks`
    /// whatever else is open, its order is the board's own, and a drop in it
    /// resolves against that array exactly as it does with no view open — so a
    /// saved view is no reason it cannot be rearranged. On the phone, where the
    /// Inbox comes up over whichever surface you were on, the old answer meant
    /// the panel stopped being re-orderable depending on the screen behind it.
    @Test func theInboxDragsWhateverIsOpenBehindIt() {
        let store = TestBoard.store()
        #expect(store.allowsInboxCardDrag)

        for view in SavedView.allCases {
            store.activeView = view
            #expect(store.allowsInboxCardDrag, "the Inbox stopped dragging under \(view.rawValue)")
            #expect(store.allowsCardDrag == false, "the board kept dragging under \(view.rawValue)")
        }

        store.activeView = nil
        store.query = "cafe"
        #expect(store.allowsInboxCardDrag, "a query stopped the Inbox dragging")
    }

    /// What the two rules still agree on: an ordering the board did not choose
    /// is an ordering a drop cannot mean, in either list.
    @Test func neitherListDragsWhenTheSortIsNotTheBoardsOwn() {
        let store = TestBoard.store()
        for order in BoardSortOrder.allCases where order != .manual {
            store.sortOrder = order
            #expect(store.allowsCardDrag == false, "\(order.rawValue)")
            #expect(store.allowsInboxCardDrag == false, "\(order.rawValue): the Inbox")
        }
        store.sortOrder = .manual
        #expect(store.allowsInboxCardDrag)
    }

    /// The defect this whole change is for, at the store: **no board narrows
    /// itself for a query, on any platform**.
    ///
    /// The desk used to, on the grounds that its field is always on screen — so
    /// the reader could at least see what had done it. That is an argument about
    /// the *explanation*, not about the answer: what people type into a search
    /// field is "where is that card", and the card is usually on another board,
    /// which a filter over the board you are already looking at can never say.
    /// The answer is `searchResults`, drawn in a panel over the top.
    @Test func nothingOnTheBoardIsNarrowedByAQuery() {
        let store = TestBoard.store()
        store.query = "cafe"
        #expect(store.isFiltering)
        #expect(store.visibleTasks(in: backlog).map(\.code) == ["NW-121", "NW-122"])
        #expect(store.inboxTasks.map(\.code) == ["NW-120"])
        #expect(store.tasks(in: .highPriority, today: today).map(\.code) == ["NW-121", "NW-124"])

        // …and the search still answers, from every board and the Inbox at once.
        #expect(store.searchResults.map(\.code) == ["NW-122"])
    }
}
