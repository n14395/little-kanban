import AppIntents
import Foundation
import WidgetKit

/// One entry, for a widget that has nothing to configure.
struct DigestEntry: TimelineEntry {
    var date: Date
    var digest: WidgetDigest

    /// The day the due chips are drawn against — see
    /// ``ConfiguredEntry/today``, which is the same rule with the reasons.
    var today: CalendarDay { max(digest.today, CalendarDay(date)) }
}

/// One entry, plus what the user picked in the widget's editor.
struct ConfiguredEntry<Configuration: WidgetConfigurationIntent>: TimelineEntry {
    var date: Date
    var digest: WidgetDigest
    var configuration: Configuration

    /// The day the due chips are drawn against: the digest's, until the entry
    /// has outlived it.
    ///
    /// The digest's `today` is what keeps a widget agreeing with the board —
    /// see ``WidgetDigest`` — but the midnight refresh exists precisely for
    /// the machine where the app is not running, and an entry built at that
    /// refresh drawing yesterday's `today` said "Tomorrow" all day about a
    /// card that was due. The entry's own date is stamped when the timeline
    /// is built, so at the midnight rebuild it *is* the new day; `max` keeps
    /// the digest's answer whenever the two agree on freshness, so a widget
    /// the app just published still says exactly what the board says. The
    /// lists themselves stay as the app computed them — membership is the
    /// app's question — which is as far as a cache can honestly roll.
    var today: CalendarDay { max(digest.today, CalendarDay(date)) }
}

/// When to look again, and what to draw when there is nothing to look at.
///
/// **A widget is refreshed by the app, not by a schedule.** Every edit
/// republishes the digest and wakes the timelines — see `WidgetPublisher` —
/// which is both cheaper and very much faster than any budget WidgetKit would
/// grant a poll. The schedule below exists for the one thing an edit cannot
/// cause: **midnight**. "Today" and "Due this week" are answers about a day, and
/// on a machine where the app is not running the day rolls over with nobody to
/// notice.
enum WidgetTimelines {
    /// The published digest, or something to draw while there is none — a fresh
    /// install, a build not entitled to the group, or the gallery preview the
    /// system renders before the widget has been placed.
    static func digest() -> WidgetDigest { WidgetDigestFile.read() ?? .sample }

    /// A second past the next midnight, so a refresh that fires early by
    /// rounding does not read the day it is trying to leave. `DayClock` does
    /// the same arithmetic for the same reason.
    static func nextRefresh(_ now: Date = .now, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return now.addingTimeInterval(3_600)
        }
        return midnight.addingTimeInterval(1)
    }
}

/// The Inbox's provider. Nothing to configure: there is one Inbox.
struct InboxTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DigestEntry {
        DigestEntry(date: .now, digest: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DigestEntry) -> Void) {
        completion(DigestEntry(date: .now, digest: WidgetTimelines.digest()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DigestEntry>) -> Void) {
        let entry = DigestEntry(date: .now, digest: WidgetTimelines.digest())
        completion(Timeline(entries: [entry], policy: .after(WidgetTimelines.nextRefresh())))
    }
}

/// One provider for all three configurable widgets.
///
/// They differ only in what the user picked, and what they picked is carried on
/// the entry for the view to resolve against the digest. Resolving it *here*
/// would mean three providers that each do the same two things — read the
/// digest, work out when to look again — and differ in one line.
struct ConfiguredTimelineProvider<Configuration: WidgetConfigurationIntent>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ConfiguredEntry<Configuration> {
        ConfiguredEntry(date: .now, digest: .sample, configuration: Configuration())
    }

    func snapshot(
        for configuration: Configuration, in context: Context
    ) async -> ConfiguredEntry<Configuration> {
        ConfiguredEntry(date: .now, digest: WidgetTimelines.digest(), configuration: configuration)
    }

    func timeline(
        for configuration: Configuration, in context: Context
    ) async -> Timeline<ConfiguredEntry<Configuration>> {
        let entry = await snapshot(for: configuration, in: context)
        return Timeline(entries: [entry], policy: .after(WidgetTimelines.nextRefresh()))
    }
}
