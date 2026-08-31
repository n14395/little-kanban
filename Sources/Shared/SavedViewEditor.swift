import SwiftUI

/// Which view the editor sheet is open on.
///
/// A one-field box because `sheet(item:)` wants something `Identifiable` and a
/// bare `UUID` conforming to it would make every id in the app a sheet trigger.
/// The arrangement `BoardSidebar.Capture` already has.
struct SavedViewDraft: Identifiable, Hashable {
    let id: SavedView.ID
    init(_ view: SavedView) { id = view.id }
    init(id: SavedView.ID) { self.id = id }
}

/// Building a view: a name, an icon, a rule, an order and a cap.
///
/// **The rule is the whole of it, and it is a tree.** Criteria join under a
/// group that says *all* or *any*, and a row can itself be a group — which is
/// what lets `due ≤ today AND (High or BUG)` be written down and told apart
/// from `(due ≤ today AND High) or BUG`. A flat list carrying an operator per
/// row cannot: it has to pick a precedence, and then the rule reads one way and
/// means another. See ``ViewRule``.
///
/// **The draft is local and commits on the way out.** Every other editor in the
/// app writes through — a column's name, a board's colour — because each of
/// those is one field and one ⌘Z. A view is five things at once, and somebody
/// who opens the editor, moves three criteria around and changes their mind
/// wants *one* undo, not eleven. `BoardStore.updateView` takes the finished
/// view; `onDisappear` is what hands it over, so closing the sheet any way at
/// all is a commit — the bargain `BoardColumnEditor` makes.
///
/// The count under the name is computed from the **draft**, not from the stored
/// view, so a criterion narrowing the list to nothing says so while there is
/// still something on screen to undo it with.
struct SavedViewEditor: View {
    /// Sizes at a pointer and under a finger.
    struct Metrics {
        /// What the panel is, or `nil` for *whatever it has been given*.
        ///
        /// **A window and a sheet want opposite things.** On the desk this is a
        /// panel of its own and 520×620 is its size; under a finger it is a
        /// sheet, and a sheet that is not the size of the sheet is a card
        /// floating in a band of the presentation's own ground at each end —
        /// which is what the phone drew, 620pt of editor centred in 874pt of
        /// screen, with the last criterion clipped and nowhere to scroll it.
        var width: CGFloat?
        var height: CGFloat?
        var fieldHeight: CGFloat
        var rowSpacing: CGFloat
        var sectionSpacing: CGFloat
        var padding: CGFloat
        var radius: CGFloat
        /// What a control claims for touch, over and above what it draws.
        var hit: CGFloat
        /// The view's icon control, which is the board's — see ``SymbolWell``.
        var symbolWell: SymbolWell.Metrics

        static let desk = Metrics(
            width: 520, height: 620, fieldHeight: 26, rowSpacing: 8, sectionSpacing: 18,
            padding: 20, radius: 10, hit: 0, symbolWell: .desk
        )
        static let sheet = Metrics(
            width: nil, height: nil, fieldHeight: 40, rowSpacing: 10, sectionSpacing: 22,
            padding: 20, radius: 12, hit: 44, symbolWell: .sheet
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(\.dismiss) private var dismiss
    @Environment(BoardStore.self) private var store

    let viewID: SavedView.ID
    var metrics: Metrics = .desk

    @State private var draft: SavedView?
    @FocusState private var isNameFocused: Bool
    private var chrome = ChromeScale()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.ink(0.08))
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    identity
                    matching
                    ordering
                }
                .padding(metrics.padding)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: chrome.scaling(metrics.width, cap: 1.35))
        // Nothing to fill on the desk, where the two numbers above are the
        // panel; everything to fill in a sheet, where the room is the room the
        // presentation gave it. `.infinity` in both directions is what makes
        // the ground below reach the sheet's own edges rather than stopping at
        // the content and letting the presentation's white through.
        .frame(
            maxWidth: metrics.width == nil ? .infinity : nil,
            maxHeight: chrome.scaling(metrics.height, cap: 1.35) ?? .infinity
        )
        .background(palette.windowFill)
        .onAppear { draft = store.view(id: viewID) }
        // Every way out is the same way out — Done, Escape, the sheet's own
        // grabber — so the commit hangs off the disappearance rather than off
        // the button.
        .onDisappear { commit() }
    }

    // MARK: The bar

    private var header: some View {
        HStack(spacing: 12) {
            Text("Edit View")
                .font(palette.ui(15, .extraBold, relativeTo: .headline))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 0)
            // What the rule currently gathers, live. The one number that says
            // whether the thing being written works.
            if let draft {
                Text(matchCount(draft))
                    .font(palette.ui(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.5))
                    .monospacedDigit()
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, metrics.padding)
        .frame(minHeight: 52)
    }

    private func matchCount(_ view: SavedView) -> String {
        let count = store.count(of: view, today: dayClock.today)
        return String(
            localized: "\(count) matching",
            comment: "How many tasks a view being edited currently gathers"
        )
    }

    // MARK: Name and glyph

    @ViewBuilder private var identity: some View {
        if let draft {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").sectionLabelStyle(size: 10, opacity: Palette.readableInk)
                TextField(
                    String(localized: "View name", comment: "Placeholder for a saved view's name"),
                    text: Binding(get: { draft.name }, set: { edit { $0.name = $1 } ($0) })
                )
                .textFieldStyle(.plain)
                .font(palette.ui(14, .semibold, relativeTo: .body))
                .foregroundStyle(palette.ink)
                .focused($isNameFocused)
                .padding(.horizontal, 10)
                .frame(minHeight: chrome(metrics.fieldHeight))
                .fieldHitArea(minHeight: metrics.hit) { isNameFocused = true }
                .background(palette.ink(0.06), in: .rect(cornerRadius: 8))
            }

            // **The same control Board Settings uses**, and the same reasoning
            // one step on: this was a row of eighteen fixed swatches, which
            // could only ever offer what was written into the source and cost a
            // block of 44pt targets to say so. A well opens the whole of
            // ``SymbolCatalog`` behind one target, and still leads with the
            // eighteen — see ``SavedView/startingSymbols``.
            //
            // It writes to the **draft** rather than to the store, unlike the
            // board's, because everything in this editor does: a view is five
            // things at once and closing the sheet is the one commit.
            VStack(alignment: .leading, spacing: 6) {
                Text("Icon").sectionLabelStyle(size: 10, opacity: Palette.readableInk)
                SymbolWell(
                    selection: draft.symbol,
                    metrics: metrics.symbolWell,
                    suggested: SavedView.startingSymbols,
                    fallback: SavedView.defaultSymbol
                ) { picked in
                    change { $0.symbol = picked }
                }
            }
        }
    }

    // MARK: The rule

    @ViewBuilder private var matching: some View {
        if let draft {
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                Text("Criteria").sectionLabelStyle(size: 10, opacity: Palette.readableInk)
                RuleGroupView(
                    rule: draft.rule,
                    depth: 0,
                    metrics: metrics,
                    change: { transform in change { $0.rule = transform($0.rule) } }
                )
            }
        }
    }

    // MARK: Order and cap

    @ViewBuilder private var ordering: some View {
        if let draft {
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                Text("Order").sectionLabelStyle(size: 10, opacity: Palette.readableInk)
                Picker(selection: Binding(
                    get: { draft.sort }, set: { next in change { $0.sort = next } }
                )) {
                    ForEach(ViewSort.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text("Order", comment: "Accessibility label of the picker choosing a saved view's card order")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minHeight: metrics.hit == 0 ? metrics.fieldHeight : metrics.hit)

                Toggle(isOn: Binding(
                    get: { draft.limit != nil },
                    // 20 is *Recently updated*'s cap, which is the only one the
                    // app has ever had and a sensible thing to land on.
                    set: { on in change { $0.limit = on ? ($0.limit ?? 20) : nil } }
                )) {
                    Text("Show only the first few")
                        .font(palette.ui(13, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(palette.ink(0.7))
                }
                .toggleStyle(.switch)

                if let limit = draft.limit {
                    Stepper(
                        value: Binding(get: { limit }, set: { next in change { $0.limit = max(1, next) } }),
                        in: 1...200
                    ) {
                        Text(String(localized: "At most \(limit)",
                                    comment: "How many cards a view shows at most"))
                            .font(palette.ui(13, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(palette.ink(0.7))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: Editing the draft

    /// Mutates the draft in place. Nothing reaches the store until ``commit()``.
    private func change(_ transform: (inout SavedView) -> Void) {
        guard var next = draft else { return }
        transform(&next)
        draft = next
    }

    /// The shape a `TextField`'s setter wants: a function of the draft and the
    /// new value. Spelled once so the binding above reads as a binding.
    private func edit(_ apply: @escaping (inout SavedView, String) -> Void) -> (String) -> Void {
        { value in change { apply(&$0, value) } }
    }

    private func commit() {
        guard let draft else { return }
        store.updateView(draft)
    }
}

/// One group of the rule tree, and its rows.
///
/// Recursive, with `depth` as the only brake: the model nests to any depth and
/// the editor offers **Add group** for one level, because two brackets inside a
/// 520pt sheet is a rule nobody can read back. A file that carries a deeper tree
/// still evaluates and still draws — the button to make another one is simply
/// not offered past the cap.
private struct RuleGroupView: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let rule: ViewRule
    let depth: Int
    let metrics: SavedViewEditor.Metrics
    /// A transform on the *whole* rule, handed down so a nested group can
    /// rewrite the tree it sits in without knowing its own path — see
    /// ``ViewRule/replacing(_:with:)``.
    let change: (@escaping (ViewRule) -> ViewRule) -> Void

    private static let maxDepth = 1

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            joinerRow
            ForEach(rule.children) { child in
                if child.criterion != nil {
                    CriterionRow(rule: child, metrics: metrics, change: change)
                } else {
                    RuleGroupView(rule: child, depth: depth + 1, metrics: metrics, change: change)
                }
            }
            addRow
        }
        .padding(depth > 0 ? 10 : 0)
        .background(
            depth > 0 ? palette.ink(0.04) : .clear,
            in: .rect(cornerRadius: metrics.radius)
        )
    }

    private var joinerRow: some View {
        HStack(spacing: 8) {
            Text(depth == 0 ? "Match" : "and")
                .font(palette.ui(13, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink(0.7))
            Picker(selection: Binding(
                get: { rule.joiner ?? .all },
                set: { next in
                    change { tree in
                        tree.replacing(rule.id) { found in
                            ViewRule(id: found.id, kind: .group(next, found.children))
                        } ?? tree
                    }
                }
            )) {
                ForEach(ViewRule.Joiner.allCases) { Text($0.label).tag($0) }
            } label: {
                // Self-contained rather than the row's own "Match" / "and",
                // which is a `Text` of its own and reads out separately — and
                // which is not the same word at every depth.
                Text("Match all or any",
                     comment: "Accessibility label of the picker joining a view's criteria")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            Text("of the following")
                .font(palette.ui(13, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink(0.7))
            Spacer(minLength: 0)
            if depth > 0 {
                removeButton { tree in tree.replacing(rule.id) { _ in nil } ?? tree }
            }
        }
        .frame(minHeight: metrics.hit)
    }

    private var addRow: some View {
        HStack(spacing: 14) {
            Button {
                change { tree in tree.appending(.criterion(ViewCriterion()), to: rule.id) }
            } label: {
                Label("Add criterion", systemImage: "plus")
                    .font(palette.ui(12.5, .semibold, relativeTo: .caption))
            }
            .buttonStyle(.bare)
            .foregroundStyle(palette.accent)

            if depth < Self.maxDepth {
                Button {
                    change { tree in
                        // A new bracket starts as **any**: a nested group that
                        // matched *all* would say exactly what the group around
                        // it already says, so the only reason to open one is to
                        // change the operator.
                        tree.appending(.group(.any, [.criterion(ViewCriterion())]), to: rule.id)
                    }
                } label: {
                    Label("Add group", systemImage: "plus.rectangle.on.rectangle")
                        .font(palette.ui(12.5, .semibold, relativeTo: .caption))
                }
                .buttonStyle(.bare)
                .foregroundStyle(palette.accent)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: metrics.hit)
    }

    private func removeButton(_ transform: @escaping (ViewRule) -> ViewRule) -> some View {
        Button { change(transform) } label: {
            Image(systemName: "minus.circle")
                .symbolSize(14, weight: .medium, relativeTo: .body)
                .foregroundStyle(palette.inkText(0.45))
                .frame(minWidth: metrics.hit, minHeight: metrics.hit)
                .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .accessibilityLabel(String(localized: "Remove",
                                   comment: "Accessibility name of the button removing a view criterion"))
    }
}

/// One leaf: field, comparator, and whichever value control the pair calls for.
private struct CriterionRow: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let rule: ViewRule
    let metrics: SavedViewEditor.Metrics
    let change: (@escaping (ViewRule) -> ViewRule) -> Void

    private var criterion: ViewCriterion { rule.criterion ?? ViewCriterion() }

    var body: some View {
        HStack(spacing: 6) {
            Picker(selection: Binding(
                get: { criterion.field },
                set: { next in write { $0.field(next) } }
            )) {
                ForEach(ViewField.allCases) { Text($0.label).tag($0) }
            } label: {
                Text("Field", comment: "Accessibility label of the picker choosing what a view criterion tests")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Picker(selection: Binding(
                get: { criterion.comparator },
                set: { next in write { $0.comparator(next) } }
            )) {
                ForEach(criterion.field.comparators) { Text($0.label).tag($0) }
            } label: {
                Text("Condition", comment: "Accessibility label of the picker choosing how a view criterion tests its field")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            value
            Spacer(minLength: 0)

            Button { change { tree in tree.replacing(rule.id) { _ in nil } ?? tree } } label: {
                Image(systemName: "minus.circle")
                    .symbolSize(14, weight: .medium, relativeTo: .body)
                    .foregroundStyle(palette.inkText(0.45))
                    .frame(minWidth: metrics.hit, minHeight: metrics.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)
            .accessibilityLabel(String(localized: "Remove",
                                       comment: "Accessibility name of the button removing a view criterion"))
        }
        .frame(minHeight: metrics.hit)
    }

    @ViewBuilder private var value: some View {
        switch criterion.valueKind {
        case .none:
            EmptyView()
        case .days:
            HStack(spacing: 4) {
                TextField(value: Binding(
                    get: { criterion.value.days ?? 0 },
                    set: { next in write { $0.value(.days(next)) } }
                ), format: .number) {
                    Text("Days", comment: "Accessibility label of the number of days in a view criterion")
                }
                .labelsHidden()
                .textFieldStyle(.plain)
                .frame(width: 44)
                .padding(.horizontal, 6)
                .frame(minHeight: metrics.fieldHeight)
                .background(palette.ink(0.06), in: .rect(cornerRadius: 6))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                Text("days")
                    .font(palette.ui(12.5, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.inkText(0.5))
            }
        case .priority:
            Picker(selection: Binding(
                get: { criterion.value.priority ?? .high },
                set: { next in write { $0.value(.priority(next)) } }
            )) {
                ForEach(Priority.leastFirst) { Text($0.displayName).tag($0) }
            } label: {
                Text("Priority", comment: "Accessibility label of the priority a view criterion compares against")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        case .board:
            idPicker(
                store.boards.map { ($0.id.uuidString, $0.name) },
                label: Text("Board", comment: "Accessibility label of the board a view criterion names")
            )
        case .column:
            idPicker(
                store.boards.flatMap { board in
                    board.columns.map { ($0.id.uuidString, "\(board.name) ▸ \($0.name)") }
                },
                label: Text("Column", comment: "Accessibility label of the column a view criterion names")
            )
        case .label:
            idPicker(
                store.labels.map { ($0.key, $0.key) },
                label: Text("Label", comment: "Accessibility label of the label a view criterion names")
            )
        case .text:
            TextField(
                String(localized: "text", comment: "Placeholder for a view criterion's text value"),
                text: Binding(
                    get: { criterion.value.text ?? "" },
                    set: { next in write { $0.value(.text(next)) } }
                )
            )
            .textFieldStyle(.plain)
            .frame(minWidth: 90)
            .padding(.horizontal, 8)
            .frame(minHeight: metrics.fieldHeight)
            .background(palette.ink(0.06), in: .rect(cornerRadius: 6))
        }
    }

    /// A picker over things named by a string — a board, a column, a label.
    ///
    /// Carries an explicit empty tag so a criterion pointing at something since
    /// deleted still has a selection to show: without it the picker draws blank
    /// and the first change silently re-points the rule at whatever happened to
    /// be first.
    ///
    /// The label is the caller's because the three uses are three different
    /// words, and the control draws none of them: a shared "Item" would name
    /// every one of them wrongly, which is barely better than naming none.
    private func idPicker(_ options: [(String, String)], label: Text) -> some View {
        Picker(selection: Binding(
            get: { criterion.value.text ?? "" },
            set: { next in write { $0.value(.text(next)) } }
        )) {
            Text("—").tag("")
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        } label: {
            label
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }

    private func write(_ transform: @escaping (inout ViewCriterion) -> Void) {
        change { tree in
            tree.replacing(rule.id) { found in
                guard var edited = found.criterion else { return found }
                transform(&edited)
                return ViewRule(id: found.id, kind: .criterion(edited))
            } ?? tree
        }
    }
}
