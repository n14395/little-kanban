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
        /// The board's own glyph, and the Inbox's — see ``Board/inboxSymbol``.
        var glyph: CGFloat
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

        // The pointer pill keeps its own type — 12.5pt beside 11pt column
        // segments — but not its own box. The padding and the corner are the
        // sheet's, scaled down rather than a different idea of the shape, so
        // the panel and the sheet draw the same control.
        static let desk = Metrics(
            glyph: 13, spacing: 7, font: 12.5, textStyle: .footnote,
            textOpacity: 0.7, chevronOpacity: 0.35,
            horizontalPadding: 12, height: 34, radius: 12
        )
        static let sheet = Metrics(
            glyph: 15, spacing: 9, font: 14, textStyle: .subheadline,
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
            // The pill is only ever drawn on a surface that has the card open,
            // so picking a board here goes there: see `BoardDestinationItems`.
            BoardDestinationItems(task: task, follows: true)
        } label: {
            HStack(spacing: metrics.spacing) {
                Image(systemName: SymbolMark.resolved(board?.symbol ?? Board.inboxSymbol))
                    .symbolSize(metrics.glyph, weight: .medium, relativeTo: metrics.textStyle)
                    .foregroundStyle(palette.inkText(0.55))
                    .accessibilityHidden(true)
                Text(board?.name ?? Board.inboxName)
                    .font(palette.ui(metrics.font, .bold, relativeTo: metrics.textStyle))
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
        // The pill spans its row on both surfaces. The label already ends in a
        // `Spacer`, which is enough on iOS; macOS's borderless menu style sizes
        // itself to its label instead, so without this the desk drew a pill as
        // wide as the board's name with the column picker full-width beneath it.
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Board")
        .accessibilityValue(board?.name ?? Board.inboxName)
        .accessibilityIdentifier(Self.pillID)
    }

    /// What `UITests/InboxFilingTests` finds this by, shared through the source
    /// rather than by both spelling the same string — the arrangement
    /// `BoardToolbar.inboxToggleID` and `SettingsTab.chipID` have.
    ///
    /// The name alone will not do. "Board" is also the phone's first tab, and
    /// the editor is a sheet at a detent — so once it is presented by the *root*
    /// rather than by the Inbox panel, the bar behind it is reachable and a
    /// query by label finds two.
    static let pillID = "BoardDestination"
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
/// making. It is also why `follows` cannot take you to the board you are on —
/// nothing moved, so there is nothing to follow.
struct BoardDestinationItems: View {
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    /// Whether picking a destination also *goes* there.
    ///
    /// It does from the pill, which is drawn on the detail surfaces and nowhere
    /// else: the card stays open in front of you as it moves, and leaving the
    /// board it went to off screen means the panel and the board behind it
    /// disagree about where the card is. It does not from the two card context
    /// menus, where filing is done from the board, a card at a time — being
    /// thrown onto another board after each one is a worse answer than the
    /// card simply leaving.
    var follows: Bool = false

    var body: some View {
        Button {
            if !task.isUnfiled { pick { store.unfile(task.id) } }
        } label: {
            label(Board.inboxName, isCurrent: task.isUnfiled)
        }
        .accessibilityAddTraits(task.isUnfiled ? [.isSelected] : [])
        // Named for the same reason the pill is: the boards below are found by
        // their own names, which are the user's and are unique, but "Inbox" is
        // also the phone's middle tab. See ``BoardDestinationMenu/pillID``.
        .accessibilityIdentifier(Self.inboxRowID)

        if !store.boards.isEmpty { Divider() }

        ForEach(store.boards) { board in
            let isCurrent = board.id == task.boardID
            Button {
                if !isCurrent { pick { store.file(task.id, onto: board.id) } }
            } label: {
                label(board.name, isCurrent: isCurrent)
            }
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        }
    }

    /// Files the card, and then follows it if this menu follows. Afterwards
    /// rather than before: where the card lives is read back off the card, so
    /// the move has to have happened for there to be anywhere to go.
    private func pick(_ file: () -> Void) {
        file()
        if follows { store.showPlace(of: task.id) }
    }

    @ViewBuilder private func label(_ name: String, isCurrent: Bool) -> some View {
        if isCurrent {
            Label(name, systemImage: "checkmark")
        } else {
            Text(name)
        }
    }

    /// What `UITests/InboxFilingTests` finds the Inbox row by.
    static let inboxRowID = "BoardDestination.inbox"
}
