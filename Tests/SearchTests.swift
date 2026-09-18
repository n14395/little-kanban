import Foundation
import Testing
@testable import LittleKanban

@MainActor
@Suite struct SearchTests {
    private func matches(_ store: BoardStore, _ query: String) -> [String] {
        store.query = query
        return store.searchResults.map(\.code)
    }

    // MARK: Tokens

    @Test func anEmptyQueryHidesNothing() {
        let store = TestBoard.store()
        #expect(matches(store, "").count == TestBoard.tasks.count)
        #expect(store.isFiltering == false)
        #expect(matches(store, "   ").count == TestBoard.tasks.count)
        #expect(store.isFiltering == false)
    }

    @Test func everyWordHasToAppearSomewhereButNotTogether() {
        let store = TestBoard.store()
        // "drag" and "columns" are three words apart in NW-121's title.
        #expect(matches(store, "drag columns") == ["NW-121"])
        #expect(matches(store, "columns drag") == ["NW-121"])
        #expect(store.isFiltering)
        // A phrase search would find this; an AND of tokens must not invent a match.
        #expect(matches(store, "drag mutations") == [])
    }

    @Test func aTokenMayComeFromAnyPartOfTheTask() {
        let store = TestBoard.store()
        #expect(matches(store, "NW-124") == ["NW-124"])                 // the code
        #expect(matches(store, "reconnect") == ["NW-123"])              // the note
        #expect(matches(store, "sync") == ["NW-124"])                   // the title
        #expect(matches(store, "polish") == ["NW-122"])                 // a label key
    }

    @Test func caseAndAccentsAreFoldedAway() {
        let store = TestBoard.store()
        #expect(matches(store, "cafe") == ["NW-122"])
        #expect(matches(store, "CAFÉ") == ["NW-122"])
        #expect(matches(store, "café") == ["NW-122"])
        #expect(matches(store, "cAfE menu") == ["NW-122"])
    }

    @Test func aQueryThatMatchesNothingHidesEverything() {
        let store = TestBoard.store()
        #expect(matches(store, "zzzz").isEmpty)
        #expect(matches(store, "").count == TestBoard.tasks.count)      // …and clearing brings it all back
    }

    // MARK: The folded-text memo

    @Test func renamingATaskChangesWhatItMatches() {
        let store = TestBoard.store()
        #expect(matches(store, "sync") == ["NW-124"])
        store.setText("Replication engine", field: .title, on: TestBoard.sync)
        #expect(matches(store, "sync") == [])
        #expect(matches(store, "replication") == ["NW-124"])
    }

    @Test func twoEditsInOneBreathAreBothSeen() {
        // The memo is stamped with a per-task counter rather than `updatedAt`:
        // two mutations can share one `Date.now`, and a memo keyed on the clock
        // would go on serving the first one's text.
        let store = TestBoard.store()
        store.setText("aaaa", field: .title, on: TestBoard.cafe)
        store.setText("bbbb", field: .title, on: TestBoard.cafe)
        #expect(matches(store, "bbbb") == ["NW-122"])
        #expect(matches(store, "aaaa") == [])
    }

    @Test func addingALabelChangesWhatATaskMatches() {
        let store = TestBoard.store()
        #expect(matches(store, "bug") == ["NW-124"])
        store.toggleLabel("bug", on: TestBoard.cafe)
        #expect(matches(store, "bug") == ["NW-122", "NW-124"])
        store.toggleLabel("bug", on: TestBoard.cafe)
        #expect(matches(store, "bug") == ["NW-124"])
    }

    @Test func aDeletedTaskLeavesNoTraceInTheResults() {
        let store = TestBoard.store()
        #expect(matches(store, "cafe") == ["NW-122"])
        store.deleteTask(TestBoard.cafe)
        #expect(matches(store, "cafe") == [])
    }

    @Test func undoingARenameTakesBackWhatTheBoardMatches() {
        // The memo is stamped with `markChanged`'s per-task counter, and a
        // restore puts a whole `tasks` array back without touching it — so a
        // memo the restore trusted would go on matching text the user has just
        // undone. `apply` drops it wholesale, which is the only stamp-free
        // answer available to it.
        let (store, undo) = TestBoard.undoing()
        store.beginEditing(.title, on: TestBoard.cafe, scope: .desk)
        store.setText("Zebra crossing", field: .title, on: TestBoard.cafe)
        step(undo) { store.endEditing(.title, on: TestBoard.cafe, scope: .desk) }
        #expect(matches(store, "zebra") == ["NW-122"])

        undo.undo()
        #expect(store[TestBoard.cafe]?.title == "Café menu polish")
        #expect(matches(store, "zebra") == [])
        #expect(matches(store, "cafe") == ["NW-122"])

        // …and the redo has to be visible to the search too.
        undo.redo()
        #expect(matches(store, "zebra") == ["NW-122"])
        #expect(matches(store, "cafe") == [])
    }

    // MARK: Grouping by column

    /// The board's own slice, which the query does not reach — see
    /// `SearchScopingTests`, where that rule lives. Asserted here as well
    /// because this is the suite about the query, and "it does nothing to the
    /// board" is half of what the query now is.
    @Test func theColumnGroupingIgnoresTheQuery() {
        let store = TestBoard.store()
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-121", "NW-122"])
        store.query = "cafe"
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-121", "NW-122"])
        #expect(store.visibleTasks(in: BoardColumn.inProgress.id).map(\.code) == ["NW-124"])
        store.query = ""
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-121", "NW-122"])
    }

    @Test func theColumnGroupingFollowsAMoveThatChangesNoCounts() {
        // A move leaves the board the same size, so a cache keyed on the count
        // alone would go on serving the old columns.
        let store = TestBoard.store()
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-121", "NW-122"])
        store.move(TestBoard.cafe, to: BoardColumn.done.id)
        #expect(store.visibleTasks(in: BoardColumn.backlog.id).map(\.code) == ["NW-121"])
        // At the head: an arrival in Done lands above what is already there.
        #expect(store.visibleTasks(in: BoardColumn.done.id).map(\.code) == ["NW-122", "NW-125"])
    }

    // MARK: What search is allowed to see

    @Test func anArchivedTaskIsInNoSearchResultAtAll() {
        // It has left the board, so it is not something the board's search
        // failed to find — it is somewhere else, and the Archive is where it is
        // looked for. See `SearchScopingTests` for which surfaces run the query.
        let store = TestBoard.store()
        #expect(matches(store, "cafe") == ["NW-122"])
        store.archive(TestBoard.cafe)
        #expect(matches(store, "cafe") == [])
        #expect(matches(store, "") == ["NW-120", "NW-121", "NW-123", "NW-124", "NW-125"])
        store.unarchive(TestBoard.cafe)
        #expect(matches(store, "cafe") == ["NW-122"])
    }
}
