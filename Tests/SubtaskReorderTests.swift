// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

/// Dropping a sub-task into the gap a caret names, which is what dragging a
/// checklist row by its grip does — see `grip(for:)` and `dropZones(for:)` in
/// `ChecklistView`.
///
/// **The row used to be the grip, and that is why this suite exists.** The
/// bargain was that a drag begun inside the row's text field belonged to the
/// field and everything else started a reorder; what "everything else" came to
/// was 8pt of padding at either end and the tick's square, and the tick is a
/// button that takes the press first. Measured on an iPhone 17 Pro: a
/// press-and-drag on the gutter moved nothing, and a press-and-drag on the row
/// itself ran the *field's* drag and pasted "Lift and shadow states" into the
/// middle of "Keyboard fallback". So the gesture was unreachable on touch and
/// destructive when it was reached by accident, and the desk had the same
/// geometry to aim at. `theChecklistRowIsNotTheGrip` is what keeps that shape
/// from coming back.
///
/// A drag cannot be driven from here, so what is pinned is the seam the drop
/// closure calls: `dropSubtask(_:on:at:)` with the caret the zone under the
/// pointer names. Both directions are asserted, because the off-by-one shows in
/// only one of them — `move(fromOffsets:toOffset:)` counts in the pre-move
/// array, so a row travelling *down* lands one past the gap's index and one
/// travelling *up* lands exactly on it. A rule that got that backwards would
/// still look right in half the drags anybody tried.
///
/// `ColumnReorderTests` is the same suite for the settings sheet's columns, and
/// the three lists in this app that re-order by hand now share one shape.
@MainActor
@Suite struct SubtaskReorderTests {
    private func store() -> BoardStore { TestBoard.store() }

    private func order(_ store: BoardStore) -> [SubTask.ID] {
        store[TestBoard.dragDrop]?.subtasks.map(\.id) ?? []
    }

    /// Lift, Column drop targets, Keyboard fallback — the order the fixture's
    /// one three-row checklist starts in, and what every case here is measured
    /// against.
    private var seeded: [SubTask.ID] { [TestBoard.lift, TestBoard.dropTargets, TestBoard.keyboard] }

    private func payload(_ subtask: SubTask.ID, on task: TaskItem.ID = TestBoard.dragDrop) -> SubtaskTransfer {
        SubtaskTransfer(taskID: task, subtaskID: subtask, text: "")
    }

    private func drop(
        _ subtask: SubTask.ID, at caret: SubtaskCaret, in store: BoardStore,
        on task: TaskItem.ID = TestBoard.dragDrop
    ) -> Bool {
        store.dropSubtask(payload(subtask, on: task), on: task, at: caret)
    }

    @Test func aRowDraggedDownTakesTheTargetsPlace() {
        let store = store()
        #expect(order(store) == seeded)

        // The first row into the gap below the last: from 0, anchor 2, so it
        // lands third.
        #expect(drop(TestBoard.lift, at: .below(TestBoard.keyboard), in: store))
        #expect(order(store) == [TestBoard.dropTargets, TestBoard.keyboard, TestBoard.lift])
        // The ticks travel with the rows they belong to, which is the half a
        // reorder written as "copy the texts across" would get wrong.
        #expect(store[TestBoard.dragDrop]?.subtasks.map(\.done) == [false, false, true])
    }

    @Test func aRowDraggedUpTakesTheTargetsPlace() {
        let store = store()

        // The last row into the gap above the middle one: from 2, anchor 1, so
        // it lands second.
        #expect(drop(TestBoard.keyboard, at: .above(TestBoard.dropTargets), in: store))
        #expect(order(store) == [TestBoard.lift, TestBoard.keyboard, TestBoard.dropTargets])
    }

    /// **The head of the list is reachable**, which under the old
    /// `drop(_:before:)` it only was by accident: that closure resolved a row
    /// into a gap by the direction of travel, so the first row's gap could be
    /// reached from below and never named directly.
    @Test func aRowCanLandInFrontOfTheFirstOne() {
        let store = store()
        #expect(drop(TestBoard.keyboard, at: .above(TestBoard.lift), in: store))
        #expect(order(store) == [TestBoard.keyboard, TestBoard.lift, TestBoard.dropTargets])
    }

    /// And so is the foot of it. Nothing sits below the last row to aim at, so
    /// its own `.below` half is what the end of the list is made of — the add
    /// row beneath is a field, not a target.
    @Test func aRowCanLandAfterTheLastOne() {
        let store = store()
        #expect(drop(TestBoard.dropTargets, at: .below(TestBoard.keyboard), in: store))
        #expect(order(store) == [TestBoard.lift, TestBoard.keyboard, TestBoard.dropTargets])
    }

    /// A row let go over itself is a drag somebody thought better of, not an
    /// instruction. `false` says the drop was not taken, and nothing moved.
    @Test func aRowDroppedOnItselfIsRefused() {
        let store = store()
        #expect(drop(TestBoard.dropTargets, at: .above(TestBoard.dropTargets), in: store) == false)
        #expect(drop(TestBoard.dropTargets, at: .below(TestBoard.dropTargets), in: store) == false)
        #expect(order(store) == seeded)
    }

    /// **The two gaps a row already sits between are refused**, which is the
    /// other half of the same rule: `subtaskDropIndex` opens no gap where a
    /// release would move nothing, and a drop that reached the store anyway must
    /// not cost a ⌘Z for a row that did not move.
    @Test func theGapsEitherSideOfTheDraggedRowAreRefused() {
        let store = store()
        #expect(drop(TestBoard.dropTargets, at: .below(TestBoard.lift), in: store) == false)
        #expect(drop(TestBoard.dropTargets, at: .above(TestBoard.keyboard), in: store) == false)
        #expect(order(store) == seeded)
    }

    /// A payload carries its task so a row dragged out of the macOS inspector
    /// cannot land in a sheet — or a second window — showing a different card:
    /// the indices would name a place in a list the row is not in. Both halves
    /// are checked, because either one alone would let the drop through.
    @Test func aRowFromAnotherTaskIsRefused() {
        let store = store()
        let elsewhere = payload(TestBoard.mutationLog, on: TestBoard.offline)

        #expect(store.dropSubtask(elsewhere, on: TestBoard.dragDrop, at: .above(TestBoard.lift)) == false)
        #expect(order(store) == seeded)
        // And the checklist it actually belongs to is untouched.
        #expect(store[TestBoard.offline]?.subtasks.map(\.id) == [TestBoard.mutationLog])
    }

    /// A drop that names a row the task no longer has — the payload outliving a
    /// delete on another surface — is refused rather than resolving to whatever
    /// `firstIndex` happens to return.
    @Test func aRowThatIsNoLongerThereIsRefused() {
        let store = store()
        let ghost = payload(TestBoard.mutationLog)

        #expect(store.dropSubtask(ghost, on: TestBoard.dragDrop, at: .above(TestBoard.lift)) == false)
        // And the same for a caret naming one.
        #expect(drop(TestBoard.lift, at: .below(TestBoard.mutationLog), in: store) == false)
        #expect(order(store) == seeded)
    }

    /// A drop on a task the store has never heard of answers `false` rather
    /// than trapping on the lookup.
    @Test func aDropOnAMissingTaskIsRefused() {
        let store = store()
        let ghost = TestBoard.taskID(99)
        #expect(store[ghost] == nil)
        #expect(drop(TestBoard.lift, at: .above(TestBoard.keyboard), in: store, on: ghost) == false)
    }

    /// Reordering logs nothing — the order is on screen, and a feed of
    /// "sub-task moved" would bury the changes that matter. Asserted through the
    /// drop rather than through `moveSubtask` alone, so a log added in the drop
    /// path would be caught too.
    @Test func aDroppedRowLeavesNoTrailInTheFeed() {
        let store = store()
        let before = store[TestBoard.dragDrop]?.activity.map(\.id)
        #expect(drop(TestBoard.lift, at: .below(TestBoard.keyboard), in: store))
        #expect(store[TestBoard.dragDrop]?.activity.map(\.id) == before)
    }

    /// One ⌘Z puts the whole order back — `moveSubtask` is `undoable`, and the
    /// drop goes through it rather than writing `subtasks` itself.
    @Test func aDroppedRowIsOneUndoStep() {
        let (store, undo) = TestBoard.undoing()

        // Grouped by hand, for the reason `step` documents: `undoing` turns
        // `groupsByEvent` off, and registering an undo outside a group throws
        // rather than failing an expectation.
        var landed = false
        step(undo) {
            landed = store.dropSubtask(
                payload(TestBoard.lift), on: TestBoard.dragDrop, at: .below(TestBoard.keyboard)
            )
        }
        #expect(landed)
        #expect(order(store) != seeded)

        undo.undo()
        #expect(order(store) == seeded)
    }

    // MARK: The row that is not there yet

    /// Where the stand-in goes, counted in the list **as it is drawn** — which
    /// is one longer than the list will be, because the row in the air is still
    /// one of the rows until the drop lands.
    @Test func theStandInOpensTheGapTheRowWouldLandIn() {
        let store = store()
        let index = { (row: SubTask.ID, caret: SubtaskCaret) in
            store.subtaskDropIndex(row, on: TestBoard.dragDrop, at: caret)
        }

        // The first row aimed past the last: three rows drawn, and it becomes
        // the fourth of them.
        #expect(index(TestBoard.lift, .below(TestBoard.keyboard)) == 3)
        // …and aimed above the last: third of the drawn three, in front of it.
        #expect(index(TestBoard.lift, .above(TestBoard.keyboard)) == 2)
        // The last row aimed at the head of the list, which is row zero.
        #expect(index(TestBoard.keyboard, .above(TestBoard.lift)) == 0)
        // The two spellings of the *same* gap agree, which they must: below the
        // first row and above the second name one place, and a stand-in that
        // jumped between them as the pointer crossed a boundary inside a single
        // gap would flicker for no reason a user could see.
        #expect(index(TestBoard.keyboard, .below(TestBoard.lift)) == 1)
        #expect(index(TestBoard.keyboard, .above(TestBoard.dropTargets)) == 1)
    }

    /// **The mark and the move are one rule, asked twice**, and this is the
    /// claim that keeps them so. A gap that opens where the drop will then
    /// refuse to land is a promise the app does not keep — the rows part, the
    /// hand lets go, and nothing happens.
    ///
    /// Asserted over *every* row against *every* caret rather than at a few
    /// chosen points, because the two rules are written out separately —
    /// `dropSubtask` returns an offset into the pre-move array and
    /// `subtaskDropIndex` an index into the drawn list — and an edit to one is
    /// exactly the thing that would leave the other behind.
    @Test func aGapOpensPreciselyWhereADropWouldLand() {
        for row in [TestBoard.lift, TestBoard.dropTargets, TestBoard.keyboard] {
            for anchor in [TestBoard.lift, TestBoard.dropTargets, TestBoard.keyboard] {
                for caret in [SubtaskCaret.above(anchor), .below(anchor)] {
                    // A store each time: `dropSubtask` moves things, and the
                    // question is about the list as it stands.
                    let asking = store()
                    let opens = asking.subtaskDropIndex(row, on: TestBoard.dragDrop, at: caret) != nil
                    let lands = store().dropSubtask(
                        payload(row), on: TestBoard.dragDrop, at: caret
                    )
                    #expect(opens == lands,
                            "\(caret) with \(row): a gap \(opens ? "opens" : "does not open") but the drop \(lands ? "lands" : "does not land")")
                }
            }
        }
    }

    /// A stand-in for a row that is not in this checklist, or on a card the
    /// store has never heard of, is no stand-in — the same refusals the drop
    /// makes, so a payload that outlived a delete opens no gap either.
    @Test func noGapOpensForARowThatIsNotThere() {
        let store = store()
        #expect(store.subtaskDropIndex(TestBoard.mutationLog, on: TestBoard.dragDrop,
                                       at: .above(TestBoard.lift)) == nil)
        #expect(store.subtaskDropIndex(TestBoard.lift, on: TestBoard.dragDrop,
                                       at: .below(TestBoard.mutationLog)) == nil)
        #expect(store.subtaskDropIndex(TestBoard.lift, on: TestBoard.taskID(99),
                                       at: .above(TestBoard.keyboard)) == nil)
    }

    /// **The insertion line went when the stand-in arrived.** Both answer the
    /// same question, and drawing them together puts a solid accent rule along
    /// the edge of the dashed outline immediately beside it — one insertion
    /// point stated twice, in two notations. `DropPreviewCard` makes the same
    /// trade on the board through `drawsDropCaret`; the checklist can simply not
    /// have one, having no other list to answer to.
    ///
    /// Read off the masked source so the prose saying why cannot satisfy it.
    @Test func theChecklistDrawsNoInsertionLineBesideTheStandIn() {
        guard SourceTree.isReachable else { return }
        guard let file = SourceTree.files().first(where: { $0.path == "Shared/ChecklistView.swift" })
        else {
            Issue.record("the checklist has moved file")
            return
        }
        #expect(file.source.contains("Capsule") == false,
                "the checklist is drawing an insertion capsule again, beside the stand-in")
    }

    /// **The row itself is no longer the grip**, which is a claim about the code
    /// rather than about the store: `dropSubtask` answers the same whether or not
    /// anything on screen is wired to it, and what was wrong was the wiring. Read
    /// off the *masked* source, so the prose above `grip(for:)` explaining why the
    /// row stopped being draggable cannot satisfy it.
    ///
    /// One `draggable` in the file, and it is inside `grip(for:)`. Two would mean
    /// the row had it back, and the row taking the gesture is what put a
    /// checklist's own text into the wrong row.
    @Test func theChecklistRowIsNotTheGrip() {
        guard SourceTree.isReachable else { return }
        guard let file = SourceTree.files().first(where: { $0.path == "Shared/ChecklistView.swift" })
        else {
            Issue.record("the checklist has moved file")
            return
        }

        let lifts = file.calls(headed: ".draggable")
        #expect(lifts.count == 1, "the checklist has \(lifts.count) drag sources; the grip is the only one")
        if let lift = lifts.first {
            #expect(file.line(containing: lift.offset).contains("lifted"),
                    "the checklist's drag is not the grip's")
        }
    }

    /// **The row is as tall as the lines it draws.**
    ///
    /// The reported bug: a sub-task just short of wrapping was given a second,
    /// empty line — the words at the top of a double-height row, the tick and
    /// the grip sliding down past them to centre on it. The cause is that a
    /// `TextField(axis: .vertical)` wraps its text 4pt before the trailing edge
    /// of its frame and draws it to the edge, so any text ending inside that
    /// 4pt band measures at two lines and draws on one. The fix hands the field
    /// 4pt of width it does not claim, which puts its wrap back on the claim's
    /// edge.
    ///
    /// **Nothing here can watch it happen** — a row's height is SwiftUI's
    /// answer to a layout proposal and there is no view hierarchy in this
    /// target, which is `FieldFocusTests`' problem and it takes the same way
    /// out. The 4 was measured outside the suite, against `NSHostingView`, by
    /// comparing the field's height with the same string's `Text` height at
    /// every width from 200 to 460pt over five strings: 4.0 is the only value
    /// that is never too tall and never too short. So what is asserted is that
    /// the number is still 4 and the field is still given it — the two halves
    /// that a later edit could take apart without anything else noticing.
    @Test func theSubtaskFieldIsGivenTheWidthItWrapsEarlyBy() {
        for (name, metrics) in [("desk", ChecklistView.Metrics.desk), ("sheet", ChecklistView.Metrics.sheet)] {
            #expect(metrics.fieldCaretGutter == 4,
                    "\(name)'s field no longer gets the 4pt it wraps early by, so a row near the wrap claims a line it does not draw")
        }

        guard SourceTree.isReachable else { return }
        guard let file = SourceTree.files().first(where: { $0.path == "Shared/ChecklistView.swift" })
        else {
            Issue.record("the checklist has moved file")
            return
        }
        // Masked source: the prose above `fieldCaretGutter` explains the band
        // at length, and prose is not the modifier.
        #expect(file.source.contains("padding(.trailing, -metrics.fieldCaretGutter)"),
                "the row's field is no longer handed its gutter; the empty second line is back")
    }

    /// **And it is a grip on every platform**, which is the whole of what was
    /// asked for: one view draws the desk inspector's checklist, the iPad's and
    /// the phone sheet's, so a `#if os` in here would be the way the drag came
    /// back on one of them and not the others. Both presets name a square at
    /// least as big as the glyph they draw in it.
    @Test func theGripIsDrawnOnEveryPlatform() {
        for (name, metrics) in [("desk", ChecklistView.Metrics.desk), ("sheet", ChecklistView.Metrics.sheet)] {
            #expect(metrics.gripGlyph > 0, "\(name) draws no grip")
            #expect(metrics.gripHit >= metrics.gripGlyph, "\(name)'s grip target is smaller than its glyph")
            #expect(metrics.gripReserve > 0, "\(name)'s add row holds no room for the grip")
        }

        guard SourceTree.isReachable else { return }
        guard let file = SourceTree.files().first(where: { $0.path == "Shared/ChecklistView.swift" })
        else {
            Issue.record("the checklist has moved file")
            return
        }
        // **Nothing in the view itself is per-platform.** The file has exactly
        // one `#if os`, and it is below the view in `SubtaskDragSession`, where
        // it asks which OS *reports* the end of a drag — `onDragSessionUpdated`
        // being macOS 26 but iOS 27. That is a question about a callback, not
        // about what is drawn, so the split is taken at the type boundary and
        // everything above it has to be unconditional.
        let view = file.source.components(separatedBy: "struct SubtaskDragSession")[0]
        #expect(file.source.contains("struct SubtaskDragSession"),
                "the drag-session shim has been renamed; this test is measuring the whole file")
        #expect(view.contains("#if os(") == false,
                "the checklist view has grown a per-platform branch; the grip has to be on all of them")
    }
}
