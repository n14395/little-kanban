import Foundation
import Testing
@testable import Cardstock

/// The tick, and which corner of a card it is drawn in.
///
/// **It moved.** It was in the leading corner, standing in front of everything
/// the card has to say — the label chips and the title both start there, and the
/// gutter it needed pushed them in by a tick's width on every card whether or
/// not that card was anywhere near being finished. The trailing corner is where
/// the rest of a card's furniture already is: the sub-task count sits under it,
/// and on an archived card the Restore button below that.
///
/// **The rule is a static because two cards draw it.** `BoardTaskCard` is the
/// desk's and the iPad's, `PhoneTaskCard` is the phone's, and the phone asks
/// this one rather than spelling it again — one platform deciding differently
/// from another is drift this app has had to correct twice.
///
/// `@MainActor` on the suite, and it is not decoration: this is a static on a
/// `View`, so it is main-actor isolated, and a nonisolated suite that calls one
/// takes the test *host* down rather than failing to compile.
@MainActor
@Suite struct CardCornerTests {
    /// A filed card has left the workflow. Ticking one used to move it between
    /// columns — quietly deciding where it would reappear — under a list
    /// ordered by `archivedAt`, where nothing moved to say so.
    @Test func anArchivedCardWearsNoTick() {
        #expect(BoardTaskCard.drawsToggle(isArchived: true, showsCardTick: true) == false)
    }

    /// Otherwise it is the setting — see `Preferences.cardTickKey` — which is
    /// why the gutter is asked about in one place: the card has to close it the
    /// moment the switch is flipped, and a card whose overlay and whose spacer
    /// disagreed would leave an empty column of nothing down its edge.
    @Test func theTickIsTheSettingUnlessTheCardIsFiled() {
        #expect(BoardTaskCard.drawsToggle(isArchived: false, showsCardTick: true))
        #expect(BoardTaskCard.drawsToggle(isArchived: false, showsCardTick: false) == false)
    }

    /// **A source read, because a corner is not a value.** Which overlay sits in
    /// which alignment is the whole of what this change was, and there is
    /// nothing a store can be asked that knows it — the same arrangement
    /// `FieldFocusTests` and `ColumnReorderTests` have with the rules they
    /// guard. What it looks like was measured on all three platforms with
    /// screenshots while it was written.
    @Test func theTickIsDrawnInTheTrailingCorner() {
        guard SourceTree.isReachable else { return }
        guard let card = SourceTree.files().first(where: { $0.path == "Shared/BoardTaskCard.swift" })
        else { Issue.record("the board card has moved file"); return }

        #expect(card.source.contains(".overlay(alignment: .topTrailing) { completionToggle }"),
                "the tick is not in the trailing corner")
        #expect(card.source.contains(".overlay(alignment: .topLeading) { completionToggle }") == false,
                "the tick is back in the leading corner, in front of the card's own text")
    }

    /// And the phone asks this file's rule rather than deciding for itself.
    @Test func thePhoneCardAsksTheSameRule() {
        guard SourceTree.isReachable else { return }
        guard let phone = SourceTree.files().first(where: { $0.path == "IOS/PhoneTaskCard.swift" })
        else { Issue.record("the phone card has moved file"); return }

        #expect(phone.source.contains("BoardTaskCard.drawsToggle(isArchived:"),
                "the phone card decides for itself whether to draw a tick")
    }
}
