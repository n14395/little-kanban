#if os(iOS)

import SwiftUI
import UIKit

/// The task detail bottom sheet — the same fields as the macOS inspector, sized
/// for touch and presented in a native sheet at full height.
struct PhoneDetailSheet: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    @FocusState private var focusedField: TaskField?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                titleField
                noteField
                moveTo
                attributeCards
                labels
                checklist
                activity
                restoreRow
                deleteRow
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .scrollDismissesKeyboard(.interactively)
        // The description is multi-line, so Return types a newline there and
        // the keyboard needs a way out that is not "tap outside". The bar is
        // scoped to the sheet rather than to that one field because SwiftUI
        // raises it for whichever field brings the keyboard up.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", action: dismissKeyboard)
                    .font(SimpleKanbanFont.ui(15, .bold, relativeTo: .body))
            }
        }
        .background(palette.sheet)
        // Full height, not the design's 82%. A sheet held at any detent below
        // `.large` floats inset from the screen edges on this OS and is scaled
        // to compensate — 0.9602 on a 402pt-wide phone, 0.9573 on a 375pt one —
        // so every 44pt control in here rendered at 42.25pt, under the touch
        // minimum. The factor is the inset over the screen width, so it differs
        // per device and no amount of padding the shared `.sheet` presets can
        // buy it back. Height was the cheaper thing to give up.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(palette.sheet)
        // The phone's open task, published for Handoff and Spotlight the same
        // way the desk publishes the inspector's.
        .taskUserActivity(task)
        .onChange(of: focusedField) { previous, current in
            if let previous { store.endEditing(previous, on: task.id, scope: .sheet) }
            if let current { store.beginEditing(current, on: task.id, scope: .sheet) }
        }
        .onAppear { claimPendingFocus() }
        .onDisappear {
            if let field = focusedField { store.endEditing(field, on: task.id, scope: .sheet) }
        }
    }

    /// A task captured with the "+" button arrives untitled, so the sheet opens
    /// ready to type its name.
    private func claimPendingFocus() {
        guard store.pendingTitleFocusID == task.id else { return }
        store.pendingTitleFocusID = nil
        focusedField = .title
    }

    // MARK: Editable text

    /// Single-line on purpose: a title is one line by definition, and on a
    /// vertical-axis field Return inserts a newline instead of submitting, so
    /// the `.done` key painted here would not have done what it said.
    private var titleField: some View {
        TextField("Task title", text: binding(.title))
            .textFieldStyle(.plain)
            .font(SimpleKanbanFont.serif(29))
            .lineSpacing(3)
            .foregroundStyle(palette.ink)
            .focused($focusedField, equals: .title)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background { focusCatcher(.title) }
            .accessibilityLabel("Title")
    }

    /// Keeps its vertical axis: a description is meant to hold paragraphs.
    private var noteField: some View {
        TextField("Add a description", text: binding(.note), axis: .vertical)
            .textFieldStyle(.plain)
            .font(SimpleKanbanFont.ui(14.5, .medium, relativeTo: .subheadline))
            .lineSpacing(5)
            .foregroundStyle(palette.ink(0.62))
            .focused($focusedField, equals: .note)
            // A one-line description is 21pt of text in a sheet full of 44pt
            // controls; the minimum keeps the empty field a target rather than
            // a hairline, and grows past it as paragraphs arrive.
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background { focusCatcher(.note) }
            .accessibilityLabel("Description")
    }

    /// A text field's own hit area is the height of its text, so the space the
    /// 44pt minimum adds around it would otherwise be dead. This sits *behind*
    /// the field rather than over it, so a tap on the text still reaches the
    /// field and still lands the caret where the finger did.
    private func focusCatcher(_ field: TaskField) -> some View {
        Color.clear
            .contentShape(.rect)
            .onTapGesture { focusedField = field }
    }

    /// Resigns first responder outright rather than only clearing this view's
    /// focus: the checklist rows keep their own focus state, and a Done key
    /// that left one of those keyboards up would be the same lie as the
    /// `.submitLabel(.done)` this sheet used to paint on a wrapping title.
    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    private func binding(_ field: TaskField) -> Binding<String> {
        Binding(
            get: { store.text(field, on: task.id) },
            set: { store.setText($0, field: field, on: task.id) }
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(task.code).sectionLabelStyle(opacity: Palette.readableInk)
            Spacer(minLength: 0)
            // The drawn circle stays at the design's 28pt; the outer frame is
            // the 44pt touch minimum, which the circular content shape then
            // trims back to a disc so the corners are not live.
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(SimpleKanbanFont.ui(12, .semibold, relativeTo: .footnote))
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.inkText(0.55))
                    .frame(minWidth: 28, minHeight: 28)
                    .background(palette.ink(0.07), in: .circle)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bare)
            .contentShape(.circle)
            .accessibilityLabel("Close")
        }
    }

    /// Closing the sheet is where a quick capture nobody typed into goes away
    /// again (1.14). The id has to be read before the sheet is torn down.
    private func dismiss() {
        let id = task.id
        store.sheetID = nil
        store.discardIfUntouched(id)
    }

    /// Where the card lives, in the two halves it now has: which board, and
    /// where on it. The segments only ever show one board's columns, so without
    /// the row above them a card could not cross from one board to another, nor
    /// come back to the Inbox — and on this surface these two are the only route
    /// a card has anywhere.
    ///
    /// The picker falls back to the board on screen for a card in the Inbox, so
    /// filing one is a single tap rather than a board and then a column.
    private var moveTo: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Move to").sectionLabelStyle(opacity: Palette.readableInk)
            BoardDestinationMenu(task: task, metrics: .sheet)
            MoveToPicker(
                board: store.board(for: task) ?? store.activeBoard,
                currentColumnID: task.columnID, metrics: .sheet
            ) { placement in
                store.move(task.id, to: placement)
            }
        }
    }

    private var attributeCards: some View {
        HStack(spacing: 8) {
            attributeCard(title: "Due") {
                DueDateField(task: task, scope: .sheet, metrics: .sheet)
            }
            attributeCard(title: "Priority") {
                PriorityPicker(task: task, scope: .sheet, metrics: .sheet)
            }
        }
    }

    private func attributeCard(title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.card, in: .rect(cornerRadius: 14))
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Labels").sectionLabelStyle(opacity: Palette.readableInk)
            LabelEditor(task: task, scope: .sheet, metrics: .sheet)
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text("Checklist").sectionLabelStyle(opacity: Palette.readableInk)
                ProgressMeter(fraction: task.subtaskFraction, height: 4)
                Text(task.subtaskProgressText)
                    .font(SimpleKanbanFont.ui(12, .bold, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.45))
            }
            VStack(spacing: 0) {
                ChecklistView(task: task, scope: .sheet, metrics: .sheet)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(palette.card, in: .rect(cornerRadius: 14))
        }
    }

    /// The history the inspector has always shown and the sheet never did (4.6),
    /// last in the scroll because it is the one section nobody opens the sheet
    /// to edit. `ActivityFeed` is the inspector's own rendering, so the same
    /// task now reads the same on both platforms.
    @ViewBuilder private var activity: some View {
        if !task.activity.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("Activity").sectionLabelStyle(opacity: Palette.readableInk)
                ActivityFeed(task: task, metrics: .sheet)
            }
        }
    }

    /// Only on a task opened from the Archive. Without it the sheet is a dead
    /// end for an archived card: every other route out of the archive is a
    /// gesture on the row behind it, and Delete is the only verb on screen.
    @ViewBuilder private var restoreRow: some View {
        if task.isArchived {
            Button { store.unarchive(task.id) } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.uturn.backward")
                    Text("Restore to Board")
                }
                .font(SimpleKanbanFont.ui(14.5, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(palette.accentSoft, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.bare)
            .padding(.top, 6)
        }
    }

    /// No confirmation, by design: the delete happens and undo is the safety
    /// net. `deleteTask` closes the sheet itself by clearing `sheetID`.
    private var deleteRow: some View {
        Button(role: .destructive) {
            store.deleteTask(task.id)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "trash")
                Text("Delete Task")
            }
            .font(SimpleKanbanFont.ui(14.5, .bold, relativeTo: .subheadline))
            .foregroundStyle(destructiveTone.foreground)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(destructiveTone.background, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.bare)
        .padding(.top, 6)
    }

    /// `Palette` has no danger semantic of its own yet, so the destructive row
    /// borrows the overdue tone rather than naming a colour here (C2). The role
    /// is passed explicitly because the task's own would turn the row green
    /// once it reached Done.
    private var destructiveTone: (background: Color, foreground: Color) {
        palette.dueTone(urgency: .overdue, role: .backlog)
    }
}

#endif
