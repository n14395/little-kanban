// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Pull a list of cards down past its top and the board checks iCloud.
///
/// The gesture every iOS app spells "refresh", on the surfaces that hold cards:
/// a board column, a saved view, the Inbox. It is the touch platforms' answer
/// to a question the desk answers with a window that is always in front of you
/// — *has the other machine sent anything yet?* — and it is deliberately the
/// system's own gesture and the system's own spinner rather than a button in a
/// toolbar, because a pull past the top is what a finger already does when it
/// wants a list to be right.
///
/// **Nothing is attached when the board is not syncing.** A spinner is a
/// promise that something is being checked, and a device with sync switched off
/// or iCloud unavailable has nothing to check: the list simply bounces, which
/// is the honest answer. See ``BoardStore/syncNow(settling:)`` for what the pull
/// does when there *is* something to ask, and for the card it leaves on screen
/// when it is done.
///
/// **`enabled:` is for a surface that has another use for the gesture**, which
/// is the phone's Inbox: it is a sheet whose own dismissal is a downward drag,
/// so a pull past the top of its cards was the same finger asking for two things
/// a few points apart. It passes `false`. The iPad's Inbox is a panel with
/// nothing to dismiss and keeps the pull.
///
/// **The bounce comes with it, which is why the modifier owns it.** Every card
/// surface in the app asks for `.basedOnSize`, so a column whose cards do not
/// fill it does not rubber-band — and a list that cannot be pulled past a top it
/// is already at cannot be pulled to refresh either. The half-empty column is
/// precisely where somebody waiting on another device's card will pull. So the
/// surface hands its resting behaviour over as `bounce:` and this decides: the
/// surface's own answer while there is nothing to check, `.always` on the
/// vertical axis for as long as the refresh is live. Two `scrollBounceBehavior`
/// lines around one scroll view would be a question about which of them the
/// scroll view reads, and that is not a question worth depending on the answer
/// to.
///
/// **Driven by hand on the two column surfaces and not on the third.** A phone
/// column and an iPad column were both pulled on a simulator, against a marker
/// minted inside the refresh, and both fired. The same drag on ``TaskListView``
/// — a `List`, whose refresh is UIKit's control rather than SwiftUI's — fired
/// nothing, three gestures round, which is as likely to be XCUITest's limit as
/// the app's: `List` with `refreshable` is the pairing Apple documents, and this
/// is the same modifier the columns carry. Left on, and left unproven.
///
/// macOS gets none of this: `refreshable` there is a menu item's job, and the
/// desk has no pull. Off iOS the modifier is the bounce line and nothing else.
struct PullToSync: ViewModifier {
    /// How this surface bounces when no refresh is attached — the line it would
    /// otherwise be carrying itself.
    let resting: ScrollBounceBehavior
    /// Whether this surface wants the gesture at all. `false` where a downward
    /// drag already means something else — see the note above.
    var enabled: Bool = true

    #if os(iOS)
    @Environment(BoardStore.self) private var store
    #endif

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if enabled, store.isSyncing {
            content
                .refreshable { await store.syncNow() }
                .scrollBounceBehavior(.always, axes: .vertical)
        } else {
            content.scrollBounceBehavior(resting, axes: .vertical)
        }
        #else
        content.scrollBounceBehavior(resting, axes: .vertical)
        #endif
    }
}

extension View {
    /// Makes this scroll view's pull past the top a check for what the user's
    /// other devices have sent, and says how it bounces when there is nothing to
    /// check. Applied to the scroll view itself, in place of the
    /// `.scrollBounceBehavior` line it would otherwise carry.
    func pullToSync(
        bounce resting: ScrollBounceBehavior = .automatic, enabled: Bool = true
    ) -> some View {
        modifier(PullToSync(resting: resting, enabled: enabled))
    }
}
