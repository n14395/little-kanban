#if os(iOS)

import SwiftUI

/// Search, the Inbox and "+ ▤" — three pills along the foot, and two glyph chips
/// and a pill in the header.
///
/// The design asks for a blurred, tinted bar here (`--glass` + `backdrop-filter`),
/// which is exactly what Liquid Glass provides natively. Every control lives in
/// one `GlassEffectContainer` so their materials blend the way adjacent floating
/// elements should — which is the whole reason the foot's two switches wear a
/// capsule each rather than sharing one rounded rectangle: a container with a
/// single element in it has nothing to blend.
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

    /// The size every mark along the foot is drawn at — the `+` and its tray, and
    /// the magnifier and tray on the two switches beside them.
    ///
    /// One number rather than four because three pills in a row drawing their
    /// marks at two sizes read as a bar and a button rather than three of one
    /// thing. It is also what makes the capture pill 52 tall and 84 wide, and
    /// that 84 is the floor `chip` holds the switches to.
    private static let footCaptureGlyph: CGFloat = 24

    var body: some View {
        GlassEffectContainer(spacing: isHeader ? 8 : 10) {
            if isHeader {
                HStack(spacing: 8) {
                    tabPill
                    quickCaptureButton
                }
            } else {
                footRow
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
    ///
    /// **Along the foot they are two pills rather than two slots of one.** The
    /// capture button beside them is a capsule now (see ``CaptureGlyphs``), and
    /// a rounded rectangle holding two chips next to a capsule is two shape
    /// languages in a bar four inches wide. So each switch wears its own glass
    /// capsule at the capture button's height, and the row is three pills — which
    /// is also what the material is for: `GlassEffectContainer` blends adjacent
    /// elements, and it can only do that for elements there are several of. See
    /// ``footRow`` for how the three are placed.
    ///
    /// **The header keeps the single rounded pill**, which is what this property
    /// is now. There the two are 34pt glyph chips standing between a serif title
    /// and the ⋯, and their being a matched pair inside one shape is what says
    /// they are one control rather than two more discs in a row that already has
    /// two.
    private var tabPill: some View {
        HStack(spacing: 0) {
            searchSlot
            inboxSlot
        }
        // No inset: each slot pads its own glyph out to the 44pt target here, so
        // the run is already exactly as tall as the row and a second one would
        // push the pill above the title it stands beside.
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    /// The three pills along the foot: **the Inbox on the window's centre line,
    /// with Search and capture flush to the edges either side of it.**
    ///
    /// The Inbox is the middle of the sentence this bar makes — search leads, the
    /// `+` ends it — and it is the one slot reached for *while* looking at
    /// something else, so it gets the place a thumb finds without aiming. Search
    /// and capture are pinned to opposite edges inside the bar's own 20pt inset,
    /// which is the same on both sides, so the two ends of the row sit the same
    /// distance in.
    ///
    /// **The gaps either side of the Inbox are not equal, and cannot be.** Three
    /// things cannot all be true at once: the middle on the centre line, both
    /// ends flush to their edges, and the ends different widths. Search carries a
    /// word and a 24pt magnifier and comes to 107; the `+` pill is
    /// ``CaptureGlyphs/width(_:)``, 84. Measured on a 17 Pro that leaves 13
    /// points on one side of the Inbox and 34 on the other. **Which two of the
    /// three to keep is the choice**, and this keeps the edges and the centre
    /// line, because both are things the eye can check against the window and a
    /// gap is not. Giving the `+` pill a floor of Search's width would even them
    /// up, at the cost of a capture button wider on this surface than on the
    /// other two.
    ///
    /// **`CentredMiddleRow` rather than an `HStack`**, and that is not stylistic
    /// — see its own note. Spelled as a stack with the ends in
    /// `maxWidth: .infinity` columns, the three shared the width three ways and
    /// the middle was handed a third of the bar whatever it asked for: with the
    /// glyphs at 13pt every pill's ideal happened to fit inside a third and it
    /// looked correct, and the moment they went to 24 the Inbox was clamped and
    /// drew **"Inb…"**. A row that puts one child on the centre line is not a
    /// stack of equal shares, and writing it as one only worked by coincidence.
    private var footRow: some View {
        CentredMiddleRow(spacing: 10) {
            searchSlot
            inboxSlot
            quickCaptureButton
        }
    }

    private var searchSlot: some View {
        slot(
            PhoneTab.search.label, symbol: PhoneTab.search.symbol,
            isCurrent: store.isSearching
        ) {
            store.toggleSearch()
        }
    }

    /// **The one slot that carries a number.** The Inbox is the only thing on
    /// this bar that fills up while you are looking at something else — search is
    /// empty until you type — so it is the only one where "how much is in there"
    /// is worth the room. The desk's toolbar has said it this way since there was
    /// a toolbar: see `BoardToolbar.inboxToggle`.
    private var inboxSlot: some View {
        slot(
            Board.inboxName, symbol: SavedView.seeded(.inbox).symbol,
            isCurrent: store.isInboxOpen, count: store.inboxCount
        ) {
            store.toggleInbox()
        }
    }

    @ViewBuilder
    private func slot(
        _ title: String, symbol: String, isCurrent: Bool, count: Int = 0,
        perform: @escaping () -> Void
    ) -> some View {
        let button = Button(action: perform) {
            chip(title, symbol: symbol, isCurrent: isCurrent, count: count)
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
            wearingGlass(button.accessibilityValue(Text(verbatim: "\(count)")))
        } else {
            wearingGlass(button)
        }
    }

    /// The material a foot slot wears and a header slot does not.
    ///
    /// Generic over what it is handed rather than erasing it to an `AnyView`,
    /// which is the shape this would otherwise take — the count has to be
    /// attached before the glass and only one of the two slots has one, so the
    /// caller arrives here holding two different types. `MacRootView` says why
    /// erasing is the wrong way out of that.
    ///
    /// **A pill of its own along the foot**, in the same material the run used to
    /// wear as one shape and at the capture button's height, so the three read as
    /// a set. `.interactive()` for that button's reason and no other: the glass
    /// is the control's own surface now rather than a tray under two of them, and
    /// a surface that does not answer the finger on it would be the one thing in
    /// the row that does not. **No tint** — the material is `.regular` here as it
    /// was on the tray, and what says a switch is on is the same `accentSoft`
    /// fill it always was.
    @ViewBuilder private func wearingGlass(_ slot: some View) -> some View {
        if isHeader {
            slot
        } else {
            slot.glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    /// The slot's own shape, inside whatever glass it is wearing: a 34pt chip in
    /// the header, and along the foot the whole of a pill.
    ///
    /// **The lit fill reaches the pill's edge along the foot**, where it used to
    /// be an 11pt chip floating inside the run's rounded rectangle with 4pt of
    /// glass showing round it. That inset made sense while the glass was a tray
    /// holding two things and the fill had to say *which of the two*; now the
    /// glass is the switch, and a rounded rectangle drawn a few points inside a
    /// capsule is a second shape saying nothing.
    @ViewBuilder
    private func chip(_ title: String, symbol: String, isCurrent: Bool, count: Int) -> some View {
        let content = label(title, symbol: symbol, isCurrent: isCurrent, count: count)
        if isHeader {
            content
                .background(isCurrent ? palette.accentSoft : .clear, in: .rect(cornerRadius: 11))
                // **The header's slot draws smaller than it claims.** The chip
                // is 34pt — the size of the two discs it sits between, so the
                // row reads as one row — and the padding around it carries the
                // target out to the 44 a finger needs. Padding rather than a
                // `frame`, because the glass pill wraps whatever this returns:
                // a 44pt frame would put the material 5pt out from the chip on
                // every side, which is a pill drawn round its own gaps.
                .padding(5)
                .contentShape(.rect)
        } else {
            content
                // **A floor rather than a share of the bar.** Each of these used
                // to take `maxWidth: .infinity` and halve whatever the capture
                // button left — two 123pt pills that were mostly air, and a row
                // with no centre for the Inbox to sit on. They size to their own
                // word and mark now, and this is only the floor they cannot go
                // below: the `+` pill's width, which is the narrowest anything on
                // this bar is allowed to be.
                //
                // It is what keeps the row adaptable, which is the one thing the
                // old `maxWidth: .infinity` was doing for it: at an accessibility
                // size the pills squeeze back down to here while the words scale
                // inside them, rather than pushing the row off the screen.
                //
                // 52 is the capture button's height, which the run used to reach
                // by wearing 4pt of padding around a 44pt slot. The bar is the
                // same height it was, and `Toast.Metrics.phone` still clears it
                // by the same margin.
                .frame(minWidth: CaptureGlyphs.width(Self.footCaptureGlyph), minHeight: 52)
                .background(isCurrent ? palette.accentSoft : .clear, in: .capsule)
                .contentShape(.capsule)
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
        // **Along the foot it is the capture pill's glyph, at its size and on its
        // text style.** Three pills in a row drawing their marks at 13 and 24
        // read as a bar and a button rather than three of one thing; the size is
        // named once, in ``footCaptureGlyph``, so they cannot drift apart. The
        // text style goes with it — a glyph growing on `.caption` beside one
        // growing on `.title3` is two glyphs that match at the system size and
        // nowhere else.
        //
        // The weight does *not* follow it. These are ink on glass and the capture
        // pill's are white on the accent, which draws heavier at the same weight;
        // `.semibold` here against its `.regular` is what makes the two look
        // like one stroke.
        let glyph = Image(systemName: symbol)
            .symbolSize(isHeader ? 15 : Self.footCaptureGlyph, weight: .semibold,
                        relativeTo: isHeader ? .caption : .title3)
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
                        // 13 rather than 12, which is the glyph's own size: the
                        // word is the label here and the glyph is the company it
                        // keeps, and a word set smaller than the mark beside it
                        // reads as the caption to it. It is also a pill's worth
                        // of room the slot no longer spends on air — see `chip`.
                        .font(palette.ui(13, isCurrent ? .extraBold : .bold, relativeTo: .caption))
                        .foregroundStyle(tint)
                        // A single word in a pill that fits it. At an
                        // accessibility size it does not, and a word has
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
                // The pill's own inset, where this used to be `maxWidth:
                // .infinity` and the pill was whatever half the bar came to.
                //
                // 15 rather than the 12 it landed on when the glyph was 13pt: a
                // wider pill, and the room a 24pt mark needs before the capsule's
                // own curve starts closing on it.
                //
                // **The ceiling on it is Search fitting without scaling its
                // word.** Centring the Inbox leaves each end `half − middle/2 −
                // spacing`, and both the middle and the end grow with this
                // number — so every point added here costs the ends one and a
                // half. Measured on a 17 Pro's 362pt bar: the words and marks
                // come to 76.7 and 94, which puts the line at 15.8. Past it
                // Search is handed less than it asked for and
                // `minimumScaleFactor` quietly draws its word a size below the
                // Inbox's, which is the sort of difference nobody sees and
                // everybody notices.
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
            }
        }
    }

    /// The number on a header chip: small, and capped.
    ///
    /// **Capped because this chip cannot grow.** Along the foot a slot is as wide
    /// as its own content and a four-figure count simply makes the pill wider;
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
    /// Not at an accessibility size. A 13pt label at AX5 is already scaling to
    /// its floor to fit the pill's own width, and a glyph beside it takes
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
    /// **It is what the rest of the bar is measured against.** Along the foot
    /// ``footRow`` pins it to the trailing edge and Search to the leading one;
    /// ``footCaptureGlyph`` is the size every mark on this bar is drawn at,
    /// switches included; and `chip` floors both switches at
    /// ``CaptureGlyphs/width(_:)`` of it, which is the narrowest a pill here is
    /// allowed to be. In the header the title beside it is the thing with
    /// `maxWidth: .infinity`, and a phone on its side has 850pt of it to give.
    /// Neither shape grows a point taller.
    private var quickCaptureButton: some View {
        let glyph: CGFloat = isHeader ? 20 : Self.footCaptureGlyph
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

/// Three controls in a row: the middle one on the container's centre line, the
/// other two flush to its leading and trailing edges.
///
/// **An `HStack` cannot say this.** The tempting spelling puts the ends in
/// `maxWidth: .infinity` columns and lets them split what the middle leaves — but
/// a stack hands its width out by flexibility, and a middle child that can shrink
/// at all is offered a *share* of the row rather than what it asked for. With
/// three children that share is a third, and a pill whose word and count come to
/// more than a third of the bar is a pill that quietly draws "Inb…". The centre
/// line is not a share of anything, so it is arithmetic and belongs here.
///
/// **The middle is measured first and keeps the centre**, and each end is then
/// given exactly the room between its own edge and the middle's gap — equal by
/// construction, which is what makes the two ends mirror each other however
/// differently wide they are. A child is proposed the smaller of its ideal and
/// that room, so at a text size the bar cannot hold, the words scale inside their
/// pills the way they did when the ends were flexible columns; nothing here
/// overlaps or is clipped.
///
/// Written for three and honest about it: anything else is laid out as a plain
/// row rather than silently doing something else with the centre line.
private struct CentredMiddleRow: Layout {
    /// The least room left either side of the middle. A minimum rather than a
    /// fixed gap: the ends are flush to the container, so what is between them
    /// and the middle is whatever the arithmetic leaves, and this is the floor it
    /// cannot come below.
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = ideals.map(\.width).reduce(0, +)
            + spacing * CGFloat(max(0, subviews.count - 1))
        // **A width this fills, but only a real one.** The row is asked for its
        // size at the extremes as well as at the real one — `.infinity` for "how
        // large could you be", and `nil` for "how large would you like to be" —
        // and handing either straight back is a frame of that width. Measured:
        // it logged *Invalid frame dimension (negative or non-finite)* and took
        // the window's hit-testing with it, so a sheet over this bar could be
        // typed into and then not dragged away again.
        let room = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? natural
        return CGSize(width: room, height: ideals.map(\.height).max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        guard bounds.width.isFinite, bounds.height.isFinite else { return }
        guard subviews.count == 3 else { return placeAsARow(in: bounds, subviews: subviews) }

        // The middle gives ground only when the bar cannot hold it and a gap
        // either side, and never moves off the centre line.
        let middle = min(subviews[1].sizeThatFits(.unspecified).width,
                         max(0, bounds.width - 2 * spacing))
        let room = max(0, bounds.width / 2 - middle / 2 - spacing)

        place(subviews[0], at: bounds.minX, anchor: .leading, room: room, in: bounds)
        subviews[1].place(
            at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
            proposal: ProposedViewSize(width: middle, height: nil)
        )
        place(subviews[2], at: bounds.maxX, anchor: .trailing, room: room, in: bounds)
    }

    private func place(
        _ view: LayoutSubview, at x: CGFloat, anchor: UnitPoint, room: CGFloat, in bounds: CGRect
    ) {
        let width = min(view.sizeThatFits(.unspecified).width, room)
        view.place(at: CGPoint(x: x, y: bounds.midY), anchor: anchor,
                   proposal: ProposedViewSize(width: width, height: nil))
    }

    /// Not the shape this layout is for, laid out as the row it looks like.
    private func placeAsARow(in bounds: CGRect, subviews: Subviews) {
        var x = bounds.minX
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            view.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                       proposal: ProposedViewSize(width: size.width, height: nil))
            x += size.width + spacing
        }
    }
}

#endif
