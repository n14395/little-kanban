import Foundation
import Synchronization
import Testing
import UserNotifications
@testable import Simple_Kanban

/// One request as the fake keeps it.
///
/// The fields are copied out of `UNNotificationRequest` rather than the object
/// being held: it is a reference type that has to cross out of the call the
/// scheduler makes, and everything worth asserting on is a value anyway.
struct ScheduledReminder: Hashable, Sendable {
    var identifier: String
    var title: String
    var body: String
    var threadIdentifier: String
    var targetContentIdentifier: String?
    var taskID: String?
    var fireHour: Int?
    var fireMinute: Int?
    var fireDay: CalendarDay?
}

/// Somewhere for the scheduler to write that is not the machine's real
/// Notification Centre.
///
/// It models the one behaviour of `UNUserNotificationCenter` the scheduler
/// leans on: an `add` under an identifier the centre already holds *replaces*
/// that request rather than queuing a second one. A fake that appended would
/// make "changing a due date reschedules rather than adding" impossible to
/// fail, which is one of the two bugs worth having this suite for.
final class FakeNotificationCenter: TaskNotificationCenter, @unchecked Sendable {
    enum Event: Hashable, Sendable {
        case added(String)
        case removed([String])
    }

    private struct State: Sendable {
        var status: UNAuthorizationStatus
        var grants: Bool
        var pending: [String: ScheduledReminder] = [:]
        var log: [Event] = []
        var authorizationRequests = 0
        var delegateAdoptions = 0
    }

    private let state: Mutex<State>

    init(status: UNAuthorizationStatus = .authorized, grants: Bool = true) {
        state = Mutex(State(status: status, grants: grants))
    }

    // MARK: What the scheduler calls

    func authorizationStatus() async -> UNAuthorizationStatus { state.withLock { $0.status } }

    func requestAuthorization() async -> Bool {
        state.withLock { state in
            state.authorizationRequests += 1
            if state.grants { state.status = .authorized } else { state.status = .denied }
            return state.grants
        }
    }

    func add(_ request: UNNotificationRequest) {
        let reminder = Self.reading(request)
        state.withLock { state in
            state.pending[reminder.identifier] = reminder
            state.log.append(.added(reminder.identifier))
        }
    }

    func removePending(identifiers: [String]) {
        state.withLock { state in
            for identifier in identifiers { state.pending[identifier] = nil }
            state.log.append(.removed(identifiers.sorted()))
        }
    }

    func adopt(delegate: UNUserNotificationCenterDelegate) {
        state.withLock { $0.delegateAdoptions += 1 }
    }

    // MARK: What a test reads

    var pending: [String: ScheduledReminder] { state.withLock { $0.pending } }
    var pendingIdentifiers: [String] { pending.keys.sorted() }
    var log: [Event] { state.withLock { $0.log } }
    var authorizationRequests: Int { state.withLock { $0.authorizationRequests } }
    var delegateAdoptions: Int { state.withLock { $0.delegateAdoptions } }

    /// Every identifier the centre has ever been handed, added or removed. The
    /// question "is the identifier stable?" is asked of this rather than of
    /// what is pending now: an identifier that moved would leave the old one
    /// behind, and the leak is only visible in the history.
    var everyIdentifier: Set<String> {
        Set(log.flatMap { event -> [String] in
            switch event {
            case .added(let identifier): [identifier]
            case .removed(let identifiers): identifiers
            }
        })
    }

    var adds: [String] {
        log.compactMap { if case .added(let identifier) = $0 { identifier } else { nil } }
    }

    var removals: [[String]] {
        log.compactMap { if case .removed(let identifiers) = $0 { identifiers } else { nil } }
    }

    func forget() { state.withLock { $0.log = [] } }

    func setStatus(_ status: UNAuthorizationStatus) { state.withLock { $0.status = status } }

    private static func reading(_ request: UNNotificationRequest) -> ScheduledReminder {
        let content = request.content
        let components = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
        return ScheduledReminder(
            identifier: request.identifier,
            title: content.title,
            body: content.body,
            threadIdentifier: content.threadIdentifier,
            targetContentIdentifier: content.targetContentIdentifier,
            taskID: content.userInfo["taskID"] as? String,
            fireHour: components?.hour,
            fireMinute: components?.minute,
            fireDay: components.flatMap { parts in
                guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
                return CalendarDay(year: year, month: month, day: day)
            }
        )
    }
}

/// Due-date reminders, driven through a fake centre.
///
/// Every probe here goes board → `reminders(from:)` → `reconcile`, which is the
/// path the app takes, rather than calling the private publishing directly: the
/// bugs worth catching — a second request instead of a replacement, a cancel
/// that never fires on delete, an identifier minted from something that changes
/// — all live in the join between the board and the scheduler.
@MainActor
@Suite struct NotificationTests {
    /// A fixed calendar, so a fire date is the same on every machine, and a
    /// `now` well before the board's due dates.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// 2026-07-01T00:00Z — before every due date `TestBoard` carries, so the
    /// board's own reminders are all still ahead.
    private static let now = Date(timeIntervalSinceReferenceDate: 804_556_800)

    private static let soon = CalendarDay(year: 2026, month: 8, day: 25)
    private static let later = CalendarDay(year: 2026, month: 12, day: 3)

    /// A scheduler over a throwaway defaults suite. Never `.standard`: these
    /// preferences are the user's, and a test that wrote there would change the
    /// app's behaviour on the developer's own machine.
    private func scheduler(
        _ center: FakeNotificationCenter, defaults: UserDefaults
    ) async -> NotificationScheduler {
        let scheduler = NotificationScheduler(center: center, defaults: defaults, calendar: Self.calendar)
        await scheduler.refreshAuthorization()
        return scheduler
    }

    private func suite() -> UserDefaults {
        UserDefaults(suiteName: "SimpleKanbanTests-\(UUID().uuidString)") ?? .standard
    }

    /// The scheduler hands each request over in a task of its own, so the
    /// centre has not seen it by the time `reconcile` returns.
    private func settle() async throws { try await Task.sleep(for: .milliseconds(40)) }

    /// The one call the board makes, spelled out so every probe below makes it
    /// the same way.
    private func sync(_ scheduler: NotificationScheduler, _ store: BoardStore) {
        scheduler.reconcile(
            NotificationScheduler.reminders(from: store.tasks, isComplete: store.isDone),
            now: Self.now
        )
    }

    /// A board, a centre and a scheduler that has already taken its baseline —
    /// the state the app is in a moment after launch.
    private func launched(
        tasks: [TaskItem] = TestBoard.tasks, status: UNAuthorizationStatus = .authorized
    ) async throws -> (store: BoardStore, center: FakeNotificationCenter, scheduler: NotificationScheduler) {
        let center = FakeNotificationCenter(status: status)
        let scheduler = await scheduler(center, defaults: suite())
        let store = TestBoard.store(tasks: tasks)
        sync(scheduler, store)
        try await settle()
        center.forget()
        return (store, center, scheduler)
    }

    // MARK: What the board wants told

    @Test func onlyADueDateThatIsStillComingGetsAReminder() {
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.offline: 100]))
        let reminders = NotificationScheduler.reminders(from: store.tasks, isComplete: store.isDone)

        // dragDrop is due and on the board. offline is due but filed away.
        // palette is in Done. Everything else has no due date at all.
        #expect(reminders.map(\.id) == [TestBoard.dragDrop])
        #expect(reminders.first?.day == TestBoard.dueDay)
        #expect(reminders.first?.code == "NW-121")
    }

    @Test func anUntitledTaskStillHasSomethingToSay() {
        var untitled = TestBoard.tasks[2]
        untitled.title = "   "
        untitled.due = Self.soon
        let store = TestBoard.store(tasks: [untitled])
        let reminder = NotificationScheduler.reminders(from: store.tasks, isComplete: store.isDone).first
        #expect(reminder?.title == untitled.displayTitle)
        #expect(reminder?.title.isEmpty == false)
    }

    // MARK: Setting, changing, clearing

    @Test func settingADueDateSchedulesExactlyOneRequest() async throws {
        let (store, center, scheduler) = try await launched()

        store.setDue(Self.soon, on: TestBoard.cafe)
        sync(scheduler, store)
        try await settle()

        #expect(center.adds == [TestBoard.cafe.uuidString])
        let reminder = try #require(center.pending[TestBoard.cafe.uuidString])
        #expect(reminder.fireDay == Self.soon)
        #expect(reminder.fireHour == 9)
        #expect(reminder.fireMinute == 0)
        #expect(reminder.title == "Café menu polish")
        #expect(reminder.taskID == TestBoard.cafe.uuidString)
        // Everything already on the board is still scheduled and was not
        // re-sent: a reconcile that republished the lot would fire a
        // notification for a task nobody touched.
        #expect(center.pendingIdentifiers.count == 3)
        #expect(center.removals.isEmpty)
    }

    @Test func reconcilingTwiceWithTheSameBoardSendsNothingTheSecondTime() async throws {
        let (store, center, scheduler) = try await launched()
        sync(scheduler, store)
        sync(scheduler, store)
        try await settle()
        #expect(center.log.isEmpty)
    }

    @Test func changingADueDateReschedulesRatherThanAddingASecond() async throws {
        let (store, center, scheduler) = try await launched()
        store.setDue(Self.soon, on: TestBoard.cafe)
        sync(scheduler, store)
        try await settle()
        center.forget()

        store.setDue(Self.later, on: TestBoard.cafe)
        sync(scheduler, store)
        try await settle()

        #expect(center.pending.count == 3, "the board still wants three reminders, not four")
        let reminder = try #require(center.pending[TestBoard.cafe.uuidString])
        #expect(reminder.fireDay == Self.later)
        // The old request is taken back under the same identifier it was filed
        // under. Nothing else in the centre is touched.
        #expect(center.removals == [[TestBoard.cafe.uuidString]])
        #expect(center.adds == [TestBoard.cafe.uuidString])
    }

    @Test func clearingADueDateCancelsTheReminder() async throws {
        let (store, center, scheduler) = try await launched()
        store.setDue(nil, on: TestBoard.dragDrop)
        sync(scheduler, store)
        try await settle()

        #expect(center.pending[TestBoard.dragDrop.uuidString] == nil)
        #expect(center.removals == [[TestBoard.dragDrop.uuidString]])
        #expect(center.adds.isEmpty)
    }

    @Test func aTaskWithNoDueDateSchedulesNothingHoweverMuchItIsEdited() async throws {
        let (store, center, scheduler) = try await launched()
        store.setPriority(.high, on: TestBoard.cafe)
        store.setText("Renamed", field: .title, on: TestBoard.cafe)
        store.toggleLabel("bug", on: TestBoard.cafe)
        store.move(TestBoard.cafe, to: BoardColumn.inProgress.id)
        sync(scheduler, store)
        try await settle()

        #expect(center.log.isEmpty)
        #expect(center.pending[TestBoard.cafe.uuidString] == nil)
    }

    @Test func aDueDateThatHasAlreadyPassedIsNotScheduled() async throws {
        let center = FakeNotificationCenter()
        let scheduler = await scheduler(center, defaults: suite())
        var stale = TestBoard.tasks[2]
        stale.due = CalendarDay(year: 2026, month: 1, day: 4)
        let store = TestBoard.store(tasks: [stale])
        sync(scheduler, store)
        try await settle()

        // Nothing is queued for a moment that has been and gone: `UNCalendar…`
        // would simply never fire, and the request would sit there for ever.
        #expect(center.pending.isEmpty)
    }

    // MARK: Cancelling

    @Test func completingATaskCancelsItsReminder() async throws {
        let (store, center, scheduler) = try await launched()
        store.complete(TestBoard.dragDrop)
        sync(scheduler, store)
        try await settle()

        #expect(center.pending[TestBoard.dragDrop.uuidString] == nil)
        #expect(center.removals == [[TestBoard.dragDrop.uuidString]])
    }

    @Test func reopeningATaskPutsItsReminderBack() async throws {
        let (store, center, scheduler) = try await launched()
        store.complete(TestBoard.dragDrop)
        sync(scheduler, store)
        try await settle()
        center.forget()

        store.reopen(TestBoard.dragDrop)
        sync(scheduler, store)
        try await settle()
        #expect(center.adds == [TestBoard.dragDrop.uuidString])
        #expect(center.pending[TestBoard.dragDrop.uuidString]?.fireDay == TestBoard.dueDay)
    }

    @Test func archivingATaskCancelsItsReminder() async throws {
        let (store, center, scheduler) = try await launched()
        store.archive(TestBoard.dragDrop)
        sync(scheduler, store)
        try await settle()

        #expect(center.pending[TestBoard.dragDrop.uuidString] == nil)
        #expect(center.removals == [[TestBoard.dragDrop.uuidString]])
    }

    @Test func deletingATaskCancelsItsReminder() async throws {
        let (store, center, scheduler) = try await launched()
        store.deleteTask(TestBoard.dragDrop)
        sync(scheduler, store)
        try await settle()

        #expect(center.pending[TestBoard.dragDrop.uuidString] == nil)
        #expect(center.removals == [[TestBoard.dragDrop.uuidString]])
    }

    @Test func undoingADeleteBringsTheReminderBack() async throws {
        let (store, undo) = TestBoard.undoing()
        let center = FakeNotificationCenter()
        let scheduler = await scheduler(center, defaults: suite())
        sync(scheduler, store)
        try await settle()

        step(undo) { store.deleteTask(TestBoard.dragDrop) }
        sync(scheduler, store)
        try await settle()
        #expect(center.pending[TestBoard.dragDrop.uuidString] == nil)

        undo.undo()
        sync(scheduler, store)
        try await settle()
        #expect(center.pending[TestBoard.dragDrop.uuidString]?.fireDay == TestBoard.dueDay)
    }

    @Test func aBulkArchiveCancelsEveryOneOfThem() async throws {
        let (store, center, scheduler) = try await launched()
        store.setDue(Self.soon, on: TestBoard.cafe)
        sync(scheduler, store)
        try await settle()
        center.forget()

        store.archive([TestBoard.cafe, TestBoard.dragDrop, TestBoard.offline])
        sync(scheduler, store)
        try await settle()
        #expect(center.pending.isEmpty)
    }

    /// `UNUserNotificationCenter` keeps 64 pending requests per app and drops
    /// the rest *without saying which*. A board with more due dates than that
    /// has to choose for itself, and the nearest are the ones worth having —
    /// letting the system pick would silently lose tomorrow's reminder to keep
    /// one three months out.
    @Test func aBoardWithMoreDueDatesThanTheSystemHoldsKeepsTheNearestOnes() async throws {
        let base = CalendarDay(year: 2026, month: 7, day: 1)
        let tasks = (1...70).map { offset in
            TaskItem(
                id: TestBoard.taskID(UInt8(offset)), code: String(format: "NW-4%02d", offset),
                title: "Bound \(offset)", due: base.adding(days: offset),
                createdAt: Self.now, updatedAt: Self.now
            )
        }
        let center = FakeNotificationCenter()
        let scheduler = await scheduler(center, defaults: suite())
        let store = TestBoard.store(tasks: tasks)
        sync(scheduler, store)
        try await settle()

        #expect(center.pending.count == 64)
        let kept = Set(center.pending.values.compactMap(\.fireDay))
        #expect(kept.contains(base.adding(days: 1)))
        #expect(kept.contains(base.adding(days: 64)))
        #expect(!kept.contains(base.adding(days: 65)))
        #expect(!kept.contains(base.adding(days: 70)))
    }

    // MARK: The identifier

    /// The identifier has to be the task's id and nothing else. Derive it from
    /// the title, the code or the day and every edit strands the old request:
    /// the centre still holds it, so the user gets a notification for a task
    /// that has moved, been renamed, or been thrown away.
    @Test func theIdentifierIsTheTaskIdThroughEveryChange() async throws {
        let (store, center, scheduler) = try await launched()
        let id = TestBoard.cafe.uuidString

        store.setDue(Self.soon, on: TestBoard.cafe)
        sync(scheduler, store)
        store.setText("An entirely different title", field: .title, on: TestBoard.cafe)
        sync(scheduler, store)
        store.setDue(Self.later, on: TestBoard.cafe)
        sync(scheduler, store)
        store.move(TestBoard.cafe, to: BoardColumn.inProgress.id)
        sync(scheduler, store)
        store.archive(TestBoard.cafe)
        sync(scheduler, store)
        store.unarchive(TestBoard.cafe)
        sync(scheduler, store)
        store.deleteTask(TestBoard.cafe)
        sync(scheduler, store)
        try await settle()

        #expect(center.everyIdentifier == [id],
                "the centre saw \(center.everyIdentifier.sorted()) — only \(id) may ever be named")
        // …and nothing was stranded: the board wants no reminder for this task
        // any more, and the centre is holding none.
        #expect(center.pending[id] == nil)
        #expect(center.pending.count == 2, "the two reminders this task never touched are untouched")
    }

    @Test func theRequestNamesTheTaskInEveryPlaceSomethingWillReadItBack() async throws {
        let (store, center, scheduler) = try await launched()
        store.setDue(Self.soon, on: TestBoard.cafe)
        sync(scheduler, store)
        try await settle()

        let reminder = try #require(center.pending[TestBoard.cafe.uuidString])
        #expect(reminder.identifier == TestBoard.cafe.uuidString)
        #expect(reminder.taskID == TestBoard.cafe.uuidString)
        #expect(reminder.body.contains("NW-122"))
        #expect(reminder.threadIdentifier.isEmpty == false)

        // A tapped notification and a pasted link have to mean the same thing,
        // so the request carries the same URL vocabulary the router parses —
        // and it has to parse back to the task the reminder is about.
        let target = try #require(reminder.targetContentIdentifier.flatMap(URL.init(string:)))
        #expect(TaskLink.taskID(in: target) == TestBoard.cafe)
    }

    // MARK: Permission

    @Test func nothingIsScheduledWhilePermissionIsRefused() async throws {
        let (store, center, scheduler) = try await launched(status: .denied)
        store.setDue(Self.soon, on: TestBoard.cafe)
        sync(scheduler, store)
        try await settle()

        #expect(center.adds.isEmpty)
        #expect(center.pending.isEmpty)
        #expect(scheduler.explanation != nil)
        #expect(scheduler.needsSystemSettings)
    }

    @Test func permissionArrivingPublishesWhatTheBoardAlreadyWanted() async throws {
        let center = FakeNotificationCenter(status: .notDetermined, grants: true)
        let scheduler = await scheduler(center, defaults: suite())
        let store = TestBoard.store()
        sync(scheduler, store)
        try await settle()
        #expect(center.pending.isEmpty, "nothing goes out before the user has said yes")

        await scheduler.requestAuthorization()
        try await settle()
        #expect(scheduler.authorization == .authorized)
        #expect(center.pendingIdentifiers == [TestBoard.dragDrop.uuidString, TestBoard.offline.uuidString].sorted())
    }

    /// The prompt is asked for on the first due date *set*, not at launch — a
    /// permission sheet on first run, before the user has seen the board, is
    /// how an app gets denied for good.
    @Test func theBoardsExistingDueDatesDoNotTriggerThePrompt() async throws {
        let center = FakeNotificationCenter(status: .notDetermined)
        let scheduler = await scheduler(center, defaults: suite())
        let store = TestBoard.store()
        sync(scheduler, store)
        try await settle()
        #expect(center.authorizationRequests == 0)

        store.setDue(Self.soon, on: TestBoard.cafe)
        sync(scheduler, store)
        try await settle()
        #expect(center.authorizationRequests == 1)

        // …and only once: a second due date does not ask again.
        store.setDue(Self.later, on: TestBoard.widget)
        sync(scheduler, store)
        try await settle()
        #expect(center.authorizationRequests == 1)
    }

    @Test func aRefusedPromptIsNotAskedASecondTime() async throws {
        let center = FakeNotificationCenter(status: .notDetermined, grants: false)
        let scheduler = await scheduler(center, defaults: suite())
        let store = TestBoard.store()
        sync(scheduler, store)
        try await settle()

        store.setDue(Self.soon, on: TestBoard.cafe)
        sync(scheduler, store)
        try await settle()
        #expect(scheduler.authorization == .denied)

        await scheduler.requestAuthorization()
        #expect(center.authorizationRequests == 1)
    }

    // MARK: Preferences

    @Test func turningRemindersOffWithdrawsThemAndTurningThemBackOnRestoresThem() async throws {
        let (_, center, scheduler) = try await launched()
        let wanted = center.pendingIdentifiers
        #expect(wanted.count == 2)

        scheduler.isEnabled = false
        try await settle()
        #expect(center.pending.isEmpty)

        scheduler.isEnabled = true
        try await settle()
        #expect(center.pendingIdentifiers == wanted)
    }

    @Test func changingTheTimeOfDayMovesEveryRequestWithoutChangingItsIdentifier() async throws {
        let (_, center, scheduler) = try await launched()
        let before = center.pendingIdentifiers
        center.forget()

        scheduler.reminderHour = 18
        scheduler.reminderMinute = 30
        try await settle()

        #expect(center.pendingIdentifiers == before)
        #expect(center.pending.values.allSatisfy { $0.fireHour == 18 && $0.fireMinute == 30 })
    }

    @Test func thePreferencesArePersistedWhereTheyBelongAndNotInTheBoard() async throws {
        let defaults = suite()
        let center = FakeNotificationCenter()
        let scheduler = await scheduler(center, defaults: defaults)
        scheduler.isEnabled = false
        scheduler.reminderHour = 7
        scheduler.reminderMinute = 45

        // Read back by a second scheduler over the same suite, which is what a
        // relaunch is.
        let second = await self.scheduler(FakeNotificationCenter(), defaults: defaults)
        #expect(second.isEnabled == false)
        #expect(second.reminderHour == 7)
        #expect(second.reminderMinute == 45)

        // …and none of it is board data. See `PreferenceTests` for the whole
        // claim; this is the half that names these three keys.
        let snapshot = BoardSnapshot(tasks: TestBoard.tasks, labels: LabelDef.seed,
                                     nextSerial: 100, accentTheme: .ember)
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        #expect(!json.contains("Reminder"))
        #expect(!json.contains("reminder"))
    }

    /// A store with no file is a preview or a test, and a scheduler with no
    /// centre is what it gets: nothing it does may reach the machine's real
    /// Notification Centre.
    @Test func aSchedulerWithNoCentreIsInert() async throws {
        let scheduler = NotificationScheduler(center: nil, defaults: suite(), calendar: Self.calendar)
        let store = TestBoard.store()
        sync(scheduler, store)
        await scheduler.refreshAuthorization()
        await scheduler.requestAuthorization()
        scheduler.isEnabled = false
        scheduler.reminderHour = 6
        #expect(scheduler.authorization == .unknown)
    }
}
