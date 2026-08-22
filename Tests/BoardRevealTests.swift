import Foundation
import Testing
@testable import Simple_Kanban

/// How far the board moves when focus arrives, and who decides.
///
/// The reported bug: clicking a card scrolled the board towards it, so the card
/// slid out from under the pointer at the moment it was being aimed at. The
/// scroll views watched `focus` itself, and a click sets focus exactly as an
/// arrow key does — which made the two the same event when they are not the
/// same thing at all. A key can put focus on a card in a column that is
/// entirely off screen; a click has already landed on one the user could see.
///
/// So the route that moved focus says how much of the board to move with it —
/// ``BoardReveal`` — and the answers are different. A key asks for the column
/// **centred**, because there has to be board on both sides to carry on
/// arrowing through. A click asks only that the column be shown **whole**, and
/// for a column that is whole already, for nothing.
///
/// **What can and cannot be asserted here.** `scrollTo` goes to a
/// `ScrollViewProxy`: no state to read back, no record of having been called.
/// Whether the board moved is a question about pixels. So this pins the two
/// things that *are* values — the wiring, read off the source the way
/// `DragReorderTests` reads the drop closures, and the arithmetic that keeps the
/// reveal margin free.
///
/// The behaviour itself was measured against the built app through the
/// accessibility API — `AXPress` on a card and a key posted to the process,
/// neither of which touches the host's pointer or keyboard. In a 372pt board
/// with 272pt columns: clicking a card in a column already whole moved the board
/// 0pt; clicking one in a column clipped at either edge left that column 16pt
/// from the edge it came in past, exactly `revealInset`; and ← and → left the
/// column centred to the point.
@MainActor
@Suite struct BoardRevealTests {
    /// Every surface that scrolls a card into view, and how many `scrollTo`
    /// calls it is allowed. The counts are here so a *new* scroll cannot be
    /// added without this test being read: the composer's and the add-column
    /// tile's are the ones that are not about focus at all.
    private static let surfaces = [
        "Shared/BoardScrollView.swift": 4,
        "Shared/BoardColumnView.swift": 3,
        "Shared/InboxPanel.swift": 2,
    ]

    private func file(_ path: String) -> SourceFile? {
        SourceTree.files().first { $0.path == path }
    }

    /// The block a surface hangs off the reveal — where both manners have to be
    /// answered, and where the anchors are.
    private func revealBlock(of path: String) -> String? {
        guard let file = file(path) else {
            Issue.record("\(path) has moved or gone")
            return nil
        }
        let source = file.source
        guard let head = source.range(of: ".onChange(of: reveal)") else {
            Issue.record("\(path) does not follow the reveal, so nothing can scroll it")
            return nil
        }
        return file.block(after: source.distance(from: source.startIndex, to: head.lowerBound))
    }

    // MARK: The wiring

    /// The rule, over every surface at once: a card is brought into view because
    /// a route *asked* for it, never because focus moved.
    @Test func noSurfaceScrollsBecauseFocusMoved() {
        guard SourceTree.isReachable else { return }
        for (path, scrolls) in Self.surfaces {
            guard let file = file(path) else { continue }
            let source = file.source
            #expect(source.contains("proxy.scrollTo"), "\(path) no longer scrolls anything")
            #expect(
                source.components(separatedBy: "proxy.scrollTo").count - 1 == scrolls,
                "\(path) has gained or lost a scroll — is the new one driven by a click?"
            )
            // The one that must not exist: a scroll hung off the focus itself.
            let onFocus = file.block(
                after: source.distance(
                    from: source.startIndex,
                    to: source.range(of: ".onChange(of: focus)")?.lowerBound ?? source.endIndex
                )
            )
            #expect(onFocus.contains("scrollTo") == false,
                    "\(path) scrolls when focus moves, so a click scrolls it: \(onFocus)")
        }
    }

    /// And each of them answers **both** manners, with the anchor each one
    /// means. Without this the rule above could be satisfied by dropping the
    /// scroll entirely and stranding the arrow keys, or by answering a click
    /// with the centring it was the whole complaint about.
    @Test func everySurfaceAnswersBothManners() {
        guard SourceTree.isReachable else { return }
        for path in Self.surfaces.keys {
            guard let body = revealBlock(of: path) else { continue }
            #expect(body.contains("case .centred"), "\(path) does not answer a key: \(body)")
            #expect(body.contains("case .intoView"), "\(path) does not answer a click: \(body)")
            #expect(body.contains("anchor: .center"),
                    "\(path) does not centre what a key revealed: \(body)")

            // The click's scroll is the one with no anchor, which is the
            // minimum that makes the target whole — and nothing at all when it
            // is whole already. An anchor of any kind would move the board on
            // every click again.
            guard let click = body.range(of: "case .intoView") else { continue }
            let arm = body[click.upperBound...]
            #expect(arm.contains("anchor") == false,
                    "\(path) gives a click an anchor, so it scrolls a whole column: \(arm)")
        }
    }

    /// Who raises one, and which manner each is allowed. Two routes do: the
    /// keyboard, both ways it moves focus, and the card's own click.
    @Test func theKeyboardCentresAndAClickOnlyReveals() {
        guard SourceTree.isReachable else { return }
        let writers = SourceTree.files().filter { $0.source.contains("reveal = ") }
        #expect(
            writers.map(\.path).sorted() == ["Shared/BoardKeyboard.swift", "Shared/BoardTaskCard.swift"],
            "the set of things that move the board has changed: \(writers.map(\.path).sorted())"
        )

        for writer in writers {
            let raises = writer.source.components(separatedBy: "reveal = ").dropFirst()
            for raise in raises {
                let manner = raise.prefix(60)
                switch writer.path {
                case "Shared/BoardKeyboard.swift":
                    #expect(manner.contains("centred"),
                            "the keyboard raises something other than a centred reveal: \(manner)")
                default:
                    #expect(manner.contains("intoView"),
                            "a click raises something other than an into-view reveal: \(manner)")
                }
            }
        }
    }

    /// A click takes the keyboard as well as asking for the reveal — the two
    /// used to be one line, and dropping either leaves a card that cannot be
    /// arrowed away from or a board that will not finish showing a column.
    @Test func aClickTakesTheKeyboardAndAsksForNothingMore() {
        guard SourceTree.isReachable else { return }
        guard let card = file("Shared/BoardTaskCard.swift") else {
            Issue.record("the board card has moved file")
            return
        }
        let source = card.source
        guard let head = source.range(of: "private func click()") else {
            Issue.record("the card no longer has a click")
            return
        }
        let body = card.block(after: source.distance(from: source.startIndex, to: head.lowerBound))
        #expect(body.contains("focus?.wrappedValue = task.id"), "a click no longer takes the keyboard")
        #expect(body.contains("relay?.reveal = .intoView(task.id)"),
                "a click no longer asks for its column: \(body)")
    }

    // MARK: The margin, and what it costs

    /// `scrollTo` has no notion of a margin, so a column is scrolled to wrapped
    /// in `revealInset` of padding and the wrapper is what has to fit. The
    /// wrapper is only free if the padding is taken back out of the spacing
    /// either side of it — otherwise every column on the board moves 32pt
    /// apart, which is a redesign rather than a scroll fix.
    ///
    /// Both derived numbers are negative at the current inset. That is the
    /// point of asking this as arithmetic rather than as a sign.
    @Test func theRevealMarginCostsTheLayoutNothing() {
        #expect(
            BoardScrollView.revealInset * 2 + BoardScrollView.columnSpacing == BoardScrollView.gutter,
            "two columns no longer sit \(BoardScrollView.gutter)pt apart"
        )
        #expect(
            BoardScrollView.revealInset + BoardScrollView.stripInset == BoardScrollView.stripPadding,
            "the strip no longer starts \(BoardScrollView.stripPadding)pt in"
        )
        #expect(BoardScrollView.revealInset > 0, "a reveal leaves the column flush against the edge")
    }
}
