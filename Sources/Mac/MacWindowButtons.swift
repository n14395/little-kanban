#if os(macOS)

import AppKit
import SwiftUI

extension View {
    /// Puts the window's traffic lights on the header's line.
    ///
    /// The window has no title bar, so the board header is drawn straight
    /// against the top of the window and the lights float over it. AppKit sits
    /// them near the top of a 32pt title bar — a whole row above a header that
    /// is taller than that — which is what left the title, the search field and
    /// the buttons reading as a second strip under the chrome rather than as
    /// the chrome itself. Handing the row's own centre down is what lines the
    /// two up, at whatever height the header has grown to.
    ///
    /// - Parameter centre: How far below the top of the window the row the
    ///   lights should sit on is centred.
    func windowButtons(centredAt centre: CGFloat) -> some View {
        background(WindowButtonRow(centre: centre).frame(width: 0, height: 0))
    }
}

private struct WindowButtonRow: NSViewRepresentable {
    var centre: CGFloat

    func makeNSView(context: Context) -> NSView { WindowButtonAligner() }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? WindowButtonAligner)?.centre = centre
    }
}

/// Holds the three standard window buttons on one row.
///
/// AppKit puts them back where it wants them whenever it lays the title bar out
/// again — a resize is enough — so this is not a placement made once. Each
/// button is watched for the move and put back, which covers every occasion
/// without having to name them: `NSView.frameDidChangeNotification` fires on
/// AppKit's write and not on the correcting one, because a frame already at the
/// target is left alone.
///
/// Correcting a button the moment it moves is not enough on its own, though.
/// AppKit is still mid-layout when the notification arrives, and it writes the
/// zoom button's frame once more on the way out of that pass — measured: close
/// and minimise held their row across a resize and zoom alone snapped back up.
/// So every notification also books a second pass for the next turn of the run
/// loop, once the layout it interrupted has finished.
private final class WindowButtonAligner: NSView {
    var centre: CGFloat = 0 {
        didSet {
            guard centre != oldValue else { return }
            align()
        }
    }

    /// Whether a second pass is already booked. One is enough — it runs after
    /// the whole burst of notifications a single layout produces.
    private var isSettling = false

    /// A background must not take the pointer away from what it is behind.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        watch()
        align()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private var buttons: [NSButton] {
        guard let window else { return [] }
        return [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
    }

    private func watch() {
        let notifications = NotificationCenter.default
        notifications.removeObserver(self)
        for button in buttons {
            button.postsFrameChangedNotifications = true
            notifications.addObserver(
                self, selector: #selector(realign),
                name: NSView.frameDidChangeNotification, object: button
            )
        }
        guard let window else { return }
        // A resize is what moves the buttons, and watching the window for it as
        // well as the buttons costs nothing — a pass that finds them already on
        // their row writes nothing.
        //
        // Full screen is AppKit's own arrangement, though: the lights come down
        // in an overlay that has nothing to do with this window's header, so the
        // row is left alone while it lasts and taken back on the way out.
        // Leaving is the one move that need not change a frame, so it is asked
        // for by name rather than waited for.
        for name in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification] {
            notifications.addObserver(self, selector: #selector(realign), name: name, object: window)
        }
    }

    @objc private func realign() {
        align()
        guard !isSettling else { return }
        isSettling = true
        DispatchQueue.main.async { [weak self] in
            self?.isSettling = false
            self?.align()
        }
    }

    private func align() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }

        for button in buttons {
            guard let titleBar = button.superview else { continue }
            // Kept whole inside the title bar. `NSView.hitTest` stops at a
            // view's own bounds before it ever asks a subview, so a button
            // hanging below the bar's would draw in the right place and then
            // refuse the click.
            let half = button.frame.height / 2
            let row = min(max(centre, half), titleBar.bounds.height - half)
            let y = (titleBar.bounds.height - row - half).rounded()
            guard abs(button.frame.origin.y - y) > 0.5 else { continue }
            button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y))
        }
    }
}

#endif
