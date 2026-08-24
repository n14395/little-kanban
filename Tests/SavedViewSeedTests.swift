import Foundation
import Testing
@testable import Simple_Kanban

/// **The seven, rebuilt out of criteria, gathering exactly what they gathered
/// before.**
///
/// This is the acceptance test for the whole feature. The views were an enum of
/// seven hand-written predicates; they are rows in the board file now, each one
/// a `ViewRule` assembled from the same criteria the editor offers. If the
/// vocabulary were short of anything — a comparator, a field, a way to join two
/// clauses — the shortfall would show up here as a seeded view that cannot say
/// what it used to say.
///
/// **The reference predicates are written out below rather than imported**,
/// because the thing they are the reference *for* deleted them. Copying them
/// here is the only way to keep asking the question after the answer moved: they
/// are the v10 enum's `matches(_:today:isDone:week:)`, transcribed, including
/// the two exclusions it applied before its own table — archived cards belong
/// only to the Archive, and Done is left out of everything but Recently updated
/// and the Archive.
///
/// `ViewBoard` is the fixture, and it was built for this: cards a day either
/// side of today, at six and seven days out, long overdue, undated, and two in
/// the Done column — the shapes that make two nearly-right predicates disagree.
@MainActor
@Suite struct SavedViewSeedTests {
    private let store = ViewBoard.store()
    private var today: CalendarDay { TestBoard.dueDay }

    /// The old enum's predicate, transcribed. The `self` it switched on is the
    /// preset.
    private func reference(
        _ preset: SavedView.Preset, _ task: TaskItem, isDone: Bool, week: WeekMeaning
    ) -> Bool {
        guard task.isArchived == (preset == .archive) else { return false }
        let excludesDone = switch preset {
        case .inbox, .today, .upcoming, .highPriority, .dueThisWeek: true
        case .recentlyUpdated, .archive: false
        }
        guard !excludesDone || !isDone else { return false }

        switch preset {
        case .inbox:
            return task.isUnfiled
        case .today:
            guard let due = task.due else { return false }
            switch DueDate.urgency(due, from: today) {
            case .today, .overdue: return true
            case .soon, .later: return false
            }
        case .upcoming:
            guard let due = task.due else { return false }
            return DueDate.daysAway(due, from: today) > 0
        case .highPriority:
            return task.priority >= .high
        case .dueThisWeek:
            guard let due = task.due else { return false }
            return week.containsAhead(due, from: today)
        case .recentlyUpdated, .archive:
            return true
        }
    }

    /// **Every seeded view against every card, on every meaning of a week.**
    ///
    /// The week matters to exactly one of the seven and is a user preference, so
    /// leaving it at the default would test one third of *Due this week* and
    /// call it done.
    @Test(arguments: SavedView.Preset.allCases, WeekMeaning.allCases)
    func aSeededRuleGathersWhatTheEnumGathered(preset: SavedView.Preset, week: WeekMeaning) {
        let view = SavedView.seeded(preset)
        let now = Date.now

        for task in store.tasks {
            let isDone = store.isDone(task)
            let expected = reference(preset, task, isDone: isDone, week: week)
            let actual = view.matches(task, today: today, isDone: isDone, week: week, now: now)

            #expect(actual == expected,
                    "\(preset.rawValue) disagrees about \(task.code) under \(week.rawValue): rule says \(actual), the enum said \(expected)")
        }
    }

    /// The same claim over a board where things have been **filed away**, which
    /// is the half the live board cannot ask: `isArchived == (preset == .archive)`
    /// is one line of the reference and it decides six of the seven.
    @Test(arguments: SavedView.Preset.allCases)
    func aSeededRuleAgreesAboutArchivedCardsToo(preset: SavedView.Preset) {
        let archived = ViewBoard.store(tasks: ViewBoard.tasks(archiving: [
            ViewBoard.dueToday: 10,
            ViewBoard.noDueHigh: 20,
            ViewBoard.doneUpcoming: 30,
        ]))
        let view = SavedView.seeded(preset)
        let now = Date.now

        for task in archived.tasks {
            let isDone = archived.isDone(task)
            let expected = reference(preset, task, isDone: isDone, week: .fallback)
            let actual = view.matches(task, today: today, isDone: isDone, week: .fallback, now: now)

            #expect(actual == expected,
                    "\(preset.rawValue) disagrees about archived \(task.code)")
        }
    }

    /// And the two that are not only a predicate: the order they come back in,
    /// and how many of them. A rule that gathered the right cards and handed
    /// them back in board order would pass everything above and still be the
    /// wrong *Recently updated*.
    @Test func recentlyUpdatedIsStillNewestFirstAndCappedAtTwenty() {
        let view = SavedView.seeded(.recentlyUpdated)
        #expect(view.sort == .recentlyUpdated)
        #expect(view.limit == 20)

        let deep = ViewBoard.store(tasks: ViewBoard.deepTasks)
        let listed = deep.tasks(in: view, today: today).map(\.code)
        #expect(listed.count == 20)
        #expect(listed.first == "NW-301", "the newest card is not at the top")
        #expect(listed.last == "NW-320")
        #expect(listed.contains("NW-321") == false, "the cap kept a card past the twentieth")
    }

    @Test func theArchiveIsStillNewestFilingFirst() {
        let view = SavedView.seeded(.archive)
        #expect(view.sort == .recentlyArchived)
        #expect(view.limit == nil)

        // Smaller offset is a *later* filing, so this is written in the reverse
        // of the order it must come back in.
        let store = ViewBoard.store(tasks: ViewBoard.tasks(archiving: [
            ViewBoard.overdueYesterday: 300,
            ViewBoard.dueToday: 100,
            ViewBoard.dueTomorrow: 200,
        ]))
        #expect(store.tasks(in: view, today: today).map(\.code) == ["NW-202", "NW-203", "NW-201"])
    }

    /// The other five keep the order the user dragged their cards into, which is
    /// the claim that stops a sort being added to one of them by accident.
    @Test(arguments: [SavedView.Preset.inbox, .today, .upcoming, .highPriority, .dueThisWeek])
    func theFilteringViewsLeaveTheBoardsOwnOrderAlone(preset: SavedView.Preset) {
        let view = SavedView.seeded(preset)
        #expect(view.sort == .manual)
        #expect(view.limit == nil)
    }

    /// **What the criteria cost to say**, which is worth stating because it is
    /// the thing the request asked for: none of the seven needs anything the
    /// editor cannot offer, and each is a handful of rows rather than a page.
    @Test func noSeededRuleNeedsMoreThanAHandfulOfCriteria() {
        for preset in SavedView.Preset.allCases {
            let count = SavedView.seeded(preset).rule.criterionCount
            #expect((1...3).contains(count),
                    "\(preset.rawValue) takes \(count) criteria to say")
        }
    }

    /// And every criterion in every seeded rule is one the editor's own pickers
    /// can produce — a field it lists, under a comparator that field offers.
    /// A seeded rule reaching for a pair the interface cannot build would be a
    /// view the user can see and not rebuild, which is the one thing this whole
    /// change was for.
    @Test func everySeededCriterionIsOneTheEditorCanBuild() {
        for preset in SavedView.Preset.allCases {
            for criterion in criteria(of: SavedView.seeded(preset).rule) {
                #expect(ViewField.allCases.contains(criterion.field))
                #expect(criterion.field.comparators.contains(criterion.comparator),
                        "\(preset.rawValue) uses \(criterion.comparator.rawValue) under \(criterion.field.rawValue), which the picker does not offer")
            }
        }
    }

    private func criteria(of rule: ViewRule) -> [ViewCriterion] {
        if let criterion = rule.criterion { return [criterion] }
        return rule.children.flatMap(criteria)
    }
}
