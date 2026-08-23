#if os(iOS)

import SwiftUI

/// The tab pill and quick-capture button: Board, the Inbox, Search, and "+".
///
/// The design asks for a blurred, tinted bar here (`--glass` + `backdrop-filter`),
/// which is exactly what Liquid Glass provides natively. Both controls live in a
/// single `GlassEffectContainer` so their materials blend the way two adjacent
/// floating elements should.
///
/// **It floats along the foot in portrait and rides in the header on its side.**
/// A phone turned sideways has around 400pt of height, and along the foot this
/// bar was spending 130 of them — the pill, the button, and the room to scroll
/// the last card clear of both — which is a third of the axis that shape has
/// least of. It stood on end up the leading edge for a while, which bought the
/// height back and charged 76pt of width for it; now it sits in the one row that
/// shape already pays for, beside the board's name, and costs neither.
///
/// **The words go with it.** Each slot is a glyph and a word along the foot and
/// the glyph alone in the header, which is what a row already holding a serif
/// title and two discs can actually take. The glyphs are the app's own — the
/// board's, the tray the Inbox is drawn with everywhere else, and the header's
/// magnifier — and each button keeps its name for VoiceOver, which never sees
/// the difference between the two shapes.
struct PhoneTabBar: View {
    /// Where the bar is drawn, which is the one value everything that differs
    /// between the two shapes reads off: what is in a slot, how big it is drawn
    /// against what is beside it, and whether there is any ground under it.
    ///
    /// Both are horizontal runs. The rail — a `VStackLayout` up the leading
    /// edge — is gone, and its arithmetic with it: three glyphs on end were
    /// 76pt of an 850pt screen that the board never got back, and the header row
    /// beside them was already there, already 44pt tall, and already had the
    /// room between the title and the ⋯.
    enum Placement {
        /// Floating over the foot of a portrait screen.
        case foot
        /// In the header's title row, on a phone held sideways.
        case header
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var placement: Placement = .foot

    private var isHeader: Bool { placement == .header }

    var body: some View {
        GlassEffectContainer(spacing: isHeader ? 8 : 10) {
            HStack(spacing: isHeader ? 8 : 10) {
                tabPill
                quickCaptureButton
            }
        }
        .padding(.horizontal, isHeader ? 0 : 20)
        .padding(.vertical, isHeader ? 0 : 12)
        // Level with the header's own two discs, which sit 3pt up from the foot
        // of the row — see `PhoneHeader.hamburger`. The bar is 10pt taller than
        // they are drawn and shares their bottom edge rather than their centre,
        // so the row it joins does not grow by a point.
        .padding(.bottom, isHeader ? 3 : 0)
        .background(alignment: .bottom) { ground }
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
    /// The order is the same in both shapes, leading to trailing, which is where
    /// a reader coming from the other one looks.
    private var tabPill: some View {
        HStack(spacing: isHeader ? 0 : 4) {
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
        // None in the header: each slot pads its own glyph out to the 44pt
        // target there, so the run is already exactly as tall as the row and a
        // second inset would push the pill above the title it stands beside.
        .padding(isHeader ? 0 : 4)
        .glassEffect(.regular, in: .rect(cornerRadius: isHeader ? 14 : 16))
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
                .background(isCurrent ? palette.accentSoft : .clear, in: .rect(cornerRadius: 11))
                // **The header's slot draws smaller than it claims.** The chip
                // is 34pt — the size of the two discs it sits between, so the
                // row reads as one row — and the padding around it carries the
                // target out to the 44 a finger needs. Padding rather than a
                // `frame`, because the glass pill wraps whatever this returns:
                // a 44pt frame would put the material 5pt out from the chip on
                // every side, which is a pill drawn round its own gaps.
                .padding(isHeader ? 5 : 0)
                .contentShape(.rect)
                // Along the foot the slot is a third of the bar, and the height
                // is what has to reach 44.
                .frame(minHeight: isHeader ? 0 : 44)
        }
        .buttonStyle(.bare)
        // Said rather than inferred, because in the header there is no word to
        // infer it from: a reader meets the same three names in both shapes.
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }

    /// What is in a slot: a glyph and a word along the foot, the glyph alone in
    /// the header.
    private func label(_ title: String, symbol: String, isCurrent: Bool) -> some View {
        let tint = isCurrent ? palette.accent : palette.inkText(0.45)
        let glyph = Image(systemName: symbol)
            .symbolSize(isHeader ? 15 : 13, weight: .semibold, relativeTo: .caption)
            .foregroundStyle(tint)

        return Group {
            if isHeader {
                // A square rather than a shrink-wrapped glyph, so three symbols
                // of three different widths make three chips of one width.
                glyph.frame(width: 34, height: 34)
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
    /// company it keeps. The header is unaffected: there the glyph *is* the
    /// label, and it has a square of its own to sit in.
    private var showsGlyphBesideWord: Bool { !dynamicTypeSize.isAccessibilitySize }

    /// The "+" — 52pt when it floats and 44 when it rides in the header, where
    /// it is one control in a row of them rather than the thing the thumb comes
    /// back to. It keeps its accent either way: it is the one button on this bar
    /// that makes something rather than going somewhere.
    private var quickCaptureButton: some View {
        Button {
            store.quickCapture()
        } label: {
            Image(systemName: "plus")
                .symbolSize(isHeader ? 20 : 24, weight: .regular, relativeTo: .title3)
                .foregroundStyle(palette.onAccent)
                .frame(minWidth: isHeader ? 44 : 52, minHeight: isHeader ? 44 : 52)
        }
        .buttonStyle(.bare)
        .glassEffect(.regular.tint(palette.accent).interactive(), in: .circle)
        .accessibilityLabel("New task")
    }

    /// What the bar sits on.
    ///
    /// Only the floating one has any. The list scrolls under the pill there and
    /// the gradient is what keeps a card from appearing to pass through it; in
    /// the header there is nothing behind the bar but the header, which is the
    /// app's own ground and already opaque.
    @ViewBuilder private var ground: some View {
        if !isHeader {
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
