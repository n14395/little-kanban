import SwiftUI

/// Publishes the current calendar day, and nothing else.
///
/// Views that render a due chip or a relative timestamp read `today` and so
/// re-render when it changes: a chip that read "Today" at 23:59 reads
/// "Yesterday" at 00:01 without a relaunch.
@MainActor @Observable
final class DayClock {
    private(set) var today: CalendarDay = .today()

    @ObservationIgnored private var wake: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    /// The environment's default value is built from a nonisolated context, so
    /// this initialiser must not touch `today` — it takes the property's own
    /// default. Tests and previews name a day with `init(today:)`.
    nonisolated init() {}

    init(today: CalendarDay) {
        self.today = today
    }

    /// Sleeps until the next midnight, once. A repeating short timer would keep
    /// the CPU awake — and the battery draining — for a value that changes once
    /// a day.
    func start() {
        guard wake == nil else { return }
        observe(.NSSystemTimeZoneDidChange)
        observe(.NSCalendarDayChanged)
        scheduleWake()
    }

    func stop() {
        wake?.cancel()
        wake = nil
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
    }

    /// Recompute now. A machine that slept through midnight never got its wake,
    /// so the app calls this when the scene becomes active.
    func refresh() {
        let now = CalendarDay.today()
        if now != today { today = now }
    }

    private func scheduleWake() {
        wake?.cancel()
        wake = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.secondsUntilNextMidnight() else { return }
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                self?.refresh()
            }
        }
    }

    /// A second past the boundary, so a wake that fires early by rounding does
    /// not read the day it is trying to leave.
    private func secondsUntilNextMidnight(_ now: Date = .now, calendar: Calendar = .current) -> TimeInterval {
        let startOfToday = calendar.startOfDay(for: now)
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return 3_600 }
        return max(1, midnight.timeIntervalSince(now) + 1)
    }

    private func observe(_ name: Notification.Name) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                // The boundary itself moves with the time zone, so the pending
                // wake is now for the wrong instant.
                self.scheduleWake()
            }
        }
        observers.append(token)
    }
}

extension EnvironmentValues {
    @Entry var dayClock = DayClock()
}
