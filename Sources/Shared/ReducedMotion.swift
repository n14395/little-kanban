import SwiftUI

/// Animation that a reader who has asked for less motion does not get.
///
/// Reduce Motion is not a preference about taste: vestibular disorders make a
/// panel that slides in from the edge, a card that lifts under the pointer and
/// a row of dots that slides between positions genuinely unpleasant. Nothing
/// here was checking it.
///
/// A `nil` animation is what SwiftUI reads as "no animation", so both the
/// modifier and ``Motion/run(_:reduceMotion:_:)`` reduce to the change
/// happening at once rather than to a change that does not happen.
enum Motion {
    static func animation(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// `withAnimation`, for the places that drive a change rather than watch a
    /// value — a scroll to a card, the pager settling on a column.
    @MainActor
    static func run<Result>(
        _ animation: Animation?, reduceMotion: Bool, _ body: () throws -> Result
    ) rethrows -> Result {
        try withAnimation(Self.animation(animation, reduceMotion: reduceMotion), body)
    }

    /// The same, for a change something has to happen *after*: a panel dragged
    /// back out of sight is only taken out of the tree once it has finished
    /// going. Under Reduce Motion the animation is `nil` and the completion
    /// runs at once, which is the right answer rather than a special case.
    @MainActor
    static func run<Result>(
        _ animation: Animation?, reduceMotion: Bool,
        _ body: () throws -> Result, completion: @escaping () -> Void
    ) rethrows -> Result {
        try withAnimation(
            Self.animation(animation, reduceMotion: reduceMotion), body, completion: completion
        )
    }
}

private struct MotionAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(Motion.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that honours Reduce Motion.
    func motionAnimation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }
}
