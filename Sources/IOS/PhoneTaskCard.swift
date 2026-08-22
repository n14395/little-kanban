#if os(iOS)

import SwiftUI

/// A card in the phone list. Tapping it raises the detail sheet; the circle in
/// its leading gutter completes it. The swipe and context-menu actions live in
/// ``PhoneTaskRowActions``, which the list applies to the row itself.
struct PhoneTaskCard: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock

    let task: TaskItem
    /// Set on the flat lists — Search, Inbox and any saved view — where a card
    /// is drawn away from the column that would otherwise say where it lives.
    /// Off by default, so the board itself is unchanged (4.8).
    var showsColumn: Bool = false

    private var isDone: Bool { store.isDone(task) }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            leadingControl
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
        .padding(.leading, 5)
        .padding(.trailing, 15)
        .padding(.top, 1)
        .padding(.bottom, 12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.card)
                .shadow(color: palette.shadow(0.05), radius: 9, y: 6)
                .shadow(color: palette.shadow(0.07), radius: 1, y: 1)
        }
        .modifier(ReorderableCard(task: task))
        // The one act on this surface that deserves `.success` (5.8). Read off
        // the card's own state rather than counted in the store, so it fires
        // once wherever the tick came from — the gutter, the swipe or the
        // menu — and only on the way *into* done.
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
                        role: store.role(of: task),
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
/// compete for the horizontal drag the way a hand-rolled swipe would; the
/// row's own swipe actions are a pan on the row and win it, which is why the
/// pager is a scroll view rather than a gesture of ours.
private struct ReorderableCard: ViewModifier {
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    /// Bumped as this card leaves the hand, and again as another lands on it —
    /// the `.impact` half of 5.8. A counter local to the card rather than
    /// `store.draggingID`, which the desk card keeps in step through
    /// `onDragSessionUpdated`: that is iOS 27, and a lift with no matching end
    /// would leave the store saying a card is in flight long after it landed.
    @State private var jolts = 0

    @ViewBuilder
    func body(content: Content) -> some View {
        if store.allowsCardDrag {
            content
                .draggable(lifted())
                .dropDestination(for: TaskTransfer.self) { items, _ in
                    guard let dropped = items.first, dropped.id != task.id,
                          store[dropped.id] != nil
                    else { return false }
                    store.move(dropped.id, onto: task.id)
                    jolts += 1
                    return true
                }
                .sensoryFeedback(.impact(weight: .light), trigger: jolts)
        } else {
            content
        }
    }

    /// The payload, and the lift with it. `.draggable` takes this as an
    /// autoclosure and calls it when a session begins rather than when the card
    /// is drawn, which makes it the one place at this deployment target that
    /// knows a card has been picked up. The bump is deferred a turn so it
    /// cannot land inside a view update if SwiftUI ever asks early.
    private func lifted() -> TaskTransfer {
        Task { @MainActor in jolts += 1 }
        return TaskTransfer(task)
    }
}

/// Complete and Delete on a task row, reachable three ways: a leading swipe, a
/// trailing swipe, and a long press.
///
/// The context menu is not a duplicate for its own sake — a swipe is unreachable
/// with VoiceOver or Switch Control, and the menu is what those read instead.
///
/// Applied by the list to the row rather than by the card to itself: list-row
/// traits are read off the row's own view, and burying them a body deeper is
/// how they quietly stop arriving.
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
                CardReorderItems(task: task)
                copyLink
                deletion
            }
            // Withheld on the board, where the pager has the horizontal drag —
            // see `BoardStore.isColumnPaging` for what was measured and why the
            // menu above carries the same verbs. Everywhere else the row is the
            // only thing asking for the gesture and keeps both edges.
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if !store.isColumnPaging { leadingAction }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if !store.isColumnPaging { deletion }
            }
    }

    /// Restore is the only thing worth doing to an archived row, so it takes the
    /// leading swipe that completion holds everywhere else: a card in the
    /// Archive is not work in progress, and offering to tick it would be.
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

    /// Only in the long-press menu. A card leaving the board on a swipe someone
    /// half-meant is the same mistake as a swipe-to-delete, and unlike delete it
    /// leaves no gap to notice.
    ///
    /// The submenu is the flat lists' way back: on the Inbox tab, in Search and
    /// in a saved view there is no column under the card saying where it is, and
    /// opening the sheet to move it is two gestures for one decision.
    @ViewBuilder private var filing: some View {
        if !task.isArchived {
            Menu {
                BoardDestinationItems(task: task)
            } label: {
                Label("Move to", systemImage: "tray.and.arrow.down")
            }

            Button { store.archive(task.id) } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
    }

    /// The card's `simplekanban://` link. Only in the menu: it is the one verb
    /// here that does nothing to the board, and a swipe that silently changed
    /// the pasteboard would be indistinguishable from a swipe that missed.
    private var copyLink: some View {
        Button { TaskLink.copyToPasteboard(task.id) } label: {
            Label("Copy Link", systemImage: "link")
        }
    }

    private var deletion: some View {
        Button(role: .destructive) {
            store.deleteTask(task.id)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

private extension BoardStore {
    /// The one verb behind the checkbox and the leading swipe alike.
    func toggleCompletion(of task: TaskItem) {
        if isDone(task) {
            reopen(task.id)
        } else {
            complete(task.id)
        }
    }
}

#endif
