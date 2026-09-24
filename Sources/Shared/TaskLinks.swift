// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The links a description turns out to have in it.
///
/// A description is plain text and always has been: it is typed into a
/// `TextField`, it goes into the file as a `String`, and it comes back out of
/// an import or a sync the same way. So a URL somebody pastes into one is a run
/// of characters like any other — it reads as a link and behaves as a sentence.
/// This is the reading of that text which finds the runs that are somewhere to
/// go, and the drawing of it that marks them.
///
/// **The system's detector rather than a pattern of our own.** `NSDataDetector`
/// is what Mail, Notes and Messages find links with, so a string that underlines
/// itself in one of those underlines itself here. The shapes a hand-written
/// expression misses are the ones nobody thinks to write down: a bare `www.`
/// host with no scheme, an email address that has to become `mailto:`, a
/// trailing full stop that belongs to the sentence rather than to the URL, a
/// URL wrapped in brackets.
///
/// **The app's one rule about links: underlined means clickable.** A description
/// in the detail panel or the phone's sheet *is* the text, so while it is being
/// read its links are underlined and they open — see ``DescriptionEditor``, which
/// takes both away the moment the caret goes in, because a click there has to
/// move the caret instead.
///
/// The same words under a card's title, or in a row of search results, are a
/// one- or two-line preview inside something that is already a control: clicking
/// a card selects it, dragging one moves it, and the search row is a button that
/// opens the task. Those get ``highlighted(_:tint:)`` — the accent and no
/// underline — because a board that navigated to a browser when the pointer came
/// down on the third word of a note is not a board anybody could drag a card
/// across.
enum TaskLinks {
    /// One link, and where in the text it was written.
    struct Match: Equatable, Sendable {
        var url: URL
        var range: Range<String.Index>
    }

    /// Shared, and built once: a data detector is an ICU object dear enough to
    /// matter on a path a card's note takes on every scroll frame. Configured
    /// at first use and then only ever read.
    ///
    /// **`nonisolated`, not `nonisolated(unsafe)`.** `NSDataDetector` is
    /// `Sendable` now — what `NSRegularExpression`, the class it inherits from,
    /// has always documented is now in the type — so the opt-out has nothing
    /// left to opt out of. ``ActivityEntry/relative`` still needs the unsafe
    /// spelling, which is why the two no longer read alike.
    private nonisolated static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    /// Every link in `text`, in the order it is written.
    static func matches(in text: String) -> [Match] {
        guard let detector, !text.isEmpty else { return [] }
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: whole).compactMap { result in
            guard let url = result.url, isSomewhereToGo(url),
                  let range = Range(result.range, in: text)
            else { return nil }
            return Match(url: url, range: range)
        }
    }

    /// Whether there is anything here to mark. This is the question the two
    /// detail surfaces ask to decide which of their two views to draw, so it is
    /// asked far more often than the answer changes.
    static func hasLink(in text: String) -> Bool { !matches(in: text).isEmpty }

    /// What the app is willing to hand to `openURL`.
    ///
    /// Finding text that looks like a URL is the detector's job; deciding what
    /// should be opened is not, and a board file is not always something the
    /// person reading it wrote — it imports from JSON and from Markdown, and it
    /// syncs. `file:` and `data:` are the two the detector can produce that are
    /// not a *place*: one opens something off this disk, the other is its own
    /// payload. Neither is what anybody means by a link in a note.
    ///
    /// A scheme this has never heard of is allowed through on purpose.
    /// `obsidian://`, `slack://` and `x-github://` are exactly the sort of thing
    /// a task's description is written to hold, and an allow-list would have
    /// been a list of the ones we happened to think of.
    private static func isSomewhereToGo(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme != "file" && scheme != "data" && scheme != "javascript"
    }

    /// `text` with its links tinted, for the two surfaces that show a
    /// description as a preview: a card's second line and a search result's.
    ///
    /// **Tinted and bare.** Neither of these opens anything — both are inside a
    /// control of their own, and the app's rule is that an underline is the
    /// promise a click will follow the link. See ``DescriptionEditor``, which
    /// draws the underline in the one state that can keep that promise.
    ///
    /// The tint is passed in rather than read from the environment so this stays
    /// a function of its arguments. It is set on the run itself, which is what
    /// keeps a link the theme's accent rather than the system's blue.
    static func highlighted(_ text: String, tint: Color) -> AttributedString {
        let found = matches(in: text)
        guard !found.isEmpty else { return AttributedString(text) }

        var out = AttributedString()
        var cursor = text.startIndex
        // `cursor` is also the guard against overlapping matches, which the
        // detector does not produce but which would silently duplicate text if
        // it ever did.
        for match in found where match.range.lowerBound >= cursor {
            out.append(AttributedString(String(text[cursor..<match.range.lowerBound])))
            var link = AttributedString(String(text[match.range]))
            link.foregroundColor = tint
            out.append(link)
            cursor = match.range.upperBound
        }
        out.append(AttributedString(String(text[cursor...])))
        return out
    }
}
