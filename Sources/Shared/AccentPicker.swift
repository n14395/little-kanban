import SwiftUI

/// The four accent options the design exposes as an editable prop, as a row of
/// swatches. The current one is ringed rather than ticked — at this size a tick
/// would cover the colour being chosen.
struct AccentPicker: View {
    struct Metrics {
        var swatch: CGFloat
        var ringGap: CGFloat
        var ringWidth: CGFloat
        var spacing: CGFloat

        static let desk = Metrics(swatch: 14, ringGap: 3.5, ringWidth: 1.5, spacing: 9)
        static let drawer = Metrics(swatch: 18, ringGap: 4, ringWidth: 2, spacing: 12)
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var metrics: Metrics = .desk

    var body: some View {
        HStack(spacing: metrics.spacing) {
            Text("Accent")
                .sectionLabelStyle(tracking: 0.08, opacity: 0.4)
            Spacer(minLength: 0)
            ForEach(AccentTheme.allCases) { theme in
                swatchButton(theme)
            }
        }
    }

    private func swatchButton(_ theme: AccentTheme) -> some View {
        let isCurrent = theme == store.accentTheme
        // Each swatch shows its own accent, not the active one, so the row
        // reads as a set of choices rather than four copies of the current pick.
        let preview = Palette(colorScheme: palette.colorScheme, accentTheme: theme).accent

        return Button {
            store.setAccentTheme(theme)
        } label: {
            Circle()
                .fill(preview)
                .frame(width: metrics.swatch, height: metrics.swatch)
                .padding(metrics.ringGap)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isCurrent ? preview : .clear,
                            lineWidth: metrics.ringWidth
                        )
                }
        }
        .buttonStyle(.bare)
        .help(theme.label)
        .accessibilityLabel(theme.label)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}
