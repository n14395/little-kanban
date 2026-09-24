import SwiftUI

/// **The one icon control in the app**: a button wearing the glyph it has,
/// which opens ``SymbolPickerPopover``.
///
/// It is ``ColorWell`` for symbols, deliberately — same shape, same sizes, same
/// place in a sheet — because it stands where the board's colour well stood and
/// a person who has met one has met the other. What is behind it is not the
/// same at all: a colour is mixed, a symbol is *found*, and finding is a search
/// field over seven thousand names rather than a spectrum.
///
/// **Two things stand on it**: a board's mark in Board Settings, and a saved
/// view's in its editor. They differ in the list the picker opens on and in
/// what stands in for a glyph this system cannot draw; everything behind that
/// is one control. The view editor drew a fixed row of eighteen swatches until
/// this replaced it — the row could only ever offer what was written into the
/// source, which is the same thing that was wrong with `DotPicker`.
///
/// The label is words as well as the glyph, for the colour well's reason: a
/// bare mark with no text is a control a person has to have been told about,
/// and this one is often the only thing in its section.
struct SymbolWell: View {
    struct Metrics {
        var font: CGFloat
        var glyph: CGFloat
        var height: CGFloat
        var radius: CGFloat
        var horizontalPadding: CGFloat
        /// The picker's own sizes, which are a finger's or a pointer's.
        var picker: SymbolPickerPopover.Metrics

        static let desk = Metrics(
            font: 12.5, glyph: 15, height: 30, radius: 9, horizontalPadding: 12, picker: .desk
        )
        static let sheet = Metrics(
            font: 14.5, glyph: 17, height: 44, radius: 11, horizontalPadding: 14, picker: .sheet
        )
    }

    @Environment(\.palette) private var palette
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    /// The symbol the button wears, and the one the picker opens on.
    let selection: String
    var metrics: Metrics = .desk
    /// What the picker's **Suggested** group holds, and what stands in for a
    /// name this system cannot draw — a board's and a view's own answers, so
    /// neither kind of row is ever left with an empty frame where its mark
    /// should be. See ``SymbolMark``.
    var suggested: [String] = Board.startingSymbols
    var fallback: String = SymbolMark.boardFallback
    var title: String = String(localized: "Select Icon", comment: "The icon button's label")
    let onSelect: (String) -> Void

    @State private var isPicking = false

    var body: some View {
        Button { isPicking = true } label: {
            HStack(spacing: 8) {
                Image(systemName: SymbolMark.resolved(selection, fallback: fallback))
                    .symbolSize(metrics.glyph, weight: .medium, relativeTo: .body)
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(palette.ui(metrics.font, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink(0.75))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(height: metrics.height)
            .background(palette.ink(0.06), in: .rect(cornerRadius: metrics.radius))
            .overlay {
                RoundedRectangle(cornerRadius: metrics.radius)
                    .strokeBorder(palette.ink(0.1), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .bareButton()
        .accessibilityLabel(title)
        // The name of the symbol, which is the only description there is: SF
        // Symbols carry no localized label, and `flag.checkered` read aloud is
        // still what was chosen. The colour well answers the same way with a
        // hex when the colour has no name.
        .accessibilityValue(selection)
        // The colour well's placement argument, unchanged and for the same
        // measured reason — see ``ColorWell/arrowEdge``.
        .popover(isPresented: $isPicking, arrowEdge: ColorWell.arrowEdge) {
            SymbolPickerPopover(
                selection: selection, metrics: metrics.picker,
                suggested: suggested, adaptation: adaptation
            ) { picked in
                onSelect(picked)
            }
            .environment(\.palette, palette)
        }
    }

    /// A sheet where a popover will not fit, which on this control is a lower
    /// bar than the colour well's: the grid wants every point of height it can
    /// get, and a phone lying down has none to give. See ``ColorWell/adaptation``.
    private var adaptation: PresentationAdaptation {
        #if os(iOS)
        verticalSizeClass == .compact ? .sheet : .popover
        #else
        .popover
        #endif
    }
}
