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
}
