import SwiftUI

/// What a quick-capture button draws: a `+`, and the tray the Inbox is drawn
/// with everywhere else, at the same size and to its right.
///
/// The three ever-present capture buttons — the source list's foot on the desk
/// (``BoardSidebar/captureButton``), the iPad's board header
/// (``BoardToolbar/captureButton``) and the phone's over its tab bar
/// (``PhoneTabBar/quickCaptureButton``) — already meant one thing on all three
/// platforms: a card worth writing down before anything about where it goes has
/// been decided, landing in the Inbox. A bare `+` did not say the second half of
/// that. On its own the glyph reads as *add here*, and here is whatever surface
/// the button is floating over — which is exactly the reading the column
/// heading's `+` is for. The tray says where it lands, in the one mark the rest
/// of the app already spends on the Inbox: the toolbar's toggle, the tab pill's
/// slot, the source list's row and the empty state are all this symbol.
///
/// **Both glyphs at one point size**, rather than the tray dropped to a
/// subscript beside the `+`. They are not a glyph and its annotation — they are
/// the verb and the destination, and a smaller tray would read as a badge on the
/// `+` rather than the other half of the sentence. Sized at all is enough
/// difference: `plus` is a narrower design than `tray` at the same size, so the
/// pair already has a natural rhythm without either being shrunk.
///
/// **A capsule rather than a circle**, which is the whole of what changes about
/// the shape. Height is untouched at every one of the three sites — the phone's
/// 52pt float, its 44pt header disc, the iPad's 44 and the desk's 44 — because
/// height is what a thumb and a row are measured against, and only the width
/// grows to hold the second glyph.
struct CaptureGlyphs: View {
    /// The point size *both* glyphs are drawn at, before Dynamic Type.
    var size: CGFloat
    var weight: Font.Weight = .regular
    /// The text style the pair grows with — see ``SwiftUI/View/symbolSize(_:weight:relativeTo:cap:)``.
    var relativeTo: Font.TextStyle = .title3

    /// The room between the two glyphs, and the same measure again at either end
    /// of the pill.
    ///
    /// Half a glyph. Written off the glyph rather than off the pill's height,
    /// which is the tempting spelling: the height's own inset — `(height -
    /// size) / 2`, what centred the `+` in the circle — is generous because it
    /// was never a gap, it was the room a single glyph had to be centred in.
    /// Spent three times over it made a pill half again as wide as it needed to
    /// be, which on the iPad's header is width taken straight off the board's
    /// name (see ``BoardToolbar/Metrics/searchFits(barWidth:leadingInset:sidebarToggle:inboxToggle:factor:)``).
    static func gap(_ size: CGFloat) -> CGFloat { size / 2 }

    /// What the pill is wide: two glyphs and three gaps — **three and a half
    /// glyphs**, which is the one number every site that has to reserve room for
    /// this control reads.
    ///
    /// A rule rather than a measurement per platform, because the four sites
    /// draw the same pair at four sizes and nothing but the size differs. Nudged
    /// at one of them it would stop being the same control.
    static func width(_ size: CGFloat) -> CGFloat { size * 3.5 }

    var body: some View {
        HStack(spacing: Self.gap(size)) {
            Image(systemName: "plus")
            Image(systemName: Board.inboxSymbol)
        }
        // One modifier over the pair rather than one each: the two being the
        // same size is the point, and a font set on the stack is a font both
        // images inherit.
        .symbolSize(size, weight: weight, relativeTo: relativeTo)
        // Not hidden from accessibility, which is the tempting spelling for a
        // pair of glyphs that say nothing on their own: the button around this
        // states its own name — "New task", "Capture a task" — and that name is
        // what UI tests find it by. A hidden label is one more way for a button
        // to publish as nameless, which is the failure `UITests/PadCaptureTests`
        // exists to catch.
    }
}
