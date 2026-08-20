#if os(iOS)

import SwiftUI

/// The task detail bottom sheet — the same fields as the macOS inspector, sized
/// for touch and presented in a native sheet with the design's 82% detent.
struct PhoneDetailSheet: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Text(task.title)
                    .font(SimpleKanbanFont.serif(29))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(task.note.isEmpty ? "No description yet." : task.note)
                    .font(SimpleKanbanFont.ui(14.5, .medium, relativeTo: .subheadline))
                    .lineSpacing(5)
                    .foregroundStyle(palette.ink(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)

                moveTo
                attributeCards
                labels
                checklist
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .background(palette.sheet)
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(palette.sheet)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(task.code).sectionLabelStyle()
            Spacer(minLength: 0)
            Button { store.sheetID = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.ink(0.55))
                    .frame(width: 28, height: 28)
                    .background(palette.ink(0.07), in: .circle)
            }
            .buttonStyle(.bare)
            .accessibilityLabel("Close")
        }
    }

    private var moveTo: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Move to").sectionLabelStyle()
            MoveToPicker(currentColumnID: task.columnID, metrics: .sheet) { column in
                store.move(task.id, to: column.id)
            }
        }
    }

    private var attributeCards: some View {
        HStack(spacing: 8) {
            attributeCard(title: "Due") {
                Text(task.due.isEmpty ? "No due date" : task.due)
                    .font(SimpleKanbanFont.ui(14, .bold, relativeTo: .subheadline))
                    .foregroundStyle(
                        task.due.isEmpty
                            ? palette.ink(0.45)
                            : palette.dueTone(due: task.due, columnID: task.columnID).foreground
                    )
            }
            attributeCard(title: "Priority") {
                HStack(spacing: 6) {
                    PriorityDot(priority: task.priority, diameter: 7)
                    Text(task.priority.displayName)
                        .font(SimpleKanbanFont.ui(14, .bold, relativeTo: .subheadline))
                }
            }
        }
    }

    private func attributeCard(title: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).sectionLabelStyle(size: 10.5, tracking: 0.08)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.card, in: .rect(cornerRadius: 14))
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Labels").sectionLabelStyle()
            LabelEditor(task: task, scope: .sheet, metrics: .sheet)
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text("Checklist").sectionLabelStyle()
                ProgressMeter(fraction: task.subtaskFraction, height: 4)
                Text(task.subtaskProgressText)
                    .font(SimpleKanbanFont.ui(12, .bold, relativeTo: .caption))
                    .foregroundStyle(palette.ink(0.45))
            }
            VStack(spacing: 0) {
                ChecklistView(task: task, scope: .sheet, metrics: .sheet)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(palette.card, in: .rect(cornerRadius: 14))
        }
    }
}

#endif
