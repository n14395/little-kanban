import Foundation
import Observation
import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Whether the system will actually deliver a reminder, in the four states a
/// settings screen has to be able to explain.
///
/// `.unknown` is not one of the system's: it is the moment between the
/// scheduler being made and the first answer coming back, and it means *do
/// nothing yet* — treating it as denied would tear down every pending request
/// once per launch.
enum NotificationAuthorization: Hashable, Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
}

/// One task's reminder, reduced to what scheduling needs. A value type so the
/// scheduler can tell "nothing has changed" from "the title moved" by comparing
/// what it published last with what it has been handed now.
struct TaskReminder: Hashable, Sendable {
    var id: UUID
    var title: String
    var code: String
    var day: CalendarDay
}

/// The half of `UNUserNotificationCenter` this app uses, behind a protocol so a
/// test can hand the scheduler somewhere to write that is not the user's real
/// Notification Centre.
protocol TaskNotificationCenter: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    /// Synchronous on purpose. `UNNotificationRequest` is not `Sendable`, so
    /// an `async` version could not be handed one from the main actor at all.
    func add(_ request: UNNotificationRequest)
    func removePending(identifiers: [String])
    func adopt(delegate: UNUserNotificationCenterDelegate)
}

/// Due-date reminders: one local notification per task that has a due date, at
/// a time of day the user picks.
///
/// **Authorisation is asked for lazily.** Not at launch — a permission prompt
/// on first run, before the user has set a due date or even seen the board, is
/// how an app gets denied permanently and never gets asked again. It is asked
/// for the first time a reminder *appears* that was not there a moment ago,
/// which is the first due date set in the session; `hasBaseline` is what keeps
/// the reminders already on the board at launch from counting as that.
///
/// Everything else follows from the identifier being the task's UUID: adding a
/// request with an identifier the centre already holds replaces it, so a
/// reschedule is an add and a cancel is a removal, and both are idempotent.
@MainActor
@Observable
final class NotificationScheduler {
    /// The app's. Created on first use rather than at launch, so a store with no
    /// file — every test and every preview — never reaches the real centre.
    static let shared = NotificationScheduler(center: SystemNotificationCenter())

    private(set) var authorization: NotificationAuthorization = .unknown

    /// Whether the user wants reminders at all. A preference rather than board
    /// data, so it lives in `UserDefaults` and not in `BoardSnapshot`.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            defaults.set(isEnabled, forKey: Keys.enabled)
            flush()
        }
    }

    /// The hour and minute reminders fire at, on the day the task is due.
    /// Default 9am: a reminder is only useful before the day has been spent.
    var reminderHour: Int {
        didSet {
            guard reminderHour != oldValue else { return }
            defaults.set(reminderHour, forKey: Keys.hour)
            republish()
        }
    }

    var reminderMinute: Int {
        didSet {
            guard reminderMinute != oldValue else { return }
            defaults.set(reminderMinute, forKey: Keys.minute)
            republish()
        }
    }

    private let center: TaskNotificationCenter?
    private let defaults: UserDefaults
    private let calendar: Calendar
    /// Retained because `UNUserNotificationCenter.delegate` is weak.
    private let relay = NotificationRelay()

    /// What should exist, and what the centre was last told. Kept apart because
    /// they part company whenever authorisation is missing: the board goes on
    /// saying what it wants, and the moment permission arrives that want is
    /// published without the board having to change again.
    @ObservationIgnored private var desired: [UUID: TaskReminder] = [:]
    @ObservationIgnored private var published: [UUID: TaskReminder] = [:]
    /// False until the first reconcile has been seen. See the type's note.
    @ObservationIgnored private var hasBaseline = false

    /// `UNUserNotificationCenter` keeps this many pending requests per app.
    private static let pendingLimit = 64

    private enum Keys {
        static let enabled = "SimpleKanbanRemindersEnabled"
        static let hour = "SimpleKanbanReminderHour"
        static let minute = "SimpleKanbanReminderMinute"
    }

    init(
        center: TaskNotificationCenter?,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
        self.isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        self.reminderHour = defaults.object(forKey: Keys.hour) as? Int ?? 9
        self.reminderMinute = defaults.object(forKey: Keys.minute) as? Int ?? 0
        guard let center else { return }
        center.adopt(delegate: relay)
        Task { await refreshAuthorization() }
    }

    // MARK: What the board wants

    /// Everything on a board that still wants telling about: a due date, not
    /// archived, not already done. The store hands the whole list every time —
    /// the diff is this object's job, and a whole list is the only thing that
    /// stays right across a bulk archive, an undo, and a board switch.
    static func reminders(from tasks: [TaskItem], isComplete: (TaskItem) -> Bool) -> [TaskReminder] {
        tasks.compactMap { task in
            guard let day = task.due, !task.isArchived, !isComplete(task) else { return nil }
            return TaskReminder(id: task.id, title: task.displayTitle, code: task.code, day: day)
        }
    }

    /// The one call the board makes. Idempotent, cheap when nothing has changed,
    /// and the only place authorisation is asked for.
    func reconcile(_ reminders: [TaskReminder], now: Date = .now) {
        // Soonest first, then capped: the system keeps only the 64 nearest
        // pending requests and drops the rest without saying which, so a board
        // with more due dates than that has to choose for itself. The nearest
        // are the ones worth having.
        let due = reminders
            .compactMap { reminder in fireDate(for: reminder.day).map { (reminder, $0) } }
            .filter { $0.1 > now }
            .sorted { $0.1 < $1.1 }
            .prefix(Self.pendingLimit)
        let next = Dictionary(due.map { ($0.0.id, $0.0) }, uniquingKeysWith: { first, _ in first })
        let appeared = next.keys.contains { desired[$0] == nil }
        desired = next
        defer { flush() }
        guard hasBaseline else {
            hasBaseline = true
            return
        }
        // The first due date of the session is the first moment the user has
        // any context for the question.
        if appeared, authorization == .notDetermined {
            Task { await requestAuthorization() }
        }
    }

    // MARK: Authorisation

    func refreshAuthorization() async {
        guard let center else { return }
        authorization = Self.reading(await center.authorizationStatus())
        flush()
    }

    /// Asks, once. After a denial the system answers `false` without showing
    /// anything, which is why the settings screen offers the trip to System
    /// Settings rather than a second prompt.
    func requestAuthorization() async {
        guard let center, authorization != .denied else { return }
        authorization = await center.requestAuthorization() ? .authorized : .denied
        flush()
    }

    private static func reading(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    // MARK: Publishing

    /// Sends the difference between what is wanted and what the centre holds.
    ///
    /// With nothing authorised there is nothing to hold: anything already
    /// scheduled is withdrawn, so revoking permission in System Settings does
    /// not leave a week of stale reminders queued behind it. `desired` is
    /// untouched, so granting permission again republishes the lot.
    private func flush() {
        guard let center, authorization != .unknown else { return }
        let target = (isEnabled && authorization == .authorized) ? desired : [:]

        let stale = published.filter { target[$0.key] != $0.value }.keys
        if !stale.isEmpty {
            center.removePending(identifiers: stale.map(\.uuidString))
        }
        let fresh = target.filter { published[$0.key] != $0.value }.values
        for reminder in fresh {
            guard let request = request(for: reminder) else { continue }
            center.add(request)
        }
        published = target
    }

    /// Drops what the centre holds and sends it again, which is what a change
    /// to the time of day means: every request's trigger moved.
    private func republish() {
        guard !published.isEmpty else { return flush() }
        center?.removePending(identifiers: published.keys.map(\.uuidString))
        published = [:]
        flush()
    }

    private func request(for reminder: TaskReminder) -> UNNotificationRequest? {
        var components = DateComponents()
        components.year = reminder.day.year
        components.month = reminder.day.month
        components.day = reminder.day.day
        components.hour = reminderHour
        components.minute = reminderMinute

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = String(localized: "\(reminder.code) is due today.",
                              comment: "Body of the reminder for a task due today; the placeholder is a task code like NW-118")
        content.sound = .default
        content.threadIdentifier = "com.n14395.SimpleKanban.due"
        content.userInfo = [NotificationRelay.taskIDKey: reminder.id.uuidString]
        // What tapping the notification opens, in the same vocabulary a pasted
        // link uses. See `TaskLink`.
        content.targetContentIdentifier = TaskLink.url(for: reminder.id).absoluteString

        return UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    private func fireDate(for day: CalendarDay) -> Date? {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = reminderHour
        components.minute = reminderMinute
        return calendar.date(from: components)
    }

    // MARK: What the settings screen shows

    /// The time of day as a `Date`, which is what a `DatePicker` binds to. The
    /// day part is arbitrary and ignored on the way back in.
    var reminderTime: Date {
        get { fireDate(for: CalendarDay(.now, calendar: calendar)) ?? .now }
        set {
            let parts = calendar.dateComponents([.hour, .minute], from: newValue)
            reminderHour = parts.hour ?? reminderHour
            reminderMinute = parts.minute ?? reminderMinute
        }
    }

    /// What the user needs told, or `nil` when reminders simply work. A denial
    /// is not an error to report once — it is a standing condition, and the
    /// place to say so is beside the switch that no longer does anything.
    var explanation: String? {
        switch authorization {
        case .denied:
            String(localized: "Simple Kanban is not allowed to send notifications, so due dates will not remind you. You can allow them in System Settings.",
                   comment: "Shown in settings when notification permission has been refused")
        case .notDetermined:
            String(localized: "You will be asked to allow notifications the first time you give a task a due date.",
                   comment: "Shown in settings before notification permission has been asked for")
        case .authorized, .unknown:
            nil
        }
    }

    /// Whether the settings screen should offer the trip to System Settings.
    var needsSystemSettings: Bool { authorization == .denied }

    func openSystemSettings() {
        #if os(macOS)
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
        #else
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

/// Where a tapped notification goes. The delegate has to exist before the
/// notification that launched the app is delivered, which is why the scheduler
/// installs it in its own initialiser rather than waiting for a view.
private final class NotificationRelay: NSObject, UNUserNotificationCenterDelegate {
    static let taskIDKey = "taskID"

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info[Self.taskIDKey] as? String, let id = UUID(uuidString: raw) else { return }
        await MainActor.run { TaskLink.router.open(TaskLink.url(for: id)) }
    }

    /// A reminder that arrives while the board is on screen is still worth
    /// showing: the board does not draw due dates that are not on the surface
    /// the user is looking at.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

/// The real Notification Centre. `UNUserNotificationCenter.current()` is reached
/// inside each call rather than held, because it traps outside an app bundle
/// and this type is constructed before anything asks it for anything.
struct SystemNotificationCenter: TaskNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// No completion handler: the only way this fails is a request this file
    /// built wrong, which is a bug here rather than anything the user can act on.
    func add(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request)
    }

    func removePending(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func adopt(delegate: UNUserNotificationCenterDelegate) {
        UNUserNotificationCenter.current().delegate = delegate
    }
}

