#if os(macOS)

import SwiftUI

/// The 336pt detail panel. Same content as the iOS sheet, different container.
struct MacInspector: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 18) {
                    Text(task.title)
                        .font(SimpleKanbanFont.serif(26))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(task.note.isEmpty ? "No description yet." : task.note)
                        .font(SimpleKanbanFont.ui(13, .medium, relativeTo: .subheadline))
                        .lineSpacing(4)
                        .foregroundStyle(palette.ink(0.62))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    status
                    attributes
                    checklist
                    activity
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 336)
        .background(palette.panel)
        .hairline(.leading, color: palette.ink(0.08))
        .transition(.opacity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(task.code)
                .sectionLabelStyle()
            Spacer(minLength: 0)
            Button { store.isInspectorOpen = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.ink(0.5))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.08), radius: 7)
            .accessibilityLabel("Close details")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status").sectionLabelStyle(size: 10.5)
            MoveToPicker(currentColumnID: task.columnID, metrics: .desk) { column in
                store.move(task.id, to: column.id)
            }
        }
    }

    private var attributes: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow(alignment: .center) {
                fieldName("Due")
                Text(task.due.isEmpty ? "No due date" : task.due)
                    .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .footnote))
                    .foregroundStyle(
                        task.due.isEmpty
                            ? palette.ink(0.45)
                            : palette.dueTone(due: task.due, columnID: task.columnID).foreground
                    )
            }
            GridRow(alignment: .center) {
                fieldName("Priority")
                HStack(spacing: 7) {
                    PriorityDot(priority: task.priority, diameter: 7)
                    Text(task.priority.displayName)
                        .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .footnote))
                }
            }
            GridRow(alignment: .top) {
                fieldName("Labels")
                LabelEditor(task: task, scope: .desk, metrics: .desk)
            }
        }
    }

    private func fieldName(_ text: String) -> some View {
        Text(text)
            .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .footnote))
            .foregroundStyle(palette.ink(0.42))
            .frame(width: 84, alignment: .leading)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Checklist").sectionLabelStyle(size: 10.5)
                ProgressMeter(fraction: task.subtaskFraction, height: 4)
                Text(task.subtaskProgressText)
                    .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .caption2))
                    .foregroundStyle(palette.ink(0.45))
            }
            ChecklistView(task: task, scope: .desk, metrics: .desk)
        }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity").sectionLabelStyle(size: 10.5)
            ForEach(task.activity) { entry in
                HStack(alignment: .top, spacing: 9) {
                    Circle()
                        .fill(palette.ink(0.22))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text("\(entryText(entry)) \(entryStamp(entry))")
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func entryText(_ entry: ActivityEntry) -> Text {
        Text(entry.text)
            .font(SimpleKanbanFont.ui(12, .medium, relativeTo: .caption))
            .foregroundColor(palette.ink(0.6))
    }

    private func entryStamp(_ entry: ActivityEntry) -> Text {
        Text("· \(entry.when)")
            .font(SimpleKanbanFont.ui(12, .semibold, relativeTo: .caption))
            .foregroundColor(palette.ink(0.35))
    }
}

#endif
