import Foundation
import Testing
@testable import Simple_Kanban

/// Where the Trash is, now that it is not a tab of Settings.
///
/// **The move, in one sentence:** everything in Settings is a preference about
/// how the app behaves, and the Trash is the user's own work sitting out a
/// thirty-day countdown. A preference can wait; a card thrown away on Tuesday
/// cannot wait past the thirtieth day, and it should not take three taps through
/// a preferences sheet to reach it.
///
/// So it has three doors — the Trash row under Manage in the source list on macOS
/// and on iPad, and the board menu on the phone — all of which raise the one flag,
/// `BoardStore.isShowingTrash`. That flag is the seam these tests are written
/// against: a store can be asked whether the doors set it, and the source can be
/// read for whether each surface has one. What a popover *looks* like is
/// `UITests`' business.
@MainActor
@Suite struct TrashSurfaceTests {

    /// Session state, like every other surface flag: what is on screen is not
    /// part of the board, and a file that recorded it would make opening the
    /// Trash a change to be synced to another device. `PreferenceTests` holds
    /// the general rule; this is the new flag's share of it.
    @Test func showingTheTrashIsSessionStateAndStartsShut() {
        let store = TestBoard.store()
        #expect(store.isShowingTrash == false)

        store.isShowingTrash = true
        #expect(store.isShowingTrash)

        // Nothing about the board changed, so nothing about the board is
        // different — which is the whole claim, and the reason this is not in
        // `BoardSnapshot`.
        #expect(store.exportedSnapshot.tasks.count == TestBoard.tasks.count)
    }

    /// **The Trash is out of Settings and stays out.** The settings surface used
    /// to build a `TrashView` in a pane of its own; a copy left behind there
    /// would be two doors onto one list, which is the arrangement the Inbox
    /// spent a release untangling.
    @Test func theSettingsSurfaceNoLongerHoldsTheTrash() throws {
        try #require(SourceTree.isReachable)
        let settings = try #require(file("Shared/SettingsView.swift"))

        #expect(!settings.source.contains("TrashView("),
                "SettingsView builds a TrashView again")
        #expect(!settings.source.contains("case .trash"),
                "SettingsView has a trash pane again")
    }

    /// Every surface that can reach the Trash, and the one flag they all raise.
    ///
    /// Read out of the source, the way `DragReorderTests` reads its drop
    /// closures: a door is a button in a view body, and there is nothing to
    /// enumerate at runtime. What matters is that each of the three files has
    /// one — a platform quietly losing its only way in is exactly the defect
    /// that put `SettingsTab` in front of both surfaces in the first place.
    @Test func everySurfaceHasItsOwnDoor() throws {
        try #require(SourceTree.isReachable)
        // The source list is macOS **and** iPad — one file, both platforms — and
        // the phone's is the header's board menu, which is that surface's drawer
        // for everything with no other home.
        for path in ["Shared/BoardSidebar.swift", "IOS/PhoneHeader.swift"] {
            let door = try #require(file(path), "\(path) is not in the source tree")
            #expect(door.source.contains("store.isShowingTrash = true"),
                    "\(path) has no way into the Trash")
        }
    }

    /// And the surface that *presents* it on the phone, which is not the surface
    /// that opens it: a menu lives inside the header and a sheet wants the root.
    /// The same split `SettingsSheet` makes for the drawer's Settings row, and
    /// the reason the flag is on the store rather than in a view.
    @Test func thePhoneRootPresentsTheSheetItsHeaderAsksFor() throws {
        try #require(SourceTree.isReachable)
        let root = try #require(file("IOS/PhoneRootView.swift"))
        #expect(root.source.contains("TrashSheet()"), "the phone raises no Trash sheet")

        let header = try #require(file("IOS/PhoneHeader.swift"))
        #expect(!header.source.contains("TrashSheet()"),
                "the header presents the sheet its own menu opens, which a menu cannot do")
    }

    private func file(_ path: String) -> SourceFile? {
        SourceTree.files().first { $0.path == path }
    }
}
