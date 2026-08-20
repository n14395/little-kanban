#if os(iOS)

import SwiftUI

/// A card in the phone list. Tapping it raises the detail sheet.
struct PhoneTaskCard: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock

    let task: TaskItem

    private var isDone: Bool { task.columnID == BoardColumn.done.id }

    var body: some View {
        Button {
            store.sheetID = task.id
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                if !task.labelKeys.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(store.labels(for: task)) { LabelChip(label: $0) }
                    }
                }

                Text(task.displayTitle)
                    .font(SimpleKanbanFont.ui(16, .bold, relativeTo: .body))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(isDone ? palette.ink(0.45) : palette.ink)
                    .strikethrough(isDone, color: palette.ink(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 9) {
                    PriorityDot(priority: task.priority, diameter: 7)
                    if let due = task.due {
                        DueChip(
                            due: due,
                            today: dayClock.today,
                            columnID: task.columnID,
                            font: 12,
                            horizontalPadding: 7,
                            radius: 7
                        )
                    }
                    if task.hasSubtasks {
                        SubtaskCountBadge(text: task.subtaskProgressText, font: 12, showsGlyph: false)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(palette.card)
                    .shadow(color: palette.shadow(0.05), radius: 9, y: 6)
                    .shadow(color: palette.shadow(0.07), radius: 1, y: 1)
            }
        }
        .buttonStyle(.bare)
        .accessibilityElement(children: .combine)
    }
}

#endif
