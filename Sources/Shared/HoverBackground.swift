import SwiftUI

/// The design's `style-hover="background: rgba(var(--ink-rgb),0.05)"` rows.
/// No-ops on touch-only devices, where `onHover` never fires.
private struct HoverBackground: ViewModifier {
    let color: Color
    let radius: CGFloat
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(isHovering ? color : .clear, in: .rect(cornerRadius: radius))
            .onHover { isHovering = $0 }
    }
}

extension View {
    func hoverBackground(_ color: Color, radius: CGFloat) -> some View {
        modifier(HoverBackground(color: color, radius: radius))
    }
}

/// A button that carries no chrome of its own — the design draws every control
/// by hand, so the button style only supplies the tap target and press feedback.
struct BareButtonStyle: ButtonStyle {
    var pressedOpacity: Double = 0.6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
    }
}

extension ButtonStyle where Self == BareButtonStyle {
    static var bare: BareButtonStyle { BareButtonStyle() }
}

/// ``BareButtonStyle``, and a focus ring the theme owns.
///
/// **The system's ring is the one colour in the app a theme could not reach.**
/// AppKit draws it in `NSColor.keyboardFocusIndicatorColor`, which follows the
/// *machine's* accent and is settable by nobody — so with Full Keyboard Access
/// on, every hand-drawn control in the app wore a rust rectangle the moment it
/// took focus, over a board whose every other colour came from the theme. A
/// `ButtonStyle` cannot turn it off: the ring is drawn by the `Button` around
/// the style's body, and `.focusEffectDisabled()` inside `makeBody` is already
/// inside it. So this is a modifier applied *to* the button rather than a style
/// applied within it — which is also why `.buttonStyle(.bare)` is spelt
/// `.bareButton()` at every call site.
///
/// **The ring is not dropped, it is re-drawn.** Keyboard focus is the one state
/// this app does not otherwise show — hover and press and selected are all
/// drawn, and focus was the system's job — so taking the ring away would leave
/// a keyboard user with nothing at all. ``Palette/accent`` at 2pt, outside the
/// control rather than over it, is the same ring one theme further in.
///
/// `radius` is the control's own corner, so the ring follows the shape the
/// button drew rather than boxing it. The default suits the rounded rectangles
/// most of the app's controls are; `.infinity` is the capsules and the discs,
/// and `0` a square edge.
struct BareButton: ViewModifier {
    @Environment(\.palette) private var palette
    @FocusState private var isFocused: Bool

    var pressedOpacity: Double
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .buttonStyle(BareButtonStyle(pressedOpacity: pressedOpacity))
            .focused($isFocused)
            // Off, so the ring below is the only one drawn. Where nothing was
            // focusable to begin with — a touch-only device, or a Mac with Full
            // Keyboard Access off — this costs nothing: `isFocused` never turns
            // on and the overlay stays clear.
            .focusEffectDisabled()
            .overlay { ring }
    }

    /// Outside the control rather than over it — `inset(by: -3)` — because a
    /// ring drawn *on* a filled capsule eats two points of the thing it is
    /// pointing at, and several of these controls are 22pt tall to begin with.
    @ViewBuilder private var ring: some View {
        let colour: Color = isFocused ? palette.accent : .clear
        if radius.isFinite {
            RoundedRectangle(cornerRadius: radius + 2)
                .inset(by: -3)
                .strokeBorder(colour, lineWidth: 2)
        } else {
            Capsule()
                .inset(by: -3)
                .strokeBorder(colour, lineWidth: 2)
        }
    }
}

extension View {
    /// A button with no chrome of its own and the theme's own focus ring — see
    /// ``BareButton`` for why this is a modifier and not just a `ButtonStyle`.
    func bareButton(pressedOpacity: Double = 0.6, radius: CGFloat = 8) -> some View {
        modifier(BareButton(pressedOpacity: pressedOpacity, radius: radius))
    }
}
