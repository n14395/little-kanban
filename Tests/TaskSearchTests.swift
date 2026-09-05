import Foundation
import Testing
@testable import Cardstock

/// The ranking: which of the things that matched comes first.
///
/// The AND over tokens is `SearchTests`, and it is the older half of the rule —
/// a query has always had to match every word. What is asserted here is the
/// half the results panel added: that *where* a word landed decides the order,
/// so a title beginning with what the user typed is at the top and a card that
/// mentions it in a note two paragraphs down is not.
///
/// Written against the scores rather than only against the order, because an
/// order can come out right by accident on six tasks. Each step of the ladder is
/// a distinction a reader would make out loud, and each is checked as itself.
@MainActor
@Suite struct TaskSearchTests {
    private func text(title: String, rest: String = "") -> TaskSearchText {
        TaskSearchText(task: TaskItem(id: UUID(), code: "", title: title, note: rest))
    }

    private func score(_ title: String, _ query: String, note: String = "") -> Int? {
        TaskSearch.score(text(title: title, rest: note), matching: TaskSearch.tokens(in: query))
    }

    // MARK: The ladder

    @Test func aTitleThatIsTheQueryOutranksATitleThatMerelyStartsWithIt() {
        #expect(score("Sync", "sync") == 10)
        #expect(score("Sync engine", "sync") == 7)
    }

    @Test func aWordInsideTheTitleOutranksALetterRunInsideAWord() {
        // "columns" is a word of it; "co" inside "macOS" is not.
        #expect(score("Drag and drop between columns", "columns") == 5)
        #expect(score("Menu bar quick-add on macOS", "co") == 3)
    }

    @Test func aHyphenStartsAWord() {
        // "Drag-and-drop" is three words to a reader, and a search that made it
        // one would rank "drop" below every accidental letter run in the board.
        #expect(score("Drag-and-drop between columns", "drop") == 5)
    }

    @Test func theTitleOutranksEverythingElseATaskCanBeFoundBy() {
        #expect(score("Offline queue", "queue") == 5)
        #expect(score("Offline queue", "reconnect", note: "Replay on reconnect.") == 1)
    }

    @Test func aTokenThatIsNowhereIsAMissHoweverWellTheRestScored() {
        #expect(score("Sync engine", "sync") != nil)
        #expect(score("Sync engine", "sync mutations") == nil)
    }

    @Test func theScoreIsTheSumSoTwoWordsOfATitleBeatOneOfEach() {
        let both = score("Sync engine rewrite", "sync engine")
        let split = score("Sync engine rewrite", "sync mutations", note: "Mutations replay.")
        #expect(both == 12)                                     // 7 + 5
        #expect(split == 8)                                     // 7 + 1
        #expect(both! > split!)
    }

    @Test func caseAndAccentsAreFoldedOnBothSides() {
        #expect(score("Café menu", "cafe") == 7)
        #expect(score("Cafe menu", "CAFÉ") == 7)
    }

    @Test func aQueryOfWhitespaceHasNoTokensAndSoIsNotASearch() {
        #expect(TaskSearch.tokens(in: "   ").isEmpty)
        #expect(TaskSearch.tokens(in: " sync  engine ") == ["sync", "engine"])
    }

    // MARK: What the store does with it

    @Test func aTitleHitComesBackAheadOfANoteHitWhateverTheBoardsOrderIs() {
        let store = TestBoard.store()
        // "menu" is a word of NW-122's title and a word of NW-120's *note* —
        // and NW-120 is the first task on the board, so a search that did not
        // rank would put it first.
        #expect(TestBoard.tasks.first?.code == "NW-120")
        store.query = "menu"
        #expect(store.searchResults.map(\.code) == ["NW-122", "NW-120"])
    }

    @Test func anEqualScoreIsBrokenByWhatWasTouchedMostRecently() {
        let store = TestBoard.store()
        store.query = "sync"
        #expect(store.searchResults.map(\.code) == ["NW-124"])

        // Two titles beginning with the same word: the scores tie, and the card
        // the user was last working on is the one they meant.
        store.setText("Sync engine", field: .title, on: TestBoard.palette)
        #expect(store.searchResults.map(\.code) == ["NW-125", "NW-124"])
    }

    @Test func anEmptyQueryIsEveryTaskRatherThanNone() {
        // The panel opens on the whole of what there is and narrows as the user
        // types — a panel that opened empty would read as a search that had
        // already failed.
        let store = TestBoard.store()
        #expect(store.searchResults.count == TestBoard.tasks.count)
        #expect(store.searchResults.map(\.code) == TestBoard.tasks.map(\.code))
    }

    // MARK: The line of description a row shows

    /// The *first line with anything on it*, so a description that opens with a
    /// blank line still shows its sentence rather than an empty row — and one
    /// line only, however many the card has.
    ///
    /// A static on the view, and this suite is `@MainActor` for it: a
    /// swift-testing suite that reaches a SwiftUI view's static from off the
    /// main actor takes the test host down with it rather than failing to
    /// compile.
    @Test func aRowShowsTheFirstLineOfTheDescriptionThatHasAnythingOnIt() {
        #expect(SearchResultsPanel.firstLine(of: "") == nil)
        #expect(SearchResultsPanel.firstLine(of: "   \n  ") == nil)
        #expect(SearchResultsPanel.firstLine(of: "One line") == "One line")
        #expect(SearchResultsPanel.firstLine(of: "First\nSecond\nThird") == "First")
        #expect(SearchResultsPanel.firstLine(of: "\n\n  Buried  \nafter") == "Buried")
    }

    @Test func theResultsSpanEveryBoardAndTheInbox() {
        // The whole point of the panel: the card you are looking for is usually
        // not on the board you are looking at.
        let store = TestBoard.store()
        store.query = "widget"
        #expect(store.searchResults.map(\.code) == ["NW-120"])   // the Inbox's
        #expect(store.searchResults.allSatisfy { $0.isUnfiled })
    }
}
