import Foundation
import Testing
@testable import Simple_Kanban

/// When the board's header runs out of width and folds its search field into a
/// button.
///
/// **The width the bar gets is not the width of the screen.** On the iPad the
/// bar sits in the split view's detail column, which is whatever is left after
/// the source list and the Inbox panel have taken theirs — and under Stage
/// Manager the window itself is any width the user drags it to. So the bar is
/// measured and the decision is arithmetic, and this is the arithmetic: at what
/// width the field folds, and that it folds *before* the row it is in overflows
/// rather than after.
///
/// The other half — that the button opens a row, that the row takes the
/// keyboard, that a query keeps its field — is a claim about a first responder
/// and a live view tree, which is `UITests/ToolbarFoldTests`.
@MainActor
@Suite struct ToolbarFoldTests {
    /// The narrowest bar the field still fits in, found by asking rather than by
    /// restating the sum: a test that added the same numbers up again would
    /// agree with a mistake.
    private func threshold(
        _ metrics: BoardToolbar.Metrics,
        sidebarToggle: Bool = true, inboxToggle: Bool = true,
        leadingInset: CGFloat = 0, factor: CGFloat = 1
    ) -> CGFloat {
        var width: CGFloat = 0
        while width < 4000 {
            if metrics.searchFits(barWidth: width, leadingInset: leadingInset,
                                  sidebarToggle: sidebarToggle, inboxToggle: inboxToggle,
                                  factor: factor) {
                return width
            }
            width += 1
        }
        return width
    }

    // MARK: The line itself

    /// The one that matters: the field goes *before* the row is out of room, not
    /// when it is already overflowing. Everything but the name is a fixed size,
    /// so the row breaks at the moment the name reaches zero — and folding there
    /// would mean the last hundred points of squeeze were spent turning the
    /// board's name into an ellipsis beside a 220pt field.
    @Test func theFieldFoldsBeforeTheRowOverflows() {
        let pad = BoardToolbar.Metrics.pad
        let folds = threshold(pad)
        // The same row with nothing at all left for the name, which is the width
        // it would otherwise be clipped at.
        let overflows = folds - pad.titleFloor

        #expect(folds > overflows)
        #expect(!pad.searchFits(barWidth: overflows, leadingInset: 0,
                                sidebarToggle: true, inboxToggle: true, factor: 1),
                "the field was still in the bar at the width the bar runs out of room")
        // And the name is left something worth reading rather than a floor of
        // one character that only technically clears the check above: 160pt is
        // about fourteen characters of a 26pt serif, measured off the app.
        #expect(pad.titleFloor >= 150)
    }

    /// Wider is never worse. A predicate that flipped back the other way at some
    /// width would be a bar that folds, unfolds and folds again as a window is
    /// dragged — which is the shape of every layout feedback loop, and the
    /// reason this decision is an estimate rather than a measurement of the
    /// squeeze itself.
    @Test func theDecisionIsMonotonicInWidth() {
        let pad = BoardToolbar.Metrics.pad
        let folds = threshold(pad)
        for width in stride(from: folds, through: folds + 600, by: 20) {
            #expect(pad.searchFits(barWidth: width, leadingInset: 0,
                                   sidebarToggle: true, inboxToggle: true, factor: 1),
                    "the field folded again at \(width), having fitted at \(folds)")
        }
        for width in stride(from: max(0, folds - 600), to: folds, by: 20) {
            #expect(!pad.searchFits(barWidth: width, leadingInset: 0,
                                    sidebarToggle: true, inboxToggle: true, factor: 1),
                    "the field fitted at \(width), below the \(folds) it needs")
        }
    }

    // MARK: Where the line falls on real iPads

    /// A 13" iPad in portrait keeps its field with the board to itself — 1032pt,
    /// which is what it gets, since the source list comes over the board in
    /// portrait rather than beside it — and keeps it with *one* of the two
    /// columns beside the board as well.
    ///
    /// The second half is where the row got easier: the bar used to fold at 712
    /// with the Inbox panel out, back when capture was a labelled **New task**
    /// button. As a circle it claims the row's own 44pt square instead of 117,
    /// which is 73 points back to the name and a fold line 73 points lower.
    ///
    /// **The panel case clears the line by twelve points**, and that is stated
    /// rather than hidden: it is the one shape here that is close enough to flip
    /// if any of these numbers moves, which is precisely what this should report
    /// when it does.
    @Test func theBigIPadInPortraitKeepsItsField() {
        let pad = BoardToolbar.Metrics.pad
        for width in [1032, 1032 - Int(InboxPanel.Metrics.pad.width), 1032 - 300, 1376 - 300] {
            #expect(pad.searchFits(barWidth: CGFloat(width), leadingInset: 0,
                                   sidebarToggle: true, inboxToggle: true, factor: 1),
                    "the field folded at \(width), which is not a squeezed bar")
        }
    }

    /// The capture button is the iPad's, and the desk's absence of one is a
    /// `nil` in the preset rather than an `#if os()` in the body — the same
    /// shape `ColumnEditorMetrics.arrowEdge` uses. It costs the row its own
    /// width and a gap, so it moves the line like anything else in there.
    @Test func captureBelongsToTheIPadAndCostsTheRowItsWidth() {
        var withoutIt = BoardToolbar.Metrics.pad
        withoutIt.capture = nil

        #expect(BoardToolbar.Metrics.desk.capture == nil)
        #expect(BoardToolbar.Metrics.pad.capture == 44)
        #expect(threshold(withoutIt) < threshold(BoardToolbar.Metrics.pad))
    }

    /// Both columns at once is another matter: the source list and the Inbox
    /// panel together leave a 13" in portrait 412pt, which is a board and not
    /// much else. An 11" in portrait needs only the source list to get there.
    @Test func theSqueezedShapesFold() {
        let pad = BoardToolbar.Metrics.pad
        #expect(!pad.searchFits(barWidth: 1032 - 300 - InboxPanel.Metrics.pad.width,
                                leadingInset: 0,
                                sidebarToggle: true, inboxToggle: true, factor: 1))
        #expect(!pad.searchFits(barWidth: 834 - 300, leadingInset: 0,
                                sidebarToggle: true, inboxToggle: true, factor: 1))
    }

    // MARK: What else claims the row

    /// The Inbox toggle is only beside a board — on a saved view there is no
    /// panel for it to open — and the toggle it stands next to is only there on
    /// the iPad. Both are room the field does not have to find, so both move the
    /// line.
    @Test func eachControlInTheRowMovesTheLine() {
        let pad = BoardToolbar.Metrics.pad
        let both = threshold(pad)
        #expect(threshold(pad, inboxToggle: false) < both)
        #expect(threshold(pad, sidebarToggle: false) < both)
        #expect(threshold(pad, sidebarToggle: false, inboxToggle: false) < threshold(pad, inboxToggle: false))
    }

    /// The band the traffic lights sit in when the source list is not there to
    /// hold it is 68pt the row does not get — see `MacRootView`. It counts
    /// against the field like anything else in the row.
    @Test func theLeadingInsetCountsAgainstTheField() {
        let pad = BoardToolbar.Metrics.pad
        #expect(threshold(pad, leadingInset: 68) == threshold(pad) + 68)
    }

    /// Chrome grows with the type inside it, and a bar whose contents have grown
    /// runs out of width sooner. Nothing shrinks below the design's own sizes,
    /// so the smallest text size folds exactly where the default does.
    @Test func largerTypeFoldsSooner() {
        let pad = BoardToolbar.Metrics.pad
        #expect(threshold(pad, factor: 1.5) > threshold(pad))
        #expect(threshold(pad, factor: 0.8) == threshold(pad))
        // And past the caps it stops moving, the way the boxes themselves stop
        // growing — see `ChromeScale`.
        #expect(threshold(pad, factor: 3) == threshold(pad, factor: 1.6))
    }

    // MARK: The desk

    /// The desk does not fold, and the reason is not that its windows are wide.
    /// Its bar *is* the title bar: the traffic lights are moved onto the row it
    /// lays out at, `MacRootView` measures the bar to find that row, and a
    /// second row under it would take the lights down with it. What keeps the
    /// desk's bar in one piece instead is the window's own floor.
    @Test func theDeskKeepsItsFieldInTheBar() {
        #expect(BoardToolbar.Metrics.desk.foldsSearch == false)
        #expect(BoardToolbar.Metrics.pad.foldsSearch == true)
        // Which puts the whole weight on that floor, so this is the canary for
        // it: the narrowest board a window can be dragged to — no source list,
        // no panel, and the 68pt band the traffic lights need — still holds
        // everything in the bar with 100pt over for the board's name. Asked of
        // `MacRootView`'s own number, so that lowering the window's minimum
        // without looking at the bar is caught here rather than by somebody
        // dragging a window narrow.
        #if os(macOS)
        var desk = BoardToolbar.Metrics.desk
        desk.titleFloor = 100
        #expect(desk.searchFits(barWidth: MacRootView.floor(sidebar: false, inbox: false),
                                leadingInset: 68,
                                sidebarToggle: false, inboxToggle: true, factor: 1),
                "the desk's own minimum window no longer holds the bar it was measured for")
        #endif
    }
}
