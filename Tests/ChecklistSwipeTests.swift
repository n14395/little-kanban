import Foundation
import SwiftUI
import Testing
@testable import LittleKanban

/// The delete button a touch row uncovers by sliding aside — and the one
/// thing about it a unit test can ask without a finger: that it is *not
/// there* until the row has moved.
///
/// Reported from a phone: every row of the sheet's checklist wore its delete
/// button at rest, drawn over the grip. The button was parked in the row's
/// `.background` on the theory that the row covered it until a swipe moved it
/// aside — but a touch row has no fill of its own, the card's ground runs
/// through it, and a button behind a transparent row is a button on screen.
/// `ChecklistView.deleteReveal(for:)` masks the button to the width the row
/// has actually moved. A drag cannot be performed from a unit test, so the
/// half that can be asked is asked of the pixels: rendered at rest, nothing in
/// the checklist is the delete tone.
@MainActor
@Suite struct ChecklistSwipeTests {
    /// The tone as it lands on a white page, measured rather than assumed: the
    /// chip colour may carry an opacity, and the question is what a button
    /// covered by nothing *draws*.
    private static func deleteTone(_ palette: Palette) throws -> (r: Int, g: Int, b: Int) {
        let tone = palette.dueTone(urgency: .overdue, isDone: false).background
        let swatch = try #require(Raster(rendering:
            Rectangle().fill(tone).frame(width: 8, height: 8).background(Color.white)
        ))
        return swatch.pixel(x: 4, y: 4)
    }

    @Test func aRowAtRestDrawsNoneOfItsDeleteButton() throws {
        let store = TestBoard.store()
        var task = try #require(store[TestBoard.dragDrop])
        // Every box unticked: a ticked one fills with the accent, and the
        // claim is about the delete tone alone.
        task.subtasks = task.subtasks.map { SubTask(id: $0.id, text: $0.text) }
        #expect(task.subtasks.count >= 2, "the fixture needs rows to render")
        let palette = Palette(theme: ThemePresets.fallback(for: .light))
        let tone = try Self.deleteTone(palette)
        // The probe has to be able to tell the tone from the page under it, or
        // a pass would mean nothing.
        #expect(max(255 - tone.r, 255 - tone.g, 255 - tone.b) > 12,
                "the delete tone \(tone) is too close to white for the probe to see")

        let checklist = ChecklistView(task: task, scope: .sheet, metrics: .sheet)
            .environment(store)
            .environment(\.palette, palette)
            .frame(width: 360)
            .background(Color.white)
        let raster = try #require(Raster(rendering: checklist))
        #expect(raster.height >= 44 * task.subtasks.count, "the checklist did not render its rows")
        #expect(raster.count(near: tone, tolerance: 4) == 0,
                "the delete button is drawn on rows nobody has swiped")
    }
}
