// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

/// Clone-on-complete: finishing a recurring card leaves the completed
/// occurrence in Done and mints the next one — a fresh card in the board's
/// first column with the rule aboard, the due date advanced, and the
/// checklist unticked. These drive `BoardStore` through the public verbs the
/// surfaces use, so every completion route is the same route the hook lives on.
@MainActor
@Suite struct RecurringTaskTests {
    private let weekly = RecurrenceRule(interval: 1, unit: .week)

    /// The card a completion spawned: the one wearing the completed card's
    /// code in its birth entry.
    private func spawn(of code: String, in store: BoardStore) -> TaskItem? {
        store.tasks.first { task in
            task.activity.contains { entry in
                if case .repeatOf(let source) = entry.kind { return source == code }
                return false
            }
        }
    }

    private func kinds(of task: TaskItem?) -> [ActivityEntry.Kind] {
        task?.activity.map(\.kind) ?? []
    }

    // MARK: The spawn

    @Test func completingARecurringCardSpawnsItsNextOccurrence() throws {
        let store = TestBoard.store()
        store.setRecurrence(weekly, on: TestBoard.dragDrop)
        let before = store.tasks.count
        let today = CalendarDay(.now)
        let expected = try #require(weekly.nextOccurrence(after: today, due: TestBoard.dueDay))

        store.complete(TestBoard.dragDrop)

        // The completed occurrence: in Done, rule gone, naming what it became.
        let completed = try #require(store[TestBoard.dragDrop])
        #expect(completed.columnID == BoardColumn.done.id)
        #expect(completed.recurrence == nil)

        // The spawn: a fresh card in the first column, everything carried.
        #expect(store.tasks.count == before + 1)
        let next = try #require(spawn(of: "NW-121", in: store))
        #expect(next.id != completed.id)
        #expect(next.code == BoardSnapshot.code(forSerial: BoardSnapshot.baseSerial))
        #expect(kinds(of: completed).contains(.repeatedAs(code: next.code)))
        #expect(next.columnID == BoardColumn.backlog.id)
        #expect(next.boardID == completed.boardID)
        #expect(next.title == completed.title)
        #expect(next.note == completed.note)
        #expect(next.labelKeys == completed.labelKeys)
        #expect(next.priority == completed.priority)
        #expect(next.due == expected)
        #expect(next.recurrence == weekly)

        // The checklist came across with every box unticked — the move to Done
        // ticked the completed copy's, and those ticks must not travel.
        #expect(next.subtasks.map(\.text) == completed.subtasks.map(\.text))
        #expect(next.subtasks.allSatisfy { !$0.done })
        #expect(Set(next.subtasks.map(\.id)).isDisjoint(with: completed.subtasks.map(\.id)))

        // Born of a repeat rather than created: the birth entry says so.
        #expect(kinds(of: next) == [.repeatOf(code: "NW-121")])
    }

    @Test func theSpawnTakesTheNextSerialRatherThanReusingOne() throws {
        let store = TestBoard.store()
        store.setRecurrence(weekly, on: TestBoard.dragDrop)
        store.complete(TestBoard.dragDrop)
        let next = try #require(spawn(of: "NW-121", in: store))

        // A card minted afterwards gets the serial after the spawn's.
        let added = store.addTask(to: .inbox, title: "After")
        let addedCode = try #require(store[added]?.code)
        #expect(next.code == BoardSnapshot.code(forSerial: BoardSnapshot.baseSerial))
        #expect(addedCode == BoardSnapshot.code(prefix: Board.inboxCodePrefix,
                                                forSerial: BoardSnapshot.baseSerial + 1))
    }

    @Test func aDragOntoDoneSpawnsLikeTheTick() throws {
        let store = TestBoard.store()
        store.setRecurrence(weekly, on: TestBoard.dragDrop)
        store.move(TestBoard.dragDrop, to: BoardColumn.done.id)

        #expect(store[TestBoard.dragDrop]?.recurrence == nil)
        #expect(spawn(of: "NW-121", in: store) != nil)
    }

    @Test func aBulkCompleteSpawnsOncePerRecurringCard() throws {
        let store = TestBoard.store()
        store.setRecurrence(weekly, on: TestBoard.dragDrop)
        store.setRecurrence(weekly, on: TestBoard.cafe)
        let before = store.tasks.count

        store.complete([TestBoard.dragDrop, TestBoard.cafe, TestBoard.sync])

        #expect(store.tasks.count == before + 2)
        #expect(spawn(of: "NW-121", in: store) != nil)
        #expect(spawn(of: "NW-122", in: store) != nil)
    }

    @Test func anInboxCardCompletesInPlaceAndSpawnsAFreshCapture() throws {
        let store = TestBoard.store()
        let today = CalendarDay(.now)
        store.setRecurrence(weekly, on: TestBoard.widget, today: today)

        store.complete(TestBoard.widget)

        let completed = try #require(store[TestBoard.widget])
        #expect(completed.isInboxCompleted)
        #expect(completed.recurrence == nil)

        let next = try #require(spawn(of: "NW-120", in: store))
        #expect(next.isUnfiled)
        #expect(!next.isInboxCompleted)
        #expect(next.due == today.adding(days: 7))
        #expect(next.recurrence == weekly)
        #expect(kinds(of: completed).contains(.repeatedAs(code: next.code)))
    }

    // MARK: The rule running out

    @Test func aRuleAtItsEndDateCompletesWithoutSpawning() throws {
        let store = TestBoard.store()
        let ended = RecurrenceRule(interval: 1, unit: .week, until: TestBoard.dueDay)
        store.setRecurrence(ended, on: TestBoard.dragDrop)
        let before = store.tasks.count

        store.complete(TestBoard.dragDrop)

        #expect(store.tasks.count == before)
        let completed = try #require(store[TestBoard.dragDrop])
        #expect(completed.columnID == BoardColumn.done.id)
        #expect(completed.recurrence == nil)
        #expect(kinds(of: completed).contains(.repeatEnded))
        #expect(spawn(of: "NW-121", in: store) == nil)
    }

    // MARK: Undo

    @Test func oneUndoRemovesTheSpawnAndUncompletes() throws {
        let (store, undo) = TestBoard.undoing()
        step(undo) { store.setRecurrence(weekly, on: TestBoard.dragDrop) }
        let armed = store.tasks

        step(undo) { store.complete(TestBoard.dragDrop) }
        #expect(store.tasks.count == armed.count + 1)

        undo.undo()
        #expect(store.tasks == armed)
        #expect(store[TestBoard.dragDrop]?.columnID == BoardColumn.backlog.id)
        #expect(store[TestBoard.dragDrop]?.recurrence == weekly)
    }

    // MARK: Setting and clearing

    @Test func enablingRepeatOnADuelessCardAnchorsItToToday() throws {
        let store = TestBoard.store()
        let today = CalendarDay(year: 2026, month: 9, day: 7)
        #expect(store[TestBoard.cafe]?.due == nil)

        store.setRecurrence(weekly, on: TestBoard.cafe, today: today)

        #expect(store[TestBoard.cafe]?.due == today)
        #expect(store[TestBoard.cafe]?.recurrence == weekly)
    }

    @Test func theRuleGoesInNormalized() throws {
        let store = TestBoard.store()
        let monthly = RecurrenceRule(interval: 1, unit: .month)
        store.setRecurrence(monthly, on: TestBoard.dragDrop)
        // Anchored to the card's own due day, so the 20th survives short months.
        #expect(store[TestBoard.dragDrop]?.recurrence?.anchorDay == TestBoard.dueDay.day)
    }

    @Test func settingLogsTheRuleAndClearingLogsTheRemoval() throws {
        let store = TestBoard.store()
        store.setRecurrence(weekly, on: TestBoard.dragDrop)
        #expect(kinds(of: store[TestBoard.dragDrop]).first == .repeatSet(weekly))

        store.clearRecurrence(on: TestBoard.dragDrop)
        #expect(store[TestBoard.dragDrop]?.recurrence == nil)
        #expect(kinds(of: store[TestBoard.dragDrop]).first == .repeatCleared)
    }

    @Test func aPickerSessionCoalescesToOneEntry() throws {
        let store = TestBoard.store()
        store.beginEditing(.recurrence, on: TestBoard.dragDrop, scope: .desk)
        store.setRecurrence(weekly, on: TestBoard.dragDrop, scope: .desk)
        let settled = RecurrenceRule(interval: 3, unit: .day)
        store.setRecurrence(settled, on: TestBoard.dragDrop, scope: .desk)
        store.endEditing(.recurrence, on: TestBoard.dragDrop, scope: .desk)

        let repeats = kinds(of: store[TestBoard.dragDrop]).filter {
            if case .repeatSet = $0 { return true }
            return false
        }
        #expect(repeats == [.repeatSet(settled)])
    }

    @Test func clearingARuleThatIsNotThereChangesNothing() throws {
        let store = TestBoard.store()
        let before = store.tasks
        store.clearRecurrence(on: TestBoard.dragDrop)
        #expect(store.tasks == before)
    }
}
