// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The numbers one of the attribute cards is drawn to, gathered so a control
/// can be handed the card it *is* rather than being put inside one.
///
/// Free-standing rather than nested in ``AttributeCard``, which is generic:
/// a type inside a generic type cannot be named without also naming what it
/// was specialised with, and the two call sites here hand this around long
/// before there is a value to draw.
struct AttributeCardStyle {
    var title: LocalizedStringKey
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 12
    var radius: CGFloat = 14
}

/// One of the two boxes on the detail surfaces' attribute row: a name over a
/// value, in a card, taking half the row.
///
/// Written once and drawn by both surfaces — see ``TaskInspector/attributeCards``
/// and `PhoneDetailSheet.attributeCards`. The two were a `Grid` of field-name
/// rows on the desk and a pair of cards on the phone, which is a difference the
/// same task should not have between one device and the next; keeping the card
/// here means the next change to it lands on both at once.
///
/// The paddings default to the phone's numbers rather than being required: the
/// panel is 372pt wide and an iPhone's sheet lays out around 330pt of content,
/// so a card sized for the narrower of the two is comfortable in the wider, and
/// only a caller that wants to differ has to say so.
///
/// **Drawn by the control, not around it** — see ``SwiftUI/View/inAttributeCard(_:)``.
/// Both values in this row open something, and a card whose name and whose
/// whitespace did nothing was a card where most of what looks like the control
/// was not one.
struct AttributeCard<Value: View>: View {
    @Environment(\.palette) private var palette

    let style: AttributeCardStyle
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(style.title)
                .sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
            value()
        }
        // `maxWidth` splits the row evenly; `maxHeight` is what makes the two
        // cards the same height, and only works because the row that holds them
        // is fixed vertically — see ``SwiftUI/View/attributeCardRow()``.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(palette.card, in: .rect(cornerRadius: style.radius))
    }
}

extension View {
    /// Draws this value as an ``AttributeCard``, or leaves it alone where the
    /// style is `nil` and the control is drawing its bare value.
    ///
    /// Called from inside the control's own button or menu label, which is the
    /// whole point: the card is then part of what the control claims, so its
    /// name, its padding and the empty half of it open the calendar or the
    /// priority menu exactly as the chip in the middle of it does. The shape is
    /// stated because a hit area that stopped at the value would leave most of
    /// a card that plainly looks pressable doing nothing when pressed.
    @ViewBuilder
    func inAttributeCard(_ style: AttributeCardStyle?) -> some View {
        if let style {
            AttributeCard(style: style) { self }
                .contentShape(.rect(cornerRadius: style.radius))
        } else {
            self
        }
    }

    /// The `HStack` holding a pair of ``AttributeCard``s.
    ///
    /// Both cards ask for `maxHeight: .infinity`, which in a scroll view resolves
    /// to nothing at all: the proposal coming down is unbounded, so "as tall as
    /// you'll give me" is the card's own ideal height and the two draw at
    /// whatever height their contents happen to be. Fixing the row vertically
    /// makes it report its ideal — the taller card's — and *then* propose that
    /// down, which the shorter card fills.
    ///
    /// Visible the moment a due date is unset in a narrow panel: "Add due date"
    /// wraps to two lines, and without this the Priority card beside it drew
    /// short and floated in the middle of the row.
    func attributeCardRow() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }
}
