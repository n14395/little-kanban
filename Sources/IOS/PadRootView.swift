#if os(iOS)

import SwiftUI

/// The iPad screen: the desk's three panes — source list, board, inspector —
/// in a `NavigationSplitView`.
///
/// Every one of those panes is the same view macOS draws, at its `.pad`
/// metrics: `BoardSidebar`, `BoardToolbar`, `BoardScrollView` and
/// `TaskInspector` all live in `Sources/Shared` precisely so this file does not
/// have to be a third copy of the board. What is genuinely the iPad's is the
/// container and the two flat surfaces below, which are a list and a heading.
///
/// A split view rather than a layout of our own because slide-over, Stage
/// Manager and the sidebar's show/hide behaviour come with it; the drawer the
/// phone uses would have to reimplement all three.
struct PadRootView: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock

    /// Whether the source list is showing. `.automatic` lets the system decide
    /// on the way in — beside the board in landscape, over it in portrait — and
    /// the toolbar's button drives it from there.
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    /// The app's, when there is an app. iPadOS draws a menu bar for us now — see
    /// ``BoardCommands`` — and the menu bar is outside every view tree, so the
    /// state it reads and writes is owned above this view. Optional for
    /// `MacRootView`'s reason: this view must still stand up in a preview, which
    /// has no app and no menu bar to have been opened from.
    @Environment(AppWindowState.self) private var injectedWindow: AppWindowState?
    @State private var standaloneWindow = AppWindowState()
    /// The board's own; see ``BoardFocusRelay``. The board asks it which column
    /// the keyboard is in before scrolling — without one it would re-centre the
    /// strip under every arrow press — and it is mirrored onto the window state
    /// the menu bar reads, exactly as the desk mirrors it.
    @State private var focusRelay = BoardFocusRelay()
    /// Which row the keyboard is on in the flat surfaces. Owned here for
    /// `BoardScrollView`'s reason: ↑ and ↓ cross rows, and a row cannot see its
    /// neighbours.
    @FocusState private var focus: TaskItem.ID?
    /// How wide the board and the panel have to share, measured rather than
    /// assumed: an iPad's detail pane changes width with the source list, the
    /// orientation and Stage Manager, and the panel is a column only while
    /// there is a column's worth left for the board.
    @State private var rowWidth: CGFloat = 0
    /// The whole detail column, panel included — which `rowWidth` is not, since
    /// the panel is that row's sibling. Measuring the room for the panel off a
    /// width the panel is subtracted from is a feedback loop: it fits, so it
    /// appears, so the row shrinks, so it no longer fits. Measured once, here.
    @State private var detailWidth: CGFloat = 0
    /// The whole split view, source list included — which `detailWidth` is not.
    /// The difference between the two is what the list is costing the board, and
    /// that difference is the only thing that knows whether this window can hold
    /// the panels that are open on both sides of it. See ``panelRoom``.
    @State private var windowWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var chrome = ChromeScale()

    private var resolvedWindow: AppWindowState { injectedWindow ?? standaloneWindow }

    /// `sheet(item:)` wants something `Identifiable`, and the store keeps the
    /// id — the same mapping `PhoneRootView` makes for the drawer's row.
    private var editingView: Binding<SavedViewDraft?> {
        Binding(
            get: { store.editingViewID.flatMap { store.view(id: $0) }.map(SavedViewDraft.init) },
            set: { store.editingViewID = $0?.id }
        )
    }

    var body: some View {
        @Bindable var store = store
        @Bindable var window = resolvedWindow

        return NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
        // **Three panels, one window, and whichever was opened wins.**
        //
        // The source list and the Inbox open on the left, the inspector on the
        // right, and each is a column wide. A window that cannot hold what is
        // open *and* a board worth looking at has to put something away, and
        // the alternative to choosing is what this used to do on either side:
        // decline to draw the Inbox — a button that appears not to work — or
        // draw the inspector on top of the board. Which one gives way is
        // ``yields(to:in:)``, and it is never more of them than it takes.
        //
        // The source list is the one of the three that is not asked for here:
        // ``toggleSidebar`` and ``revealSidebar`` are, because **the ask is the
        // trigger and the measurement is not**. Watching the list take width
        // reads the system's own answer as the reader's: `.automatic` puts the
        // list out at launch on an 11" in portrait and takes it away again a
        // moment later, and a rule keyed on that collapsed the editor on the way
        // in — measured, `beside=true d=516` then `insp=false` then
        // `beside=false d=834`, which is a window that shut one of its panels
        // before anybody had touched it.
        //
        // `isInboxShowing` rather than `isInboxOpen`: the panel stands beside the
        // board and a saved view has taken the board's place, so on Today the
        // flag is set and there is nothing on screen to make room for.
        .onChange(of: store.isInboxShowing) { _, showing in
            guard showing else { return }
            makeRoom(for: .inbox, in: panelRoom)
        }
        // And the panel on the other side of the board, whose usual way in is a
        // tap on a card rather than a button — `BoardTaskCard.click` opens it,
        // as does `BoardStore.reveal`. Only the transition is watched, so a
        // second card tapped while it is already out reflows nothing.
        .onChange(of: store.isInspectorOpen) { _, open in
            guard open else { return }
            makeRoom(for: .inspector, in: panelRoom)
        }
        // The source list's other way in, and the same gesture the phone's
        // drawer answers. A split view looks like it should bring this with it
        // — `UISplitViewController` has `presentsWithGesture` — and measured on
        // an iPad Pro 13" in portrait it does not: a pull from x=0 across the
        // board left the list where it was. What claims that pan is the board's
        // own horizontal scroll view, which is exactly what `leadingEdgeSwipe`
        // is built to outrank.
        .leadingEdgeSwipe(perform: revealSidebar)
        .boardToast(metrics: .sheet)
        // What the menu bar opens. All four are presented here rather than by
        // whatever asked for them, for one reason: the asker is a menu item and
        // menu items are outside every view tree. The source list presents its
        // own label manager and its own view editor from its own state, which is
        // right — a row can present the sheet it asks for — and these are the
        // menu's, which is why they are separate flags.
        .sheet(isPresented: $store.isShowingShortcuts) {
            ShortcutsSheet()
        }
        .sheet(isPresented: $window.isPickingDueDate) {
            DueDateSheet()
        }
        .sheet(item: editingView) { draft in
            SavedViewEditor(viewID: draft.id, metrics: .sheet)
        }
        .labelManagerSheet(isPresented: $window.isManagingLabels, metrics: .sheet)
        // **The source list is the split view's column, not a child of ours**,
        // so View ▸ Toggle Sidebar cannot simply hide a view: it asks for the
        // flag, and this is where the flag becomes `columnVisibility`. Written
        // back the other way too, because the button, the edge swipe and the
        // system's own `.automatic` all move that column without asking the
        // menu — and a tick that says the list is out while it is away is worse
        // than no tick.
        .onChange(of: window.isSidebarVisible) { _, visible in
            setSidebar(visible)
        }
        .onChange(of: columnVisibility) { _, visibility in
            window.isSidebarVisible = visibility != .detailOnly
        }
        // Both directions, because the menu hands focus on as well as reading
        // it: ⌘⌫ names the neighbour of the card it deleted. Each write is a
        // no-op when the two already agree, so neither can chase the other.
        .onChange(of: focusRelay.focusedTaskID) { _, id in window.focusedTaskID = id }
        .onChange(of: window.focusedTaskID) { _, id in focusRelay.focusedTaskID = id }
        // One way only: nothing outside the board sets which column is under
        // the keyboard, ⌘N only asks.
        .onChange(of: focusRelay.focusedColumnID) { _, id in window.focusedColumnID = id }
        .environment(resolvedWindow)
        .environment(focusRelay)
        .background(palette.windowFill.ignoresSafeArea())
        .motionAnimation(.easeOut(duration: 0.16), value: store.surface)
        // The same two acts the phone marks (5.8): picking where you are.
        .sensoryFeedback(.selection, trigger: store.surface)
    }

    // MARK: Panes

    /// In a scroll view because the list is taller than a landscape iPad mini
    /// once every row claims its 44pt, and a source list that cannot reach its
    /// last row is worse than one that scrolls.
    private var sidebar: some View {
        // **The whole pane, down to the glass.** Bleeding the fill alone got the
        // colour to the bottom and left the *list* where it was, so a sidebar
        // scrolled to its last row still showed a band of empty panel under it —
        // the fill was right and the rows still stopped short. ``HomeIndicatorFoot``
        // is what answers that, and carries the measurements: an
        // `ignoresSafeArea` on the scroll view will not do it, because inside a
        // split view column the inset is a margin UIKit has already applied.
        //
        // The board's strip and a saved view take the same strip back. What
        // still stops at the inset is the Inbox panel's rows and the task
        // editor's fields, which bleed only their fills; see `detail`.
        ScrollView {
            // The two bindings a menu bar needs: File ▸ New Board opens the
            // list's own naming field rather than making an untitled board, and
            // the window takes itself out of the accessibility tree while the
            // label manager is up.
            BoardSidebar(
                metrics: .pad,
                isNamingNewBoard: Binding(
                    get: { resolvedWindow.isNamingNewBoard },
                    set: { resolvedWindow.isNamingNewBoard = $0 }
                )
            )
        }
        .scrollBounceBehavior(.basedOnSize)
        // **The column's ground and its seam, both hung here**, because the
        // scroll view is the only thing in this column that is the column's
        // height. `BoardSidebar` paints them on the desk, where it *is* the
        // column; in here it is as tall as its rows and no taller, so its wash
        // stopped under the last one and its hairline stopped with it. What
        // that left was a band of column under the list carrying the wash once
        // where the list above carried it twice — from the pane and from here —
        // and no line down the side of it at all. One wash now, over the whole
        // column, which is what the inspector and the Inbox panel each get and
        // what the desk's source list has always had.
        .background(palette.panelOverlay)
        .hairline(.trailing, color: palette.ink(0.07))
        .underTheHomeIndicator()
        .navigationSplitViewColumnWidth(
            min: chrome(260, cap: 1.4), ideal: chrome(Self.sidebarIdeal, cap: 1.4),
            max: chrome(360, cap: 1.4)
        )
        // The bar would draw a second, empty header above our own.
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The toolbar, and under it the board with its panel beside it.
    ///
    /// The panel is laid out here rather than taken from `.inspector` on the
    /// detail column. That spelling put the panel over the *whole* column,
    /// toolbar included: in portrait with the source list out, the bar's capture
    /// button — a labelled **New task** then, 117×44 — measured at x=839 inside
    /// a 1032pt window and reported `hittable=false`, because the inspector was
    /// drawn on top of it. The primary action of the surface was unreachable in
    /// one of the two orientations. An `HStack` under the toolbar is what macOS does with the
    /// same three pieces — see `MacRootView` — and it cannot cover a sibling.
    private var detail: some View {
        HStack(spacing: 0) {
            // Full height of the detail column, toolbar row included, so the
            // panel starts where the source list stops — the same place it
            // starts on the desk.
            if store.isInboxShowing, hasRoomForTheInbox {
                InboxPanel(metrics: .pad)
                    .transition(.move(edge: .leading))
            }

            VStack(spacing: 0) {
            BoardToolbar(metrics: .pad, toggleSidebar: toggleSidebar)
                // The search results hang out of the bar and over the board and
                // the inspector, which are the next two siblings down — see
                // `BoardToolbar.resultsPanel`.
                .zIndex(1)
            HStack(spacing: 0) {
                surface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.isInspectorOpen, hasRoomBesideTheBoard {
                    inspector
                        .frame(width: inspectorWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Where there is not room for both, the panel goes *over the
            // board* — never over the toolbar, which is the whole point. An
            // iPad mini in portrait with the source list out leaves 130pt of
            // detail beside a 384pt panel, and 130pt is half a column: showing
            // the board underneath is worth more than showing a sliver of it.
            .overlay(alignment: .trailing) {
                if store.isInspectorOpen, !hasRoomBesideTheBoard {
                    inspector
                        .frame(width: inspectorWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
        // The Inbox panel's `.move(edge: .leading)` takes it a column's width
        // to the left of where it sits, and the split view does not clip its
        // detail column — so without this the panel slides in from the far left
        // of the *window*, across the source list, and out the same way. The
        // desk answers the same thing by drawing the source list above the
        // panel; here the two are in different containers, so `zIndex` has
        // nothing to say and the column has to hold its own edge.
        //
        // **Open at the foot**, because the edge it is holding is a *side* one.
        // This was `.clipped()`, on the column's own bounds — and those bounds
        // stop at the home indicator's 20pt inset, so it cut off the Inbox
        // panel's fill and the task editor's exactly where they bleed under it
        // (see `sidebar`). That strip of window fill under two of the three
        // panels and not the third is what a clip meant for the sides was
        // costing. Nothing in this column draws below its foot but those fills.
        .clipShape(OpenFooted())
        .background(palette.windowFill)
        // No `value: store.selection` here: keyed on the selection, every tap
        // on a card put the whole detail column through a 0.16s diff. The
        // inspector pane animates its own task swap, and the card its own ring.
        .motionAnimation(.easeOut(duration: 0.16), value: store.isInspectorOpen)
        .motionAnimation(.easeOut(duration: 0.16), value: store.isInboxShowing)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// What `.inspector`'s ideal width was. A fixed column rather than a
    /// resizable one: the divider came with `.inspector`, and so did drawing
    /// over the toolbar.
    /// Both grow with the reader's text size, by the same factor the panel and
    /// the columns inside them do — otherwise a 384pt slot holds a panel that
    /// has grown to 518 and clips it, and the floor lets a column through that
    /// is no longer wide enough to draw.
    private var inspectorWidth: CGFloat { chrome(Self.baseInspectorWidth, cap: TaskInspector.widthCap) }
    /// Not private: `SidebarRoomTests` asks what this window closes and for
    /// which panel, and the answer is arithmetic on this number. A copy of it
    /// in the test would go on passing after the panel had been widened.
    static let baseInspectorWidth: CGFloat = 384
    /// What the split view lays the source list out at, named once because two
    /// things read it: the column-width modifier that asks for it, and
    /// ``makeRoomForTheSourceList``, which has to know what the list will take
    /// while the list is not there to be measured.
    static let sidebarIdeal: CGFloat = 300

    /// The board's own floor: one `.pad` column and the strip's margins. Below
    /// it the panel stops being a column and becomes an overlay.
    private var boardFloor: CGFloat { chrome(BoardColumnView.Metrics.pad.width) + 32 }

    private var hasRoomBesideTheBoard: Bool {
        // Zero before the first layout pass, which must not read as "no room":
        // the panel would flash as an overlay on the way in.
        rowWidth <= 0 || rowWidth - inspectorWidth >= boardFloor
    }

    /// What the source list is taking from the board right now: the difference
    /// between the window and the detail column. Zero when it is not out — and
    /// zero as well when the system has drawn it *over* the board rather than
    /// beside it, which is the right answer both times, because this is what the
    /// list costs the board rather than whether it is on screen.
    private var sidebarCost: CGFloat { max(0, windowWidth - detailWidth) }
    private var sidebarIsBesideTheBoard: Bool { sidebarCost > 1 }

    /// What the three panels are costing the board right now, and what the
    /// window has to fit them in.
    ///
    /// **What is open, not what could be.** The source list is counted at what
    /// it is actually taking — nothing at all when the system has drawn it over
    /// the board rather than beside it, which is the honest answer, since a
    /// panel that costs the board nothing is not competing for anything.
    private var panelRoom: PanelRoom {
        PanelRoom(
            window: windowWidth,
            floor: boardFloor,
            sourceList: sidebarIsBesideTheBoard ? sidebarCost : 0,
            inbox: store.isInboxShowing ? chrome(InboxPanel.Metrics.pad.width) : 0,
            inspector: store.isInspectorOpen ? inspectorWidth : 0
        )
    }

    /// The source list is about to open, which is a press rather than a
    /// measurement: it is not laid out yet, so what it will take is the
    /// column's own ideal — the same estimate-rather-than-oscillate trade the
    /// toolbar's fold makes about its own row. Where the list is already out
    /// beside the board, the measurement stands.
    private func makeRoomForTheSourceList() {
        makeRoom(
            for: .sourceList,
            in: panelRoom.opening(.sourceList, at: chrome(Self.sidebarIdeal, cap: 1.4))
        )
    }

    /// One of the three has just opened: put away whatever it takes for it to
    /// have its room, and nothing more.
    ///
    /// The whole list is worked out from one snapshot before anything is
    /// closed, so what happens does not depend on the order the closes land in
    /// or on when the layout catches up with them. Each close is watched by one
    /// of the handlers above, and each of those only fires on the way *open*,
    /// which is what keeps this from answering itself.
    private func makeRoom(for opened: Panel, in room: PanelRoom) {
        for panel in Self.yields(to: opened, in: room) {
            switch panel {
            case .sourceList:
                // The one panel this view does not own: it is the split view's
                // column, and `columnVisibility` is how it is asked.
                Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
                    columnVisibility = .detailOnly
                }
            case .inbox:
                store.isInboxOpen = false
            case .inspector:
                store.isInspectorOpen = false
            }
        }
    }

    /// Whether the Inbox panel fits without taking the board's last column.
    ///
    /// The inspector answers this by moving on top of the board when it will
    /// not fit; the Inbox cannot borrow that trick, because it sits *above* the
    /// toolbar and an overlay there is exactly the defect the panel's own
    /// comment describes — the button drawn over and unhittable. So it waits
    /// instead.
    ///
    /// **And it waits for the board alone.** The inspector's width used to count
    /// against this too, which looked like arithmetic and behaved like a dead button:
    /// an 11" in portrait is 834pt, and 834 less the inspector's 384 and the
    /// panel's 320 is 130 — so with a task selected the panel went on declining
    /// *after* the source list had closed to make room for it, and the Inbox
    /// button did nothing but put the source list away. The inspector needs no
    /// room reserved here precisely because it has its own answer to being
    /// squeezed: it draws over the board. This one counts what cannot move.
    ///
    /// What is left for it to decline is a detail column with no room for a
    /// panel and a board at all — 672pt, down where `RootSurface` is about to
    /// hand the window to the phone's layout anyway.
    private var hasRoomForTheInbox: Bool {
        Self.holdsTheInbox(
            detail: detailWidth, panel: chrome(InboxPanel.Metrics.pad.width), floor: boardFloor
        )
    }

    /// The two things the main area can be, exactly as on the desk. The Inbox
    /// is not one of them: it is global, and it now stands beside the board in
    /// a panel of its own rather than taking the board's place.
    @ViewBuilder
    private var surface: some View {
        switch store.surface {
        case .board:
            BoardScrollView(metrics: .pad)
        case .view(let id):
            // Looked up on every draw rather than carried: the view is editable
            // now, so a copy taken when the surface was chosen would go on
            // drawing the rule the editor has just changed.
            if let view = store.view(id: id) { savedViewList(view) }
        }
    }

    /// The panel holds its column with nothing selected, the way the desk's
    /// does: dropping it would reflow the board out from under the toggle that
    /// had just done what it says.
    @ViewBuilder
    private var inspector: some View { PadInspectorPane() }

    // MARK: Which panel gives way

    /// The three panels that share an iPad window, in the order they stand in
    /// it: the split view's source list, the Inbox beside the board, and the
    /// task editor on the far side.
    ///
    /// They are one type rather than three flags because they compete for one
    /// thing — the width the board is left with — and a rule written per pair
    /// is three rules that have to agree.
    enum Panel: CaseIterable, Sendable {
        case sourceList, inbox, inspector

        /// What gives way for this one, and in what order.
        ///
        /// **Furthest from what was just asked for goes first.** The reader's
        /// attention is where they have just clicked, so the panel at the other
        /// end of the window is the one they are least likely to miss — and it
        /// is the one whose going leaves the thing they asked for next to what
        /// they were already looking at rather than pushed across the screen.
        ///
        /// It is also why opening either panel on the left collapses the task
        /// editor before it touches the other one: on an 11" in landscape the
        /// two left-hand panels fit together perfectly well once the editor is
        /// away, so making them take turns while a third column sat on the far
        /// side was answering the wrong question.
        var yieldOrder: [Panel] {
            switch self {
            case .sourceList: [.inspector, .inbox]
            case .inbox: [.inspector, .sourceList]
            case .inspector: [.sourceList, .inbox]
            }
        }
    }

    /// What each panel is costing the board, and the window they are costing it
    /// out of. Zero is a panel that is not open — or one the system has drawn
    /// *over* the board, which takes nothing from it and is the same answer.
    struct PanelRoom: Equatable, Sendable {
        var window: CGFloat
        /// One `.pad` column and the strip's margins: a board narrower than
        /// this is not a board.
        var floor: CGFloat
        var sourceList: CGFloat = 0
        var inbox: CGFloat = 0
        var inspector: CGFloat = 0

        /// Whether what is open leaves a board worth looking at.
        ///
        /// Zero before the first layout pass reads as *room*, which is the safe
        /// way round: the alternative is a window that shuts one of its panels
        /// on the way in.
        var holdsWhatIsOpen: Bool {
            guard window > 0 else { return true }
            return window - sourceList - inbox - inspector >= floor
        }

        func cost(of panel: Panel) -> CGFloat {
            switch panel {
            case .sourceList: sourceList
            case .inbox: inbox
            case .inspector: inspector
            }
        }

        /// The same window with a panel that is about to open counted at what
        /// it will take. A panel already out is left at what it is measured to
        /// be costing — the estimate is only ever for the one that is not there
        /// to be measured yet.
        func opening(_ panel: Panel, at width: CGFloat) -> PanelRoom {
            guard cost(of: panel) <= 0 else { return self }
            var room = self
            switch panel {
            case .sourceList: room.sourceList = width
            case .inbox: room.inbox = width
            case .inspector: room.inspector = width
            }
            return room
        }

        func closing(_ panel: Panel) -> PanelRoom {
            var room = self
            switch panel {
            case .sourceList: room.sourceList = 0
            case .inbox: room.inbox = 0
            case .inspector: room.inspector = 0
            }
            return room
        }
    }

    /// Which panels close when `opened` opens, in the order they close.
    ///
    /// Static and arithmetic so that `PadSurfaceTests` can ask it: what it
    /// decides is which panel disappears from under the reader, and a rule that
    /// only a booted iPad can be asked is one that gets re-derived by hand every
    /// time somebody changes a column's width.
    ///
    /// **Never more than it takes.** Each candidate is only closed while the
    /// window still does not hold what is open, so a window that fits three
    /// panels closes none of them, and one that only had to lose the editor
    /// keeps both panels on the left.
    static func yields(to opened: Panel, in room: PanelRoom) -> [Panel] {
        var room = room
        var closing: [Panel] = []
        for panel in opened.yieldOrder where !room.holdsWhatIsOpen {
            // A panel that is not open takes nothing and gives nothing: skip it
            // rather than counting it as this window's answer, or the next one
            // along never gets asked.
            guard room.cost(of: panel) > 0 else { continue }
            room = room.closing(panel)
            closing.append(panel)
        }
        return closing
    }

    /// Whether a detail column this wide holds the Inbox panel and a board.
    ///
    /// The inspector is deliberately not an argument — ``hasRoomForTheInbox``
    /// says why — and this rule and ``yields(to:in:)`` have an invariant between
    /// them that only a test can hold: whatever ``yields(to:in:)`` closes for
    /// the Inbox, the window it leaves has to be one this accepts. Where it does
    /// not, the Inbox button puts other panels away and nothing else happens,
    /// which is the dead button the turn-taking was written to remove.
    ///
    /// Zero reads as *room* for the same reason as above: the first layout pass
    /// must not shut a panel on the way in.
    static func holdsTheInbox(detail: CGFloat, panel: CGFloat, floor: CGFloat) -> Bool {
        guard detail > 0 else { return true }
        return detail - panel >= floor
    }

    /// `.automatic` is whatever the system chose, and the first press has to
    /// mean something either way round: in landscape it hides the list, in
    /// portrait — where the list is already off screen — it brings it out.
    private func toggleSidebar() {
        let opening = columnVisibility == .detailOnly
        if opening { makeRoomForTheSourceList() }
        Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
            columnVisibility = opening ? .all : .detailOnly
        }
    }

    /// The menu bar's half of the same act. It says which state it wants rather
    /// than which way to flip, because a menu item is pressed against a tick
    /// that may already be right — and it goes through `makeRoomForTheSourceList`
    /// like the other two, so a list brought out from the menu puts away
    /// whatever it needs to exactly as the button's does.
    private func setSidebar(_ visible: Bool) {
        guard visible != (columnVisibility != .detailOnly) else { return }
        if visible { makeRoomForTheSourceList() }
        Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
            columnVisibility = visible ? .all : .detailOnly
        }
    }

    /// A pull from the edge only ever means *show me the list*. It is not the
    /// button's other half: in landscape the list is already beside the board,
    /// and a gesture that put it away would be the swipe undoing itself on the
    /// one shape where the edge and the list are the same place.
    private func revealSidebar() {
        guard columnVisibility != .all else { return }
        makeRoomForTheSourceList()
        Motion.run(.easeOut(duration: 0.2), reduceMotion: reduceMotion) {
            columnVisibility = .all
        }
    }

    // MARK: The flat surfaces

    /// **No header over the list.** The view is named in the toolbar's title —
    /// see ``BoardToolbar`` — and a strip under it saying the same thing was one
    /// answer given twice, at the cost of 60 points of list.
    private func savedViewList(_ view: SavedView) -> some View {
        let tasks = store.tasks(in: view, today: dayClock.today)

        return VStack(spacing: 0) {
            if tasks.isEmpty {
                savedViewEmptyState(view)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list(tasks)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The same card the board draws, not the phone's. Tapping it selects and
    /// opens the inspector — this surface has one — where a tap on the phone
    /// raises a sheet the iPad never presents; and the keyboard reaches these
    /// rows for the same reason the desk's do.
    private func list(_ tasks: [TaskItem]) -> some View {
        TaskColumnsView(tasks: tasks, metrics: .pad) { task in
            ListCard(task: task, metrics: .pad, focus: $focus)
        }
    }

    /// One emptiness now: a view with nothing in it. The query opens
    /// ``SearchResultsPanel`` over the board rather than narrowing what is
    /// behind it, so a view the search emptied is not a state this can be in.
    private func savedViewEmptyState(_ view: SavedView) -> some View {
        EmptyStateView.savedView(view, metrics: .sheet)
    }
}

/// The inspector column: the selected task's panel, or the empty state.
///
/// A view of its own for `MacInspectorPane`'s reason: `selectedTask` reads the
/// selection *and* the whole `tasks` array, so read from `PadRootView.body`
/// it re-ran the entire detail column on every task edit. The pane is where
/// that dependency stops, and it keeps the fade the column-level
/// `value: store.selection` animation used to give the panel swap.
private struct PadInspectorPane: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var body: some View {
        Group {
            if let task = store.selectedTask {
                TaskInspector(task: task, metrics: .pad)
            } else {
                EmptyStateView.noSelection(metrics: .sheet)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Down to the glass, the way `TaskInspector` is: the empty
                    // state is the same panel with nothing in it, and a pane
                    // that changes height when a card is picked is worse than
                    // either height.
                    .background(palette.panelOverlay.ignoresSafeArea(.container, edges: .bottom))
            }
        }
        .motionAnimation(.easeOut(duration: 0.16), value: store.selectedID)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A rectangle with no floor: the view's own bounds, carried far enough past
/// the foot that whatever bleeds under the home indicator survives the clip.
///
/// ``PadRootView`` clips its detail column to hold the column's *sides* — see
/// the comment on the call — and a clip that also closed the bottom took the
/// panels' fills with it.
private struct OpenFooted: Shape {
    /// Deeper than any inset a device reports — the iPad's is 20pt — and
    /// finite, because a rectangle of infinite height is not one any renderer
    /// wants to intersect.
    static let depth: CGFloat = 200

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY,
                    width: rect.width, height: rect.height + Self.depth))
    }
}

#endif
