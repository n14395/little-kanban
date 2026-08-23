import Foundation
import Testing
@testable import Simple_Kanban

/// `Priority` itself: the order it declares, what a card starts on, and what it
/// answers to on disk.
///
/// **Because three of these are load-bearing somewhere else.** The order of
/// `allCases` *is* the priority sort — `BoardStore.rank(_:)` ranks a card by its
/// index in that array — and it is the order every menu draws. The default is
/// what a card is minted with. The stored spellings are what a board file from
/// any shipped version decodes through. None of the three is checked by the
/// code that leans on it, so a case added in the wrong place, or a `default`
/// moved, changes behaviour a long way from here and says nothing.
@Suite struct PriorityTests {
    // MARK: The order, which is the sort

    @Test func theCasesRunMostUrgentFirst() {
        #expect(Priority.allCases == [.max, .high, .medium, .low])
    }

    /// The same claim said the other way round, because this is the spelling
    /// filters use — `SavedView.highPriority` takes everything `>= .high` — and
    /// a `Comparable` written off an index is exactly the kind of thing that
    /// ends up backwards.
    @Test func moreUrgentComparesGreater() {
        #expect(Priority.max > .high)
        #expect(Priority.high > .medium)
        #expect(Priority.medium > .low)
        #expect(Priority.max > .low)
        #expect(Priority.low < .max)
        #expect(Priority.allCases.sorted() == [.low, .medium, .high, .max])
    }

    /// The editor's picker is the one surface that reads the scale upwards, and
    /// it takes that order from here rather than reversing `allCases` in a view
    /// body where nothing could check it.
    @Test func theEditorsOrderIsTheSameFourTheOtherWayUp() {
        #expect(Priority.leastFirst == [.low, .medium, .high, .max])
        #expect(Priority.leastFirst.reversed() == Priority.allCases)
        #expect(Priority.leastFirst.first == Priority.default,
                "the picker does not open on what a card starts at")
    }

    // MARK: What a card starts on

    @Test func aTaskStartsAtTheDefaultAndTheDefaultIsTheFloor() {
        #expect(Priority.default == .low)
        #expect(Priority.allCases.last == Priority.default, "the default is not the least urgent case")
        // The property default and the mint both have to say it, and they say
        // it through the same constant — see `BoardStore.mintTask`.
        #expect(TaskItem(code: "NW-1", title: "").priority == Priority.default)
    }

    // MARK: What it answers to on disk

    @Test func everyShippedSpellingDecodes() {
        // v6 onwards: the tokens.
        #expect(Priority(stored: "max") == .max)
        #expect(Priority(stored: "high") == .high)
        #expect(Priority(stored: "medium") == .medium)
        #expect(Priority(stored: "low") == .low)
        // Up to v5: the display strings of the day. `max` has none — it arrived
        // two versions after the file stopped storing its own words.
        #expect(Priority(stored: "High") == .high)
        #expect(Priority(stored: "Medium") == .medium)
        #expect(Priority(stored: "Low") == .low)
        #expect(Priority(stored: "Max") == nil)
        #expect(Priority(stored: "urgent") == nil)
        #expect(Priority(stored: "") == nil)
    }

    /// The refusal is not local, which is the whole reason `max` cost a version
    /// bump: a token this build does not know throws out of `init(from:)`, and a
    /// `Codable` throw takes the *whole file* with it rather than one field. See
    /// `BoardMigration.migrate(v7:)`.
    @Test func anUnknownTokenThrowsRatherThanFallingBack() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(Priority.self, from: Data(#""max""#.utf8)) == .max)
        #expect(throws: DecodingError.self) {
            try decoder.decode(Priority.self, from: Data(#""urgent""#.utf8))
        }
    }

    @Test func aPriorityRoundTripsAsItsToken() throws {
        let encoder = JSONEncoder()
        for priority in Priority.allCases {
            let data = try encoder.encode(priority)
            #expect(String(decoding: data, as: UTF8.self) == "\"\(priority.rawValue)\"")
            #expect(try JSONDecoder().decode(Priority.self, from: data) == priority)
        }
    }
}
