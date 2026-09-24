// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Task ▸ Set Due Date…, which is the one menu item with something to type into.
///
/// A sheet rather than a submenu of dates because it acts on every card the
/// item was aimed at: `DueDateField` is the real control and it belongs to one
/// task's detail surface, where there is a card to point at. Here there may be
/// nine — or one that has the keyboard and is not selected at all.
///
/// The three shortcuts are the ones `DueDateField` offers, for the same reason —
/// most due dates on a board are today, tomorrow, or the end of the week.
struct DueDateSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store
    /// Optional for `MacRootView`'s reason: this stands up in a preview, which
    /// has no window and no menu bar to have been opened from.
    @Environment(AppWindowState.self) private var window: AppWindowState?

    @State private var day: Date = .now

    private var today: CalendarDay { dayClock.today }

    /// What the menu item was aimed at, which is not the same as the selection:
    /// ⎋ clears the selection and leaves the keyboard on the card, and this
    /// sheet then opened aimed at nothing and set nothing. The item hands its
    /// own `applicable(_:)` over rather than have the rule written twice.
    private var targets: Set<TaskItem.ID> { window?.dueDateTargets ?? store.selection }

    /// The cards it is aimed at that are still there. Undo and a delete can
    /// both empty a sheet from under itself.
    private var living: [TaskItem] { targets.compactMap { store[$0] } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(palette.ui(14, .extraBold, relativeTo: .headline))
                .foregroundStyle(palette.ink)

            HStack(spacing: 6) {
                // `DueDate.Preset` is where these are named and dated, and the
                // shared field draws the same three off it. Spelling the labels
                // and the arithmetic out again here got the labels shipped
                // without a translator's comment and put a second copy of
                // "next week is seven days" in the app.
                ForEach(DueDate.Preset.allCases) { shortcut($0) }
            }

            // Labelled rather than `DatePicker("")`: an empty key is an entry
            // in the catalogue that no translator can act on, and the label is
            // what VoiceOver reads the calendar out as once `labelsHidden`
            // takes it off the screen.
            DatePicker(selection: $day, displayedComponents: .date) {
                Text("Due date", comment: "Accessibility label of the calendar in the macOS due-date sheet")
            }
            .datePickerStyle(.graphical)
            .labelsHidden()
                .frame(width: 268)

            HStack(spacing: 8) {
                Button {
                    apply(nil)
                } label: {
                    Text("Clear due date", comment: "Button that takes the due date off the tasks the sheet is aimed at")
                        .font(palette.ui(12, .bold, relativeTo: .footnote))
                        .foregroundStyle(palette.inkText(0.55))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 30)
                }
                .bareButton()
                .hoverBackground(palette.ink(0.06), radius: 9)

                Spacer(minLength: 0)

                Button { dismiss() } label: {
                    Text("Cancel", comment: "Button that closes the due-date sheet without setting a date")
                        .font(palette.ui(12, .bold, relativeTo: .footnote))
                        .foregroundStyle(palette.inkText(0.55))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                }
                .bareButton()
                .hoverBackground(palette.ink(0.06), radius: 9)
                .keyboardShortcut(.cancelAction)

                Button {
                    apply(CalendarDay(day))
                } label: {
                    Text("Set", comment: "Button that files the chosen due date onto the tasks the sheet is aimed at")
                        .font(palette.ui(12, .bold, relativeTo: .footnote))
                        .foregroundStyle(palette.onAccent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 30)
                        .background(palette.accent, in: .rect(cornerRadius: 9))
                }
                .bareButton()
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .background(palette.windowFill)
        // What this is aimed at can go from under it — by an undo, or by the
        // cards being deleted — and a sheet aimed at nothing has nothing to set.
        .onChange(of: living.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
        .onAppear {
            // One card opens on its own date; several have no one date to show.
            day = ((living.count == 1 ? living.first?.due : nil) ?? today).date()
        }
    }

    private var title: String {
        let count = living.count
        return count > 1
            ? String(localized: "Due date for \(count) tasks", comment: "Title of the due-date sheet when it is aimed at several tasks")
            : String(localized: "Due date", comment: "Title of the due-date sheet")
    }

    private func shortcut(_ preset: DueDate.Preset) -> some View {
        Button {
            apply(preset.day(from: today))
        } label: {
            Text(preset.label)
                .font(palette.ui(12, .bold, relativeTo: .footnote))
                .foregroundStyle(palette.ink(0.7))
                .padding(.horizontal, 10)
                .frame(minHeight: 28)
                .background(palette.ink(0.06), in: .rect(cornerRadius: 8))
        }
        .bareButton()
    }

    private func apply(_ value: CalendarDay?) {
        store.setDue(value, on: targets)
        dismiss()
    }
}
