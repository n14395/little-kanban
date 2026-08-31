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

    /// The same view as the *phone* draws it: the members, and then the query
    /// on top of them.
    ///
    /// The query is not part of a view any more — the desk and the iPad open a
    /// results panel instead of narrowing what is on screen, see
    /// `SearchResultsPanel` — so the composition below is asked through the one
    /// surface that still applies it, which is where `mobileTasks` puts it.
    private func narrowed(_ view: SavedView, _ store: BoardStore, on day: CalendarDay? = nil) -> [String] {
        store.narrowed(store.tasks(in: view, today: day ?? today)).map(\.code)
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

    /// **The floor, not the case.** The predicate read `== .high`, which meant
    /// a priority added *above* High would have been left out of the one list
    /// that is for urgent work — silently, and on the day it was added.
    @Test func highPriorityTakesEverythingAtLeastThatUrgent() {
        let store = ViewBoard.store()
        #expect(Set(codes(.highPriority, store)) == ["NW-206", "NW-207"])

        // A low card raised past the floor arrives.
        store.setPriority(.max, on: ViewBoard.noDueLow)
        #expect(Set(codes(.highPriority, store)) == ["NW-206", "NW-207", "NW-208"])

        // …and one dropped below it leaves, which is the same predicate read
        // the other way.
        store.setPriority(.medium, on: ViewBoard.noDueHigh)
        #expect(Set(codes(.highPriority, store)) == ["NW-206", "NW-208"])
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
        #expect(SavedView.today.sort == .manual)
        #expect(SavedView.upcoming.sort == .manual)
        #expect(SavedView.highPriority.sort == .manual)
        #expect(SavedView.dueThisWeek.sort == .manual)
        #expect(SavedView.recentlyUpdated.sort == .recentlyUpdated)
        #expect(SavedView.archive.sort == .recentlyArchived)
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
        // And the order the source list draws them in, Inbox first — where work
        // arrives, above everything that has happened to it since.
        #expect(SavedView.filters
                == [.inbox, .today, .upcoming, .highPriority, .dueThisWeek, .recentlyUpdated])
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

    /// **The view itself is never narrowed.** A query is a search now, not a
    /// filter: it opens a panel of results over whatever is on screen and
    /// leaves the surface underneath alone. The composition below is the
    /// phone's, where the field is a tab and a view opened while a query is
    /// live still narrows — with `showsMobileFilterNotice` on screen to say so.
    @Test func aQueryNarrowsTheViewRatherThanReplacingIt() {
        let store = ViewBoard.store()
        store.query = "NW-206"
        #expect(codes(.today, store) == ["NW-201", "NW-202", "NW-206"],
                "the view itself was narrowed by a search")
        #expect(narrowed(.today, store) == ["NW-206"])
        #expect(narrowed(.highPriority, store) == ["NW-206"])
        // A task the query finds but the view does not contain stays out.
        #expect(narrowed(.upcoming, store) == [])
        store.query = "NW-203"
        #expect(narrowed(.upcoming, store) == ["NW-203"])
        #expect(narrowed(.today, store) == [])

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
        #expect(narrowed(.recentlyUpdated, store) == [])
        store.query = "NW-32"
        // NW-320 through NW-325 all match; only NW-320 is inside the cap.
        #expect(narrowed(.recentlyUpdated, store) == ["NW-320"])
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
        #expect(narrowed(.recentlyUpdated, store).isEmpty)   // outside the cap
        #expect(store.count(of: .recentlyUpdated, today: today) == 20)

        store.clearQuery()
        #expect(store.count(of: .recentlyUpdated, today: today)
                == codes(.recentlyUpdated, store).count)
    }

    // MARK: The Inbox, which is a place rather than a filter

    /// The view and the panel are two faces of one list, so they had better be
    /// the same cards in the same order — a person can see both at once by
    /// picking Inbox with the panel open, and a disagreement would be visible.
    @Test func theInboxViewIsExactlyTheCardsOnNoBoardAtAll() {
        let store = TestBoard.store()
        let inView = store.tasks(in: .inbox, today: TestBoard.dueDay).map(\.id)

        #expect(!inView.isEmpty, "the fixture has no unfiled cards to test with")
        #expect(inView == store.inboxTasks.map(\.id),
                "the view and the panel disagree about the Inbox")
        #expect(store.count(of: .inbox, today: TestBoard.dueDay) == store.inboxCount)
        #expect(inView.allSatisfy { store[$0]?.isUnfiled == true })
    }

    /// An archived card is only ever in the Archive — including one that was in
    /// the Inbox when it was filed away, which is the case the shared
    /// `isArchived == (self == .archive)` guard exists for.
    @Test func anArchivedCardLeavesTheInboxView() throws {
        let store = TestBoard.store()
        let card = try #require(store.inboxTasks.first)

        store.archive(card.id)

        #expect(store.tasks(in: .inbox, today: TestBoard.dueDay).contains { $0.id == card.id } == false)
        #expect(store.tasks(in: .archive, today: TestBoard.dueDay).contains { $0.id == card.id })
    }

    /// **Every surface lists every view, unfiltered.**
    ///
    /// The phone used to drop the seeded Inbox from its drawer, because the
    /// drawer carried an Inbox row of its own a thumb's width above it. That row
    /// is gone — the tab bar's middle slot is the way to the Inbox on the phone,
    /// as the toolbar's toggle is on the desk — and the filter went with it. The
    /// views are the board file's own list, so a surface that hides one is a
    /// surface where the same file draws a shorter list than the machine next to
    /// it: from the outside that is indistinguishable from a row having gone
    /// missing, rather than from a decision anybody made.
    ///
    /// Read out of the source, because "what a list is handed" is not a value
    /// the store can be asked: every one of these draws from `store.views`, and
    /// the bug this pins is a `filter` appearing on one of them.
    @Test func everySurfaceListsTheSameViews() {
        guard SourceTree.isReachable else { return }
        let lists = [
            "Shared/BoardSidebar.swift",   // the desk and the iPad
            "IOS/PhoneNavDrawer.swift",    // the phone
            "App/BoardCommands.swift",     // the menu bar
        ]
        var seen: Set<String> = []
        for file in SourceTree.files() where lists.contains(file.path) {
            let code = String(file.code)
            #expect(code.contains("ForEach(store.views)"),
                    "\(file.path) no longer lists the board's views as they are")
            #expect(code.contains("store.views.filter") == false,
                    "\(file.path) hides a view every other surface shows")
            seen.insert(file.path)
        }
        #expect(seen == Set(lists), "a list of views moved file: found \(seen)")
    }

    // MARK: The seeded seven

    /// What the enum used to guarantee by being an enum, now that the seven are
    /// rows in a file: seven of them, each with a name, a glyph and an id of its
    /// own, and every id **fixed** rather than minted — a migration that made a
    /// fresh one each run would lose the last-surface preference on every launch
    /// and hand somebody two Archives the second time it ran.
    @Test func everySeededViewNamesItselfAndKeepsItsID() {
        let seeded = SavedView.seededAll
        #expect(seeded.count == 7)
        #expect(Set(seeded.map(\.id)).count == 7)
        #expect(Set(seeded.map(\.label)).count == 7)
        #expect(Set(seeded.map(\.symbol)).count == 7)
        #expect(seeded.allSatisfy { !$0.label.isEmpty && !$0.symbol.isEmpty })
        #expect(seeded.map(\.preset) == SavedView.Preset.allCases.map { $0 })
        // Twice through, same ids.
        #expect(SavedView.seededAll.map(\.id) == seeded.map(\.id))
        // And every one of them still says it is what it was seeded as, which
        // is what the hand-written empty states are gated on.
        #expect(seeded.allSatisfy { $0.isUnchangedPreset })
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


/// The editor's own size, and the one distinction it has to keep: on the desk it
/// is a panel and on a touch screen it is a sheet.
///
/// **The failure this pins is what a fixed height does inside a presentation
/// that has its own.** `620` was applied on every platform, so on a 402×874
/// phone the editor drew as a squat card centred in the sheet with a band of its
/// own ground above and below it, the last criterion clipped and no way to
/// scroll to it. A sheet has to be the size of the sheet, and `nil` is how this
/// says *whatever I have been given*.
@MainActor
@Suite struct SavedViewEditorMetricTests {
    /// The desk's panel is a panel: both numbers are its own, and they are the
    /// ones the rule's own nesting limit was chosen against — two brackets
    /// inside 520pt is a rule nobody can read back.
    @Test func theDeskPanelCarriesItsOwnSize() {
        #expect(SavedViewEditor.Metrics.desk.width == 520)
        #expect(SavedViewEditor.Metrics.desk.height == 620)
    }

    /// And the touch preset carries neither, which is the whole fix: the frame
    /// fills in both directions, so the editor reaches the sheet's edges instead
    /// of leaving the presentation's own ground showing at each end.
    @Test func theSheetIsTheSizeOfTheSheet() {
        #expect(SavedViewEditor.Metrics.sheet.width == nil)
        #expect(SavedViewEditor.Metrics.sheet.height == nil)
    }

    /// The other half of the same preset, kept here because it is what tells the
    /// two apart at a glance: a control under a finger claims 44 and one under a
    /// pointer claims what it draws.
    @Test func theTouchPresetClaimsATouchTarget() {
        #expect(SavedViewEditor.Metrics.sheet.hit == 44)
        #expect(SavedViewEditor.Metrics.desk.hit == 0)
    }

    /// The icon well came from Board Settings whole, so it has to arrive at
    /// both of this editor's sizes rather than at the desk's twice — a 30pt
    /// control in a sheet is the thing the touch presets exist to prevent.
    @Test func theIconWellIsSizedForTheSurfaceItIsOn() {
        #expect(SavedViewEditor.Metrics.sheet.symbolWell.height == SymbolWell.Metrics.sheet.height)
        #expect(SavedViewEditor.Metrics.desk.symbolWell.height == SymbolWell.Metrics.desk.height)
        #expect(SymbolWell.Metrics.sheet.height >= 44)
    }
}
