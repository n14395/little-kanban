import Foundation
import Testing
@testable import Simple_Kanban

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

    /// The Inbox is a panel over the board now, and raising it leaves the saved
    /// view for the same reason picking a tab does — the card a quick capture
    /// makes lands in the Inbox, and a filter it is unlikely to match is not
    /// where the user should be left looking.
    @Test func aQuickCaptureRaisesTheInboxAndLeavesTheSavedViewBehind() {
        let store = TestBoard.store()
        store.activeView = .today
        store.quickCapture()
        #expect(store.isInboxOpen)
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
                      boards: store.boards, trash: store.trash)

        step(undo) { store.clearQuery() }

        #expect(store.query == "")
        #expect(store.isFiltering == false)
        #expect(store.showsMobileFilterNotice == false)
        #expect(store.activeView == .today)     // clearing the search is not leaving the view
        #expect(undo.undoActionName == "")
        #expect(BoardMutation(tasks: store.tasks, labels: store.labels, nextSerial: 0,
                      boards: store.boards, trash: store.trash) == before)

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
        #expect(store.boardTasks(in: backlog).map(\.code) == ["NW-121", "NW-122"])
        store.archive(TestBoard.dragDrop)
        #expect(store.boardTasks(in: backlog).map(\.code) == ["NW-122"])
        store.clearQuery()
        #expect(store.boardTasks(in: backlog).map(\.code) == ["NW-122"])
    }

    /// The drop that `allowsCardDrag` exists for. A saved view draws no columns
    /// and two of them impose an ordering of their own, so "put this card before
    /// that one" resolves against a board array the rows on screen bear no
    /// relation to — a silent cross-column move aimed at a position nobody can
    /// see. The query half of the rule was already there; the view half was the
    /// hole a flat list opened in it.
    @Test func aCardOnlyDragsWhereTheRowsAreTheBoardsOwnOrder() {
        let store = TestBoard.store()
        #expect(store.allowsCardDrag)

        store.query = "cafe"
        #expect(store.allowsCardDrag == false)
        store.query = "   "
        #expect(store.allowsCardDrag)           // whitespace is not a filter here either

        store.clearQuery()
        for view in SavedView.allCases {
            store.activeView = view
            #expect(store.allowsCardDrag == false, "\(view.rawValue)")
        }

        store.activeView = nil
        #expect(store.allowsCardDrag)
    }

    @Test func theDesktopBoardKeepsFilteringBecauseItsFieldIsAlwaysOnScreen() {
        // The rule is about a field that is not visible, not about search being
        // untrustworthy: macOS shows its field beside the board at all times.
        let store = TestBoard.store()
        store.query = "cafe"
        #expect(store.visibleTasks(in: backlog).map(\.code) == ["NW-122"])
        #expect(store.isFiltering)
    }
}
