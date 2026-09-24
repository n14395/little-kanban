import SwiftUI

/// The board's label vocabulary: rename in place, recolour from the board's
/// own palette, delete. A plain view so a Settings pane can host the same
/// body later; `View.labelManagerSheet(isPresented:metrics:)` is how the sidebar
/// and the drawer put it on screen today.
struct LabelManagerView: View {
    struct Metrics {
        /// A panel on the desk, the whole sheet on a phone — hence optional.
        var width: CGFloat?
        var maxHeight: CGFloat?
        var titleFont: CGFloat
        var nameFont: CGFloat
        var chipSize: LabelChip.Size
        var rowSpacing: CGFloat
        var rowPadding: CGFloat
        var rowRadius: CGFloat
        var rowMinHeight: CGFloat
        var listSpacing: CGFloat
        var panelPadding: CGFloat
        /// The colour well shares the row, so its own height is the touch
        /// answer — 44pt in the sheet metrics, see `ColorWell.Metrics.sheet`.
        var colorWell: ColorWell.Metrics
        /// The create popover's form — the same one the task picker shows.
        var compose: LabelComposeForm.Metrics
        /// Which side of the **Create new label** row the form hangs off, or
        /// `nil` to let the system place it — ``LabelEditor/Metrics/arrowEdge``
        /// and ``DueDateField/Metrics/arrowEdge``, which says why at length.
        /// The row heads the list, so on a phone there is nothing above it to
        /// hang a form in: named, the edge was the only placement UIKit was
        /// permitted, and it was the wrong one.
        var arrowEdge: Edge?
        var glyph: CGFloat
        var glyphHit: CGFloat
        /// The floor the rename field claims for itself. `rowMinHeight` is the
        /// line's, and a field does not inherit it: the element a `TextField`
        /// publishes is the text it draws — measured at 124.7×22.3 inside this
        /// 44pt row — so the claim has to be made on the field and the shape
        /// named, exactly as `ChecklistView.Metrics.fieldHit` does. No overhang
        /// to give back here: the line already stands 44pt tall around it.
        var fieldHit: CGFloat

        static let desk = Metrics(
            width: 396, maxHeight: 520, titleFont: 13, nameFont: 12.5, chipSize: .compact,
            rowSpacing: 8, rowPadding: 10, rowRadius: 12, rowMinHeight: 0,
            listSpacing: 8, panelPadding: 14,
            colorWell: .desk, compose: .desk, arrowEdge: .bottom,
            glyph: 11, glyphHit: 26, fieldHit: 0
        )
        static let sheet = Metrics(
            width: nil, maxHeight: nil, titleFont: 15, nameFont: 15, chipSize: .comfortable,
            rowSpacing: 10, rowPadding: 14, rowRadius: 14, rowMinHeight: 44,
            listSpacing: 10, panelPadding: 16,
            colorWell: .sheet, compose: .sheet, arrowEdge: nil,
            glyph: 15, glyphHit: 44, fieldHit: 44
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store

    var metrics: Metrics = .desk

    /// The row being renamed, and what it says so far. The store refuses an
    /// empty name, so the field cannot be bound straight through it — backspacing
    /// to nothing would snap the old name back under the cursor.
    @FocusState private var focusedKey: String?
    @State private var draft: String = ""
    @State private var draftKey: String?

    /// The create popover and what has been typed and picked into it. Local
    /// state, not a store draft: the manager edits the vocabulary, not a task,
    /// and dismissing the popover is when a half-made label should be dropped.
    @State private var isComposing = false
    @State private var composeName = ""
    @State private var composeColor: SwatchColor?

    /// The row a dragged label would land in front of — where the insertion
    /// line is drawn.
    @State private var dropTargetKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.hairline(.bottom, color: palette.ink(0.08))
            content
        }
        .frame(width: metrics.width)
        .frame(maxHeight: metrics.maxHeight)
        .background(palette.windowFill)
        .presentationBackground(palette.windowFill)
        .onChange(of: focusedKey) { previous, current in
            if previous != nil { commitRename() }
            if let current {
                draft = store.label(forKey: current)?.name ?? ""
                draftKey = current
            }
        }
        .onDisappear { commitRename() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Labels")
                .font(palette.ui(metrics.titleFont, .bold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
            CountPill(count: store.labels.count)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Done")
                    .font(palette.ui(metrics.nameFont, .bold, relativeTo: .footnote))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 8)
                    .frame(minHeight: metrics.glyphHit)
            }
            .bareButton()
            .hoverBackground(palette.ink(0.06), radius: 8)
        }
        .padding(.horizontal, metrics.panelPadding)
        .padding(.vertical, metrics.panelPadding * 0.7)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.listSpacing) {
                createRow
                if store.labels.isEmpty {
                    Text("No labels yet. Create one here, or from a task's Labels field.")
                        .font(palette.ui(metrics.nameFont, .medium, relativeTo: .footnote))
                        .foregroundStyle(palette.inkText(0.45))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(store.labels) { label in
                        row(for: label)
                    }
                }
            }
            .padding(metrics.panelPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Ahead of the rows, the way the picker leads with its **New Label** —
    /// and it hangs the same form off itself. The difference is what a commit
    /// means: here the definition joins the vocabulary and lands on no task.
    private var createRow: some View {
        Button { isComposing = true } label: {
            HStack(spacing: metrics.rowSpacing) {
                Image(systemName: "plus")
                    .symbolSize(metrics.nameFont, weight: .heavy, relativeTo: .footnote)
                    .foregroundStyle(palette.accent)
                Text("Create new label")
                    .font(palette.ui(metrics.nameFont, .bold, relativeTo: .footnote))
                    .foregroundStyle(palette.accent)
                Spacer(minLength: 0)
            }
            .frame(minHeight: metrics.rowMinHeight)
            .padding(.horizontal, metrics.rowPadding)
            .padding(.vertical, metrics.rowMinHeight > 0 ? 0 : metrics.rowPadding * 0.7)
            .contentShape(.rect)
        }
        .bareButton()
        .hoverBackground(palette.ink(0.06), radius: metrics.rowRadius)
        .popover(isPresented: $isComposing, arrowEdge: metrics.arrowEdge) {
            LabelComposeForm(
                name: $composeName,
                chosenColor: $composeColor,
                defaultColor: store.nextLabelColor,
                metrics: metrics.compose,
                onCancel: { endComposing() },
                onCommit: {
                    store.createLabel(named: composeName, color: composeColor ?? store.nextLabelColor)
                    endComposing()
                }
            )
            .padding(metrics.rowPadding)
            .frame(width: 230)
            .background(palette.card)
            .presentationBackground(palette.card)
            .presentationCompactAdaptation(.popover)
            .environment(store)
            .environment(\.palette, palette)
        }
    }

    private func endComposing() {
        composeName = ""
        composeColor = nil
        isComposing = false
    }

    private func row(for label: LabelDef) -> some View {
        HStack(spacing: metrics.rowSpacing) {
            LabelChip(label: label, size: metrics.chipSize)

            TextField("Label name", text: nameBinding(for: label))
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.nameFont, .bold, relativeTo: .footnote))
                .foregroundStyle(palette.ink)
                .focused($focusedKey, equals: label.key)
                .onSubmit { focusedKey = nil }
                .onKeyPress(.escape) {
                    cancelRename()
                    focusedKey = nil
                    return .handled
                }
                .frame(maxWidth: .infinity, minHeight: metrics.fieldHit, alignment: .leading)
                .contentShape(.accessibility, Rectangle())
                // A field holding text announces no placeholder, and this
                // one is the only control on the sheet VoiceOver would
                // otherwise reach unnamed.
                .accessibilityLabel("Label name")

            CountPill(count: usageCount(of: label))
                .accessibilityLabel("On \(usageCount(of: label)) tasks")

            // **The same colour control every other surface uses** — see
            // `BoardStore.recolorLabel(_:to:)` and ``LabelTone/pair(from:)``:
            // both draw the board's palette, and the four colours a chip
            // actually wears are derived from the one this returns. On the
            // row rather than on a line of its own, sized to its words rather
            // than stretched — the chip beside it already says what the
            // colour is for, which is also why the title is the short one.
            ColorWell(selection: label.baseColor, metrics: metrics.colorWell,
                      title: String(localized: "Colour", comment: "The label manager's colour button")) {
                store.recolorLabel(label.key, to: $0)
            }
            .fixedSize(horizontal: true, vertical: false)

            deleteButton(for: label)
        }
        // The floor belongs to the line, and it is the name that has to be
        // reachable by finger. The field's own hit area is the 22pt of text it
        // draws, so the rest of the line hands focus over; the chip, the
        // colour well, the trash and the field keep theirs.
        .frame(minHeight: metrics.rowMinHeight)
        .contentShape(.rect)
        .onTapGesture { focusedKey = label.key }
        .padding(metrics.rowPadding)
        .background(palette.card, in: .rect(cornerRadius: metrics.rowRadius))
        // The insertion line, drawn where the row would land.
        .overlay(alignment: .top) {
            if dropTargetKey == label.key {
                Capsule().fill(palette.accent).frame(height: 2)
            }
        }
        // The whole row is the grip, `ChecklistView`'s bargain: a drag begun
        // inside the name field is the field's — that is how text selection
        // works — so the chip, the count, the padding and the gutter are what
        // start a reorder. The well and the trash sit in front and keep their
        // own clicks.
        .draggable(LabelTransfer(label))
        .dropDestination(for: LabelTransfer.self) { items, _ in
            drop(items.first, before: label)
        } isTargeted: { isTargeted in
            dropTargetKey = isTargeted ? label.key : (dropTargetKey == label.key ? nil : dropTargetKey)
        }
        // The drag's answer said in words, and the only route VoiceOver and
        // Switch Control have to it — a long-press lift is unreachable to
        // both. Through `moveLabel` and `dropOffset`, exactly as the drop is,
        // so the menu and the drag cannot have two ideas of where a row lands.
        .contextMenu {
            reorderItems(for: label)
        }
    }

    @ViewBuilder
    private func reorderItems(for label: LabelDef) -> some View {
        if let index = store.labels.firstIndex(where: { $0.key == label.key }) {
            if index > 0 {
                Button {
                    move(from: index, to: index - 1)
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
            }
            if index + 1 < store.labels.count {
                Button {
                    move(from: index, to: index + 1)
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
            }
        }
    }

    private func move(from: Int, to: Int) {
        store.moveLabel(
            fromOffsets: IndexSet(integer: from),
            toOffset: BoardStore.dropOffset(from: from, to: to)
        )
    }

    /// Moves the dragged row to where `target` sits. A payload for a key the
    /// board no longer has is refused rather than guessed at.
    private func drop(_ payload: LabelTransfer?, before target: LabelDef) -> Bool {
        guard let payload,
              let from = store.labels.firstIndex(where: { $0.key == payload.key }),
              let to = store.labels.firstIndex(where: { $0.key == target.key }),
              from != to
        else { return false }
        move(from: from, to: to)
        return true
    }

    private func deleteButton(for label: LabelDef) -> some View {
        Button {
            // The row is going away; a half-typed name for it goes too, rather
            // than landing as a rename immediately before the delete.
            if focusedKey == label.key { cancelRename() }
            store.deleteLabel(label.key)
        } label: {
            Image(systemName: "trash")
                .font(palette.ui(metrics.glyph, .bold, relativeTo: .footnote))
                .fontWeight(.semibold)
                .foregroundStyle(palette.inkText(0.4))
                .frame(minWidth: metrics.glyphHit, minHeight: metrics.glyphHit)
        }
        .bareButton()
        .hoverBackground(palette.ink(0.08), radius: 8)
        .accessibilityLabel("Delete label")
    }

    private func usageCount(of label: LabelDef) -> Int {
        store.tasks.count { $0.labelKeys.contains(label.key) }
    }

    /// The stored name is looked up rather than read off `label`: the binding the
    /// field is holding when the draft is dropped is the one built for the row's
    /// value *before* the rename, and its snapshot would put the old name back
    /// under the cursor until something unrelated invalidated the row.
    private func nameBinding(for label: LabelDef) -> Binding<String> {
        Binding(
            get: {
                draftKey == label.key
                    ? draft
                    : store.label(forKey: label.key)?.name ?? label.name
            },
            set: {
                draft = $0
                draftKey = label.key
            }
        )
    }

    /// The rename lands when the field gives up focus, so a name typed a letter
    /// at a time is one activity-free store mutation and one ⌘Z — the same
    /// bargain the task fields make. An empty name is refused by the store and
    /// the field falls back to what is stored.
    private func commitRename() {
        guard let key = draftKey else { return }
        store.renameLabel(key, to: draft)
        cancelRename()
    }

    private func cancelRename() {
        draftKey = nil
        draft = ""
    }
}

extension View {
    /// Presents the board's label manager as a sheet.
    func labelManagerSheet(
        isPresented: Binding<Bool>,
        metrics: LabelManagerView.Metrics = .desk
    ) -> some View {
        modifier(LabelManagerSheet(isPresented: isPresented, metrics: metrics))
    }
}

/// Carries the palette and the store across the presentation, which is its own
/// window on macOS.
private struct LabelManagerSheet: ViewModifier {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    @Binding var isPresented: Bool
    let metrics: LabelManagerView.Metrics

    func body(content: Content) -> some View {
        content
            // 7.1's reported defect, half of which reproduces: with the sheet
            // up, `New task` behind it still reported `hittable=true`, so a
            // reader could walk into a surface the modal has taken the pointer
            // away from. The sheet itself is fine — measured on macOS 26 it is
            // a real `AXSheet`, a child of the window, with all 55 of its
            // elements under it — so the fix is on this side of the seam.
            .accessibilityHidden(isPresented)
            .sheet(isPresented: $isPresented) {
                LabelManagerView(metrics: metrics)
                    .environment(store)
                    .environment(\.palette, palette)
                    .tint(palette.accent)
                    .accessibilityAddTraits(.isModal)
            }
    }
}
