#if os(macOS)

import SwiftUI

/// A draggable board card.
struct MacTaskCard: View {
    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    @State private var isHovering = false

    private var isSelected: Bool { store.selectedID == task.id }
    private var isDragging: Bool { store.draggingID == task.id }
    private var isDone: Bool { task.columnID == BoardColumn.done.id }

    var body: some View {
        Button {
            store.selectedID = task.id
            store.isInspectorOpen = true
        } label: {
            content
        }
        .buttonStyle(.bare)
        .opacity(isDragging ? 0.4 : 1)
        .offset(y: isHovering ? -1 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .draggable(task.id.uuidString)
        .onDragSessionUpdated { session in
            switch session.phase {
            case .initial:
                store.draggingID = task.id
            case .ended:
                store.draggingID = nil
                store.dropTargetColumnID = nil
            default:
                break
            }
        }
        .dropDestination(for: String.self) { items, _ in
            // The drag payload is a `String` because `UUID` is not `Transferable`.
            guard let text = items.first, let dragged = UUID(uuidString: text),
                  dragged != task.id, store[dragged] != nil
            else { return false }
            store.move(dragged, to: task.columnID, before: task.id)
            return true
        } isTargeted: { targeted in
            if targeted { store.dropTargetColumnID = task.columnID }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !task.labelKeys.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(store.labels(for: task)) { LabelChip(label: $0) }
                }
            }

            Text(task.displayTitle)
                .font(SimpleKanbanFont.ui(13.5, .bold, relativeTo: .subheadline))
                .lineSpacing(1.5)
                .foregroundStyle(isDone ? palette.ink(0.45) : palette.ink)
                .strikethrough(isDone, color: palette.ink(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)

            if !task.note.isEmpty {
                Text(task.note)
                    .font(SimpleKanbanFont.ui(11.5, .medium, relativeTo: .caption))
                    .lineSpacing(1.5)
                    .foregroundStyle(palette.ink(0.5))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                PriorityDot(priority: task.priority)
                if let due = task.due {
                    DueChip(due: due, today: dayClock.today, columnID: task.columnID)
                }
                if task.hasSubtasks {
                    SubtaskCountBadge(text: task.subtaskProgressText)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 10)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.card)
                .shadow(
                    color: palette.shadow(isHovering ? 0.13 : 0.06),
                    radius: isHovering ? 7 : 1,
                    y: isHovering ? 4 : 1
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(palette.ink(0.07), lineWidth: 1)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(palette.accent, lineWidth: 2)
            }
        }
    }
}

#endif
