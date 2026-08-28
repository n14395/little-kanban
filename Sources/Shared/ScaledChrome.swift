import SwiftUI

/// How much larger the reader's text is than the default, as one number the
/// chrome can multiply its own fixed sizes by.
///
/// The design pins a toolbar at 66pt, a column at 272 and the inspector at 336.
/// Every one of those is a box drawn around type that grows with Dynamic Type,
/// so at an accessibility size the type outgrows the box and is clipped — an
/// iPad at AX5 truncated its column headings to "Bac…" and wrapped the
/// inspector's "Priority" across two lines mid-word. Growing the box by the
/// same factor is what keeps the two in step.
///
/// Capped, because the factor at AX5 is a little over two and a source list
/// twice its width is most of an iPad. Past the cap the box stops growing and
/// what is inside it wraps instead, which is a trade a wide container can make
/// and a fixed-height strip cannot — so heights are stated as minimums and
/// only widths take the cap.
struct ChromeScale: DynamicProperty {
    /// Measured from 100 rather than from 1, so the rounding `ScaledMetric`
    /// does at small values cannot turn a 4% step into a 0% one.
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 100

    /// Never below 1: the design's sizes are already the floor, and a reader on
    /// the *smallest* text size still needs 44pt under a finger.
    var factor: CGFloat { max(1, unit / 100) }

    func callAsFunction(_ size: CGFloat, cap: CGFloat = 1.6) -> CGFloat {
        size * min(factor, cap)
    }

    /// An optional size — the source list's width is `nil` where the container
    /// decides — grown only where there is one. Named rather than a second
    /// `callAsFunction`, which `CGFloat` would make ambiguous at every site.
    func scaling(_ size: CGFloat?, cap: CGFloat = 1.6) -> CGFloat? {
        size.map { callAsFunction($0, cap: cap) }
    }
}

/// An SF Symbol drawn at a design point size that follows the reader's text
/// size.
///
/// `.font(.system(size:))` pins a glyph: at an accessibility size the word
/// beside it doubles and the glyph does not, and an icon-only control keeps the
/// target it had at the default size. Naming the text style the glyph stands
/// beside is what moves the two together. C3 already asks this of new code;
/// this is what the old code was swept onto.
private struct ScaledSymbol: ViewModifier {
    @ScaledMetric private var scaled: CGFloat
    private let base: CGFloat
    private let weight: Font.Weight
    private let cap: CGFloat

    init(size: CGFloat, weight: Font.Weight, relativeTo textStyle: Font.TextStyle, cap: CGFloat) {
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.base = size
        self.weight = weight
        self.cap = cap
    }

    /// Capped for the same reason ``ChromeScale`` is: past a point the glyph is
    /// growing inside a box that has stopped, and a symbol that outgrows its
    /// button is worse than one that stops a little short of the type.
    func body(content: Content) -> some View {
        content.font(.system(size: min(scaled, base * cap), weight: weight))
    }
}

extension View {
    /// A symbol at `size` points at the default text size, growing with the
    /// reader's — the replacement for `.font(.system(size:weight:))` on an
    /// `Image(systemName:)`.
    func symbolSize(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body,
        cap: CGFloat = 1.6
    ) -> some View {
        modifier(ScaledSymbol(size: size, weight: weight, relativeTo: textStyle, cap: cap))
    }
}
