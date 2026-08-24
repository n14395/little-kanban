import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

/// The checklist line along the foot of a card, and the fraction above it.
///
/// The two say the same thing in two registers — a number for reading one card,
/// a length for reading a column of them — so what matters is that they cannot
/// disagree, and that the line is drawn where a card's own corners will shape it
/// rather than laid over the top of them.
@MainActor
@Suite struct CardProgressTests {
    // MARK: The fraction the line is drawn to

    @Test func theFractionIsTheTickedShareOfTheChecklist() {
        func task(_ done: Int, of total: Int) -> TaskItem {
            TaskItem(
                id: UUID(), code: "NW-1", title: "T",
                subtasks: (0..<total).map { SubTask(text: "\($0)", done: $0 < done) }
            )
        }
        #expect(task(0, of: 3).subtaskFraction == 0)
        #expect(task(2, of: 3).subtaskFraction == 2.0 / 3.0)
        #expect(task(3, of: 3).subtaskFraction == 1)
        // A card with no checklist draws no line at all, and answering zero
        // rather than dividing by it is what lets the caller ask either way.
        #expect(task(0, of: 0).subtaskFraction == 0)
        #expect(task(0, of: 0).hasSubtasks == false)
    }

    /// The words and the length come from the same two numbers, so a card cannot
    /// show "2/3" over a line drawn to a half.
    @Test func theFractionAndTheWordsAgree() {
        let task = TaskItem(
            id: UUID(), code: "NW-1", title: "T",
            subtasks: [SubTask(text: "a", done: true), SubTask(text: "b", done: true),
                       SubTask(text: "c")]
        )
        #expect(task.subtaskProgressText == "2/3")
        #expect(task.subtaskFraction == 2.0 / 3.0)
    }

    // MARK: Where it is drawn

    /// **Inside the card's own shape, and clipped by it.**
    ///
    /// Laid over the top instead, a rectangle at the foot of a rounded card
    /// squares off the two bottom corners; and hung under the background, it
    /// would take the card's shadow with it. Both surfaces put it in the same
    /// `ZStack(alignment: .bottom)` inside the rounded rectangle, clip, and
    /// shadow the result.
    @Test func bothCardsDrawTheLineInsideTheirOwnShape() throws {
        guard SourceTree.isReachable else { return }
        for path in ["Shared/BoardTaskCard.swift", "IOS/PhoneTaskCard.swift"] {
            let file = try #require(SourceTree.files().first { $0.path == path }, "\(path) has moved")
            let source = file.source
            let head = try #require(source.range(of: ".background {"), "\(path) has no card ground")
            let body = file.block(after: source.distance(from: source.startIndex, to: head.lowerBound))
            #expect(body.contains("ZStack(alignment: .bottom)"), "\(path) does not stack the line at the foot")
            #expect(body.contains(".clipShape("), "\(path) does not clip the line to the card's corners")
            // The meter itself may be a line down the file — the board card
            // pulls it out as `progressLine` — so this is asked of the whole
            // source rather than of the ground it is stacked into.
            #expect(source.contains("isFlush: true"), "\(path) draws a capsule against a clipped edge")
        }
    }

    /// **The line survives compact, and the fraction does not.**
    ///
    /// Compact exists to buy back vertical space — it drops the note, the
    /// priority dot and the count — and the line is the one thing on a card that
    /// costs none of it: it sits in the corner radius the card already has. So
    /// the mode chosen for reading many cards at once keeps its answer to "how
    /// far along is any of this".
    @Test func theBoardCardDrawsItsLineAtEveryDensity() throws {
        guard SourceTree.isReachable else { return }
        let file = try #require(
            SourceTree.files().first { $0.path == "Shared/BoardTaskCard.swift" },
            "the board card has moved"
        )
        let source = file.source
        let head = try #require(source.range(of: "private var progressLine: some View"),
                                "the line has been renamed")
        let body = file.block(after: source.distance(from: source.startIndex, to: head.lowerBound))
        #expect(body.contains("task.hasSubtasks"), "the line is drawn on cards with no checklist")
        #expect(body.contains("density") == false, "the line went away with the note and the dot")
    }

    /// The fraction sits against the **trailing** edge, under nothing but the
    /// line it describes.
    ///
    /// It used to sit third from the left, where the priority dot and the due
    /// chip — neither of which is always drawn — pushed it a different distance
    /// in on every card, so a column of them ran down a ragged diagonal. Read
    /// off the order of the row's own source, because what is being asserted is
    /// which side of the `Spacer` it is on.
    @Test func theFractionSitsAtTheTrailingEdgeOfTheBoardCard() throws {
        guard SourceTree.isReachable else { return }
        let file = try #require(
            SourceTree.files().first { $0.path == "Shared/BoardTaskCard.swift" },
            "the board card has moved"
        )
        let source = file.source
        let spacer = try #require(source.range(of: "Spacer(minLength: 0)"), "the meta row has no spacer")
        let badge = try #require(source.range(of: "SubtaskCountBadge("), "the card lost its fraction")
        #expect(spacer.lowerBound < badge.lowerBound,
                "the fraction is still on the leading side of the meta row")
    }
}
