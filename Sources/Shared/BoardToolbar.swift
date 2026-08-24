import SwiftUI

/// The board header: the source list's toggle, the Inbox, the board's name,
/// search, capture on the iPad, and the inspector's toggle.
///
/// **Capture is the iPad's alone**, and it is a circle with a `+` in it rather
/// than the labelled button this row carried until 8.2. Two reasons it is only
/// here. The desk has one already, at the foot of the source list — see
/// ``BoardSidebar/captureButton`` — and ⌘N on the File menu besides; the iPad
/// has no menu bar, so without this the only ways to make a card there are a
/// column heading's `+` and the Inbox panel's, both of which decide where it
/// goes before you have decided what it is. And the label was the widest thing
/// in a row whose only compressible piece is the board's name: as a circle it
/// claims the same 44pt square as every other control beside it, which is 73
/// points back to the name and a fold line 73 points lower — see
/// ``Metrics/searchFits(barWidth:leadingInset:sidebarToggle:inboxToggle:factor:)``.
struct BoardToolbar: View {
    /// The bar at a pointer and the bar under a finger. Everything in it is
    /// 34pt tall in the design, which is under the touch minimum — see **Touch
    /// targets** in the README.
    struct Metrics {
        var height: CGFloat
        var spacing: CGFloat
        var horizontalPadding: CGFloat
        var titleSize: CGFloat
        var searchWidth: CGFloat
        var searchFont: CGFloat
        /// The square, or the height, every control in the bar claims.
        var control: CGFloat
        var controlRadius: CGFloat
        var glyph: CGFloat
        /// What the two text fields claim — see ``FieldHitArea``.
        var fieldHit: CGFloat
        /// The room the board's name keeps before the search field folds. A
        /// floor rather than a width: the name truncates long before this, and
        /// this is the point past which truncating it further is worth less
        /// than the field it is truncating for.
        ///
        /// Measured against the built app rather than picked: a squeezed 13"
        /// iPad drew "Northwind iOS 3.0" as "Northwind i…" in 131pt, so 160 is
        /// around fourteen characters at the pad's 26pt serif — enough to tell
        /// one board from another, which is the whole job of a name in a bar you
        /// are already looking at. Folding buys it the field's 220 back, less
        /// the 44 the button keeps.
        var titleFloor: CGFloat
        /// The one control whose width is its own content rather than a number
        /// in this table: a tray, a count and their padding. Measured off the
        /// built app — see
        /// ``searchFits(barWidth:leadingInset:sidebarToggle:inboxToggle:factor:)``.
        var inboxWidth: CGFloat
        /// The capture button's diameter, and `nil` where the bar carries none.
        ///
        /// A size that is allowed to be absent, the way
        /// ``BoardColumnView/ColumnEditorMetrics/arrowEdge`` is — the presets
        /// differ, rather than the body branching on `#if os()` (C1). The desk's
        /// is `nil` because its capture button is at the foot of the source
        /// list, where a window's furniture goes.
        var capture: CGFloat?
        /// Whether the field folds into a button when the row runs out of
        /// width.
        ///
        /// **The desk does not.** This bar *is* the window's title bar and the
        /// traffic lights are pinned to the middle of the row it lays out at —
        /// `MacRootView` measures the bar and moves them there — so a second
        /// row under it would take the lights down with it. The window has a
        /// floor of its own instead (`MacRootView.floor`), which is what keeps
        /// the bar's contents in it; the iPad's detail column has no such floor,
        /// because a split view can hand it whatever is left after the source
        /// list and the Inbox panel have taken theirs.
        var foldsSearch: Bool
        /// What the results panel under the field is drawn at. A field of this
        /// table rather than a `#if os()` in the body, for `capture`'s reason:
        /// the two bars differ by their presets and by nothing else.
        var results: SearchResultsPanel.Metrics

        // The desk's height is the row the window's traffic lights sit on —
        // there is no title bar, so this bar *is* the chrome rather than a
        // strip beneath it, and 50 is the tallest row whose centre the lights
        // can still be moved to: AppKit's own title bar is 32pt, a light is
        // 14pt, and one hanging out of that bar draws where it is asked to and
        // then refuses the click. See `windowButtons(centredAt:)`.
        static let desk = Metrics(
            height: 50, spacing: 14, horizontalPadding: 20, titleSize: 24, searchWidth: 216,
            searchFont: 13, control: 34, controlRadius: 10, glyph: 12,
            fieldHit: 0, titleFloor: 140, inboxWidth: 56, capture: nil, foldsSearch: false,
            results: .desk
        )
        static let pad = Metrics(
            height: 72, spacing: 14, horizontalPadding: 18, titleSize: 26, searchWidth: 220,
            searchFont: 15, control: 44, controlRadius: 12, glyph: 15,
            fieldHit: 44, titleFloor: 160, inboxWidth: 68, capture: 44, foldsSearch: true,
            results: .pad
        )

        /// Whether the bar can hold the search field at this width.
        ///
        /// Everything in the row but the board's name is a fixed size, so what
        /// is left for the name is the width less all of those — and the name
        /// needs a floor of its own, or the field keeps its 220pt while the name
        /// beside it is an ellipsis. Below the floor the field folds into a
        /// button and the name gets those 220 points back.
        ///
        /// **Estimated rather than measured, and it has to be.** Measuring the
        /// squeeze means measuring the row *with* the field in it, and taking
        /// the field out on the strength of that measurement gives the name
        /// room, which puts the field back, which squeezes the name: the
        /// decision would oscillate at exactly the width it matters at. So the
        /// one control that sizes to its content — the Inbox toggle, whose badge
        /// is a number that grows — is named in the table above at what the
        /// built app laid it out at.
        ///
        /// `Tests/ToolbarFoldTests` pins the arithmetic, including that the row
        /// folds before it overflows rather than after.
        func searchFits(
            barWidth: CGFloat, leadingInset: CGFloat,
            sidebarToggle: Bool, inboxToggle: Bool, factor: CGFloat
        ) -> Bool {
            // `ChromeScale`'s own arithmetic, which cannot be borrowed here: it
            // is a `DynamicProperty` and reads the environment, and this is a
            // function about numbers.
            func grown(_ size: CGFloat, cap: CGFloat = 1.6) -> CGFloat {
                size * min(max(factor, 1), cap)
            }

            // The name, the spacer, the field and the inspector toggle are in
            // every version of this row.
            var claimed = horizontalPadding * 2 + leadingInset
                + grown(titleFloor, cap: 1.35)
                + grown(searchWidth, cap: 1.35)
                + grown(control)
            var pieces = 4
            if sidebarToggle { claimed += grown(control); pieces += 1 }
            if inboxToggle { claimed += grown(inboxWidth); pieces += 1 }
            if let capture { claimed += grown(capture); pieces += 1 }
            // An `HStack`'s spacing goes between every pair, the spacer
            // included — so the gaps are one fewer than the pieces, not one
            // fewer than the controls.
            claimed += spacing * CGFloat(pieces - 1)
            return claimed <= barWidth
        }
    }

    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    /// The bar is a box around type that grows, so its own sizes grow with it —
    /// see ``ChromeScale``. Every height below is a *minimum*: past the cap the
    /// bar keeps growing on its content rather than clipping it.
    private var chrome = ChromeScale()

    /// Which board's title is a field. It is a `Text` the rest of the time so
    /// that the pointer over an empty stretch of toolbar is not sitting in a
    /// text field, and so the name truncates rather than filling the bar.
    ///
    /// The board's identity rather than a flag, the way `BoardSidebar` holds
    /// which row it is editing: Escape clears this before the field goes, which
    /// is the only thing that tells the parting focus change "the user
    /// cancelled" from "the user clicked away".
    @State private var renamingBoardID: Board.ID?
    @State private var draft = ""
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isSearchFocused: Bool
    /// Lit while a card is over the Inbox button. Local, unlike the panel's:
    /// this one has no cards of its own to take the hover from it.
    @State private var isInboxDropTarget = false
    /// Whether the folded field has been asked for. Only ever read while the
    /// bar is folded — see ``showsSearchRow``, which is the flag *and* the
    /// query, because a query with no field on screen is a search the reader
    /// has no way back to.
    @State private var isSearchOpen = false
    /// What the row actually laid out at. The iPad's detail column is whatever
    /// the split view has left after the source list and the Inbox panel, so
    /// this is measured rather than reasoned about from the screen's width —
    /// the same thing `PadRootView` does with the room beside the board.
    @State private var barWidth: CGFloat = 0
    /// Whether the results panel is under the field. Not simply "the field has
    /// focus": clicking a result moves focus out of the field on macOS, and a
    /// panel that vanished on that would be a panel whose rows cannot be
    /// clicked. It is opened by asking for the field and closed by the four
    /// things that end a search — Escape, a result, the × , and putting the
    /// folded row away.
    @State private var isShowingResults = false
    /// Which result Return would take. Held here rather than in the panel
    /// because the keys that move it are pressed in the *field*: the panel
    /// never takes focus, so it has no key events of its own.
    @State private var highlighted: TaskItem.ID?
    /// Where the field ended up in the bar, so the panel can hang under it.
    /// Measured rather than reasoned about: the field is at the trailing end of
    /// the bar at full width and fills a row of its own when the bar has folded.
    @State private var fieldFrame: CGRect = .zero

    var metrics: Metrics = .desk
    /// Room for the window controls when the sidebar is not there to hold it.
    var leadingInset: CGFloat = 0
    /// Shows and hides the source list. The menu bar owns that on the desk and
    /// passes `nil`; a split view has no chrome of ours to put it in, so on
    /// iPad the bar carries the button itself.
    var toggleSidebar: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            bar
            // The field the button folded into, in a row of its own beneath the
            // bar. **A row rather than an overlay**, which is the tempting
            // spelling and the wrong one: an overlay hangs over the top of the
            // board, and the top of the board is where the cards a live search
            // has just matched are. The bar has grown a row here for as long as
            // the field is up; the board starts lower and every card in it stays
            // reachable. It is also the shape that lifts with the keyboard
            // rather than being covered by it.
            if showsSearchRow {
                searchField(fills: true)
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.bottom, metrics.spacing)
            }
        }
        .hairline(.bottom, color: palette.ink(0.07))
        .coordinateSpace(.named(Self.barSpace))
        // Over the board rather than in it, and drawn by the bar because the
        // bar owns the field: the panel is laid out against `fieldFrame`, which
        // only this view has.
        //
        // **The z-order is the caller's**, and has to be: the board and the
        // detail panel are the bar's *siblings*, one stack up, and a `zIndex`
        // written here orders this view against its own contents rather than
        // against them. Measured — with it here, the panel drew underneath the
        // inspector and was invisible from the moment a card was selected. Both
        // roots put `.zIndex(1)` on the bar.
        .overlay(alignment: .topLeading) { resultsPanel }
        .motionAnimation(.easeOut(duration: 0.16), value: showsSearchRow)
        // Edit ▸ Find, and the iPad's ⌘F from a hardware keyboard. The menu bar
        // is outside this view's tree and cannot reach a `FocusState`, so the
        // ask travels as a counter on the store and lands here. A counter rather
        // than a flag: with the field already focused a flag would already be
        // true, and the second ⌘F would be no change at all.
        .onChange(of: store.searchFocusToken) { _, _ in askForTheField() }
        // A window pulled wide again puts the field back in the bar, and the
        // row's flag has to go with it — left standing, the next fold would open
        // a row nobody asked for and take the keyboard with it.
        .onChange(of: foldsSearch) { _, folded in
            if !folded { isSearchOpen = false }
        }
    }

    /// The bar itself: one row, whatever the width.
    private var bar: some View {
        HStack(spacing: metrics.spacing) {
            sidebarToggle
            inboxToggle
            title

            Spacer(minLength: 0)

            if foldsSearch {
                searchToggle
            } else {
                searchField(fills: false)
            }
            captureButton
            inspectorToggle
        }
        .padding(.leading, metrics.horizontalPadding + leadingInset)
        .padding(.trailing, metrics.horizontalPadding)
        .frame(minHeight: chrome(metrics.height))
        // Measured on the bar rather than on the stack around it, so the row
        // that drops out of it cannot be part of what decides whether it drops:
        // both are the column's width, and only one of them is there already.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
    }

    // MARK: Folding

    /// Whether the field has folded into a button.
    ///
    /// Zero before the first layout pass, which must not read as *no room*: the
    /// bar would come up folded and unfold a frame later, which is a flinch on
    /// every launch.
    private var foldsSearch: Bool {
        guard metrics.foldsSearch, barWidth > 0 else { return false }
        return !metrics.searchFits(
            barWidth: barWidth,
            leadingInset: leadingInset,
            sidebarToggle: toggleSidebar != nil,
            inboxToggle: store.showsInboxToggle,
            factor: chrome.factor
        )
    }

    /// Whether the row under the bar is showing.
    ///
    /// The flag *or* a live query. The second half is what a window narrowed
    /// around a search does: the field folds, and if the query folded away with
    /// it the reader would be left with a search still running and nowhere to
    /// edit or clear it. So a query keeps its field.
    private var showsSearchRow: Bool {
        foldsSearch && (isSearchOpen || !store.query.isEmpty)
    }

    private func toggleSearchRow() {
        if showsSearchRow { closeSearchRow() } else { isSearchOpen = true }
    }

    // MARK: The results

    /// Every task in the app, best match first — see ``SearchResultsPanel``.
    /// Read once per render and handed to the panel and to the keys alike, so
    /// what Return takes is what the reader is looking at.
    private var results: [TaskItem] { store.searchResults }

    @ViewBuilder
    private var resultsPanel: some View {
        if isShowingResults, fieldFrame != .zero {
            let width = SearchResultsPanel.width(
                under: fieldFrame.width, in: barWidth, metrics: metrics.results
            )
            SearchResultsPanel(
                results: results, highlighted: $highlighted, metrics: metrics.results
            ) { choose($0) }
            .frame(width: width)
            // **The overlay proposes the bar's own height**, which is 50pt, and
            // a scroll view offered 50pt takes it: the panel drew one row and
            // scrolled the rest, with its ground and its shadow drawn around
            // that one row. `fixedSize` is what makes it ask for the height it
            // wants instead; the cap inside it is `Metrics.maxHeight`.
            .fixedSize(horizontal: false, vertical: true)
            .offset(
                x: SearchResultsPanel.offset(under: fieldFrame, width: width, in: barWidth),
                y: fieldFrame.maxY + 6
            )
            .transition(.opacity)
        }
    }

    /// A result the user picked: go to the card, and the search is over.
    /// ``BoardStore/reveal(_:)`` is the whole errand — the card's board, the
    /// card selected, its detail open — and is the same call a
    /// `simplekanban://` link makes.
    private func choose(_ id: TaskItem.ID) {
        // The field first, and then the card. `reveal` clears the query, which
        // is a change this view watches — and a watcher that saw the field
        // still focused would take the clear for a keystroke and re-open the
        // panel over the card it had just gone to.
        isSearchFocused = false
        closeResults()
        if foldsSearch { isSearchOpen = false }
        store.reveal(id)
    }

    private func closeResults() {
        isShowingResults = false
        highlighted = nil
    }

    /// ↑/↓ in the field, which is where they are pressed. A list with no
    /// highlight starts at the top on the way down and at the bottom on the way
    /// up, so one press of either key always lands somewhere.
    private func moveHighlight(by delta: Int) {
        let ids = results.map(\.id)
        guard !ids.isEmpty else { return highlighted = nil }
        guard let current = highlighted, let index = ids.firstIndex(of: current) else {
            highlighted = delta > 0 ? ids.first : ids.last
            return
        }
        let next = index + delta
        guard ids.indices.contains(next) else { return }
        highlighted = ids[next]
    }

    /// Putting the row away is a cancel, query and all — the other half of the
    /// bargain ``showsSearchRow`` strikes. Leaving the query behind would take
    /// away the field it is typed in and the panel it answers into at once.
    private func closeSearchRow() {
        isSearchOpen = false
        isSearchFocused = false
        closeResults()
        store.clearQuery()
    }

    /// ⌘F, wherever the field is at the time. Folded, the row has to exist
    /// before anything in it can hold the keyboard: opening it is what this
    /// does, and the field's own `focusWhenReady` takes the keyboard as it
    /// arrives. The assignment is for the field that is already on screen.
    private func askForTheField() {
        if foldsSearch { isSearchOpen = true }
        isSearchFocused = true
    }

    @ViewBuilder
    private var sidebarToggle: some View {
        if let toggleSidebar {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.leading")
                    .symbolSize(metrics.glyph + 1, weight: .medium, relativeTo: .subheadline)
                    .foregroundStyle(palette.inkText(0.45))
                    .frame(minWidth: chrome(metrics.control), minHeight: chrome(metrics.control))
                    .contentShape(.rect)
            }
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.06), radius: metrics.controlRadius)
            .accessibilityLabel("Toggle sidebar")
        }
    }

    /// The Inbox, in front of the board's name because that is the order the
    /// two are in on screen: the panel opens to the left of everything the bar
    /// says. A toggle, like the inspector button at the other end of the bar,
    /// and marked the same way when it is out.
    ///
    /// **Only beside a board.** The panel stands beside the board and a saved
    /// view has taken the board's place, so on Today the button would toggle
    /// something the surface cannot show. It moved here from the top of the
    /// source list, where it was a destination back when the Inbox was a page.
    ///
    /// It takes drops for the reason the source-list row used to: with the
    /// panel shut this is the only way back by pointer for a card filed by
    /// mistake — the Inbox is not a column, so there is no column to drop it on.
    @ViewBuilder
    private var inboxToggle: some View {
        if store.showsInboxToggle {
            Button { store.toggleInbox() } label: {
                HStack(spacing: 6) {
                    // Open, the button's job is to shut the panel, and the panel
                    // is immediately to its left — so it points at what it will
                    // close rather than naming what is already on screen. The
                    // count goes with the tray: it is there to say what is in
                    // the Inbox while the Inbox cannot be seen.
                    if store.isInboxOpen {
                        Image(systemName: "chevron.left")
                            .symbolSize(metrics.glyph + 1, weight: .semibold, relativeTo: .subheadline)
                            .foregroundStyle(palette.ink)
                    } else {
                        Image(systemName: "tray")
                            .symbolSize(metrics.glyph + 1, weight: .medium, relativeTo: .subheadline)
                            .foregroundStyle(palette.inkText(0.45))
                        // Nothing in it is worth a badge saying nought.
                        if store.inboxCount > 0 {
                            CountPill(count: store.inboxCount)
                        }
                    }
                }
                .padding(.horizontal, 9)
                // Square at the minimum: an icon and no badge is 34pt of
                // content on the iPad, and a finger needs 44 in both directions
                // rather than only downwards.
                .frame(minWidth: chrome(metrics.control), minHeight: chrome(metrics.control))
                .background(inboxBackground, in: .rect(cornerRadius: metrics.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.controlRadius)
                        .strokeBorder(isInboxDropTarget ? palette.accent : palette.ink(0.12),
                                      lineWidth: isInboxDropTarget ? 2 : 1)
                }
                .contentShape(.rect(cornerRadius: metrics.controlRadius))
            }
            .buttonStyle(.bare)
            // Not read by anyone — an identifier is not a label — but the one
            // way a UI test can tell this button from the source list's Inbox
            // row and the panel's own header, all three of which are called
            // "Inbox" because all three are the Inbox.
            .accessibilityIdentifier(Self.inboxToggleID)
            .help(store.isInboxOpen ? "Hide the Inbox" : "Show the Inbox")
            // The count is what the button is worth, not part of what it is
            // called: gathered into the name it reads out as "Inbox 4", a
            // control whose name changes every time a card is filed.
            .accessibilityLabel(Board.inboxName)
            // Still the count, even while the chevron has taken the badge's
            // place: what a reader needs from this control is how much is in
            // there, and the panel being open is the `.isSelected` below.
            .accessibilityValue(Text(verbatim: "\(store.inboxCount)"))
            .accessibilityAddTraits(store.isInboxOpen ? [.isSelected] : [])
            .dropDestination(for: TaskTransfer.self) { items, _ in
                isInboxDropTarget = false
                guard store.allowsCardDrag, let dropped = items.first, store[dropped.id] != nil
                else { return false }
                store.unfile(dropped.id)
                return true
            } isTargeted: { targeted in
                isInboxDropTarget = targeted && store.allowsCardDrag
            }
        }
    }

    /// Shared with `UITests/InboxDragTests` through the source rather than by
    /// both spelling the same string.
    static let inboxToggleID = "InboxToggle"

    private var inboxBackground: Color {
        if isInboxDropTarget { return palette.accent.opacity(0.12) }
        return store.isInboxOpen ? palette.ink(0.07) : .clear
    }

    /// The active board's name, renamed where it is written. `nil` is a state
    /// the user can reach by deleting their last board, and it says so rather
    /// than leaving the bar looking unfinished.
    @ViewBuilder
    private var title: some View {
        if let board = store.activeBoard {
            Group {
                if renamingBoardID == board.id {
                    TextField("Board name", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .onSubmit { isTitleFocused = false }
                        .onKeyPress(.escape) {
                            renamingBoardID = nil
                            return .handled
                        }
                        .fieldHitArea(minHeight: metrics.fieldHit) { isTitleFocused = true }
                        .focusWhenReady($isTitleFocused)
                        .accessibilityLabel("Board name")
                        // Only while this is still the board being renamed.
                        // Escape and a board switch both clear it first, so a
                        // cancelled draft cannot arrive here as a rename.
                        .onChange(of: isTitleFocused) { _, focused in
                            guard !focused, renamingBoardID == board.id else { return }
                            store.renameBoard(board.id, to: draft)
                            renamingBoardID = nil
                        }
                } else {
                    Button {
                        draft = board.name
                        renamingBoardID = board.id
                    } label: {
                        Text(board.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            // The bar's own control height, so the name is a
                            // target the size of everything beside it rather
                            // than the height of its own glyphs. The pointer
                            // preset is what the text already measured.
                            .frame(minHeight: chrome(metrics.control))
                    }
                    .buttonStyle(.bare)
                    .help("Rename this board")
                    .accessibilityLabel("Board name, \(board.name)")
                    .accessibilityHint("Renames this board")
                }
            }
            .font(palette.display(metrics.titleSize))
            .foregroundStyle(palette.ink)
            // Switching boards under a live field would rename the new one to
            // the old one's half-typed name.
            .onChange(of: board.id) { _, _ in renamingBoardID = nil }
        } else {
            Text("No board", comment: "Toolbar title once the last board has been deleted")
                .font(palette.display(metrics.titleSize))
                .foregroundStyle(palette.inkText(0.4))
                .lineLimit(1)
        }
    }

    /// The field, in the bar or in the row that drops out from under it. The
    /// two differ in their width and in nothing else, so they are one view: a
    /// second copy is a second place for the clear button, the hit area and the
    /// token to drift out of step.
    private func searchField(fills: Bool) -> some View {
        @Bindable var store = store
        let pinned = chrome(metrics.searchWidth, cap: 1.35)

        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .symbolSize(metrics.glyph, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(palette.inkText(0.45))
                .accessibilityHidden(true)
            TextField("Search tasks", text: $store.query)
                .textFieldStyle(.plain)
                .font(palette.ui(metrics.searchFont, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)
                .focused($isSearchFocused)
                .fieldHitArea(minHeight: metrics.fieldHit) { isSearchFocused = true }
                .accessibilityIdentifier(Self.searchFieldID)
                // Opened by a press on the button, so it opens focused and with
                // the keyboard, which is the whole errand — `focusWhenReady`
                // rather than `onAppear`, which lands before the field can hold
                // the keyboard and is dropped on the floor.
                //
                // `when:` is what keeps a row that appeared on its own from
                // taking the keyboard: a window narrowed around a live query
                // shows the field so the query stays visible and clearable, and
                // a resize that raises a keyboard is a resize typing into a text
                // field.
                .focusWhenReady($isSearchFocused, when: fills && isSearchOpen)
                // The panel opens with the field, so a search that has been
                // asked for is a list of somewhere to go rather than a caret in
                // an empty box. It lists everything until there is a query to
                // narrow it — see `BoardStore.searchResults`.
                .onChange(of: isSearchFocused) { _, focused in
                    if focused { isShowingResults = true }
                }
                // Typing opens it; *clearing* must not. `reveal` drops the
                // query on its way out, so without the second test choosing a
                // result closed the panel and this re-opened it a frame later,
                // showing every task in the app over the card just gone to.
                // Measured on the desk, with the × as well as with a result.
                .onChange(of: store.query) { _, query in
                    if isSearchFocused, !query.isEmpty { isShowingResults = true }
                    // The rows underneath it have changed, so the row Return
                    // would take is no longer the row that was under the
                    // highlight.
                    highlighted = nil
                }
                // ↑/↓ walk the panel. They are pressed here because the panel
                // never holds focus — see `SearchResultsPanel`.
                .onKeyPress(.downArrow) {
                    guard isShowingResults else { return .ignored }
                    moveHighlight(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard isShowingResults else { return .ignored }
                    moveHighlight(by: -1)
                    return .handled
                }
                // Escape is "never mind", and a search is one thing to mind:
                // the panel goes and the query goes with it, which is what a
                // search field does everywhere else on the desk. The field
                // keeps the keyboard, so the next thing typed starts a fresh
                // search rather than landing nowhere. A second press has no
                // panel to take and belongs to whatever is behind — except on a
                // folded bar, where it puts the row away.
                .onKeyPress(.escape) {
                    if isShowingResults {
                        closeResults()
                        store.clearQuery()
                        return .handled
                    }
                    guard fills else { return .ignored }
                    closeSearchRow()
                    return .handled
                }
                // Return takes the highlighted result. With nothing highlighted
                // it drops the keyboard and leaves the query standing, which is
                // what it has always done.
                .onSubmit {
                    if let highlighted { choose(highlighted) } else { isSearchFocused = false }
                }
            // Selecting the field's text to delete it is a keyboard errand for
            // a state the user can see from across the room.
            if !store.query.isEmpty {
                Button { store.clearQuery() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(palette.inkText(0.32))
                        .frame(minWidth: metrics.fieldHit, minHeight: metrics.fieldHit)
                }
                .buttonStyle(.bare)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        // In the bar, the one fixed width in the row that has to stay one: a
        // flexible field and the `Spacer` beside it both claim the slack, and
        // the title loses. It grows with the type inside it and stops at the
        // cap. In the row below there is nothing to lose the slack to, so it
        // takes the width — which is the point of dropping it there.
        .frame(minWidth: fills ? nil : pinned,
               maxWidth: fills ? .infinity : pinned,
               alignment: .leading)
        .frame(minHeight: chrome(metrics.control))
        .background(palette.ink(0.05), in: .rect(cornerRadius: metrics.controlRadius))
        // Where the panel hangs from. In the bar's own space rather than the
        // window's, because that is the space the overlay is laid out in.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.barSpace)) } action: {
            fieldFrame = $0
        }
    }

    /// The bar's own coordinate space, so the field's frame and the panel's
    /// offset are the same numbers.
    private static let barSpace = "SimpleKanban.toolbar"

    /// The field, folded.
    ///
    /// A button rather than a narrower field: 44pt of field holds about three
    /// characters, and the row underneath gets the whole width instead. It is
    /// marked while it is standing in for something — selected while the row is
    /// out, and outlined in the accent while there is a query, so a search is
    /// never running behind a bar that looks idle.
    private var searchToggle: some View {
        Button { toggleSearchRow() } label: {
            Image(systemName: "magnifyingglass")
                .symbolSize(metrics.glyph + 1, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(showsSearchRow ? palette.ink : palette.inkText(0.45))
                .frame(minWidth: chrome(metrics.control), minHeight: chrome(metrics.control))
                .background(showsSearchRow ? palette.ink(0.07) : .clear,
                            in: .rect(cornerRadius: metrics.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.controlRadius)
                        .strokeBorder(store.isFiltering ? palette.accent : palette.ink(0.12),
                                      lineWidth: store.isFiltering ? 2 : 1)
                }
                .contentShape(.rect(cornerRadius: metrics.controlRadius))
        }
        .buttonStyle(.bare)
        // Not read by anyone — an identifier is not a label — but the one way a
        // UI test can tell this button from the glyph inside the field it folded
        // out of, both of which are a magnifying glass because both are search.
        .accessibilityIdentifier(Self.searchToggleID)
        .accessibilityLabel("Search tasks")
        .accessibilityAddTraits(showsSearchRow ? [.isSelected] : [])
        .help(showsSearchRow ? "Hide the search field" : "Search tasks")
    }

    /// Shared with `UITests/ToolbarFoldTests` through the source rather than by
    /// both spelling the same string — the arrangement ``inboxToggleID`` has.
    static let searchToggleID = "SearchToggle"
    static let searchFieldID = "SearchField"

    /// A `+` in a filled circle, and nothing else — the same control the phone
    /// floats over its tab bar (``PhoneTabBar/quickCaptureButton``), at the size
    /// the rest of this row is.
    ///
    /// **No word beside it.** The label was 73pt of a row that has only the
    /// board's name to give, and a `+` in the accent is the one glyph in this
    /// app that already means *make one of these* — it is what the columns, the
    /// Inbox panel and the phone all draw. What the word carried is carried by
    /// the accessibility label instead, which is what a reader gets either way:
    /// a button whose label is its glyph publishes nothing without one.
    ///
    /// Where the card lands is Settings ▸ **New tasks go to**, which is why this
    /// is `beginAddingWhereVisible` rather than the phone's `quickCapture` — the
    /// board is on screen here, so "where you are" is a place the user can see.
    @ViewBuilder private var captureButton: some View {
        if let diameter = metrics.capture {
            Button {
                store.beginAddingWhereVisible()
            } label: {
                Image(systemName: "plus")
                    // Off the circle rather than off the bar's glyph size, so
                    // the two keep their proportion if the circle ever changes:
                    // the phone draws 24 in 52, which is this.
                    .symbolSize(diameter * 0.45, weight: .medium, relativeTo: .title3)
                    .foregroundStyle(palette.onAccent)
                    .frame(minWidth: chrome(diameter), minHeight: chrome(diameter))
                    .background(palette.accent, in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.bare)
            .help("New task")
            // The glyph publishes nothing, so this is the whole of what the
            // button is called. ⌘N is the File menu's on the desk and there is
            // no menu bar here, so it carries no key of its own either.
            .accessibilityLabel("New task")
        }
    }

    private var inspectorToggle: some View {
        Button {
            store.isInspectorOpen.toggle()
        } label: {
            Image(systemName: "sidebar.right")
                .symbolSize(metrics.glyph + 1, weight: .medium, relativeTo: .subheadline)
                .foregroundStyle(store.isInspectorOpen ? palette.ink : palette.inkText(0.45))
                .frame(minWidth: chrome(metrics.control), minHeight: chrome(metrics.control))
                .background(store.isInspectorOpen ? palette.ink(0.07) : .clear, in: .rect(cornerRadius: metrics.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: metrics.controlRadius)
                        .strokeBorder(palette.ink(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.bare)
        .help("Toggle details sidebar")
        .accessibilityLabel("Toggle details sidebar")
        // ⌥⌘I is the View menu's. Nothing in this bar claims a key of its own:
        // two claims on one key is the drift `AppCommand` exists to stop, and a
        // menu is where a shortcut is discoverable.
    }
}
