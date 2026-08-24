import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

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
