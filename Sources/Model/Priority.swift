// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How urgent a task is.
///
/// The raw values are tokens, not words. They are what the board file carries,
/// and a file whose stored values *are* its UI text cannot be translated
/// without rewriting everybody's boards — which is what the spellings below
/// replaced in snapshot v6. `displayName` is the only thing here that speaks a
/// language.
enum Priority: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    /// **Most urgent first**, because `allCases` is not only a list here: it is
    /// the priority sort itself, which ranks a card by its index in this array,
    /// and it is the order the Set Priority submenu draws. A case inserted in
    /// the wrong place would quietly re-sort every board set to sort by
    /// priority. The editor's own picker runs the other way — see
    /// ``leastFirst``.
    case max, high, medium, low

    /// What a task starts on.
    ///
    /// One spelling, because two places mint a card — `TaskItem`'s own property
    /// default and `BoardStore.mintTask`, which passes it explicitly — and a
    /// default that disagreed with itself would depend on which door the card
    /// came through. `BoardTransferDocument` reads it too: the Markdown export
    /// names a priority only where it is not this one.
    ///
    /// **Not the middle of the range.** A card arrives from a quick capture
    /// more often than from anywhere else, and a capture is a thing written
    /// down rather than a thing ranked; starting everything at Medium made the
    /// mark on a card say nothing about it, because every card had the same
    /// one. Starting at the floor means a priority on a card is something
    /// somebody decided.
    ///
    /// The migrations do *not* read this. A file that predates the field means
    /// whatever the default was when it was written, which is `.medium`, and
    /// re-reading old boards through today's default would silently re-rank
    /// them — see `BoardMigration`, where that `.medium` is written out.
    static let `default`: Priority = .low

    /// The same four the other way up, least urgent first — what the editor's
    /// picker lists.
    ///
    /// **The one place that does not run loudest first.** `allCases` is the
    /// order the *board* wants: the priority sort ranks a card by its index in
    /// it, and a menu of commands aimed at a selection reads best with the
    /// loudest thing at the top. A picker on a card is a different question —
    /// it is a scale being read off rather than a list being chosen from, and a
    /// scale reads upwards. Spelled here rather than as a `.reversed()` in a
    /// view body so there is one place to find out which order a surface draws
    /// and why.
    static let leastFirst: [Priority] = allCases.reversed()

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .max: String(localized: "Max", comment: "Task priority")
        case .high: String(localized: "High", comment: "Task priority")
        case .medium: String(localized: "Medium", comment: "Task priority")
        case .low: String(localized: "Low", comment: "Task priority")
        }
    }

    /// How files up to v5 spelled these — the display strings of the day.
    /// Written out rather than derived with `capitalized`, so the mapping stays
    /// exact in a locale where case folding is not the identity it looks like.
    ///
    /// Three rather than four: `max` arrived in v8, long after the file stopped
    /// storing its own words, so it has no older spelling to answer to.
    private static let storedBeforeV6: [String: Priority] = [
        "High": .high, "Medium": .medium, "Low": .low,
    ]

    /// A priority as any shipped board file spells it: the v6 token, or the
    /// pre-v6 display string. `nil` for neither.
    ///
    /// This is where the v5 → v6 migration actually happens. The step itself
    /// has nothing else to do — the shape either side of it is identical — but
    /// the version still has to be bumped, because a v5 build handed a file of
    /// tokens would decode none of them.
    init?(stored raw: String) {
        guard let value = Priority(rawValue: raw) ?? Self.storedBeforeV6[raw] else { return nil }
        self = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = Priority(stored: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\(raw) is not a priority this build knows"
            )
        }
        self = value
    }
}

extension Priority: Comparable {
    /// Ordered by urgency, so `.max > .high` reads the way it sounds and a
    /// filter can say `>= .high` instead of listing the cases above it — which
    /// is a list that grows every time one is added, and `SavedView` is the
    /// place that would have been silently wrong when this one was.
    ///
    /// `allCases` runs the other way, most urgent first, because that is the
    /// order the menus and the sort want. The inversion happens once, here.
    static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.urgency > rhs.urgency }

    /// Position in ``allCases``: 0 is the most urgent. The priority sort uses
    /// the same number directly — see `BoardStore.rank(_:)` — because it ranks
    /// ascending and wants the loudest card at the top.
    private var urgency: Int { Priority.allCases.firstIndex(of: self) ?? 0 }
}
