import SwiftUI

/// The sub-task list shared by the macOS inspector and the iOS detail sheet.
struct ChecklistView: View {
    struct Metrics {
        var boxSize: CGFloat
        var boxRadius: CGFloat
        var rowSpacing: CGFloat
        var rowVerticalPadding: CGFloat
        var rowHorizontalPadding: CGFloat
        var rowRadius: CGFloat
        var font: CGFloat
        var showsRowHover: Bool

        static let desk = Metrics(
            boxSize: 15, boxRadius: 5, rowSpacing: 9,
            rowVerticalPadding: 7, rowHorizontalPadding: 8, rowRadius: 9,
            font: 12.5, showsRowHover: true
        )
        static let sheet = Metrics(
            boxSize: 20, boxRadius: 6, rowSpacing: 11,
            rowVerticalPadding: 11, rowHorizontalPadding: 8, rowRadius: 0,
            font: 14, showsRowHover: false
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    let scope: DetailScope
    var metrics: Metrics = .desk

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.showsRowHover ? 2 : 0) {
            ForEach(task.subtasks) { subtask in
                Button {
                    store.toggleSubtask(subtask.id, on: task.id)
                } label: {
                    row(for: subtask)
                }
                .buttonStyle(.bare)
            }
            addRow
        }
    }

    private func row(for subtask: SubTask) -> some View {
        HStack(alignment: .top, spacing: metrics.rowSpacing) {
            checkbox(isDone: subtask.done)
            Text(subtask.text)
                .font(SimpleKanbanFont.ui(metrics.font, .semibold, relativeTo: .footnote))
                .lineSpacing(2)
                .foregroundStyle(subtask.done ? palette.ink(0.4) : palette.ink(0.8))
                .strikethrough(subtask.done, color: palette.ink(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, metrics.rowVerticalPadding)
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .hoverBackground(metrics.showsRowHover ? palette.ink(0.05) : .clear, radius: metrics.rowRadius)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(subtask.done ? [.isSelected] : [])
    }

    private func checkbox(isDone: Bool) -> some View {
        RoundedRectangle(cornerRadius: metrics.boxRadius)
            .fill(isDone ? palette.accent : .clear)
            .overlay {
                RoundedRectangle(cornerRadius: metrics.boxRadius)
                    .strokeBorder(isDone ? palette.accent : palette.ink(0.25), lineWidth: 1.5)
            }
            .overlay {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: metrics.boxSize * 0.58, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: metrics.boxSize, height: metrics.boxSize)
            .padding(.top, metrics.showsRowHover ? 1 : 0)
    }

    private var addRow: some View {
        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            RoundedRectangle(cornerRadius: metrics.boxRadius)
                .strokeBorder(palette.ink(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5]))
                .frame(width: metrics.boxSize, height: metrics.boxSize)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: metrics.boxSize * 0.5, weight: .semibold))
                        .foregroundStyle(palette.ink(0.4))
                }

            TextField("Add new sub-task", text: subtaskDraftBinding)
                .textFieldStyle(.plain)
                .font(SimpleKanbanFont.ui(metrics.font, .semibold, relativeTo: .footnote))
                .foregroundStyle(palette.ink)
                .onSubmit { store.addSubtask(to: task.id, text: store.subtaskDraft(for: scope)) }
        }
        .padding(.vertical, metrics.rowVerticalPadding)
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .hoverBackground(metrics.showsRowHover ? palette.ink(0.05) : .clear, radius: metrics.rowRadius)
    }

    private var subtaskDraftBinding: Binding<String> {
        Binding(
            get: { store.subtaskDraft(for: scope) },
            set: { store.setSubtaskDraft($0, for: scope) }
        )
    }
}
