import SwiftUI

/// The card that is not there yet: a faint copy of the card being dragged,
/// drawn in the gap it would drop into.
///
/// **A card rather than a line.** The insertion point was a 3pt accent capsule
/// on the edge of whichever card the gap was beside — see
/// ``BoardStore/dropCaret`` — which says *between these two* and leaves the two
/// questions a reorder actually asks unanswered: how much room the card will
/// take when it lands, and whether the card in the hand is the one that will
/// take it. A copy answers both at once. It pushes its new neighbours apart by
/// exactly what the real card is about to claim, and it is legibly that card —
/// same title, same chips, same due date, same checklist bar — so a hand
/// crossing a board of forty cards is never guessing which one is in the air.
///
/// **Faint, and dashed.** The cards either side of it are real and this one is
/// a promise; drawn at full strength it is a second copy of a card that already
/// exists twenty rows up, which is worse than no mark at all. The copy itself
/// is ``BoardTaskCard/standIn`` — the card's whole drawing with none of its
/// behaviour, which it must be: whole, it would bring its own drop zones and a
/// second `.draggable` for the card already in the air.
///
/// **It takes the drop, because by the time it is on screen it is what the
/// pointer is over** — opening a gap moves the card below it down, and the
/// pointer that was in that card's upper half is now here. The zone is an
/// overlay of the same shape a card's own half uses, for the same reason: it is
/// the spelling that is known to be reached.
///
/// Hidden from a reader: a row that appears mid-gesture and vanishes on release
/// is noise in a list somebody is counting, and a reader moves cards with
/// ``MoveActions`` rather than by dragging them.
struct DropPreviewCard<Card: View>: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    /// The stand-in is drawn in both lists a card can be dropped into, so it
    /// asks the same question they do — see ``allowsDrag``.
    @Environment(\.isInboxList) private var isInboxList

    /// What is landing, and where "here" is — see ``DropPreview``.
    let preview: DropPreview
    /// The card's corner, so the dashed edge follows it rather than cutting
    /// across it. The two surfaces round their cards differently.
    var cornerRadius: CGFloat
    /// How far the gap's own zone reaches past the stand-in, into the spacing
    /// either side of it — a card's ``BoardTaskCard/Metrics/dropReach``, which
    /// is half the gap between two cards.
    ///
    /// **Because without it there was a band belonging to nobody.** A card's
    /// two halves reach `dropReach` into the gap at each end, so between two
    /// cards the pointer is always over one of them. The stand-in opens a gap
    /// *twice* that wide — a whole card and a second spacing — and claimed none
    /// of it, which left a strip either side of it that was neither a card's
    /// half nor the stand-in's: bare list, which is the list's **ground**, and
    /// the ground is what retires a caret. A pointer held in that strip shut
    /// the gap, the cards sprang back under it, the half it landed on named the
    /// same gap again, and the stand-in flickered in and out at the frame rate
    /// for as long as the pointer stayed there. Reaching as far as the cards do
    /// closes the strip: the stand-in's zone and its neighbours' halves meet in
    /// the middle of each spacing, and there is nowhere between two cards from
    /// which the ground can be touched.
    var reach: CGFloat
    /// The copy itself, built by whichever surface is drawing — the board's
    /// card and the phone's are different views.
    @ViewBuilder let card: () -> Card

    /// Faint enough to read as a promise rather than as a second card, solid
    /// enough that the title on it can still be read.
    private static var faintness: Double { 0.45 }

    var body: some View {
        // **Only where it stands in a gap.** A stand-in on an *empty* list has
        // no gap to hold: it is drawn over the list's own ground, which is the
        // destination that was going to take the drop and the one keeping the
        // list marked as hovered. A zone of its own there would take the hover
        // off that ground, and the two would hand it back and forth — the same
        // loop, one level out. Untouchable, it simply lets the ground work.
        if let caret = preview.caret {
            standIn.overlay { gap(at: caret) }
        } else {
            standIn
        }
    }

    private var standIn: some View {
        card()
            .opacity(Self.faintness)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        palette.accent.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The board's rule or the Inbox's, whichever list this gap is in — see
    /// ``BoardStore/allowsInboxCardDrag``.
    private var allowsDrag: Bool {
        isInboxList ? store.allowsInboxCardDrag : store.allowsCardDrag
    }

    /// The drop this stand-in has been promising for as long as it has been on
    /// screen, and the claim that keeps it here.
    ///
    /// `Color.clear` behind a `contentShape` rather than the card itself: that
    /// is the shape `BoardTaskCard.dropZones` uses and is known to be reached,
    /// and a copy drawn with its hit testing off is not something to hang a
    /// destination on. Applied *outside* `standIn` for that second reason.
    ///
    /// It is also the shape `BoardTaskCard.dropZones` *sizes* — out past its
    /// row by ``reach`` at each end, so it meets the halves of the cards above
    /// and below it. See ``reach`` for what was in the gap before it did.
    private func gap(at caret: DropCaret) -> some View {
        Color.clear
            .contentShape(.rect)
            .dropDestination(for: TaskTransfer.self) { items, _ in
                guard allowsDrag, let dropped = items.first, store[dropped.id] != nil
                else { return false }
                store.drop(dropped.id, at: caret)
                return true
            } isTargeted: { targeted in
                // Counted like every other destination: a pane that kept quiet
                // would read as nobody holding the drag, and the store would
                // call it over — see `BoardStore.dragTargeting`.
                store.dragTargeting(targeted)
                guard allowsDrag, targeted else { return }
                // Re-asserted rather than merely kept: this is the zone the
                // pointer is in now, and saying so is what stops the list's own
                // ground from retiring the gap out from under it.
                store.dropTargetCaret = caret
                store.dropTargetColumnID = preview.placement.columnID
                if preview.placement.isInbox { store.isInboxDropTarget = true }
            }
            .padding(.vertical, -reach)
    }
}

extension EnvironmentValues {
    /// Whether a card draws the insertion *line* on its own edge.
    ///
    /// False in the lists that draw a ``DropPreviewCard`` instead, which is
    /// every list a card can be dropped into. Both marks answer the same
    /// question, and drawing them together puts a solid accent rule along the
    /// edge of the dashed outline immediately beside it — one insertion point
    /// stated twice, in two notations.
    ///
    /// An environment value rather than a parameter because the card is two
    /// wrappers below the list that knows the answer — ``BoardCard`` on the
    /// board and `PlatformTaskCard` on the phone — and neither has any other
    /// reason to carry it.
    @Entry var drawsDropCaret = true

    /// True inside the Inbox's own list — the phone's sheet and the panel the
    /// desk and iPad draw beside the board.
    ///
    /// Which list a card is in is the whole of whether it can be dragged, and
    /// the card cannot tell from the card: an unfiled card appears in the Inbox
    /// *and* in any saved view whose rule it matches, and those two answer
    /// differently. So the list says. See ``BoardStore/allowsCardDrag`` for the
    /// board's rule and ``BoardStore/allowsInboxCardDrag`` for this one.
    ///
    /// An environment value for `drawsDropCaret`'s reason: the card is two
    /// wrappers below the list that knows.
    @Entry var isInboxList = false
}
