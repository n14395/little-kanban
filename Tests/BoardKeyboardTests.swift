#if os(macOS)

import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

/// How the arrows move around the board. `BoardFocusMap` is the rule, held
/// apart from the view so it can be asked rather than clicked at.
@MainActor
@Suite struct BoardFocusTests {
    private let backlog = BoardColumn.backlog.id
    private let upNext = BoardColumn.upNext.id
    private let doing = BoardColumn.inProgress.id
    private let done = BoardColumn.done.id

    /// The seeded test board: two cards in Backlog, one in each of the rest.
    private func map() -> BoardFocusMap { BoardFocusMap(TestBoard.store()) }

    @Test func theMapIsTheBoardLeftToRightAndTopToBottom() {
        let map = map()
        #expect(map.columns == [backlog, upNext, doing, done])
        #expect(map.cards[backlog] == [TestBoard.dragDrop, TestBoard.cafe])
        #expect(map.columnID(of: TestBoard.sync) == doing)
        // The Inbox is not a column, so a card in it is nowhere on this map.
        #expect(map.location(of: TestBoard.widget) == nil)
    }

    @Test func upAndDownStopAtTheEndsRatherThanWrapping() {
        let map = map()
        #expect(map.card(TestBoard.dragDrop, movedBy: 1) == TestBoard.cafe)
        #expect(map.card(TestBoard.cafe, movedBy: -1) == TestBoard.dragDrop)
        // Wrapping to the other end of the column reads as a bug at the moment
        // it happens; `nil` leaves the key to the scroll view.
        #expect(map.card(TestBoard.cafe, movedBy: 1) == nil)
        #expect(map.card(TestBoard.dragDrop, movedBy: -1) == nil)
    }

    @Test func sidewaysKeepsTheRowAndClampsToWhatIsThere() {
        let map = map()
        #expect(map.card(TestBoard.dragDrop, inColumnBy: 1) == TestBoard.offline)
        // The second row of a column with one card is that card, not nothing.
        #expect(map.card(TestBoard.cafe, inColumnBy: 1) == TestBoard.offline)
        #expect(map.card(TestBoard.dragDrop, inColumnBy: -1) == nil)
        #expect(map.card(TestBoard.palette, inColumnBy: 1) == nil)
    }

    @Test func focusStepsOverAnEmptyColumnAndAMoveLandsInIt() {
        let store = TestBoard.store()
        store.deleteTask(TestBoard.offline)
        let map = BoardFocusMap(store)

        // Nothing in Up Next to focus, so → carries on to In Progress.
        #expect(map.cards[upNext] == [])
        #expect(map.card(TestBoard.dragDrop, inColumnBy: 1) == TestBoard.sync)
        // ⌥→ is the other question: an empty column is exactly where a card
        // wants to go.
        #expect(map.column(TestBoard.dragDrop, by: 1) == upNext)
        #expect(map.column(TestBoard.palette, by: 1) == nil)
    }

    @Test func theMapIsWhatIsVisibleNotWhatIsOnTheBoard() {
        let store = TestBoard.store()
        store.query = "sync"
        let map = BoardFocusMap(store)

        #expect(map.cards[backlog] == [])
        #expect(map.cards[doing] == [TestBoard.sync])
        // A card the search has hidden is not one an arrow key can land on.
        #expect(map.location(of: TestBoard.dragDrop) == nil)
        #expect(map.card(TestBoard.sync, inColumnBy: -1) == nil)
    }

    @Test func deletingFallsToTheCardBelowAndThenToTheOneAbove() {
        let map = map()
        #expect(map.card(after: TestBoard.dragDrop) == TestBoard.cafe)
        #expect(map.card(after: TestBoard.cafe) == TestBoard.dragDrop)
        // Nothing else in the column, and focus has nowhere to fall.
        #expect(map.card(after: TestBoard.sync) == nil)
    }
}

/// The board matches key presses against `AppCommand.shortcuts` rather than
/// against literals, which is what stops the menu, the sheet and the board
/// disagreeing about what a key does. These pin the matching itself.
@Suite struct BoardKeyMatchTests {
    private func command(_ key: KeyEquivalent, _ modifiers: EventModifiers = []) -> AppCommand? {
        AppCommand.command(key: key, modifiers: modifiers, among: BoardKeyboard.boardCommands)
    }

    @Test func theModifierIsWhatSeparatesMovingFocusFromMovingTheCard() {
        #expect(command(.leftArrow) == .focusPreviousColumn)
        #expect(command(.leftArrow, .option) == .moveCardLeft)
        #expect(command(.rightArrow) == .focusNextColumn)
        #expect(command(.rightArrow, .option) == .moveCardRight)
        // Neither of them, and the key goes back to the scroll view.
        #expect(command(.leftArrow, .command) == nil)
    }

    @Test func completionAnswersToBothOfItsKeys() {
        #expect(command(.space) == .completeTask)
        #expect(command(.return, .command) == .completeTask)
        #expect(command(.return) == .openTask)
    }

    @Test func aKeyPressCarriesModifiersThatAreNotPartOfAnyShortcut() {
        // Caps lock and the numeric pad arrive with the press and belong to no
        // shortcut; comparing the whole set would make the arrows stop working
        // for anyone who had left caps lock on.
        #expect(command(.upArrow, [.capsLock, .numericPad]) == .focusCardAbove)
        #expect(command(.delete, [.command, .capsLock]) == .deleteTask)
    }

    /// Two commands on one key is the drift `AppCommand` exists to stop, and
    /// the board is where it would show up first — `command(key:modifiers:)`
    /// takes the first match and the second would simply never fire.
    @Test func noTwoOfTheBoardsCommandsClaimTheSameKey() {
        var seen: Set<String> = []
        for command in BoardKeyboard.boardCommands {
            for shortcut in command.shortcuts {
                let key = "\(shortcut.modifiers.rawValue):\(shortcut.key.keyEquivalent.character)"
                #expect(seen.insert(key).inserted, "\(command.rawValue) reuses \(shortcut.display)")
            }
        }
    }
}

/// One owner per press, across the two surfaces that both claim to handle keys.
///
/// ⌘⌫ and ⌘⏎ are the menu bar's. A menu key equivalent is dispatched out of
/// `NSApplication.sendEvent` before the responder chain is offered the event, so
/// a card that also claims either is claiming a key it will never receive: two
/// owners written down, one in fact, and the written-down one is the one a
/// reader believes. Space is the card's, and is completion's *other* key — which
/// is what makes this rule a partition of one command's shortcuts rather than of
/// the enum.
///
/// The rule was carried by a single defaulted argument at one call site and was
/// undefended in both directions. Dropping `excluding:` gave the card ⌘⌫ and ⌘⏎
/// back; widening `menuOwnedShortcuts` from the key each item *declares* to every
/// key its command names took Space off the card altogether. Both left all 488
/// tests green. `BoardKeyboard.command(for:among:)` is now the one call a card
/// makes, so there is no argument left to leave off, and these pin what it
/// answers.
@Suite struct KeyOwnershipTests {
    private func board(_ key: KeyEquivalent, _ modifiers: EventModifiers = []) -> AppCommand? {
        BoardKeyboard.command(key: key, modifiers: modifiers, among: BoardKeyboard.boardCommands)
    }

    private func flat(_ key: KeyEquivalent, _ modifiers: EventModifiers = []) -> AppCommand? {
        BoardKeyboard.command(key: key, modifiers: modifiers, among: BoardKeyboard.flatCommands)
    }

    /// The vocabulary still names both presses — `BoardKeyMatchTests` pins that
    /// — and no card answers to either of them.
    @Test func theMenuOwnsBothOfItsKeysAndNoCardAnswersToThem() {
        #expect(BoardKeyboard.menuOwnedShortcuts.contains(AppShortcut(.delete, .command)))
        #expect(BoardKeyboard.menuOwnedShortcuts.contains(AppShortcut(.return, .command)))

        #expect(board(.delete, .command) == nil)
        #expect(board(.return, .command) == nil)
        #expect(flat(.delete, .command) == nil)
        #expect(flat(.return, .command) == nil)
    }

    /// The half of completion the card keeps. The menu declares one key per item
    /// — its first — so the second stays where it is handled, and a card asked
    /// for `completeTask` still has a press that reaches it.
    @Test func spaceStaysTheCardsAndSoDoesTheReturnWithoutTheCommandKey() {
        #expect(!BoardKeyboard.menuOwnedShortcuts.contains(AppShortcut(.space)))
        #expect(board(.space) == .completeTask)
        #expect(flat(.space) == .completeTask)

        // ⏎ on its own is Open Task and is nobody's menu item.
        #expect(!BoardKeyboard.menuOwnedShortcuts.contains(AppShortcut(.return)))
        #expect(board(.return) == .openTask)
        #expect(flat(.return) == .openTask)
    }

    /// Named rather than derived, because a set defined as "whatever the menu
    /// declares" agrees with itself however the menu is spelt. These are the
    /// eight presses the menu bar puts a key equivalent on, and the seven the
    /// board keeps — the second list is what a widened exclusion silently eats.
    @Test func theMenuTakesItsOwnKeysAndNoneOfTheBoards() {
        let menu: Set<AppShortcut> = [
            AppShortcut("n", .command), AppShortcut("n", [.command, .shift]),
            AppShortcut(.delete, .command), AppShortcut("f", .command),
            AppShortcut("i", [.command, .option]), AppShortcut("s", [.command, .control]),
            AppShortcut(.return, .command), AppShortcut("/", .command),
        ]
        #expect(BoardKeyboard.menuOwnedShortcuts == menu)

        for shortcut in [AppShortcut(.space), AppShortcut(.return), AppShortcut(.escape),
                         AppShortcut("c", .command), AppShortcut("v", .command),
                         AppShortcut("a", .command), AppShortcut(.leftArrow, .option)] {
            #expect(!BoardKeyboard.menuOwnedShortcuts.contains(shortcut),
                    "the menu has taken \(shortcut.display) off the board")
        }
    }

    /// The rule stated over the whole vocabulary rather than over the two keys
    /// that happen to collide today: whatever the menu bar puts a key equivalent
    /// on, no card answers to. A key added to a menu item stops shadowing a
    /// card's on its own, and this is what says so.
    @Test func noPressTheMenuDeclaresReachesACard() {
        for command in AppCommand.allCases where command.isMenuItem {
            guard let shortcut = command.shortcuts.first else { continue }
            let key = shortcut.key.keyEquivalent
            let modifiers = shortcut.modifiers.eventModifiers
            #expect(board(key, modifiers) == nil,
                    "a board card answers to \(shortcut.display), which is \(command.rawValue)'s menu key")
            #expect(flat(key, modifiers) == nil,
                    "a list row answers to \(shortcut.display), which is \(command.rawValue)'s menu key")
        }
    }

    /// The other surface split: the flat lists carry the same vocabulary less
    /// the four commands that need columns, derived from the board's rather
    /// than written out again, so a key added to one arrives at the other.
    /// ↑ and ↓ read the same on both, which is the whole of the difference.
    @Test func aFlatSurfaceAnswersToEverythingButTheFourKeysThatNeedColumns() {
        #expect(Set(BoardKeyboard.boardCommands).subtracting(BoardKeyboard.flatCommands)
                == BoardKeyboard.columnCommands)

        for key in [KeyEquivalent.leftArrow, .rightArrow] {
            #expect(flat(key) == nil, "a flat list moved focus to a column it does not have")
            #expect(flat(key, .option) == nil, "a flat list moved a card to a column it does not have")
            #expect(board(key) != nil)
            #expect(board(key, .option) != nil)
        }
        #expect(flat(.upArrow) == .focusCardAbove)
        #expect(flat(.downArrow) == .focusCardBelow)
        #expect(flat("a", .command) == .selectAll)
        #expect(flat(.escape) == .deselect)
    }

    /// And the converse, so the exclusion cannot be widened into a mute button:
    /// every command a card carries still has at least one press that reaches
    /// it. `deleteTask` is the exception it is listed as — the card knows how to
    /// perform it and the menu is what asks.
    @Test func everyCommandACardCarriesStillHasAPressThatReachesIt() {
        for command in BoardKeyboard.boardCommands where command != .deleteTask {
            let reached = command.shortcuts.contains { shortcut in
                board(shortcut.key.keyEquivalent, shortcut.modifiers.eventModifiers) == command
            }
            #expect(reached, "\(command.rawValue) is on the card and no press reaches it")
        }
    }
}

/// What each key actually does once it has been matched.
///
/// `BoardKeyboard.perform` is the whole of the phase's keyboard behaviour: ⌥←
/// calling `move`, ⏎ opening the inspector, Space toggling, focus following a
/// deleted card. It used to be a private method on a `View`, reachable by
/// nothing but a person with a keyboard, and one-line defects inside it
/// survived the entire suite.
///
/// Two claims are made of every command: what it did to the store, and where it
/// left the keyboard. The second is the half a rendered board would not show —
/// focus that silently stops following a card looks exactly like focus that
/// follows it until the next key press.
@MainActor
@Suite struct BoardKeyDispatchTests {
    private let backlog = BoardColumn.backlog.id
    private let upNext = BoardColumn.upNext.id
    private let doing = BoardColumn.inProgress.id
    private let done = BoardColumn.done.id

    /// The board's four columns hold, left to right: `dragDrop` over `cafe`,
    /// then `offline`, `sync` and `palette` one apiece — so the first column,
    /// the last column, the top of a column and the bottom of one are all a
    /// named card away.
    private func run(
        _ command: AppCommand, on id: TaskItem.ID, in store: BoardStore
    ) -> BoardKeyboard.Outcome {
        BoardKeyboard.perform(
            command, on: store[id]!, in: store, map: BoardFocusMap(store), today: TestBoard.dueDay
        )
    }

    // MARK: Moving focus

    @Test func theArrowsMoveFocusAndTheInspectorFollowsIt() {
        let store = TestBoard.store()

        #expect(run(.focusCardBelow, on: TestBoard.dragDrop, in: store)
                == .init(isHandled: true, focus: TestBoard.cafe))
        // Focus is how the board is read as well as driven: what the keyboard
        // is on is what the inspector is showing.
        #expect(store.selectedID == TestBoard.cafe)

        #expect(run(.focusCardAbove, on: TestBoard.cafe, in: store)
                == .init(isHandled: true, focus: TestBoard.dragDrop))
        #expect(run(.focusNextColumn, on: TestBoard.dragDrop, in: store)
                == .init(isHandled: true, focus: TestBoard.offline))
        #expect(run(.focusPreviousColumn, on: TestBoard.offline, in: store)
                == .init(isHandled: true, focus: TestBoard.dragDrop))
        #expect(store.selectedID == TestBoard.dragDrop)
    }

    /// The four edges of the board. A refusal keeps the key rather than taking
    /// it: `isHandled` false is what lets the scroll view scroll, and focus has
    /// to stay exactly where it was rather than falling to nothing.
    @Test func focusRefusesAtEveryEdgeAndKeepsTheCardItIsOn() {
        let store = TestBoard.store()
        store.select(TestBoard.dragDrop)

        // Top and bottom of a column.
        #expect(run(.focusCardAbove, on: TestBoard.dragDrop, in: store)
                == .init(isHandled: false, focus: TestBoard.dragDrop))
        #expect(run(.focusCardBelow, on: TestBoard.cafe, in: store)
                == .init(isHandled: false, focus: TestBoard.cafe))
        // First and last column.
        #expect(run(.focusPreviousColumn, on: TestBoard.dragDrop, in: store)
                == .init(isHandled: false, focus: TestBoard.dragDrop))
        #expect(run(.focusNextColumn, on: TestBoard.palette, in: store)
                == .init(isHandled: false, focus: TestBoard.palette))

        // And a refusal changed nothing on the way past.
        #expect(store.selectedID == TestBoard.dragDrop)
    }

    // MARK: Moving the card

    /// ⌥→ moves the card and focus stays on it, so a run of them walks the card
    /// across the board rather than leaving the keyboard behind in Backlog.
    @Test func optionArrowMovesTheCardAndFocusFollowsItAcrossTheBoard() {
        let (store, undo) = TestBoard.undoing()

        step(undo) {
            #expect(run(.moveCardRight, on: TestBoard.dragDrop, in: store)
                    == .init(isHandled: true, focus: TestBoard.dragDrop))
        }
        #expect(store[TestBoard.dragDrop]?.columnID == upNext)

        // The second press is measured from where the card is now.
        step(undo) { _ = run(.moveCardRight, on: TestBoard.dragDrop, in: store) }
        #expect(store[TestBoard.dragDrop]?.columnID == doing)

        step(undo) { _ = run(.moveCardLeft, on: TestBoard.dragDrop, in: store) }
        #expect(store[TestBoard.dragDrop]?.columnID == upNext)
        #expect(undo.actionNames == ["Move Task", "Move Task", "Move Task"])
    }

    @Test func aCardRefusesToLeaveTheBoardAtEitherEnd() {
        let (store, undo) = TestBoard.undoing()
        let before = store.tasks

        step(undo) {
            #expect(run(.moveCardLeft, on: TestBoard.dragDrop, in: store)
                    == .init(isHandled: false, focus: TestBoard.dragDrop))
            #expect(run(.moveCardRight, on: TestBoard.palette, in: store)
                    == .init(isHandled: false, focus: TestBoard.palette))
        }
        #expect(store.tasks == before)
        #expect(undo.actionNames.isEmpty)
    }

    /// Unlike focus movement, which steps over an empty column, a card moves
    /// into one: an empty column is most of what an empty column is for.
    @Test func aCardMovesIntoTheEmptyColumnFocusWouldStepOver() {
        let store = TestBoard.store()
        store.deleteTask(TestBoard.offline)

        #expect(run(.focusNextColumn, on: TestBoard.dragDrop, in: store)
                == .init(isHandled: true, focus: TestBoard.sync))
        #expect(run(.moveCardRight, on: TestBoard.cafe, in: store)
                == .init(isHandled: true, focus: TestBoard.cafe))
        #expect(store[TestBoard.cafe]?.columnID == upNext)
    }

    /// ⌥→ carries the whole selection when the focused card is part of it, the
    /// rule every other command here follows.
    @Test func movingACardInTheSelectionMovesTheSelection() {
        let (store, undo) = TestBoard.undoing()
        store.selectAll([TestBoard.dragDrop, TestBoard.cafe])

        step(undo) { _ = run(.moveCardRight, on: TestBoard.dragDrop, in: store) }
        #expect(store[TestBoard.dragDrop]?.columnID == upNext)
        #expect(store[TestBoard.cafe]?.columnID == upNext)
        #expect(undo.actionNames == ["Move Tasks"])
    }

    // MARK: ⏎, Space and ⌘⌫

    @Test func returnOpensTheDetailSurfaceOnTheFocusedCard() {
        let store = TestBoard.store()
        // Closed first: the inspector opens by default, and a test that did not
        // shut it would pass against a ⏎ that opens nothing.
        store.isInspectorOpen = false

        #expect(run(.openTask, on: TestBoard.cafe, in: store)
                == .init(isHandled: true, focus: TestBoard.cafe))
        #expect(store.isInspectorOpen)
        #expect(store.selectedID == TestBoard.cafe)
    }

    /// Space is the tick beside the card, so on one card it toggles — and a
    /// second press has to put it back where it came from, or the key is a
    /// one-way trip that reads as a toggle.
    @Test func spaceTogglesOneCardBothWays() {
        let (store, undo) = TestBoard.undoing()

        step(undo) {
            #expect(run(.completeTask, on: TestBoard.dragDrop, in: store)
                    == .init(isHandled: true, focus: TestBoard.dragDrop))
        }
        #expect(store[TestBoard.dragDrop]?.columnID == done)

        step(undo) { _ = run(.completeTask, on: TestBoard.dragDrop, in: store) }
        #expect(store[TestBoard.dragDrop]?.columnID == backlog)
        #expect(undo.actionNames == ["Complete Task", "Reopen Task"])
    }

    /// Several cards complete rather than toggling: "reopen three of these and
    /// complete the other two" is not a thing one key can mean.
    @Test func spaceOnASelectionCompletesAndNeverReopens() {
        let (store, undo) = TestBoard.undoing()
        store.selectAll([TestBoard.dragDrop, TestBoard.palette])

        step(undo) { _ = run(.completeTask, on: TestBoard.dragDrop, in: store) }
        #expect(store[TestBoard.dragDrop]?.columnID == done)
        // The one already in Done stayed there rather than being reopened.
        #expect(store[TestBoard.palette]?.columnID == done)
        #expect(undo.actionNames == ["Complete Task"])
    }

    /// ⌘⌫ hands the keyboard on before the card it is on leaves the board.
    @Test func deletingHandsFocusToTheNeighbourAndThenToNothing() {
        let (store, undo) = TestBoard.undoing()

        step(undo) {
            #expect(run(.deleteTask, on: TestBoard.dragDrop, in: store)
                    == .init(isHandled: true, focus: TestBoard.cafe))
        }
        #expect(store[TestBoard.dragDrop] == nil)

        // Last card in its column, and focus has nowhere to fall.
        step(undo) {
            #expect(run(.deleteTask, on: TestBoard.sync, in: store)
                    == .init(isHandled: true, focus: nil))
        }
        #expect(undo.actionNames == ["Delete Task", "Delete Task"])
    }

    // MARK: ⌘A and ⎋

    @Test func selectAllAndDeselectActOnTheSurfaceAndLeaveFocusAlone() {
        let store = TestBoard.store()

        #expect(run(.selectAll, on: TestBoard.cafe, in: store)
                == .init(isHandled: true, focus: TestBoard.cafe))
        #expect(store.selection == Set(store.visibleTaskIDs(today: TestBoard.dueDay)))

        #expect(run(.deselect, on: TestBoard.cafe, in: store)
                == .init(isHandled: true, focus: TestBoard.cafe))
        #expect(store.selection.isEmpty)
    }

    /// Nothing the card claims falls through to the dispatcher's `default`. A
    /// command dropped out of the switch is a key that stops working and takes
    /// no test with it — the press still matches, and the card still refuses.
    @Test func everyCommandTheCardClaimsIsRoutedSomewhere() {
        let cards = [TestBoard.dragDrop, TestBoard.cafe, TestBoard.offline,
                     TestBoard.sync, TestBoard.palette]
        for command in BoardKeyboard.boardCommands {
            let handled = cards.contains { id in
                let store = TestBoard.store()
                return run(command, on: id, in: store).isHandled
            }
            #expect(handled, "\(command.rawValue) is claimed by the card and routed nowhere")
        }
    }
}

/// The two rings a card can wear, which a card can wear at once.
///
/// Under `accessibilityDifferentiateWithoutColor` a ring is a shape and a
/// thickness and nothing else, so two rings in `palette.accent` that differ only
/// in colour are one ring — and "this card is selected" and "this card has the
/// keyboard" become the same statement. The contract asks for a difference in
/// width *or* inset; both are cheap, and either one alone is one edit away from
/// being tidied out.
@Suite struct FocusRingTests {
    /// The ordinary selected card. Both rings land on it now — the selection
    /// follows the keyboard onto whatever it is on — so a second ring inside
    /// the first would be one border drawn twice.
    @Test func aCardThatIsTheWholeSelectionWearsOneRing() {
        #expect(!BoardTaskCard.drawsFocusRing(isFocused: true, isSelected: true, selectionCount: 1))
        // And the selection ring alone on a card the keyboard is not on.
        #expect(!BoardTaskCard.drawsFocusRing(isFocused: false, isSelected: true, selectionCount: 1))
    }

    /// The two states where focus is not the same fact as selection, and the
    /// inner ring is the only thing that marks it.
    @Test func theFocusRingReturnsWhereTheSelectionRingCannotSayIt() {
        // Inside a multi-selection every card wears the outer ring alike; this
        // is the one the arrows move from and ⇧ sweeps from.
        #expect(BoardTaskCard.drawsFocusRing(isFocused: true, isSelected: true, selectionCount: 3))
        // And where a ⌘-click has taken the focused card out of the selection,
        // which would otherwise leave the keyboard on a card marked nothing.
        #expect(BoardTaskCard.drawsFocusRing(isFocused: true, isSelected: false, selectionCount: 1))
        #expect(BoardTaskCard.drawsFocusRing(isFocused: true, isSelected: false, selectionCount: 0))
    }

    /// Asked of every preset rather than of one pair of statics. The rings used
    /// to be constants on `Ring` fitted to the desk's 12pt corner, so the pad's
    /// card — rounded at 14 — wore a selection ring 2pt inside its own edge.
    @Test func theFocusRingIsReadableWithoutColour() {
        for metrics in [BoardTaskCard.Metrics.desk, .pad] {
            let selection = metrics.selectionRing
            let focus = metrics.focusRing

            #expect(focus.lineWidth != selection.lineWidth, "the two rings are one thickness")
            #expect(focus.inset != selection.inset, "the two rings sit on one line")
            // Inside the selection's, so a card wearing both reads as a ring
            // within a ring rather than as one ring that has moved.
            #expect(focus.inset > selection.inset)
            #expect(focus.lineWidth < selection.lineWidth)
            // And a ring inset from the corner has to be rounded tighter or it
            // crosses the corner it is following.
            #expect(focus.cornerRadius < selection.cornerRadius)
        }
    }

    /// The ring is drawn on the card's own edge, so it has to be rounded like
    /// it: a radius that no longer matches reads as a rectangle laid over a
    /// rounded card at exactly the four places anyone looks.
    @Test func theRingsFollowTheCardsCorner() {
        for metrics in [BoardTaskCard.Metrics.desk, .pad] {
            #expect(metrics.selectionRing.cornerRadius == metrics.cornerRadius)
            // And the inner one follows it in, by the amount it is set in by.
            #expect(metrics.focusRing.cornerRadius == metrics.cornerRadius - metrics.focusRing.inset)
        }
    }
}

#endif
