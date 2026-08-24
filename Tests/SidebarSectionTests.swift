import Foundation
import Testing
@testable import Simple_Kanban

/// The foot of the source list, and that all three platforms draw the same
/// thing there.
///
/// **This is a drift test.** The section had gone three different ways: the desk
/// and the iPad shared `BoardSidebar` and headed it **Manage** with Labels and
/// the Trash under it, but the settings row was `#if os(iOS)` — so the desk's
/// list was two rows where the iPad's was three; and the phone's drawer headed
/// its own section **Labels**, held one row called *Manage labels*, had no way
/// to the Trash at all, and kept Settings loose under the lists rather than in a
/// section. Three surfaces, three answers, for a part of the app that is the
/// same list of places on every one of them.
///
/// **A source read, because a section is a layout.** What a `VStack` puts in
/// what order is not a value any store can be asked, and the two files are the
/// two places the answer lives — the same arrangement `CardCornerTests` has
/// with the card's corners. What the rows *do* is tested where they land:
/// `TrashSurfaceTests` presses the Trash, `SettingsTabsTests` is the sheet, and
/// the label manager has its own.
@Suite struct ManageSectionTests {
    /// The two files that draw a source list, and what each calls its rows.
    private static let sidebars = [
        (path: "Shared/BoardSidebar.swift", surface: "the desk and iPad source list"),
        (path: "IOS/PhoneNavDrawer.swift", surface: "the phone's drawer"),
    ]

    private func source(_ path: String) -> String? {
        SourceTree.files().first { $0.path == path }?.source
    }

    /// **Manage**, on both, and not *Labels*: the section stopped being one row
    /// about one thing when the Trash moved into it, and a heading that spent
    /// the word the row underneath it was already spending is the drift this
    /// suite is here to catch.
    @Test(arguments: sidebars.map(\.path))
    func everySidebarHeadsTheSectionManage(path: String) {
        guard SourceTree.isReachable, let source = source(path) else { return }
        #expect(source.contains("sectionHeader(\"Manage\""),
                "\(path) does not head its last section Manage")
        #expect(source.contains("sectionHeader(\"Labels\"") == false,
                "\(path) still heads a section with the name of a row inside it")
    }

    /// The three rows, in the order they are read: what the board is made of,
    /// what it has thrown away, and the app itself.
    @Test(arguments: sidebars.map(\.path))
    func everySidebarHoldsTheSameThreeRowsInTheSameOrder(path: String) {
        guard SourceTree.isReachable, let source = source(path) else { return }

        // The window after the heading, which is where a *use* is — the
        // declarations are hundreds of lines further down, and a row that
        // exists and is not in the list is exactly the phone's old settings
        // row, which sat loose under the lists. Read by distance rather than by
        // indentation so that re-indenting the file is not a failing test.
        guard let heading = source.range(of: "sectionHeader(\"Manage\"") else {
            Issue.record("\(path) has no Manage section at all")
            return
        }
        let window = String(source[heading.upperBound...].prefix(500))

        let rows = ["labelsRow", "trashRow", "settingsRow"]
        let places = rows.compactMap { row -> (String, Int)? in
            guard let range = window.range(of: row) else { return nil }
            return (row, window.distance(from: window.startIndex, to: range.lowerBound))
        }

        #expect(places.count == rows.count,
                "\(path) is missing \(rows.filter { row in !places.contains { $0.0 == row } })")
        #expect(places.map(\.1) == places.map(\.1).sorted(),
                "\(path) draws them in the order \(places.map(\.0))")
    }

    /// And the row that was missing from the desk. `SettingsLink` rather than a
    /// flag is the whole of why it could be left out: `isShowingSettings` raises
    /// the sheet the phone and the iPad use and does nothing at all on macOS,
    /// where Settings is a scene the system opens.
    @Test func theDeskHasASettingsRowOfItsOwn() {
        guard SourceTree.isReachable, let source = source("Shared/BoardSidebar.swift") else { return }
        #expect(source.contains("SettingsLink"),
                "the desk's list has no Settings row — ⌘, is a key, not a place")
    }

    /// The names, which is the other half of what the user sees: a row is named
    /// for what it *is*, like every board and every view above it, rather than
    /// for what pressing it does.
    @Test func theRowsAreNamedForWhatTheyAreRatherThanForTheVerb() {
        guard SourceTree.isReachable else { return }
        for (path, surface) in Self.sidebars {
            guard let source = source(path) else { continue }
            #expect(source.contains("Text(\"Labels\")"), "\(surface) does not call the row Labels")
            #expect(source.contains("Text(\"Trash\")"), "\(surface) has no Trash row")
            #expect(source.contains("Text(\"Settings\")"), "\(surface) has no Settings row")
            #expect(source.contains("Text(\"Manage labels\")") == false,
                    "\(surface) still calls the row by its verb")
        }
    }
}
