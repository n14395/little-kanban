import Foundation
import Testing
@testable import Simple_Kanban

/// The saved-view predicates, asked at the day either side of every bound they
/// draw.
///
/// A predicate test that only looks at the middle of a range cannot fail on an
/// off-by-one, which is the defect these actually have: `>` for `>=`, `1...6`
/// for `0...6`, an urgency case left out. So every view here is asked about the
/// task one day inside its bound and the task one day outside it, and the board
/// under it (`ViewBoard`) exists to have a task on each of those days.
@MainActor
@Suite struct SavedViewTests {
    private let today = ViewBoard.today

    private func codes(_ view: SavedView, _ store: BoardStore, on day: CalendarDay? = nil) -> [String] {
        store.tasks(in: view, today: day ?? today).map(\.code)
    }

    /// The predicate on its own, away from the store's ordering and cap.
    private func matches(_ view: SavedView, _ id: TaskItem.ID, on day: CalendarDay? = nil) -> Bool {
        let task = ViewBoard.tasks.first { $0.id == id }!
        return view.matches(task, today: day ?? today, isDone: task.columnID == BoardColumn.done.id)
    }

    // MARK: Today — overdue is not allowed to fall out of it

    @Test func todayIsOverdueAndTodayAndStopsAtTomorrow() {
        #expect(matches(.today, ViewBoard.longOverdue))          // eight days past
        #expect(matches(.today, ViewBoard.overdueYesterday))     // one day past
        #expect(matches(.today, ViewBoard.dueToday))             // the day itself
        #expect(matches(.today, ViewBoard.dueTomorrow) == false) // one day ahead
        #expect(matches(.today, ViewBoard.dueInSix) == false)
        // No due date is not "due today", however urgent the task looks.
        #expect(matches(.today, ViewBoard.noDueHigh) == false)

        let store = ViewBoard.store()
        #expect(codes(.today, store) == ["NW-201", "NW-202", "NW-206"])
    }

    // MARK: Upcoming — strictly ahead

    @Test func upcomingStartsTomorrowAndNeverLooksBack() {
        #expect(matches(.upcoming, ViewBoard.dueToday) == false)   // 0 is not ahead
        #expect(matches(.upcoming, ViewBoard.dueTomorrow))
        #expect(matches(.upcoming, ViewBoard.dueInSeven))          // no far bound
        #expect(matches(.upcoming, ViewBoard.overdueYesterday) == false)
        #expect(matches(.upcoming, ViewBoard.longOverdue) == false)
        #expect(matches(.upcoming, ViewBoard.noDueLow) == false)

        let store = ViewBoard.store()
        #expect(codes(.upcoming, store) == ["NW-203", "NW-204", "NW-205"])
    }

    // MARK: Due this week — 0...6, and neither neighbour

    @Test func dueThisWeekIsSevenDaysCountingToday() {
        #expect(matches(.dueThisWeek, ViewBoard.overdueYesterday) == false)  // -1
        #expect(matches(.dueThisWeek, ViewBoard.dueToday))                   // 0
        #expect(matches(.dueThisWeek, ViewBoard.dueTomorrow))                // 1
        #expect(matches(.dueThisWeek, ViewBoard.dueInSix))                   // 6
        #expect(matches(.dueThisWeek, ViewBoard.dueInSeven) == false)        // 7
        #expect(matches(.dueThisWeek, ViewBoard.noDueHigh) == false)

        let store = ViewBoard.store()
        #expect(codes(.dueThisWeek, store) == ["NW-202", "NW-203", "NW-204"])

        // The window is seven days wide wherever it is put: a day later the
        // task that was seven out is in, and the one that was due today is not.
        let tomorrow = today.adding(days: 1)
        #expect(matches(.dueThisWeek, ViewBoard.dueInSeven, on: tomorrow))
        #expect(matches(.dueThisWeek, ViewBoard.dueToday, on: tomorrow) == false)
    }

    // MARK: High priority — a filter on the task, not on the calendar

    @Test func highPriorityIgnoresDueDatesEntirely() {
        #expect(matches(.highPriority, ViewBoard.noDueHigh))        // no due date at all
        #expect(matches(.highPriority, ViewBoard.longOverdue))      // eight days overdue
        #expect(matches(.highPriority, ViewBoard.noDueLow) == false)
        #expect(matches(.highPriority, ViewBoard.dueToday) == false)  // medium, due today

        let store = ViewBoard.store()
        #expect(codes(.highPriority, store) == ["NW-206", "NW-207"])
        // …and it says the same thing on any day, which is the point of it.
        #expect(codes(.highPriority, store, on: today.adding(days: 400)) == ["NW-206", "NW-207"])
        #expect(codes(.highPriority, store, on: today.adding(days: -400)) == ["NW-206", "NW-207"])
    }

    // MARK: Recently updated — ordering, cap, and Done left in

    @Test func recentlyUpdatedIsNewestFirstAndKeepsDone() {
        let store = ViewBoard.store()
        // Written in a board order that is nothing like this, so a build that
        // never sorted would return the array it was given.
        #expect(codes(.recentlyUpdated, store) == [
            "NW-202", "NW-206", "NW-204", "NW-208", "NW-201",
            "NW-209", "NW-205", "NW-207", "NW-203", "NW-210",
        ])
        // The two Done tasks are in it — NW-209 in the middle, NW-210 last.
        #expect(codes(.recentlyUpdated, store).contains("NW-209"))
        #expect(codes(.recentlyUpdated, store).contains("NW-210"))
        #expect(matches(.recentlyUpdated, ViewBoard.doneDueToday))
    }

    @Test func recentlyUpdatedStopsAtTwenty() {
        let store = ViewBoard.store(tasks: ViewBoard.deepTasks)
        let listed = codes(.recentlyUpdated, store)
        #expect(listed.count == 20)
        #expect(listed.first == "NW-301")            // the newest
        #expect(listed.last == "NW-320")             // the twentieth
        #expect(listed == (1...20).map { String(format: "NW-3%02d", $0) })
        #expect(listed.contains("NW-321") == false)  // the twenty-first is dropped
        #expect(SavedView.recentlyUpdated.limit == 20)
        // The count on the row is the capped one too: the pill counts what the
        // list would show, or it is reporting a list nobody can reach.
        #expect(store.count(of: .recentlyUpdated, today: today) == 20)
    }

    @Test func onlyRecentlyUpdatedAndTheArchiveOverrideTheBoardsOwnOrder() {
        #expect(SavedView.today.sort == nil)
        #expect(SavedView.upcoming.sort == nil)
        #expect(SavedView.highPriority.sort == nil)
        #expect(SavedView.dueThisWeek.sort == nil)
        #expect(SavedView.recentlyUpdated.sort != nil)
        #expect(SavedView.archive.sort != nil)
        for view in SavedView.allCases where view != .recentlyUpdated {
            #expect(view.limit == nil, "\(view.rawValue) should not cap its list")
        }
    }

    // MARK: Done, which four of the six views leave out

    @Test func everyViewButRecentlyUpdatedAndTheArchiveLeavesDoneOut() {
        let store = ViewBoard.store()
        for view in [SavedView.today, .upcoming, .dueThisWeek, .highPriority] {
            let listed = codes(view, store)
            #expect(listed.contains("NW-209") == false, "\(view.rawValue) kept a Done task")
            #expect(listed.contains("NW-210") == false, "\(view.rawValue) kept a Done task")
        }
        // NW-209 is due today and high priority: were it anywhere else it would
        // be in three of them.
        #expect(matches(.today, ViewBoard.doneDueToday) == false)
        #expect(matches(.dueThisWeek, ViewBoard.doneDueToday) == false)
        #expect(matches(.highPriority, ViewBoard.doneDueToday) == false)
        #expect(matches(.upcoming, ViewBoard.doneUpcoming) == false)

        // …and finishing a task takes it out of them while it is still on screen.
        #expect(codes(.today, store) == ["NW-201", "NW-202", "NW-206"])
        store.complete(ViewBoard.dueToday)
        #expect(codes(.today, store) == ["NW-201", "NW-206"])
        #expect(codes(.dueThisWeek, store) == ["NW-203", "NW-204"])
    }

    // MARK: The archive, which is the only view that has it

    @Test func everyViewButTheArchiveLeavesArchivedTasksOut() {
        let store = ViewBoard.store(tasks: ViewBoard.tasks(archiving: [
            ViewBoard.dueToday: 900,        // filed first
            ViewBoard.dueTomorrow: 300,
            ViewBoard.noDueHigh: 600,
            ViewBoard.doneDueToday: 100,    // filed last
        ]))
        #expect(codes(.today, store) == ["NW-201", "NW-206"])
        #expect(codes(.upcoming, store) == ["NW-204", "NW-205"])
        #expect(codes(.dueThisWeek, store) == ["NW-204"])
        #expect(codes(.highPriority, store) == ["NW-206"])
        #expect(codes(.recentlyUpdated, store) == [
            "NW-206", "NW-204", "NW-208", "NW-201", "NW-205", "NW-210",
        ])
        for view in SavedView.filters {
            #expect(store.count(of: view, today: today) == codes(view, store).count)
        }
    }

    @Test func theArchiveIsNewestFiledFirst() {
        let store = ViewBoard.store(tasks: ViewBoard.tasks(archiving: [
            ViewBoard.dueToday: 900,
            ViewBoard.dueTomorrow: 300,
            ViewBoard.noDueHigh: 600,
            ViewBoard.doneDueToday: 100,
        ]))
        // Board order is 202, 203, 207, 209; this is close to its reverse, so a
        // list that was never sorted — or sorted the other way — cannot pass.
        #expect(codes(.archive, store) == ["NW-209", "NW-203", "NW-207", "NW-202"])
        #expect(store.count(of: .archive, today: today) == 4)
        // It keeps Done, and it is the only view an archived task is in.
        #expect(matches(.archive, ViewBoard.doneDueToday) == false)   // not filed on this board
        #expect(SavedView.filters.contains(.archive) == false)
        #expect(SavedView.filters == [.today, .upcoming, .highPriority, .dueThisWeek, .recentlyUpdated])
    }

    @Test func filingAWholeColumnAtOnceKeepsTheBoardsOrderUnderneath() {
        // `archiveCompleted` files everything on one instant, so every row in
        // the Archive ties. The order then has to be the one the board had,
        // rather than whatever an unstable sort left behind.
        let store = ViewBoard.store()
        store.move(ViewBoard.overdueYesterday, to: BoardColumn.done.id)
        store.move(ViewBoard.dueInSix, to: BoardColumn.done.id)
        store.archiveCompleted()
        // A move appends, so the board's Done column reads 209, 210, 201, 204 —
        // and with every `archivedAt` identical that is what the Archive shows.
        #expect(codes(.archive, store) == ["NW-209", "NW-210", "NW-201", "NW-204"])
    }

    // MARK: Search composes with a view

    @Test func aQueryNarrowsTheViewRatherThanReplacingIt() {
        let store = ViewBoard.store()
        store.query = "NW-206"
        #expect(codes(.today, store) == ["NW-206"])
        #expect(codes(.highPriority, store) == ["NW-206"])
        // A task the query finds but the view does not contain stays out.
        #expect(codes(.upcoming, store) == [])
        store.query = "NW-203"
        #expect(codes(.upcoming, store) == ["NW-203"])
        #expect(codes(.today, store) == [])

        // The row's pill counts the view, not the search: a badge that shrank
        // as the user typed on another surface would be reporting the query.
        #expect(store.count(of: .today, today: today) == 3)
        #expect(store.count(of: .upcoming, today: today) == 3)
        store.clearQuery()
        #expect(codes(.today, store) == ["NW-201", "NW-202", "NW-206"])
    }

    @Test func theViewIsAppliedFirstAndTheQuerySecond() {
        // Twenty-five tasks, so the cap has something to cut, and a query aimed
        // squarely at what it cut. Filtering first and capping after would hand
        // back rows the view does not contain.
        let store = ViewBoard.store(tasks: ViewBoard.deepTasks)
        store.query = "NW-325"
        #expect(codes(.recentlyUpdated, store) == [])
        store.query = "NW-32"
        // NW-320 through NW-325 all match; only NW-320 is inside the cap.
        #expect(codes(.recentlyUpdated, store) == ["NW-320"])
        #expect(store.count(of: .recentlyUpdated, today: today) == 20)
    }


    // MARK: The badge and the list — which number each of them is

    /// The rule both surfaces settled on, pinned for every case at once.
    ///
    /// `count(of:)` is the view's *membership*. It is the badge on a
    /// destination — a sidebar row, a drawer row, a menu item — and one that
    /// shrank as the user typed into a field on another surface would be
    /// reporting the query rather than the view. A count drawn directly *on top
    /// of* a list is that list's length instead, which is why
    /// `MacSavedViewList` heads its rows with `tasks(in:).count`.
    ///
    /// Which leaves exactly one invariant, and it has to hold for every case:
    /// with nothing typed, the two are the same number. A gap there is not a
    /// scoping decision, it is the badge and the list disagreeing about what
    /// the view contains — a pill reading "7" over an empty list.
    @Test func everyViewsCountIsItsListsLengthWhenNothingIsTyped() {
        let filed = ViewBoard.tasks(archiving: [
            ViewBoard.dueToday: 900, ViewBoard.dueTomorrow: 300,
            ViewBoard.noDueHigh: 600, ViewBoard.doneDueToday: 100,
        ])
        let boards: [(String, [TaskItem])] = [
            ("the bounds board", ViewBoard.tasks),
            ("a board with an archive", filed),
            ("a board deeper than the cap", ViewBoard.deepTasks),
            ("an empty board", []),
        ]
        // Three days, so a view whose membership is empty on one of them is not
        // the only thing being asked about.
        let days = [today, today.adding(days: -9), today.adding(days: 40)]

        for (name, tasks) in boards {
            let store = ViewBoard.store(tasks: tasks)
            for view in SavedView.allCases {
                for day in days {
                    #expect(store.count(of: view, today: day)
                            == store.tasks(in: view, today: day).count,
                            "\(view.rawValue) on \(name) counts something it does not list")
                }
            }
        }
    }

    /// …and the query is the only thing allowed to part them.
    ///
    /// Every row the query leaves is still a row the view contains, the badge
    /// does not move, and clearing the query closes the gap again. A build that
    /// narrowed the badge would pass the previous test and fail this one; a
    /// build that stopped narrowing the list would fail both.
    @Test func aQueryIsTheOnlyThingThatMayPartTheBadgeFromTheList() {
        let store = ViewBoard.store(tasks: ViewBoard.tasks(archiving: [
            ViewBoard.dueToday: 900, ViewBoard.dueTomorrow: 300,
            ViewBoard.noDueHigh: 600, ViewBoard.doneDueToday: 100,
        ]))
        let membership = Dictionary(uniqueKeysWithValues: SavedView.allCases.map {
            ($0, store.count(of: $0, today: today))
        })
        let unqueried = Dictionary(uniqueKeysWithValues: SavedView.allCases.map {
            ($0, Set(codes($0, store)))
        })

        for query in ["NW-206", "bound", "zzzz", "NW-2"] {
            store.query = query
            for view in SavedView.allCases {
                let listed = codes(view, store)
                #expect(store.count(of: view, today: today) == membership[view],
                        "\(view.rawValue)'s badge moved when the query did")
                #expect(listed.count <= membership[view]!,
                        "\(view.rawValue) listed more rows than it contains")
                #expect(Set(listed).isSubset(of: unqueried[view]!),
                        "\(view.rawValue) let the query add a row the view does not contain")
            }
        }

        store.clearQuery()
        for view in SavedView.allCases {
            #expect(store.count(of: view, today: today) == codes(view, store).count)
        }
    }

    /// The cap is part of the membership, not part of the query, so it lands on
    /// both numbers the same way. Twenty-five tasks and a query aimed squarely
    /// at the five the cap cut.
    @Test func theCapCountsAgainstTheBadgeAndTheListAlike() {
        let store = ViewBoard.store(tasks: ViewBoard.deepTasks)
        #expect(store.count(of: .recentlyUpdated, today: today) == 20)
        #expect(codes(.recentlyUpdated, store).count == 20)

        store.query = "NW-325"
        #expect(codes(.recentlyUpdated, store).isEmpty)   // outside the cap
        #expect(store.count(of: .recentlyUpdated, today: today) == 20)

        store.clearQuery()
        #expect(store.count(of: .recentlyUpdated, today: today)
                == codes(.recentlyUpdated, store).count)
    }

    // MARK: The enum's own surface

    @Test func everyViewNamesItselfAndCarriesASymbol() {
        #expect(SavedView.allCases.count == 6)
        #expect(SavedView.allCases.map(\.id) == SavedView.allCases.map(\.rawValue))
        #expect(Set(SavedView.allCases.map(\.label)).count == 6)
        #expect(Set(SavedView.allCases.map(\.symbol)).count == 6)
        #expect(SavedView.allCases.allSatisfy { !$0.label.isEmpty && !$0.symbol.isEmpty })
        // It is `Codable` against its raw value, so a later phase can remember
        // the last view as a preference without inventing a mapping.
        #expect(SavedView(rawValue: "dueThisWeek") == .dueThisWeek)
    }

    @Test func theActiveViewIsSessionStateAndNotBoardData() {
        let (store, undo) = TestBoard.undoing()
        store.activeView = .highPriority
        step(undo) { store.setPriority(.low, on: TestBoard.dragDrop) }
        undo.undo()
        // A ⌘Z aimed at a card must not also move the user to another list.
        #expect(store.activeView == .highPriority)
        #expect(store[TestBoard.dragDrop]?.priority == .high)
    }
}
