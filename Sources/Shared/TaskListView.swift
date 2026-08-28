import SwiftUI

/// Sizes for ``TaskListView``.
///
/// Free-standing rather than nested, which is the one place this file departs
/// from the `Metrics` convention: the view is generic over the card it draws,
/// so a nested type could only be spelled `TaskListView<SomeCard>.Metrics` and
/// nothing outside the view — a caller, a test — could name it. `metrics:` is
/// still written `.desk` / `.sheet` at every call site, which is the part that
/// mattered.
struct TaskListMetrics {
    /// The gap between two cards. Spent as half above and half below each row:
    /// `listRowSpacing` is iOS-only, and a row inset is the one lever both
    /// platforms have.
    var rowSpacing: CGFloat
    /// The margin either side of a card. On the phone this is the design's 20pt
    /// list inset; on the desk it is the gutter the board would have had.
    var horizontalPadding: CGFloat
    /// How wide a row is allowed to grow. A flat list stretched across a 1400pt
    /// window draws cards a metre wide with eight words on them, so the desk
    /// caps the row and centres it; a phone has no width to give away.
    var maxRowWidth: CGFloat
    var topInset: CGFloat
    /// Room under the last card. The phone's floating tab bar sits over it.
    var bottomInset: CGFloat

    static let desk = TaskListMetrics(
        rowSpacing: 8, horizontalPadding: 16, maxRowWidth: 620, topInset: 12, bottomInset: 16
    )
    static let sheet = TaskListMetrics(
        rowSpacing: 10, horizontalPadding: 20, maxRowWidth: .infinity, topInset: 2, bottomInset: 130
    )
    /// The Inbox panel, which is a column's width. No cap, because the panel
    /// *is* the cap — and the gutter and the gap between cards are a column's
    /// own, so a card in the panel sits on the same grid as a card beside it.
    static let panel = TaskListMetrics(
        rowSpacing: BoardColumnView.Metrics.desk.cardSpacing,
        horizontalPadding: BoardColumnView.Metrics.desk.horizontalPadding,
        maxRowWidth: .infinity, topInset: 10, bottomInset: 12
    )
    static let panelPad = TaskListMetrics(
        rowSpacing: BoardColumnView.Metrics.pad.cardSpacing,
        horizontalPadding: BoardColumnView.Metrics.pad.horizontalPadding,
        maxRowWidth: .infinity, topInset: 12, bottomInset: 16
    )
}

/// A flat list of tasks drawn from anywhere on the board.
///
/// A saved view, the phone's Search tab and the phone's Inbox tab are the same
/// surface with different contents, so they are one view: three copies of
/// "cards from anywhere on the board" would drift apart inside a phase.
///
/// A `List` rather than a `LazyVStack`, on both platforms. It was chosen for
/// `swipeActions` — a hand-rolled swipe fights the scroll view for the gesture,
/// re-implements the full-swipe threshold, and is invisible to VoiceOver — and
/// **that reason expired in 6.4, when the phone's cards stopped swiping at
/// all**. It is kept rather than re-chosen: the two are not interchangeable, and
/// the difference runs the wrong way for a swap made on tidiness alone. A `List`
/// handles drags inside its own bounds, which is why `InboxPanel` and the
/// board's columns are stacks — so moving *to* a stack here would be a change to
/// what a drop on these surfaces does, measured, and not a deletion.
struct TaskListView<Card: View, Trailing: View>: View {
    typealias Metrics = TaskListMetrics

    let tasks: [TaskItem]
    var metrics: Metrics = .desk
    private let card: (TaskItem) -> Card
    private let trailing: () -> Trailing

    init(
        tasks: [TaskItem],
        metrics: Metrics = .desk,
        @ViewBuilder card: @escaping (TaskItem) -> Card,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.tasks = tasks
        self.metrics = metrics
        self.card = card
        self.trailing = trailing
    }

    var body: some View {
        List {
            ForEach(tasks) { task in
                card(task).modifier(TaskListRow(metrics: metrics))
            }
            // Rows of the caller's own after the cards — the phone's empty
            // state and its dashed "add task to…" row. Inside the same `List`
            // rather than under it, so they scroll with the cards and carry the
            // same margins instead of a second copy of them. Dropped entirely
            // when there are none, rather than left to `EmptyView`: wrapped in
            // a row modifier it is a view like any other, and a list is
            // entitled to give it a row's worth of insets.
            if Trailing.self != EmptyView.self {
                trailing().modifier(TaskListRow(metrics: metrics))
            }
        }
        .listStyle(.plain)
        // A saved view, the Search tab and the Inbox tab, all three of which
        // are a flat read of the board — so a pull past the top asks iCloud
        // whether the board has moved. See ``PullToSync``; nothing is attached
        // on the desk or where sync is off.
        .pullToSync()
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.top, metrics.topInset, for: .scrollContent)
        .contentMargins(.bottom, metrics.bottomInset, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
    }
}

extension TaskListView where Trailing == EmptyView {
    init(
        tasks: [TaskItem],
        metrics: Metrics = .desk,
        @ViewBuilder card: @escaping (TaskItem) -> Card
    ) {
        self.init(tasks: tasks, metrics: metrics, card: card) { EmptyView() }
    }
}

extension TaskListView where Card == PlatformTaskCard {
    /// The list drawing whichever card this platform has, with rows of the
    /// caller's own after the cards. `showsColumn` defaults on because this
    /// list is precisely where a card has left its column behind and nothing
    /// else says where it came from (4.8).
    init(
        tasks: [TaskItem],
        metrics: Metrics = .desk,
        showsColumn: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            tasks: tasks,
            metrics: metrics,
            card: { PlatformTaskCard(task: $0, showsColumn: showsColumn) },
            trailing: trailing
        )
    }
}

extension TaskListView where Card == PlatformTaskCard, Trailing == EmptyView {
    init(tasks: [TaskItem], metrics: Metrics = .desk, showsColumn: Bool = true) {
        self.init(tasks: tasks, metrics: metrics, showsColumn: showsColumn) { EmptyView() }
    }
}

/// The board card, whichever platform is drawing it.
///
/// C5 keeps `Sources/Mac` and `Sources/IOS` each behind their own `#if`, so a
/// shared list cannot name either card. This is that rule's escape hatch: one
/// small view with the branch inside it, rather than the branch smeared through
/// the list.
struct PlatformTaskCard: View {
    let task: TaskItem
    var showsColumn: Bool = true
    /// The list's keyboard focus, where the surface has one to give. macOS
    /// only in practice — it is what makes the row reachable by ⌘A, ⌘C, ⎋ and
    /// the arrows, which the flat surfaces went without while the shortcuts
    /// sheet advertised all four.
    var focus: FocusState<TaskItem.ID?>.Binding?

    var body: some View {
        #if os(macOS)
        if let focus {
            ListCard(task: task, showsColumn: showsColumn, focus: focus)
        } else {
            BoardTaskCard(task: task, showsColumn: showsColumn)
        }
        #else
        // The lift and the menu, in that order and on one view: UIKit shares a
        // long press between the two interactions only when they sit on the
        // same one — see ``ReorderableCard``, which is why the drag is applied
        // here beside the menu rather than inside the card.
        PhoneTaskCard(task: task, showsColumn: showsColumn)
            .modifier(ReorderableCard(task: task))
            .modifier(PhoneTaskRowActions(task: task))
        #endif
    }
}

/// Strips a list row back to its card: no separator, no ground of its own, the
/// design's margin instead of the system's, and the row's width capped and
/// centred rather than left to fill a desktop window.
private struct TaskListRow: ViewModifier {
    let metrics: TaskListMetrics

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: metrics.maxRowWidth)
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(
                top: metrics.rowSpacing / 2, leading: metrics.horizontalPadding,
                bottom: metrics.rowSpacing / 2, trailing: metrics.horizontalPadding
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
