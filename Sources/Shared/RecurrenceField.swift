// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The "Repeat this task" row, under the checklist in both editors.
///
/// The `BoardSettingsView.columnLimit` shape — a toggle that opts into an
/// optional — with a popover for the value, because a rule is five decisions
/// rather than one number. Ticking it on arms a sensible default (every week,
/// on the due date's weekday) and opens the settings; the summary line under
/// the toggle reopens them.
///
/// **Ticking it off asks first.** The editor's other destructive verbs
/// deliberately skip confirmation — one ⌘Z away, see ``TaskInspector/header``
/// — but this one is a user-requested exception: a rule is configuration
/// someone built, unticking reads as tidying rather than destroying, and the
/// cost of it lands weeks later when the task quietly fails to come back.
struct RecurrenceField: View {
    struct Metrics {
        var toggleFont: CGFloat
        var summaryFont: CGFloat
        var summaryRadius: CGFloat
        /// The floor under the summary row, zero on the desk.
        var rowHit: CGFloat
        var picker: RecurrencePicker.Metrics
        /// Which side the popover hangs off — ``DueDateField/Metrics/arrowEdge``
        /// exactly, for the same measured reason.
        var arrowEdge: Edge?

        static let desk = Metrics(
            toggleFont: 13, summaryFont: 12.5, summaryRadius: 8, rowHit: 0,
            picker: .desk, arrowEdge: .bottom
        )
        static let sheet = Metrics(
            toggleFont: 15, summaryFont: 14, summaryRadius: 10, rowHit: 44,
            picker: .sheet, arrowEdge: nil
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    let scope: DetailScope
    var metrics: Metrics = .desk

    @State private var isPickerOpen = false
    /// Which task the open session belongs to, for
    /// ``DueDateField/editingID``'s reason.
    @State private var editingID: TaskItem.ID?
    @State private var isConfirmingStop = false

    private var today: CalendarDay { dayClock.today }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: toggleBinding) {
                Text("Repeat this task")
                    .font(palette.ui(metrics.toggleFont, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink(0.7))
            }
            .toggleStyle(.switch)
            if let rule = task.recurrence {
                summaryButton(rule)
            }
        }
        .popover(isPresented: pickerBinding, arrowEdge: metrics.arrowEdge) {
            RecurrencePicker(task: task, scope: scope, today: today, metrics: metrics.picker)
                .environment(store)
                .environment(\.palette, palette)
                .presentationCompactAdaptation(.popover)
        }
        .alert("Stop repeating?", isPresented: $isConfirmingStop) {
            Button("Stop Repeating", role: .destructive) {
                store.clearRecurrence(on: task.id, scope: scope)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This task will no longer repeat.")
        }
        // A surface torn down — or re-pointed at another card — with the panel
        // still open would otherwise leave the session open.
        .onChange(of: task.id) {
            setPickerOpen(false)
            isConfirmingStop = false
        }
        .onDisappear { setPickerOpen(false) }
    }

    /// On arms the default and opens the panel; off only *asks*. The rule
    /// stays until the alert's destructive button clears it, so a Cancel
    /// leaves the toggle exactly where it was — it reads the task, not this
    /// view's state, and the task has not changed.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { task.recurrence != nil },
            set: { on in
                if on {
                    guard task.recurrence == nil else { return }
                    // The session opens first so the arming and the twiddling
                    // that follows coalesce into one activity entry.
                    setPickerOpen(true)
                    store.setRecurrence(defaultRule, on: task.id, scope: scope, today: today)
                } else {
                    isConfirmingStop = true
                }
            }
        )
    }

    /// Every week, on the day the card is due — the rule most tasks want, and
    /// one tap from the other four decisions.
    private var defaultRule: RecurrenceRule {
        RecurrenceRule(interval: 1, unit: .week, weekdays: [(task.due ?? today).weekday])
    }

    private func summaryButton(_ rule: RecurrenceRule) -> some View {
        Button {
            setPickerOpen(true)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .symbolSize(metrics.summaryFont - 1, weight: .semibold, relativeTo: .caption)
                Text(rule.summaryText())
                    .font(palette.ui(metrics.summaryFont, .bold, relativeTo: .caption))
                    .lineLimit(1)
                Image(systemName: "chevron.forward")
                    .symbolSize(metrics.summaryFont - 3, weight: .bold, relativeTo: .caption2)
                    .foregroundStyle(palette.inkText(0.35))
            }
            .foregroundStyle(palette.inkText(0.6))
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(minHeight: metrics.rowHit)
            .contentShape(.rect)
        }
        .bareButton()
        .hoverBackground(palette.ink(0.06), radius: metrics.summaryRadius)
        .accessibilityLabel("Repeat settings")
        .accessibilityValue(rule.summaryText())
    }

    private var pickerBinding: Binding<Bool> {
        Binding(get: { isPickerOpen }, set: { setPickerOpen($0) })
    }

    /// The panel's whole lifetime is one editing session, for
    /// ``DueDateField/setPickerOpen(_:)``'s reason: five decisions tried and
    /// retried write one activity entry naming what they settled on.
    private func setPickerOpen(_ open: Bool) {
        guard open != isPickerOpen else { return }
        isPickerOpen = open
        if open {
            editingID = task.id
            store.beginEditing(.recurrence, on: task.id, scope: scope)
        } else if let editingID {
            store.endEditing(.recurrence, on: editingID, scope: scope)
            self.editingID = nil
        }
    }
}
