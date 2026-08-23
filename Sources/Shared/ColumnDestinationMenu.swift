import SwiftUI

/// Where on its board a card sits, as menu items — the second half of the
/// question ``BoardDestinationItems`` asks the first half of.
///
/// The two are drawn side by side in both card context menus, as **Move Board**
/// and **Move Column**, and they split the same way `BoardDestinationMenu` and
/// ``MoveToPicker`` split it on the detail surfaces: the board menu answers
/// *which board*, and a card in the Inbox is on none; this answers *where on
/// it*, and the Inbox is not a place on a board.
///
/// **The card's own board, not the board on screen.** A card drawn in a saved
/// view or a search result can belong to another one, and its columns are the
/// ones it can move between — the rule the rotor actions and ⌥←/→ have always
/// followed, and which lives in `BoardStore.moveDestinations(for:)` so that the
/// list drawn here, the list the rotor offers and the guard the callers use to
/// decide whether there is a submenu at all are one list.
///
/// **A tick marks the column the card is in, and nothing else does**, which is
/// ``BoardDestinationItems``' convention and for its reasons: a list that drops
/// or disables the current entry changes shape depending on where the card is,
/// so a column sits somewhere different each time the menu is opened and the
/// menu never says where the card is now. Picking the ticked one does nothing,
/// rather than sending the card to the bottom of the column it is already in.
///
/// This replaced Move Up / Move Down, which named a *neighbour* rather than a
/// place: the pair could only ever shuffle a card inside one column, said
/// "down" backwards to work around `move`'s refusal of `before: nil`, and
/// changed which of the two rows it drew depending on where in the column the
/// card had got to. Naming the destination is the same act said in the same
/// words as everything else that files a card.
struct ColumnDestinationItems: View {
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    var body: some View {
        ForEach(store.moveDestinations(for: task)) { column in
            let isCurrent = column.id == task.columnID
            Button {
                // The selection when this card is in it, which is what ⌥←/→,
                // the rotor actions and the Task menu's Move to Column all do:
                // a menu raised on one of five selected cards is raised on the
                // five.
                if !isCurrent { store.move(store.commandTargets(task.id), to: column.id) }
            } label: {
                if isCurrent {
                    Label(column.name, systemImage: "checkmark")
                } else {
                    Text(column.name)
                }
            }
            .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        }
    }
}
