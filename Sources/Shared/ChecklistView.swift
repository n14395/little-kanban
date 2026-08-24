import SwiftUI

/// The sub-task list shared by the macOS inspector and the iOS detail sheet.
///
/// Every row edits in place: the box toggles and the text is a field driven by
/// the same `beginEditing`/`endEditing` session as the task title, so a row
/// retyped a letter at a time is one activity entry and one ⌘Z.
struct ChecklistView: View {
    struct Metrics {
        var box: CompletionToggle.Metrics
        var rowSpacing: CGFloat
        var rowVerticalPadding: CGFloat
        var rowHorizontalPadding: CGFloat
        /// The row's floor. Touch needs 44pt; a desk row sizes to its text.
        var rowMinHeight: CGFloat
        var rowRadius: CGFloat
        var font: CGFloat
        var showsRowHover: Bool
        /// Whether a row carries its own `×`. A pointer reveals it on hover; a
        /// touch surface reaches delete through the row's context menu instead
        /// of spending 44pt of row on a control that is nearly always idle.
        var showsInlineDelete: Bool
        var deleteGlyph: CGFloat
        /// How far the box's touch square is allowed to spill past the space the
        /// row gives it. The 44pt target lands inside the row's own padding
        /// rather than pushing the text across and the row down, so raising it
        /// moves nothing that is drawn.
        var boxOverhang: CGFloat
        /// The floor the row's text field claims, and how much of that claim it
        /// hands straight back. A field publishes an accessibility element the
        /// size of the text it draws — 21pt in a 44pt row — and no frame around
        /// it moves that; the field has to claim the height itself and name the
        /// shape. `fieldOverhang` is `boxOverhang`'s trick for the consequence:
        /// the claim would otherwise push the row past the height it draws.
        var fieldHit: CGFloat
        var fieldOverhang: CGFloat

        static let desk = Metrics(
            box: .deskRow, rowSpacing: 9,
            rowVerticalPadding: 6, rowHorizontalPadding: 8, rowMinHeight: 0,
            rowRadius: 9, font: 12.5,
            showsRowHover: true, showsInlineDelete: true, deleteGlyph: 9.5,
            boxOverhang: 0, fieldHit: 0, fieldOverhang: 0
        )
        static let sheet = Metrics(
            box: .sheetRow, rowSpacing: 11,
            rowVerticalPadding: 6, rowHorizontalPadding: 8, rowMinHeight: 44,
            rowRadius: 0, font: 14,
            showsRowHover: false, showsInlineDelete: false, deleteGlyph: 13,
            boxOverhang: 7, fieldHit: 44, fieldOverhang: 6
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    let scope: DetailScope
    var metrics: Metrics = .desk

    /// Which row holds the keyboard, and which task that row belongs to: a
    /// detail surface can be re-pointed at another card mid-edit, and the
    /// session has to be closed against the task it was opened on.
    @FocusState private var focusedRow: SubTask.ID?
    @State private var focusOwnerID: TaskItem.ID?
    @FocusState private var isDraftFocused: Bool
    @State private var hoveredRow: SubTask.ID?
    @State private var dropTargetRow: SubTask.ID?
    /// Bumped by the box and by nothing else, which is what the feedback is
    /// for: derived state — the row's `done` flags — also changes when the
    /// surface is re-pointed at another card, and a tick nobody made is worse
    /// than silence.
    @State private var ticks = 0

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.showsRowHover ? 2 : 0) {
            ForEach(task.subtasks) { subtask in
                row(for: subtask)
            }
            addRow
        }
        .onChange(of: focusedRow) { previous, current in
            if let previous, let owner = focusOwnerID {
                store.endEditing(.subtask, on: owner, scope: scope, subtask: previous)
            }
            focusOwnerID = current == nil ? nil : task.id
            if let current {
                store.beginEditing(.subtask, on: task.id, scope: scope, subtask: current)
            }
        }
        .onChange(of: task.id) { previousID, _ in
            endFocusedSession(on: previousID)
            focusedRow = nil
        }
        // A surface torn down mid-edit takes the field out of the hierarchy, and
        // a session left open never logs the rename and never restores a row
        // emptied to whitespace.
        .onDisappear { endFocusedSession(on: focusOwnerID) }
        // Ticking a row was the one gesture in the sheet with nothing to feel
        // (5.8). `.selection` rather than `.success`: a sub-task is a value
        // changing, and the tick that finishes the card is the card's.
        .sensoryFeedback(.selection, trigger: ticks)
    }

    private func endFocusedSession(on owner: TaskItem.ID?) {
        if let row = focusedRow, let owner, owner == focusOwnerID {
            store.endEditing(.subtask, on: owner, scope: scope, subtask: row)
        }
        focusOwnerID = nil
    }

    private func row(for subtask: SubTask) -> some View {
        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            CompletionToggle(isDone: subtask.done, metrics: metrics.box) {
                store.toggleSubtask(subtask.id, on: task.id)
                ticks += 1
            }
            .padding(-metrics.boxOverhang)

            TextField("Sub-task", text: textBinding(for: subtask))
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.font, .semibold, relativeTo: .footnote))
                .foregroundStyle(subtask.done ? palette.inkText(0.4) : palette.ink(0.8))
                .strikethrough(subtask.done, color: palette.ink(0.4))
                .focused($focusedRow, equals: subtask.id)
                .onSubmit { focusedRow = nil }
                .frame(maxWidth: .infinity, minHeight: metrics.fieldHit, alignment: .leading)
                .contentShape(.accessibility, Rectangle())
                .padding(.vertical, -metrics.fieldOverhang)
                // A placeholder is not a name, and this one is gone the moment
                // the row has any text — which is every row a reader meets.
                .accessibilityLabel("Sub-task")

            if metrics.showsInlineDelete {
                deleteButton(for: subtask)
            }
        }
        .padding(.vertical, metrics.rowVerticalPadding)
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .frame(minHeight: metrics.rowMinHeight)
        // A field's own hit area is the text it draws — 21pt inside a 44pt
        // row — so the slack the row keeps for a finger has to hand focus over,
        // the way `addRow` does. The box, the delete control and the text itself
        // sit in front of this shape and still take their own taps.
        .contentShape(.rect)
        .onTapGesture { focusedRow = subtask.id }
        .hoverBackground(metrics.showsRowHover ? palette.ink(0.05) : .clear, radius: metrics.rowRadius)
        .onHover { isInside in
            if isInside { hoveredRow = subtask.id } else if hoveredRow == subtask.id { hoveredRow = nil }
        }
        // The insertion point, drawn where the row would land.
        .overlay(alignment: .top) {
            if dropTargetRow == subtask.id {
                Capsule().fill(palette.accent).frame(height: 2)
            }
        }
        // The whole row is the grip. A drag begun inside the field is the
        // field's — that is how text selection works — so the box, the padding
        // and the gutter are what start a reorder.
        .draggable(SubtaskTransfer(subtask, on: task.id))
        .dropDestination(for: SubtaskTransfer.self) { items, _ in
            drop(items.first, before: subtask)
        } isTargeted: { isTargeted in
            dropTargetRow = isTargeted ? subtask.id : (dropTargetRow == subtask.id ? nil : dropTargetRow)
        }
        // Also the touch surface's delete, and the path VoiceOver can reach on
        // both: a control revealed by hover is a control a screen reader cannot
        // ask for. The two reorder items are here for the same reason — the row
        // could only be reordered by lifting it, and a long-press lift is
        // unreachable to VoiceOver and to Switch Control.
        .contextMenu {
            reorderItems(for: subtask)
            // Only when there is something above it: a lone row has no reorder
            // items, and a separator with nothing on one side of it is a line.
            if task.subtasks.count > 1 { Divider() }
            Button(role: .destructive) {
                store.deleteSubtask(subtask.id, from: task.id)
            } label: {
                Label("Delete Sub-task", systemImage: "trash")
            }
        }
    }

    /// Move Up / Move Down for one row: the drag's answer, said in words.
    ///
    /// Both go through `moveSubtask` and `dropOffset`, which is what the drop
    /// closure calls — so the menu and the drag cannot end up with two ideas of
    /// where a row lands, and `dropOffset`'s off-by-one is pinned once.
    @ViewBuilder
    private func reorderItems(for subtask: SubTask) -> some View {
        if let index = task.subtasks.firstIndex(where: { $0.id == subtask.id }) {
            if index > 0 {
                Button {
                    move(from: index, to: index - 1)
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
            }
            if index + 1 < task.subtasks.count {
                Button {
                    move(from: index, to: index + 1)
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
            }
        }
    }

    private func move(from: Int, to: Int) {
        store.moveSubtask(
            fromOffsets: IndexSet(integer: from),
            toOffset: BoardStore.dropOffset(from: from, to: to),
            on: task.id
        )
    }

    private func deleteButton(for subtask: SubTask) -> some View {
        Button {
            store.deleteSubtask(subtask.id, from: task.id)
        } label: {
            Image(systemName: "xmark")
                .font(palette.ui(metrics.deleteGlyph, .bold, relativeTo: .caption2))
                .fontWeight(.bold)
                .foregroundStyle(palette.inkText(0.4))
                .frame(width: metrics.box.hitSize, height: metrics.box.hitSize)
        }
        .buttonStyle(.bare)
        .opacity(hoveredRow == subtask.id ? 1 : 0)
        // Invisible is not the same as absent: without this the dead corner of
        // an unhovered row still deletes what is in it.
        .allowsHitTesting(hoveredRow == subtask.id)
        .accessibilityHidden(hoveredRow != subtask.id)
        .accessibilityLabel("Delete sub-task")
    }

    /// Moves the dragged row to where `target` sits. A payload from another task
    /// is refused rather than moved across, which is not a gesture the checklist
    /// offers.
    private func drop(_ payload: SubtaskTransfer?, before target: SubTask) -> Bool {
        guard let payload, payload.taskID == task.id,
              let from = task.subtasks.firstIndex(where: { $0.id == payload.subtaskID }),
              let to = task.subtasks.firstIndex(where: { $0.id == target.id }),
              from != to
        else { return false }
        move(from: from, to: to)
        return true
    }

    private var addRow: some View {
        HStack(alignment: .center, spacing: metrics.rowSpacing) {
            RoundedRectangle(cornerRadius: metrics.box.radius)
                .strokeBorder(
                    palette.ink(0.28),
                    style: StrokeStyle(lineWidth: metrics.box.borderWidth, dash: [2.5, 2.5])
                )
                .frame(width: metrics.box.size, height: metrics.box.size)
                .overlay {
                    Image(systemName: "plus")
                        .font(palette.ui(metrics.box.size * 0.5, .semibold, relativeTo: .caption2))
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.inkText(0.4))
                }
                .frame(width: metrics.box.hitSize, height: metrics.box.hitSize)
                .padding(-metrics.boxOverhang)

            TextField("Add new sub-task", text: subtaskDraftBinding)
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.font, .semibold, relativeTo: .footnote))
                .foregroundStyle(palette.ink)
                .focused($isDraftFocused)
                .frame(minHeight: metrics.fieldHit)
                .contentShape(.accessibility, Rectangle())
                .padding(.vertical, -metrics.fieldOverhang)
                .accessibilityLabel("Add new sub-task")
                .onSubmit {
                    store.commitSubtaskDraft(for: scope, task: task.id)
                    // Return **ends editing** — that is what it is for, and the
                    // rows above rely on it: theirs clears `focusedRow`. This
                    // one field is the exception, because a checklist is
                    // written as a list: the draft moves down under the
                    // sub-task it just made, and the next one is typed straight
                    // into it. Losing the keyboard there costs a click a line.
                    //
                    // Asked for on the far side of a yield, for the reason
                    // `focusWhenReady` gives: inside the submit handler is
                    // inside the turn that is about to resign the field.
                    Task { @MainActor in
                        await Task.yield()
                        isDraftFocused = true
                    }
                }
                .onKeyPress(.escape) {
                    // Only ours to swallow when there is something to clear —
                    // otherwise Escape belongs to whatever is presenting us.
                    guard !store.subtaskDraft(for: scope, task: task.id).isEmpty else { return .ignored }
                    store.setSubtaskDraft("", for: scope, task: task.id)
                    return .handled
                }
        }
        .padding(.vertical, metrics.rowVerticalPadding)
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .frame(minHeight: metrics.rowMinHeight)
        // The dashed box was decoration. It — and the rest of the row's slack —
        // is the field's tap target now; taps inside the field still belong to
        // the field, which is what puts the caret where it was aimed.
        .contentShape(.rect)
        .onTapGesture { isDraftFocused = true }
        .hoverBackground(metrics.showsRowHover ? palette.ink(0.05) : .clear, radius: metrics.rowRadius)
    }

    private func textBinding(for subtask: SubTask) -> Binding<String> {
        Binding(
            get: { store.subtaskText(subtask.id, on: task.id) },
            set: { store.updateSubtask(subtask.id, text: $0, on: task.id) }
        )
    }

    private var subtaskDraftBinding: Binding<String> {
        Binding(
            get: { store.subtaskDraft(for: scope, task: task.id) },
            set: { store.setSubtaskDraft($0, for: scope, task: task.id) }
        )
    }
}
