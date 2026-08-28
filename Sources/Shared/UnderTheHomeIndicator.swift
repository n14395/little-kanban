import SwiftUI

/// Hands a pane the strip an iPad keeps at the foot of the screen, so its
/// content ends where the screen does rather than where the system margin does.
///
/// **What the strip is.** iPadOS reserves about 20pt along the bottom for the
/// home indicator — a short pill centred on the *screen* — and every pane laid
/// out inside that inset stops short of the glass by that much. Read as design
/// it looks like a gap somebody chose: a board whose columns clear the toolbar
/// by 16pt at the top and the bottom of the window by 36, a saved view sitting
/// twice as far off the foot as the head. There is no status bar down there and
/// nothing else in the way; the number is the device's, not the layout's.
///
/// **Why a negative padding and not `ignoresSafeArea`.** Inside a
/// `NavigationSplitView` the inset is a layout margin UIKit has already applied
/// to the column. A colour in a `background` can be *drawn* over it — that is
/// what the Inbox panel and the task editor do, and it is measured — but a frame
/// cannot *reclaim* it: `ignoresSafeArea(.container, edges: .bottom)` on the
/// scroll view itself left the pane's bottom edge exactly where it was, measured
/// with a marker at 20–24pt. A negative padding is plain layout and owes the
/// safe area nothing. The inset is read from the proxy rather than written as
/// `20` because how much room the indicator wants is the device's answer.
///
/// **Where it is safe.** The indicator is a pill in the middle of the bottom
/// edge and it takes no touches — a tap passes through it, and only an upward
/// swipe from the very edge belongs to the system. So this is for panes whose
/// foot is scrolling content: the source list, the board's strip of columns, a
/// saved view's. It is *not* for a control that has to be pressed at the bottom
/// of the screen, which would sit under the pill and read as unfinished.
///
/// A no-op off iOS, where there is no such strip and the panes are already
/// against the window's edge.
struct HomeIndicatorFoot: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        GeometryReader { proxy in
            content.padding(.bottom, -proxy.safeAreaInsets.bottom)
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Lets this pane's content run to the bottom of the screen, under the strip
    /// iPadOS keeps for the home indicator. See ``HomeIndicatorFoot`` for what
    /// it costs and where it is not appropriate.
    func underTheHomeIndicator() -> some View {
        modifier(HomeIndicatorFoot())
    }
}
