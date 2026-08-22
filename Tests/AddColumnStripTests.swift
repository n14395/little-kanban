import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

/// The trailing tile that grows a board a column.
///
/// It used to be a column-wide pill: 272pt of board — a whole card's worth —
/// spent on two words, on every board, for ever. It now stands on its side.
///
/// These *render* it rather than reading its constants, because the constants
/// were never the risk. `rotationEffect` draws a view turned without telling
/// the layout, so a rotated label claims the width of the horizontal words it
/// used to be: the tile would look right and still hold the board open to the
/// old width. Only a measurement can tell those two apart.
@MainActor
@Suite struct AddColumnStripTests {
    private static func rendered(_ metrics: BoardColumnView.Metrics) -> CGSize? {
        size(of: ImageRenderer(content: tile(metrics)))
    }

    /// One spelling per platform for the same measurement, so both of them
    /// measure: `nsImage` is macOS-only, and a suite that compiles on one
    /// platform is not a suite that runs on the other.
    private static func size(of renderer: ImageRenderer<some View>) -> CGSize? {
        #if os(macOS)
        renderer.nsImage?.size
        #else
        renderer.uiImage?.size
        #endif
    }

    private static func tile(_ metrics: BoardColumnView.Metrics) -> some View {
        AddColumnTile(isComposing: .constant(false), metrics: metrics)
            .environment(TestBoard.store())
            .environment(\.palette, Palette(colorScheme: .light))
    }

    /// The point of the exercise: the tile is a strip, not a column.
    @Test(arguments: [("desk", BoardColumnView.Metrics.desk), ("pad", BoardColumnView.Metrics.pad)])
    func theTileIsAStripRatherThanAColumn(preset: (name: String, metrics: BoardColumnView.Metrics)) throws {
        let size = try #require(Self.rendered(preset.metrics), "\(preset.name) rendered nothing")
        #expect(size.width <= preset.metrics.addColumnWidth + 1,
                "\(preset.name) is \(size.width)pt wide; the strip claims \(preset.metrics.addColumnWidth)")
        #expect(size.width < preset.metrics.width / 3,
                "\(preset.name) is \(size.width)pt of a \(preset.metrics.width)pt column")
    }

    /// The words are turned, so the tile is taller than it is wide. Flat is
    /// what a rotation that never took looks like.
    @Test(arguments: [("desk", BoardColumnView.Metrics.desk), ("pad", BoardColumnView.Metrics.pad)])
    func theWordsRunDownIt(preset: (name: String, metrics: BoardColumnView.Metrics)) throws {
        let size = try #require(Self.rendered(preset.metrics))
        #expect(size.height > size.width * 2,
                "\(preset.name) is \(size.width)x\(size.height); the label did not turn")
    }

    /// Naming the column still wants a text field and the four roles beside it,
    /// which is a column's width whatever opened it.
    @Test func theComposerIsStillAColumnWide() throws {
        let renderer = ImageRenderer(
            content: AddColumnTile(isComposing: .constant(true), metrics: .desk)
                .environment(TestBoard.store())
                .environment(\.palette, Palette(colorScheme: .light))
        )
        let size = try #require(Self.size(of: renderer))
        #expect(size.width == BoardColumnView.Metrics.desk.width)
    }

    // MARK: The composer only exists while it is being used

    /// The tile is a button that becomes a field, and it is a field only while
    /// the field has the keyboard: clicking away puts the button back. Left
    /// open, a half-named column sits where a button should be — at the end of
    /// the strip, on every board, for the rest of the session — which is not
    /// the trade the *task* composer makes, where the row left behind is
    /// harmless and a half-typed title is worth keeping.
    ///
    /// Whether a field holds the keyboard is not a value this target can read,
    /// so this reads the source. Measured against the built app through the
    /// accessibility API: with the composer open and the keyboard moved to
    /// another control, the field goes and `Add column` comes back.
    @Test func theComposerClosesWhenTheKeyboardLeavesIt() {
        guard SourceTree.isReachable else { return }
        guard let file = SourceTree.files().first(where: { $0.path == "Shared/BoardColumnView.swift" })
        else {
            Issue.record("the column view has moved file")
            return
        }
        let source = file.source
        guard let head = source.range(of: ".onChange(of: isFocused)") else {
            Issue.record("the add-column composer no longer watches its own focus")
            return
        }
        let body = file.block(after: source.distance(from: source.startIndex, to: head.lowerBound))
        #expect(body.contains("cancel()"), "losing the keyboard no longer closes it: \(body)")

        // The strip scrolls this tile into view in the same turn the composer
        // opens in, so a close that fired on any momentary loss of the keyboard
        // would be a field that shuts as it appears. It waits a turn and asks
        // again.
        #expect(body.contains("await Task.yield()"),
                "the close acts on the first loss of the keyboard: \(body)")
        #expect(body.contains("guard !isFocused"),
                "the close does not re-check that the keyboard really left: \(body)")
    }

    /// The composer names the column and does nothing else. The four role
    /// segments under the field are gone, which takes `.done` with them: a
    /// column added from the board is a `.backlog` one, and the phone's drawer
    /// is the only place left that chooses. `BoardStore` still has no
    /// `setColumnRole`, so this is the whole of what a pointer can say about a
    /// new column's role — see ``AddColumnTile``.
    @Test func theComposerAsksForANameAndNothingElse() {
        guard SourceTree.isReachable else { return }
        guard let file = SourceTree.files().first(where: { $0.path == "Shared/BoardColumnView.swift" })
        else {
            Issue.record("the column view has moved file")
            return
        }
        #expect(file.source.contains("rolePicker") == false,
                "the board's add-column composer has a role picker under it again")

        // The phone still has one, and is now the only surface that does. If
        // this goes, no surface can make a Done column at all.
        let phone = SourceTree.files().first { $0.path == "IOS/PhoneNavDrawer.swift" }
        #expect(phone?.source.contains("rolePicker") == true,
                "no surface left can give a board a Done column")
    }
}
