// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftUI
import Testing
@testable import LittleKanban

@Suite struct LabelTests {
    // MARK: Slugs

    @Test func aSlugIsLowercaseAndHyphenatedWithNoLooseEnds() {
        #expect(LabelDef.key(from: "Design") == "design")
        #expect(LabelDef.key(from: "Infra Work!") == "infra-work")
        #expect(LabelDef.key(from: "  Release 1.2  ") == "release-1-2")
        #expect(LabelDef.key(from: "--already--hyphenated--") == "already-hyphenated")
        #expect(LabelDef.key(from: "iOS") == "ios")
        #expect(LabelDef.key(from: "Café") == "café")
    }

    @Test func aNameThatSlugsToNothingGetsAKeyOfItsOwn() {
        // An empty key would collide with every other empty key and detach
        // every task carrying one.
        let first = LabelDef.key(from: "!!!")
        let second = LabelDef.key(from: "***")
        #expect(first.hasPrefix("label-"))
        #expect(first.count == "label-".count + 8)
        #expect(first != second)
        #expect(LabelDef.key(from: "-").hasPrefix("label-"))
        #expect(LabelDef.key(from: "").hasPrefix("label-"))
    }

    @Test func keysAlreadyOnDiskKeepResolving() throws {
        // "release-1-2" was slugged by an older build; nothing may rewrite it.
        let temp = TempBoard()
        try temp.put(try Fixture.data("board-v1"))
        let snapshot = try #require(temp.file.load().snapshot)
        #expect(snapshot.labels.map(\.key).contains("release-1-2"))
        #expect(snapshot.tasks.contains { $0.labelKeys.contains("release-1-2") })
    }

    // MARK: Creating

    @MainActor
    @Test func creatingALabelAddsItOnceAndAppliesIt() {
        let store = TestBoard.store()
        store.createLabel(named: "Infra Work", on: TestBoard.cafe)
        #expect(store.labels.count == LabelDef.seed.count + 1)
        #expect(store.label(forKey: "infra-work")?.name == "Infra Work")
        #expect(store[TestBoard.cafe]?.labelKeys == ["polish", "infra-work"])

        // A name that slugs to a key already in use just applies that label.
        store.createLabel(named: "infra   work", on: TestBoard.dragDrop)
        #expect(store.labels.count == LabelDef.seed.count + 1)
        #expect(store[TestBoard.dragDrop]?.labelKeys == ["design", "ios", "infra-work"])
        #expect(store.label(forKey: "infra-work")?.name == "Infra Work")     // the first name stands
    }

    /// The manager's drag: the vocabulary reorders, every definition survives
    /// unchanged, and no task is touched — order is presentation, not an
    /// event. `dropOffset` is the same off-by-one the checklist and the
    /// columns go through, so "drop on the row below" means landing below it.
    @MainActor
    @Test func reorderingLabelsMovesTheListAndNothingElse() throws {
        let store = TestBoard.store()
        let before = store.labels
        try #require(before.count >= 3, "the seed list is too short to reorder meaningfully")
        let tasksBefore = store.tasks

        store.moveLabel(
            fromOffsets: IndexSet(integer: 0),
            toOffset: BoardStore.dropOffset(from: 0, to: 2)
        )
        let expected = [before[1].key, before[2].key, before[0].key] + before.dropFirst(3).map(\.key)
        #expect(store.labels.map(\.key) == expected)
        #expect(Set(store.labels) == Set(before), "a definition changed in the move")
        #expect(store.tasks == tasksBefore, "a reorder reached a task")

        // A drop back where it started is not an event.
        let settled = store.labels
        store.moveLabel(fromOffsets: IndexSet(integer: 1), toOffset: 1)
        #expect(store.labels == settled)
    }

    /// The manager's create: the definition joins the vocabulary and lands on
    /// no task; a name that slugs to an existing key makes nothing and hands
    /// back the key of the row already on the list.
    @MainActor
    @Test func creatingFromTheManagerTouchesNoTask() {
        let store = TestBoard.store()
        let tasksBefore = store.tasks
        let key = store.createLabel(named: "Quiet Work", color: SwatchColor.rgb(0x8058C8, opacity: 1))
        #expect(key == "quiet-work")
        #expect(store.label(forKey: "quiet-work")?.name == "Quiet Work")
        #expect(store.tasks == tasksBefore, "a vocabulary edit reached a task")

        #expect(store.createLabel(named: "Polish") == "polish")
        #expect(store.labels.count == LabelDef.seed.count + 1, "an existing name made a second definition")
        #expect(store.createLabel(named: "   ") == nil)
    }

    /// The compose form's path: a chosen colour is worn, and the rotation is
    /// what a label made without one wears — the same answer `nextLabelColor`
    /// shows the form before anything is picked.
    @MainActor
    @Test func aChosenColourIsWornAndTheRotationCoversTheRest() {
        let store = TestBoard.store()
        let picked = SwatchColor.rgb(0x8058C8, opacity: 1)

        store.createLabel(named: "Deliberate", color: picked, on: TestBoard.cafe)
        #expect(store.label(forKey: "deliberate")?.light == store.labelTones(for: picked).light)
        #expect(store.label(forKey: "deliberate")?.dark == store.labelTones(for: picked).dark)

        // Read after the create above: every label added moves the rotation on
        // a place, and this is the answer the compose form's well would show.
        let expectedDefault = store.nextLabelColor
        store.createLabel(named: "Defaulted", on: TestBoard.cafe)
        #expect(store.label(forKey: "defaulted")?.light == store.labelTones(for: expectedDefault).light)

        // A colour handed in with a name that already names a label is not a
        // recolour: "adding" an existing label must not repaint it.
        let polish = store.label(forKey: "polish")
        store.createLabel(named: "Polish", color: picked, on: TestBoard.dragDrop)
        #expect(store.label(forKey: "polish") == polish)
    }

    @MainActor
    @Test func applyingALabelATaskAlreadyHasIsNotAnEvent() {
        let store = TestBoard.store()
        let before = store[TestBoard.cafe]
        store.createLabel(named: "Polish", on: TestBoard.cafe)
        #expect(store[TestBoard.cafe] == before)
        #expect(store.labels.count == LabelDef.seed.count)
    }

    @MainActor
    @Test func aNameIsCappedAtWhatAChipCanShow() {
        let store = TestBoard.store()
        let long = String(repeating: "a", count: 60)
        store.createLabel(named: long, on: TestBoard.cafe)
        #expect(store.labels.last?.name.count == 40)

        store.renameLabel(store.labels.last?.key ?? "", to: String(repeating: "b", count: 60))
        #expect(store.labels.last?.name == String(repeating: "b", count: 40))
    }

    @MainActor
    @Test func aNameIsFoldedToOneLineAndTrimmed() {
        let store = TestBoard.store()
        store.createLabel(named: "  Infra\n   Work  ", on: TestBoard.cafe)
        #expect(store.label(forKey: "infra-work")?.name == "Infra Work")
    }

    @MainActor
    @Test func aBlankNameCreatesNothing() {
        let store = TestBoard.store()
        store.createLabel(named: "   \n ", on: TestBoard.cafe)
        #expect(store.labels.count == LabelDef.seed.count)
        #expect(store[TestBoard.cafe]?.labelKeys == ["polish"])
    }

    // MARK: Renaming

    @MainActor
    @Test func renamingKeepsTheKeyAndSoKeepsEveryTask() {
        let store = TestBoard.store()
        let carriers = store.tasks.filter { $0.labelKeys.contains("design") }.map(\.id)
        #expect(carriers.count == 2)

        store.renameLabel("design", to: "Visual design")
        #expect(store.label(forKey: "design")?.name == "Visual design")
        #expect(store.labels.map(\.key) == LabelDef.seed.map(\.key))
        for id in carriers {
            let task = store[id]
            #expect(task?.labelKeys.contains("design") == true)
            #expect(task.map { store.labels(for: $0).map(\.name).contains("Visual design") } == true)
        }
    }

    @MainActor
    @Test func renamingToTheSameNameOrToNothingDoesNotHappen() {
        let store = TestBoard.store()
        let before = store.labels
        store.renameLabel("design", to: "Design")
        store.renameLabel("design", to: "   ")
        store.renameLabel("no-such-key", to: "Ghost")
        #expect(store.labels == before)
    }

    // MARK: Recolouring

    @MainActor
    @Test func recolouringTouchesTheDefinitionAndNothingElse() {
        let store = TestBoard.store()
        let tasksBefore = store.tasks
        store.recolorLabel("design", to: .hex(0x783CA0))
        #expect(store.label(forKey: "design")?.light == LabelTone.pair(from: 0x783CA0).light)
        #expect(store.label(forKey: "design")?.dark == LabelTone.pair(from: 0x783CA0).dark)
        #expect(store.label(forKey: "design")?.name == "Design")
        #expect(store.tasks == tasksBefore)

        // The same colours again is not a change.
        let labelsBefore = store.labels
        store.recolorLabel("design", to: .hex(0x783CA0))
        #expect(store.labels == labelsBefore)
    }

    // MARK: Deleting

    @MainActor
    @Test func deletingStripsTheKeyFromEveryTaskThatCarriedIt() {
        let store = TestBoard.store()
        let carriers = store.tasks.filter { $0.labelKeys.contains("design") }.map(\.id)
        #expect(carriers.count == 2)

        store.deleteLabel("design")
        #expect(store.label(forKey: "design") == nil)
        #expect(store.tasks.allSatisfy { !$0.labelKeys.contains("design") })
        // A chip vanishing from a card is explicable from that card's history.
        for id in carriers {
            #expect(store[id]?.activity.first?.kind == .labelRemoved(key: "design", name: "Design"))
        }
        // Other labels on those tasks are left alone.
        #expect(store[TestBoard.dragDrop]?.labelKeys == ["ios"])
    }

    @MainActor
    @Test func onlyTheTasksThatCarriedTheLabelRecordItsRemoval() {
        let store = TestBoard.store()
        store.deleteLabel("bug")
        // NW-124 is the only one carrying it, so it is the only feed touched.
        #expect(store.tasks.count { $0.activity.first?.kind == .labelRemoved(key: "bug", name: "Bug") } == 1)
        #expect(store[TestBoard.sync]?.labelKeys == ["api"])
    }

    @MainActor
    @Test func deletingALabelNoTaskCarriesLeavesEveryTaskAlone() {
        // Made and then taken back off, which is the only way to reach a label
        // no task carries: `labels` has no public setter, on purpose.
        let store = TestBoard.store()
        store.createLabel(named: "Unused", on: TestBoard.cafe)
        store.toggleLabel("unused", on: TestBoard.cafe)
        #expect(store.labels.map(\.key).contains("unused"))
        let tasksBefore = store.tasks
        store.deleteLabel("unused")
        #expect(store.tasks == tasksBefore)
        #expect(store.labels.map(\.key) == LabelDef.seed.map(\.key))
    }

    @MainActor
    @Test func deletingAKeyThatIsNotALabelDoesNothing() {
        let store = TestBoard.store()
        let before = store.labels
        store.deleteLabel("no-such-key")
        #expect(store.labels == before)
    }

    // MARK: Toggling on a task

    @MainActor
    @Test func toggleAddsAtTheEndAndRemovesInPlace() {
        let store = TestBoard.store()
        store.toggleLabel("bug", on: TestBoard.dragDrop)
        #expect(store[TestBoard.dragDrop]?.labelKeys == ["design", "ios", "bug"])
        store.toggleLabel("ios", on: TestBoard.dragDrop)
        #expect(store[TestBoard.dragDrop]?.labelKeys == ["design", "bug"])
    }

    @MainActor
    @Test func aTaskCanCarryAKeyWithNoDefinitionWithoutBreaking() {
        // A board written by another build, or one mid-migration.
        var orphaned = TestBoard.tasks[2]
        orphaned.labelKeys = ["polish", "vanished"]
        let store = BoardStore(tasks: [orphaned], labels: LabelDef.seed, file: nil)
        #expect(store.labels(for: orphaned).map(\.key) == ["polish"])
        #expect(store.label(forKey: "vanished") == nil)
    }

    // MARK: The seed vocabulary

    @Test func theSeedLabelsHaveDistinctKeysAndBothTones() {
        #expect(Set(LabelDef.seed.map(\.key)).count == LabelDef.seed.count)
        for label in LabelDef.seed {
            #expect(LabelDef.key(from: label.name) == label.key, Comment(rawValue: label.name))
            #expect(label.tone(for: .light) == label.light)
            #expect(label.tone(for: .dark) == label.dark)
        }
    }
}

#if os(macOS)

/// The label picker's popover, and the one thing a popover cannot be told twice.
///
/// **The defect.** The picker's panel swaps itself for the compose form, which
/// is shorter, and the popover follows it down. Cancel, and the list came back
/// into a popover that stayed the compose form's size for as long as it was
/// open — a list of labels in a 130pt slot with a scroll bar down the side of it.
///
/// **Why.** A scroll view accepts whatever height it is offered, so the panel
/// had no height of its own: once the popover was small, the list fitted into it
/// without complaint and asked for nothing. Its *ideal* height was right the
/// whole time — 236pt, measured — and a popover that is already open does not
/// read the ideal; it follows what the content accepts. The compose form has a
/// definite height, which is why the popover shrank at all.
///
/// Measured on macOS 27 with a SwiftUI `.popover` in an off-screen window,
/// switching a fixed-height panel and a scroll-view panel against a shorter one:
///
/// | panel | opened | swapped | back |
/// | --- | --- | --- | --- |
/// | two fixed heights | 262 | 156 | **262** |
/// | scroll view, no floor | 238 | 156 | **156** |
/// | scroll view, floored | 238 | 156 | **238** |
///
/// So the popover grows perfectly well; it was never being asked to. The floor
/// is `LabelPickerList.rowsHeight`, and this is the invariant it buys: the panel
/// will not lay itself out shorter than the rows it is drawing.
@MainActor
@Suite struct LabelPickerHeightTests {
    /// Somewhere for `onGeometryChange` to report to. A class rather than a
    /// captured `var` because the write lands on a later layout pass.
    @Observable final class Measured { var height: CGFloat = -1 }

    /// The panel's laid-out height when it is offered `height` — which is what
    /// an open popover offers it, and what the popover then takes as its size.
    private func panelHeight(offered height: CGFloat, in store: BoardStore) async -> CGFloat {
        let measured = Measured()
        let task = store[TestBoard.dragDrop]!
        let view = NSHostingView(
            rootView: LabelPickerList(task: task, scope: .desk, metrics: .desk)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured.height = $0 }
                .environment(store)
        )
        view.frame = NSRect(x: 0, y: 0, width: LabelPickerList.Metrics.desk.width, height: height)
        view.layoutSubtreeIfNeeded()
        for _ in 0..<20 where measured.height < 0 {
            try? await Task.sleep(for: .milliseconds(25))
        }
        return measured.height
    }

    /// The whole of the fix: squeezed into the compose form's slot, the list
    /// stands its ground rather than folding into it.
    @Test func theListWillNotFoldIntoTheComposeFormsHeight() async {
        let store = TestBoard.store()
        let natural = await panelHeight(offered: 400, in: store)
        let squeezed = await panelHeight(offered: 130, in: store)

        #expect(squeezed > 130, "the list accepted the compose form's height and the popover will stay there")
        #expect(squeezed == natural || squeezed >= 200,
                "the list came back at \(squeezed) rather than its own \(natural)")
    }

    /// And the cap still caps: a list longer than `maxListHeight` scrolls inside
    /// it rather than growing a popover the length of the vocabulary. The floor
    /// is `min(rows, maxListHeight)` precisely so these two cannot fight.
    @Test func aLongListStillStopsAtItsCap() async {
        let seed = LabelDef.seed[0]
        let many = (0..<40).map {
            LabelDef(key: "probe-\($0)", name: "Label \($0)", light: seed.light, dark: seed.dark)
        }
        let store = BoardStore(
            tasks: TestBoard.tasks, boards: SeedData.boards, activeBoardID: SeedData.boards.first?.id,
            labels: many, nextSerial: BoardSnapshot.baseSerial
        )
        let natural = await panelHeight(offered: 900, in: store)
        // The rows come to well over a thousand points; the panel is the cap
        // plus the search field, the New Label button and the panel's padding.
        #expect(natural < LabelPickerList.Metrics.desk.maxListHeight + 120,
                "the panel grew past its cap and would open a popover the length of the vocabulary")
        #expect(natural > LabelPickerList.Metrics.desk.maxListHeight,
                "the panel did not reach its cap at all")
    }
}

#endif
