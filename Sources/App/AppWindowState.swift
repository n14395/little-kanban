import SwiftUI

/// What one window knows about itself that the board does not: whether its
/// source list is showing, which column has the keyboard, and the handful of
/// things a menu item asks of a view it cannot reach.
///
/// Session state like the store's own, and here rather than there because none
/// of it is saved and none of it is the board's. Owned by the app so the menu
/// bar — which is outside every window's view tree — can read and write it.
///
/// **On both platforms**, which it was not: this was `MacWindowState`, on the
/// reasoning that iPadOS had no menu bar of ours to own it. It has one now — see
/// ``BoardCommands`` — and everything here means exactly what it meant on the
/// desk: the iPad's source list is a column of a `NavigationSplitView` rather
/// than a sibling in an `HStack`, so ``isSidebarVisible`` is mapped onto that
/// column's visibility by `PadRootView` and is otherwise the same flag.
@MainActor
@Observable
final class AppWindowState {
    var isSidebarVisible = true

    /// The column holding the focused card, or `nil` while nothing on the board
    /// has focus. ⌘N adds to it: the composer has to open where the user is
    /// looking, and on a board scrolled right the leftmost column is not it.
    var focusedColumnID: BoardColumn.ID?

    /// The card the keyboard is on, written by the surface that draws it.
    ///
    /// The menu bar reads it because ⌘⌫ and ⌘⏎ are *its* keys: an item on the
    /// menu bar wins a press before a focused view ever sees it, so a card
    /// claiming them too would simply never run. The menu asks what the
    /// keyboard is on instead, and acts on that card's `commandTargets`.
    var focusedTaskID: TaskItem.ID?

    /// Set by File ▸ New Board and cleared by the sidebar when it opens its
    /// field. A board is named as it is made, and the field that names it is a
    /// row in a list the menu has no way to reach.
    var isNamingNewBoard = false

    /// Set by Task ▸ Set Due Date… and cleared by the sheet it opens. The
    /// ellipsis in that title is a promise that something appears to type into.
    var isPickingDueDate = false

    /// Set by View ▸ Labels…, and the menu bar's own flag rather than the
    /// sidebar's.
    ///
    /// The sidebar has a row that opens the same manager and keeps its own
    /// state for it, which is right: a row can present the sheet it asks for.
    /// The menu cannot — it is outside the view tree, and the list it would
    /// borrow the flag from is a view that may not be on screen at all. One
    /// flag per asker, one sheet, and never both at once, because a sheet is
    /// modal and the second ask cannot happen while the first is up.
    var isManagingLabels = false

    /// Which of the two app-menu items opened the About window. Check for
    /// Updates… promises a check, so the panel starts one rather than making the
    /// user ask twice; About promises nothing and does nothing. Session state
    /// like the rest of this, and none of it is saved.
    var aboutStartsCheck = false

    /// The cards Set Due Date… was aimed at, handed to the sheet rather than
    /// worked out there a second time.
    ///
    /// The sheet read `store.selection`, which is not what the item acts on: ⎋
    /// clears the selection and leaves focus where it was, so the item stayed
    /// live — rightly, it is aimed at the focused card — opened a sheet titled
    /// "Due date", and Set did nothing at all. Two derivations of one rule is
    /// how a menu comes to promise what it will not do; there is one now, and it
    /// is `BoardCommands.applicable(_:)`.
    var dueDateTargets: Set<TaskItem.ID> = []
}
