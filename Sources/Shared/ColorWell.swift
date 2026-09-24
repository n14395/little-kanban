// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

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
        /// The theme editor, where twenty-odd of these stand in a column beside
        /// their own labels. Shorter and narrower than the desk's, and the
        /// popover behind it is the same one — that is the whole point of there
        /// being one control.
        static let compact = Metrics(
            font: 11, height: 26, radius: 7, horizontalPadding: 8, picker: .desk
        )
    }

    /// Which side of the well the picker hangs off, or `nil` to let the system
    /// place it — ``BoardColumnView/ColumnEditorMetrics/arrowEdge`` and
    /// ``BoardSidebar/Metrics/trashArrowEdge`` exactly, and for the third time
    /// for the same measured reason.
    ///
    /// A named edge is not a preference on iOS, it is the *only* placement
    /// UIKit is permitted, and `.bottom` permits only "above the button". The
    /// wells that matter have nothing above them: Board Settings draws one
    /// about 220pt down an 874pt screen, so the picker was clamped into the
    /// ~150pt between it and the status bar with the saved row cut off the top
    /// and the two buttons off the bottom, while the whole lower half of the
    /// screen sat empty. Left to choose, UIKit hangs it below the well, which
    /// is where the room is.
    ///
    /// A platform rather than a metric, because ``Metrics/compact`` is worn by
    /// the theme editor on *both* — one field on it cannot want a different
    /// answer from the same field on a phone.
    static let arrowEdge: Edge? = {
        #if os(macOS)
        // A window has room on every side of a well, and AppKit treats the edge
        // as a preference it may overrule rather than the only door.
        .bottom
        #else
        nil
        #endif
    }()

    @Environment(\.palette) private var palette
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    /// The colour the button wears, and the one the picker opens on.
    let selection: SwatchColor
    var metrics: Metrics = .desk
    /// The words on the button. The default is the long form; a surface whose
    /// row already says what the colour is for — the label manager's, where
    /// the chip sits right beside it — hands in the shorter one.
    var title: String = String(localized: "Select Colour", comment: "The colour button's label")
    let onSelect: (SwatchColor) -> Void

    @State private var isPicking = false

    var body: some View {
        Button { isPicking = true } label: {
            Text(title)
                .font(palette.ui(metrics.font, .bold, relativeTo: .subheadline))
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
        .bareButton()
        .accessibilityLabel(title)
        .accessibilityValue(name)
        .popover(isPresented: $isPicking, arrowEdge: Self.arrowEdge) {
            ColorPickerPopover(
                selection: selection, metrics: metrics.picker, adaptation: adaptation
            ) { picked in
                onSelect(picked)
            }
            .environment(\.palette, palette)
        }
    }

    /// What the popover becomes where a popover will not fit — read here rather
    /// than inside it, because once presented its own environment describes the
    /// popover and not the screen the popover has to live on.
    ///
    /// **A landscape phone is the one place it cannot stay a popover.** 402pt of
    /// screen leaves about 180 above the well and 180 below, and the picker is
    /// 425 — and a popover asked for more height than it can have is *clipped*
    /// rather than resized: UIKit shrinks the box and lays the picker out at
    /// full size inside it, so the hex field and both buttons were drawn 100pt
    /// below the bottom edge with no way to scroll to them. A sheet is given
    /// the height it asks for, and is the only container on that screen that
    /// can hold this. Everywhere else — a phone stood up, an iPad, a Mac — the
    /// popover has room and stays one.
    private var adaptation: PresentationAdaptation {
        #if os(iOS)
        verticalSizeClass == .compact ? .sheet : .popover
        #else
        .popover
        #endif
    }

    /// Black or white, whichever the colour underneath can be read against —
    /// see ``ColorMath/prefersDarkText(on:)``. Not `palette.ink`: the button's
    /// ground is the *chosen* colour rather than the theme's, so a light theme
    /// with a near-black swatch on it needs light text, which the theme's ink
    /// is not. Every selection has a literal now that `.accent` and `.ink` are
    /// pinned — see ``SwatchColor/literalValue``.
    private var readableInk: Color {
        ColorMath.prefersDarkText(on: selection.literalValue)
            ? Color(hex: 0x141211) : Color(hex: 0xFCFBF9)
    }

    private var name: String { PaletteSwatch(selection).displayName }
}
