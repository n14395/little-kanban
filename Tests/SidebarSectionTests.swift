import Foundation
import Testing
@testable import Cardstock

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

/// Who paints the source list's ground, and its seam.
///
/// The reported bug, from an iPad: the column's colour stopped a couple of
/// hundred points above the foot of the screen, and the hairline down its
/// trailing edge stopped with it. `BoardSidebar` hangs both on itself, which is
/// exactly right on the desk — there the view *is* the column, the height of the
/// window. On iPad it sits inside a `ScrollView`, and inside one a view is as
/// tall as its content: the wash ended under the last row.
///
/// The tell was that the band below it was not bare but *paler*. The scroll view
/// was already washing the whole column from behind, so the list carried the
/// wash twice and the band carried it once — which is also why the fix is not
/// "wash it again" but "wash it once, from the thing that is the column's
/// height", and why the seam has to move with the ground rather than after it.
///
/// **Read out of the source, because a colour's *extent* is not a value.**
/// Whether a background covers a column or only the rows in it is SwiftUI's
/// answer to a layout proposal; there is no view hierarchy in this target to ask.
/// Measured instead against `NSHostingView`, outside the suite: a pane like this
/// one in a 600pt column, with five rows in it, painted its ground and its seam
/// to y=204 and stopped. What is asserted here is the arrangement that followed.
@Suite struct SourceListGroundTests {
    @Test func theColumnsGroundIsPaintedOnceByWhicheverViewIsTheColumn() {
        #expect(BoardSidebar.Metrics.desk.paintsItsOwnGround,
                "the desk's source list is the column, and nothing else there would paint it")
        #expect(BoardSidebar.Metrics.pad.paintsItsOwnGround == false,
                "the iPad's list is inside a scroll view, where it is only as tall as its rows")

        guard SourceTree.isReachable else { return }
        let files = SourceTree.files()
        guard let pad = files.first(where: { $0.path == "IOS/PadRootView.swift" }),
              let list = files.first(where: { $0.path == "Shared/BoardSidebar.swift" })
        else {
            Issue.record("the iPad root or the source list has moved file")
            return
        }

        // Scoped to the property that draws the column: the Inbox panel and the
        // task editor wash themselves in the same file, and a whole-file read
        // would be satisfied by either of them.
        let parts = pad.source.components(separatedBy: "private var sidebar: some View")
        #expect(parts.count == 2, "PadRootView.sidebar has been renamed; this is reading the wrong view")
        let column = parts.last?.components(separatedBy: "private var detail").first ?? ""
        #expect(column.contains("background(palette.panelOverlay)"),
                "the iPad's column has no ground of its own, and the pane inside it no longer paints one")
        #expect(column.contains("hairline(.trailing"),
                "the iPad's column has no seam; the pane's would stop where its rows do")

        // And the pane's own pair stays behind the switch. Unconditional again
        // is the bug again — two washes over the rows and one under them.
        #expect(list.source.contains("metrics.paintsItsOwnGround ? palette.panelOverlay"),
                "the source list paints its ground whatever surface it is on")
        #expect(list.source.contains("metrics.paintsItsOwnGround ? palette.ink"),
                "the source list paints its seam whatever surface it is on")
    }
}
