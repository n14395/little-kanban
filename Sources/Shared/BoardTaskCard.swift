import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A draggable board card.
struct BoardTaskCard: View {
    /// Everything about the card that a pointer and a finger disagree about.
    ///
    /// The drawing is the design's on both: what changes is the tick's hit
    /// square, the gutter that square sits in, and enough type to be read at
    /// arm's length. See **Touch targets** in the README for the rule.
    struct Metrics {
        /// The card's own tick, drawn by the control the checklist rows use so
        /// the two cannot drift apart.
        var toggle: CompletionToggle.Metrics
        var toggleSpacing: CGFloat
        var cornerRadius: CGFloat
        var horizontalPadding: CGFloat
        var topPadding: CGFloat
        var bottomPadding: CGFloat
        var titleSize: CGFloat
        var noteSize: CGFloat
        /// The square the Archive's Restore button claims. Zero on the desk,
        /// where the drawn pill is the target — a `frame(minWidth: 0)` is an
        /// exact no-op.
        var restoreHit: CGFloat
        /// The two rings a card can wear. Here rather than as constants on
        /// ``Ring`` because a ring follows the corner it is drawn on: the pad's
        /// card is rounded at 14 and the desk's at 12, and a pair of statics
        /// fitted to the desk drew the pad's selection 2pt inside its own edge.
        var selectionRing: Ring
        var focusRing: Ring

        /// How far the toggle's hit square overhangs the box it draws, which is
        /// what the overlay is pulled back by so the circle lands on the
        /// gutter rather than beside it.
        var toggleInset: CGFloat { (toggle.hitSize - toggle.size) / 2 }

        static let desk = Metrics(
            toggle: .desk, toggleSpacing: 9, cornerRadius: 12, horizontalPadding: 12,
            topPadding: 11, bottomPadding: 10, titleSize: 13.5, noteSize: 11.5, restoreHit: 0,
            selectionRing: Ring(cornerRadius: 12, lineWidth: 2, inset: 0),
            focusRing: Ring(cornerRadius: 9, lineWidth: 1.5, inset: 3)
        )
        /// A card under a finger. The tick claims 44, so the gutter and the
        /// card's own margins grow with it rather than letting the circle sit
        /// outside the card.
        static let pad = Metrics(
            toggle: .sheet, toggleSpacing: 10, cornerRadius: 14, horizontalPadding: 14,
            topPadding: 13, bottomPadding: 12, titleSize: 15, noteSize: 12.5, restoreHit: 44,
            selectionRing: Ring(cornerRadius: 14, lineWidth: 2, inset: 0),
            focusRing: Ring(cornerRadius: 11, lineWidth: 1.5, inset: 3)
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store
    /// Where a click says which card the board should show whole. Optional
    /// because the phone's card and a preview have no board around them.
    @Environment(BoardFocusRelay.self) private var relay: BoardFocusRelay?
    /// The lift under the pointer is the one piece of motion a card has, and a
    /// board of them lifting as the pointer crosses is exactly the drift a
    /// reader with a vestibular disorder asked to be spared. The shadow still
    /// deepens — that is where the pointer is, not movement.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Two lines of note is a card that stays a card. At an accessibility size
    /// two lines is half a sentence, and the audit reports it clipped, so the
    /// card gives the note the room instead — the reader who needs the big type
    /// is the one who can least afford to open the detail to read a summary.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let task: TaskItem
    var metrics: Metrics = .desk
    /// Set on a card drawn away from its column — a saved view or a search
    /// result — where the column is the one thing the card no longer says.
    var showsColumn: Bool = false
    /// Whether this card has the keyboard, passed in rather than worked out
    /// here. Neither way of asking from inside works: `\.isFocused` is false —
    /// the element AppKit ends up focusing is the card's own `Button`, not the
    /// `focusable()` wrapper around it — and reading `focus` below is reading a
    /// binding held as a plain property, which is not a dynamic property and
    /// hands back the value from whenever it was made. The ring drew for
    /// neither, all phase. ``BoardCard`` holds the binding *as* a dynamic
    /// property, so it is the one place that can answer this.
    var isFocused: Bool = false
    /// The surface's keyboard focus, supplied by whichever wrapper made the
    /// card reachable — ``BoardCard`` on the board, ``ListCard`` in the flat
    /// lists. Written to, not read from: a click has to take the keyboard as
    /// well as the selection. `nil` only where nothing has a keyboard to give:
    /// a preview, or the phone's own card.
    var focus: FocusState<TaskItem.ID?>.Binding?

    @State private var isHovering = false

    /// One of the two rings a card can wear, as numbers rather than as four
    /// literals buried in an overlay.
    ///
    /// A card can be both selected and focused, and two rings that differ only
    /// in colour are one ring to anyone reading the screen with
    /// `differentiateWithoutColor` on. The whole of that claim is that the two
    /// differ in geometry, so both are named on ``Metrics`` — beside the corner
    /// radius they have to follow — where a test can hold them up against each
    /// other at every preset.
    struct Ring: Equatable {
        var cornerRadius: CGFloat
        var lineWidth: CGFloat
        /// How far inside the card's edge the ring is drawn.
        var inset: CGFloat
    }

    /// Whether the keyboard's ring is drawn, given what the selection ring is
    /// already saying about the same card.
    ///
    /// **Only where it adds something.** The two rings are one card's now — the
    /// selection follows the keyboard onto it, however focus arrived; see
    /// ``BoardKeyboard/selectionFollows(focusOnto:selection:held:)`` — so on the
    /// ordinary selected card the inner ring was drawing a second border round
    /// the first and saying the same thing twice.
    ///
    /// It is still drawn in the two states where focus and selection are not
    /// the same fact. A card focused inside a **multi-selection** is the one the
    /// arrows will move from and ⇧ will sweep from, which nothing else on screen
    /// marks — every card in the selection wears the outer ring alike. And a
    /// card focused while **not selected at all**, which is where a ⌘-click that
    /// took a card out of the selection leaves it: without this the card holding
    /// the keyboard would carry no mark whatsoever.
    nonisolated static func drawsFocusRing(
        isFocused: Bool, isSelected: Bool, selectionCount: Int
    ) -> Bool {
        isFocused && !(isSelected && selectionCount == 1)
    }

    private var isSelected: Bool { store.isSelected(task.id) }
    private var drawsFocusRing: Bool {
        Self.drawsFocusRing(
            isFocused: isFocused, isSelected: isSelected, selectionCount: store.selectionCount
        )
    }
    private var isDragging: Bool { store.draggingID == task.id }
    private var isDone: Bool { store.isDone(task) }

    var body: some View {
        Button {
            click()
        } label: {
            content
        }
        .buttonStyle(.bare)
        .overlay(alignment: .topLeading) { completionToggle }
        .overlay(alignment: .bottomTrailing) { restoreButton }
        .opacity(isDragging ? 0.4 : 1)
        .offset(y: isHovering && !reduceMotion ? -1 : 0)
        .motionAnimation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .modifier(DraggableWhenOrdered(
            isEnabled: store.allowsCardDrag, isFiltering: store.isFiltering,
            transfer: TaskTransfer(task)
        ))
        .modifier(CardDragSession(id: task.id))
        .dropDestination(for: TaskTransfer.self) { items, _ in
            guard store.allowsCardDrag, let dropped = items.first,
                  dropped.id != task.id, store[dropped.id] != nil
            else { return false }
            store.move(dropped.id, onto: task.id)
            return true
        } isTargeted: { targeted in
            guard store.allowsCardDrag else { return }
            if targeted { store.dropTargetColumnID = task.columnID }
            // An unfiled card is in the Inbox panel, which is not a column and
            // so cannot be named by the line above. Without this the panel goes
            // dark the moment the pointer crosses one of its own cards.
            if task.isUnfiled { store.isInboxDropTarget = targeted }
        }
        .contextMenu {
            // In the Archive the verb is Restore, and only Restore. Ticking a
            // filed card used to move it to Done — silently choosing where it
            // would reappear, and taking its outstanding sub-tasks with it —
            // under a list ordered by `archivedAt`, where nothing moved to say
            // so.
            if task.isArchived {
                Button {
                    store.unarchive(task.id)
                } label: {
                    Label("Restore Task", systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                Button {
                    toggleCompletion()
                } label: {
                    Label(isDone ? "Reopen Task" : "Complete Task",
                          systemImage: isDone ? "arrow.uturn.backward" : "checkmark.circle")
                }
                Button {
                    store.archive(task.id)
                } label: {
                    Label("Archive Task", systemImage: "archivebox")
                }
            }
            Divider()
            // Where the card lives, as opposed to where it is in the workflow.
            // The Inbox is no longer a column, so this is the only way back to
            // it other than dropping the card on the sidebar row; a board other
            // than this one has never had a route by pointer at all.
            //
            // The destinations themselves are `BoardDestinationItems`, shared
            // with the inspector's pill and the phone: this list had its own
            // idea of where the card is now — it dropped the current board and
            // the Inbox from the menu, so the menu changed shape depending on
            // the card and never said where the card was.
            Menu {
                BoardDestinationItems(task: task)
            } label: {
                Label("Move Task", systemImage: "square.stack.3d.up")
            }
            CardReorderItems(task: task)
            Button {
                TaskLink.copyToPasteboard(task.id)
            } label: {
                Label("Copy Link", systemImage: "link")
            }
            Divider()
            Button(role: .destructive) {
                store.deleteTask(task.id)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // The toggle is hidden from VoiceOver because the card combines its
        // children; these put the same verbs back as rotor actions.
        .accessibilityActions {
            if !task.isArchived {
                Button(isDone ? "Reopen task" : "Complete task") { toggleTargets() }
            }
            // A filed card is already off the board, so unfiling it is not a
            // move the Archive can show — restoring it is the way back.
            if !task.isUnfiled, !task.isArchived {
                Button("Move to Inbox") { store.move(targets, to: .inbox) }
            }
        }
        .accessibilityAction(named: task.isArchived ? Text("Restore task") : Text("Archive task")) {
            if task.isArchived {
                // A card at a time: the store has no bulk restore, and one is
                // the only way to keep this honest about which cards it takes.
                for id in targets { store.unarchive(id) }
            } else {
                store.archive(targets)
            }
        }
        .accessibilityAction(named: Text("Delete task")) {
            store.deleteTasks(targets)
        }
        .modifier(MoveActions(task: task))
    }

    private func toggleCompletion() {
        if isDone {
            store.reopen(task.id)
        } else {
            store.complete(task.id)
        }
    }

    /// What a rotor action acts on: the whole selection when this card is part
    /// of it, exactly as the keys and the menu bar do. A VoiceOver user who has
    /// picked three cards and chooses "Move to Backlog" means three — the
    /// actions used to move, complete and delete one while the identically
    /// named menu item took the lot.
    ///
    /// The tick and the context menu stay singular on purpose: both are aimed
    /// at one card with a pointer, and the card they are aimed at is the one
    /// under it.
    private var targets: Set<TaskItem.ID> { store.commandTargets(task.id) }

    /// The rotor's complete, which follows the same rule Space does: one card
    /// toggles, several complete.
    private func toggleTargets() {
        if targets.count == 1, isDone {
            store.reopen(task.id)
        } else {
            store.complete(targets)
        }
    }

    /// A click, and what the modifier held with it means: ⌘ adds this card to
    /// the selection or takes it out again, ⇧ sweeps from the last card picked
    /// to this one, and a plain click picks this one and opens it.
    private func click() {
        switch CardClick.modifier {
        case .extend:
            store.toggleSelection(of: task.id)
        case .range:
            store.extendSelection(to: task.id, through: siblingIDs)
        case .none:
            store.select(task.id)
            store.isInspectorOpen = true
        }
        focus?.wrappedValue = task.id
        // The click landed on a card that was on screen, so this asks for the
        // least the board can do: show the column it is in whole, and nothing
        // at all when it is whole already. See ``BoardReveal``.
        relay?.reveal = .intoView(task.id)
    }

    /// The cards a ⇧-click may sweep across: this card's own column on the
    /// board, and the whole flat list on every other surface. The range a user
    /// means is the one they can see, in the order they can see it — which is
    /// neither the board's array order nor a set's.
    private var siblingIDs: [TaskItem.ID] {
        guard store.surface == .board, let columnID = task.columnID else {
            return store.visibleTaskIDs(today: dayClock.today)
        }
        return store.visibleTasks(in: columnID).map(\.id)
    }

    /// Sits over the card rather than inside its label: a button nested in
    /// another button's label never sees the click, and completing a task must
    /// not also open the inspector.
    ///
    /// Absent on an archived card — see the context menu — which is why the
    /// gutter it is drawn over is conditional too.
    @ViewBuilder
    private var completionToggle: some View {
        if !task.isArchived {
            CompletionToggle(isDone: isDone, metrics: metrics.toggle) {
                toggleCompletion()
            }
            .padding(.leading, metrics.horizontalPadding - metrics.toggleInset)
            .padding(.top, metrics.topPadding - metrics.toggleInset)
            .help(isDone ? "Reopen task" : "Complete task")
            // The card combines its children, so the button's own label would
            // be read as part of the card; the card's actions carry the verbs.
            .accessibilityHidden(true)
        }
    }

    /// The Archive's rows each offer their way back, in the trailing corner the
    /// meta row leaves empty. Drawn only on an archived card, which the board
    /// never shows, so this costs the board nothing.
    @ViewBuilder
    private var restoreButton: some View {
        if task.isArchived {
            Button {
                store.unarchive(task.id)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .imageScale(.small)
                    Text("Restore", comment: "Button on an archived card that puts it back on the board")
                        .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .caption2))
                }
                .foregroundStyle(palette.inkText(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(palette.ink(0.06), in: .capsule)
                .frame(minWidth: metrics.restoreHit, minHeight: metrics.restoreHit)
            }
            .buttonStyle(.bare)
            .padding(.trailing, 10)
            .padding(.bottom, 8)
            .help("Put this task back on the board")
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func ring(_ ring: Ring, isDrawn: Bool) -> some View {
        if isDrawn {
            RoundedRectangle(cornerRadius: ring.cornerRadius)
                .strokeBorder(palette.accent, lineWidth: ring.lineWidth)
                .padding(ring.inset)
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: metrics.toggleSpacing) {
            // Holds the gutter the completion toggle is drawn over. An archived
            // card has no toggle, and the Archive is all archived cards, so the
            // whole list closes up rather than each row leaving a hole.
            if !task.isArchived {
                Color.clear
                    .frame(width: metrics.toggle.size, height: metrics.toggle.size)
            }

            VStack(alignment: .leading, spacing: 8) {
                if showsColumn || !task.labelKeys.isEmpty {
                    FlowLayout(spacing: 5) {
                        if showsColumn {
                            ColumnChip(column: store.column(for: task))
                        }
                        ForEach(store.labels(for: task)) { LabelChip(label: $0) }
                    }
                }

                Text(task.displayTitle)
                    .font(SimpleKanbanFont.ui(metrics.titleSize, .bold, relativeTo: .subheadline))
                    .lineSpacing(1.5)
                    .foregroundStyle(isDone ? palette.inkText(0.45) : palette.ink)
                    .strikethrough(isDone, color: palette.ink(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !task.note.isEmpty {
                    Text(task.note)
                        .font(SimpleKanbanFont.ui(metrics.noteSize, .medium, relativeTo: .caption))
                        .lineSpacing(1.5)
                        .foregroundStyle(palette.inkText(0.5))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    PriorityDot(priority: task.priority, namesPriority: true)
                    if let due = task.due {
                        DueChip(due: due, today: dayClock.today, role: store.role(of: task))
                    }
                    if task.hasSubtasks {
                        SubtaskCountBadge(text: task.subtaskProgressText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
        .background {
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .fill(palette.card)
                .shadow(
                    color: palette.shadow(isHovering ? 0.13 : 0.06),
                    radius: isHovering ? 7 : 1,
                    y: isHovering ? 4 : 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: metrics.cornerRadius)
                .strokeBorder(palette.ink(0.07), lineWidth: 1)
        }
        .overlay { ring(metrics.selectionRing, isDrawn: isSelected) }
        // The keyboard's ring, drawn inside the selection's rather than in
        // place of it — thinner and set in, so the difference survives being
        // read in grey — and only where the two are not the same fact. See
        // `drawsFocusRing`.
        .overlay { ring(metrics.focusRing, isDrawn: drawsFocusRing) }
    }
}

/// What was held down when a card was clicked.
///
/// AppKit's own flags rather than a gesture's: a `Button` says it was pressed
/// and not what was held while it was, and a second tap gesture beside it would
/// have the button fire as well and select the card it was meant to add. A
/// finger holds nothing, so touch always means the plain click.
enum CardClick {
    case none, extend, range

    @MainActor
    static var modifier: CardClick {
        #if os(macOS)
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { return .extend }
        if flags.contains(.shift) { return .range }
        return .none
        #else
        return .none
        #endif
    }
}

/// Keeps `draggingID` and the column highlight in step with a real drag
/// session, so a card that is picked up and dropped nowhere stops looking as
/// though it is still in the air.
///
/// The lift ends at `dataTransferCompleted` rather than at `ended`, which is
/// the whole reason this reads phases at all rather than watching for a mouse
/// up: the two are around a tenth of a second apart on macOS, and a card
/// undimmed in the gap flashes back into the column it is leaving. `endDrag`
/// has the long version.
///
/// Behind an availability check rather than a `#if`: `onDragSessionUpdated` is
/// macOS 26 but iOS **27**, and this app deploys to iOS 26. An iPad on 26 drags
/// and drops exactly as it does now — the drop handlers clear both — and simply
/// does not dim the card it is carrying.
private struct CardDragSession: ViewModifier {
    @Environment(BoardStore.self) private var store

    let id: TaskItem.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        reporting(content)
        #else
        if #available(iOS 27.0, *) {
            reporting(content)
        } else {
            content
        }
        #endif
    }

    @available(iOS 27.0, macOS 26.0, *)
    private func reporting(_ content: Content) -> some View {
        content.onDragSessionUpdated { session in
            switch session.phase {
            case .initial:
                store.draggingID = id
            case .ended(let operation):
                // *Not* where the lift ends when the card was taken. The mouse
                // coming up is only where the drag image starts flying home;
                // the payload is loaded off the pasteboard after that, and the
                // drop handler that moves the card runs later still. Undimming
                // here put the card back at full strength in the column it was
                // leaving for the tenth of a second before the move landed.
                //
                // Only an operation that carries something is worth waiting
                // for. The rest — the drop refused, the drop nowhere, the drag
                // to the Trash — are the end of it, and the card stops looking
                // lifted with the snap back.
                switch operation {
                case .copy, .move: break
                default: store.endDrag()
                }
            case .dataTransferCompleted:
                // The payload has been handed over, which is the beat the drop
                // handler runs on. `performMove` has almost always cleared this
                // already; what is left for this to catch is a drop that went
                // through without moving the card — refused by the handler,
                // aimed at the place the card already was, or taken by another
                // app altogether.
                store.endDrag()
            default:
                break
            }
        }
    }
}

/// Move Up / Move Down for one card, as menu items.
///
/// Reordering without a drag, which is the whole of what VoiceOver and Switch
/// Control have: a long-press lift is unreachable to both, and 7.1 counts a
/// gesture-only capability as a blocker. The board's cards had the lift and
/// nothing else — only the phone's row carried these — so on the iPad the
/// order of a column was a pointer-and-finger-only fact. The phone's row now
/// draws these too, rather than its own second copy of them.
///
/// The menu rather than a rotor action, because the menu is where a reader
/// meets the card's other verbs already and a second copy of a verb is a second
/// thing to read past.
///
/// Offered only where the cards on screen are in the board's own order, which
/// is the same guard the drag is under — see `BoardStore.allowsCardDrag`. In a
/// saved view or a search result the card would not visibly move.
struct CardReorderItems: View {
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    /// The cards this one shares a place with, in the order they are drawn —
    /// its column's, or the Inbox's for a card on no board. What "up" and
    /// "down" are relative to, and the one list a reorder is defined over.
    private var siblings: [TaskItem] {
        guard let columnID = task.columnID else { return store.inboxTasks }
        return store.boardTasks(in: columnID)
    }

    var body: some View {
        if store.allowsCardDrag, !task.isArchived,
           let index = siblings.firstIndex(where: { $0.id == task.id }) {
            if index > 0 {
                Button {
                    store.move(task.id, to: task.placement, before: siblings[index - 1].id)
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
            }
            if index + 1 < siblings.count {
                // Said as "the card below moves above this one", because the
                // other way round cannot be said at all: `move` refuses a
                // `before: nil` into the place a card is already in — that is
                // what stops a drop on a column from sending a card to the
                // bottom of its own — so the last row is not a destination.
                Button {
                    let next = siblings[index + 1]
                    store.move(next.id, to: next.placement, before: task.id)
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
            }
        }
    }
}

/// One rotor action per column of the card's board.
///
/// This is the non-drag way to move a task, which VoiceOver and Switch Control
/// have never had — the board's whole vocabulary was a pointer dragging a card
/// from one place to another. ⌥←/→ are the same thing for a keyboard.
///
/// The card's own board, not the board on screen: a card drawn in a saved view
/// or a search result can belong to another one, and its columns are the ones
/// it can move between.
private struct MoveActions: ViewModifier {
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    private var columns: [BoardColumn] {
        guard !task.isArchived else { return [] }
        return store.board(for: task)?.columns ?? []
    }

    func body(content: Content) -> some View {
        content.accessibilityActions {
            ForEach(columns) { column in
                if column.id != task.columnID {
                    Button(String(localized: "Move to \(column.name)",
                                  comment: "Accessibility action on a card, one per column of its board")) {
                        // The selection when this card is in it, which is what
                        // ⌥←/→ and the Task menu's own Move to Column do.
                        store.move(store.commandTargets(task.id), to: column.id)
                    }
                }
            }
        }
    }
}

/// Dragging is off wherever the cards on screen are not in the board's own
/// order — see `BoardStore.allowsCardDrag`. The card dims and says which of the
/// two reasons it is rather than failing silently; a saved view gets its own
/// sentence because "clear the search" would be advice about a search the user
/// has not typed.
private struct DraggableWhenOrdered: ViewModifier {
    let isEnabled: Bool
    let isFiltering: Bool
    let transfer: TaskTransfer

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.draggable(transfer)
        } else {
            content
                .opacity(0.88)
                .help(isFiltering
                      ? "Clear the search to drag cards between columns"
                      : "Go back to the board to drag cards between columns")
        }
    }
}
