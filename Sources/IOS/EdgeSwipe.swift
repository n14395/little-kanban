#if os(iOS)

import SwiftUI
import UIKit

extension View {
    /// Opens something when a pan starts at the screen's leading edge and moves
    /// inwards — the gesture every other iOS app uses to reach what is parked
    /// behind that edge, and the one both of this app's iOS surfaces were
    /// missing: the phone's drawer could only be reached through the hamburger
    /// and the iPad's source list only through the toolbar's toggle.
    ///
    /// The edge is *leading*, not left. In a right-to-left layout the drawer
    /// comes from the other side — `ZStack(alignment: .leading)` and
    /// `.transition(.move(edge: .leading))` both mirror on their own — so the
    /// gesture that opens it has to come from the same side the panel does.
    /// `UIRectEdge` is UIKit's and absolute where SwiftUI's `Edge` is semantic,
    /// so it is one of the two values in this app that do *not* mirror
    /// themselves — the drawer panel's shadow offset is the other — and it
    /// flips by hand off `layoutDirection`.
    func leadingEdgeSwipe(perform action: @escaping () -> Void) -> some View {
        modifier(LeadingEdgeSwipe(action: action))
    }
}

private struct LeadingEdgeSwipe: ViewModifier {
    @Environment(\.layoutDirection) private var layoutDirection
    let action: () -> Void

    func body(content: Content) -> some View {
        content.background {
            EdgePanAnchor(
                edge: layoutDirection == .rightToLeft ? .right : .left, action: action
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A `UIScreenEdgePanGestureRecognizer`, hung on the view controller hosting
/// this view tree.
///
/// **Why UIKit, when the rest of this app is SwiftUI.** A `DragGesture` on a
/// strip at the edge is the obvious spelling and it loses. The board is a
/// horizontal scroll view on both idioms, and a pan that lands anywhere over it
/// is claimed by that scroll view's own recognizer — the same rule that took
/// the swipe actions off the board's rows (see `BoardStore.isColumnPaging`).
/// `UIScreenEdgePanGestureRecognizer` is the recognizer built for this case —
/// it is what a navigation controller's interactive pop is made of — and
/// SwiftUI exposes nothing like it. Being one is not by itself enough to win;
/// see `Coordinator`'s delegate method for the half that settles it.
///
/// **Hung on the controller's view, not on the window.** A sheet is presented
/// as a sibling of the board's view controller rather than a descendant of it,
/// so a recognizer at this level never sees a touch that landed on a sheet or
/// on the dimming above one. On the window it would, and an edge pan under the
/// detail sheet would open a drawer nobody can see.
///
/// The anchor itself is a zero-sized, non-interactive view. It is here to find
/// the controller and to say when the tree goes away; the recognizer it carries
/// lives further up.
private struct EdgePanAnchor: UIViewRepresentable {
    let edge: UIRectEdge
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> AnchorView {
        AnchorView(recognizer: context.coordinator.recognizer)
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        // The closure captures the store and the environment, so it is a new one
        // on every pass; the recognizer is not, and must not be re-made or the
        // pan in flight is cancelled under the finger.
        context.coordinator.action = action
        context.coordinator.recognizer.edges = edge
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) {
        view.detach()
    }

    /// Main-actor bound, which is where a gesture recognizer is made and
    /// where its action arrives; a bare `NSObject` is `nonisolated` and
    /// cannot hold one as a stored property.
    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void

        lazy var recognizer: UIScreenEdgePanGestureRecognizer = {
            let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePanned))
            pan.delegate = self
            return pan
        }()

        init(action: @escaping () -> Void) {
            self.action = action
        }

        /// **The line that makes the gesture work at all.** Being a screen-edge
        /// pan is not on its own enough to beat the pager: measured on an
        /// iPhone 17 Pro, a pull from x=0 across the board went to
        /// `UIScrollViewPanGestureRecognizer` and this one never left
        /// `.possible`. What it needed was the failure requirement stated
        /// explicitly — every competing pan waits for this one to give up.
        ///
        /// The wait costs nothing anywhere else. A screen-edge pan fails the
        /// moment a touch lands outside its margin, so a scroll that starts
        /// anywhere but the edge is never held; one that starts *on* the edge
        /// and goes down is held until the direction rules this out, which is
        /// exactly how a navigation controller's back gesture behaves.
        ///
        /// Simultaneous recognition would have been the other spelling and is
        /// the wrong one: it opens the drawer *and* turns the board to the next
        /// column, which is two answers to one swipe.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            other is UIPanGestureRecognizer
        }

        /// `.began`, not `.ended`. The recognizer has already required a touch
        /// down within the system's edge margin and movement inwards by the time
        /// it fires, so the drawer opens under the finger that asked for it
        /// rather than after it lifts — which is the difference between the
        /// gesture feeling like the drawer and feeling like a delayed button.
        @objc private func edgePanned(_ pan: UIScreenEdgePanGestureRecognizer) {
            guard pan.state == .began else { return }
            action()
        }
    }

    final class AnchorView: UIView {
        private let recognizer: UIScreenEdgePanGestureRecognizer
        /// Weak, and remembered rather than re-derived: the controller's view
        /// outlives this one, and detaching has to reach the view the
        /// recognizer actually went onto even after the chain has come apart.
        private weak var host: UIView?

        init(recognizer: UIScreenEdgePanGestureRecognizer) {
            self.recognizer = recognizer
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// The responder chain is only complete once the view is in a window,
        /// which is why the recognizer goes on here and not in `init`.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, let controllerView = owningControllerView else {
                detach()
                return
            }
            guard controllerView !== host else { return }
            detach()
            controllerView.addGestureRecognizer(recognizer)
            host = controllerView
        }

        func detach() {
            host?.removeGestureRecognizer(recognizer)
            host = nil
        }

        /// The nearest view controller above this view, by way of the responder
        /// chain — a view's `next` is its superview until the top of a
        /// controller's tree, where it is the controller.
        private var owningControllerView: UIView? {
            var responder: UIResponder? = next
            while let current = responder {
                if let controller = current as? UIViewController { return controller.view }
                responder = current.next
            }
            return nil
        }
    }
}

#endif
