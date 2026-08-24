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
        var colorWell: ColorWell.Metrics
        var swatchSpacing: CGFloat
        /// The square a swatch claims. Six of them share one row, so on touch
        /// the drawn circle is nowhere near the 44pt a finger needs.
        var swatchHit: CGFloat
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
            colorWell: .desk, swatchSpacing: 4,
            swatchHit: 26, glyph: 11, glyphHit: 26, fieldHit: 0
        )
        static let sheet = Metrics(
            width: nil, maxHeight: nil, titleFont: 15, nameFont: 15, chipSize: .comfortable,
            rowSpacing: 10, rowPadding: 14, rowRadius: 14, rowMinHeight: 44,
            listSpacing: 10, panelPadding: 16,
            colorWell: .sheet, swatchSpacing: 6,
            swatchHit: 44, glyph: 15, glyphHit: 44, fieldHit: 44
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
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.06), radius: 8)
        }
        .padding(.horizontal, metrics.panelPadding)
        .padding(.vertical, metrics.panelPadding * 0.7)
    }

    @ViewBuilder
    private var content: some View {
        if store.labels.isEmpty {
            Text("No labels yet. Add one from a task's Labels field.")
                .font(palette.ui(metrics.nameFont, .medium, relativeTo: .footnote))
                .foregroundStyle(palette.inkText(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(metrics.panelPadding)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.listSpacing) {
                    ForEach(store.labels) { label in
                        row(for: label)
                    }
                }
                .padding(metrics.panelPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row(for label: LabelDef) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
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

                deleteButton(for: label)
            }
            // The floor belongs to this line rather than to the row: the row is
            // this line plus the swatches and clears 44pt whatever happens, and
            // it is the name that has to be reachable by finger. The field's own
            // hit area is the 22pt of text it draws, so the rest of the line
            // hands focus over; the chip, the trash and the field keep theirs.
            .frame(minHeight: metrics.rowMinHeight)
            .contentShape(.rect)
            .onTapGesture { focusedKey = label.key }

            swatches(for: label)
        }
        .padding(metrics.rowPadding)
        .background(palette.card, in: .rect(cornerRadius: metrics.rowRadius))
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
        .buttonStyle(.bare)
        .hoverBackground(palette.ink(0.08), radius: 8)
        .accessibilityLabel("Delete label")
    }

    /// **The same colour control every other surface uses.** It was a row of
    /// ten hand-tuned swatches of its own, which is why a colour saved while
    /// recolouring a board could not be given to a label: the two lists had
    /// nothing to do with each other. Now both draw the board's palette, and
    /// the four colours a chip actually wears — a tinted ground and text on it,
    /// in each scheme — are derived from the one this returns. See
    /// `BoardStore.recolorLabel(_:to:)` and ``LabelTone/pair(from:)``.
    private func swatches(for label: LabelDef) -> some View {
        HStack(spacing: metrics.swatchSpacing) {
            ColorWell(selection: label.baseColor, metrics: metrics.colorWell) {
                store.recolorLabel(label.key, to: $0)
            }
            Spacer(minLength: 0)
        }
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
