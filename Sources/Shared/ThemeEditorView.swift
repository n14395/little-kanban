import SwiftUI

/// Every parameter of one theme, editable.
///
/// **The sections are the design document's, in its order and under its
/// names** — display font, ui font, window bg, panel overlay, card, ink, wash,
/// highlight, status hues, label chips, due chips — and the note under each one
/// is that document's own line about where the parameter shows up. Somebody with
/// the explorer open in one window and this in the other should not have to
/// translate between them.
///
/// The picture at the top is the same ``ThemePreviewTile`` the browser draws,
/// larger, and it follows the draft: a colour changed here repaints it before
/// the mouse has left the picker. Nothing is applied to the app until **Save**,
/// so a theme can be taken apart and abandoned.
struct ThemeEditorView: View {
    struct Metrics: Sendable {
        var width: CGFloat?
        /// See ``ThemeBrowserView/Metrics/minHeight``. A form of thirty rows
        /// behind a 420pt window is a form nobody can see the shape of.
        var minHeight: CGFloat?
        var padding: CGFloat
        var sectionSpacing: CGFloat
        var titleSize: CGFloat
        var headingSize: CGFloat
        var previewScale: CGFloat
        var field: ThemeField.Metrics
        var showsHeader: Bool

        static let desk = Metrics(
            width: 600, minHeight: 680, padding: 20, sectionSpacing: 20, titleSize: 16,
            headingSize: 10, previewScale: 1.6, field: .desk, showsHeader: true
        )
        static let sheet = Metrics(
            width: nil, minHeight: nil, padding: 18, sectionSpacing: 24, titleSize: 18,
            headingSize: 11.5, previewScale: 1.25, field: .sheet, showsHeader: true
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var metrics: Metrics = .desk
    /// Handed the theme when Save is pressed. The browser is what decides
    /// whether that also means selecting it.
    let onSave: (Theme) -> Void

    @State private var draft: Theme
    @State private var isExporting = false

    init(theme: Theme, metrics: Metrics = .desk, onSave: @escaping (Theme) -> Void) {
        self.metrics = metrics
        self.onSave = onSave
        _draft = State(initialValue: theme)
    }

    var body: some View {
        VStack(spacing: 0) {
            if metrics.showsHeader {
                header.hairline(.bottom, color: palette.ink(0.08))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    preview
                    identity
                    fonts
                    ground
                    surfaces
                    inkSection
                    highlight
                    status
                    chips
                }
                .padding(metrics.padding)
            }
        }
        .frame(width: metrics.width)
        .frame(minHeight: metrics.minHeight, maxHeight: .infinity)
        .background(palette.windowFill)
        .presentationBackground(palette.windowFill)
        .fileExporter(
            isPresented: $isExporting,
            document: ThemeDocument([draft]),
            contentType: .json,
            defaultFilename: ThemeDocument.filename(for: draft)
        ) { _ in }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 10) {
            Text("Edit Theme")
                .font(palette.display(metrics.titleSize))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 0)
            Button {
                isExporting = true
            } label: {
                Label(
                    String(localized: "Export…", comment: "Button: writes the theme out as a JSON file"),
                    systemImage: "square.and.arrow.up"
                )
                .labelStyle(.iconOnly)
                .font(palette.ui(metrics.titleSize - 3, .bold, relativeTo: .subheadline))
                .foregroundStyle(palette.inkText(0.5))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.bare)
            .help(String(localized: "Export this theme as JSON",
                         comment: "Tooltip on the theme export button"))

            Button { dismiss() } label: {
                Text("Cancel")
                    .font(palette.ui(metrics.titleSize - 3, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.inkText(0.55))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)

            Button {
                onSave(draft)
                dismiss()
            } label: {
                Text("Save")
                    .font(palette.ui(metrics.titleSize - 3, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(palette.accent, in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)
            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, metrics.padding)
        .padding(.vertical, 12)
    }

    private var preview: some View {
        // Centred and on its own, because it is the answer to every field
        // below it and reading it against the form is what the form is for.
        HStack {
            Spacer(minLength: 0)
            ThemePreviewTile(theme: draft, scale: metrics.previewScale)
            Spacer(minLength: 0)
        }
    }

    // MARK: The sections

    private var identity: some View {
        section(String(localized: "Theme", comment: "Theme editor section: the theme's own name and kind")) {
            ThemeFieldRow(title: String(localized: "Name", comment: "Theme parameter: what the theme is called"), metrics: metrics.field) {
                TextField(
                    String(localized: "Name", comment: "Placeholder in the theme name field"),
                    text: $draft.name
                )
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.field.valueFont, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 8)
                .frame(width: 200, height: max(metrics.field.hit, 26))
                .background(palette.ink(0.06), in: .rect(cornerRadius: 7))
            }
            ThemeFieldRow(
                title: String(localized: "Slot", comment: "Theme parameter: whether the theme is the light or the dark one"),
                note: String(localized: "Which half of the system's appearance this theme fills. Light and dark are separate choices — see Appearance in Settings.",
                             comment: "Explains that a theme fills either the light slot or the dark one"),
                metrics: metrics.field
            ) {
                Picker(selection: $draft.appearance) {
                    ForEach(ThemeAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                } label: {
                    Text("Slot", comment: "Accessibility label of the picker choosing which appearance a theme fills")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    private var fonts: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            section(String(localized: "Display font", comment: "Theme editor section heading, from the design document")) {
                ThemeFieldRow(
                    title: String(localized: "Face", comment: "Theme parameter: which font family"),
                    note: String(localized: "Board titles and the task title in the inspector. Nothing else.",
                                 comment: "Where the display font is used, from the design document"),
                    metrics: metrics.field
                ) {
                    ThemeFontField(font: $draft.displayFont, showsItalic: true, metrics: metrics.field)
                }
                fallbackNote(for: draft.displayFont)
            }
            section(String(localized: "UI font", comment: "Theme editor section heading, from the design document")) {
                ThemeFieldRow(
                    title: String(localized: "Face", comment: "Theme parameter: which font family"),
                    note: String(localized: "All other text. The weight is a baseline: the app's own weights shift with it, so 400 leaves them exactly where they were written.",
                                 comment: "Where the UI font is used and what its weight means"),
                    metrics: metrics.field
                ) {
                    ThemeFontField(font: $draft.uiFont, showsItalic: false, metrics: metrics.field)
                }
                fallbackNote(for: draft.uiFont)
            }
        }
    }

    private var ground: some View {
        section(String(localized: "Window bg", comment: "Theme editor section heading, from the design document")) {
            ThemeGradientField(gradient: $draft.windowBackground, metrics: metrics.field)
        }
    }

    private var surfaces: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            section(String(localized: "Panel overlay", comment: "Theme editor section heading, from the design document")) {
                ThemeFieldRow(
                    title: String(localized: "Overlay", comment: "Theme parameter: the wash over the sidebar and inspector"),
                    note: String(localized: "Sidebar and inspector, layered over the window bg — so the gradient runs through them.",
                                 comment: "Where the panel overlay is used, from the design document"),
                    metrics: metrics.field
                ) {
                    ThemeColorField(color: $draft.panelOverlay, metrics: metrics.field)
                }
            }
            section(String(localized: "Card", comment: "Theme editor section heading, from the design document")) {
                ThemeFieldRow(title: String(localized: "Fill", comment: "Theme parameter: a card's background"), metrics: metrics.field) {
                    ThemeColorField(color: $draft.card.fill, metrics: metrics.field)
                }
                ThemeFieldRow(title: String(localized: "Border", comment: "Theme parameter: a card's hairline"), metrics: metrics.field) {
                    ThemeColorField(color: $draft.card.border, metrics: metrics.field)
                }
                ThemeFieldRow(
                    title: String(localized: "Radius", comment: "Theme parameter: how round a card's corners are"),
                    note: String(localized: "The one size the design varies from theme to theme.",
                                 comment: "Note under the card radius field"),
                    metrics: metrics.field
                ) {
                    ThemeNumberField(
                        label: String(localized: "Radius",
                                      comment: "Accessibility label of the card corner radius field"),
                        value: $draft.card.radius, range: 0...28, suffix: "pt", metrics: metrics.field
                    )
                }
            }
        }
    }

    private var inkSection: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            section(String(localized: "Ink", comment: "Theme editor section heading, from the design document")) {
                ThemeFieldRow(title: String(localized: "Text", comment: "Theme parameter: the full-strength text colour"), metrics: metrics.field) {
                    ThemeColorField(color: $draft.ink.base, showsOpacity: false, metrics: metrics.field)
                }
                ThemeFieldRow(
                    title: String(localized: "Muted", comment: "Theme parameter: the middle tier of ink"),
                    metrics: metrics.field
                ) {
                    ThemeNumberField(
                        label: String(localized: "Muted",
                                      comment: "Accessibility label of the middle ink tier's strength field"),
                        value: Binding(get: { draft.ink.muted * 100 }, set: { draft.ink.muted = $0 / 100 }),
                        range: 0...100, suffix: "%", metrics: metrics.field
                    )
                }
                ThemeFieldRow(
                    title: String(localized: "Faint", comment: "Theme parameter: the quietest tier of ink"),
                    note: String(localized: "Rules, dots and meter tracks take these exactly. Text does not go below 68% — the contrast floor is not a style choice.",
                                 comment: "Explains that the ink tiers are floored for text"),
                    metrics: metrics.field
                ) {
                    ThemeNumberField(
                        label: String(localized: "Faint",
                                      comment: "Accessibility label of the quietest ink tier's strength field"),
                        value: Binding(get: { draft.ink.faint * 100 }, set: { draft.ink.faint = $0 / 100 }),
                        range: 0...100, suffix: "%", metrics: metrics.field
                    )
                }
            }
            section(String(localized: "Wash", comment: "Theme editor section heading, from the design document")) {
                ThemeFieldRow(
                    title: String(localized: "Wash", comment: "Theme parameter: the faint fill behind quiet controls"),
                    note: String(localized: "Search field, count pills, the segmented track, an empty meter, and any due date further out than soon.",
                                 comment: "Where the wash is used, from the design document"),
                    metrics: metrics.field
                ) {
                    ThemeColorField(color: $draft.wash, metrics: metrics.field)
                }
            }
        }
    }

    private var highlight: some View {
        section(String(localized: "Highlight", comment: "Theme editor section heading, from the design document")) {
            ThemeFieldRow(
                title: String(localized: "Accent", comment: "Theme parameter: the app's highlight colour"),
                note: String(localized: "Selected-card outline, the active board row, the active segment, + buttons, meter fill, high priority.",
                             comment: "Where the accent is used, from the design document"),
                metrics: metrics.field
            ) {
                ThemeColorField(color: $draft.highlight.accent, showsOpacity: false, metrics: metrics.field)
            }
            ThemeFieldRow(
                title: String(localized: "Soft", comment: "Theme parameter: the accent as a tint"),
                metrics: metrics.field
            ) {
                ThemeColorField(color: $draft.highlight.soft, metrics: metrics.field)
            }
            ThemeFieldRow(
                title: String(localized: "On accent", comment: "Theme parameter: what is drawn on top of the accent"),
                note: String(localized: "What survives on top of it: a filled button's label, the tick in a completed checkbox.",
                             comment: "Explains the on-accent colour"),
                metrics: metrics.field
            ) {
                ThemeColorField(color: $draft.highlight.onAccent, showsOpacity: false, metrics: metrics.field)
            }
        }
    }

    private var status: some View {
        section(String(localized: "Status hues", comment: "Theme editor section heading, from the design document")) {
            // One row where the design document has two: the amber status hue
            // lost its last reader when the priority marks became traffic
            // lights — see `ThemeStatus`, which keeps the field only so files
            // round-trip. A control that changes nothing is not offered.
            ThemeFieldRow(
                title: String(localized: "Done", comment: "Theme parameter: the colour finished work reads as"),
                note: String(localized: "A finished task's date chip, and a full meter. Overdue has no field of its own — it is the hot due chip below.",
                             comment: "Where the done hue is used, and why there is no overdue status hue"),
                metrics: metrics.field
            ) {
                ThemeColorField(color: $draft.status.done, showsOpacity: false, metrics: metrics.field)
            }
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            section(String(localized: "Label chips", comment: "Theme editor section heading, from the design document")) {
                chipPreview
                ThemeFieldRow(
                    title: String(localized: "Ground lift", comment: "Theme parameter: how far a chip's ground is lightened before tinting"),
                    note: String(localized: "A theme sets the recipe rather than the colours — each label carries its own. The ground is the label's colour lifted this far towards white, then drawn at the strength below.",
                                 comment: "Explains that the theme carries the chip rule, not the chip colours"),
                    metrics: metrics.field
                ) {
                    ThemeNumberField(
                        label: String(localized: "Ground lift",
                                      comment: "Accessibility label of how far a label chip's ground is lifted"),
                        value: Binding(get: { draft.labelChips.backgroundLift * 100 },
                                       set: { draft.labelChips.backgroundLift = $0 / 100 }),
                        range: -100...100, suffix: "%", metrics: metrics.field
                    )
                }
                ThemeFieldRow(
                    title: String(localized: "Ground strength", comment: "Theme parameter: the opacity of a chip's ground"),
                    metrics: metrics.field
                ) {
                    ThemeNumberField(
                        label: String(localized: "Ground strength",
                                      comment: "Accessibility label of a label chip ground's opacity"),
                        value: Binding(get: { draft.labelChips.backgroundOpacity * 100 },
                                       set: { draft.labelChips.backgroundOpacity = $0 / 100 }),
                        range: 0...100, suffix: "%", metrics: metrics.field
                    )
                }
                ThemeFieldRow(
                    title: String(localized: "Text shade", comment: "Theme parameter: how far a chip's text is taken from the label's colour"),
                    note: String(localized: "Positive takes the text towards white, negative towards black.",
                                 comment: "Explains the sign of the chip text shade"),
                    metrics: metrics.field
                ) {
                    ThemeNumberField(
                        label: String(localized: "Text shade",
                                      comment: "Accessibility label of how far a label chip's text is shaded"),
                        value: Binding(get: { draft.labelChips.foregroundShade * 100 },
                                       set: { draft.labelChips.foregroundShade = $0 / 100 }),
                        range: -100...100, suffix: "%", metrics: metrics.field
                    )
                }
            }
            section(String(localized: "Due chips", comment: "Theme editor section heading, from the design document")) {
                ThemeFieldRow(
                    title: String(localized: "Overdue ground", comment: "Theme parameter: the background of an overdue date chip"),
                    note: String(localized: "Overdue and today. Its colour at full strength is also what max priority wears.",
                                 comment: "Explains that the overdue chip's hue doubles as the alarm colour"),
                    metrics: metrics.field
                ) {
                    ThemeColorField(color: $draft.dueChips.hot.background, metrics: metrics.field)
                }
                ThemeFieldRow(title: String(localized: "Overdue text", comment: "Theme parameter: the text of an overdue date chip"), metrics: metrics.field) {
                    ThemeColorField(color: $draft.dueChips.hot.foreground, showsOpacity: false, metrics: metrics.field)
                }
                ThemeFieldRow(
                    title: String(localized: "Soon ground", comment: "Theme parameter: the background of a due-soon date chip"),
                    note: String(localized: "The next couple of days. Anything further out takes the wash.",
                                 comment: "Explains which dates take the warm chip, from the design document"),
                    metrics: metrics.field
                ) {
                    ThemeColorField(color: $draft.dueChips.warm.background, metrics: metrics.field)
                }
                ThemeFieldRow(title: String(localized: "Soon text", comment: "Theme parameter: the text of a due-soon date chip"), metrics: metrics.field) {
                    ThemeColorField(color: $draft.dueChips.warm.foreground, showsOpacity: false, metrics: metrics.field)
                }
            }
        }
    }

    /// The rule, applied to real label colours, so the three numbers above have
    /// something to be read against. The board's own palette rather than an
    /// invented row of hues: these are the colours the user's labels are
    /// actually made from.
    private var chipPreview: some View {
        let draftPalette = Palette(theme: draft)
        return FlowLayout(spacing: 6) {
            ForEach(store.savedColors.prefix(6)) { entry in
                let tone = draftPalette.chipTone(for: entry.swatch)
                Text(entry.displayName)
                    .font(draftPalette.ui(metrics.field.noteFont, .extraBold, relativeTo: .caption2))
                    .kerning(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(tone.foreground)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tone.background, in: .rect(cornerRadius: 6))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(draftPalette.card, in: .rect(cornerRadius: draft.card.radius))
        .accessibilityLabel(String(localized: "Label chips as this theme draws them",
                                   comment: "Accessibility name of the live chip preview"))
    }

    // MARK: Pieces

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .sectionLabelStyle(size: metrics.headingSize)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(palette.card, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(palette.ink(0.07), lineWidth: 1)
            }
        }
    }

    /// Said only when it is true: this face is not one the app carries, so the
    /// theme will not look like this anywhere else.
    @ViewBuilder
    private func fallbackNote(for font: ThemeFont) -> some View {
        if !FontCatalog.isBundled(font.family) {
            Text("This face is not bundled with the app. A copy of this theme opened on another device falls back to a system font.")
                .font(palette.ui(metrics.field.noteFont, .medium, relativeTo: .caption2))
                .foregroundStyle(palette.inkText(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
        }
    }
}
