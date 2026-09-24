// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The matcher every search on every platform goes through.
///
/// **One engine, three surfaces.** The phone's Search tab, the desk's results
/// panel and the iPad's are the same question asked from three places — *which
/// tasks answer to these words, best first* — and the answer must not depend on
/// which window it was asked from. What is platform-specific is where the list
/// is drawn; the list itself is built here.
///
/// **Every token has to match, and where it matched decides the order.** The
/// AND over tokens is the rule the board search has always had, so "drag
/// columns" still finds a title with the two words apart. What is new is that a
/// hit is *scored* rather than merely counted: a task whose title starts with
/// the word the user typed is what they meant, and a task that mentions it in a
/// note two paragraphs down almost never is. Sorting on that is the whole
/// difference between a filter and a search.
enum TaskSearch {
    /// The query, folded the way the haystacks are folded and split on
    /// whitespace. Empty for a query of spaces, which is not a search.
    static func tokens(in query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Case- and diacritic-insensitive, so "cafe" finds "Café" — applied to the
    /// query and to the text it is matched against, which is the only way the
    /// two can meet.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// How well a task answers the whole query, or `nil` when it does not
    /// answer it at all — one missing token is a miss however well the rest
    /// scored.
    ///
    /// The score is the sum over tokens, so a query that matches two words of a
    /// title beats one that matches one word of it and one word of a note.
    static func score(_ text: TaskSearchText, matching tokens: [String]) -> Int? {
        var total = 0
        for token in tokens {
            guard let score = score(text, matching: token) else { return nil }
            total += score
        }
        return total
    }

    /// What one token is worth, by where it landed.
    ///
    /// The ladder is short on purpose. Every step is a distinction a reader
    /// would make out loud — *that is the task, that is a task starting with
    /// what I typed, that is a task with the word in it somewhere, that is a
    /// task that merely mentions it* — and a finer grading than that is a
    /// number nobody can predict from the screen.
    private static func score(_ text: TaskSearchText, matching token: String) -> Int? {
        let title = text.title
        let hits = title.ranges(of: token)
        guard !hits.isEmpty else { return text.rest.contains(token) ? 1 : nil }
        if title == token { return 10 }
        if hits.contains(where: { $0.lowerBound == title.startIndex }) { return 7 }
        // A word later in the title, which is what a second query word usually
        // lands on: "columns" in "Drag-and-drop between columns" is the answer
        // even though the title does not start with it.
        if hits.contains(where: { startsAWord(title, at: $0.lowerBound) }) { return 5 }
        return 3
    }

    /// Whether the character before `index` ends a word. A hyphen counts, so
    /// "drop" is a word of "Drag-and-drop" rather than something buried in it.
    private static func startsAWord(_ text: String, at index: String.Index) -> Bool {
        guard index > text.startIndex else { return true }
        let before = text[text.index(before: index)]
        return !before.isLetter && !before.isNumber
    }
}

/// The folded text one task is matched against, in the two halves that rank
/// differently.
///
/// Split rather than the single string it used to be, because the ranking is
/// the whole of what this change is for: a hit in a title and a hit in a note
/// are not worth the same, and a search cannot tell them apart from one
/// concatenated haystack. Folding is the expensive part of a keystroke, so
/// `BoardStore` memoises the pair per task.
struct TaskSearchText: Equatable {
    var title: String
    /// The note, the code and the label keys, joined — everything a task can be
    /// found by that is not its name.
    var rest: String

    init(task: TaskItem) {
        title = TaskSearch.fold(task.title)
        rest = TaskSearch.fold("\(task.note) \(task.code) \(task.labelKeys.joined(separator: " "))")
    }
}
