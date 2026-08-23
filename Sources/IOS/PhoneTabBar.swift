#if os(iOS)

import SwiftUI

/// The floating tab pill and quick-capture button.
///
/// The design asks for a blurred, tinted bar here (`--glass` + `backdrop-filter`),
/// which is exactly what Liquid Glass provides natively. Both controls live in a
/// single `GlassEffectContainer` so their materials blend the way two adjacent
/// floating elements should.
///
/// **It runs along the foot in portrait and up the leading edge in landscape.**
/// A phone on its side has around 390pt of height, and this bar was spending
/// 130 of them — the pill, the button, and the room to scroll the last card
/// clear of both — which is a third of the axis that shape has least of. Stood
/// on end it takes about 76pt of an 850pt width instead.
///
/// **The words go with it.** Each slot is a glyph and a word in portrait and
/// the glyph alone on the rail, which is what a bar turned sideways can
/// actually hold: three words standing on end cost 260pt of the run and left
/// the button hanging off the end of the screen at an accessibility size, and
/// a word read bottom-to-top is slower to take in than the icon it was next
/// to. The glyphs are the app's own — the board's, the tray the Inbox is drawn
/// with everywhere else, and the header's magnifier — and each button keeps its
/// name for VoiceOver, which never sees the difference between the two shapes.
struct PhoneTabBar: View {
    /// Which way the bar runs. Everything that differs between the two shapes —
    /// the stacks, which padding is thickness and which is length, and the
    /// ground under it — reads off this one value.
    enum Axis {
        case horizontal, vertical
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var axis: Axis = .horizontal

    private var isVertical: Bool { axis == .vertical }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            stack(spacing: 10) {
                tabPill
                quickCaptureButton
            }
        }
        .padding(.horizontal, isVertical ? 12 : 20)
        .padding(.vertical, 12)
        .background(alignment: isVertical ? .leading : .bottom) { ground }
    }

    /// The bar's two stacks, which are the same stack turned.
    ///
    /// `AnyLayout` rather than an `if`: both shapes hold the same three buttons,
    /// and a branch would hand them new identity on every rotation — a fresh
    /// glass material and a fresh transition each time the phone turns.
    private func stack<Content: View>(
        spacing: CGFloat, @ViewBuilder content: () -> Content
    ) -> some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        return layout(content)
    }

    /// Two destinations and a toggle, drawn as three equal slots.
    ///
    /// **The Inbox is the toggle**, and it sits between them rather than at
    /// either end because that is where it was when it was a tab and because it
    /// is the one thing on this bar you reach for *while* on a board. It raises
    /// ``PhoneInboxSheet`` over whatever is on screen instead of replacing it —
    /// so unlike the other two it does not answer "where am I", and it reads as
    /// current whenever the panel is up, over a saved view included.
    ///
    /// The order is the same in both shapes: leading to trailing becomes top to
    /// bottom, which is where a reader coming from the portrait bar looks.
    private var tabPill: some View {
        stack(spacing: 4) {
            slot(PhoneTab.board.label, symbol: PhoneTab.board.symbol, isCurrent: isCurrent(.board)) {
                store.selectTab(.board)
            }
            slot(Board.inboxName, symbol: SavedView.inbox.symbol, isCurrent: store.isInboxOpen) {
                store.toggleInbox()
            }
            slot(PhoneTab.search.label, symbol: PhoneTab.search.symbol, isCurrent: isCurrent(.search)) {
                store.selectTab(.search)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    /// A saved view has replaced the list, so neither place the tabs name is
    /// what is on screen; highlighting one anyway would be the drawer's inert
    /// rows over again. The Inbox does not go through this — a panel over the
    /// top is showing whether or not a view is under it.
    private func isCurrent(_ tab: PhoneTab) -> Bool {
        store.activeView == nil && store.tab == tab
    }

    private func slot(
        _ title: String, symbol: String, isCurrent: Bool, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            label(title, symbol: symbol, isCurrent: isCurrent)
                .background(isCurrent ? palette.accentSoft : .clear, in: .rect(cornerRadius: 12))
                // The selected chip is drawn at the design's thickness; the slot
                // claims the 44pt minimum across the bar, whichever axis that is.
                .frame(minWidth: isVertical ? 44 : 0, minHeight: isVertical ? 0 : 44)
        }
        .buttonStyle(.bare)
        // Said rather than inferred, because on the rail there is no word to
        // infer it from: a reader meets the same three names in both shapes.
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    /// What is in a slot: a glyph and a word along the foot, the glyph alone up
    /// the rail.
    private func label(_ title: String, symbol: String, isCurrent: Bool) -> some View {
        let tint = isCurrent ? palette.accent : palette.inkText(0.45)
        let glyph = Image(systemName: symbol)
            .symbolSize(isVertical ? 17 : 13, weight: .semibold, relativeTo: .caption)
            .foregroundStyle(tint)

        return Group {
            if isVertical {
                // A square rather than a shrink-wrapped glyph, so three symbols
                // of three different widths make three slots of one width and
                // each one is a 44pt target.
                glyph.frame(width: 44, height: 44)
            } else {
                HStack(spacing: 5) {
                    if showsGlyphBesideWord { glyph }
                    Text(title)
                        .font(SimpleKanbanFont.ui(12, isCurrent ? .extraBold : .bold, relativeTo: .caption))
                        .foregroundStyle(tint)
                        // Three single words in three equal thirds of a phone.
                        // At an accessibility size they do not fit, and a word
                        // has nowhere to break: the pill read "Boar / d",
                        // "Inbo / x", "Sear / ch". Held to one line and allowed
                        // to shrink, they still grow with the reader's text —
                        // just not past the slot they sit in.
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
            }
        }
    }

    /// Whether the word gets a glyph beside it.
    ///
    /// Not at an accessibility size. A 12pt label at AX5 is already scaling to
    /// its floor to fit a third of a phone's width, and a glyph beside it takes
    /// the last of that room and truncates the word — "Sear…" — which is worse
    /// than no glyph, because the word is the label and the glyph is the
    /// company it keeps. The rail is unaffected: there the glyph *is* the label,
    /// and it has a square of its own to grow in.
    private var showsGlyphBesideWord: Bool { !dynamicTypeSize.isAccessibilitySize }

    private var quickCaptureButton: some View {
        Button {
            store.quickCapture()
        } label: {
            Image(systemName: "plus")
                .symbolSize(24, weight: .regular, relativeTo: .title3)
                .foregroundStyle(palette.onAccent)
                .frame(minWidth: 52, minHeight: 52)
        }
        .buttonStyle(.bare)
        .glassEffect(.regular.tint(palette.accent).interactive(), in: .circle)
        .accessibilityLabel("New task")
    }

    /// What the bar sits on.
    ///
    /// Portrait fades, because the list scrolls under the pill and the gradient
    /// is what keeps a card from appearing to pass through it. Landscape has
    /// nothing behind it to fade: `PhoneRootView` insets the board by the rail's
    /// own width rather than letting it run underneath, so the strip is simply
    /// the app's ground with the pill floating on it — and it runs out under the
    /// leading edge, which in landscape is where the sensor housing is.
    @ViewBuilder private var ground: some View {
        if isVertical {
            palette.appBackground.ignoresSafeArea(edges: .leading)
        } else {
            LinearGradient(
                stops: [
                    .init(color: palette.appBackground.opacity(0), location: 0),
                    .init(color: palette.appBackground.opacity(0.96), location: 0.6),
                    .init(color: palette.appBackground.opacity(0.96), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

#endif
