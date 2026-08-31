import SwiftUI

/// The picker behind every ``SymbolWell``: a search field, a group to browse,
/// and a grid of glyphs.
///
/// **Choosing is one act.** Pressing a glyph takes it and closes, the way a
/// saved colour does in ``ColorPickerPopover`` — there is no draft here to
/// commit on the way out, because unlike a spectrum this control cannot be
/// dragged through a hundred choices nobody made. One press, one ⌘Z.
///
/// **It opens on a short list rather than on everything.** The catalogue is
/// seven thousand names in alphabetical order, so "everything" opens on
/// `0.circle` and the second screenful is still digits. A dozen or two marks the
/// thing being edited might plausibly want is a picker that answers most of the
/// time without a search, and All is one item away in the menu for the times it
/// does not. What that list *is* comes from the caller —
/// ``Board/startingSymbols`` for a board, ``SavedView/startingSymbols`` for a
/// view — because what a board is likely to want and what a view is are not the
/// same question.
///
/// **Typing searches the whole catalogue whatever is being browsed.** A person
/// who types "plane" while looking at the suggested few is asking the app for a
/// plane, not asking whether one of *these* is a plane; a search scoped to the
/// group in front of them would answer nothing and look broken. Picking a real
/// group *does* scope the search, because that is what picking one is for.
struct SymbolPickerPopover: View {
    struct Metrics {
        var width: CGFloat
        /// The grid's own height. A popover is handed a height rather than
        /// asked for one — see ``ColorPickerPopover`` — and a grid with no
        /// height of its own would ask for all seven thousand rows.
        var gridHeight: CGFloat
        var glyph: CGFloat
        /// The square each glyph is drawn in, which on touch is also its floor.
        var cell: CGFloat
        var font: CGFloat
        var hit: CGFloat
        var spacing: CGFloat

        static let desk = Metrics(
            width: 300, gridHeight: 240, glyph: 15, cell: 34, font: 12.5, hit: 28, spacing: 10
        )
        static let sheet = Metrics(
            width: 340, gridHeight: 300, glyph: 17, cell: 44, font: 14.5, hit: 44, spacing: 12
        )
    }

    /// What the grid is showing: the short list the caller starts from, the
    /// whole catalogue, or one of the system's own groups.
    enum Scope: Hashable {
        case suggested
        case all
        case category(SymbolCatalog.Category)

        var label: String {
            switch self {
            case .suggested: String(localized: "Suggested", comment: "The icon picker's opening group")
            case .all: String(localized: "All Icons", comment: "The icon picker's group holding every symbol")
            case .category(let category): category.label
            }
        }

        var symbol: String {
            switch self {
            case .suggested: "sparkles"
            case .all: "square.grid.2x2"
            case .category(let category): category.symbol
            }
        }
    }

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let selection: String
    var metrics: Metrics = .desk
    /// What the **Suggested** group holds — see the type's own note.
    var suggested: [String] = Board.startingSymbols
    /// Popover or sheet where iOS insists on adapting one of them — the well
    /// decides, because it can still see the screen. See ``SymbolWell/adaptation``.
    var adaptation: PresentationAdaptation = .popover
    let onSelect: (String) -> Void

    @State private var query = ""
    @State private var scope: Scope = .suggested
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            search
            groups
            grid
        }
        .padding(metrics.spacing)
        .frame(width: metrics.width)
        .background(palette.card)
        .presentationBackground(palette.card)
        #if os(iOS)
        // **The keyboard is the popover's business, not the panel's.** Tapping
        // the field raises it, UIKit shortens the popover to stand clear of it
        // — and SwiftUI then lifted the panel's *contents* by the same overlap
        // a second time, on top of a frame that had already moved. What went up
        // out of the top of the panel was the search field itself, so the
        // reader was left typing into a field they could no longer see, with
        // the grid where it had been. Nothing inside here is under the keyboard
        // by the time this is laid out; the container saw to that.
        .ignoresSafeArea(.keyboard)
        .presentationCompactAdaptation(adaptation)
        #endif
    }

    // MARK: Finding one

    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .symbolSize(metrics.font, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(palette.inkText(0.45))
                .accessibilityHidden(true)
            TextField(
                String(localized: "Search icons", comment: "Placeholder in the icon picker's search field"),
                text: $query
            )
            .textFieldStyle(.plain)
            .font(palette.ui(metrics.font, .semibold, relativeTo: .subheadline))
            .foregroundStyle(palette.ink)
            .focused($isSearchFocused)
            #if os(iOS)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            #endif
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolSize(metrics.font, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(palette.inkText(0.35))
                        .frame(minWidth: metrics.hit, minHeight: metrics.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.bare)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 9)
        .frame(minHeight: metrics.hit + 4)
        .fieldHitArea(minHeight: metrics.hit + 4) { isSearchFocused = true }
        .background(palette.ink(0.06), in: .rect(cornerRadius: 8))
    }

    /// The groups, as a menu rather than a row of chips: there are twenty-nine
    /// of them, and a row of twenty-nine anything does not fit in a control
    /// that is 300pt wide.
    private var groups: some View {
        Menu {
            Picker(selection: $scope) {
                Label(Scope.suggested.label, systemImage: Scope.suggested.symbol).tag(Scope.suggested)
                Label(Scope.all.label, systemImage: Scope.all.symbol).tag(Scope.all)
                Divider()
                ForEach(SymbolCatalog.Category.allCases) { category in
                    Label(category.label, systemImage: category.symbol).tag(Scope.category(category))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scope.symbol)
                    .symbolSize(metrics.font - 1, weight: .semibold, relativeTo: .caption)
                    .accessibilityHidden(true)
                Text(scope.label)
                    .font(palette.ui(metrics.font, .bold, relativeTo: .subheadline))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(palette.inkText(0.35))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(palette.ink(0.7))
            .padding(.horizontal, 9)
            .frame(minHeight: metrics.hit + 4)
            .background(palette.ink(0.06), in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .modifier(BorderlessMenu())
        .menuIndicator(.hidden)
        .accessibilityLabel("Icon group")
        .accessibilityValue(scope.label)
    }

    // MARK: The glyphs

    /// What the grid is drawing.
    ///
    /// A search from ``Scope/suggested`` widens to the whole catalogue — see
    /// the type's own note — and one from anywhere else stays where it is.
    private var shown: [SymbolCatalog.Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        switch scope {
        case .suggested where trimmed.isEmpty:
            return suggested.map { SymbolCatalog.Entry(name: $0, categories: [], terms: "") }
        case .suggested, .all:
            return SymbolCatalog.search(trimmed)
        case .category(let category):
            return SymbolCatalog.search(trimmed, in: category)
        }
    }

    @ViewBuilder private var grid: some View {
        let entries = shown
        ScrollView {
            if entries.isEmpty {
                Text("No icon matches that.", comment: "The icon picker with nothing to show")
                    .font(palette.ui(metrics.font, .medium, relativeTo: .subheadline))
                    .foregroundStyle(palette.inkText(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: metrics.cell), spacing: 4)], spacing: 4
                ) {
                    ForEach(entries) { entry in
                        glyphButton(entry.name)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // **An ideal rather than a height**, which is the difference between a
        // panel that fits and one that is cut. The ideal is what the popover
        // asks the panel for and so what it opens at; a definite proposal
        // smaller than that — the room above a keyboard, a short screen — is
        // taken instead, and the grid scrolls what it gives up. The two rows
        // above it are fixed, so the grid is the one thing here that can yield,
        // and the field and the group menu stay where the reader left them.
        //
        // A `height` made all three overflow together and the panel was drawn
        // at its full length inside whatever it had been handed, clipped at
        // both ends. See `LabelPickerList.standsItsGround` and
        // `DueDateField.picker`, which are the same arithmetic on the two
        // panels either side of this one.
        .frame(idealHeight: metrics.gridHeight, maxHeight: metrics.gridHeight)
    }

    private func glyphButton(_ name: String) -> some View {
        let isCurrent = name == selection
        return Button {
            onSelect(name)
            dismiss()
        } label: {
            Image(systemName: name)
                .symbolSize(metrics.glyph, weight: .medium, relativeTo: .body)
                .foregroundStyle(isCurrent ? palette.onAccent : palette.inkText(0.6))
                .frame(width: metrics.cell, height: metrics.cell)
                .background(
                    isCurrent ? palette.accent : palette.ink(0.05), in: .rect(cornerRadius: 8)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .help(name)
        // The symbol's own name, which is the only description there is — see
        // ``SymbolWell``. Every glyph in this grid draws on this system, so
        // there is no fallback to announce.
        .accessibilityLabel(name)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}
