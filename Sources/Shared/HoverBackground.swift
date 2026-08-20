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
