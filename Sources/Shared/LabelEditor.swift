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

/// The picker body: a search field over every known label with a tick for the
/// ones applied, and a **New Label** button that swaps the panel for a small
/// compose form — a name, a colour, and the two verbs.
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
        /// The shared name-and-colour form — the manager presents the same one.
        var compose: LabelComposeForm.Metrics

        static let desk = Metrics(
            width: 214, maxListHeight: 320, rowVerticalPadding: 6, rowHorizontalPadding: 7,
            rowRadius: 8, rowHit: 0, chipSize: .compact, fieldFont: 12, fieldPadding: 8,
            fieldRadius: 9, panelPadding: 7, compose: .desk
        )
        static let sheet = Metrics(
            width: 250, maxListHeight: 320, rowVerticalPadding: 9, rowHorizontalPadding: 8,
            rowRadius: 10, rowHit: 44, chipSize: .comfortable, fieldFont: 14, fieldPadding: 10,
            fieldRadius: 11, panelPadding: 8, compose: .sheet
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    /// Which surface the picker belongs to, so the half-typed name in its
    /// compose form is kept apart from the other surface's.
    let scope: DetailScope
    var metrics: Metrics = .desk

    @FocusState private var isSearchFocused: Bool

    /// What the search field has narrowed the list to. View state rather than
    /// a store draft — a filter is about what is on screen, and dismissing the
    /// popover is exactly when it should be forgotten.
    @State private var query = ""
    /// Whether the panel is showing the compose form instead of the list.
    @State private var isComposing = false
    /// The colour picked in the form, or `nil` while it still shows the
    /// rotation's next — see `BoardStore.nextLabelColor`.
    @State private var chosenColor: SwatchColor?

    /// Read through the store so ticks update as labels are toggled.
    private var liveTask: TaskItem { store[task.id] ?? task }

    var body: some View {
        Group {
            if isComposing {
                composeForm
            } else {
                list
            }
        }
        .padding(metrics.panelPadding)
        .frame(width: metrics.width)
        .background(palette.card)
        .presentationBackground(palette.card)
    }

    private var list: some View {
        VStack(spacing: 5) {
            searchField
            newLabelButton
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(visibleLabels) { label in
                        row(for: label)
                    }
                    if visibleLabels.isEmpty, !query.isEmpty {
                        Text("No labels match")
                            .font(palette.ui(metrics.fieldFont, .medium, relativeTo: .caption))
                            .foregroundStyle(palette.inkText(0.45))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, metrics.rowVerticalPadding)
                            .padding(.horizontal, metrics.rowHorizontalPadding)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: metrics.maxListHeight)
        }
        .defaultFocus($isSearchFocused, true)
        // `defaultFocus` alone does not always take in a popover, whose window
        // becomes key a beat after its content appears. The fallback was an
        // `onAppear`, which is the assignment this app has since watched fail
        // three times over — see ``SwiftUICore/View/focusWhenReady(_:)``. It
        // runs again when the compose form hands the panel back, which is the
        // second moment the search field should be ready under the cursor.
        .focusWhenReady($isSearchFocused)
    }

    /// The labels the query leaves standing — all of them for an empty one.
    private var visibleLabels: [LabelDef] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.labels }
        return store.labels.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
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

    private var searchField: some View {
        HStack(spacing: metrics.chipSize == .compact ? 7 : 8) {
            Image(systemName: "magnifyingglass")
                .symbolSize(metrics.fieldFont, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(palette.inkText(0.4))
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.fieldFont, .bold, relativeTo: .caption))
                .foregroundStyle(palette.ink)
                .focused($isSearchFocused)
                .accessibilityLabel("Search labels")
                .onKeyPress(.escape) {
                    // A narrowed list widens first; a second Escape closes.
                    guard query.isEmpty else {
                        query = ""
                        return .handled
                    }
                    store.closeLabelPicker(scope, task: task.id)
                    return .handled
                }
        }
        .padding(metrics.fieldPadding)
        .background(palette.ink(0.05), in: .rect(cornerRadius: metrics.fieldRadius))
    }

    /// Heads the list rather than riding in it, so it cannot be scrolled out
    /// of reach — it is the panel's one way to say something new.
    private var newLabelButton: some View {
        Button { beginComposing() } label: {
            HStack(spacing: metrics.chipSize == .compact ? 7 : 8) {
                Image(systemName: "plus")
                    .symbolSize(metrics.fieldFont, weight: .heavy, relativeTo: .subheadline)
                    .foregroundStyle(palette.accent)
                Text("New Label")
                    .font(palette.ui(metrics.fieldFont, .bold, relativeTo: .caption))
                    .foregroundStyle(palette.accent)
                Spacer(minLength: 0)
            }
            .padding(.vertical, metrics.rowVerticalPadding)
            .padding(.horizontal, metrics.rowHorizontalPadding)
            .frame(minHeight: metrics.rowHit)
            .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .hoverBackground(palette.ink(0.06), radius: metrics.rowRadius)
    }

    /// Opens the form on whatever the search said: a query that found nothing
    /// is most of a name somebody was about to make, and retyping it would be
    /// the popover forgetting what it was just told.
    private func beginComposing() {
        store.setLabelDraft(query.trimmingCharacters(in: .whitespaces), for: scope, task: task.id)
        chosenColor = nil
        isComposing = true
    }

    // MARK: The compose form

    private var composeForm: some View {
        LabelComposeForm(
            name: draftBinding,
            chosenColor: $chosenColor,
            defaultColor: store.nextLabelColor,
            metrics: metrics.compose,
            onCancel: cancelComposing,
            onCommit: commitNewLabel
        )
    }

    private func commitNewLabel() {
        // The colour is passed explicitly so the label wears exactly what the
        // well showed, chosen or defaulted.
        store.commitLabelDraft(for: scope, task: task.id, color: chosenColor ?? store.nextLabelColor)
        // Back to the list with the filter cleared: the new label is applied
        // and ticked, and a query left standing could hide the very row that
        // proves it.
        query = ""
        isComposing = false
    }

    private func cancelComposing() {
        store.setLabelDraft("", for: scope, task: task.id)
        chosenColor = nil
        isComposing = false
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { store.labelDraft(for: scope, task: task.id) },
            set: { store.setLabelDraft($0, for: scope, task: task.id) }
        )
    }
}

/// The name-and-colour form both label composers share: the task picker swaps
/// its popover to it, and the manager hangs it off its **Create new label**
/// button. It owns its own focus and its own empty-name refusal; what happens
/// to a committed name is the caller's — the picker applies it to a task, the
/// manager only adds it to the vocabulary.
struct LabelComposeForm: View {
    struct Metrics {
        var fieldFont: CGFloat
        var fieldPadding: CGFloat
        var fieldRadius: CGFloat
        /// The floor under the two verbs, for a finger.
        var actionHit: CGFloat
        var colorWell: ColorWell.Metrics

        static let desk = Metrics(
            fieldFont: 12, fieldPadding: 8, fieldRadius: 9, actionHit: 0, colorWell: .desk
        )
        static let sheet = Metrics(
            fieldFont: 14, fieldPadding: 10, fieldRadius: 11, actionHit: 44, colorWell: .sheet
        )
    }

    @Environment(\.palette) private var palette

    @Binding var name: String
    /// The colour picked in the form, or `nil` while the well still shows
    /// `defaultColor` — the rotation's next, see `BoardStore.nextLabelColor`.
    @Binding var chosenColor: SwatchColor?
    let defaultColor: SwatchColor
    var metrics: Metrics = .desk
    let onCancel: () -> Void
    let onCommit: () -> Void

    @FocusState private var isNameFocused: Bool

    private var isEmpty: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New Label")
                .font(palette.ui(metrics.fieldFont + 1, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)

            TextField("Label name", text: $name)
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.fieldFont, .bold, relativeTo: .caption))
                .foregroundStyle(palette.ink)
                .focused($isNameFocused)
                .onSubmit { if !isEmpty { onCommit() } }
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
                .accessibilityLabel("Label name")
                .padding(metrics.fieldPadding)
                .background(palette.ink(0.05), in: .rect(cornerRadius: metrics.fieldRadius))

            // Opens on the rotation's next colour, which is what the label
            // would have worn anyway — the form only makes the default visible
            // and pickable.
            ColorWell(selection: chosenColor ?? defaultColor, metrics: metrics.colorWell) {
                chosenColor = $0
            }

            HStack {
                Button("Cancel") { onCancel() }
                    .font(palette.ui(metrics.fieldFont, .semibold, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.55))
                    .buttonStyle(.bare)
                    .frame(minHeight: metrics.actionHit)
                Spacer(minLength: 0)
                Button("Add") { onCommit() }
                    .font(palette.ui(metrics.fieldFont, .bold, relativeTo: .caption))
                    .foregroundStyle(palette.accent)
                    .buttonStyle(.bare)
                    .frame(minHeight: metrics.actionHit)
                    .disabled(isEmpty)
                    .opacity(isEmpty ? 0.4 : 1)
            }
        }
        .defaultFocus($isNameFocused, true)
        .focusWhenReady($isNameFocused)
    }
}
