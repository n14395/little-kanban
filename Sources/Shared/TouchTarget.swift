// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// A text field's claim on the row it sits in.
///
/// A `TextField` hit-tests and publishes only the text it draws — around 21pt
/// inside a 44pt row — so a frame around it buys nothing and the accessibility
/// frame stays the size of the glyphs. `.contentShape(.accessibility,)` is what
/// hands it the row; see **Touch targets** in the README.
///
/// Applied through a modifier rather than written inline because the pointer
/// presets pass zero, and zero has to mean *nothing at all*: a shared control
/// that quietly reshapes its accessibility element on macOS is not the same
/// control it was.
struct FieldHitArea: ViewModifier {
    let minHeight: CGFloat
    /// Claims the rest of the row for the field. Drawn *behind* it, so a tap on
    /// the text still reaches the field and the caret lands where the finger
    /// did — `PhoneDetailSheet.focusCatcher` makes the same trade.
    var claimFocus: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if minHeight > 0 {
            content
                .frame(minHeight: minHeight)
                .contentShape(.accessibility, Rectangle())
                .background {
                    if let claimFocus {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture(perform: claimFocus)
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    /// Gives a text field the row's height as its target and its accessibility
    /// frame. A `minHeight` of zero is an exact no-op.
    func fieldHitArea(minHeight: CGFloat, claimFocus: (() -> Void)? = nil) -> some View {
        modifier(FieldHitArea(minHeight: minHeight, claimFocus: claimFocus))
    }
}
