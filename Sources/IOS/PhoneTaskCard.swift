#if os(iOS)

import SwiftUI

/// A card in the phone list. Tapping it raises the detail sheet; the circle in
/// its leading gutter completes it. Everything else a card can be told to do is
/// in ``PhoneTaskRowActions``' long-press menu, which the list applies to the
/// row itself.
struct PhoneTaskCard: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock
    /// Whether the gutter is drawn at all — see ``Preferences/cardTickKey``.
    /// It does not silence the Archive's Restore, which uses the same gutter
    /// for a different verb and is the only way off that list.
    @AppStorage(Preferences.cardTickKey) private var showsCardTick = true

    let task: TaskItem
    /// Set on the flat lists — Search, Inbox and any saved view — where a card
    /// is drawn away from the column that would otherwise say where it lives.
    /// Off by default, so the board itself is unchanged (4.8).
    var showsColumn: Bool = false

    private var isDone: Bool { store.isDone(task) }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if hasLeadingControl { leadingControl }
            Button {
                store.sheetID = task.id
            } label: {
                summary
            }
            .buttonStyle(.bare)
            .accessibilityElement(children: .combine)
        }
        // The toggle's 44pt target is what sets the top inset here: the card
        // gives it the first pixel and the summary carries the visual padding
        // instead, which keeps the circle level with the first line rather than
        // 11pt below it.
        //
        // The leading inset is the gutter's, not the card's — 5, because the
        // 44pt square overhangs the 22pt circle it draws by 11 either side. So
        // with no gutter the card owes its text the margin the gutter was
        // standing in for, and pays the 15 its trailing edge already does.
        .padding(.leading, hasLeadingControl ? 5 : 15)
        .padding(.trailing, 15)
        .padding(.top, 1)
        .padding(.bottom, 12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.card)
                .shadow(color: palette.shadow(0.05), radius: 9, y: 6)
                .shadow(color: palette.shadow(0.07), radius: 1, y: 1)
        }
        // The one act on this surface that deserves `.success` (5.8). Read off
        // the card's own state rather than counted in the store, so it fires
        // once wherever the tick came from — the gutter, the menu or the detail
        // sheet — and only on the way *into* done.
        .sensoryFeedback(.success, trigger: isDone) { was, now in now && !was }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !task.labelKeys.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(store.labels(for: task)) { LabelChip(label: $0) }
                }
            }

            Text(task.displayTitle)
                .font(SimpleKanbanFont.ui(16, .bold, relativeTo: .body))
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(isDone ? palette.inkText(0.45) : palette.ink)
                .strikethrough(isDone, color: palette.ink(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 9) {
                PriorityDot(priority: task.priority, diameter: 7, namesPriority: true)
                if let due = task.due {
                    DueChip(
                        due: due,
                        today: dayClock.today,
                        isDone: store.isDone(task),
                        font: 12,
                        horizontalPadding: 7,
                        radius: 7
                    )
                }
                if task.hasSubtasks {
                    SubtaskCountBadge(text: task.subtaskProgressText, font: 12, showsGlyph: false)
                }
                Spacer(minLength: 0)
                if showsColumn {
                    ColumnChip(column: store.column(for: task))
                }
            }
        }
        .padding(.top, 11)
    }

    /// Whether the leading gutter is drawn. The Archive's Restore is not a
    /// preference — it is a filed card's only way back, and the switch below it
    /// is about the tick.
    private var hasLeadingControl: Bool { task.isArchived || showsCardTick }

    /// In the Archive the verb is Restore, not Complete. The tick was still
    /// live on an archived card, and it did two invisible things: it moved the
    /// card between columns — quietly deciding where it would reappear — and,
    /// on the way into Done, ticked off whatever sub-tasks were left. Neither
    /// showed, because the Archive sorts by `archivedAt` and the row did not
    /// move. A card that is filed away is not work in progress, so the gutter
    /// carries the one verb that is.
    @ViewBuilder private var leadingControl: some View {
        if task.isArchived { restoreBox } else { completeBox }
    }

    private var completeBox: some View {
        CompletionToggle(isDone: isDone, metrics: .sheet) {
            store.toggleCompletion(of: task)
        }
    }

    private var restoreBox: some View {
        Button { store.unarchive(task.id) } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(SimpleKanbanFont.ui(12, .bold, relativeTo: .caption))
                .fontWeight(.bold)
                .foregroundStyle(palette.accent)
                .frame(minWidth: 22, minHeight: 22)
                .background {
                    Circle().strokeBorder(palette.accent.opacity(0.35), lineWidth: 1.75)
                }
                // The drawn circle matches the tick it stands in for; the frame
                // around it is the same 44pt target that tick claimed.
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bare)
        .contentShape(.circle)
        .accessibilityLabel("Restore to board")
    }
}

/// Long-press to lift, drag to reorder (5.2). The same two modifiers the desk
/// card carries, under the same guard: where the cards on screen are not in the
/// board's own order there is nothing a drop could mean, so the gesture is not
/// offered — see `BoardStore.allowsCardDrag`.
///
/// The lift is a long press and the page turn is a pan, so the two do not
/// compete for the horizontal drag the way a hand-rolled swipe would. **A card
/// moves sideways only once it has been picked up**, which is now the whole of
/// what a sideways finger on a card can mean: the rows carried swipe actions
/// until 6.4 and no longer do — see ``PhoneTaskRowActions``.
///
/// **Applied beside ``PhoneTaskRowActions`` rather than inside the card**, and
/// that is the whole of what makes a lifted card follow the finger. UIKit shares
/// one long press between a view's `UIDragInteraction` and its
/// `UIContextMenuInteraction`: move during the lift and the drag takes it, hold
/// still and the menu does. It only shares it when both are on the *same* view.
/// With `.draggable` a body deeper than `.contextMenu` they were on two, the
/// menu's lift failed the drag's gesture underneath it, and the only way into a
/// drag left was to haul the presented menu far enough to tear the preview out
/// of it — which is a long way, by design, and is what this surface used to ask
/// for. Both are on the row now.
struct ReorderableCard: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    /// Bumped as this card leaves the hand, and again as another lands on it —
    /// the `.impact` half of 5.8. A counter local to the card, because the two
    /// things it counts happen to *this* card.
    @State private var jolts = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if store.allowsCardDrag {
            content
                // The same insertion point the desk draws, for the same reason
                // and by the same rule — see `BoardStore.dropCaret`. A finger
                // hides more of the board than a pointer does, so if anything
                // this surface needs it more.
                .overlay(alignment: dropCaretEdge ?? .top) { dropCaret }
                .overlay { dropZones }
                .draggable(lifted())
                .sensoryFeedback(.impact(weight: .light), trigger: jolts)
        } else {
            content
        }
    }

    /// The row's two halves, as separate insertion targets — the desk's
    /// ``BoardTaskCard/dropZones`` on a phone, and every word of that comment
    /// applies here. The reach is `TaskListMetrics.sheet.rowSpacing` halved,
    /// which is the gap on both of the containers a phone card is drawn in:
    /// ``PhoneColumnPage``'s stack on the board, and `TaskListView`'s `List` on
    /// the flat surfaces, which spends the same gap as two half-row insets.
    @ViewBuilder private var dropZones: some View {
        if store.allowsCardDrag, store.draggingID != nil {
            VStack(spacing: 0) {
                dropZone(.above(task.id))
                dropZone(.below(task.id))
            }
            .padding(.vertical, -TaskListMetrics.sheet.rowSpacing / 2)
        }
    }

    private func dropZone(_ caret: DropCaret) -> some View {
        Color.clear
            .contentShape(.rect)
            .dropDestination(for: TaskTransfer.self) { items, _ in
                guard let dropped = items.first, store[dropped.id] != nil else { return false }
                store.drop(dropped.id, at: caret)
                jolts += 1
                return true
            } isTargeted: { targeted in
                if targeted {
                    store.dropTargetCaret = caret
                } else if store.dropTargetCaret == caret {
                    store.dropTargetCaret = nil
                }
            }
    }

    private var dropCaretEdge: Alignment? {
        switch store.dropCaret {
        case .above(let id) where id == task.id: .top
        case .below(let id) where id == task.id: .bottom
        default: nil
        }
    }

    @ViewBuilder private var dropCaret: some View {
        if dropCaretEdge != nil {
            Capsule()
                .fill(palette.accent)
                .frame(height: 3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The payload, and the lift with it. `.draggable` takes this as an
    /// autoclosure and calls it when a session begins rather than when the card
    /// is drawn, which makes it the one place at this deployment target that
    /// knows a card has been picked up — the desk's ``CardDragSession`` is iOS
    /// 27. The latch and the expiry that make one pick-up one lift are
    /// ``BoardStore/beginDrag(_:onLift:)``'s; the bump is this card's, because
    /// it is this card that was picked up.
    private func lifted() -> TaskTransfer {
        store.beginDrag(task.id) { jolts += 1 }
        return TaskTransfer(task)
    }

}

/// Everything a card can be told to do, in one long-press menu.
///
/// **The rows do not swipe.** Complete had the leading edge and Trash the
/// trailing one until 6.4, and both are gone: a card that slides out from under
/// a sideways finger is the one thing on this surface that moves without having
/// been picked up, and being picked up is what moving a card is supposed to
/// mean. The board's rows had already given theirs up to the pager — so the
/// surfaces disagreed about what a sideways drag on a card did, which is worse
/// than either answer — and the pager keeps its swipe.
///
/// **Nothing became unreachable.** The menu was never a duplicate of the swipes:
/// it carried Move to, Archive, the reorder items and Copy Link, which no edge
/// ever offered, and it was already the only route for a reader on VoiceOver or
/// Switch Control, to whom a swipe is invisible. What the two edges held —
/// Complete and Trash — is still the first and last thing in it.
///
/// Applied by the list to the row rather than by the card to itself: list-row
/// traits are read off the row's own view, and burying them a body deeper is
/// how they quietly stop arriving. ``ReorderableCard`` is applied on the same
/// view immediately before this one, and has to be: the lift this menu opens
/// with is the drag's lift too, and UIKit only shares it between interactions
/// that sit on one view.
struct PhoneTaskRowActions: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    private var isDone: Bool { store.isDone(task) }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                leadingAction
                filing
                copyLink
                deletion
            }
    }

    /// Restore is the only thing worth doing to an archived row, so it takes the
    /// place at the head of the menu that completion holds everywhere else: a
    /// card in the Archive is not work in progress, and offering to tick it
    /// would be.
    @ViewBuilder private var leadingAction: some View {
        if task.isArchived { restoration } else { completion }
    }

    private var completion: some View {
        Button { store.toggleCompletion(of: task) } label: {
            Label(
                isDone ? "Reopen" : "Complete",
                systemImage: isDone ? "arrow.uturn.backward" : "checkmark"
            )
        }
        .tint(palette.accent)
    }

    private var restoration: some View {
        Button { store.unarchive(task.id) } label: {
            Label("Restore", systemImage: "arrow.uturn.backward")
        }
        .tint(palette.accent)
    }

    /// A card leaving the board on a gesture someone half-meant is the same
    /// mistake as a swipe-to-delete, and unlike delete it leaves no gap to
    /// notice — which is why filing never had an edge of its own even while the
    /// edges existed.
    ///
    /// The submenu is the flat lists' way back: on the Inbox tab, in Search and
    /// in a saved view there is no column under the card saying where it is, and
    /// opening the sheet to move it is two gestures for one decision.
    @ViewBuilder private var filing: some View {
        if !task.isArchived {
            Menu {
                BoardDestinationItems(task: task)
            } label: {
                Label("Move Board", systemImage: "tray.and.arrow.down")
            }

            // Where on that board, which is the other half of the same
            // question — see ``ColumnDestinationItems``. Drawn only where there
            // are columns to name: a card in the Inbox is on no board, and a
            // submenu with nothing in it is a row that opens onto nothing.
            if !store.moveDestinations(for: task).isEmpty {
                Menu {
                    ColumnDestinationItems(task: task)
                } label: {
                    Label("Move Column", systemImage: "arrow.left.arrow.right")
                }
            }

            Button { store.archive(task.id) } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
    }

    /// The card's `simplekanban://` link — the one verb here that does nothing
    /// to the board, which is why it never had an edge of its own: a swipe that
    /// silently changed the pasteboard would have been indistinguishable from a
    /// swipe that missed.
    private var copyLink: some View {
        Button { TaskLink.copyToPasteboard(task.id) } label: {
            Label("Copy Link", systemImage: "link")
        }
    }

    private var deletion: some View {
        Button(role: .destructive) {
            store.trashTask(task.id)
        } label: {
            Label("Trash", systemImage: "trash")
        }
    }
}

private extension BoardStore {
    /// The one verb behind the checkbox and the menu's first item alike.
    func toggleCompletion(of task: TaskItem) {
        if isDone(task) {
            reopen(task.id)
        } else {
            complete(task.id)
        }
    }
}

#endif
