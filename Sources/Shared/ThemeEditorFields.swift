import SwiftUI

/// The handful of controls the theme editor is built out of.
///
/// Pulled out of ``ThemeEditorView`` because there are twenty-five colours,
/// nine numbers and two faces in a theme, and a form that spelled each one out
/// inline would be a thousand lines in which the *arrangement* — which is the
/// only interesting part — could not be seen.
enum ThemeField {
    struct Metrics: Sendable {
        var labelFont: CGFloat
        var noteFont: CGFloat
        var valueFont: CGFloat
        var fieldWidth: CGFloat
        var rowHeight: CGFloat
        var hit: CGFloat
        var well: ColorWell.Metrics

        static let desk = Metrics(
            labelFont: 12, noteFont: 10.5, valueFont: 11.5,
            fieldWidth: 62, rowHeight: 30, hit: 26, well: .compact
        )
        static let sheet = Metrics(
            labelFont: 15, noteFont: 12.5, valueFont: 14,
            fieldWidth: 76, rowHeight: 44, hit: 44, well: .compact
        )
    }
}

/// A name on the left, a control on the right, and an optional line of why
/// underneath. Every row in the editor is one of these.
struct ThemeFieldRow<Control: View>: View {
    @Environment(\.palette) private var palette

    let title: String
    var note: String?
    var metrics: ThemeField.Metrics = .desk
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(palette.ui(metrics.labelFont, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink)
                if let note {
                    Text(note)
                        .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption2))
                        .foregroundStyle(palette.inkText(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.vertical, 5)
        .frame(minHeight: metrics.rowHeight)
    }
}

/// A colour, and the strength it is drawn at.
///
/// The button is the app's one ``ColorWell`` — the same control, over the same
/// saved palette, as the one that colours a board, a column or a label, so a
/// colour mixed while building a theme is offered the next time a label is
/// coloured and the other way round.
///
/// **Opacity is a field of its own** rather than a fourth pair of digits in the
/// picker's hex. Two of a theme's colours are only meaningful as tints — the
/// panel overlay *is* an alpha, and so is the wash — and the design document
/// states them as `rgba(...)` with the alpha written out. A number you can type
/// is what "specified exactly" asks for.
struct ThemeColorField: View {
    @Environment(\.palette) private var palette

    @Binding var color: ThemeColor
    var showsOpacity: Bool = true
    var metrics: ThemeField.Metrics = .desk

    var body: some View {
        HStack(spacing: 8) {
            ColorWell(selection: .hex(color.hex), metrics: metrics.well) { picked in
                if case .rgb(let hex, _) = picked { color = ThemeColor(hex, opacity: color.opacity) }
            }
            .frame(width: 108)
            if showsOpacity {
                ThemeNumberField(
                    label: String(localized: "Opacity",
                                  comment: "Accessibility label of the strength field beside a theme colour"),
                    value: Binding(
                        get: { color.opacity * 100 },
                        set: { color = color.withOpacity($0 / 100) }
                    ),
                    range: 0...100, suffix: "%", metrics: metrics
                )
            }
        }
    }
}

/// A number, typed. Not a slider: the parameters this edits are things like
/// `0.09` and `11pt`, and the difference between a theme and a near-miss of one
/// is a value you can read back and a value you dragged to.
///
/// Commits on return and on losing focus, and refuses what it cannot read — a
/// field half-way through `1` on its way to `13` must not clamp to 1 under the
/// cursor.
///
/// **And it commits every readable keystroke into the binding as it is
/// typed.** Return and focus loss are not moments the iOS editor can count
/// on: the decimal pad has no Return, and Save does not resign focus — so a
/// value whose only commit was those two was silently discarded by the very
/// button that promises to keep it. Writing the parse live costs nothing the
/// editor did not already promise ("the preview follows the draft") and only
/// the *text* is protected from being reformatted under the cursor: that
/// still happens at the real boundaries alone.
struct ThemeNumberField: View {
    @Environment(\.palette) private var palette

    /// What VoiceOver calls this field, since the control draws no label of
    /// its own — the name is in the ``ThemeFieldRow`` beside it, which is a
    /// separate element and is read out separately.
    ///
    /// No default. There are nine of these and each one edits a different
    /// number; a default would be a label that is wrong at eight of them, and
    /// the whole defect this parameter exists for is a field nobody can name.
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var suffix: String = ""
    var decimals: Int = 0
    var metrics: ThemeField.Metrics = .desk

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 3) {
            TextField(text: $text) { Text(label) }
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .onSubmit(commit)
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                // The live half of the contract above. Guarded on focus so a
                // programmatic text reset does not write back into the value
                // it was reset from.
                .onChange(of: text) { _, typed in
                    guard isFocused,
                          let parsed = Double(typed.replacingOccurrences(of: ",", with: "."))
                    else { return }
                    value = min(max(parsed, range.lowerBound), range.upperBound)
                }
            if !suffix.isEmpty {
                Text(suffix)
                    .foregroundStyle(palette.inkText(0.4))
            }
        }
        .font(palette.ui(metrics.valueFont, .semibold, relativeTo: .subheadline))
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 7)
        .frame(width: metrics.fieldWidth, height: max(metrics.hit, 26))
        .background(palette.ink(0.06), in: .rect(cornerRadius: 7))
        .onAppear { text = formatted(value) }
        .onChange(of: value) { _, new in if !isFocused { text = formatted(new) } }
    }

    private func commit() {
        guard let parsed = Double(text.replacingOccurrences(of: ",", with: ".")) else {
            text = formatted(value)
            return
        }
        value = min(max(parsed, range.lowerBound), range.upperBound)
        text = formatted(value)
    }

    private func formatted(_ number: Double) -> String {
        String(format: "%.\(decimals)f", number)
    }
}

/// A face: the family, the weight it is drawn at, and whether it is slanted.
///
/// The families the app carries come first and the ones this machine happens to
/// have come after, under headings, because the difference matters: a theme
/// built on a bundled face looks the same everywhere it is opened, and one built
/// on a font the user bought falls back to a system face on any machine without
/// it. The note under the row says so when that is what has been chosen.
struct ThemeFontField: View {
    @Environment(\.palette) private var palette

    @Binding var font: ThemeFont
    /// Slant is offered on the display face and not on the UI face: a whole
    /// interface set in italic is not a theme, it is a mistake with a checkbox.
    var showsItalic: Bool
    var metrics: ThemeField.Metrics = .desk

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Section(String(localized: "In the app", comment: "Font picker section: faces the app ships with")) {
                    ForEach(FontCatalog.bundledFamilies, id: \.self) { family in
                        pick(family)
                    }
                }
                Section(String(localized: "Installed", comment: "Font picker section: faces on this machine")) {
                    ForEach(FontCatalog.installedFamilies, id: \.self) { family in
                        pick(family)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(font.family)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(palette.ui(metrics.valueFont - 3, .bold, relativeTo: .caption2))
                        .foregroundStyle(palette.inkText(0.35))
                }
                .font(palette.ui(metrics.valueFont, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)
                .frame(minHeight: max(metrics.hit, 26))
                .contentShape(.rect)
            }
            .modifier(BorderlessMenu())
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(String(localized: "Family", comment: "Accessibility name of the font family picker"))
            .accessibilityValue(font.family)

            Menu {
                ForEach(Self.weights, id: \.value) { weight in
                    Button {
                        font = ThemeFont(font.family, weight: weight.value, italic: font.isItalic)
                    } label: {
                        if weight.value == font.weight {
                            Label(weight.name, systemImage: "checkmark")
                        } else {
                            Text(weight.name)
                        }
                    }
                }
            } label: {
                Text(verbatim: "\(font.weight)")
                    .font(palette.ui(metrics.valueFont, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink)
                    .frame(width: 38, height: max(metrics.hit, 26))
                    .background(palette.ink(0.06), in: .rect(cornerRadius: 7))
            }
            .modifier(BorderlessMenu())
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(String(localized: "Weight", comment: "Accessibility name of the font weight picker"))

            if showsItalic {
                Button {
                    font = ThemeFont(font.family, weight: font.weight, italic: !font.isItalic)
                } label: {
                    Image(systemName: "italic")
                        .font(palette.ui(metrics.valueFont, .bold, relativeTo: .subheadline))
                        .foregroundStyle(font.isItalic ? palette.onAccent : palette.inkText(0.5))
                        .frame(width: 28, height: max(metrics.hit, 26))
                        .background(
                            font.isItalic ? palette.accent : palette.ink(0.06),
                            in: .rect(cornerRadius: 7)
                        )
                }
                .buttonStyle(.bare)
                .accessibilityLabel(String(localized: "Italic", comment: "Accessibility name of the italic toggle"))
                .accessibilityAddTraits(font.isItalic ? [.isSelected] : [])
            }
        }
    }

    private func pick(_ family: String) -> some View {
        Button {
            font = ThemeFont(family, weight: font.weight, italic: font.isItalic)
        } label: {
            if family == font.family {
                Label(family, systemImage: "checkmark")
            } else {
                Text(family)
            }
        }
    }

    /// The nine CSS steps, named the way a type foundry names them.
    static let weights: [(value: Int, name: String)] = [
        (100, "100 · Thin"), (200, "200 · Extra Light"), (300, "300 · Light"),
        (400, "400 · Regular"), (500, "500 · Medium"), (600, "600 · Semibold"),
        (700, "700 · Bold"), (800, "800 · Extra Bold"), (900, "900 · Black"),
    ]
}

/// The window's ground: an angle, and a run of stops that can be added to,
/// re-placed and taken away.
struct ThemeGradientField: View {
    @Environment(\.palette) private var palette

    @Binding var gradient: ThemeGradient
    var metrics: ThemeField.Metrics = .desk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The thing itself, at the angle it is set to, so the number in the
            // field below has something to mean.
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: gradient.gradient,
                    startPoint: gradient.startPoint,
                    endPoint: gradient.endPoint
                ))
                .frame(height: 54)
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(palette.ink(0.12), lineWidth: 1)
                }

            ThemeFieldRow(
                title: String(localized: "Angle", comment: "Theme parameter: the direction of the window gradient"),
                note: String(localized: "0° runs upwards, and the angle turns clockwise.",
                             comment: "Explains how the gradient angle is measured"),
                metrics: metrics
            ) {
                ThemeNumberField(
                    label: String(localized: "Angle",
                                  comment: "Accessibility label of the window gradient's angle field"),
                    value: $gradient.angle, range: 0...360, suffix: "°", metrics: metrics
                )
            }

            // Two percentages on a row is two percentages nobody can tell apart,
            // and they mean quite different things: how strong the colour is, and
            // how far along the ground it sits.
            Text("Colour, strength, and how far along the gradient it sits.")
                .font(palette.ui(metrics.noteFont, .medium, relativeTo: .caption2))
                .foregroundStyle(palette.inkText(0.45))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(gradient.stops.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    ThemeColorField(
                        color: Binding(
                            get: { gradient.stops[index].color },
                            set: { gradient.stops[index].color = $0 }
                        ),
                        metrics: metrics
                    )
                    ThemeNumberField(
                        label: String(localized: "Position",
                                      comment: "Accessibility label of how far along the gradient a stop sits"),
                        value: Binding(
                            get: { gradient.stops[index].location * 100 },
                            set: { gradient.stops[index].location = $0 / 100 }
                        ),
                        range: 0...100, suffix: "%", metrics: metrics
                    )
                    Button {
                        gradient.stops.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(palette.ui(metrics.valueFont + 1, .bold, relativeTo: .subheadline))
                            .foregroundStyle(palette.inkText(0.4))
                            .frame(width: max(metrics.hit, 26), height: max(metrics.hit, 26))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.bare)
                    // One stop is a flat ground, which is a theme somebody may
                    // want. None is not a colour at all.
                    .disabled(gradient.stops.count <= 1)
                    .accessibilityLabel(String(localized: "Remove stop", comment: "Accessibility name of the gradient stop delete button"))
                }
            }

            Button {
                let last = gradient.stops.last
                gradient.stops.append(
                    ThemeGradient.Stop(color: last?.color ?? ThemeColor(0x000000), location: 1)
                )
            } label: {
                Label(
                    String(localized: "Add Stop", comment: "Button: adds a colour stop to the window gradient"),
                    systemImage: "plus"
                )
                .font(palette.ui(metrics.valueFont, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.accent)
                .frame(minHeight: max(metrics.hit, 26))
                .contentShape(.rect)
            }
            .buttonStyle(.bare)
        }
    }
}
