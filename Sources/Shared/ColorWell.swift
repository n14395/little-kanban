import SwiftUI

/// **The one colour control in the app**: a button wearing the colour it has,
/// which opens ``ColorPickerPopover``.
///
/// It replaced `DotPicker`, a row of six fixed swatches that every surface drew
/// inline. The row could only ever offer what was written into the source, and
/// it cost a line of six 44pt targets wherever it appeared — which is why the
/// add-column composer had to be measured against a landscape keyboard twice.
/// A button is one target, says what is currently chosen without a ring to
/// read, and has room behind it for a picker that would never have fitted in a
/// row.
///
/// The label is the same words everywhere, and they are words rather than a
/// bare swatch: a coloured rectangle with no text is a thing a person has to
/// have been told about, and this one is often the only control in its section.
struct ColorWell: View {
    struct Metrics {
        var font: CGFloat
        var height: CGFloat
        var radius: CGFloat
        var horizontalPadding: CGFloat
        /// The popover's own sizes, which are a finger's or a pointer's.
        var picker: ColorPickerPopover.Metrics

        static let desk = Metrics(
            font: 12.5, height: 30, radius: 9, horizontalPadding: 12, picker: .desk
        )
        static let sheet = Metrics(
            font: 14.5, height: 44, radius: 11, horizontalPadding: 14, picker: .sheet
        )
    }

    @Environment(\.palette) private var palette

    /// The colour the button wears, and the one the picker opens on.
    let selection: SwatchColor
    var metrics: Metrics = .desk
    let onSelect: (SwatchColor) -> Void

    @State private var isPicking = false

    var body: some View {
        Button { isPicking = true } label: {
            Text("Select Colour")
                .font(SimpleKanbanFont.ui(metrics.font, .bold, relativeTo: .subheadline))
                .foregroundStyle(readableInk)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(height: metrics.height)
                .background(palette.resolve(selection), in: .rect(cornerRadius: metrics.radius))
                // A pale colour on a pale card is a button with no edges. The
                // hairline is the colour's own ink at a low weight, so it reads
                // as the swatch's own outline rather than as a border.
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.radius)
                        .strokeBorder(readableInk.opacity(0.18), lineWidth: 1)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.bare)
        .accessibilityLabel("Select Colour")
        .accessibilityValue(name)
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            ColorPickerPopover(selection: selection, metrics: metrics.picker) { picked in
                onSelect(picked)
            }
            .environment(\.palette, palette)
        }
    }

    /// Black or white, whichever the colour underneath can be read against —
    /// see ``ColorMath/prefersDarkText(on:)``. Not `palette.ink`: the button's
    /// ground is the *chosen* colour rather than the theme's, so a light theme
    /// with a near-black swatch on it needs light text, which the theme's ink
    /// is not.
    private var readableInk: Color {
        guard let value = resolvedValue else { return palette.onAccent }
        return ColorMath.prefersDarkText(on: value) ? Color(hex: 0x141211) : Color(hex: 0xFCFBF9)
    }

    /// The selection as a literal, where it is one. `.accent` resolves through
    /// the theme; `.ink` cannot, being one colour in light and another in dark,
    /// so it falls back to the theme's own answer for text on accent.
    private var resolvedValue: UInt32? {
        switch selection {
        case .rgb(let value, _): value
        case .accent: palette.accentTheme.hex
        case .ink: nil
        }
    }

    private var name: String { PaletteSwatch(selection).displayName }
}
