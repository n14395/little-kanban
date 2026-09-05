import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import LittleKanban

/// Where a dragged card says it is going to land, and whether it is telling the
/// truth.
///
/// **The gap this started from:** a card in the air dimmed and the column under
/// the pointer lit up, and that was the whole of the feedback — *which list*,
/// never *where in it*, which is the entire content of a reorder.
///
/// **The gap that turned up once there was a caret to watch it:** a drop that
/// names a *card* can only ever mean one of the two gaps beside it, and the rule
/// that picked which one was the direction the drag came from. That rule cannot
/// name the head of a list. A card dragged from anywhere earlier in board order
/// onto the first card of a later column landed *after* it, so no gesture
/// existed that put a card at the top of another column — and the caret,
/// faithfully drawing that rule, kept appearing on the far side of the card the
/// pointer was on.
///
/// A caret now names a **gap**, set by whichever half of whichever card the
/// pointer is in, and `drop(_:at:)` inserts into exactly that gap. Nothing is
/// inferred from where the card came from, which is why most of what follows is
/// about the two ends of a list.
@MainActor
@Suite struct DropCaretTests {
    private let backlog = BoardColumn.backlog.id
    private let upNext = BoardColumn.upNext.id

    private func order(_ store: BoardStore, in columnID: BoardColumn.ID) -> [TaskItem.ID] {
        store.visibleTasks(in: columnID).map(\.id)
    }

    // MARK: The caret is where the pointer is

    @Test func theCaretIsWhicheverHalfOfWhicheverCardThePointerIsIn() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.widget

        store.dropTargetCaret = .above(TestBoard.cafe)
        #expect(store.dropCaret == .above(TestBoard.cafe))

        store.dropTargetCaret = .below(TestBoard.cafe)
        #expect(store.dropCaret == .below(TestBoard.cafe))
    }

    /// **The one that could not be done at all.** `widget` is in the Inbox and
    /// sits at index 0; `offline` is the first card in Up Next and sits at
    /// index 3. Under the old rule — *after* the target when the drag came from
    /// above it — dropping the first onto the second put it second in Up Next,
    /// and there was no drag anywhere on the board that made it first.
    @Test func aCardCanBeDroppedAtTheHeadOfAnotherList() {
        let store = TestBoard.store()
        #expect(order(store, in: upNext).first == TestBoard.offline)

        store.drop(TestBoard.widget, at: .above(TestBoard.offline))

        #expect(order(store, in: upNext).first == TestBoard.widget)
        #expect(store[TestBoard.widget]?.columnID == upNext)
    }

    @Test func aCardCanBeDroppedAtTheFootOfAnotherList() throws {
        let store = TestBoard.store()
        let last = try #require(order(store, in: upNext).last)

        store.drop(TestBoard.widget, at: .below(last))

        #expect(order(store, in: upNext).last == TestBoard.widget)
    }

    /// Between two cards, from either side of the gap: one gap, named by the
    /// card above it or the card below it, has to land in the same place.
    @Test func theTwoNamesForOneGapMeanTheSamePlace() {
        for caret in [DropCaret.below(TestBoard.dragDrop), .above(TestBoard.cafe)] {
            let store = TestBoard.store()
            #expect(order(store, in: backlog) == [TestBoard.dragDrop, TestBoard.cafe])

            store.drop(TestBoard.widget, at: caret)

            #expect(
                order(store, in: backlog) == [TestBoard.dragDrop, TestBoard.widget, TestBoard.cafe],
                "\(caret) did not land between the two"
            )
        }
    }

    /// Nothing is read off the direction of travel any more, so a card coming
    /// from below lands in the gap it was pointed at rather than the other one.
    @Test func aCardComingFromBelowLandsWhereTheCaretIs() {
        let store = TestBoard.store()
        // `palette` is in Done, which is past Backlog in board order.
        store.drop(TestBoard.palette, at: .above(TestBoard.dragDrop))
        #expect(order(store, in: backlog).first == TestBoard.palette)
    }

    // MARK: Standing still

    /// A drop into the gap the card is already in moves nothing — and, more to
    /// the point, writes nothing: a ⌘Z that takes back a card which never moved
    /// is worse than no ⌘Z at all.
    @Test func droppingWhereTheCardAlreadyIsCostsNothing() {
        for caret in [DropCaret.above(TestBoard.cafe), .below(TestBoard.dragDrop)] {
            let (store, undo) = TestBoard.undoing()
            let before = store.tasks

            store.drop(TestBoard.dragDrop, at: caret)

            #expect(store.tasks == before, "\(caret) moved a card that was already there")
            #expect(undo.canUndo == false, "\(caret) registered a step for standing still")
        }
    }

    @Test func thereIsNoCaretOnTheCardInTheAir() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.cafe
        store.dropTargetCaret = .above(TestBoard.cafe)
        #expect(store.dropCaret == nil)
        store.dropTargetCaret = .below(TestBoard.cafe)
        #expect(store.dropCaret == nil)
    }

    /// **The iPad's half.** `onDragSessionUpdated` is macOS 26 but iOS *27*, so
    /// on an iPad running 26 nothing set `draggingID` at all — and a caret that
    /// asked for it first drew nothing, on the one surface where a whole board
    /// of cards is within reach of a finger. The card in the air is something
    /// the caret *checks against* now rather than something it needs: the
    /// pointer is over a gap either way. `BoardTaskCard` also sets the flag from
    /// the payload ask on that build, which brings the dimmed card and the
    /// column highlight back with it.
    @Test func theCaretIsDrawnWithoutADragSessionToNameTheCard() {
        let store = TestBoard.store()
        #expect(store.draggingID == nil)
        store.dropTargetCaret = .above(TestBoard.cafe)
        #expect(store.dropCaret == .above(TestBoard.cafe))
    }

    // MARK: A list's own ground, which is the foot of it

    /// **A drop on a column's ground lands at the bottom, wherever the card came
    /// from.** The ground briefly kept the row instead — a card third in one
    /// column landed third in the next — and under a finger that is a card
    /// jumping several rows *up* a list the user was pointing below the end of.
    /// The space under the cards is what a person aims at, and the bottom is
    /// what that space means.
    @Test func aColumnsGroundLandsAtTheFoot() throws {
        let store = Self.deeper()
        let third = order(store, in: backlog)[2]
        store.draggingID = third
        store.dropTargetColumnID = upNext

        let foot = try #require(order(store, in: upNext).last)
        #expect(store.dropCaret == .below(foot))

        store.drop(third, onGroundOf: store.placement(forColumn: upNext))
        #expect(order(store, in: upNext).last == third)
    }

    /// The Inbox panel is a list like any other, and its ground says the same
    /// thing — including for the phone's sheet, which is the same drop.
    @Test func theInboxPanelsGroundLandsAtTheFootToo() throws {
        let store = Self.deeper()
        let second = order(store, in: backlog)[1]
        store.draggingID = second
        store.isInboxDropTarget = true

        let foot = try #require(store.inboxTasks.map(\.id).last)
        #expect(store.dropCaret == .below(foot))

        store.drop(second, onGroundOf: .inbox)
        #expect(store.inboxTasks.map(\.id).last == second)
    }

    @Test func anInboxCardsGroundDropPreviewsAndMovesItToTheFoot() throws {
        let store = Self.deeper()
        let first = try #require(store.inboxTasks.first?.id)
        let last = try #require(store.inboxTasks.last?.id)
        #expect(first != last, "the fixture needs an Inbox card to move")
        store.draggingID = first
        store.isInboxDropTarget = true

        #expect(store.dropCaret == .below(last))
        #expect(store.dropPreview(in: .inbox)?.index == store.inboxTasks.count)

        store.drop(first, onGroundOf: .inbox)
        #expect(store.inboxTasks.last?.id == first)
    }

    /// The rule does not read the row the card is leaving, so the *last* card of
    /// a long list lands at the foot of a short one exactly as the first card of
    /// it does. Both directions, because "always the foot" is only a rule if the
    /// card's own position cannot change the answer.
    @Test func theRowTheCardCameFromChangesNothing() throws {
        let done = BoardColumn.done.id
        for index in [0, 2] {
            let store = Self.deeper()
            let card = order(store, in: backlog)[index]
            store.draggingID = card
            store.dropTargetColumnID = done
            let foot = try #require(order(store, in: done).last)
            #expect(store.dropCaret == .below(foot), "the caret moved with the card's own row")

            store.drop(card, onGroundOf: store.placement(forColumn: done))
            #expect(order(store, in: done).last == card, "a card from row \(index) missed the foot")
        }
    }

    /// An empty list has no card to hang a mark off — a caret is drawn *by* a
    /// card, on one of its edges — so the column highlight is the whole of the
    /// feedback, and the drop still lands.
    @Test func anEmptyGroundDrawsNoCaretAndStillTakesTheCard() throws {
        let store = TestBoard.store()
        // Every column in the seed board has a card in it, so the empty one is
        // made here — which is also the state a column is in the moment the
        // add-column tile builds it.
        let empty = try #require(store.addColumn(named: "Parked"))
        store.draggingID = TestBoard.dragDrop
        store.dropTargetColumnID = empty
        #expect(store.dropCaret == nil)

        store.drop(TestBoard.dragDrop, onGroundOf: store.placement(forColumn: empty))
        #expect(order(store, in: empty) == [TestBoard.dragDrop])
    }

    /// The foot is a default for a drop that did not say where, and nothing
    /// more: a pointer inside a card has named a gap, and the gap wins.
    @Test func aPointerInsideACardBeatsTheGround() {
        let store = Self.deeper()
        let third = order(store, in: backlog)[2]
        store.draggingID = third
        store.dropTargetColumnID = upNext
        store.dropTargetCaret = .above(order(store, in: upNext)[0])

        #expect(store.dropCaret == .above(order(store, in: upNext)[0]))

        store.drop(third, at: .above(order(store, in: upNext)[0]))
        #expect(order(store, in: upNext).first == third)
    }

    /// **Every route agrees.** The move-to menu, the sidebar's board rows and a
    /// bulk move all go through `move(_:to:)` and land at the foot, and a drop
    /// on the ground is now that same call — so a card arrives at the same place
    /// whether it was carried there or sent.
    @Test func theMoveToMenuLandsAtTheFootToo() {
        let store = Self.deeper()
        let third = order(store, in: backlog)[2]

        store.move(third, to: upNext)

        #expect(order(store, in: upNext).last == third)
    }

    /// A board with a third row to keep: the seed fixture's columns hold one
    /// and two cards, which cannot tell "kept its row" from "landed at the
    /// foot". The fillers go in after whatever is already there, so the
    /// fixture's own cards keep the places the rest of this file names them by.
    private static func deeper() -> BoardStore {
        var tasks = TestBoard.tasks
        var n: UInt8 = 0x20
        for columnID in [BoardColumn.backlog.id, BoardColumn.upNext.id, BoardColumn.inbox.id] {
            for row in 0..<3 {
                tasks.append(TaskItem(
                    id: TestBoard.taskID(n), code: "NW-2\(n)", columnID: columnID,
                    title: "Filler \(row) of \(columnID)",
                    createdAt: TestBoard.at(Int(n)), updatedAt: TestBoard.at(Int(n))
                ))
                n += 1
            }
        }
        return TestBoard.store(tasks: tasks)
    }

    /// The case the caret has to stay *out* of. A drop on the ground of the
    /// column a card is already in is aimed at where the card already is, and
    /// the drop returns without moving it — so a caret anywhere would be
    /// promising a trip that never happens. Keeping the row it is already on is
    /// keeping it where it is.
    @Test func aColumnsOwnGroundOffersNoCaretToACardAlreadyInIt() {
        let (store, undo) = TestBoard.undoing()
        let before = order(store, in: backlog)
        store.draggingID = TestBoard.dragDrop
        store.dropTargetColumnID = backlog
        #expect(store.dropCaret == nil)

        store.drop(TestBoard.dragDrop, onGroundOf: store.placement(forColumn: backlog))
        #expect(order(store, in: backlog) == before, "the drop that draws no caret moved a card")
        #expect(undo.canUndo == false, "the drop that draws no caret registered a step")
    }

    // MARK: Nothing to draw

    @Test func thereIsNoCaretWithoutAPointerOverAnything() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.dragDrop
        #expect(store.dropCaret == nil)
    }

    /// Dragging is off wherever the cards on screen are not in board order — a
    /// drop has nothing it could mean there — and the caret goes with it rather
    /// than drawing a promise the drop will refuse.
    ///
    /// A saved view, then, and no longer a query: the search draws a panel over
    /// the board instead of narrowing it, so the rows underneath are still the
    /// board's own order. `SearchScopingTests` has the rule itself.
    @Test func aSurfaceThatRefusesADragDrawsNoCaret() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.dragDrop
        store.dropTargetCaret = .above(TestBoard.cafe)
        #expect(store.dropCaret != nil)

        store.query = "café"
        #expect(store.allowsCardDrag, "a query stopped a drag it no longer hides anything from")
        #expect(store.dropCaret != nil)

        store.activeView = .upcoming
        #expect(store.allowsCardDrag == false)
        #expect(store.dropCaret == nil)
    }

    @Test func endingALiftClearsTheCaret() {
        let store = TestBoard.store()
        store.draggingID = TestBoard.dragDrop
        store.dropTargetCaret = .above(TestBoard.cafe)

        store.endDrag()

        #expect(store.dropTargetCaret == nil)
        #expect(store.dropCaret == nil)
    }

    // MARK: The mark itself

    /// The rule above is only worth having if the card draws it on the edge it
    /// names, and *which edge* is the one thing no store test can see. So the
    /// card is rendered with the caret above and again with it below, and the
    /// **accent-coloured row** is found in each: `.above` has to land in the top
    /// of the card and `.below` in the bottom. Swapping `.top` and `.bottom` in
    /// the card fails this and nothing else, which is what it is for.
    ///
    /// **The mark is looked for rather than diffed against a plain card.** The
    /// first spelling compared a marked render with an unmarked one and asked
    /// which rows changed, which is only sound if nothing else about the card
    /// changed between the two — and in a full parallel run something does: the
    /// same card came out 83pt here and 110pt on its own, and a third of it
    /// differed for reasons that had nothing to do with a caret. A full-width
    /// run of the accent colour is the caret and nothing else on a card is, so
    /// one picture is enough and whatever else moved does not matter.
    ///
    /// `AddColumnStripTests` renders for the same reason: some claims are about
    /// pixels, and only a measurement can tell a right one from a wrong one.
    @Test func theCaretIsDrawnOnTheEdgeItNames() throws {
        let above = try #require(Self.render(caret: .above(TestBoard.cafe)))
        let below = try #require(Self.render(caret: .below(TestBoard.cafe)))
        let height = above.height

        let top = try #require(Self.accentRows(in: above), "no caret was drawn above")
        let bottom = try #require(Self.accentRows(in: below), "no caret was drawn below")

        // A line, not a wash: three points of card, give or take what the
        // capsule's antialiasing bleeds into the row either side of it.
        #expect(top.count <= 8, "the caret above covers \(top.count) rows of \(height)")
        #expect(bottom.count <= 8, "the caret below covers \(bottom.count) rows of \(height)")

        let ceiling = Double(height) * 0.2
        #expect(Double(top.upperBound) < ceiling,
                "the caret for `.above` is \(top) of \(height) rows down — not on the top edge")
        #expect(Double(bottom.lowerBound) > Double(height) - ceiling,
                "the caret for `.below` is \(bottom) of \(height) rows down — not on the bottom edge")
    }

    /// The rows that are mostly accent, counted downwards from the top edge.
    /// Nothing else on a card paints a whole row of it — the label chip is a
    /// wash of it a few points wide, and the priority dot is seven across.
    @MainActor
    private static func accentRows(in raster: Raster) -> ClosedRange<Int>? {
        let accent = Palette(theme: ThemePresets.fallback(for: .light)).accent.resolve(in: EnvironmentValues())
        let (r, g, b) = (accent.red, accent.green, accent.blue)
        var rows: [Int] = []
        for row in 0..<raster.height where raster.fraction(ofRow: row, near: (r, g, b)) > 0.5 {
            rows.append(fromTop ? row : raster.height - 1 - row)
        }
        guard let low = rows.min(), let high = rows.max() else { return nil }
        return low...high
    }

    /// One card, with the store put into the state that draws `caret` — **the
    /// card this platform's board draws**. Not only for fidelity: on iOS 26,
    /// `ImageRenderer` paints its yellow "unsupported" placeholder over the
    /// bounds of any `UIViewRepresentable` in the tree, and `BoardTaskCard`
    /// carries one — `pointerContextMenu`'s whole-card `PointerSensor` — so
    /// its raster comes out placeholder from edge to edge, caret and all.
    /// `PhoneTaskCard` draws the same caret contract and carries no
    /// representable (the phone's pointer menu is `PhoneTaskRowActions`, a
    /// modifier the *list* applies), so the iOS run measures that card, and
    /// `BoardTaskCard`'s shared caret logic stays pinned by the macOS run.
    @MainActor
    private static func render(caret: DropCaret?) -> Raster? {
        let store = TestBoard.store()
        store.dropTargetCaret = caret
        #if os(iOS)
        // The caret is `ReorderableCard`'s to draw on the phone — the list
        // applies it to the row, the card itself carries none.
        let bare = AnyView(PhoneTaskCard(task: store[TestBoard.cafe]!)
            .modifier(ReorderableCard(task: store[TestBoard.cafe]!)))
        #else
        let bare = AnyView(BoardTaskCard(task: store[TestBoard.cafe]!))
        #endif
        let card = bare
            .frame(width: 260)
            .environment(store)
            .environment(\.palette, Palette(theme: ThemePresets.fallback(for: .light)))
            .environment(\.dayClock, DayClock(today: TestBoard.dueDay))
        return Raster(rendering: card)
    }

    /// Whether the first row of a raster is the top of the picture.
    ///
    /// `CGBitmapContext`'s row order is a detail nobody should have to hold in
    /// their head, and a test that guessed it wrong would pass while the caret
    /// was drawn on the wrong edge — which is the one thing this file exists to
    /// catch. So it is measured rather than assumed: a tile that is black on
    /// top and white below is rendered, and whichever end came out dark is the
    /// top.
    @MainActor
    private static let fromTop: Bool = {
        let probe = VStack(spacing: 0) {
            Color.black
            Color.white
        }
        .frame(width: 8, height: 8)
        guard let raster = Raster(rendering: probe) else { return true }
        let first = raster.row(0).reduce(0) { $0 + Int($1) }
        let last = raster.row(raster.height - 1).reduce(0) { $0 + Int($1) }
        return first < last
    }()

    /// A rendered view as raw RGBA rows.
    private struct Raster {
        let width: Int
        let height: Int
        private let bytes: [UInt8]

        @MainActor
        init?(rendering view: some View) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.cgImage, image.width > 0, image.height > 0 else { return nil }
            // Locals rather than the properties: the closure below would
            // otherwise capture a `self` that is not finished being built.
            let w = image.width, h = image.height
            var buffer = [UInt8](repeating: 0, count: w * h * 4)
            let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(
                    data: raw.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            width = w
            height = h
            bytes = buffer
        }

        func row(_ index: Int) -> ArraySlice<UInt8> {
            bytes[(index * width * 4)..<((index + 1) * width * 4)]
        }

        /// How much of a row is within a rounding step of one colour.
        func fraction(ofRow index: Int, near colour: (Float, Float, Float)) -> Double {
            let target = [colour.0, colour.1, colour.2].map { UInt8(max(0, min(255, $0 * 255))) }
            let start = index * width * 4
            var hits = 0
            for x in 0..<width {
                let pixel = start + x * 4
                let close = (0..<3).allSatisfy { channel in
                    let value = Int(bytes[pixel + channel]), want = Int(target[channel])
                    return abs(value - want) <= 12
                }
                if close { hits += 1 }
            }
            return Double(hits) / Double(width)
        }
    }
}
