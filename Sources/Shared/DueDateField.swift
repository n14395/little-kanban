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
        var addHorizontalPadding: CGFloat
        var addVerticalPadding: CGFloat
        var addBorderWidth: CGFloat
        var pickerWidth: CGFloat
        var rowFont: CGFloat
        var rowVerticalPadding: CGFloat
        var rowRadius: CGFloat
        var panelPadding: CGFloat

        static let desk = Metrics(
            chipFont: 12.5, chipHorizontalPadding: 7, chipRadius: 6,
            addHorizontalPadding: 8, addVerticalPadding: 3, addBorderWidth: 1,
            pickerWidth: 268, rowFont: 12, rowVerticalPadding: 6,
            rowRadius: 8, panelPadding: 10
        )
        static let sheet = Metrics(
            chipFont: 14, chipHorizontalPadding: 9, chipRadius: 7,
            addHorizontalPadding: 11, addVerticalPadding: 5, addBorderWidth: 1.5,
            pickerWidth: 320, rowFont: 14, rowVerticalPadding: 9,
            rowRadius: 10, panelPadding: 12
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    let scope: DetailScope
    var metrics: Metrics = .desk

    @State private var isPickerOpen = false
    /// Which task the open session belongs to. A detail surface can be pointed
    /// at another card while the calendar is open, and a session ended against
    /// the wrong task would leave the first one's open — which silences every
    /// later due date it logs.
    @State private var editingID: TaskItem.ID?

    private var today: CalendarDay { dayClock.today }

    var body: some View {
        Button {
            setPickerOpen(!isPickerOpen)
        } label: {
            if let due = task.due {
                DueChip(
                    due: due,
                    today: today,
                    columnID: task.columnID,
                    font: metrics.chipFont,
                    horizontalPadding: metrics.chipHorizontalPadding,
                    radius: metrics.chipRadius
                )
            } else {
                addAffordance
            }
        }
        .buttonStyle(.bare)
        .accessibilityLabel("Due date")
        .accessibilityValue(task.dueText(today: today) ?? "No due date")
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
                .font(.system(size: metrics.chipFont - 1, weight: .semibold))
            Text("Add due date")
                .font(SimpleKanbanFont.ui(metrics.chipFont, .bold, relativeTo: .footnote))
        }
        .foregroundStyle(palette.ink(0.45))
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

            DatePicker(
                "Due date",
                selection: calendarBinding,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(palette.accent)

            if task.due != nil {
                Divider().overlay(palette.ink(0.08))
                Button {
                    store.setDue(nil, on: task.id, scope: scope)
                    setPickerOpen(false)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: metrics.rowFont, weight: .semibold))
                        Text("Clear due date")
                            .font(SimpleKanbanFont.ui(metrics.rowFont, .bold, relativeTo: .caption))
                    }
                    .foregroundStyle(palette.ink(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, metrics.rowVerticalPadding)
                    .padding(.horizontal, 6)
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
                .foregroundStyle(isCurrent ? .white : palette.ink(0.65))
                .lineLimit(1)
                .padding(.vertical, metrics.rowVerticalPadding - 2)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity)
                .background(isCurrent ? palette.accent : palette.ink(0.06), in: .capsule)
        }
        .buttonStyle(.bare)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    /// The calendar edits the task directly; with no due date set it opens on
    /// today rather than on a date the task does not have. `DatePicker` deals
    /// in instants, so the day is resolved to midday and back.
    private var calendarBinding: Binding<Date> {
        Binding(
            get: { (task.due ?? today).date() },
            set: { store.setDue(CalendarDay($0), on: task.id, scope: scope) }
        )
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
            editingID = task.id
            store.beginEditing(.due, on: task.id, scope: scope)
        } else if let editingID {
            store.endEditing(.due, on: editingID, scope: scope)
            self.editingID = nil
        }
    }
}
