import SwiftUI

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
/// panel is 336pt wide and an iPhone's sheet lays out around 330pt of content,
/// so a card sized for one already fits the other, and only a caller that wants
/// to differ has to say so.
struct AttributeCard<Value: View>: View {
    @Environment(\.palette) private var palette

    let title: LocalizedStringKey
    var horizontalPadding: CGFloat = 14
    var verticalPadding: CGFloat = 12
    var radius: CGFloat = 14
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
            value()
        }
        // `maxWidth` splits the row evenly; `maxHeight` is what makes the two
        // cards the same height, and only works because the row that holds them
        // is fixed vertically — see ``SwiftUI/View/attributeCardRow()``.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(palette.card, in: .rect(cornerRadius: radius))
    }
}

extension View {
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
