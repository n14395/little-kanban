#if os(macOS)

import SwiftUI

/// The 336pt detail panel. Same content as the iOS sheet, different container.
///
/// Every field here writes straight through to the store, so an edit shows on
/// the board card as it is typed. Activity is logged once per editing session
/// rather than once per keystroke — see `BoardStore.beginEditing`.
struct MacInspector: View {
    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    @FocusState private var focusedField: TaskField?
    /// Which task the focused field belongs to. Selecting another card swaps
    /// `task` underneath a live focus, so the snapshot is closed against the
    /// task that was actually being edited.
    @State private var focusOwnerID: TaskItem.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 18) {
                    titleField
                    noteField
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
        .onChange(of: focusedField) { previous, current in
            if let previous, let owner = focusOwnerID {
                store.endEditing(previous, on: owner, scope: .desk)
            }
            focusOwnerID = current == nil ? nil : task.id
            if let current { store.beginEditing(current, on: task.id, scope: .desk) }
        }
        .onChange(of: task.id) { previousID, _ in
            if let field = focusedField, let owner = focusOwnerID, owner == previousID {
                store.endEditing(field, on: owner, scope: .desk)
            }
            focusOwnerID = nil
            focusedField = nil
        }
        // Closing the panel mid-edit takes the field out of the hierarchy;
        // whether SwiftUI clears `focusedField` first is not guaranteed, and a
        // session left open never logs the rename and never restores a title
        // emptied to whitespace. Closed against the task that was being edited,
        // which may no longer be `task`.
        .onDisappear {
            if let field = focusedField, let owner = focusOwnerID {
                store.endEditing(field, on: owner, scope: .desk)
            }
            focusOwnerID = nil
        }
        .onAppear { claimPendingFocus() }
        .onChange(of: store.pendingTitleFocusID) { _, _ in claimPendingFocus() }
    }

    /// A task created without a title opens with the title field ready.
    private func claimPendingFocus() {
        guard store.pendingTitleFocusID == task.id else { return }
        store.pendingTitleFocusID = nil
        focusedField = .title
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

    // MARK: Editable text

    private var titleField: some View {
        TextField("Task title", text: binding(.title), axis: .vertical)
            .textFieldStyle(.plain)
            .font(SimpleKanbanFont.serif(26))
            .lineSpacing(3)
            .foregroundStyle(palette.ink)
            .focused($focusedField, equals: .title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Title")
    }

    private var noteField: some View {
        TextField("Add a description", text: binding(.note), axis: .vertical)
            .textFieldStyle(.plain)
            .font(SimpleKanbanFont.ui(13, .medium, relativeTo: .subheadline))
            .lineSpacing(4)
            .foregroundStyle(palette.ink(0.62))
            .focused($focusedField, equals: .note)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Description")
    }

    private func binding(_ field: TaskField) -> Binding<String> {
        Binding(
            get: { store.text(field, on: task.id) },
            set: { store.setText($0, field: field, on: task.id) }
        )
    }

    // MARK: Attributes

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
                DueDateField(task: task, scope: .desk, metrics: .desk)
            }
            GridRow(alignment: .center) {
                fieldName("Priority")
                PriorityPicker(task: task, scope: .desk, metrics: .desk)
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
        Text(entry.text(today: dayClock.today))
            .font(SimpleKanbanFont.ui(12, .medium, relativeTo: .caption))
            .foregroundColor(palette.ink(0.6))
    }

    private func entryStamp(_ entry: ActivityEntry) -> Text {
        Text("· \(entry.whenText())")
            .font(SimpleKanbanFont.ui(12, .semibold, relativeTo: .caption))
            .foregroundColor(palette.ink(0.35))
    }
}

#endif
