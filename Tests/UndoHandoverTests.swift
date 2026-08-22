#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Simple_Kanban

/// The one link in undo that the rest of the suite cannot see.
///
/// Every other undo test hands the store a manager itself. That leaves the
/// handover in `RootView` — `@Environment(\.undoManager)` into
/// `store.undoManager` — covered by nothing: break it and all of `UndoTests`
/// still passes while ⌘Z in the shipping app does nothing at all, because a
/// store with no manager runs every mutation and registers none of them.
///
/// So this puts the real `RootView` in a real window and checks the store came
/// out of it wired. It is a macOS test because the window is what supplies the
/// manager; the iOS surface gets its own from the scene the same way.
@MainActor
@Suite struct UndoHandoverTests {

    @Test func aWindowHandsItsUndoManagerToTheStore() async throws {
        let store = TestBoard.store()
        #expect(store.undoManager == nil, "nothing has introduced them yet")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        // A window made in code is released when it closes, which under ARC
        // over-releases the one this test is still holding and takes the host
        // down a test or two later.
        window.isReleasedWhenClosed = false
        // The per-window state the app owns beside the store. `MacRootView` and
        // the sidebar read it out of the environment, and a missing
        // `@Environment` object is a trap rather than an empty state — it takes
        // the whole test host down.
        let windowState = MacWindowState()
        // Never ordered front: the test must not take a screen or a focus.
        window.contentView = NSHostingView(
            rootView: RootView().environment(store).environment(windowState)
        )
        window.layoutIfNeeded()
        window.displayIfNeeded()

        // `onAppear` lands with the first layout pass rather than on assignment.
        for _ in 0..<40 where store.undoManager == nil {
            try? await Task.sleep(for: .milliseconds(25))
        }

        let adopted = try #require(store.undoManager, "RootView never adopted the window's manager")
        #expect(adopted === window.undoManager)

        // And it is a live one: a mutation through the store lands on it.
        store.setPriority(.low, on: TestBoard.dragDrop)
        #expect(adopted.canUndo)
        #expect(adopted.undoActionName == "Set Priority")

        window.contentView = nil
        window.close()
    }
}
#endif
