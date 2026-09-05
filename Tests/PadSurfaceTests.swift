import Foundation
import SwiftUI
import Testing
@testable import Cardstock

#if os(iOS)
import UIKit

/// Which of the three panels an iPad window has to put away, and when.
///
/// The source list, the Inbox panel and the task editor are each a column wide,
/// two of them open on the left and one on the right, and a window that has not
/// got room for what is open and a board is a window where something has to
/// give way. What it used to do on either side was refuse to choose: the Inbox
/// panel declined to draw — a button that did not appear to work — and the
/// editor drew itself on top of the board. They take turns now: whichever was
/// opened keeps its room, and the panel furthest from it is the first to go.
///
/// **A value test because the decision is a number**, taken from widths the view
/// measures. `UITests/PadSidebarsTests` presses the buttons.
@MainActor
@Suite struct SidebarRoomTests {
    private let panel = InboxPanel.Metrics.pad.width
    /// Read off the view rather than copied: widening the panel changes every
    /// answer below, and a number spelled again here would go on agreeing with
    /// itself while the window it describes had moved.
    private let editor = PadRootView.baseInspectorWidth
    private let list = PadRootView.sidebarIdeal
    /// One `.pad` column and the strip's margins, which is `PadRootView`'s own
    /// floor spelled out — a board narrower than this is not a board.
    private let floor = BoardColumnView.Metrics.pad.width + 32

    /// A window with all three out unless told otherwise, which is the state
    /// every one of these questions is asked from.
    private func room(
        _ window: CGFloat, list: Bool = true, inbox: Bool = true, editor: Bool = true
    ) -> PadRootView.PanelRoom {
        PadRootView.PanelRoom(
            window: window, floor: floor,
            sourceList: list ? self.list : 0,
            inbox: inbox ? panel : 0,
            inspector: editor ? self.editor : 0
        )
    }

    private func yields(
        to opened: PadRootView.Panel, _ room: PadRootView.PanelRoom
    ) -> [PadRootView.Panel] {
        PadRootView.yields(to: opened, in: room)
    }

    // MARK: The case that must not close anything

    /// A 13" in landscape holds all four columns at once — 1376 less the list,
    /// the panel and the editor still leaves 408 for a board. It is the shape
    /// this layout was drawn for, and whichever panel is opened there, nothing
    /// else may move.
    @Test(arguments: PadRootView.Panel.allCases)
    func theBigIPadInLandscapeClosesNothing(opened: PadRootView.Panel) {
        #expect(yields(to: opened, room(1376)).isEmpty)
    }

    /// And nothing closes before the first layout pass, when there is no width
    /// to reason from. The other way round is a window that shuts one of its
    /// panels on the way in.
    @Test(arguments: PadRootView.Panel.allCases)
    func anUnmeasuredWindowClosesNothing(opened: PadRootView.Panel) {
        #expect(yields(to: opened, room(0)).isEmpty)
    }

    // MARK: Opening one of the two on the left

    /// **The editor collapses first**, and on an 11" in landscape that is the
    /// whole of it: 1194 holds any two of the three, so the two panels on the
    /// left go on sharing the window once the one on the right has gone. Making
    /// *them* take turns while a third column sat on the far side was answering
    /// the wrong question.
    @Test(arguments: [PadRootView.Panel.sourceList, .inbox])
    func openingAPanelOnTheLeftCollapsesTheEditorFirst(opened: PadRootView.Panel) {
        #expect(yields(to: opened, room(1194)) == [.inspector])
    }

    /// An 11" in portrait is the window that has room for one: 834 less the
    /// editor and either column is not a board, so opening a panel on the left
    /// takes the room from both of the others — and in that order.
    @Test func theSmallerIPadInPortraitEmptiesTheRestForIt() {
        #expect(yields(to: .inbox, room(834)) == [.inspector, .sourceList])
        #expect(yields(to: .sourceList, room(834)) == [.inspector, .inbox])
    }

    /// The two on the left still take turns when the editor is already away,
    /// which is the rule this one grew out of and the one `PadSidebarsTests`
    /// presses: a panel that is not open costs nothing, so it is skipped rather
    /// than counted as this window's answer — and the next one along gets asked.
    @Test func theTwoOnTheLeftStillTakeTurnsWithTheEditorAway() {
        #expect(yields(to: .inbox, room(834, editor: false)) == [.sourceList])
        #expect(yields(to: .sourceList, room(834, editor: false)) == [.inbox])
    }

    /// A source list the system has drawn *over* the board costs the board
    /// nothing, so it is not competing and it is not closed. The editor goes,
    /// and that is enough.
    @Test func aListDrawnOverTheBoardIsNotCompeting() {
        #expect(yields(to: .inbox, room(834, list: false)) == [.inspector])
    }

    // MARK: Opening the one on the right

    /// The same rule from the other side, which is the half that was missing:
    /// a card tapped on an 11" in landscape opens the editor, and the source
    /// list — the panel at the far end of the window — is what gives way. The
    /// Inbox stays, because closing it as well would be taking more than the
    /// editor needs.
    @Test func openingTheEditorTakesTheRoomFromTheFarSide() {
        #expect(yields(to: .inspector, room(1194)) == [.sourceList])
    }

    /// And where one is not enough, both go. An 11" in portrait with both
    /// panels out has nothing else to give.
    @Test func openingTheEditorOnANarrowWindowClosesBoth() {
        #expect(yields(to: .inspector, room(834)) == [.sourceList, .inbox])
    }

    /// The editor is the one panel that has an answer to being squeezed —
    /// `hasRoomBesideTheBoard` draws it over the board — but it is the last
    /// resort rather than the first: with nothing on the left to close, that is
    /// what is left, and this says the rule does not pretend otherwise.
    @Test func withNothingOnTheLeftTheEditorHasNothingToTake() {
        #expect(yields(to: .inspector, room(600, list: false, inbox: false)).isEmpty)
    }

    // MARK: The line itself

    /// The rule is the board's floor rather than a number of its own: a window
    /// one point above it holds all three, one point below does not.
    @Test func theLineIsExactlyTheBoardsFloor() {
        let exact = list + panel + editor + floor
        #expect(yields(to: .inbox, room(exact)).isEmpty)
        #expect(yields(to: .inbox, room(exact - 1)) == [.inspector])
    }

    /// **Never more than it takes.** Whatever closes, what is left has to be a
    /// window that holds the rest — and the panel that was opened has to still
    /// be in it. Asked of every iPad width and every combination of what was
    /// open, because the failure this guards against is a rule that closes one
    /// panel too few and leaves the thing the reader asked for squeezed out.
    @Test(arguments: [834.0, 1024, 1032, 1180, 1194, 1366, 1376] as [CGFloat])
    func whatIsLeftAlwaysHoldsTheRest(window: CGFloat) {
        for opened in PadRootView.Panel.allCases {
            for list in [true, false] {
                for inbox in [true, false] {
                    for editor in [true, false] {
                        var left = room(window, list: list, inbox: inbox, editor: editor)
                        let closing = yields(to: opened, left)
                        #expect(closing.contains(opened) == false,
                                "\(opened) closed the panel that was just opened")
                        for panel in closing { left = left.closing(panel) }
                        #expect(left.holdsWhatIsOpen,
                                "\(window) still has no board after closing \(closing)")
                    }
                }
            }
        }
    }

    /// The panel's own line counts the board and *not* the editor.
    ///
    /// The editor has an answer to being squeezed that the panel has not: it
    /// draws over the board. So an 11" in portrait — 834pt, less the panel's
    /// column — holds the Inbox with a task selected, even though 834 less the
    /// editor as well would not.
    @Test func thePanelCountsTheBoardAndNotTheInspector() {
        #expect(PadRootView.holdsTheInbox(detail: 834, panel: panel, floor: floor))
        #expect(PadRootView.holdsTheInbox(detail: panel + floor, panel: panel, floor: floor))
        #expect(!PadRootView.holdsTheInbox(detail: panel + floor - 1, panel: panel, floor: floor))
        #expect(PadRootView.holdsTheInbox(detail: 0, panel: panel, floor: floor))
    }

    /// The invariant between the two rules, and the way they broke it.
    ///
    /// Whatever closes to make room for the Inbox, the window it leaves has to
    /// be one the panel will actually draw in. It was not: an 11" in portrait
    /// with a task selected declined the panel at 834 − 384 − 320, so the Inbox
    /// button put the source list away and did nothing else, which is the same
    /// dead button the turn-taking was written to remove.
    @Test(arguments: [834.0, 1024, 1032, 1180, 1194, 1366, 1376] as [CGFloat])
    func whateverClosesForTheInboxLeavesRoomToDrawIt(window: CGFloat) {
        for list in [true, false] {
            for editor in [true, false] {
                var left = room(window, list: list, editor: editor)
                for panel in yields(to: .inbox, left) { left = left.closing(panel) }
                // What the split view leaves the detail column is the window
                // less whatever the list is still taking from it.
                #expect(
                    PadRootView.holdsTheInbox(
                        detail: window - left.sourceList, panel: panel, floor: floor
                    ),
                    "the panel still will not draw in what this leaves it"
                )
            }
        }
    }
}

/// Which of the two iOS layouts a window gets.
///
/// The rule was `horizontalSizeClass == .regular` and nothing else, which is
/// not "this is an iPad": a Max- or Plus-class iPhone reports a regular
/// horizontal size class in landscape, and one did — driven at 956×440, an
/// iPhone drew `PadRootView` with the split view's sidebar toggle, the
/// inspector and the board's column controls, and never drew the three-up
/// landscape board `PhoneRootView` lays out for exactly those devices (5.5).
///
/// Both halves are asked here because either one alone is wrong in a way the
/// other is not: the idiom alone hands the desk's three panes to an iPad in
/// Slide Over, which has a phone's width and nowhere to put a sidebar.
@Suite struct RootSurfaceTests {
    @Test func aRegularWidthIPadTakesTheDesksLayout() {
        #expect(RootSurface.resolve(idiom: .pad, horizontalSizeClass: .regular) == .pad)
    }

    /// The blocker. A phone is a phone at every width it can reach.
    @Test func aPhoneInLandscapeIsStillAPhone() {
        #expect(RootSurface.resolve(idiom: .phone, horizontalSizeClass: .regular) == .phone)
        #expect(RootSurface.resolve(idiom: .phone, horizontalSizeClass: .compact) == .phone)
    }

    /// And the window still has the other half of the say: Slide Over and a
    /// narrow split are compact, and take the phone's one-column layout.
    @Test func anIPadWithAPhonesWidthTakesThePhonesLayout() {
        #expect(RootSurface.resolve(idiom: .pad, horizontalSizeClass: .compact) == .phone)
    }

    /// A size class the environment has not resolved yet is not a licence to
    /// draw three panes into a window of unknown width.
    @Test func anUnknownWidthTakesThePhonesLayout() {
        #expect(RootSurface.resolve(idiom: .pad, horizontalSizeClass: nil) == .phone)
        #expect(RootSurface.resolve(idiom: .phone, horizontalSizeClass: nil) == .phone)
    }
}
#endif

/// Which keys some *other* surface takes before a card can see them.
///
/// `menuOwnedShortcuts` is a claim about AppKit: a menu key equivalent is
/// dispatched out of `NSApplication.sendEvent` before the responder chain is
/// offered the event, so a card that also claims ⌘⌫ or ⌘⏎ is claiming a press
/// it will never receive. The set was built on both platforms all the same, and
/// on a keyboard-equipped iPad the two presses were excluded from the card's
/// vocabulary and handled by nobody.
///
/// The iPad has a menu bar of this app's now — `BoardCommands` is declared into
/// both scenes — so the reason the exclusion stays empty there has changed and
/// the answer has not: UIKit offers a press to the responder chain first and
/// reaches the menu at the end of it, which is the opposite order. The card
/// answers, and the menu item is what catches the press when no card has focus.
///
/// `KeyOwnershipTests` says the macOS half; this says the other one, and it has
/// to live in a file that is not `#if os(macOS)` to say it at all.
@Suite struct MenuKeyOwnershipByPlatformTests {
    private func board(_ key: KeyEquivalentBox) -> AppCommand? {
        BoardKeyboard.command(key: key.key, modifiers: key.modifiers, among: BoardKeyboard.boardCommands)
    }

    /// A shim so the two spellings can be written once: `KeyEquivalent` and
    /// `EventModifiers` are SwiftUI's, and naming them in a `@Test` argument
    /// list is more ceremony than the claim is worth.
    struct KeyEquivalentBox {
        var key: KeyEquivalent
        var modifiers: EventModifiers
    }

    @Test func theMenuBarOnlyTakesKeysOnThePlatformThatHasOne() {
        #if os(macOS)
        #expect(!BoardKeyboard.menuOwnedShortcuts.isEmpty)
        #expect(board(KeyEquivalentBox(key: .delete, modifiers: .command)) == nil)
        #expect(board(KeyEquivalentBox(key: .return, modifiers: .command)) == nil)
        #else
        #expect(BoardKeyboard.menuOwnedShortcuts.isEmpty,
                "on iOS the card is offered the press before the menu is, so it keeps these")
        // And the menu bar it does have declares both items all the same.
        #expect(AppCommand.trashTask.isMenuItem(on: .touch))
        #expect(AppCommand.completeTask.isMenuItem(on: .touch))
        #expect(board(KeyEquivalentBox(key: .delete, modifiers: .command)) == .trashTask)
        #expect(board(KeyEquivalentBox(key: .return, modifiers: .command)) == .completeTask)
        #endif
    }

    /// And the keys that were never anyone else's still reach a card on both.
    @Test func theCardsOwnKeysAreUnchanged() {
        #expect(board(KeyEquivalentBox(key: .space, modifiers: [])) == .completeTask)
        #expect(board(KeyEquivalentBox(key: .return, modifiers: [])) == .openTask)
        #expect(board(KeyEquivalentBox(key: .leftArrow, modifiers: .option)) == .moveCardLeft)
    }
}

/// The iPad's flat surfaces are the board's own card at the board's own sizes,
/// and since the saved views became columns that is meant literally: the same
/// width, the same gap between cards, the same gutter between columns.
///
/// `TaskListMetrics.pad` used to say the softer version of this — a capped,
/// centred *row* — and went when its last caller did. What replaced it is
/// `TaskColumnMetrics.pad`, and the claim worth pinning is not its numbers but
/// where they come from: a preset that copied 320 and 10 out of
/// `BoardColumnView` would be right the day it was written and wrong the day
/// the board's column changed.
///
/// `@MainActor` because these presets are — `BoardScrollView` is a `View`, so
/// its `gutter` is isolated along with it. A nonisolated suite calling one
/// crashes the test host rather than failing to compile.
@MainActor
@Suite struct PadListMetricTests {
    @Test func theFlatSurfacesTakeTheBoardsOwnColumn() {
        #expect(TaskColumnMetrics.pad.columnWidth == BoardColumnView.Metrics.pad.width)
        #expect(TaskColumnMetrics.pad.cardSpacing == BoardColumnView.Metrics.pad.cardSpacing)
        #expect(TaskColumnMetrics.desk.columnWidth == BoardColumnView.Metrics.desk.width)
        #expect(TaskColumnMetrics.desk.cardSpacing == BoardColumnView.Metrics.desk.cardSpacing)
        // And the gap between two of them is the strip's, so a view and the
        // board it was gathered from are the same grid rather than two grids
        // that happen to agree.
        #expect(TaskColumnMetrics.pad.columnSpacing == BoardScrollView.gutter)
        #expect(TaskColumnMetrics.desk.columnSpacing == BoardScrollView.gutter)
    }

    /// Room under the last card, but not the phone's 130pt: that is space left
    /// for a floating tab bar, and the iPad has none.
    @Test func theIPadLeavesNoRoomForABarItDoesNotHave() {
        #expect(TaskColumnMetrics.pad.bottomInset < TaskListMetrics.sheet.bottomInset)
        #expect(TaskColumnMetrics.pad.bottomInset > 0)
    }

    /// **All three panels reach the glass.**
    ///
    /// An iPad keeps 20pt at the foot of the screen for the home indicator, and
    /// a pane laid out inside that inset stops short of the bottom — which is
    /// read as a strip of window fill under the source list, the Inbox panel and
    /// the task editor, and not as a system margin. The two panels beside the
    /// board bleed their *fill* under it while their rows stay where they are,
    /// which is what `ignoresSafeArea` on the colour inside `background` buys.
    ///
    /// **The source list goes further and takes the strip outright, rows and
    /// all.** Bleeding the fill alone left a list scrolled to its last row
    /// sitting 20pt up with empty panel beneath it — the colour was right and
    /// the list still stopped short. It can afford the whole strip because the
    /// home indicator is a short pill centred on the *screen*, nowhere near a
    /// column against the leading edge. And it is a negative padding rather
    /// than an `ignoresSafeArea` because inside a split view column the inset is
    /// a margin UIKit has already applied: a colour can be drawn over it, a
    /// frame cannot reclaim it — both measured.
    ///
    /// The detail column's clip is here because it is the other half: it holds
    /// the column's **sides** — the Inbox panel's `.move(edge: .leading)` would
    /// otherwise slide across the source list — and spelled `.clipped()`, on the
    /// column's own bounds, it cut two of the three fills off at exactly the
    /// inset they were bleeding under. ``OpenFooted`` is the same clip with no
    /// floor.
    ///
    /// Read out of the source: a safe area is a runtime fact about a device, and
    /// what is asserted here is which views asked to reach past it.
    @Test func everyPanelsFillReachesUnderTheHomeIndicator() {
        guard SourceTree.isReachable else { return }
        let bleed = "ignoresSafeArea(.container, edges: .bottom)"
        var seen: Set<String> = []
        for file in SourceTree.files() {
            let code = String(file.code)
            switch file.path {
            case "IOS/PadRootView.swift":
                // **One bleed and one negative padding, which is the whole
                // point of the paragraph above.** This counted two bleeds, and
                // there has only ever been one: the editor pane's empty state.
                // The source list reaches the foot the other way — a negative
                // bottom padding, because inside a split view column the inset
                // is a margin UIKit has already applied and a frame cannot
                // reclaim it. Counting to two tested the one mechanism twice
                // and the one that carries the source list not at all.
                #expect(code.components(separatedBy: bleed).count - 1 == 1,
                        "the editor pane's empty state stops at the home indicator")
                #expect(code.contains("underTheHomeIndicator()"),
                        "the source list's rows stop short of the home indicator again")
                #expect(code.contains(".clipped()") == false,
                        "the detail column's clip closed at the foot again")
                #expect(code.contains("clipShape(OpenFooted())"))
                seen.insert(file.path)
            case "Shared/InboxPanel.swift", "Shared/TaskInspector.swift":
                #expect(code.contains(bleed), "\(file.path) stops at the home indicator")
                seen.insert(file.path)
            // The two surfaces the *board* can be. Both were laid out inside
            // the strip and both took the same fix — see the next test for the
            // arithmetic that made it visible.
            case "Shared/BoardScrollView.swift", "Shared/TaskColumnsView.swift":
                #expect(code.contains("underTheHomeIndicator()"),
                        "\(file.path) stops short of the bottom of an iPad again")
                seen.insert(file.path)
            // The one place the trick is written down, so a sixth surface
            // wanting it copies a modifier rather than a negative padding.
            case "Shared/UnderTheHomeIndicator.swift":
                #expect(code.contains("padding(.bottom, -proxy.safeAreaInsets.bottom)"))
                seen.insert(file.path)
            default:
                break
            }
        }
        #expect(seen.count == 6, "a panel moved file: found \(seen)")
    }

    /// **The foot mirrors the head.** The strip an iPad keeps for the home
    /// indicator is not a margin anybody chose, and while the board was laid out
    /// inside it the columns cleared the toolbar by 16 and the bottom of the
    /// window by 36. A saved view was worse: a 28pt foot against a 12pt head,
    /// and then the strip under that.
    ///
    /// The insets are what a test can hold; that the strip itself is taken back
    /// is `everyPanelsFillReachesUnderTheHomeIndicator`'s claim, next door.
    @Test func theTopAndBottomMarginsMatch() {
        #expect(TaskColumnMetrics.pad.topInset == TaskColumnMetrics.pad.bottomInset,
                "a saved view sits further off the foot of an iPad than the head")
        // The board's strip spends one number on both edges by construction —
        // `.padding(.vertical,)` — so what is asserted is that it still does.
        #expect(BoardScrollView.stripPadding > 0)
    }
}
