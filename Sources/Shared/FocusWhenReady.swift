import SwiftUI

extension View {
    /// Takes the keyboard as soon as the field is able to hold it.
    ///
    /// **`@FocusState` set from `onAppear` is dropped on the floor.** The
    /// assignment lands before AppKit has finished installing the field, and
    /// nothing reports the failure: the row appears with a placeholder, no
    /// caret, and the first thing typed goes wherever the focus actually is.
    /// Every inline field in this app is opened *by* something — the column's
    /// "+", the sidebar's New board, the title in the toolbar — so there is no
    /// second click to recover with, and three of them shipped like that.
    ///
    /// One `Task.yield()` is the whole fix, and it is not a guess at a
    /// duration. It puts the assignment on the far side of the run-loop turn
    /// the view was created in, which is the turn the field becomes focusable
    /// in. The alternatives were measured against the built app and do not
    /// work: `onAppear` does not, a bare `task` does not — it starts in the
    /// same turn — and `defaultFocus` does not either, outside the popover it
    /// was reached for in `LabelEditor`, because it settles a scope's default
    /// when the scope is *established* and these fields appear inside one that
    /// already exists. A sleep long enough to work — 50ms was — is this same
    /// yield written as a number that happens to be right on one machine.
    ///
    /// Every field that opens focused goes through here, so there is one place
    /// to change if a later SDK moves the turn this lands in.
    ///
    /// Generic over the focus value because half of these fields are one of
    /// several — the column editor opens on its Name and has a Short beside it
    /// — and a `Bool`-only version would have left those spelling the idiom out
    /// again, which is how the three that shipped broken came to differ.
    func focusWhenReady<Value: Hashable>(
        _ focus: FocusState<Value>.Binding, _ value: Value
    ) -> some View {
        task {
            await Task.yield()
            focus.wrappedValue = value
        }
    }

    /// The `Bool` field, which is most of them. `when:` is for the one surface
    /// that opens the same sheet two ways — the phone's drawer, which types a
    /// board's name only when it was opened to rename it — and is a condition
    /// rather than a value so that "do not focus" cannot be said as "focus
    /// `false`", which would take the keyboard *away* from wherever it is.
    func focusWhenReady(_ focus: FocusState<Bool>.Binding, when condition: Bool = true) -> some View {
        task {
            guard condition else { return }
            await Task.yield()
            focus.wrappedValue = true
        }
    }
}
