#if os(iOS)

import SwiftUI

/// The tab pill and quick-capture button: Search, the Inbox, and "+ ▤".
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
/// header's magnifier and the tray the Inbox is drawn with everywhere else —
/// and each button keeps its name for VoiceOver, which never sees the
/// difference between the two shapes.
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

    /// Two switches, drawn as two equal slots.
    ///
    /// **The Board slot is gone.** It named the surface you were already
    /// looking at: the board *is* the phone's main surface, so the slot spent a
    /// third of the bar being lit for doing nothing most of the time, and the
    /// two ways off the board — a saved view and search — both have a way back
    /// of their own. The drawer's board rows are that way back, and they select
    /// the tab as well as the board (see `PhoneNavDrawer.show(_:)`), so nothing
    /// is stranded by its going.
    ///
    /// **The Inbox is the toggle**, and it is in the middle of the bar: search
    /// leads, the Inbox sits between it and the `+`, which puts the one thing
    /// you reach for *while* looking at something else under the thumb that is
    /// already on its way to capture. It raises ``PhoneInboxSheet`` over
    /// whatever is on screen instead of replacing it — so unlike search it does
    /// not answer "where am I", and it reads as current whenever the panel is
    /// up, over a saved view included.
    ///
    /// **Search is a switch too**, which it was not. It replaces the list, and
    /// with the Board slot gone there was nothing on this bar to put it away
    /// again: leaving search meant opening the drawer and picking the board you
    /// were already looking at. A lit slot tapped again closes what it opened —
    /// see ``BoardStore/toggleSearch()``, which is also where the query goes,
    /// and which says why this is not the drawer's "a destination row is not a
    /// toggle" over again.
    ///
    /// The order is the same in both shapes, leading to trailing, which is where
    /// a reader coming from the other one looks.
    private var tabPill: some View {
        HStack(spacing: isHeader ? 0 : 4) {
            slot(
                PhoneTab.search.label, symbol: PhoneTab.search.symbol,
                isCurrent: store.isSearching
            ) {
                store.toggleSearch()
            }
            // **The one slot that carries a number.** The Inbox is the only
            // thing on this bar that fills up while you are looking at
            // something else — search is empty until you type — so it is the
            // only one where "how much is in there" is worth the room. The
            // desk's toolbar has said it this way since there was a toolbar:
            // see `BoardToolbar.inboxToggle`.
            slot(
                Board.inboxName, symbol: SavedView.seeded(.inbox).symbol,
                isCurrent: store.isInboxOpen, count: store.inboxCount
            ) {
                store.toggleInbox()
            }
        }
        // None in the header: each slot pads its own glyph out to the 44pt
        // target there, so the run is already exactly as tall as the row and a
        // second inset would push the pill above the title it stands beside.
        .padding(isHeader ? 0 : 4)
        .glassEffect(.regular, in: .rect(cornerRadius: isHeader ? 14 : 16))
    }

    @ViewBuilder
    private func slot(
        _ title: String, symbol: String, isCurrent: Bool, count: Int = 0,
        perform: @escaping () -> Void
    ) -> some View {
        let button = Button(action: perform) {
            label(title, symbol: symbol, isCurrent: isCurrent, count: count)
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
        // infer it from: a reader meets the same names in both shapes.
        .accessibilityLabel(title)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])

        // The count is a **value** rather than part of the name, for
        // `BoardToolbar.inboxToggle`'s reason: folded into the label it reads
        // out as "Inbox 4", a control whose *name* changes every time a card is
        // captured. Attached only where there is one, rather than handed an
        // empty string — the two slots that count nothing have no value to
        // report, and an empty literal is a key in the string catalogue that
        // localizes nothing.
        if count > 0 {
            button.accessibilityValue(Text(verbatim: "\(count)"))
        } else {
            button
        }
    }

    /// What is in a slot: a glyph and a word along the foot, the glyph alone in
    /// the header — and, where there is something to count, the number.
    ///
    /// **Nothing in it is worth a badge saying nought**, which is the desk's
    /// rule for the same control. A nought on a bar that is on screen at all
    /// times is a permanent mark that never means anything.
    private func label(_ title: String, symbol: String, isCurrent: Bool, count: Int) -> some View {
        let tint = isCurrent ? palette.accent : palette.inkText(0.45)
        let glyph = Image(systemName: symbol)
            .symbolSize(isHeader ? 15 : 13, weight: .semibold, relativeTo: .caption)
            .foregroundStyle(tint)

        return Group {
            if isHeader {
                // A square rather than a shrink-wrapped glyph, so symbols of
                // different widths make chips of one width.
                //
                // The number rides *on* the glyph here rather than beside it,
                // for that same reason: a pill in the row would make this chip
                // wider than the one next to it, and their being a matched pair
                // is what tells the eye they are one control.
                glyph
                    .frame(width: 34, height: 34)
                    .overlay(alignment: .topTrailing) {
                        if count > 0 { headerBadge(count) }
                    }
            } else {
                HStack(spacing: 5) {
                    if showsGlyphBesideWord { glyph }
                    Text(title)
                        .font(palette.ui(12, isCurrent ? .extraBold : .bold, relativeTo: .caption))
                        .foregroundStyle(tint)
                        // Single words in equal shares of a phone's width. At an
                        // accessibility size they do not fit, and a word has
                        // nowhere to break: the pill read "Inbo / x", "Sear /
                        // ch". Held to one line and allowed to shrink, they
                        // still grow with the reader's text — just not past the
                        // slot they sit in.
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    // Beside the word, the way the desk's toolbar puts it beside
                    // the tray. It stays at an accessibility size where the
                    // *glyph* is dropped: the glyph is company for the word,
                    // and this is the one part of the slot the word does not
                    // already say.
                    if count > 0 {
                        CountPill(count: count, font: 10.5, horizontalPadding: 5)
                            .layoutPriority(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
            }
        }
    }

    /// The number on a header chip: small, and capped.
    ///
    /// **Capped because this chip cannot grow.** Along the foot a slot is a
    /// third of the screen and a four-figure count simply makes the pill wider;
    /// here the chip is 34pt by construction, and a badge that kept growing
    /// would run out over the chip beside it. Past 99 the exact number is not
    /// what anybody is reading it for — VoiceOver still gets the true count off
    /// the slot's `accessibilityValue`.
    private func headerBadge(_ count: Int) -> some View {
        Text(count > 99
             ? String(localized: "99+", comment: "A count too large to fit the tab bar's badge")
             : "\(count)")
            .font(palette.ui(9, .bold, relativeTo: .caption2))
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(palette.accent, in: .capsule)
            // Out over the glyph's corner rather than inside it, so the digits
            // sit clear of the tray's own outline.
            .offset(x: 6, y: -3)
            // The slot says the count as its value; read here as well it is a
            // loose number in the middle of a row of buttons.
            .accessibilityHidden(true)
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

    /// Capture — 52pt tall when it floats and 44 when it rides in the header,
    /// where it is one control in a row of them rather than the thing the thumb
    /// comes back to. It keeps its accent either way: it is the one button on
    /// this bar that makes something rather than going somewhere.
    ///
    /// It lands in the Inbox (``BoardStore/quickCapture()``), where the `+` on
    /// a column adds to that column — and it now *says* so, with the tray beside
    /// the `+` and a capsule around the pair. See ``CaptureGlyphs``, which is
    /// where that shape and its arithmetic live, since the desk and the iPad
    /// draw the same button.
    ///
    /// **The width comes out of the tab pill, not out of the bar.** Along the
    /// foot the two slots share `maxWidth: .infinity` between them, so the
    /// glyph's extra room is taken from a pair of slots that were each a third
    /// of the screen; in the header the title beside it is the thing with
    /// `maxWidth: .infinity` and a phone on its side has 850pt of it to give.
    /// Neither shape grows a point taller.
    private var quickCaptureButton: some View {
        let glyph: CGFloat = isHeader ? 20 : 24
        return Button {
            store.quickCapture()
        } label: {
            CaptureGlyphs(size: glyph, weight: .regular, relativeTo: .title3)
                .foregroundStyle(palette.onAccent)
                .frame(minWidth: CaptureGlyphs.width(glyph), minHeight: isHeader ? 44 : 52)
        }
        .buttonStyle(.bare)
        .glassEffect(.regular.tint(palette.accent).interactive(), in: .capsule)
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
                    .init(color: palette.ground.opacity(0), location: 0),
                    .init(color: palette.ground.opacity(0.96), location: 0.6),
                    .init(color: palette.ground.opacity(0.96), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

#endif
