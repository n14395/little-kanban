import SwiftUI

/// The picker behind every ``ColorWell``: the saved colours, a spectrum to mix
/// a new one in, and the hex of whatever is currently chosen.
///
/// **The saved colours are the board's, not this view's.** `BoardStore.savedColors`
/// is one list for the whole app, so a colour saved while recolouring a column
/// is offered the next time a board, a column or a label is recoloured, and one
/// deleted here leaves every other picker with it. See ``PaletteSwatch``.
///
/// **What commits, and when.** Pressing a saved swatch is a whole act — it
/// chooses that colour and closes. The spectrum and the hex field are not: they
/// move a *draft*, and the draft lands when the picker goes away. That split is
/// the difference between one undo step and forty, because every colour this
/// returns is a store mutation with a ⌘Z of its own, and a drag across the
/// spectrum passes through a hundred colours nobody chose.
struct ColorPickerPopover: View {
    struct Metrics {
        var width: CGFloat
        var swatch: CGFloat
        var swatchHit: CGFloat
        var spectrumHeight: CGFloat
        var hueWidth: CGFloat
        var font: CGFloat
        var hit: CGFloat
        var spacing: CGFloat

        static let desk = Metrics(
            width: 268, swatch: 20, swatchHit: 26, spectrumHeight: 132,
            hueWidth: 16, font: 12.5, hit: 28, spacing: 12
        )
        static let sheet = Metrics(
            width: 320, swatch: 26, swatchHit: 44, spectrumHeight: 160,
            hueWidth: 26, font: 14.5, hit: 44, spacing: 14
        )
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let selection: SwatchColor
    var metrics: Metrics = .desk
    let onSelect: (SwatchColor) -> Void

    /// The colour the spectrum and the hex field are moving, which is not the
    /// selection until this view goes away — see the note above.
    @State private var draft = ColorMath.HSB(hue: 0, saturation: 0, brightness: 0)
    /// What the hex field holds. A string of its own rather than a formatting of
    /// `draft`, because a half-typed `#C2` is not a colour and the field must
    /// not snap back to `#C20000` under the cursor between keystrokes.
    @State private var hexText = ""
    @State private var hasLoaded = false
    @FocusState private var isHexFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            saved
            spectrum
            hexRow
            buttons
        }
        .padding(metrics.spacing)
        .frame(width: metrics.width)
        .background(palette.card)
        .presentationBackground(palette.card)
        #if os(iOS)
        // A popover on the phone too, rather than the sheet iOS would adapt it
        // into: this is a control hanging off a button, and a sheet that covers
        // the surface the colour is being chosen *for* hides the thing being
        // decided about.
        .presentationCompactAdaptation(.popover)
        #endif
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            draft = ColorMath.hsb(of: openingValue)
            hexText = ColorMath.hexString(openingValue)
        }
        .onDisappear(perform: commitDraft)
    }

    // MARK: The saved colours

    private var saved: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saved").sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
            FlowLayout(spacing: 0) {
                ForEach(store.savedColors) { entry in
                    swatchButton(entry)
                }
            }
        }
    }

    private func swatchButton(_ entry: PaletteSwatch) -> some View {
        let isCurrent = entry.swatch == selection
        return Button {
            // A saved colour is a finished choice: taken, and the picker closes
            // on it. The draft follows so the spectrum does not put the old
            // colour back on the way out.
            draft = ColorMath.hsb(of: value(of: entry.swatch) ?? openingValue)
            hexText = ColorMath.hexString(value(of: entry.swatch) ?? openingValue)
            onSelect(entry.swatch)
            dismiss()
        } label: {
            Circle()
                .fill(palette.resolve(entry.swatch))
                .frame(width: metrics.swatch, height: metrics.swatch)
                .padding(3)
                .overlay {
                    Circle().strokeBorder(isCurrent ? palette.ink(0.45) : .clear, lineWidth: 2)
                }
                .frame(minWidth: metrics.swatchHit, minHeight: metrics.swatchHit)
        }
        .buttonStyle(.bare)
        .help(entry.displayName)
        .accessibilityLabel(entry.displayName)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
        // **Deleting is a menu rather than a badge**: an × on every swatch puts
        // a destructive target inside a 26pt circle, next to the target that
        // *chooses* the colour, and the two would be one slip apart. No
        // confirmation, because nothing wearing the colour changes — see
        // `BoardStore.deleteSavedColor`.
        .contextMenu {
            if entry.isRemovable {
                Button(role: .destructive) {
                    store.deleteSavedColor(entry.swatch)
                } label: {
                    Label("Remove from Palette", systemImage: "trash")
                }
            } else {
                // Said rather than left out: an empty menu on one swatch and a
                // full one on the next reads as a bug.
                Text("The accent follows the app’s theme and stays in the palette")
            }
        }
    }

    // MARK: The spectrum

    private var spectrum: some View {
        HStack(spacing: 10) {
            saturationAndBrightness
            hueSlider
        }
        .frame(height: metrics.spectrumHeight)
    }

    /// Saturation left to right, brightness bottom to top — the square every
    /// colour picker on both platforms draws, so the gesture is one people
    /// already have.
    private var saturationAndBrightness: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [.white, Color(hue: draft.hue, saturation: 1, brightness: 1)],
                    startPoint: .leading, endPoint: .trailing
                )
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                knob
                    .position(
                        x: draft.saturation * size.width,
                        y: (1 - draft.brightness) * size.height
                    )
            }
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    setDraft(
                        saturation: drag.location.x / max(size.width, 1),
                        brightness: 1 - drag.location.y / max(size.height, 1)
                    )
                }
            )
        }
        .accessibilityLabel("Colour spectrum")
        .accessibilityValue(ColorMath.hexString(draftValue))
        // A drag surface is not reachable by a reader, and this one has a field
        // under it that names the same colour exactly — see ``hexRow``.
        .accessibilityHint("Type a hex code in the field below to set a colour exactly")
    }

    private var hueSlider: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            LinearGradient(
                colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map {
                    Color(hue: $0, saturation: 1, brightness: 1)
                },
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(.rect(cornerRadius: 6))
            .overlay(alignment: .top) {
                Capsule()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Capsule().fill(.clear))
                    .frame(height: 8)
                    .shadow(color: .black.opacity(0.35), radius: 1)
                    .offset(y: draft.hue * height - 4)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    setDraft(hue: drag.location.y / max(height, 1))
                }
            )
        }
        .frame(width: metrics.hueWidth)
        .accessibilityLabel("Hue")
        .accessibilityValue(ColorMath.hexString(draftValue))
    }

    private var knob: some View {
        Circle()
            .strokeBorder(.white, lineWidth: 2)
            .background(Circle().fill(Color(hex: draftValue)))
            .frame(width: 14, height: 14)
            .shadow(color: .black.opacity(0.35), radius: 1)
            .allowsHitTesting(false)
    }

    // MARK: The hex

    private var hexRow: some View {
        HStack(spacing: 8) {
            Text("Hex").sectionLabelStyle(size: 10.5, tracking: 0.08, opacity: Palette.readableInk)
            TextField("Hex", text: $hexText)
                .textFieldStyle(.plain)
                .font(SimpleKanbanFont.ui(metrics.font, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)
                .focused($isHexFocused)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                #endif
                .onChange(of: hexText) { _, typed in
                    // Only when it is a colour. Everything else is somebody
                    // part-way through typing one.
                    guard let value = ColorMath.hexValue(typed) else { return }
                    draft = ColorMath.hsb(of: value)
                }
                .onSubmit { normaliseHex() }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: metrics.hit, alignment: .leading)
                .background(palette.ink(0.06), in: .rect(cornerRadius: 8))
                .accessibilityLabel("Hex code")
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: draftValue))
                .frame(width: metrics.hit + 6, height: metrics.hit)
                .overlay {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(palette.ink(0.15), lineWidth: 1)
                }
                .accessibilityHidden(true)
        }
    }

    // MARK: The two buttons

    private var buttons: some View {
        HStack(spacing: 8) {
            Button { store.saveColor(.hex(draftValue)) } label: {
                Text("Save to Palette")
                    .font(SimpleKanbanFont.ui(metrics.font, .bold, relativeTo: .subheadline))
                    .foregroundStyle(isSaved ? palette.inkText(0.35) : palette.accent)
                    .padding(.horizontal, 10)
                    .frame(minHeight: metrics.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)
            // Nothing to do rather than nothing to say: the colour is already
            // in the row above, where the ring is.
            .disabled(isSaved)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Done")
                    .font(SimpleKanbanFont.ui(metrics.font, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: metrics.hit)
                    .background(palette.accent, in: .rect(cornerRadius: 9))
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)
        }
    }

    // MARK: What the draft is

    private var draftValue: UInt32 { ColorMath.value(of: draft) }

    private var isSaved: Bool {
        store.savedColors.contains { $0.swatch == .hex(draftValue) }
    }

    /// The colour the picker opens on. `.ink` has no literal — it is one colour
    /// in light and another in dark — so the spectrum starts from what the theme
    /// is drawing it as, which is the colour on screen.
    private var openingValue: UInt32 {
        value(of: selection) ?? 0x8A8A8A
    }

    private func value(of swatch: SwatchColor) -> UInt32? {
        switch swatch {
        case .rgb(let value, _): value
        case .accent: palette.accentTheme.hex
        case .ink: nil
        }
    }

    private func setDraft(hue: Double? = nil, saturation: Double? = nil, brightness: Double? = nil) {
        draft = ColorMath.HSB(
            hue: hue ?? draft.hue,
            saturation: saturation ?? draft.saturation,
            brightness: brightness ?? draft.brightness
        )
        hexText = ColorMath.hexString(draftValue)
    }

    private func normaliseHex() {
        hexText = ColorMath.hexString(draftValue)
        isHexFocused = false
    }

    /// The draft lands on the way out, and only if it is a different colour from
    /// the one the picker opened on — a picker opened and closed again has not
    /// recoloured anything, and must not cost a ⌘Z that says it did.
    private func commitDraft() {
        guard hasLoaded, draftValue != openingValue else { return }
        onSelect(.hex(draftValue))
    }
}
