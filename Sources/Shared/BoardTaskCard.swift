// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

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
        /// How far the two insertion targets reach past the card, into the gap
        /// either side of it. Half the column's own `cardSpacing`, so one
        /// card's reach meets the next one's exactly in the middle and a
        /// pointer between two cards is always over one of them.
        var dropReach: CGFloat
        /// The checklist line along the card's foot. Thin on purpose: it is the
        /// only thing on a card that costs no line at all, and it says the same
        /// as the fraction beside it in a form that can be read across a whole
        /// column without stopping at any one card.
        var progressHeight: CGFloat

        /// How far the toggle's hit square overhangs the box it draws, which is
        /// what the overlay is pulled back by so the circle lands on the
        /// gutter rather than beside it.
        var toggleInset: CGFloat { (toggle.hitSize - toggle.size) / 2 }

        static let desk = Metrics(
            toggle: .desk, toggleSpacing: 9, cornerRadius: 12, horizontalPadding: 12,
            topPadding: 11, bottomPadding: 10, titleSize: 13.5, noteSize: 11.5, restoreHit: 0,
            selectionRing: Ring(cornerRadius: 12, lineWidth: 2, inset: 0),
            focusRing: Ring(cornerRadius: 9, lineWidth: 1.5, inset: 3),
            dropReach: 4, progressHeight: 4.5
        )
        /// A card under a finger. The tick claims 44, so the gutter and the
        /// card's own margins grow with it rather than letting the circle sit
        /// outside the card.
        static let pad = Metrics(
            toggle: .sheet, toggleSpacing: 10, cornerRadius: 14, horizontalPadding: 14,
            topPadding: 13, bottomPadding: 12, titleSize: 15, noteSize: 12.5, restoreHit: 44,
            selectionRing: Ring(cornerRadius: 14, lineWidth: 2, inset: 0),
            focusRing: Ring(cornerRadius: 11, lineWidth: 1.5, inset: 3),
            dropReach: 5, progressHeight: 5
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store
    /// How much of a card to draw. `@AppStorage` rather than a read of
    /// `Preferences`, because the board has to redraw the moment it changes and
    /// a plain read is a value nothing is watching.
    @AppStorage(CardDensity.storageKey) private var density = CardDensity.fallback
    /// Whether the card draws its tick at all — see ``Preferences/cardTickKey``.
    /// `@AppStorage` for the same reason `density` is: every card on the board
    /// has to close its gutter the moment the switch is flipped.
    @AppStorage(Preferences.cardTickKey) private var showsCardTick = false
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
    /// False in the lists that draw a ``DropPreviewCard`` in the gap instead,
    /// which is every list a card can be dropped into — see the environment
    /// value for why one insertion point must not be stated twice.
    @Environment(\.drawsDropCaret) private var drawsDropCaret
    /// Which list this card is in, which is what decides whether it can be
    /// dragged — see ``allowsDrag``.
    @Environment(\.isInboxList) private var isInboxList

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
    /// Draw the card as the faint copy that stands in the gap a drop would land
    /// in, rather than as a card anyone can touch. See ``standIn``.
    var isStandIn: Bool = false

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

    /// Which edge of this card the drop would land against, or `nil` when it
    /// would not land here. `BoardStore.dropCaret` is where the answer is
    /// worked out; the card only draws it.
    private var dropCaretEdge: Alignment? {
        switch store.dropCaret {
        case .above(let id) where id == task.id: .top
        case .below(let id) where id == task.id: .bottom
        default: nil
        }
    }

    /// The board's rule or the Inbox's, whichever list this card is drawn in
    /// — see ``BoardStore/allowsInboxCardDrag``.
    private var allowsDrag: Bool {
        isInboxList ? store.allowsInboxCardDrag : store.allowsCardDrag
    }

    /// The card's two halves, as separate insertion targets: the top half means
    /// *above this card*, the bottom half means *below it*.
    ///
    /// **Halves rather than one target for the whole card**, because a drop
    /// that names a card can only ever mean one gap, and the rule that picked
    /// which one — the direction the drag came from — could not name the top of
    /// a list at all. See `BoardStore.dropTargetCaret`.
    ///
    /// **Over the card, and only while a card is actually travelling.** They are
    /// plain hit-testable views, so over a card nobody is dropping on they
    /// would take the click that opens it — and during a drag there is no click
    /// to take, which is the whole window they need to exist in. That window is
    /// ``BoardStore/isCardTravelling`` and not `draggingID`, which is a *lift*:
    /// a long press released in place set it, nothing cleared it, and every
    /// card in the list sat under a pane and refused to open. Behind the card
    /// was the other spelling and it does not work: measured on an iPad, a drop
    /// whose only target was a background zone landed nowhere, because the
    /// card's own content is in front of it and a drop stops at what it lands
    /// on.
    ///
    /// They reach `dropReach` past the card at each end, so the two halves of
    /// one card and the halves of the next meet in the middle of the gap: a
    /// pointer between two cards is over one of them rather than over neither,
    /// which is what made the caret blink out and jump to the foot of the
    /// column.
    @ViewBuilder private var dropZones: some View {
        if allowsDrag, store.isCardTravelling {
            VStack(spacing: 0) {
                dropZone(.above(task.id))
                dropZone(.below(task.id))
            }
            .padding(.vertical, -metrics.dropReach)
        }
    }

    private func dropZone(_ caret: DropCaret) -> some View {
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
                guard allowsDrag else { return }
                if targeted { store.dropTargetColumnID = task.columnID }
                // An unfiled card is in the Inbox panel, which is not a column
                // and so cannot be named by the line above. Without this the
                // panel goes dark the moment the pointer crosses one of its own
                // cards.
                if task.isUnfiled { store.isInboxDropTarget = targeted }
                // Claimed on the way in and **not** given up on the way out —
                // see `BoardStore.dropTargetCaret` for why leaving a half says
                // nothing worth acting on, and which three facts do retire a
                // caret. The short version: by the time this half is left, the
                // stand-in it asked for has opened in the gap and taken the
                // pointer, and clearing here would shut the gap that moved it.
                if targeted { store.dropTargetCaret = caret }
            }
    }

    /// The insertion point: the line that says *here*, on the edge the card
    /// would go against. The same mark `ChecklistView` draws between its rows,
    /// a shade thicker because a column's gaps are wider than a checklist's.
    ///
    /// On the edge rather than floating in the gap above it: an overlay knows
    /// the card's bounds and not the column's spacing, and a line drawn against
    /// the card it names cannot be read as belonging to the one on the other
    /// side of the gap.
    @ViewBuilder private var dropCaret: some View {
        if drawsDropCaret, dropCaretEdge != nil {
            Capsule()
                .fill(palette.accent)
                .frame(height: 3)
                .padding(.horizontal, 1)
                // A mark, not a target. Without this it is a hole in the card
                // it is drawn on, and the drop under it goes nowhere.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    var body: some View {
        if isStandIn { standIn } else { interactive }
    }

    /// The card as a **stand-in**: everything it draws, none of what it does.
    ///
    /// Drawn in the gap a dragged card would land in — see ``DropPreviewCard``,
    /// which is the only thing that asks for one. It is this view rather than a
    /// shape the size of a card because the question a stand-in answers is *is
    /// this the card I am carrying, and will it fit here*, and an outline
    /// answers neither: the chips, the note, the due date and the checklist bar
    /// are what identify a card at a glance, and they are also what make it the
    /// height it is going to be.
    ///
    /// **Stripped of every interaction**, and it has to be. Left whole it would
    /// bring its own ``dropZones`` with it — two more destinations, claiming
    /// the gaps either side of a card that is *in the air*, which `dropCaret`
    /// reads as no caret at all — and a second `.draggable` for a card already
    /// being dragged. The tick and the ring come along because they are part of
    /// what the card looks like; the click, the drag, the drops, the menu and
    /// the rotor actions do not.
    private var standIn: some View {
        content
            .overlay(alignment: .topTrailing) { completionToggle }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var interactive: some View {
        Button {
            click()
        } label: {
            content
        }
        .bareButton()
        .overlay(alignment: .topTrailing) { completionToggle }
        .overlay(alignment: .bottomTrailing) { restoreButton }
        .overlay(alignment: dropCaretEdge ?? .top) { dropCaret }
        .opacity(isDragging ? 0.4 : 1)
        .offset(y: isHovering && !reduceMotion ? -1 : 0)
        .motionAnimation(.easeOut(duration: 0.12), value: isHovering)
        // The ring's fade is the card's own now. It used to ride a
        // window-level `value: store.selection` animation, which made every
        // click interpolate the entire window rather than the one card whose
        // ring is moving.
        .motionAnimation(.easeOut(duration: 0.16), value: isSelected)
        .onHover { isHovering = $0 }
        .modifier(DraggableWhenOrdered(
            isEnabled: allowsDrag, transfer: TaskTransfer(task)
        ))
        .modifier(CardDragSession(id: task.id))
        .overlay { dropZones }
        // For a pointer, and only a pointer: a right-click menu on the desk,
        // and the same on an iPad with a trackpad — a finger holding this card
        // is picking it up, and gets the drag with no popup in front of it.
        // See ``pointerContextMenu(items:)`` for the split, and the
        // accessibility actions below for the same verbs by rotor, which the
        // menu no longer carries for a reader driving by touch.
        .pointerContextMenu {
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
                    store.toggleCompletion(task.id)
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
                Label("Move Board", systemImage: "square.stack.3d.up")
            }
            // Where on that board, which is the other half of the same
            // question — see ``ColumnDestinationItems``. Drawn only where there
            // are columns to name: a card in the Inbox is on no board and an
            // archived one has left the workflow, and a submenu with nothing in
            // it is a row that opens onto nothing.
            if !store.moveDestinations(for: task).isEmpty {
                Menu {
                    ColumnDestinationItems(task: task)
                } label: {
                    Label("Move Column", systemImage: "arrow.left.arrow.right")
                }
            }
            Button {
                TaskLink.copyToPasteboard(task.id)
            } label: {
                Label("Copy Link", systemImage: "link")
            }
            Divider()
            Button(role: .destructive) {
                store.trashTask(task.id)
            } label: {
                Label("Trash Task", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // The toggle is hidden from VoiceOver because the card combines its
        // children; the shared modifier puts the same verbs back as rotor
        // actions — see ``TaskRotorActions``, which both cards wear. The desk
        // acts on the whole selection, which is the `true` here.
        .modifier(TaskRotorActions(task: task, actsOnSelection: true))
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
    /// board, the Inbox panel's own list for a card in the panel, and the
    /// whole flat list on every other surface. The range a user means is the
    /// one they can see, in the order they can see it — which is neither the
    /// board's array order nor a set's.
    ///
    /// **The panel is its own list, not a prefix of the board's.** The Inbox
    /// is drawn *with* the board, and the flat every-visible-card order —
    /// right for ⌘A — stitched the two together here: a ⇧-click on a panel
    /// card with the anchor on a board card gathered the panel *and* every
    /// column up to the anchor, and the ⌘⌫ after it trashed the lot. A sweep
    /// anchored on the other surface lands as a plain click instead, which is
    /// what a board-card sweep whose anchor left its column has always done.
    private var siblingIDs: [TaskItem.ID] {
        guard store.surface == .board else {
            return store.visibleTaskIDs(today: dayClock.today)
        }
        guard let columnID = task.columnID else {
            return store.inboxTasks.map(\.id)
        }
        return store.visibleTasks(in: columnID).map(\.id)
    }

    /// Whether the card draws a tick, which is also whether `content` leaves it
    /// a gutter. Asked in one place so the overlay and the space it is drawn
    /// over cannot disagree — the failure that would leave is an empty column
    /// of nothing down the edge of every card.
    ///
    /// **The tick is in the trailing corner.** It was in the leading one, where
    /// it stood in front of everything the card has to say — the label chips and
    /// the title both start there, and the gutter pushed them in by a tick's
    /// width on every card whether or not that card was anywhere near being
    /// finished. The trailing corner is where the rest of the card's furniture
    /// already is: the sub-task count sits under it and the Archive's Restore
    /// button below that.
    ///
    /// Two ways to answer no. An archived card has never had one: in the
    /// Archive the verb is Restore and only Restore, see the context menu. The
    /// switch is the new one, and it is a preference — see
    /// ``Preferences/cardTickKey`` for why.
    private var drawsToggle: Bool {
        Self.drawsToggle(isArchived: task.isArchived, showsCardTick: showsCardTick)
    }

    /// Static so `CardCornerTests` can ask it, and so the phone's card can ask
    /// the *same* rule rather than spelling it again — both cards draw this
    /// tick, and there is no reading of this app where one of them should show
    /// it and the other should not.
    static func drawsToggle(isArchived: Bool, showsCardTick: Bool) -> Bool {
        !isArchived && showsCardTick
    }

    /// Sits over the card rather than inside its label: a button nested in
    /// another button's label never sees the click, and completing a task must
    /// not also open the inspector.
    @ViewBuilder
    private var completionToggle: some View {
        if drawsToggle {
            CompletionToggle(isDone: isDone, metrics: metrics.toggle) {
                store.toggleCompletion(task.id)
            }
            .padding(.trailing, metrics.horizontalPadding - metrics.toggleInset)
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
                        .font(palette.ui(11, .bold, relativeTo: .caption2))
                }
                .foregroundStyle(palette.inkText(0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(palette.ink(0.06), in: .capsule)
                .frame(minWidth: metrics.restoreHit, minHeight: metrics.restoreHit)
            }
            .bareButton(radius: .infinity)
            .padding(.trailing, 10)
            .padding(.bottom, 8)
            .help("Put this task back on the board")
            .accessibilityHidden(true)
        }
    }

    /// The checklist's progress, along the foot of the card.
    ///
    /// **Drawn whatever the density is**, unlike the fraction beside it. Compact
    /// exists to buy back vertical space — it drops the note, the priority dot
    /// and the count — and this is the one thing on a card that costs none: it
    /// sits in the corner radius the card already has. A column read at a glance
    /// keeps its answer to "how far along is any of this" in the mode chosen for
    /// reading many cards at once.
    ///
    /// Decoration, and hidden from a reader: ``SubtaskCountBadge`` says the same
    /// thing in words and is what the card's combined label carries.
    @ViewBuilder private var progressLine: some View {
        if task.hasSubtasks {
            ProgressMeter(
                fraction: task.subtaskFraction,
                height: metrics.progressHeight,
                isFlush: true
            )
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
                    .font(palette.ui(metrics.titleSize, .bold, relativeTo: .subheadline))
                    .lineSpacing(1.5)
                    .foregroundStyle(isDone ? palette.inkText(0.45) : palette.ink)
                    .strikethrough(isDone, color: palette.ink(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !task.note.isEmpty, density.showsDetail {
                    // Tinted and not underlined: the card is the control here,
                    // and a link that took the click would be a card you could
                    // not reliably select or drag. See ``TaskLinks``.
                    Text(TaskLinks.highlighted(task.note, tint: palette.accent))
                        .font(palette.ui(metrics.noteSize, .medium, relativeTo: .caption))
                        .lineSpacing(1.5)
                        .foregroundStyle(palette.inkText(0.5))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Compact keeps the *due* chip and drops the rest. A date is
                // the one thing on a card that changes on its own, and a card
                // that stopped saying it was overdue to save a line would be a
                // card hiding the only thing it had to say. See ``CardDensity``.
                HStack(spacing: 8) {
                    if density.showsDetail {
                        PriorityDot(priority: task.priority, namesPriority: true)
                    }
                    if let due = task.due {
                        DueChip(due: due, today: dayClock.today, isDone: store.isDone(task))
                    }
                    Spacer(minLength: 0)
                    // **The far end of the row**, with the line under it that
                    // says the same thing. It used to sit third from the left,
                    // where the two things that answer *when* — the priority dot
                    // and the due chip — pushed it a different distance in on
                    // every card, so a column of cards had their counts down a
                    // ragged diagonal. Against the trailing edge they line up,
                    // and the pair reads as one: the fraction and the bar
                    // directly beneath it.
                    if task.hasSubtasks, density.showsDetail {
                        SubtaskCountBadge(text: task.subtaskProgressText)
                    }
                }
                .padding(.top, 1)
            }

            // Holds the gutter the completion toggle is drawn over, and only
            // when there is a toggle to draw: the space is reserved by this
            // spacer alone, so a card with no tick runs its text to the card's
            // own margin rather than leaving a hole where one was.
            if drawsToggle {
                Color.clear
                    .frame(width: metrics.toggle.size, height: metrics.toggle.size)
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.topPadding)
        .padding(.bottom, metrics.bottomPadding)
        .background {
            // **The checklist line is part of the card's ground, not something
            // laid on top of it.** Drawn inside the same rounded rectangle and
            // clipped by it, so its ends follow the card's corners instead of
            // squaring them off — and so the shadow below is the shadow of the
            // card rather than of a bar hanging off its foot.
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: metrics.cornerRadius).fill(palette.card)
                progressLine
            }
            .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius))
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
/// macOS 26 but iOS **27**, and this app deploys to iOS 26. A device on 26
/// drags and drops exactly as it does now — the drop handlers clear both, and
/// `BoardStore.dragTargeting` reads the end of a drag off the destinations
/// letting go of it — and simply does not dim the card it is carrying until one
/// of them has seen it.
///
/// **Internal rather than private, because the phone's card carries it too**,
/// and went without for as long as it was the desk's alone: `ReorderableCard`
/// had `.draggable` and no reader, so on a build that *does* announce the end of
/// a drag nothing here was listening, and a card let go without a drop stayed in
/// the air until `BoardStore.liftExpiry` gave up on it. Applied outside
/// `.draggable` on both, which it has to be — a session is reported to the
/// subtree it began in.
struct CardDragSession: ViewModifier {
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

/// One rotor action per column of the card's board.
///
/// This is the non-drag way to move a task, which VoiceOver and Switch Control
/// have never had — the board's whole vocabulary was a pointer dragging a card
/// from one place to another. ⌥←/→ are the same thing for a keyboard.
///
/// The card's own board, not the board on screen — `moveDestinations(for:)` has
/// the rule, and the **Move Column** submenu on this card's context menu is the
/// same list drawn for a pointer.
///
/// Internal rather than private because the phone's card carries the same
/// actions for the same reason: its row menu answers only a pointer now, and a
/// reader by touch still has to be able to move a card somewhere.
struct MoveActions: ViewModifier {
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    func body(content: Content) -> some View {
        content.accessibilityActions {
            ForEach(store.moveDestinations(for: task)) { column in
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
/// order — see `BoardStore.allowsCardDrag`. The card dims and says why rather
/// than failing silently.
///
/// **There is one reason left.** There were two: a saved view, and a live
/// search that had hidden the cards in between. The search does not touch the
/// board any more — it opens ``SearchResultsPanel`` over it — so a card stays
/// draggable with a query running, and "clear the search to drag" is advice
/// about a state the app no longer has.
private struct DraggableWhenOrdered: ViewModifier {
    @Environment(BoardStore.self) private var store

    let isEnabled: Bool
    let transfer: TaskTransfer

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            #if os(macOS)
            content.draggable(transfer)
            #else
            if #available(iOS 27.0, *) {
                content.draggable(transfer)
            } else {
                // `CardDragSession` is the tidy way to know a card is in the
                // air and it is iOS **27**, so on an iPad running 26 nothing
                // set `draggingID` at all: no dimmed card, no column
                // highlight, and — once there was one to draw — no insertion
                // caret either. The payload being asked for is the only signal
                // this build has, and it is the one the phone has always used.
                content.draggable(lifted())
            }
            #endif
        } else {
            content
                .opacity(0.88)
                .help("Go back to the board to drag cards between columns")
        }
    }

    /// The payload, and the lift with it. See ``BoardStore/beginDrag(_:onLift:)``
    /// for the latch and the expiry this needs.
    private func lifted() -> TaskTransfer {
        store.beginDrag(transfer.id)
        return transfer
    }
}
