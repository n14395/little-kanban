import SwiftUI

/// Which board a card lives on, as a pill that opens the list of destinations.
///
/// The list is the Inbox and then every board, in sidebar order, and it is
/// written here because four surfaces were writing it — with three different
/// ideas of how to mark where the card already is. A tick marks it, and only a
/// tick: see ``BoardDestinationItems``.
///
/// This is the whole control for a surface that wants one — a labelled pill and
/// the menu behind it. A surface that already has a menu of its own nests
/// ``BoardDestinationItems`` in a submenu instead.
struct BoardDestinationMenu: View {
    struct Metrics {
        var dot: CGFloat
        var spacing: CGFloat
        var font: CGFloat
        /// What the pill's name scales against under Dynamic Type.
        var textStyle: Font.TextStyle
        var textOpacity: Double
        var chevronOpacity: Double
        var horizontalPadding: CGFloat
        /// The pill's height, which on touch is also its floor.
        var height: CGFloat
        var radius: CGFloat

        static let desk = Metrics(
            dot: 7, spacing: 7, font: 12.5, textStyle: .footnote,
            textOpacity: 0.7, chevronOpacity: 0.35,
            horizontalPadding: 10, height: 30, radius: 10
        )
        static let sheet = Metrics(
            dot: 8, spacing: 9, font: 14, textStyle: .subheadline,
            textOpacity: 1, chevronOpacity: 0.4,
            horizontalPadding: 14, height: 44, radius: 12
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    var metrics: Metrics = .desk

    private var board: Board? { store.board(for: task) }

    var body: some View {
        Menu {
            BoardDestinationItems(task: task)
        } label: {
            HStack(spacing: metrics.spacing) {
                Circle()
                    .fill(palette.resolve(board?.dot ?? Board.inboxDot))
                    .frame(width: metrics.dot, height: metrics.dot)
                Text(board?.name ?? Board.inboxName)
                    .font(SimpleKanbanFont.ui(metrics.font, .bold, relativeTo: metrics.textStyle))
                    .foregroundStyle(palette.ink(metrics.textOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(palette.inkText(metrics.chevronOpacity))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(minHeight: metrics.height)
            .background(palette.ink(0.06), in: .rect(cornerRadius: metrics.radius))
            .contentShape(.rect)
        }
        .modifier(BorderlessMenu())
        .menuIndicator(.hidden)
        .accessibilityLabel("Board")
        .accessibilityValue(board?.name ?? Board.inboxName)
    }
}

/// The destinations on their own: the Inbox, a rule, then every board.
///
/// **A tick marks where the card is now, and nothing else does.** The three
/// conventions this replaces each lost something. Disabling the current
/// destination and dropping it from the list both make the menu change shape
/// depending on where the card is, so a board sits at a different place each
/// time it is opened and the menu never says where the card is now — and a
/// disabled row is one a screen reader skips, which is the row carrying the
/// answer. The tick is also what SwiftUI's own `Picker` draws in a menu, so it
/// is what a reader is already being told to expect on both platforms.
///
/// Choosing the ticked one does nothing rather than re-filing: filing a card
/// onto the board it is already on sends it to that board's landing column,
/// which is a move nobody asked for and the two ticked menus were quietly
/// making.
struct BoardDestinationItems: View {
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    var body: some View {
        Button {
            if !task.isUnfiled { store.unfile(task.id) }
        } label: {
            label(Board.inboxName, isCurrent: task.isUnfiled)
        }
        .accessibilityAddTraits(task.isUnfiled ? [.isSelected] : [])

        if !store.boards.isEmpty { Divider() }

        ForEach(store.boards) { board in
            let isCurrent = board.id == task.boardID
            Button {
                if !isCurrent { store.file(task.id, onto: board.id) }
            } label: {
                label(board.name, isCurrent: isCurrent)
            }
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        }
    }

    @ViewBuilder private func label(_ name: String, isCurrent: Bool) -> some View {
        if isCurrent {
            Label(name, systemImage: "checkmark")
        } else {
            Text(name)
        }
    }
}
