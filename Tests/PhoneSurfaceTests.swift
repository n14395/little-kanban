import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

#if os(iOS)

/// How wide the phone's drawer is drawn, and the thing that made it wrong.
///
/// The design says 84%, and the drawer read that as 84% *of the container* —
/// which is the screen's width, which on its side is the long edge. An iPhone
/// in landscape is 956pt across, so the board list came out at 803pt over a
/// 150pt strip of board: not a drawer, a takeover. 84% of the **short** edge is
/// the same number whichever way the phone is held, which is what a drawer that
/// is the same drawer in both orientations actually means.
///
/// **A value test because the fix is a number**, and because the two places
/// that need it — the panel and the pan that drags it in — have to arrive at the
/// same one or the drawer trails behind the finger.
@MainActor
@Suite struct DrawerWidthTests {
    /// The phones, portrait, as `CGSize`s: an SE, a 15, a Pro Max.
    private let phones: [CGSize] = [
        CGSize(width: 375, height: 667),
        CGSize(width: 393, height: 852),
        CGSize(width: 440, height: 956),
    ]

    /// The panel as the view asks for it: the container it is drawn in is the
    /// screen's width, because the drawer fills the window.
    private func width(_ screen: CGSize) -> CGFloat {
        PhoneNavDrawer.width(in: screen.width, screen: screen)
    }

    private func turned(_ size: CGSize) -> CGSize {
        CGSize(width: size.height, height: size.width)
    }

    /// The claim, on every phone: turning it does not resize the drawer.
    @Test func aDrawerIsTheSameDrawerHeldEitherWayUp() {
        for portrait in phones {
            #expect(width(portrait) == width(turned(portrait)))
            #expect(width(portrait) == portrait.width * PhoneNavDrawer.widthFraction)
        }
    }

    /// The bug, stated as the thing that must not come back. 84% of a landscape
    /// iPhone's width is most of the screen.
    @Test func theLandscapeDrawerIsNotTheLandscapeWidth() {
        let landscape = turned(CGSize(width: 440, height: 956))
        #expect(width(landscape) == 440 * PhoneNavDrawer.widthFraction)
        #expect(landscape.width * PhoneNavDrawer.widthFraction > 800)
    }

    /// And it is that phone's own portrait width it may not exceed, rather than
    /// a maximum picked once: an SE's drawer is narrower than a Pro Max's, and
    /// capping both at the same number would widen one of them on its side.
    @Test func theCapIsTheDeviceAndNotAConstant() {
        let small = width(phones[0])
        let large = width(phones[2])
        #expect(small < large)
        for portrait in phones {
            #expect(width(turned(portrait)) <= width(portrait))
        }
    }

    /// A screen nobody has measured yet leaves the container as the only thing
    /// to go on, which is what the drawer did before it was handed a screen.
    /// Zero must not win the `min`.
    @Test func anUnmeasuredScreenFallsBackToTheContainer() {
        #expect(PhoneNavDrawer.width(in: 440, screen: .zero) == 440 * PhoneNavDrawer.widthFraction)
        #expect(PhoneNavDrawer.width(in: 440, screen: CGSize(width: 0, height: 956))
                == 440 * PhoneNavDrawer.widthFraction)
    }

    /// And the container still counts when it is the narrowest thing in the sum:
    /// the panel is 84% of what it is drawn inside, never more, whatever the
    /// screen around it is doing.
    @Test func aNarrowContainerStillHoldsThePanel() {
        let screen = CGSize(width: 956, height: 440)
        #expect(PhoneNavDrawer.width(in: 320, screen: screen) == 320 * PhoneNavDrawer.widthFraction)
    }
}

#endif
