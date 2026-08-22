import SwiftUI

/// A task's history, newest first — the list the macOS inspector has always
/// drawn, lifted out so the iOS sheet can draw the same one. The same task used
/// to show its past on one platform and hide it on the other.
///
/// The macOS rendering is the reference and is reproduced exactly: a 6pt dot at
/// 22% ink, the sentence at 60%, the stamp behind it at 35%. Only the sizes
/// differ between the two surfaces, which is what `Metrics` carries. The
/// section heading is not drawn here — both surfaces already label their own
/// sections, and their labels differ in size.
struct ActivityFeed: View {
    struct Metrics {
        /// Between two entries. Also the gap the desk's `VStack` used when the
        /// rows were still inline in `TaskInspector`, so the panel is unchanged.
        var rowSpacing: CGFloat
        var dot: CGFloat
        var dotSpacing: CGFloat
        /// Drops the dot onto the first line's baseline rather than its ascender.
        var dotTopPadding: CGFloat
        var font: CGFloat
        var lineSpacing: CGFloat

        static let desk = Metrics(
            rowSpacing: 8, dot: 6, dotSpacing: 9, dotTopPadding: 6, font: 12, lineSpacing: 2
        )
        static let sheet = Metrics(
            rowSpacing: 11, dot: 6, dotSpacing: 11, dotTopPadding: 7, font: 13.5, lineSpacing: 3
        )
    }

    /// The three inks the design spends on a feed row. Not in `Metrics`: they
    /// are the rendering rather than the geometry, and they are the same on both
    /// surfaces — a stamp that read darker on the phone would be a different
    /// design, not a bigger one.
    private static let dotInk = 0.22
    private static let textInk = 0.6
    private static let stampInk = 0.35

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock

    let entries: [ActivityEntry]
    var metrics: Metrics = .desk

    init(entries: [ActivityEntry], metrics: Metrics = .desk) {
        self.entries = entries
        self.metrics = metrics
    }

    init(task: TaskItem, metrics: Metrics = .desk) {
        self.init(entries: task.activity, metrics: metrics)
    }

    @ViewBuilder
    var body: some View {
        if !entries.isEmpty { feed }
    }

    private var feed: some View {
        // Read once, here, rather than inside each row: this is the dependency
        // that re-renders the whole feed when the day rolls over, which is what
        // keeps "Due set to 20 Aug" from being written against yesterday.
        let today = dayClock.today

        return VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            ForEach(entries) { entry in
                row(entry, today: today)
            }
        }
    }

    private func row(_ entry: ActivityEntry, today: CalendarDay) -> some View {
        HStack(alignment: .top, spacing: metrics.dotSpacing) {
            Circle()
                .fill(palette.ink(Self.dotInk))
                .frame(width: metrics.dot, height: metrics.dot)
                .padding(.top, metrics.dotTopPadding)

            // A minute at a time, so "just now" becomes "20 min ago" without a
            // relaunch. The timeline wraps one row rather than the feed: a tick
            // then invalidates a line of text instead of the whole panel. It has
            // to wrap the pair rather than the stamp alone because the stamp
            // flows on after the sentence, wrapping with it, and only a
            // concatenated `Text` does that.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text("\(text(entry, today: today)) \(stamp(entry, now: context.date))")
                    .lineSpacing(metrics.lineSpacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func text(_ entry: ActivityEntry, today: CalendarDay) -> Text {
        Text(entry.text(today: today))
            .font(SimpleKanbanFont.ui(metrics.font, .medium, relativeTo: .caption))
            .foregroundColor(palette.ink(Self.textInk))
    }

    private func stamp(_ entry: ActivityEntry, now: Date) -> Text {
        Text("· \(entry.whenText(from: now))")
            .font(SimpleKanbanFont.ui(metrics.font, .semibold, relativeTo: .caption))
            .foregroundColor(palette.ink(Self.stampInk))
    }
}
