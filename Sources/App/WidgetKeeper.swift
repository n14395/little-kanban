// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Publishes the widgets' digest at the two moments a *save* does not cover.
///
/// Every edit to the board already republishes, on the save debounce — see
/// `BoardStore.reconcileSystemsAndSync`, where the widgets are the fourth
/// follower. Two things that change what a widget draws are not edits to the
/// board, so nothing there fires for them:
///
/// - **A launch.** Nothing has been saved yet, so a machine that was rebooted
///   with a widget on the desktop would draw whatever the digest said before
///   the last quit until somebody typed into the board.
/// - **Midnight.** "Today" and "Due this week" are evaluated against a day, and
///   the day rolls over under a board nobody is editing. `DayClock` is what
///   knows, and it is an environment value only a view can read.
///
/// The appearance override is here for the same reason it is on
/// ``AppIconKeeper``: it decides which of the two theme slots a widget wears,
/// it lives in `UserDefaults` rather than in the board, and a change to it
/// saves nothing.
///
/// Publishing more often than necessary costs nothing anybody sees:
/// ``WidgetPublisher`` compares against what it last wrote and does not wake a
/// widget for a digest that has not changed.
struct WidgetKeeper: ViewModifier {
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    func body(content: Content) -> some View {
        content
            // `.task` rather than `.onAppear`: a first launch has no board yet
            // — `FirstRunView` is still asking which one to start from — and
            // this runs after the store has been restored either way.
            .task { WidgetPublisher.publish(store, today: dayClock.today) }
            .onChange(of: dayClock.today) { _, today in
                WidgetPublisher.publish(store, today: today)
            }
            .onChange(of: appearance) { _, _ in
                WidgetPublisher.publish(store, today: dayClock.today)
            }
    }
}

extension View {
    /// See ``WidgetKeeper``.
    func keepsTheWidgetsInStep() -> some View { modifier(WidgetKeeper()) }
}
