import SwiftUI

/// A task's label chips plus the dashed `+` that opens the label picker.
struct LabelEditor: View {
    struct Metrics {
        var chipSize: LabelChip.Size
        var addFont: CGFloat
        var addHorizontalPadding: CGFloat
        var addVerticalPadding: CGFloat
        var addRadius: CGFloat
        var addBorderWidth: CGFloat
        var spacing: CGFloat
        /// The square the dashed `+` claims. Zero on the desk, where it claims
        /// only what it draws; on touch the dashed box is half a target.
        var addHit: CGFloat
        var picker: LabelPickerList.Metrics

        static let desk = Metrics(
            chipSize: .compact, addFont: 11, addHorizontalPadding: 7, addVerticalPadding: 3,
            addRadius: 6, addBorderWidth: 1, spacing: 5, addHit: 0, picker: .desk
        )
        static let sheet = Metrics(
            chipSize: .comfortable, addFont: 13, addHorizontalPadding: 11, addVerticalPadding: 5,
            addRadius: 8, addBorderWidth: 1.5, spacing: 6, addHit: 44, picker: .sheet
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    let scope: DetailScope
    var metrics: Metrics = .desk

    var body: some View {
        FlowLayout(spacing: metrics.spacing) {
            ForEach(store.labels(for: task)) { label in
                LabelChip(label: label, size: metrics.chipSize) {
                    store.toggleLabel(label.key, on: task.id)
                }
            }
            addButton
        }
    }

    private var addButton: some View {
        Button {
            store.toggleLabelPicker(scope, task: task.id)
        } label: {
            Image(systemName: "plus")
                .symbolSize(metrics.addFont, weight: .heavy, relativeTo: .caption)
                .foregroundStyle(palette.inkText(0.5))
                .padding(.horizontal, metrics.addHorizontalPadding)
                .padding(.vertical, metrics.addVerticalPadding)
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.addRadius)
                        .strokeBorder(
                            palette.ink(0.25),
                            style: StrokeStyle(lineWidth: metrics.addBorderWidth, dash: [3, 3])
                        )
                }
                .frame(minWidth: metrics.addHit, minHeight: metrics.addHit)
        }
        .buttonStyle(.bare)
        .accessibilityLabel("Add label")
        .popover(isPresented: pickerBinding, arrowEdge: .bottom) {
            LabelPickerList(task: task, scope: scope, metrics: metrics.picker)
                .environment(store)
                .environment(\.palette, palette)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var pickerBinding: Binding<Bool> {
        Binding(
            get: { store.labelPickerScope == scope },
            set: { isOpen in
                if isOpen { store.labelPickerScope = scope } else { store.closeLabelPicker(scope, task: task.id) }
            }
        )
    }
}

/// The picker body: every known label with a tick for the ones applied, plus a
/// field that creates a new label on ⏎.
struct LabelPickerList: View {
    struct Metrics {
        var width: CGFloat
        var maxListHeight: CGFloat
        var rowVerticalPadding: CGFloat
        var rowHorizontalPadding: CGFloat
        var rowRadius: CGFloat
        /// The row's floor. A chip plus its padding falls short of 44 on touch.
        var rowHit: CGFloat
        var chipSize: LabelChip.Size
        var fieldFont: CGFloat
        var fieldPadding: CGFloat
        var fieldRadius: CGFloat
        var panelPadding: CGFloat

        static let desk = Metrics(
            width: 214, maxListHeight: 168, rowVerticalPadding: 6, rowHorizontalPadding: 7,
            rowRadius: 8, rowHit: 0, chipSize: .compact, fieldFont: 12, fieldPadding: 8,
            fieldRadius: 9, panelPadding: 7
        )
        static let sheet = Metrics(
            width: 250, maxListHeight: 196, rowVerticalPadding: 9, rowHorizontalPadding: 8,
            rowRadius: 10, rowHit: 44, chipSize: .comfortable, fieldFont: 14, fieldPadding: 10,
            fieldRadius: 11, panelPadding: 8
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    /// Which surface the picker belongs to, so the half-typed name in its
    /// field is kept apart from the other surface's.
    let scope: DetailScope
    var metrics: Metrics = .desk

    /// The picker exists to be typed into, so it opens with the field ready.
    @FocusState private var isFieldFocused: Bool

    /// Read through the store so ticks update as labels are toggled.
    private var liveTask: TaskItem { store[task.id] ?? task }

    var body: some View {
        VStack(spacing: 5) {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(store.labels) { label in
                        row(for: label)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: metrics.maxListHeight)

            newLabelField
        }
        .padding(metrics.panelPadding)
        .frame(width: metrics.width)
        .background(palette.card)
        .presentationBackground(palette.card)
        .defaultFocus($isFieldFocused, true)
        // `defaultFocus` alone does not always take in a popover, whose window
        // becomes key a beat after its content appears. The fallback was an
        // `onAppear`, which is the assignment this app has since watched fail
        // three times over — see ``SwiftUICore/View/focusWhenReady(_:)``.
        .focusWhenReady($isFieldFocused)
    }

    private func row(for label: LabelDef) -> some View {
        let isApplied = liveTask.labelKeys.contains(label.key)
        return Button {
            store.toggleLabel(label.key, on: task.id)
        } label: {
            HStack(spacing: 8) {
                LabelChip(label: label, size: metrics.chipSize)
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .symbolSize(metrics.chipSize == .compact ? 11 : 13, weight: .bold, relativeTo: .caption)
                    .foregroundStyle(palette.ink(0.7))
                    .opacity(isApplied ? 1 : 0)
            }
            .padding(.vertical, metrics.rowVerticalPadding)
            .padding(.horizontal, metrics.rowHorizontalPadding)
            .frame(minHeight: metrics.rowHit)
            .background(isApplied ? palette.ink(0.05) : .clear, in: .rect(cornerRadius: metrics.rowRadius))
        }
        .buttonStyle(.bare)
        .hoverBackground(palette.ink(0.06), radius: metrics.rowRadius)
        .accessibilityAddTraits(isApplied ? [.isSelected] : [])
    }

    private var newLabelField: some View {
        HStack(spacing: metrics.chipSize == .compact ? 7 : 8) {
            Image(systemName: "plus")
                .symbolSize(metrics.fieldFont, weight: .heavy, relativeTo: .subheadline)
                .foregroundStyle(palette.inkText(0.4))
            TextField("New label, then ⏎", text: draftBinding)
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.fieldFont, .bold, relativeTo: .caption))
                .foregroundStyle(palette.ink)
                .focused($isFieldFocused)
                .onSubmit { store.commitLabelDraft(for: scope, task: task.id) }
                .onKeyPress(.escape) {
                    // Closing the picker is also what clears the draft.
                    store.closeLabelPicker(scope, task: task.id)
                    return .handled
                }
        }
        .padding(metrics.fieldPadding)
        .background(palette.ink(0.05), in: .rect(cornerRadius: metrics.fieldRadius))
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { store.labelDraft(for: scope, task: task.id) },
            set: { store.setLabelDraft($0, for: scope, task: task.id) }
        )
    }
}
