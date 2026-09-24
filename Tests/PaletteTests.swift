// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

/// The palette every colour picker in the app draws from: what is in it, what
/// can be put in it, what can be taken out, and that it is still there next
/// time.
///
/// **The point of it is that there is one.** A colour saved while recolouring a
/// column has to be offered the next time a board or a label is recoloured, and
/// that is not a fact about any picker — it is a fact about the store, which is
/// the only thing all of them read. So it is asked here rather than in a view
/// test that could only ever check one surface.
@MainActor
@Suite struct PaletteTests {
    private func store() -> BoardStore { TestBoard.store(boards: TestBoard.boards) }

    // MARK: What a board starts with

    @Test func aFreshBoardOffersTheSixTheAppShipsWith() {
        let store = store()
        #expect(store.savedColors.map(\.swatch) == PaletteSwatch.seedPalette)
        #expect(store.savedColors.first?.swatch == .accent, "the accent is not first")
        #expect(store.savedColors.allSatisfy { $0.name != nil }, "a shipped colour has no name")
    }

    /// The six carry names as well as hexes: a swatch announced as "Colour 4"
    /// tells a reader its position and nothing about what choosing it does.
    ///
    /// They lived on `Board` until v16, when a board's mark became a glyph and
    /// the list moved to the type it had always been the seed for.
    @Test func theSeedIsTheOneTheRestOfTheAppNames() {
        #expect(PaletteSwatch.seedPalette == PaletteSwatch.seed.map(\.swatch))
        #expect(PaletteSwatch.seed.allSatisfy { $0.name?.isEmpty == false })
        #expect(Set(PaletteSwatch.seedPalette).count == PaletteSwatch.seedPalette.count,
                "the seed offers one colour twice")
    }

    // MARK: Saving

    @Test func aSavedColourJoinsTheEndOfTheList() {
        let store = store()
        let before = store.savedColors.count

        store.saveColor(.hex(0x123456))
        #expect(store.savedColors.count == before + 1)
        #expect(store.savedColors.last?.swatch == .hex(0x123456))
        // Mixed rather than shipped, so it answers to its hex.
        #expect(store.savedColors.last?.name == nil)
        #expect(store.savedColors.last?.displayName == "#123456")
    }

    /// **Saving a colour that is already saved is not a failure and not a
    /// duplicate.** The row is a set of choices; two swatches of one colour are
    /// one choice a person has to tell apart pixel by pixel.
    @Test func savingTheSameColourTwiceLeavesOneOfIt() {
        let store = store()
        store.saveColor(.hex(0x123456))
        let after = store.savedColors.count

        store.saveColor(.hex(0x123456))
        #expect(store.savedColors.count == after)
        // Including the ones it shipped with.
        store.saveColor(.hex(0xC2532F))
        #expect(store.savedColors.count == after)
    }

    /// Opacity is dropped on the way in: a picker offers a colour, and a 40%
    /// swatch draws as one colour on the palette's ground and another on a card.
    @Test func aSavedColourIsTheColourWithoutItsOpacity() {
        let store = store()
        store.saveColor(.rgb(0x123456, opacity: 0.4))
        #expect(store.savedColors.last?.swatch == .hex(0x123456))
        // And it counts as already saved next time round.
        store.saveColor(.hex(0x123456))
        #expect(store.savedColors.filter { $0.swatch == .hex(0x123456) }.count == 1)
    }

    // MARK: Deleting

    @Test func aDeletedColourLeavesEveryPicker() {
        let store = store()
        store.saveColor(.hex(0x123456))
        #expect(store.deleteSavedColor(.hex(0x123456)))
        #expect(store.savedColors.contains { $0.swatch == .hex(0x123456) } == false)
    }

    /// **Nothing wearing the colour changes.** A column and a label each store
    /// the colour itself rather than a place in this list, which is what makes
    /// deleting safe enough to do with no alert in front of it. Boards are out
    /// of this since v16: a board wears a glyph, and there is no colour of one
    /// to repaint.
    @Test func deletingAColourRepaintsNothing() throws {
        let store = store()
        let column = try #require(store.columns.first?.id)
        store.recolorColumn(column, to: .hex(0xC2532F))
        let second = try #require(store.columns.dropFirst().first?.id)
        store.recolorColumn(second, to: .hex(0xC2532F))

        #expect(store.deleteSavedColor(.hex(0xC2532F)))
        #expect(store.column(id: column)?.dot == .hex(0xC2532F))
        #expect(store.column(id: second)?.dot == .hex(0xC2532F))
    }

    /// The accent is not a hex but "whatever the accent theme is". Nothing else
    /// in the palette can say that, and a board wearing it would be left
    /// pointing at a choice no picker offers.
    @Test func theAccentCannotBeDeleted() {
        let store = store()
        #expect(store.deleteSavedColor(.accent) == false)
        #expect(store.savedColors.contains { $0.swatch == .accent })
        #expect(PaletteSwatch(.accent).isRemovable == false)
        #expect(PaletteSwatch(.hex(0xC2532F)).isRemovable)
    }

    @Test func aColourThatIsNotInThePaletteCannotBeDeletedFromIt() {
        let store = store()
        let before = store.savedColors
        #expect(store.deleteSavedColor(.hex(0xABCDEF)) == false)
        #expect(store.savedColors == before)
    }

    /// One ⌘Z each way. Both go through `undoable`, because a palette is the
    /// user's own work and a mis-aimed context menu is one click.
    @Test func savingAndDeletingAreEachOneUndoStep() {
        let (store, undo) = TestBoard.undoing(boards: TestBoard.boards)
        let seeded = store.savedColors

        // Grouped by hand: `TestBoard.undoing` turns `groupsByEvent` off, and a
        // registration outside a group is not a failed expectation — it throws
        // and takes the test host down with it.
        step(undo) { store.saveColor(.hex(0x123456)) }
        undo.undo()
        #expect(store.savedColors == seeded)

        undo.redo()
        var removed = false
        step(undo) { removed = store.deleteSavedColor(.hex(0x123456)) }
        #expect(removed)
        undo.undo()
        #expect(store.savedColors.contains { $0.swatch == .hex(0x123456) })
    }

    // MARK: What is still there next time

    @Test func aPaletteSurvivesARelaunch() throws {
        let temp = TempBoard()
        let first = TestBoard.store(boards: TestBoard.boards, file: temp.file)
        first.saveColor(.hex(0x123456))
        #expect(first.deleteSavedColor(.hex(0xC98A16)))
        first.saveNow()

        let second = BoardStore.restored(file: temp.file)
        #expect(second.savedColors.contains { $0.swatch == .hex(0x123456) })
        #expect(second.savedColors.contains { $0.swatch == .hex(0xC98A16) } == false)
    }

    /// A board file written before there was a palette gets the six back, not an
    /// empty picker — those six are exactly what the build that wrote it was
    /// offering. Same for a file hand-edited down to nothing: a picker with no
    /// colours in it offers no way to put one there.
    @Test func aFileWithNoPaletteGetsTheSix() throws {
        let snapshot = BoardSnapshot(
            tasks: [], boards: TestBoard.boards, labels: LabelDef.seed,
            nextSerial: BoardSnapshot.baseSerial
        )
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(snapshot)
        ) as? [String: Any] ?? [:]
        json["palette"] = nil
        json["version"] = 9
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try BoardFile.decode(data)
        #expect(decoded.snapshot.palette.map(\.swatch) == PaletteSwatch.seedPalette)
        #expect(decoded.migratedFrom == 9, "a v9 file was not migrated")
        #expect(decoded.snapshot.version == BoardSnapshot.currentVersion)

        #expect(BoardStore(savedColors: []).savedColors.map(\.swatch) == PaletteSwatch.seedPalette)
    }

    /// The palette is a field, so the version had to move — a build without it
    /// decodes a file with it perfectly well, drops the key, and writes the loss
    /// back. See `BoardMigration.migrate(v9:)`.
    ///
    /// Asserted as the *step* rather than as the tip: v10 is where the palette
    /// arrived and stays where it is however many versions land on top of it.
    @Test func thePaletteArrivedWithAVersionOfItsOwn() {
        #expect(BoardSnapshot.currentVersion >= 10)
        var v9 = BoardSnapshot(
            tasks: [], boards: TestBoard.boards, labels: LabelDef.seed,
            nextSerial: BoardSnapshot.baseSerial
        )
        v9.version = 9
        #expect(BoardSnapshot.migrate(v9: v9).version == 10)
        #expect(BoardSnapshot.migrate(v9: v9).palette.map(\.swatch) == PaletteSwatch.seedPalette)
    }
}
