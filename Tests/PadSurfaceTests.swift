import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

#if os(iOS)
import UIKit

/// Which of the two iOS layouts a window gets.
///
/// The rule was `horizontalSizeClass == .regular` and nothing else, which is
/// not "this is an iPad": a Max- or Plus-class iPhone reports a regular
/// horizontal size class in landscape, and one did — driven at 956×440, an
/// iPhone drew `PadRootView` with the split view's sidebar toggle, the
/// inspector and the board's column controls, and never drew the two-up
/// landscape board `PhoneRootView` lays out for exactly those devices (5.5).
///
/// Both halves are asked here because either one alone is wrong in a way the
/// other is not: the idiom alone hands the desk's three panes to an iPad in
/// Slide Over, which has a phone's width and nowhere to put a sidebar.
/// Which of the two panels that open on the left of an iPad window has to give
/// way, and when.
///
/// Both the source list and the Inbox panel are a column wide and both open on
/// the same side, so a window that is not wide enough for two columns and a
/// board cannot show both. What it used to do there was nothing: the panel's own
/// `hasRoomForTheInbox` declined to draw it, so on an 11" in portrait with the
/// list out the Inbox button was a control that did not appear to work. They
/// take turns now — whichever is opened closes the other — and this is the
/// arithmetic that decides whether the window is one of those.
///
/// **A value test because the decision is a number**, taken from widths the view
/// measures. `UITests/PadSidebarsTests` presses the buttons.
@MainActor
@Suite struct SidebarRoomTests {
    private let panel = InboxPanel.Metrics.pad.width
    private let inspector: CGFloat = 348
    private let list = PadRootView.sidebarIdeal
    /// One `.pad` column and the strip's margins, which is `PadRootView`'s own
    /// floor spelled out — a board narrower than this is not a board.
    private let floor = BoardColumnView.Metrics.pad.width + 32

    private func holds(_ window: CGFloat, inspector: CGFloat) -> Bool {
        PadRootView.holdsBothSidebars(
            window: window, sidebar: list, inspector: inspector, panel: panel, floor: floor
        )
    }

    /// A 13" in portrait holds both with the inspector away — 1032 less the
    /// list's 300 and the panel's column still leaves a board — and does not
    /// hold them with the inspector out, which takes more than the board has
    /// left.
    @Test func theBigIPadInPortraitHoldsBothOnlyWithoutTheInspector() {
        #expect(holds(1032, inspector: 0))
        #expect(!holds(1032, inspector: inspector))
    }

    /// An 11" in portrait holds neither combination: 834 less two columns is
    /// half a board. This is the shape the rule was written for.
    @Test func theSmallerIPadInPortraitHoldsOnlyOne() {
        #expect(!holds(834, inspector: 0))
        #expect(!holds(834, inspector: inspector))
    }

    /// A 13" in landscape holds all four at once — the desk's three panes plus
    /// the Inbox, which is the shape this layout was drawn for, and the case
    /// that must *not* start closing panels.
    ///
    /// An 11" in landscape does not, and that is worth being surprised by: 1194
    /// less three columns is 226, which is not a board. It holds both of the
    /// left-hand panels perfectly well with the inspector away, so on that iPad
    /// whether the two take turns depends on the inspector — which is the honest
    /// answer, because the inspector is a column of the same window.
    @Test func landscapeHoldsEverythingOnTheBigIPadAndNotOnTheSmall() {
        #expect(holds(1376, inspector: inspector))
        #expect(!holds(1194, inspector: inspector))
        #expect(holds(1194, inspector: 0))
    }

    /// Before the first layout pass there is no width, and no width has to read
    /// as *room for both* — the other way round is a window that shuts one of
    /// its panels on the way in.
    @Test func anUnmeasuredWindowHoldsBoth() {
        #expect(holds(0, inspector: inspector))
    }

    /// And the rule is the board's floor rather than a number of its own: a
    /// window one point above it holds both, one point below does not.
    @Test func theLineIsExactlyTheBoardsFloor() {
        let exact = list + inspector + panel + floor
        #expect(holds(exact, inspector: inspector))
        #expect(!holds(exact - 1, inspector: inspector))
    }
}

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
/// it will never receive. The set was built on both platforms all the same,
/// and `BoardCommands` is only ever built into the macOS scene — the iPad's
/// `WindowGroup` declares no commands — so on a keyboard-equipped iPad the two
/// presses were excluded from the card's vocabulary and handled by nobody.
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
                "iOS builds no menu bar of ours, so nothing takes these presses first")
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

/// The iPad's flat lists are the board's own card at the board's own sizes, and
/// the preset that says so lives on the type rather than inside `PadRootView` —
/// where nothing outside the view could name it.
@Suite struct PadListMetricTests {
    @Test func theIPadsListPresetIsNamedBesideItsSiblings() {
        let pad = TaskListMetrics.pad
        // Room under the last card, but not the phone's 130pt: that is space
        // left for a floating tab bar, and the iPad has none.
        #expect(pad.bottomInset < TaskListMetrics.sheet.bottomInset)
        #expect(pad.bottomInset > 0)
        // A row is capped and centred rather than stretched across 13 inches,
        // which is the desk's rule at the iPad's width.
        #expect(pad.maxRowWidth > TaskListMetrics.desk.maxRowWidth)
        #expect(pad.maxRowWidth < .infinity)
    }
}
