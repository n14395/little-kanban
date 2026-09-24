// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

/// **Settings ▸ Delete everything…**, which used to be *Reset to the sample
/// board* and used to hand people the sample whether they wanted it or not.
///
/// The row now raises the same picker a first launch does, so the question
/// "what should be on this board" gets asked rather than answered, and
/// `BoardStore.startOver(with:)` is what a chosen row runs.
@MainActor
@Suite struct StartingOverTests {
    /// The difference from `importBoard`, and the reason this is not that call.
    /// A merge folds a template into what is already there, which is right for
    /// a first launch, where what is already there is nothing. Here it would
    /// leave the cards somebody just asked to be rid of sitting beside the new
    /// ones.
    @Test func startingOverReplacesTheBoardRatherThanMergingIntoIt() {
        let store = TestBoard.store()
        let before = store.tasks.count
        #expect(before > 0)

        store.startOver(with: SeedData.blank.snapshot)

        #expect(store.tasks.isEmpty, "\(store.tasks.count) of the old cards survived")
        #expect(store.boards.map(\.name) == SeedData.blank.boards.map(\.name))
    }

    @Test func everyStarterCanBeStartedOverInto() {
        for template in SeedData.starters {
            let store = TestBoard.store()
            store.startOver(with: template.snapshot)
            #expect(store.tasks.count == template.tasks.count, "\(template.id) landed wrong")
            #expect(store.boards.count == template.boards.count, "\(template.id) landed wrong")
            #expect(store.labels.count == template.labels.count, "\(template.id) landed wrong")
        }
    }

    /// The board being looked at has just been deleted, and a surface reading
    /// `activeBoard` must never be shown nothing while there is a board to show.
    @Test func theNewBoardIsTheOneBeingLookedAt() {
        let store = TestBoard.store()
        let wasLookingAt = store.activeBoardID
        store.startOver(with: SeedData.personal.snapshot)

        #expect(store.activeBoardID != wasLookingAt)
        #expect(store.activeBoardID == store.boards.first?.id)
        #expect(store.activeBoard != nil)
    }

    /// The accent is a preference somebody set on this machine, not part of the
    /// board they are replacing.
    @Test func theAccentSurvives() {
        let store = TestBoard.store()
        store.selectTheme(TestBoard.otherDarkTheme)
        store.startOver(with: SeedData.sprint.snapshot)
        #expect(store.themes.darkID == TestBoard.otherDarkTheme.id)
    }

    /// One ⌘Z, and it puts back everything — which is the whole reason the
    /// board is not emptied when the warning is accepted and filled in again
    /// when the picker returns. `UndoHarnessTests` holds the step count and the
    /// name; this holds what the step is worth.
    @Test func oneUndoPutsTheWholeBoardBack() {
        let (store, undo) = TestBoard.undoing()
        let before = store.tasks.map(\.id)
        let boardsBefore = store.boards.map(\.id)

        step(undo) { store.startOver(with: SeedData.blank.snapshot) }
        #expect(store.tasks.isEmpty)

        undo.undo()
        #expect(store.tasks.map(\.id) == before)
        #expect(store.boards.map(\.id) == boardsBefore)
        #expect(undo.canUndo == false, "starting over cost more than one step")
    }

    /// The copy in `backups/` is what the promise falls back on once the
    /// session that could undo it has ended.
    @Test func theBoardAsItStandsIsKeptFirst() throws {
        let temp = TempBoard()
        let store = TestBoard.store(file: temp.file)
        try FileManager.default.createDirectory(
            at: temp.file.backupsDirectory, withIntermediateDirectories: true
        )

        store.startOver(with: SeedData.blank.snapshot)

        #expect(store.availableBackups().isEmpty == false, "nothing was kept before the board went")
    }

    // MARK: What the picker says

    /// The picker is the same five rows either way; the words around them are
    /// not, and a modal that says *Welcome to Little Kanban* while it is about
    /// to replace somebody's board is the failure this arrangement exists to
    /// avoid.
    @Test func theTwoOccasionsDoNotSayTheSameThing() {
        #expect(FirstRunView.Occasion.firstLaunch.title != FirstRunView.Occasion.startingOver.title)
        #expect(FirstRunView.Occasion.firstLaunch.subtitle != FirstRunView.Occasion.startingOver.subtitle)
        #expect(FirstRunView.Occasion.firstLaunch.footnote != FirstRunView.Occasion.startingOver.footnote)
    }

    @Test func everyOccasionSaysSomethingInEveryPosition() {
        for occasion in FirstRunView.Occasion.allCases {
            #expect(!occasion.title.isEmpty)
            #expect(!occasion.subtitle.isEmpty)
            #expect(!occasion.footnote.isEmpty)
        }
    }

    /// A first launch has nothing to lose and no way out but a choice. Starting
    /// over has a whole board to lose, so it can be called off — and `cancel`
    /// is what both the button and `interactiveDismissDisabled` read.
    @Test func onlyTheOccasionWithSomethingToLoseCanBeCalledOff() {
        let firstLaunch = FirstRunView(templates: SeedData.starters, choose: { _ in })
        #expect(firstLaunch.cancel == nil, "a first launch can be escaped without choosing")

        let startingOver = FirstRunView(
            occasion: .startingOver, templates: SeedData.starters, choose: { _ in }, cancel: {}
        )
        #expect(startingOver.cancel != nil, "starting over traps somebody into replacing their board")
    }
}
