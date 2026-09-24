// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// A month of days, laid out to whatever width it is given.
///
/// **Why this is not `DatePicker(.graphical)`.** On macOS that control is a
/// fixed size: measured through the accessibility tree, 138×148pt inside a
/// 248pt column, whatever it is proposed. `.frame(maxWidth: .infinity)` only
/// centres it, and neither `.controlSize(.large)` nor a larger `.font` moves it
/// a point — both were tried and measured. So a calendar that fills the panel
/// it is drawn in has to be drawn here.
///
/// Three things come with that, which is why it is worth the file. The cells are
/// a *seventh of the width* rather than 19pt, so there is something to aim at
/// — 35pt on the desk, 45 under a finger. It reads in this app's type and
/// palette rather than the system's. And the same calendar is now drawn on both
/// platforms, where before macOS and iOS each got whatever their own graphical
/// picker happened to be.
struct MonthGrid: View {
    struct Metrics {
        var titleFont: CGFloat
        var weekdayFont: CGFloat
        var dayFont: CGFloat
        /// The least a day cell may be. Width is always a seventh of what the
        /// grid was given; this is the other axis.
        var cellHeight: CGFloat
        var cellRadius: CGFloat
        var rowSpacing: CGFloat
        /// The square the month arrows claim.
        var arrow: CGFloat

        static let desk = Metrics(
            titleFont: 13, weekdayFont: 10, dayFont: 12.5,
            cellHeight: 28, cellRadius: 7, rowSpacing: 2, arrow: 24
        )
        // 44, not 40: a day is a control under a finger, and the contract's
        // floor applies to it like anything else. Its *width* is a seventh of
        // whatever the panel is — 45pt at the sheet's own width — so the height
        // is the axis that has to be stated.
        static let sheet = Metrics(
            titleFont: 15, weekdayFont: 11, dayFont: 15,
            cellHeight: 44, cellRadius: 9, rowSpacing: 3, arrow: 44
        )
    }

    @Environment(\.palette) private var palette

    /// Any day in the month being shown — the grid only reads its year and
    /// month.
    let month: CalendarDay
    /// The day the task is due, if it has one. Drawn filled.
    let selected: CalendarDay?
    let today: CalendarDay
    var metrics: Metrics = .desk
    /// Steps the month by ±1. The caller owns which month is on screen: it also
    /// has to reset it when the panel is reopened on another card.
    let step: (Int) -> Void
    let select: (CalendarDay) -> Void

    private var chrome = ChromeScale()

    init(
        month: CalendarDay,
        selected: CalendarDay?,
        today: CalendarDay,
        metrics: Metrics = .desk,
        step: @escaping (Int) -> Void,
        select: @escaping (CalendarDay) -> Void
    ) {
        self.month = month
        self.selected = selected
        self.today = today
        self.metrics = metrics
        self.step = step
        self.select = select
    }

    var body: some View {
        VStack(spacing: metrics.rowSpacing) {
            header
            weekdays
            days
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(Self.monthTitle(month))
                .font(palette.ui(metrics.titleFont, .extraBold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 8)
            arrow("chevron.left", by: -1, name: "Previous month")
            arrow("chevron.right", by: 1, name: "Next month")
        }
        .padding(.bottom, 2)
    }

    private func arrow(_ symbol: String, by delta: Int, name: LocalizedStringKey) -> some View {
        Button { step(delta) } label: {
            Image(systemName: symbol)
                .symbolSize(metrics.weekdayFont + 1, weight: .bold, relativeTo: .caption)
                .foregroundStyle(palette.inkText(0.55))
                .frame(minWidth: chrome(metrics.arrow), minHeight: chrome(metrics.arrow))
                .contentShape(.rect)
        }
        .bareButton()
        .hoverBackground(palette.ink(0.06), radius: metrics.cellRadius)
        .accessibilityLabel(name)
    }

    private var weekdays: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.weekdayTitles().enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(palette.ui(metrics.weekdayFont, .extraBold, relativeTo: .caption2))
                    .foregroundStyle(palette.inkText(0.4))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
        // The row names the columns and is read by every cell under it; a
        // reader arriving on "Mon" alone has been told nothing.
        .accessibilityHidden(true)
    }

    /// Six weeks, always — a grid that grew and shrank as the months changed
    /// would move the rows under a pointer already on its way to one.
    private var days: some View {
        let grid = Self.days(inMonthOf: month)
        return VStack(spacing: metrics.rowSpacing) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { weekday in
                        cell(grid[week * 7 + weekday])
                    }
                }
            }
        }
    }

    private func cell(_ day: CalendarDay) -> some View {
        let isSelected = day == selected
        let isToday = day == today
        let isThisMonth = day.month == month.month && day.year == month.year
        return Button { select(day) } label: {
            Text("\(day.day)")
                .font(palette.ui(metrics.dayFont, isToday ? .extraBold : .semibold,
                                          relativeTo: .footnote))
                .foregroundStyle(colour(isSelected: isSelected, isToday: isToday, isThisMonth: isThisMonth))
                .frame(maxWidth: .infinity)
                .frame(minHeight: chrome(metrics.cellHeight))
                .background(
                    isSelected ? palette.accent : .clear,
                    in: .rect(cornerRadius: metrics.cellRadius)
                )
                .contentShape(.rect)
        }
        .bareButton()
        .hoverBackground(isSelected ? .clear : palette.ink(0.06), radius: metrics.cellRadius)
        // The number alone is no use out loud — every month has an 11.
        .accessibilityLabel(Text(Self.spokenDay(day)))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func colour(isSelected: Bool, isToday: Bool, isThisMonth: Bool) -> Color {
        if isSelected { return palette.onAccent }
        if isToday { return palette.accent }
        return isThisMonth ? palette.ink : palette.inkText(0.3)
    }
}

// MARK: - The arithmetic

extension MonthGrid {
    /// The forty-two days a grid draws for the month `day` is in: the month
    /// itself, padded at both ends with the neighbouring months' days so every
    /// row is a full week.
    ///
    /// Six weeks whatever the month, so the panel does not change height as the
    /// arrows are pressed. Thirty-one days starting on the last column need six
    /// rows, so six is what every month gets.
    ///
    /// The neighbours are drawn rather than left blank, and they are live: a due
    /// date at the start of next month is one press away in the row it actually
    /// falls in, which is what a person looking at a calendar expects.
    static func days(
        inMonthOf day: CalendarDay, calendar: Calendar = .current
    ) -> [CalendarDay] {
        let first = CalendarDay(year: day.year, month: day.month, day: 1)
        // 1 = Sunday through 7 = Saturday, whatever the locale starts its weeks
        // on — the offset below is what turns that into a column.
        let weekday = calendar.component(.weekday, from: first.date(in: calendar))
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        let start = first.adding(days: -offset, in: calendar)
        return (0..<42).map { start.adding(days: $0, in: calendar) }
    }

    /// The column headings, rotated so the first one is the locale's first day
    /// of the week.
    static func weekdayTitles(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }

    /// "September 2026", in the reader's language and in their order — some
    /// locales put the year first, which is why this is a template rather than
    /// a format string.
    static func monthTitle(_ day: CalendarDay, locale: Locale = .current) -> String {
        guard locale == Locale.current else {
            // A named locale is the tests' path; the app always asks for the
            // reader's own, which is the formatter kept below.
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("MMMM y")
            return formatter.string(from: day.date())
        }
        return currentMonthTitle.string(from: day.date())
    }

    /// What a cell is worth out loud: the whole date, because the number on it
    /// is not one.
    static func spokenDay(_ day: CalendarDay, locale: Locale = .current) -> String {
        guard locale == Locale.current else {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            return formatter.string(from: day.date())
        }
        return currentSpokenDay.string(from: day.date())
    }

    /// Shared, for ``TaskItem``'s reason: a `DateFormatter` is an ICU object
    /// dear enough to matter when every render of the grid builds forty-two
    /// spoken labels and a title. Configured once, then only ever read.
    ///
    /// **`nonisolated`, not `nonisolated(unsafe)`.** `DateFormatter` is
    /// `Sendable` now, so the opt-out has nothing left to opt out of and the
    /// compiler says so. ``TaskItem/relative`` still needs the unsafe spelling
    /// — a `RelativeDateTimeFormatter` is not `Sendable` — which is why the two
    /// no longer match.
    private nonisolated static let currentMonthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM y")
        return formatter
    }()

    /// As ``currentMonthTitle``, and `nonisolated` for its reason.
    private nonisolated static let currentSpokenDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
}
