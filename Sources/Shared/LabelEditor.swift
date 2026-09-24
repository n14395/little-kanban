// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

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
        /// Which side of the `+` the picker hangs off, or `nil` to let the
        /// system place it — ``DueDateField/Metrics/arrowEdge`` exactly, and
        /// for the same measured reason it gives at length: a named edge is the
        /// only placement UIKit is permitted, and `.bottom` permits only "above
        /// the button". The Labels row sits low enough in the phone's editor
        /// that the panel was clamped into the space above it with the search
        /// field, the **New Label** button and the first labels cut off the top
        /// — while the whole lower half of the screen sat empty.
        var arrowEdge: Edge?

        static let desk = Metrics(
            chipSize: .compact, addFont: 11, addHorizontalPadding: 7, addVerticalPadding: 3,
            addRadius: 6, addBorderWidth: 1, spacing: 5, addHit: 0, picker: .desk,
            arrowEdge: .bottom
        )
        static let sheet = Metrics(
            chipSize: .comfortable, addFont: 13, addHorizontalPadding: 11, addVerticalPadding: 5,
            addRadius: 8, addBorderWidth: 1.5, spacing: 6, addHit: 44, picker: .sheet,
            arrowEdge: nil
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    #if os(iOS)
    /// Read here rather than inside the panel, for ``ColorWell/adaptation``'s
    /// reason: a presented popover's own environment describes the popover, not
    /// the screen it has to fit on. See ``LabelPickerList/standsItsGround``.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    let task: TaskItem
    let scope: DetailScope
    var metrics: Metrics = .desk

    /// Whether the panel may insist on its own height. Everywhere but a phone
    /// lying down, where 402pt of screen cannot hold it either side of the `+`.
    private var panelHasRoom: Bool {
        #if os(iOS)
        verticalSizeClass != .compact
        #else
        true
        #endif
    }

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
        .bareButton()
        .accessibilityLabel("Add label")
        .popover(isPresented: pickerBinding, arrowEdge: metrics.arrowEdge) {
            LabelPickerList(
                task: task, scope: scope, metrics: metrics.picker,
                standsItsGround: panelHasRoom
            )
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
        // **Wider and better inset than it was**, which is what the panel is
        // measured against its own siblings rather than against nothing: the
        // calendar's touch panel is 344 wide inside 12pt of padding and the
        // label manager's compose popover 230 inside 16, while this one was 250
        // inside *8* — the desk's inset plus one point. The compose form it
        // swaps to is a title, a field, a colour the width of the panel and two
        // verbs, and at that inset all four ran wall to wall with the popover's
        // own rounded corners a few points off them. Fourteen is the family's
        // middle, and the width grows with it so the extra inset comes out of
        // the screen rather than out of the content.
        static let sheet = Metrics(
            width: 300, maxListHeight: 320, rowVerticalPadding: 9, rowHorizontalPadding: 8,
            rowRadius: 10, rowHit: 44, chipSize: .comfortable, fieldFont: 14, fieldPadding: 10,
            fieldRadius: 11, panelPadding: 14, compose: .sheet
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    /// Which surface the picker belongs to, so the half-typed name in its
    /// compose form is kept apart from the other surface's.
    let scope: DetailScope
    var metrics: Metrics = .desk
    /// Whether the list refuses a height smaller than its rows — see
    /// ``rowsHeight``, which is the whole of why it would.
    ///
    /// **The caller decides, because only the caller can still see the screen**
    /// — `ColorWell.adaptation`'s reason: once presented, this view's own
    /// environment describes the popover rather than the screen the popover has
    /// to live on. The floor answers a popover that will not grow back, and it
    /// is the right answer wherever there is room for the panel at all. Where
    /// there is not — a phone lying down has about 180pt either side of the `+`
    /// and this panel is 361 with five labels in it — standing its ground means
    /// being laid out at full length inside a box that size and *clipped*, with the
    /// search field and **New Label** off the top. Yielding, the panel fits
    /// what it is given: the chrome above the list is fixed, so the list is what
    /// shrinks and the rows scroll inside what is left.
    ///
    /// Placement is the first half of the same answer — see
    /// ``LabelEditor/Metrics/arrowEdge``, which is what stops the panel being
    /// pinned to the short side of the `+` on a screen that has a long one.
    var standsItsGround = true

    @FocusState private var isSearchFocused: Bool

    /// What the search field has narrowed the list to. View state rather than
    /// a store draft — a filter is about what is on screen, and dismissing the
    /// popover is exactly when it should be forgotten.
    @State private var query = ""
    /// Whether the panel is showing the compose form instead of the list.
    @State private var isComposing = false
    /// What the rows come to, measured — the floor under the list, and the
    /// whole of why the popover can come back from the compose form.
    ///
    /// **A scroll view accepts any height it is offered**, which is what a
    /// scroll view is for and is exactly wrong for the one thing above it. The
    /// panel swaps itself for the compose form, which has a definite height and
    /// is shorter, so the popover shrinks to fit it — measured on macOS, 236pt
    /// down to 130pt. Cancel, and the list comes back into a 130pt popover,
    /// fits itself into it without complaint, and asks for nothing: the popover
    /// has no reason to grow and stays at the compose form's size for as long
    /// as it is open. The list's *ideal* height was right all along — 236 —
    /// but ideal is not what a popover that is already open reads.
    ///
    /// So the list states a floor. `minHeight` rather than an exact height
    /// because the first layout pass has nothing measured yet: a `frame(height:)`
    /// keyed on this would open the popover at nought and grow it, where a
    /// floor of nought is simply the flexible list the panel already was, sized
    /// correctly on the way in and pinned from the next pass onwards. Capped at
    /// `maxListHeight` so a long list still scrolls inside its 320pt.
    ///
    /// **A floor only where the screen has room for one** — see
    /// ``standsItsGround``, which is where the opposite constraint is written
    /// down.
    @State private var rowsHeight: CGFloat = 0
    /// What the compose form comes to, measured — ``rowsHeight``'s number for
    /// the other panel, and the floor under it for the same reason read the
    /// other way round. A vocabulary of one or two labels makes the list
    /// *shorter* than the form, and the popover, sized to the list and deaf to
    /// ideals once open, was not growing when the form swapped in: the form was
    /// laid out at full length inside the list's little box, **Cancel** and
    /// **Add** below the fold, and the one panel in the app whose whole job is
    /// a fixed four rows was scrolling them.
    @State private var formHeight: CGFloat = 0
    /// The colour picked in the form, or `nil` while it still shows the
    /// rotation's next — see `BoardStore.nextLabelColor`.
    @State private var chosenColor: SwatchColor?

    /// Read through the store so ticks update as labels are toggled.
    private var liveTask: TaskItem { store[task.id] ?? task }

    var body: some View {
        Group {
            if isComposing {
                // **The form is not given the height it asks for.** It is
                // shorter than the list it replaces and the popover follows it
                // down — measured on the phone, a 349pt panel to 202 — but it
                // lands a little short of the form's own 225, and what was
                // drawn outside the box was **Cancel** and **Add**, 21pt below
                // the panel's foot and reporting `hittable == false`: a form
                // that could be opened and neither committed nor cancelled.
                // A scroll view asks for exactly the same height and scrolls
                // whatever it is not given, which is `DueDateField.picker`'s
                // answer to the same arithmetic.
                //
                // And, like the list, it states its measured height as a floor
                // — see ``formHeight`` for the case that needs one: a list
                // shorter than the form, whose popover otherwise never grows.
                // The floor asks; the scroll keeps the few points the popover
                // undershoots by reachable rather than clipped.
                ScrollView {
                    composeForm
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { formHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(minHeight: standsItsGround ? min(formHeight, metrics.maxListHeight) : 0)
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
                // What the rows actually come to, which is the one number a
                // scroll view will not tell anybody. See ``rowsHeight``.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowsHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(minHeight: standsItsGround ? min(rowsHeight, metrics.maxListHeight) : 0,
                   maxHeight: metrics.maxListHeight)
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
        .bareButton()
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
        .bareButton()
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
        /// Between the four rows. Under a finger they are a 42pt field, a 44pt
        /// colour and a 44pt pair of verbs, and 8pt between them reads as one
        /// block of controls rather than four things — the same eight that
        /// separates a 22pt field from a 26pt well on the desk, where it is the
        /// right number.
        var spacing: CGFloat
        var colorWell: ColorWell.Metrics

        static let desk = Metrics(
            fieldFont: 12, fieldPadding: 8, fieldRadius: 9, actionHit: 0,
            spacing: 8, colorWell: .desk
        )
        static let sheet = Metrics(
            fieldFont: 14, fieldPadding: 10, fieldRadius: 11, actionHit: 44,
            spacing: 12, colorWell: .sheet
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
        VStack(alignment: .leading, spacing: metrics.spacing) {
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
                    .bareButton()
                    .frame(minHeight: metrics.actionHit)
                Spacer(minLength: 0)
                Button("Add") { onCommit() }
                    .font(palette.ui(metrics.fieldFont, .bold, relativeTo: .caption))
                    .foregroundStyle(palette.accent)
                    .bareButton()
                    .frame(minHeight: metrics.actionHit)
                    .disabled(isEmpty)
                    .opacity(isEmpty ? 0.4 : 1)
            }
        }
        .defaultFocus($isNameFocused, true)
        .focusWhenReady($isNameFocused)
    }
}
