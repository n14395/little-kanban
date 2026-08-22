import SwiftUI

/// The board header: title, search, new-task button, inspector toggle.
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
        /// The label on the New task button.
        var buttonFont: CGFloat
        /// The square, or the height, every control in the bar claims.
        var control: CGFloat
        var controlRadius: CGFloat
        var glyph: CGFloat
        /// What the two text fields claim — see ``FieldHitArea``.
        var fieldHit: CGFloat

        // The desk's height is the row the window's traffic lights sit on —
        // there is no title bar, so this bar *is* the chrome rather than a
        // strip beneath it, and 50 is the tallest row whose centre the lights
        // can still be moved to: AppKit's own title bar is 32pt, a light is
        // 14pt, and one hanging out of that bar draws where it is asked to and
        // then refuses the click. See `windowButtons(centredAt:)`.
        static let desk = Metrics(
            height: 50, spacing: 14, horizontalPadding: 20, titleSize: 24, searchWidth: 216,
            searchFont: 13, buttonFont: 12.5, control: 34, controlRadius: 10, glyph: 12,
            fieldHit: 0
        )
        static let pad = Metrics(
            height: 72, spacing: 14, horizontalPadding: 18, titleSize: 26, searchWidth: 220,
            searchFont: 15, buttonFont: 14.5, control: 44, controlRadius: 12, glyph: 15,
            fieldHit: 44
        )
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

    var metrics: Metrics = .desk
    /// Room for the window controls when the sidebar is not there to hold it.
    var leadingInset: CGFloat = 0
    /// Shows and hides the source list. The menu bar owns that on the desk and
    /// passes `nil`; a split view has no chrome of ours to put it in, so on
    /// iPad the bar carries the button itself.
    var toggleSidebar: (() -> Void)?

    var body: some View {
        HStack(spacing: metrics.spacing) {
            sidebarToggle
            inboxToggle
            title

            Spacer(minLength: 0)

            searchField
            newTaskButton
            inspectorToggle
        }
        .padding(.leading, metrics.horizontalPadding + leadingInset)
        .padding(.trailing, metrics.horizontalPadding)
        .frame(minHeight: chrome(metrics.height))
        .hairline(.bottom, color: palette.ink(0.07))
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
                        .onAppear { isTitleFocused = true }
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
            .font(SimpleKanbanFont.serif(metrics.titleSize))
            .foregroundStyle(palette.ink)
            // Switching boards under a live field would rename the new one to
            // the old one's half-typed name.
            .onChange(of: board.id) { _, _ in renamingBoardID = nil }
        } else {
            Text("No board", comment: "Toolbar title once the last board has been deleted")
                .font(SimpleKanbanFont.serif(metrics.titleSize))
                .foregroundStyle(palette.inkText(0.4))
                .lineLimit(1)
        }
    }

    private var searchField: some View {
        @Bindable var store = store

        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .symbolSize(metrics.glyph, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(palette.inkText(0.45))
                .accessibilityHidden(true)
            TextField("Search tasks", text: $store.query)
                .textFieldStyle(.plain)
                .font(SimpleKanbanFont.ui(metrics.searchFont, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)
                .focused($isSearchFocused)
                .fieldHitArea(minHeight: metrics.fieldHit) { isSearchFocused = true }
                // Edit ▸ Find. The menu bar is outside this view's tree and
                // cannot reach a `FocusState`, so ⌘F travels as a counter on
                // the store and lands here. A counter rather than a flag: with
                // the field already focused a flag would already be true, and
                // the second ⌘F would be no change at all.
                .onChange(of: store.searchFocusToken) { _, _ in isSearchFocused = true }
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
        // The one fixed width in the bar that has to stay one: a flexible field
        // and the `Spacer` above it both claim the slack, and the title loses.
        // It grows with the type inside it and stops at the cap.
        .frame(width: chrome(metrics.searchWidth, cap: 1.35), alignment: .leading)
        .frame(minHeight: chrome(metrics.control))
        .background(palette.ink(0.05), in: .rect(cornerRadius: metrics.controlRadius))
    }

    private var newTaskButton: some View {
        Button {
            store.beginAddingWhereVisible()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .symbolSize(metrics.glyph, weight: .bold, relativeTo: .subheadline)
                    .accessibilityHidden(true)
                Text("New task")
                    .font(SimpleKanbanFont.ui(metrics.buttonFont, .bold, relativeTo: .subheadline))
            }
            .foregroundStyle(palette.onAccent)
            .padding(.horizontal, 14)
            .frame(minHeight: chrome(metrics.control))
            .background(palette.accent, in: .rect(cornerRadius: metrics.controlRadius))
        }
        .buttonStyle(.bare)
        // ⌘N is the File menu's now. Two claims on one key is exactly the drift
        // `AppCommand` exists to stop, and the menu is where a shortcut is
        // discoverable.
        //
        // The plus is published beside the word whatever it is asked to be, so
        // the subtree is substituted rather than hidden piecemeal.
        .accessibilityRepresentation {
            Button(String(localized: "New task",
                          comment: "Accessibility name of the toolbar button that adds a task")) {
                store.beginAddingWhereVisible()
            }
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
        // ⌥⌘I is the View menu's — see `newTaskButton`.
    }
}
