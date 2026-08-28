import SwiftUI

/// The task verbs, as rotor actions — one list, worn by both cards.
///
/// Each card combines its children for VoiceOver, which hides the tick, and
/// the context menu answers only a pointer — see ``pointerContextMenu(items:)``
/// — which to a reader driving by touch is a menu that is not there. So every
/// verb the menu carries has to be here, by rotor. The list used to be written
/// twice, once per card, and had already drifted: the desk said "Complete
/// task" where the phone said "Complete", and a verb added to one would have
/// silently missed the other.
///
/// `actsOnSelection` is the one difference that is real rather than drift.
/// The desk's verbs act on the whole selection when this card is part of it,
/// exactly as the keys and the menu bar do — a VoiceOver user who has picked
/// three cards and chooses a verb means three. The phone has no
/// multi-selection, so its verbs act on the card the reader is standing on.
/// The tick and the context menu stay singular everywhere, on purpose: both
/// are aimed at one card with a pointer, and the card they are aimed at is
/// the one under it.
struct TaskRotorActions: ViewModifier {
    @Environment(BoardStore.self) private var store

    let task: TaskItem
    /// True on the desk, where the rotor takes `commandTargets`; false on the
    /// phone, where it takes this card alone.
    let actsOnSelection: Bool

    private var isDone: Bool { store.isDone(task) }

    private var targets: Set<TaskItem.ID> {
        actsOnSelection ? store.commandTargets(task.id) : [task.id]
    }

    func body(content: Content) -> some View {
        content
            .accessibilityActions {
                if !task.isArchived {
                    Button(isDone ? "Reopen task" : "Complete task") { toggleTargets() }
                }
                // A filed card is already off the board, so unfiling it is not
                // a move the Archive can show — restoring it is the way back.
                if !task.isUnfiled, !task.isArchived {
                    Button("Move to Inbox") { store.move(targets, to: .inbox) }
                }
                // The one menu verb the rotor did not already carry. It leant
                // on the context menu, which now answers only a pointer.
                Button("Copy Link") { TaskLink.copyToPasteboard(task.id) }
            }
            .accessibilityAction(named: task.isArchived ? Text("Restore task") : Text("Archive task")) {
                if task.isArchived {
                    // A card at a time: the store has no bulk restore, and one
                    // is the only way to keep this honest about which cards it
                    // takes.
                    for id in targets { store.unarchive(id) }
                } else {
                    store.archive(targets)
                }
            }
            .accessibilityAction(named: Text("Trash task")) {
                store.trashTasks(targets)
            }
            .modifier(MoveActions(task: task))
    }

    /// The rotor's complete, which follows the same rule Space does: one card
    /// toggles, several complete.
    private func toggleTargets() {
        if targets.count == 1, isDone {
            store.reopen(task.id)
        } else {
            store.complete(targets)
        }
    }
}
