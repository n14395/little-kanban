// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

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
        /// The show-more button: the size of the words on it, the gap above it,
        /// and the square a finger claims for it.
        var toggleFont: CGFloat
        var toggleSpacing: CGFloat
        var toggleHit: CGFloat

        static let desk = Metrics(
            rowSpacing: 8, dot: 6, dotSpacing: 9, dotTopPadding: 6, font: 12, lineSpacing: 2,
            toggleFont: 12, toggleSpacing: 10, toggleHit: 28
        )
        static let sheet = Metrics(
            rowSpacing: 11, dot: 6, dotSpacing: 11, dotTopPadding: 7, font: 13.5, lineSpacing: 3,
            toggleFont: 13, toggleSpacing: 8, toggleHit: 44
        )
    }

    /// How many entries a feed shows before it is asked to show the rest.
    ///
    /// **Five, and the newest five**, the list already being newest-first. It is
    /// enough to answer the question the section is usually opened for — *what
    /// happened to this card lately* — and short enough that the sections under
    /// it are still on the same screen. A card worked on for a month carries a
    /// hundred entries, and a hundred entries is pages of scrolling in front of
    /// nothing: the feed is the last section on both surfaces precisely because
    /// it is the one nobody opens the panel to read.
    static let collapsedCount = 5

    /// The three inks the design spends on a feed row. Not in `Metrics`: they
    /// are the rendering rather than the geometry, and they are the same on both
    /// surfaces — a stamp that read darker on the phone would be a different
    /// design, not a bigger one.
    private static let dotInk = 0.22
    private static let textInk = 0.6
    private static let stampInk = 0.35

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let entries: [ActivityEntry]
    /// Which card the entries belong to, so the feed can fold itself back up
    /// when the surface is re-pointed — see ``isExpanded``. Optional because
    /// the entries initialiser has no card to name.
    var owner: TaskItem.ID?
    var metrics: Metrics = .desk

    /// Open, and shut by default.
    ///
    /// **Session state rather than the card's.** Which cards somebody has read
    /// the whole history of is not a fact about the board, and the desk can be
    /// showing the same card in a second window with a different answer. It is
    /// also why it is reset when ``owner`` changes: the inspector stays mounted
    /// while the board hands it one card after another, so a feed left open
    /// would open every card after it at full length, which is the whole of what
    /// this is here to stop.
    @State private var isExpanded = false

    init(entries: [ActivityEntry], metrics: Metrics = .desk) {
        self.entries = entries
        self.metrics = metrics
    }

    init(task: TaskItem, metrics: Metrics = .desk) {
        self.init(entries: task.activity, metrics: metrics)
        self.owner = task.id
    }

    @ViewBuilder
    var body: some View {
        if !entries.isEmpty { feed }
    }

    /// The entries drawn, and how many are not.
    private var shown: [ActivityEntry] {
        isExpanded ? entries : Array(entries.prefix(Self.collapsedCount))
    }

    private var hidden: Int { entries.count - shown.count }

    private var feed: some View {
        // Read once, here, rather than inside each row: this is the dependency
        // that re-renders the whole feed when the day rolls over, which is what
        // keeps "Due set to 20 Aug" from being written against yesterday.
        let today = dayClock.today

        return VStack(alignment: .leading, spacing: metrics.toggleSpacing) {
            // A minute at a time, so "just now" becomes "20 min ago" without a
            // relaunch. **One** timeline around the feed rather than one per
            // row: each row's schedule was anchored at the moment that row
            // appeared, so a forty-entry history ticked forty times a minute at
            // scattered offsets — one shared minute re-stamps the same rows in
            // one pass.
            //
            // The button is outside it. It says nothing that goes stale, and a
            // control redrawn every minute for no reason is a control that
            // cannot hold a press animation.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    ForEach(shown) { entry in
                        row(entry, today: today, now: context.date)
                    }
                }
            }
            if isExpanded || hidden > 0 { toggle }
        }
        .onChange(of: owner) { isExpanded = false }
    }

    /// **One button that changes what it says**, rather than a Show and a Hide
    /// that take turns: it stands in the same place doing the same job either
    /// way round, and a control that moved or was replaced would read as two
    /// different things.
    ///
    /// It names the number it would add, because *how much more there is* is the
    /// question somebody hesitating over it has — the whole reason the feed
    /// folds is that the answer can be a hundred. Shut again it says only
    /// **Show less**: the count is on screen by then.
    ///
    /// Indented past the dot column so it lines up under the sentences rather
    /// than under the marks, which is what makes it read as the end of the list
    /// instead of an entry in it.
    private var toggle: some View {
        Button {
            Motion.run(.easeInOut(duration: 0.22), reduceMotion: reduceMotion) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(palette.ui(metrics.toggleFont, .bold, relativeTo: .caption))
                Image(systemName: "chevron.down")
                    .font(.system(size: metrics.toggleFont - 2, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(palette.accent)
            .frame(minHeight: metrics.toggleHit, alignment: .leading)
            .contentShape(.rect)
        }
        .bareButton()
        .padding(.leading, metrics.dot + metrics.dotSpacing)
    }

    private var label: String {
        isExpanded
            ? String(localized: "Show less", comment: "Folds a task's activity list back to its most recent few")
            : String(localized: "Show \(hidden) more",
                     comment: "Unfolds the rest of a task's activity list; the count is how many more entries there are")
    }

    private func row(_ entry: ActivityEntry, today: CalendarDay, now: Date) -> some View {
        HStack(alignment: .top, spacing: metrics.dotSpacing) {
            Circle()
                .fill(palette.ink(Self.dotInk))
                .frame(width: metrics.dot, height: metrics.dot)
                .padding(.top, metrics.dotTopPadding)

            // The pair concatenated rather than the stamp wrapped alone: the
            // stamp flows on after the sentence, wrapping with it, and only a
            // concatenated `Text` does that.
            Text("\(text(entry, today: today)) \(stamp(entry, now: now))")
                .lineSpacing(metrics.lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func text(_ entry: ActivityEntry, today: CalendarDay) -> Text {
        Text(entry.text(today: today))
            .font(palette.ui(metrics.font, .medium, relativeTo: .caption))
            .foregroundColor(palette.ink(Self.textInk))
    }

    private func stamp(_ entry: ActivityEntry, now: Date) -> Text {
        Text("· \(entry.whenText(from: now))")
            .font(palette.ui(metrics.font, .semibold, relativeTo: .caption))
            .foregroundColor(palette.ink(Self.stampInk))
    }
}
