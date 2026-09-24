// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

/// The history section folds.
///
/// A card worked on for a month carries a hundred activity entries, and the
/// panel drew every one of them: pages of scrolling under the section nobody
/// opens the panel to read. `ActivityFeed` shows the newest few and offers the
/// rest behind one button.
///
/// **What can be asserted from here and what cannot.** Whether the button is on
/// screen is `@State` and a rendered layout, neither of which a unit test can
/// reach. What it *can* hold is the two things the fold is built on — that the
/// newest entries are the ones at the front of the list, and that both detail
/// surfaces get the same feed — plus the wiring, read off the masked source.
@MainActor
@Suite struct ActivityFeedTests {

    /// **The fold keeps the newest, because the list is newest-first.** The feed
    /// takes a `prefix`, so the whole behaviour rests on the order the store
    /// writes entries in: `insert(at: 0)`, everywhere. A store that started
    /// appending would leave the section folded onto the five things that
    /// happened when the card was made — the least useful five there are — and
    /// the fold would still look like it was working.
    @Test func theFoldKeepsTheNewestEntries() {
        let store = TestBoard.store()
        let id = TestBoard.cafe

        // Comfortably past the fold, then one act of a different kind so the
        // newest entry can be named without depending on any of the others.
        for text in ["One", "Two", "Three", "Four", "Five", "Six"] {
            _ = store.addSubtask(to: id, text: text)
        }
        store.archive(id)

        let activity = store[id]?.activity ?? []
        #expect(activity.count > ActivityFeed.collapsedCount,
                "the card did not gather enough history to fold")

        let folded = Array(activity.prefix(ActivityFeed.collapsedCount))
        #expect(folded.count == ActivityFeed.collapsedCount)
        #expect(folded.first?.kind == .archived,
                "the folded feed does not lead with the last thing that happened")
        #expect(folded.contains { $0.id == activity.last?.id } == false,
                "the fold is showing the oldest entries rather than the newest")
    }

    /// A number rather than a `Metrics` field: it is the same five on a 372pt
    /// panel and on a phone, because what it is chosen against is how much of
    /// the *history* answers the question, not how much room there is.
    @Test func bothSurfacesFoldToTheSameFew() {
        #expect(ActivityFeed.collapsedCount == 5)
        for (name, metrics) in [("desk", ActivityFeed.Metrics.desk), ("sheet", ActivityFeed.Metrics.sheet)] {
            #expect(metrics.toggleHit > 0, "\(name) has no room for the button")
            #expect(metrics.toggleFont > 0, "\(name) draws the button's words at nothing")
        }
        // The iPad draws the inspector, and it has to fold like the phone's
        // sheet rather than like the desk's panel — a finger, not a pointer.
        #expect(TaskInspector.Metrics.pad.activity.toggleHit
            == ActivityFeed.Metrics.sheet.toggleHit,
                "the iPad's activity feed took the desk's button")
    }

    /// **The wiring**, read off the *masked* source — comments and string
    /// literals are blanked — so the prose explaining the fold cannot satisfy
    /// it.
    ///
    /// Three claims, and each is a way the fold silently stops working: the feed
    /// draws a `prefix` rather than everything, it starts shut, and it shuts
    /// again when the panel is handed another card. The last is the one nothing
    /// on screen would give away — the desk's inspector stays mounted while the
    /// board hands it one card after another, so a feed left open would open
    /// every card after it at full length.
    @Test func theFeedFoldsShutAndStaysShutBetweenCards() {
        guard SourceTree.isReachable else { return }
        guard let file = SourceTree.files().first(where: { $0.path == "Shared/ActivityFeed.swift" })
        else {
            Issue.record("the activity feed has moved file")
            return
        }
        let code = file.source
        #expect(code.contains("prefix(Self.collapsedCount)"),
                "the feed draws its whole history again")
        #expect(code.contains("isExpanded = false"),
                "the feed does not start shut")
        #expect(code.contains("onChange(of: owner)"),
                "the feed stays open when the panel is pointed at another card")
    }

    /// Both detail surfaces draw the same feed, so neither can be left with the
    /// old unbounded list. They pass the task rather than its entries, which is
    /// also what carries the owner the reset above watches.
    @Test func everyDetailSurfaceDrawsTheSharedFeed() {
        guard SourceTree.isReachable else { return }
        for path in ["Shared/TaskInspector.swift", "IOS/PhoneDetailSheet.swift"] {
            guard let file = SourceTree.files().first(where: { $0.path == path }) else {
                Issue.record("\(path) is not there")
                continue
            }
            #expect(file.source.contains("ActivityFeed(task:"),
                    "\(path) draws its history without the shared feed, or without naming the card")
        }
    }
}
