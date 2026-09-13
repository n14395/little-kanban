import SwiftUI

/// The repeat rule's panel: cadence, weekday chips, what the count runs from,
/// and when it ends — with the next occurrence it all adds up to at the foot,
/// so every change answers the only question that matters before the popover
/// closes.
///
/// Every control writes straight through the store on change, the app's
/// live-write convention — no draft, no Done button. The popover's lifetime is
/// one editing session (see ``RecurrenceField``), so twiddling the stepper
/// leaves one activity entry naming what was settled on.
struct RecurrencePicker: View {
    struct Metrics {
        var width: CGFloat
        var rowFont: CGFloat
        var captionFont: CGFloat
        var rowVerticalPadding: CGFloat
        var rowRadius: CGFloat
        var panelPadding: CGFloat
        /// The least a weekday chip may be. Its width is a seventh of the
        /// panel; this is the other axis — `MonthGrid.Metrics.cellHeight`'s
        /// bargain exactly.
        var chipHit: CGFloat
        /// The floor under a tappable row, zero on the desk.
        var rowHit: CGFloat
        /// The calendar the end date is picked from.
        var grid: MonthGrid.Metrics

        static let desk = Metrics(
            width: 268, rowFont: 12, captionFont: 11, rowVerticalPadding: 6,
            rowRadius: 8, panelPadding: 10, chipHit: 28, rowHit: 0, grid: .desk
        )
        static let sheet = Metrics(
            width: 344, rowFont: 14, captionFont: 12.5, rowVerticalPadding: 9,
            rowRadius: 10, panelPadding: 12, chipHit: 44, rowHit: 44, grid: .sheet
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    let scope: DetailScope
    /// A parameter rather than a read of the clock — the app-wide `DayClock`
    /// bargain — so the preview at the foot re-renders when the field does.
    let today: CalendarDay
    var metrics: Metrics = .desk

    /// Which month the end-date calendar is showing — the panel's, not the
    /// rule's, for ``DueDateField/visibleMonth``'s reason.
    @State private var visibleMonth = CalendarDay(year: 2000, month: 1, day: 1)

    var body: some View {
        ScrollView {
            if let rule = task.recurrence {
                panel(rule)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: metrics.width)
        .background(palette.card)
        .presentationBackground(palette.card)
        .onAppear { visibleMonth = task.recurrence?.until ?? task.due ?? today }
    }

    private func panel(_ rule: RecurrenceRule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cadenceRow(rule)
            if rule.unit == .week {
                weekdayChips(rule)
            }
            sectionLabel("Repeats")
            basisChoice(rule)
            sectionLabel("Ends")
            endsChoice(rule)
            if rule.until != nil {
                endGrid(rule)
            }
            Divider().overlay(palette.ink(0.08))
            preview(rule)
        }
        .padding(metrics.panelPadding)
    }

    /// "Every [2] [weeks]". The unit's menu label pluralises with the stepper
    /// so the row always reads as the sentence it is.
    private func cadenceRow(_ rule: RecurrenceRule) -> some View {
        HStack(spacing: 8) {
            Stepper(value: binding(for: rule, keyPath: \.interval), in: 1...99) {
                Text("Every \(rule.interval)")
                    .font(palette.ui(metrics.rowFont + 1, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.inkText(0.8))
                    .monospacedDigit()
            }
            Picker(selection: binding(for: rule, keyPath: \.unit)) {
                ForEach(RecurrenceRule.Unit.allCases, id: \.self) { unit in
                    Text(Self.unitName(unit, count: rule.interval)).tag(unit)
                }
            } label: {
                // A real name under `.labelsHidden()`, the `DueDateSheet`
                // pattern: nothing is drawn, and VoiceOver still has a word
                // for the control.
                Text("Repeat unit")
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .frame(minHeight: metrics.rowHit)
    }

    /// S M T W T F S, first day per the reader's calendar. At least one stays
    /// lit: a weekly rule happens on *some* day, so unticking the last chip is
    /// refused rather than answered with an empty week.
    private func weekdayChips(_ rule: RecurrenceRule) -> some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let selected = effectiveWeekdays(rule)
        return HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { offset in
                let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
                let isOn = selected.contains(weekday)
                Button {
                    var next = selected
                    if next.contains(weekday) { next.remove(weekday) } else { next.insert(weekday) }
                    guard !next.isEmpty else { return }
                    var updated = rule
                    updated.weekdays = next
                    store.setRecurrence(updated, on: task.id, scope: scope, today: today)
                } label: {
                    Text(symbols[weekday - 1])
                        .font(palette.ui(metrics.rowFont, .bold, relativeTo: .caption))
                        .foregroundStyle(isOn ? palette.onAccent : palette.ink(0.65))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: metrics.chipHit)
                        .background(isOn ? palette.accent : palette.ink(0.06), in: .capsule)
                }
                .buttonStyle(.bare)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }

    /// The chips as drawn: an empty set means the anchor day's own weekday —
    /// see ``RecurrenceRule/weekdays`` — and the panel shows that day lit
    /// rather than showing a week with nothing on it.
    private func effectiveWeekdays(_ rule: RecurrenceRule) -> Set<Int> {
        guard rule.weekdays.isEmpty else { return rule.weekdays }
        return [(task.due ?? today).weekday]
    }

    @ViewBuilder private func basisChoice(_ rule: RecurrenceRule) -> some View {
        HStack(spacing: 5) {
            choice("On schedule", isCurrent: rule.basis == .schedule) {
                var updated = rule
                updated.basis = .schedule
                store.setRecurrence(updated, on: task.id, scope: scope, today: today)
            }
            choice("After completion", isCurrent: rule.basis == .completion) {
                var updated = rule
                updated.basis = .completion
                store.setRecurrence(updated, on: task.id, scope: scope, today: today)
            }
        }
        Text(rule.basis == .schedule
             ? "The next date keeps the due-date pattern, however late this one is finished."
             : "The next date counts from the day this one is finished.")
            .font(palette.ui(metrics.captionFont, .medium, relativeTo: .caption2))
            .foregroundStyle(palette.inkText(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func endsChoice(_ rule: RecurrenceRule) -> some View {
        HStack(spacing: 5) {
            choice("Never", isCurrent: rule.until == nil) {
                var updated = rule
                updated.until = nil
                store.setRecurrence(updated, on: task.id, scope: scope, today: today)
            }
            choice("On date", isCurrent: rule.until != nil) {
                guard rule.until == nil else { return }
                var updated = rule
                // Opens on the next occurrence — the earliest end date that
                // still means anything — rather than on a day already gone.
                let landing = rule.nextOccurrence(after: today, due: task.due) ?? (task.due ?? today)
                updated.until = landing
                visibleMonth = landing
                store.setRecurrence(updated, on: task.id, scope: scope, today: today)
            }
        }
    }

    private func endGrid(_ rule: RecurrenceRule) -> some View {
        MonthGrid(
            month: visibleMonth,
            selected: rule.until,
            today: today,
            metrics: metrics.grid,
            step: { delta in visibleMonth = DueDateField.month(visibleMonth, by: delta) },
            select: { day in
                var updated = rule
                updated.until = day
                store.setRecurrence(updated, on: task.id, scope: scope, today: today)
                visibleMonth = day
            }
        )
    }

    /// "Next: Mon 14 Sep" — the rule's own arithmetic, so what the panel
    /// promises is exactly what completing the card will do.
    private func preview(_ rule: RecurrenceRule) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "repeat")
                .symbolSize(metrics.rowFont - 1, weight: .semibold, relativeTo: .caption)
            if let next = rule.nextOccurrence(after: today, due: task.due) {
                Text("Next: \(Self.dayText(next, from: today))")
                    .font(palette.ui(metrics.rowFont, .bold, relativeTo: .caption))
            } else {
                Text("The end date has passed, so this will not repeat again.")
                    .font(palette.ui(metrics.captionFont, .medium, relativeTo: .caption2))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(palette.inkText(0.6))
    }

    private func choice(_ label: LocalizedStringKey, isCurrent: Bool, act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(label)
                .font(palette.ui(metrics.rowFont, .bold, relativeTo: .caption))
                .foregroundStyle(isCurrent ? palette.onAccent : palette.ink(0.65))
                .lineLimit(1)
                .padding(.vertical, metrics.rowVerticalPadding - 2)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity)
                .background(isCurrent ? palette.accent : palette.ink(0.06), in: .capsule)
                .frame(minHeight: metrics.rowHit)
        }
        .buttonStyle(.bare)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
            .padding(.top, 2)
    }

    /// One field of the rule, written back through the store so the change is
    /// normalized, logged and undoable like any other.
    private func binding<Value>(
        for rule: RecurrenceRule, keyPath: WritableKeyPath<RecurrenceRule, Value>
    ) -> Binding<Value> {
        Binding(
            get: { (task.recurrence ?? rule)[keyPath: keyPath] },
            set: { value in
                var updated = task.recurrence ?? rule
                updated[keyPath: keyPath] = value
                store.setRecurrence(updated, on: task.id, scope: scope, today: today)
            }
        )
    }

    /// The day spelled out with its weekday, the year only when it is not this
    /// one — `ActivityEntry.dayText`'s bargain with a weekday on the front,
    /// because "which day of the week" is most of what a repeat preview is for.
    static func dayText(_ day: CalendarDay, from today: CalendarDay) -> String {
        let date = day.date()
        return day.year == today.year
            ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// The unit as the cadence row's menu says it, agreeing in number with the
    /// stepper beside it.
    static func unitName(_ unit: RecurrenceRule.Unit, count: Int) -> String {
        switch unit {
        case .day:
            count == 1
                ? String(localized: "day", comment: "Repeat unit, singular: every 1 day")
                : String(localized: "days", comment: "Repeat unit, plural: every N days")
        case .week:
            count == 1
                ? String(localized: "week", comment: "Repeat unit, singular: every 1 week")
                : String(localized: "weeks", comment: "Repeat unit, plural: every N weeks")
        case .month:
            count == 1
                ? String(localized: "month", comment: "Repeat unit, singular: every 1 month")
                : String(localized: "months", comment: "Repeat unit, plural: every N months")
        case .year:
            count == 1
                ? String(localized: "year", comment: "Repeat unit, singular: every 1 year")
                : String(localized: "years", comment: "Repeat unit, plural: every N years")
        }
    }
}
