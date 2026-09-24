// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The sub-task list shared by the macOS inspector and the iOS detail sheet.
///
/// Every row edits in place: the box toggles and the text is a field driven by
/// the same `beginEditing`/`endEditing` session as the task title, so a row
/// retyped a letter at a time is one activity entry and one ⌘Z.
///
/// **The rows re-order by dragging the grip at the end of one**, on both
/// platforms, and the Move Up / Move Down pair in the row's context menu is the
/// same answer said in words for the readers a drag has nothing to offer. See
/// ``grip(for:)`` for why the grip had to become a control of its own, and
/// ``dropZones(for:)`` for where a dragged row lands.
struct ChecklistView: View {
    struct Metrics {
        var box: CompletionToggle.Metrics
        var rowSpacing: CGFloat
        /// The gap *between* rows. Named rather than left as a ternary in the
        /// body because the drop zones are measured against it: each row's two
        /// halves reach ``dropReach`` past it at either end, so one row's meet
        /// the next one's in the middle of the gap and a pointer between two
        /// rows is over one of them rather than over neither.
        var rowGap: CGFloat
        var rowVerticalPadding: CGFloat
        var rowHorizontalPadding: CGFloat
        /// The row's floor. Touch needs 44pt; a desk row sizes to its text.
        var rowMinHeight: CGFloat
        var rowRadius: CGFloat
        var font: CGFloat
        var showsRowHover: Bool
        /// Whether a row carries its own `×`. A pointer reveals it on hover; a
        /// touch surface reaches delete by sliding the row aside — see
        /// ``deleteRevealWidth`` — rather than spending 44pt of row on a
        /// control that is nearly always idle.
        var showsInlineDelete: Bool
        var deleteGlyph: CGFloat
        /// How much row a swipe toward the leading edge slides aside, which is
        /// the width of the delete button it uncovers. 0 is no swipe at all —
        /// the desk, whose `×` is on the row already and where a sideways drag
        /// over text means selection.
        var deleteRevealWidth: CGFloat
        /// How far the box's touch square is allowed to spill past the space the
        /// row gives it. The 44pt target lands inside the row's own padding
        /// rather than pushing the text across and the row down, so raising it
        /// moves nothing that is drawn.
        var boxOverhang: CGFloat
        /// The floor the row's text field claims, and how much of that claim it
        /// hands straight back. A field publishes an accessibility element the
        /// size of the text it draws — 21pt in a 44pt row — and no frame around
        /// it moves that; the field has to claim the height itself and name the
        /// shape. `fieldOverhang` is `boxOverhang`'s trick for the consequence:
        /// the claim would otherwise push the row past the height it draws.
        var fieldHit: CGFloat
        var fieldOverhang: CGFloat
        /// The room the field keeps at the end of a line for the insertion
        /// point, handed back to it as width.
        ///
        /// **This is the empty second line.** A `TextField(axis: .vertical)`
        /// wraps its text 4pt before the trailing edge of its frame and *draws*
        /// it to the edge, so a sub-task whose text ends inside that 4pt band
        /// is measured at two lines and drawn on one. The row grows by a whole
        /// line, the words sit at the top of it, and the box and the grip —
        /// which centre on the row — slide down past the text they belong to.
        /// It reads as arbitrary because it is a band and not a threshold: two
        /// sub-tasks of quite different lengths can both be caught at one
        /// window width and neither at the next, which is what makes it look
        /// like the long ones are wrapping for no reason.
        ///
        /// **4 is measured, not guessed.** The field's height was compared
        /// against the same string's `Text` height at every width from 200 to
        /// 460pt, over five strings, in a bundled face and the system one
        /// alike: the mismatch is exactly 4pt wide at every wrap point. Handing
        /// the field 4pt of width it does not claim puts its wrap back on the
        /// claim's trailing edge, so the text still stops where it always did
        /// and the row is as tall as the lines it actually draws. At 3.5 a
        /// sliver of the band survives; at 4.5 the field starts keeping text on
        /// a line `Text` would have wrapped, which is the same fault pointing
        /// the other way.
        ///
        /// The same number on both surfaces — it is the field's own reserve
        /// rather than anything about the row's size. The phone shows less of
        /// it than the desk does: a sheet row has ``rowMinHeight`` 44 under it,
        /// which a second claimed line clears by only a couple of points.
        var fieldCaretGutter: CGFloat
        /// The reorder grip at the trailing end of every row: the glyph as
        /// drawn, the square it claims, and how much of that claim it hands
        /// straight back. `gripOverhang` is `boxOverhang`'s trick for
        /// `boxOverhang`'s reason — a 44pt target that took its full width
        /// would push the text across and the row down.
        var gripGlyph: CGFloat
        var gripHit: CGFloat
        var gripOverhang: CGFloat
        /// The corner the stand-in's dashed edge follows. Its own number rather
        /// than `rowRadius`, which is the *hover* background's and is 0 on
        /// touch, where there is no hover and so nothing to round — a dashed
        /// outline with square corners round a rounded row reads as a crop mark.
        var standInRadius: CGFloat

        /// How far each row's drop halves spill past it, which is half the gap
        /// so that the two rows either side of a gap tile it exactly. Overlap
        /// would work too, but which of two overlapping destinations takes a
        /// drop is a z-order question, and a boundary nobody can point at is
        /// worse than one that is a hair thin.
        var dropReach: CGFloat { rowGap / 2 }

        /// The width the grip takes in the row, which the add row below the
        /// list holds open so its draft field ends where the rows' fields do.
        var gripReserve: CGFloat { gripHit - 2 * gripOverhang }

        /// Whether this surface deletes by swipe, said as the question the
        /// call sites ask rather than as a second flag that could disagree
        /// with the width.
        var swipesToDelete: Bool { deleteRevealWidth > 0 }

        static let desk = Metrics(
            box: .deskRow, rowSpacing: 9, rowGap: 2,
            rowVerticalPadding: 6, rowHorizontalPadding: 8, rowMinHeight: 0,
            rowRadius: 9, font: 12.5,
            showsRowHover: true, showsInlineDelete: true, deleteGlyph: 9.5,
            deleteRevealWidth: 0,
            boxOverhang: 0, fieldHit: 0, fieldOverhang: 0, fieldCaretGutter: 4,
            gripGlyph: 10, gripHit: 18, gripOverhang: 0, standInRadius: 9
        )
        static let sheet = Metrics(
            box: .sheetRow, rowSpacing: 11, rowGap: 0,
            rowVerticalPadding: 6, rowHorizontalPadding: 8, rowMinHeight: 44,
            rowRadius: 0, font: 14,
            showsRowHover: false, showsInlineDelete: false, deleteGlyph: 13,
            deleteRevealWidth: 64,
            boxOverhang: 7, fieldHit: 44, fieldOverhang: 6, fieldCaretGutter: 4,
            gripGlyph: 14, gripHit: 44, gripOverhang: 7, standInRadius: 10
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    let scope: DetailScope
    var metrics: Metrics = .desk

    /// Which row holds the keyboard, and which task that row belongs to: a
    /// detail surface can be re-pointed at another card mid-edit, and the
    /// session has to be closed against the task it was opened on.
    @FocusState private var focusedRow: SubTask.ID?
    @State private var focusOwnerID: TaskItem.ID?
    @FocusState private var isDraftFocused: Bool
    @State private var hoveredRow: SubTask.ID?
    /// The swipe-to-delete session, where the surface has one — see
    /// ``Metrics/swipesToDelete``: the row settled aside with its delete
    /// button showing, the row a finger is carrying sideways right now, and
    /// how far it has come. Surface state like the reorder drag's, and for the
    /// same reason: an open button is a fact about this checklist, not about
    /// the board.
    @State private var revealedRow: SubTask.ID?
    @State private var swipingRow: SubTask.ID?
    @State private var swipeTranslation: CGFloat = 0
    /// The row that has left the ground, and the gap the drop is aimed at.
    /// Both are session state rather than board state: what is being carried is
    /// a fact about this surface, and the desk can be showing the same card in
    /// a second window.
    @State private var draggingRow: SubTask.ID?
    @State private var dropCaret: SubtaskCaret?
    /// How many of this checklist's drop zones have the drag under them, and
    /// which lift they belong to. Together they are how a drag that ended
    /// *without* a drop is noticed on a build whose drag session does not
    /// announce it — see ``targeting(_:)``.
    @State private var zonesTargeted = 0
    @State private var lifts = 0
    /// Which row the current run of payload asks belongs to.
    ///
    /// **A latch that outlives the drag by a beat**, and that is the whole
    /// difference between it and `draggingRow` — see ``lifted(_:)``, which is
    /// where the beat is paid for and why.
    @State private var liftedRow: SubTask.ID?
    /// Bumped by the box and by nothing else, which is what the feedback is
    /// for: derived state — the row's `done` flags — also changes when the
    /// surface is re-pointed at another card, and a tick nobody made is worse
    /// than silence.
    ///
    /// **Only the box that *re-opens* a row bumps this.** Ticking one closed is
    /// finishing something, and it is announced by the store and tapped by
    /// `CompletionFeedback` in the same breath as the chime — the card's own
    /// `.success`, which is what a finger that finished a step should feel. Two
    /// taps for the one tap is what counting both directions here would give.
    @State private var reopens = 0

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowGap) {
            if standInIndex == 0 { standIn }
            ForEach(Array(task.subtasks.enumerated()), id: \.element.id) { position, subtask in
                row(for: subtask)
                // After this row, which is the gap the stand-in opens when it is
                // the row *following* this one.
                if standInIndex == position + 1 { standIn }
            }
            addRow
        }
        .onChange(of: focusedRow) { previous, current in
            if let previous, let owner = focusOwnerID {
                store.endEditing(.subtask, on: owner, scope: scope, subtask: previous)
            }
            focusOwnerID = current == nil ? nil : task.id
            if let current {
                store.beginEditing(.subtask, on: task.id, scope: scope, subtask: current)
                // A row taking the keyboard puts any open delete button away:
                // the row tap already trades focus for the put-away, but a tap
                // that lands on a field goes to the field directly, and typing
                // into a row standing half aside is nobody's intent.
                if revealedRow != nil { settleSwipe(open: nil) }
            }
        }
        // **A draft with something in it is a sub-task, whether or not Return
        // was pressed.** Leaving the field — tapping a row above, the note, the
        // board behind — used to abandon what had been typed to a draft nobody
        // could see was still there, so the row a person had watched themselves
        // write simply was not on the list. Losing focus now does what Return
        // does, minus the one part Return is *for*: the field is not asked back,
        // because a hand that left it meant to leave.
        //
        // **An empty draft still makes nothing**, which is the whole of the
        // exception: `addSubtask` trims and refuses blank, so a field somebody
        // only tapped commits nothing and keeps whatever whitespace it had.
        // That is also what makes the second call after Return harmless — the
        // submit handler has already committed and emptied the draft by the time
        // the field resigns, so this finds nothing left to add.
        .onChange(of: isDraftFocused) { _, isFocused in
            guard !isFocused else { return }
            store.commitSubtaskDraft(for: scope, task: task.id)
        }
        .onChange(of: task.id) { previousID, _ in
            endFocusedSession(on: previousID)
            focusedRow = nil
            // Nothing left to carry either: a caret still lit would be naming a
            // row in a list that has gone, and the zones would be over the new
            // card's rows taking the taps that focus them.
            endDrag()
        }
        // A surface torn down mid-edit takes the field out of the hierarchy, and
        // a session left open never logs the rename and never restores a row
        // emptied to whitespace.
        .onDisappear { endFocusedSession(on: focusOwnerID) }
        // Ticking a row was the one gesture in the sheet with nothing to feel
        // (5.8). Closing one is `CompletionFeedback`'s now, at the card's own
        // `.success` — see `subtaskCompleted`. This is the other direction, where
        // nothing has been finished and `.selection` is the whole of what a value
        // changing is worth.
        .sensoryFeedback(.selection, trigger: reopens)
    }

    private func endFocusedSession(on owner: TaskItem.ID?) {
        if let row = focusedRow, let owner, owner == focusOwnerID {
            store.endEditing(.subtask, on: owner, scope: scope, subtask: row)
        }
        focusOwnerID = nil
    }

    private func row(for subtask: SubTask) -> some View {
        swipeToDelete(rowSurface(subtask), for: subtask)
            // The row in the air stays where it is until the drop lands, and says
            // so by going faint. Its copy in the gap is what has to be read while
            // the drag is in flight; two rows at full strength would be two rows.
            .opacity(draggingRow == subtask.id ? StandIn.inTheAir : 1)
            // Where a dragged row would land, drawn in the gap it would land in
            // rather than on a row it would not.
            .overlay { dropZones(for: subtask) }
    }

    /// The row as it sits on the surface — everything that slides when a swipe
    /// takes hold of it, which is why the drop zones and the dimming are
    /// applied outside, on ``row(for:)``: a gap in the list does not move
    /// because one row is standing aside.
    private func rowSurface(_ subtask: SubTask) -> some View {
        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            rowContent(subtask)
                // **On the row's content, and pointedly not on the grip.** A
                // context menu is opened by a long press, and a long press on
                // the grip is how a drag begins on touch — so with this on the
                // whole row, taking hold of the handle put the menu on screen
                // over the drag that was starting. Reported from a phone, and
                // the note that used to sit here claimed the opposite: the
                // simulator's drag did start, so the menu going up as well was
                // never visible in a test that only asked where the row landed.
                //
                // Everything *else* about the row keeps it: the box, the text,
                // the delete control and the slack between them. What is lost is
                // the 8pt of padding outside this group, which is the price of
                // the handle having a gesture of its own.
                .contextMenu {
                    reorderItems(for: subtask)
                    // Only when there is something above it: a lone row has no
                    // reorder items, and a separator with nothing on one side of
                    // it is a line.
                    if task.subtasks.count > 1 { Divider() }
                    Button(role: .destructive) {
                        store.deleteSubtask(subtask.id, from: task.id)
                    } label: {
                        Label("Delete Sub-task", systemImage: "trash")
                    }
                }
            grip(for: subtask)
        }
        .padding(.vertical, metrics.rowVerticalPadding)
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .frame(minHeight: metrics.rowMinHeight)
        // A field's own hit area is the text it draws — 21pt inside a 44pt
        // row — so the slack the row keeps for a finger has to hand focus over,
        // the way `addRow` does. The box, the delete control, the grip and the
        // text itself sit in front of this shape and still take their own taps.
        .contentShape(.rect)
        // A tap with a delete button open anywhere in the list puts the button
        // away instead of doing what it says — the bargain every swipe-to-
        // delete on the platform makes, so a finger aiming at a row it cannot
        // see is half-covered never focuses something by mistake.
        .onTapGesture {
            // `swipingRow` too, not just the settled button: a drag the system
            // cancelled mid-flight never reaches `onEnded`, and this tap is
            // how a row left mid-slide comes home rather than taking focus.
            if revealedRow == nil, swipingRow == nil {
                focusedRow = subtask.id
            } else {
                settleSwipe(open: nil)
            }
        }
        .hoverBackground(metrics.showsRowHover ? palette.ink(0.05) : .clear, radius: metrics.rowRadius)
        .onHover { isInside in
            if isInside { hoveredRow = subtask.id } else if hoveredRow == subtask.id { hoveredRow = nil }
        }
    }

    /// Everything in a row except the grip — which is to say, everything the
    /// row's context menu is allowed to open from.
    private func rowContent(_ subtask: SubTask) -> some View {
        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            CompletionToggle(isDone: subtask.done, metrics: metrics.box) {
                // Read before the toggle, which is what this row still holds:
                // the value came out of `task.subtasks` when the row was drawn,
                // and the store's write does not reach back into it. Done
                // already means this press re-opens the row — the one direction
                // `subtaskCompleted` says nothing about, and so the one this has
                // to speak for.
                let reopening = subtask.done
                store.toggleSubtask(subtask.id, on: task.id)
                if reopening { reopens += 1 }
            }
            .padding(-metrics.boxOverhang)

            // The vertical axis wraps a long sub-task instead of clipping it
            // mid-sentence; `updateSubtask` folds whitespace, so a newline
            // cannot reach the row's text. Return on such a field never fires
            // `.onSubmit`, so `.onKeyPress` ends the session in its place —
            // the same trade the inspector's title field makes, spelled out
            // there. The *draft* row below keeps its single axis on purpose:
            // its Return commits and re-arms, a flow the software keyboard has
            // to keep, and a draft scrolls while it is typed rather than
            // truncating.
            TextField("Sub-task", text: textBinding(for: subtask), axis: .vertical)
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.font, .semibold, relativeTo: .footnote))
                .foregroundStyle(subtask.done ? palette.inkText(0.4) : palette.ink(0.8))
                .strikethrough(subtask.done, color: palette.ink(0.4))
                .focused($focusedRow, equals: subtask.id)
                .onKeyPress(.return) {
                    focusedRow = nil
                    return .handled
                }
                .onSubmit { focusedRow = nil }
                .frame(maxWidth: .infinity, minHeight: metrics.fieldHit, alignment: .leading)
                .contentShape(.accessibility, Rectangle())
                .padding(.vertical, -metrics.fieldOverhang)
                // `boxOverhang`'s trick a third time, sideways: the field
                // measures and draws 4pt wider than the row gives it, which is
                // exactly the reserve it wraps early by. Nothing moves —
                // the text stops where it always did — but a row is now as tall
                // as the lines it draws rather than the lines it planned for.
                // See ``Metrics/fieldCaretGutter``.
                .padding(.trailing, -metrics.fieldCaretGutter)
                // A placeholder is not a name, and this one is gone the moment
                // the row has any text — which is every row a reader meets.
                .accessibilityLabel("Sub-task")

            if metrics.showsInlineDelete {
                deleteButton(for: subtask)
            }
        }
        // So the menu opens from the whole of this group rather than only from
        // the controls in it: the gaps between a box, a line of text and a
        // hover-hidden `×` are most of a row's width.
        .contentShape(.rect)
    }

    /// Move Up / Move Down for one row: the drag's answer, said in words, and
    /// the only route VoiceOver and Switch Control have to it — the only other
    /// way to move a row is to lift it by the grip, and a long-press lift is
    /// unreachable to both.
    ///
    /// These are the last two callers of `dropOffset`, and rightly so: a menu
    /// item names the row it is moving *past*, which is exactly the row-into-a-gap
    /// question that rule answers, and here the direction of travel is stated
    /// rather than guessed at. The drag went to a caret instead — see
    /// ``BoardStore/dropSubtask(_:on:at:)``.
    @ViewBuilder
    private func reorderItems(for subtask: SubTask) -> some View {
        if let index = task.subtasks.firstIndex(where: { $0.id == subtask.id }) {
            if index > 0 {
                Button {
                    move(from: index, to: index - 1)
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
            }
            if index + 1 < task.subtasks.count {
                Button {
                    move(from: index, to: index + 1)
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
            }
        }
    }

    private func move(from: Int, to: Int) {
        store.moveSubtask(
            fromOffsets: IndexSet(integer: from),
            toOffset: BoardStore.dropOffset(from: from, to: to),
            on: task.id
        )
    }

    private func deleteButton(for subtask: SubTask) -> some View {
        Button {
            store.deleteSubtask(subtask.id, from: task.id)
        } label: {
            Image(systemName: "xmark")
                .font(palette.ui(metrics.deleteGlyph, .bold, relativeTo: .caption2))
                .fontWeight(.bold)
                .foregroundStyle(palette.inkText(0.4))
                .frame(width: metrics.box.hitSize, height: metrics.box.hitSize)
        }
        .bareButton()
        .opacity(hoveredRow == subtask.id ? 1 : 0)
        // Invisible is not the same as absent: without this the dead corner of
        // an unhovered row still deletes what is in it.
        .allowsHitTesting(hoveredRow == subtask.id)
        .accessibilityHidden(hoveredRow != subtask.id)
        .accessibilityLabel("Delete sub-task")
    }

    // MARK: Delete by swipe

    /// A touch row slid toward the leading edge uncovers its delete button —
    /// the pointer's hover-`×`, for the surfaces where there is no hover and
    /// where ``Metrics/showsInlineDelete`` decided against a control that is
    /// nearly always idle. The context menu keeps its Delete Sub-task: the
    /// menu is the route VoiceOver has, and a swipe is not a gesture it can
    /// perform.
    ///
    /// **The scroll view is not fought for the drag.** The sheet and the
    /// inspector both scroll vertically, and a vertical pan is theirs before
    /// this gesture sees it; what reaches the row is the sideways movement a
    /// vertical scroll view has no claim on, and the dominance check in
    /// ``swipeGesture(for:)`` turns away whatever diagonal slips through.
    /// `TaskListView` chose a `List` to get `swipeActions` for free rather
    /// than make this bargain; this list is a `VStack` for the reorder drag's
    /// sake and has no such offer to take.
    ///
    /// **Clipped, because the row slides and the card does not.** The sheet
    /// draws the checklist on a card with 6pt of margin; a row slid 64pt
    /// leading would cross the card's edge and keep going. `.clipped()` cuts
    /// the drawing at the row's own frame — hit testing is untouched, so the
    /// box's and the grip's overhung touch targets keep their spill.
    @ViewBuilder
    private func swipeToDelete(_ row: some View, for subtask: SubTask) -> some View {
        if metrics.swipesToDelete {
            row
                .offset(x: -swipeReveal(for: subtask.id) * revealSign)
                .clipped()
                .background(alignment: .trailing) { deleteReveal(for: subtask) }
                .gesture(swipeGesture(for: subtask))
        } else {
            row
        }
    }

    /// Which way "aside" is, as a sign on the x axis. The button parks at the
    /// trailing edge and the row slides the other way — semantic directions —
    /// but `.offset` and a drag's translation are both absolute, so the flip
    /// is done by hand off `layoutDirection`, the way `EdgePan` flips its
    /// distances: everything below works in "points of button uncovered" and
    /// only this sign knows which way that is on screen.
    private var revealSign: CGFloat { layoutDirection == .rightToLeft ? -1 : 1 }

    /// How much of `id`'s delete button is uncovered: the button's width for
    /// the row settled open, the drag in flight for the row under a finger,
    /// and 0 for every other row. Dragged past the button, the row keeps a
    /// third of the finger's movement — far enough to feel held rather than
    /// stopped, and nothing like far enough to read as a fuller swipe meaning
    /// something more, which on this platform would be delete-without-asking.
    private func swipeReveal(for id: SubTask.ID) -> CGFloat {
        let settled: CGFloat = revealedRow == id ? metrics.deleteRevealWidth : 0
        guard swipingRow == id else { return settled }
        let dragged = settled - swipeTranslation * revealSign
        if dragged < 0 { return 0 }
        if dragged > metrics.deleteRevealWidth {
            return metrics.deleteRevealWidth + (dragged - metrics.deleteRevealWidth) / 3
        }
        return dragged
    }

    private func swipeGesture(for subtask: SubTask) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if swipingRow != subtask.id {
                    // Claimed only once the movement is more across than down.
                    // The scroll view has usually settled the question already;
                    // this is for the diagonal it let go.
                    guard abs(value.translation.width) > abs(value.translation.height)
                    else { return }
                    // Taking hold of one row puts away whichever other row was
                    // standing open: one button on screen is a state a reader
                    // can hold, two is a puzzle.
                    if let open = revealedRow, open != subtask.id {
                        Motion.run(Self.swipeSettle, reduceMotion: reduceMotion) {
                            revealedRow = nil
                        }
                    }
                    swipingRow = subtask.id
                }
                swipeTranslation = value.translation.width
            }
            .onEnded { value in
                guard swipingRow == subtask.id else { return }
                // Judged on where the flick was heading rather than where the
                // finger let go, so a short sharp swipe opens the button and a
                // short sharp shove closes it.
                let settled: CGFloat = revealedRow == subtask.id ? metrics.deleteRevealWidth : 0
                let landing = settled - value.predictedEndTranslation.width * revealSign
                settleSwipe(open: landing > metrics.deleteRevealWidth / 2 ? subtask.id : nil)
            }
    }

    /// The swipe coming to rest — open on `id`'s button, or closed on `nil` —
    /// with the settle animated because the row is travelling the rest of the
    /// way on its own.
    private func settleSwipe(open id: SubTask.ID?) {
        Motion.run(Self.swipeSettle, reduceMotion: reduceMotion) {
            revealedRow = id
            swipingRow = nil
            swipeTranslation = 0
        }
    }

    /// The same put-away, unanimated, for the paths where the row is leaving
    /// the screen or the list anyway: a delete, a reorder lift, the surface
    /// re-pointed at another card.
    private func closeSwipe() {
        revealedRow = nil
        swipingRow = nil
        swipeTranslation = 0
    }

    private static let swipeSettle: Animation = .snappy(duration: 0.2)

    /// The delete button the swipe uncovers, parked behind the row's trailing
    /// edge and shown by the row moving off it rather than by appearing.
    /// `dueTone`'s overdue red because `Palette` has no danger semantic of its
    /// own yet — the borrow the sheet's Trash Task row makes (C2), and the
    /// same argument here.
    ///
    /// **Uncovered by a mask, not by the row.** A touch row has no fill of its
    /// own — the card's ground runs through it — so a button parked behind it
    /// was never behind anything: every row wore its delete button at rest,
    /// drawn over the grip, which is how it was reported from a phone. The
    /// mask is the width the row has moved aside, so the button appears from
    /// under the row's trailing edge exactly as it would from under an opaque
    /// one, and is nothing at all at rest. It reads the same value as the
    /// row's offset, so the two travel on the same animation.
    /// `ChecklistSwipeTests` renders a row at rest and looks for the tone.
    ///
    /// Hit-testable and readable only while its row stands open: invisible is
    /// not the same as absent, which is the hover-`×`'s lesson — without the
    /// gate, the covered button would be a live delete under the grip.
    private func deleteReveal(for subtask: SubTask) -> some View {
        let tone = palette.dueTone(urgency: .overdue, isDone: false)
        let uncovered = swipeReveal(for: subtask.id)
        return Button {
            store.deleteSubtask(subtask.id, from: task.id)
            closeSwipe()
        } label: {
            Image(systemName: "trash")
                .font(palette.ui(metrics.deleteGlyph, .semibold, relativeTo: .caption))
                .foregroundStyle(tone.foreground)
                .frame(width: metrics.deleteRevealWidth)
                .frame(maxHeight: .infinity)
                .background(tone.background, in: .rect(cornerRadius: metrics.standInRadius))
        }
        .bareButton()
        .mask(alignment: .trailing) { Rectangle().frame(width: uncovered) }
        .allowsHitTesting(revealedRow == subtask.id)
        .accessibilityHidden(revealedRow != subtask.id)
        .accessibilityLabel("Delete sub-task")
    }

    // MARK: Re-ordering by drag

    /// **The grip.** A control of its own rather than the row, which is the
    /// change 6.6 made and the reason the drag worked nowhere before it.
    ///
    /// The row *was* the grip, on the bargain that a drag begun inside the field
    /// belongs to the field and everything else starts a reorder. What that left
    /// was 8pt of padding at either end and the tick's square — and the tick is a
    /// button, which takes the press first. Measured on an iPhone: a press-and-
    /// drag on the gutter moved nothing at all, and a press-and-drag on the row's
    /// text ran the *field's* own drag instead and dropped "Lift + shadow states"
    /// into the middle of "Keyboard fallback". So the gesture was not merely
    /// unreachable on touch, it was destructive. The desk had the same geometry
    /// and the same 8pt to aim at.
    ///
    /// So the grip is a thing on the screen now, at the trailing end of the row
    /// where a list's reorder handle belongs, and the drag starts on it and
    /// nowhere else. It is drawn on both platforms and at all times: it is the
    /// only affordance a reorder has, and a control revealed on hover — which is
    /// the bargain the `×` beside it makes — cannot be discovered by a finger.
    ///
    /// Hidden from accessibility because a drag is not something VoiceOver or
    /// Switch Control can perform: what they get is Move Up / Move Down in the
    /// row's context menu, which is why those exist and what ``reorderItems(for:)``
    /// says from there.
    private func grip(for subtask: SubTask) -> some View {
        gripGlyph
            // `draggable` takes its payload as an autoclosure, so this is
            // evaluated when the *session* starts and not when the row is drawn
            // — which keeps the text on the payload current after an edit two
            // rows up.
            .draggable(lifted(subtask))
            // Where a drag begins and ends, on the builds that say so.
            .modifier(SubtaskDragSession(
                begin: { beginLift(subtask.id) },
                end: endLift
            ))
            .accessibilityHidden(true)
    }

    /// The grip as drawn, which the stand-in borrows: a row's promise has to be
    /// the width the row will be, and the grip is part of that width.
    private var gripGlyph: some View {
        Image(systemName: "line.3.horizontal")
            .font(palette.ui(metrics.gripGlyph, .semibold, relativeTo: .caption2))
            .foregroundStyle(palette.inkText(0.32))
            .frame(width: metrics.gripHit, height: metrics.gripHit)
            // An image's own shape is the glyph, which on touch is a target the
            // width of three thin lines. The square is what is being aimed at.
            .contentShape(.rect)
            .padding(-metrics.gripOverhang)
    }

    /// The payload — and, where there is no better signal, the lift as well.
    ///
    /// **The payload ask is a poor thing to hang a lift on**, and two reported
    /// bugs came out of doing it. SwiftUI does not ask `.draggable` for its
    /// payload once: it asks for the drag preview, and again as the view updates
    /// under the finger, and it keeps asking *through the drop* while the rows
    /// reorder. So the asks have to be de-duplicated by hand, and every latch
    /// that does it is a guess about when one drag stopped and the next began —
    /// a guess that showed first as a row left faded after it landed, and then
    /// as a second drag that never armed at all, the handle coming away from a
    /// row that stayed where it was.
    ///
    /// **So where the drag session announces itself, it is the authority** —
    /// `onDragSessionUpdated` reports `.initial` exactly once per session, which
    /// is what a lift is. See ``SubtaskDragSession``, and
    /// ``BoardStore/announcesDragEnd`` for which builds have it: macOS 26, but
    /// iOS **27**. Only iOS 26 has nothing else to go on, and only there does
    /// the latch below run — a narrower place for a guess to live.
    private func lifted(_ subtask: SubTask) -> SubtaskTransfer {
        if !BoardStore.announcesDragEnd {
            let id = subtask.id
            // Deferred a turn, because the ask lands inside a view update and
            // this writes the state the checklist is drawn from.
            Task { @MainActor in
                guard liftedRow != id else { return }
                beginLift(id)
            }
        }
        return SubtaskTransfer(subtask, on: task.id)
    }

    /// A row has left the ground, and the number of the lift that says so.
    ///
    /// **Every lift is numbered, and every deferred answer carries its number.**
    /// That is what stops a signal belonging to one drag from landing on the
    /// next: the expiry below, the settle in ``targeting(_:)`` and the session's
    /// own end in ``endLift(_:)`` all check the drag they were told about is
    /// still the drag in hand. A stale one is dropped rather than obeyed.
    ///
    /// The carried state is reset here rather than only on the way out, so a
    /// caret or a count left over from a drag that ended untidily cannot be read
    /// as belonging to this one.
    @discardableResult
    private func beginLift(_ id: SubTask.ID) -> Int {
        lifts += 1
        liftedRow = id
        draggingRow = id
        dropCaret = nil
        zonesTargeted = 0
        // A lifted row takes its delete button with it: the stand-in copies
        // the row as drawn, and a copy standing 64pt aside would be a promise
        // about a control the drop does not deliver.
        closeSwipe()
        let lift = lifts
        // The last resort, for a drag that ends without anything saying so —
        // which after this change is only possible on a build with no session
        // callback. `BoardStore.beginDrag` keeps the same backstop for the same
        // reason, and accepts the same cost: a dimmed row and nothing more.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(BoardStore.liftExpiry))
            if lifts == lift, draggingRow == id { endDrag() }
        }
        return lifts
    }

    /// The end of the drag numbered `lift`, from the session that began it.
    ///
    /// Refused when a later lift owns the screen: a session's closing callbacks
    /// can arrive after the *next* drag has started, and obeying one of those is
    /// how a live drag gets shut down under the finger — the row stops
    /// responding, the gap closes, and the handle appears to come away from what
    /// it was carrying.
    private func endLift(_ lift: Int) {
        guard lift == lifts else { return }
        endDrag()
    }

    private func endDrag() {
        draggingRow = nil
        dropCaret = nil
        zonesTargeted = 0
        // Which also covers the surface being re-pointed at another card —
        // `onChange(of: task.id)` routes through here, and a button left open
        // would name a row on the list that has gone.
        closeSwipe()
        releaseLatch()
    }

    /// Opens ``liftedRow`` again, a beat after the drag it belonged to ended.
    ///
    /// Only the no-callback path consults it — see ``lifted(_:)`` — but it is
    /// released on every path, so that a build which starts announcing its drag
    /// sessions does not leave a latch shut behind it. The beat has to outlast
    /// the trailing payload asks a drop shakes loose, a frame or two, and end
    /// well inside the half second a long press takes, so the next real pick-up
    /// is never the one that gets swallowed.
    private func releaseLatch() {
        guard let id = liftedRow else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.latchSettle))
            if liftedRow == id { liftedRow = nil }
        }
    }

    private static let latchSettle: TimeInterval = 0.25

    /// Counts the zones holding the drag, and calls the drag over when none of
    /// them is.
    ///
    /// **This is what pays for the caret being claimed and never given back.**
    /// A zone that cleared the caret on the way out cannot coexist with a
    /// stand-in: the stand-in opens in the gap the zone just named, which moves
    /// the rows and puts the pointer *inside the stand-in* — and then the zone
    /// that was left fires its `false` and shuts the gap it asked for, the rows
    /// spring back, the zone under the pointer names the same gap again, and the
    /// two trade places at the frame rate. So nothing clears on the way out, and
    /// the drag being over is established here instead. `BoardTaskCard.dropZone`
    /// and ``BoardStore/dragTargeting(_:)`` are the same two halves of the same
    /// bargain.
    ///
    /// **Only where the drag session does not say.** On macOS, and on iOS 27
    /// and after, `onDragSessionUpdated` reports the end exactly — see
    /// ``BoardStore/announcesDragEnd`` — and inferring it from a settle timer as
    /// well would race the real answer. iOS 26 has no such report, which is why
    /// this exists rather than being deleted in favour of the modifier.
    private func targeting(_ targeted: Bool) {
        zonesTargeted = targeted ? zonesTargeted + 1 : max(0, zonesTargeted - 1)
        guard !BoardStore.announcesDragEnd, !targeted, zonesTargeted == 0, draggingRow != nil
        else { return }
        let lift = lifts
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(BoardStore.dragSettle))
            guard lifts == lift, zonesTargeted == 0, draggingRow != nil else { return }
            endDrag()
        }
    }

    /// The row's two halves, as separate insertion targets: the top half means
    /// *above this sub-task*, the bottom half means *below it*. The board's cards
    /// and the settings sheet's columns do the same, and the notes there are the
    /// notes here — halves because a drop that names a *row* can only mean a gap
    /// by guessing which way the drag came from, and only while something is in
    /// the air because otherwise they take the tap that focuses the row.
    ///
    /// **Over the row rather than behind it**, which matters more here than it
    /// does for a column: the row is mostly `TextField`, and a text field accepts
    /// a plain-text drop. `SubtaskTransfer` offers its text as one — see its
    /// `ProxyRepresentation` — so a zone behind the field would let a row dragged
    /// onto another row be pasted into it instead of moved above it. A drop stops
    /// at whatever is in front.
    @ViewBuilder private func dropZones(for subtask: SubTask) -> some View {
        if draggingRow != nil {
            VStack(spacing: 0) {
                dropZone(.above(subtask.id))
                dropZone(.below(subtask.id))
            }
            .padding(.vertical, -metrics.dropReach)
        }
    }

    private func dropZone(_ caret: SubtaskCaret) -> some View {
        Color.clear
            .contentShape(.rect)
            .dropDestination(for: SubtaskTransfer.self) { items, _ in
                defer { endDrag() }
                guard let dropped = items.first else { return false }
                return store.dropSubtask(dropped, on: task.id, at: caret)
            } isTargeted: { targeted in
                targeting(targeted)
                // Claimed on the way in and **not** given up on the way out —
                // see ``targeting(_:)`` for the loop that a clear here starts.
                if targeted { dropCaret = caret }
            }
    }

    // MARK: The row that is not there yet

    /// Which row of the list as drawn the stand-in is, or `nil` for none on the
    /// way. ``BoardStore/subtaskDropIndex(_:on:at:)`` is where the answer is
    /// worked out; the list only makes room for it.
    private var standInIndex: Int? {
        guard let draggingRow, let dropCaret else { return nil }
        return store.subtaskDropIndex(draggingRow, on: task.id, at: dropCaret)
    }

    /// **The row that is not there yet**: a faint copy of the sub-task being
    /// dragged, drawn in the gap it would drop into. ``DropPreviewCard`` is the
    /// board's and the Inbox's version of this, and the argument there is the
    /// argument here.
    ///
    /// **A row rather than a line.** The insertion point was a 2pt accent
    /// capsule on the edge of whichever row the gap was beside, which says
    /// *between these two* and leaves unanswered the question a reorder actually
    /// asks — *is this the row I am carrying, and where will it be when I let
    /// go*. A copy answers both at once: it is legibly that sub-task, tick and
    /// strikethrough and all, and it pushes its new neighbours apart by exactly
    /// what the real row is about to claim.
    ///
    /// **Faint, and dashed.** The rows either side of it are real and this one
    /// is a promise; at full strength it is a second copy of a row that already
    /// exists two lines up, which is worse than no mark at all. The original
    /// stays where it is, dimmed, until the drop lands — see the `opacity` on
    /// ``row(for:)``.
    ///
    /// **Drawn rather than built from the row**, which is the same stripping
    /// ``BoardTaskCard/standIn`` does and for the same reasons: a whole row
    /// would bring its own drop zones, a second `.draggable` for a sub-task
    /// already in the air, and a live `TextField` the keyboard could land in.
    /// The text is a `Text` for that last one — the tick and the grip come along
    /// because they are what the row *looks* like, and they are inert inside
    /// `allowsHitTesting(false)`.
    @ViewBuilder private var standIn: some View {
        if let id = draggingRow, let caret = dropCaret,
           let subtask = task.subtasks.first(where: { $0.id == id }) {
            standInRow(subtask)
                .overlay { standInGap(at: caret) }
                // A stable identity across the positions it moves between, so
                // SwiftUI carries one view from gap to gap rather than tearing
                // down and rebuilding a row on every crossing.
                .id(Self.standInID)
        }
    }

    private func standInRow(_ subtask: SubTask) -> some View {
        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            CompletionToggle(isDone: subtask.done, metrics: metrics.box) {}
                .padding(-metrics.boxOverhang)

            Text(store.subtaskText(subtask.id, on: task.id))
                .font(palette.ui(metrics.font, .semibold, relativeTo: .footnote))
                .foregroundStyle(subtask.done ? palette.inkText(0.4) : palette.ink(0.8))
                .strikethrough(subtask.done, color: palette.ink(0.4))
                .frame(maxWidth: .infinity, minHeight: metrics.fieldHit, alignment: .leading)
                .padding(.vertical, -metrics.fieldOverhang)

            // The delete `×`'s square, held open and empty: it is in the real
            // row's layout at every moment — hidden by opacity, not by absence
            // — so a stand-in without it would be the one row in the list whose
            // text ran wider than the rest.
            if metrics.showsInlineDelete {
                Color.clear.frame(width: metrics.box.hitSize, height: 0)
            }
            gripGlyph
        }
        .padding(.vertical, metrics.rowVerticalPadding)
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .frame(minHeight: metrics.rowMinHeight)
        .opacity(StandIn.faintness)
        .overlay { StandIn.outline(cornerRadius: metrics.standInRadius, accent: palette.accent) }
        .allowsHitTesting(false)
        // A row that appears mid-gesture and vanishes on release is noise in a
        // list somebody is counting, and a reader moves rows with Move Up and
        // Move Down rather than by dragging them.
        .accessibilityHidden(true)
    }

    /// The drop this stand-in has been promising for as long as it has been on
    /// screen, and the claim that keeps it here.
    ///
    /// **It takes the drop, because by the time it is on screen it is what the
    /// pointer is over**: opening a gap moves the row below it down, and the
    /// pointer that was in that row's lower half is now in here. Applied outside
    /// `standInRow`, whose hit testing is off — a copy drawn inert is not
    /// something to hang a destination on.
    ///
    /// Sized out past itself by ``Metrics/dropReach`` at each end, exactly as a
    /// row's own halves are, so the stand-in's zone and its neighbours' meet in
    /// the middle of each gap and there is no strip between two rows belonging
    /// to nobody.
    private func standInGap(at caret: SubtaskCaret) -> some View {
        Color.clear
            .contentShape(.rect)
            .dropDestination(for: SubtaskTransfer.self) { items, _ in
                defer { endDrag() }
                guard let dropped = items.first else { return false }
                return store.dropSubtask(dropped, on: task.id, at: caret)
            } isTargeted: { targeted in
                targeting(targeted)
                // Re-asserted rather than merely kept: this is the zone the
                // pointer is in now, and saying so is what stops the gap being
                // retired out from under it.
                if targeted { dropCaret = caret }
            }
            .padding(.vertical, -metrics.dropReach)
    }

    private static let standInID = "checklist-drop-preview"

    private var addRow: some View {
        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            RoundedRectangle(cornerRadius: metrics.box.radius)
                .strokeBorder(
                    palette.ink(0.28),
                    style: StrokeStyle(lineWidth: metrics.box.borderWidth, dash: [2.5, 2.5])
                )
                .frame(width: metrics.box.size, height: metrics.box.size)
                .overlay {
                    Image(systemName: "plus")
                        .font(palette.ui(metrics.box.size * 0.5, .semibold, relativeTo: .caption2))
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.inkText(0.4))
                }
                .frame(width: metrics.box.hitSize, height: metrics.box.hitSize)
                .padding(-metrics.boxOverhang)

            TextField("Add new sub-task", text: subtaskDraftBinding)
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.font, .semibold, relativeTo: .footnote))
                .foregroundStyle(palette.ink)
                .focused($isDraftFocused)
                .frame(minHeight: metrics.fieldHit)
                .contentShape(.accessibility, Rectangle())
                .padding(.vertical, -metrics.fieldOverhang)
                .accessibilityLabel("Add new sub-task")
                .onSubmit {
                    store.commitSubtaskDraft(for: scope, task: task.id)
                    // Return **ends editing** — that is what it is for, and the
                    // rows above rely on it: theirs clears `focusedRow`. This
                    // one field is the exception, because a checklist is
                    // written as a list: the draft moves down under the
                    // sub-task it just made, and the next one is typed straight
                    // into it. Losing the keyboard there costs a click a line.
                    //
                    // Asked for on the far side of a yield, for the reason
                    // `focusWhenReady` gives: inside the submit handler is
                    // inside the turn that is about to resign the field.
                    Task { @MainActor in
                        await Task.yield()
                        isDraftFocused = true
                    }
                }
                .onKeyPress(.escape) {
                    // Only ours to swallow when there is something to clear —
                    // otherwise Escape belongs to whatever is presenting us.
                    guard !store.subtaskDraft(for: scope, task: task.id).isEmpty else { return .ignored }
                    store.setSubtaskDraft("", for: scope, task: task.id)
                    return .handled
                }

            // The grip's width, held open with nothing in it: there is no row
            // yet to re-order, and a draft whose field ran on past the trailing
            // edge of every field above it would read as a different column.
            Color.clear
                .frame(width: metrics.gripReserve, height: 0)
                .accessibilityHidden(true)
        }
        .padding(.vertical, metrics.rowVerticalPadding)
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .frame(minHeight: metrics.rowMinHeight)
        // The dashed box was decoration. It — and the rest of the row's slack —
        // is the field's tap target now; taps inside the field still belong to
        // the field, which is what puts the caret where it was aimed.
        .contentShape(.rect)
        .onTapGesture { isDraftFocused = true }
        .hoverBackground(metrics.showsRowHover ? palette.ink(0.05) : .clear, radius: metrics.rowRadius)
    }

    private func textBinding(for subtask: SubTask) -> Binding<String> {
        Binding(
            get: { store.subtaskText(subtask.id, on: task.id) },
            set: { store.updateSubtask(subtask.id, text: $0, on: task.id) }
        )
    }

    private var subtaskDraftBinding: Binding<String> {
        Binding(
            get: { store.subtaskDraft(for: scope, task: task.id) },
            set: { store.setSubtaskDraft($0, for: scope, task: task.id) }
        )
    }
}

/// Where a checklist drag begins and ends, on the builds that say so.
///
/// ``CardDragSession`` for a sub-task, and the same shape for the same reason:
/// `onDragSessionUpdated` is macOS 26 but iOS **27**, and this app runs on iOS
/// 26 — so where it exists it is the exact answer, and where it does not
/// `ChecklistView.lifted(_:)` and `targeting(_:)` have to infer both ends from
/// the payload asks and the drop zones letting go.
///
/// **Both ends, not just the far one.** This began as an end-of-drag callback
/// beside a lift inferred from the payload ask, and that split was the source of
/// two bugs: a payload is asked for many times per drag and goes on being asked
/// for through the drop, so the lift had to be de-duplicated by a latch, and
/// every version of that latch got the boundary between one drag and the next
/// slightly wrong. `.initial` arrives exactly once per session and needs no
/// latch at all.
///
/// **It carries the lift's number between the two**, which is what makes a late
/// closing callback harmless: the session holds the number it was given when it
/// started and hands it back at the end, and `ChecklistView.endLift(_:)` ignores
/// anything that does not belong to the drag in hand. Without that, a callback
/// arriving after the *next* drag had started would end that one instead.
private struct SubtaskDragSession: ViewModifier {
    /// Raises the lift and answers with its number.
    let begin: () -> Int
    /// Ends the lift of that number, if it is still the one in hand.
    let end: (Int) -> Void

    @State private var lift: Int?

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
                lift = begin()
            case .ended(let operation):
                // An operation that carries something is a drop, and the drop
                // handler is what clears up after it — running here as well
                // would shut the gap out from under a drop still landing.
                switch operation {
                case .copy, .move: break
                default: finish()
                }
            case .dataTransferCompleted:
                // The payload has been handed over. Almost always already
                // cleared by the drop handler; what is left for this to catch
                // is a drop that went through without moving the row.
                finish()
            default:
                break
            }
        }
    }

    /// Once per session, and only for a session this view actually started: the
    /// number is taken back on the way out so a second closing callback — and
    /// there are usually two — cannot be read as a second drag ending.
    private func finish() {
        guard let lift else { return }
        self.lift = nil
        end(lift)
    }
}
