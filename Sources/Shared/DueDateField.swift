import SwiftUI

/// The due-date control: the design's chip, made tappable, opening a calendar
/// with the three shortcuts that cover most of what a board actually needs.
///
/// Empty state borrows `LabelEditor`'s dashed `+` so "nothing set yet" reads the
/// same way in both fields.
struct DueDateField: View {
    struct Metrics {
        var chipFont: CGFloat
        var chipHorizontalPadding: CGFloat
        var chipRadius: CGFloat
        /// The square the chip's button claims, and the floor under a row in
        /// the calendar. Zero on the desk, where each claims what it draws.
        var chipHit: CGFloat
        var rowHit: CGFloat
        var addHorizontalPadding: CGFloat
        var addVerticalPadding: CGFloat
        var addBorderWidth: CGFloat
        var pickerWidth: CGFloat
        var rowFont: CGFloat
        var rowVerticalPadding: CGFloat
        var rowRadius: CGFloat
        var panelPadding: CGFloat
        /// The calendar inside the panel — see ``MonthGrid``, which is drawn to
        /// whatever width it is given rather than to a size of its own.
        var grid: MonthGrid.Metrics

        static let desk = Metrics(
            chipFont: 12.5, chipHorizontalPadding: 7, chipRadius: 6, chipHit: 0, rowHit: 0,
            addHorizontalPadding: 8, addVerticalPadding: 3, addBorderWidth: 1,
            pickerWidth: 268, rowFont: 12, rowVerticalPadding: 6,
            rowRadius: 8, panelPadding: 10, grid: .desk
        )
        static let sheet = Metrics(
            chipFont: 14, chipHorizontalPadding: 9, chipRadius: 7, chipHit: 44, rowHit: 44,
            addHorizontalPadding: 11, addVerticalPadding: 5, addBorderWidth: 1.5,
            pickerWidth: 344, rowFont: 14, rowVerticalPadding: 9,
            rowRadius: 10, panelPadding: 12, grid: .sheet
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    let scope: DetailScope
    var metrics: Metrics = .desk

    @State private var isPickerOpen = false
    /// Which month the grid is showing. The panel's, not the task's: paging
    /// forward to look at next month must not move the due date, and the two
    /// part company the moment an arrow is pressed. Set when the panel opens —
    /// see ``setPickerOpen(_:)`` — so it opens on the date the card has.
    @State private var visibleMonth = CalendarDay(year: 2000, month: 1, day: 1)
    /// Which task the open session belongs to. A detail surface can be pointed
    /// at another card while the calendar is open, and a session ended against
    /// the wrong task would leave the first one's open — which silences every
    /// later due date it logs.
    @State private var editingID: TaskItem.ID?

    private var today: CalendarDay { dayClock.today }

    /// What the chip is worth out loud. The fallback is localized here rather
    /// than left in the modifier: `??` beside a `String` picks
    /// `accessibilityValue`'s `StringProtocol` overload, which takes its
    /// argument as the finished text and never looks in the catalogue.
    private var spokenDue: String {
        task.dueText(today: today)
            ?? String(localized: "No due date", comment: "Spoken value of a card's due-date chip when nothing is set")
    }

    var body: some View {
        Button {
            setPickerOpen(!isPickerOpen)
        } label: {
            Group {
                if let due = task.due {
                    DueChip(
                        due: due,
                        today: today,
                        role: store.role(of: task),
                        font: metrics.chipFont,
                        horizontalPadding: metrics.chipHorizontalPadding,
                        radius: metrics.chipRadius
                    )
                } else {
                    addAffordance
                }
            }
            .frame(minWidth: metrics.chipHit, minHeight: metrics.chipHit)
        }
        .buttonStyle(.bare)
        .accessibilityLabel("Due date")
        .accessibilityValue(spokenDue)
        .popover(isPresented: pickerBinding, arrowEdge: .bottom) {
            picker
                .environment(\.palette, palette)
                .presentationCompactAdaptation(.popover)
        }
        // A surface torn down — or re-pointed at another card — with the
        // calendar still open would otherwise leave the session open.
        .onChange(of: task.id) { setPickerOpen(false) }
        .onDisappear { setPickerOpen(false) }
    }

    private var addAffordance: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar")
                .symbolSize(metrics.chipFont - 1, weight: .semibold, relativeTo: .caption)
            Text("Add due date")
                .font(SimpleKanbanFont.ui(metrics.chipFont, .bold, relativeTo: .footnote))
        }
        .foregroundStyle(palette.inkText(0.45))
        .padding(.horizontal, metrics.addHorizontalPadding)
        .padding(.vertical, metrics.addVerticalPadding)
        .overlay {
            RoundedRectangle(cornerRadius: metrics.chipRadius)
                .strokeBorder(
                    palette.ink(0.25),
                    style: StrokeStyle(lineWidth: metrics.addBorderWidth, dash: [3, 3])
                )
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(DueDate.Preset.allCases) { preset in
                    presetButton(preset)
                }
            }

            MonthGrid(
                month: visibleMonth,
                selected: task.due,
                today: today,
                metrics: metrics.grid,
                step: { delta in visibleMonth = Self.month(visibleMonth, by: delta) },
                select: { day in
                    store.setDue(day, on: task.id, scope: scope)
                    // A day picked out of the greyed-out edge of the grid is a
                    // day in another month, and the grid follows it there rather
                    // than leaving the selection off the bottom of what is drawn.
                    visibleMonth = day
                }
            )

            if task.due != nil {
                Divider().overlay(palette.ink(0.08))
                Button {
                    store.setDue(nil, on: task.id, scope: scope)
                    setPickerOpen(false)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "xmark.circle")
                            .symbolSize(metrics.rowFont, weight: .semibold, relativeTo: .subheadline)
                        Text("Clear due date")
                            .font(SimpleKanbanFont.ui(metrics.rowFont, .bold, relativeTo: .caption))
                    }
                    .foregroundStyle(palette.inkText(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, metrics.rowVerticalPadding)
                    .padding(.horizontal, 6)
                    .frame(minHeight: metrics.rowHit)
                }
                .buttonStyle(.bare)
                .hoverBackground(palette.ink(0.06), radius: metrics.rowRadius)
            }
        }
        .padding(metrics.panelPadding)
        .frame(width: metrics.pickerWidth)
        .background(palette.card)
        .presentationBackground(palette.card)
    }

    private func presetButton(_ preset: DueDate.Preset) -> some View {
        let day = preset.day(from: today)
        let isCurrent = task.due == day
        return Button {
            store.setDue(day, on: task.id, scope: scope)
            setPickerOpen(false)
        } label: {
            Text(preset.label)
                .font(SimpleKanbanFont.ui(metrics.rowFont, .bold, relativeTo: .caption))
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

    /// The month `delta` months from this one, on its first.
    ///
    /// The day of the month is dropped on purpose: the 31st is not a day of
    /// every month, and a step that resolved it forward would land on the 1st of
    /// the month after and skip one every time it was pressed from a long month.
    static func month(_ day: CalendarDay, by delta: Int) -> CalendarDay {
        let months = (day.year * 12 + day.month - 1) + delta
        return CalendarDay(year: months / 12, month: months % 12 + 1, day: 1)
    }

    private var pickerBinding: Binding<Bool> {
        Binding(get: { isPickerOpen }, set: { setPickerOpen($0) })
    }

    /// The calendar's whole lifetime is one editing session, so trying three
    /// dates before settling on a fourth writes one activity entry rather than
    /// four. The presets close the popover as they set, which ends the session
    /// in the same breath and still writes exactly one.
    private func setPickerOpen(_ open: Bool) {
        guard open != isPickerOpen else { return }
        isPickerOpen = open
        if open {
            // On the card's own month, or on this one when it has no date yet.
            visibleMonth = task.due ?? today
            editingID = task.id
            store.beginEditing(.due, on: task.id, scope: scope)
        } else if let editingID {
            store.endEditing(.due, on: editingID, scope: scope)
            self.editingID = nil
        }
    }
}
