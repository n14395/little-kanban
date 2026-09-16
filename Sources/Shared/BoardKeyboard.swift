import SwiftUI

/// The board as the keyboard sees it: the columns left to right, and the cards
/// in each in the order they are drawn.
///
/// Built from what is *visible*, not from the board's array — a card the query
/// has hidden is not one an arrow key can land on. A value rather than a view
/// so the navigation rules can be tested without one.
struct BoardFocusMap {
    let columns: [BoardColumn.ID]
    let cards: [BoardColumn.ID: [TaskItem.ID]]

    init(columns: [BoardColumn.ID], cards: [BoardColumn.ID: [TaskItem.ID]]) {
        self.columns = columns
        self.cards = cards
    }

    @MainActor
    init(_ store: BoardStore) {
        let columns = store.columns.map(\.id)
        self.init(
            columns: columns,
            cards: Dictionary(uniqueKeysWithValues: columns.map {
                ($0, store.visibleTasks(in: $0).map(\.id))
            })
        )
    }

    /// Where a card is, as the column's place in the strip and the card's place
    /// in that column. `nil` for a card the board is not drawing.
    func location(of id: TaskItem.ID) -> (column: Int, row: Int)? {
        for (column, columnID) in columns.enumerated() {
            if let row = cards[columnID]?.firstIndex(of: id) { return (column, row) }
        }
        return nil
    }

    func columnID(of id: TaskItem.ID) -> BoardColumn.ID? {
        location(of: id).map { columns[$0.column] }
    }

    /// ↑ and ↓. Clamped rather than wrapped: a list that jumps from its last row
    /// to its first reads as a bug at the moment it happens, and `nil` here lets
    /// the scroll view have the key instead.
    func card(_ id: TaskItem.ID, movedBy rows: Int) -> TaskItem.ID? {
        guard let here = location(of: id),
              let column = cards[columns[here.column]]
        else { return nil }
        let row = here.row + rows
        guard column.indices.contains(row) else { return nil }
        return column[row]
    }

    /// ← and →. Lands on the same row of the next column that has one, so focus
    /// crosses the board at the height it was at rather than jumping to the top
    /// of every column. Empty columns are stepped over — there is nothing in
    /// them to focus.
    func card(_ id: TaskItem.ID, inColumnBy step: Int) -> TaskItem.ID? {
        guard step != 0, let here = location(of: id) else { return nil }
        var index = here.column + step
        while columns.indices.contains(index) {
            if let column = cards[columns[index]], !column.isEmpty {
                return column[min(here.row, column.count - 1)]
            }
            index += step
        }
        return nil
    }

    /// ⌥← and ⌥→: where the card itself goes. The *adjacent* column whether or
    /// not it has anything in it, unlike focus movement — moving a card into an
    /// empty column is most of what an empty column is for.
    func column(_ id: TaskItem.ID, by step: Int) -> BoardColumn.ID? {
        guard step != 0, let here = location(of: id) else { return nil }
        let index = here.column + step
        guard columns.indices.contains(index) else { return nil }
        return columns[index]
    }

    /// Where focus lands once the card holding it has gone: the next card down,
    /// or the one above it when it was last.
    func card(after id: TaskItem.ID) -> TaskItem.ID? {
        card(id, movedBy: 1) ?? card(id, movedBy: -1)
    }

    /// The same, stepped past everything leaving alongside it. ⌘⌫ on a
    /// partial multi-selection trashes the focused card *and* its neighbours,
    /// and a fallback that only looked one row away could land on another
    /// card of the same delete — keyboard focus on a card that is already
    /// gone. Walks down to the first survivor, then up, then gives up, which
    /// is `card(after:)`'s own order at whatever distance it takes.
    func card(after id: TaskItem.ID, skipping leaving: Set<TaskItem.ID>) -> TaskItem.ID? {
        var step = 1
        while let candidate = card(id, movedBy: step) {
            if !leaving.contains(candidate) { return candidate }
            step += 1
        }
        step = -1
        while let candidate = card(id, movedBy: step) {
            if !leaving.contains(candidate) { return candidate }
            step -= 1
        }
        return nil
    }

    /// The one column a flat surface has. Not any board's, and named so a test
    /// can spell it.
    static let flatColumn = BoardColumn.ID()

    /// The flat surfaces — the Inbox, a saved view, the Archive — as the
    /// keyboard sees them: a single column of rows in the order they are drawn.
    ///
    /// ↑ and ↓ read the same on them as on the board. ←/→ and ⌥←/→ have nowhere
    /// to go and refuse, which is the whole of the difference between the two
    /// kinds of surface.
    init(flat ids: [TaskItem.ID]) {
        self.init(columns: [Self.flatColumn], cards: [Self.flatColumn: ids])
    }
}

extension AppCommand {
    /// The command a key press asks for, out of the ones the surface handles.
    ///
    /// Matching against `AppCommand.shortcuts` rather than against literals is
    /// what keeps the board's keys, the menu's and the sheet's the same keys:
    /// ⌥← moves a card because `moveCardLeft` says so in one place.
    ///
    /// Only the four modifiers the app names are compared — a key press carries
    /// caps lock and the numeric pad as well, and neither is part of a shortcut.
    ///
    /// `claimed` is the keys some other surface takes first — see
    /// ``BoardKeyboard/menuOwnedShortcuts``. A shortcut in it matches nothing,
    /// so two surfaces cannot both answer to one key.
    static func command(
        key: KeyEquivalent, modifiers: EventModifiers, among candidates: [AppCommand],
        excluding claimed: Set<AppShortcut> = []
    ) -> AppCommand? {
        let held = modifiers.intersection([.command, .shift, .option, .control])
        return candidates.first { command in
            command.shortcuts.contains { shortcut in
                !claimed.contains(shortcut)
                    && shortcut.key.keyEquivalent == key
                    && shortcut.modifiers.eventModifiers == held
            }
        }
    }

    static func command(
        for press: KeyPress, among candidates: [AppCommand], excluding claimed: Set<AppShortcut> = []
    ) -> AppCommand? {
        command(key: press.key, modifiers: press.modifiers, among: candidates, excluding: claimed)
    }
}

/// What a key press does to a card, held apart from the view that receives it.
///
/// Every line of this used to be a `private func` on a `View`, where the four
/// behaviours the phase is *about* — ⌥← calling `move`, ⏎ opening the detail
/// surface, Space toggling, focus following a deleted card — could not be
/// asked a question by anything but a person with a keyboard. Four one-line
/// mutants inside it survived the whole suite.
///
/// The store is `@MainActor`, so the doing is too; the vocabulary either side
/// of it is `nonisolated` so the matching can be read from anywhere.
enum BoardKeyboard {
    /// Whether a card took the key, and which card has the keyboard afterwards.
    struct Outcome: Equatable {
        /// A refusal — ← at the leftmost column — is *not* handled, so the
        /// scroll view still gets the key.
        var isHandled: Bool
        /// Where focus is once the command has run. The card that had it,
        /// unless the command moved it or took the card away.
        var focus: TaskItem.ID?
    }

    /// The keys the menu bar takes before any view sees them.
    ///
    /// A menu key equivalent is dispatched from `NSApplication.sendEvent`
    /// before the responder chain is offered the event, so a card claiming ⌘⌫
    /// or ⌘⏎ is claiming a key it never receives — two owners on paper and one
    /// in fact. Derived from what the menu actually declares (its first key per
    /// item), so a shortcut added to a menu item cannot silently start
    /// shadowing a card's.
    ///
    /// Still empty on iOS, and the reason is now the interesting one. The iPad
    /// **does** draw this app's menu bar — `BoardCommands` is declared into both
    /// scenes — so the old premise ("there is no menu there") has gone; what is
    /// left is the dispatch order, which is the other way round. UIKit offers a
    /// key press to the responder chain first and reaches the menu at the end of
    /// it, where AppKit dispatches a menu key equivalent out of
    /// `NSApplication.sendEvent` before any view is asked. So on the desk the
    /// card must stand aside for ⌘⌫ and ⌘⏎, and on the iPad the card answers
    /// first and the menu item is what catches the press when nothing has focus
    /// — which is the same act on the same cards either way, because the menu
    /// aims at exactly the focused card. Excluding them on iOS is what left both
    /// keys handled by nobody at all.
    ///
    /// The desk's list is derived from what the menu actually declares on the
    /// desk, so an item added there cannot silently start shadowing a card's key.
    ///
    /// **``AppCommand/menuPress``, not the first of `shortcuts`.** The two were
    /// the same thing until an item was drawn without the key its command
    /// carries: Open Task is ↩ on a focused card and an item with no key at all,
    /// because ↩ on a menu would be taken out of every text field in the app.
    /// Read off `shortcuts` this set would hold ↩ — and the card would stand
    /// aside for a menu item that never receives it, leaving the key handled by
    /// nobody, which is the same fault the iOS branch below is written to avoid.
    nonisolated static let menuOwnedShortcuts: Set<AppShortcut> = {
        #if os(macOS)
        Set(AppCommand.allCases.filter { $0.isMenuItem(on: .current) }.compactMap(\.menuPress))
        #else
        []
        #endif
    }()

    /// The four commands that only mean anything where there are columns. The
    /// flat surfaces drop them: there is nothing to move focus across and
    /// nowhere to move a card to.
    nonisolated static let columnCommands: Set<AppCommand> = [
        .focusPreviousColumn, .focusNextColumn, .moveCardLeft, .moveCardRight,
    ]

    /// What a focused board card answers to. Copy and paste are not here: they
    /// are the Edit menu's own items, made live by `copyable` and
    /// `pasteDestination`, which is what keeps ⌘C working in every text field
    /// in the app.
    ///
    /// `trashTask` is listed because the card knows how to perform it and can
    /// be asked to, not because it answers to ⌘⌫; that key and ⌘⏎ are the menu
    /// bar's, and ``command(for:among:)`` is what makes sure no card claims
    /// them. Space is `completeTask`'s other key and stays here.
    ///
    /// `nonisolated` because it is a vocabulary rather than view state, and
    /// `BoardKeyMatchTests` reads it from outside the main actor.
    nonisolated static let boardCommands: [AppCommand] = [
        .focusPreviousColumn, .focusNextColumn, .focusCardAbove, .focusCardBelow,
        .moveCardLeft, .moveCardRight, .openTask, .completeTask, .trashTask,
        .selectAll, .deselect,
    ]

    /// The same vocabulary on a flat surface, without the column moves. Derived
    /// rather than written out again, so a key added to the board arrives here
    /// too.
    nonisolated static let flatCommands: [AppCommand] =
        boardCommands.filter { !columnCommands.contains($0) }

    /// The key sets `onKeyPress` filters on, one per vocabulary — computed once
    /// rather than per card per render, because every visible card carries a
    /// `CardKeyboard` and the vocabularies never change.
    nonisolated static let boardKeys: Set<KeyEquivalent> =
        Set(boardCommands.flatMap { $0.shortcuts.map(\.key.keyEquivalent) })
    nonisolated static let flatKeys: Set<KeyEquivalent> =
        Set(flatCommands.flatMap { $0.shortcuts.map(\.key.keyEquivalent) })

    /// What a card asks of a key press: the command it means, out of the
    /// vocabulary that surface carries, less the keys the menu bar takes first.
    ///
    /// The **one** call a card makes, rather than every card passing
    /// ``menuOwnedShortcuts`` to the matcher itself. An exclusion supplied at
    /// the call site is one an edit can drop, and dropping it puts two owners
    /// back on ⌘⌫ and ⌘⏎ without changing a line of what either owner does —
    /// which is exactly the shape of defect nothing notices until a key stops
    /// working. There is no argument here to leave off.
    nonisolated static func command(
        key: KeyEquivalent, modifiers: EventModifiers, among commands: [AppCommand]
    ) -> AppCommand? {
        AppCommand.command(
            key: key, modifiers: modifiers, among: commands, excluding: menuOwnedShortcuts
        )
    }

    nonisolated static func command(for press: KeyPress, among commands: [AppCommand]) -> AppCommand? {
        command(key: press.key, modifiers: press.modifiers, among: commands)
    }

    /// Whether focus arriving on a card should bring the selection with it.
    ///
    /// It should, nearly always: every focus move in ``perform(_:on:in:map:today:)``
    /// selects what it lands on, because what the keyboard is on is what the
    /// inspector should be showing. The rule is stated here rather than only
    /// there because **focus does not only arrive by key** — AppKit moves the
    /// first responder on mouse *down*, through the responder chain, before any
    /// `Button` has fired.
    ///
    /// Which is the defect this answers. Selecting in the card's own action
    /// left the two rings driven by two different events half a click apart:
    /// the focus ring on the card being pressed and the selection ring still on
    /// the last one, for as long as the mouse was held. A **drag** never
    /// completes that action at all, so the two never came back together — the
    /// card being carried wore one ring and the card left behind wore the
    /// other, until some later click happened to land.
    ///
    /// Two of the three answers are still "leave the selection alone", and both
    /// are cases where the user is working *with* a selection rather than
    /// moving through one. `held` is ⌘ or ⇧: those mean "as well as what is
    /// already picked", and collapsing onto this card on mouse down would throw
    /// that away before the click meaning to add to it had been delivered. A
    /// card already *in* the selection is the same judgement from the other
    /// side — reaching it with the keyboard, or picking it up to drag, is not a
    /// decision to drop the rest.
    nonisolated static func selectionFollows(
        focusOnto id: TaskItem.ID, selection: Set<TaskItem.ID>, held: CardClick
    ) -> Bool {
        held == .none && !selection.contains(id)
    }

    /// Performs one command against the card that has the keyboard.
    ///
    /// `map` is what the surface is drawing — the board's columns, or a flat
    /// list's single column — and is what decides where a card may go and where
    /// focus lands after it.
    @MainActor
    static func perform(
        _ command: AppCommand,
        on task: TaskItem,
        in store: BoardStore,
        map: BoardFocusMap,
        today: CalendarDay
    ) -> Outcome {
        func stay(_ isHandled: Bool) -> Outcome { Outcome(isHandled: isHandled, focus: task.id) }

        func moveFocus(to id: TaskItem.ID?) -> Outcome {
            guard let id else { return stay(false) }
            // Focus is how the board is read as well as driven: what the
            // keyboard is on is what the inspector should be showing.
            store.select(id)
            return Outcome(isHandled: true, focus: id)
        }

        // ⌥←/→. The whole selection when this card is part of it, which is the
        // rule every other command here follows, and focus stays on the card so
        // a run of ⌥→ walks it across the board.
        func moveCard(by step: Int) -> Outcome {
            guard let target = map.column(task.id, by: step) else { return stay(false) }
            store.move(store.commandTargets(task.id), to: target)
            return stay(true)
        }

        switch command {
        case .focusCardAbove: return moveFocus(to: map.card(task.id, movedBy: -1))
        case .focusCardBelow: return moveFocus(to: map.card(task.id, movedBy: 1))
        case .focusPreviousColumn: return moveFocus(to: map.card(task.id, inColumnBy: -1))
        case .focusNextColumn: return moveFocus(to: map.card(task.id, inColumnBy: 1))
        case .moveCardLeft: return moveCard(by: -1)
        case .moveCardRight: return moveCard(by: 1)
        case .openTask:
            store.select(task.id)
            store.isInspectorOpen = true
            return stay(true)
        case .completeTask:
            // Space and ⌘⏎. One card toggles, because that is what the tick
            // beside it does and Space is the same gesture; several complete,
            // because "reopen three of these and complete the other two" is not
            // a thing one key means.
            let targets = store.commandTargets(task.id)
            if targets.count == 1, store.isDone(task) {
                store.reopen(task.id)
            } else {
                store.complete(targets)
            }
            return stay(true)
        case .trashTask:
            // Worked out before the delete, while the card is still on the
            // surface to have a neighbour — and past the rest of the
            // selection, which is leaving with it. See
            // `BoardFocusMap.card(after:skipping:)`.
            let targets = store.commandTargets(task.id)
            let next = map.card(after: task.id, skipping: targets)
            store.trashTasks(targets)
            return Outcome(isHandled: true, focus: next)
        case .selectAll:
            store.selectAllVisible(today: today)
            return stay(true)
        case .deselect:
            store.clearSelection()
            return stay(true)
        default:
            return stay(false)
        }
    }

    /// What ⌘C puts on the pasteboard: the selection when this card is in it,
    /// this card alone otherwise. `TaskTransfer` carries the board's own type
    /// *and* `NW-118 Drag-and-drop between columns`, so the same copy pastes
    /// back as a card here and as a line of text into a commit message.
    @MainActor
    static func copyPayload(for task: TaskItem, in store: BoardStore) -> [TaskTransfer] {
        // More than one target can only be the selection, which the store
        // already hands back in board order.
        guard store.commandTargets(task.id).count > 1 else { return [TaskTransfer(task)] }
        return store.selectedTasks.map(TaskTransfer.init)
    }

    /// ⌘V. Plain text becomes cards where the focused card lives — one per
    /// line, so a list pasted out of a note arrives as a list, and all of them
    /// in one undoable step because one act of the user's is one ⌘Z.
    ///
    /// An archived card is not a destination: its placement is the column it
    /// left, and a card appearing on a board the user is not looking at is a
    /// paste that did nothing as far as they can see.
    @MainActor
    static func paste(_ strings: [String], onto task: TaskItem, in store: BoardStore) {
        guard !task.isArchived else { return }
        let titles = pastedTitles(strings)
        guard !titles.isEmpty else { return }
        store.addTasks(to: task.placement, titles: titles)
    }

    /// The titles a paste makes cards from: a line each, blanks dropped.
    nonisolated static func pastedTitles(_ strings: [String]) -> [String] {
        strings
            .flatMap { $0.split(whereSeparator: \.isNewline) }
            .map { title(fromPastedLine: $0) }
            .filter { !$0.isEmpty }
    }

    /// One pasted line as a title, with a leading task code taken off: text
    /// copied out of this app comes back as "NW-118 Drag-and-drop between
    /// columns", and a new card carrying another card's code in its title would
    /// be lying about which task it is.
    ///
    /// A code has a letter in it — `NW-118`, `IN-147`, `AL-140` — which is what
    /// separates one from a date. `2024-01 Review the quarter` used to arrive
    /// as `Review the quarter`, its date silently eaten.
    nonisolated static func title(fromPastedLine line: some StringProtocol) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(where: \.isWhitespace) else { return trimmed }
        let code = trimmed[..<space]
        guard code.contains(where: \.isLetter),
              code.wholeMatch(of: /[A-Z0-9]{1,4}-[0-9]+/) != nil
        else { return trimmed }
        return String(trimmed[space...]).trimmingCharacters(in: .whitespaces)
    }
}

/// Where a board surface publishes what its keyboard is on, for the things that
/// have to ask from outside its view tree.
///
/// On macOS that is the menu bar: ⌘⌫ and ⌘⏎ are *its* keys, an item on it wins
/// a press before any view sees the event, so it has to be able to name the
/// card the press was aimed at. `MacRootView` mirrors this onto
/// `AppWindowState`, which is where the menu reads it — the shared board would
/// otherwise have to know what a window is, and a phone has neither.
@MainActor
@Observable
final class BoardFocusRelay {
    /// The card the keyboard is on. Written by whichever card takes focus, and
    /// read back the other way: the menu names the neighbour of a card it
    /// deleted, and the card it names has to take the keyboard.
    var focusedTaskID: TaskItem.ID?

    /// The column that card is in, which is where ⌘N adds. On a board scrolled
    /// right the leftmost column is not where the user is looking.
    var focusedColumnID: BoardColumn.ID?

    /// The card to bring into view, and how far to go about it.
    ///
    /// Separate from `focusedTaskID`, which every route writes and which is
    /// read for other reasons: what the board does about focus arriving depends
    /// on *how* it arrived, and only the route that moved it knows that.
    ///
    /// Raised rather than cleared, and read on change: two scroll views watch
    /// it — the column, which brings the card up vertically, and the strip,
    /// which brings its column across — and a one-shot either of them consumed
    /// would leave the other with nothing.
    var reveal: BoardReveal?
}

/// A request to bring a card into view, and how much of the board to move doing
/// it.
///
/// The distinction is the whole of it. A **key** can put focus on a card in a
/// column that is entirely off screen — arrowing onto something invisible is
/// arrowing into nothing — so it asks for the card in the middle, where there
/// is board on both sides to carry on arrowing through. A **click** has already
/// landed on a card the user could see, so scrolling to centre it moved the
/// board out from under the pointer at the moment it was being aimed: the most
/// a click may ask for is that the column it landed in be shown *whole*, and
/// for a column that is whole already, nothing at all.
struct BoardReveal: Equatable {
    enum Manner: Equatable {
        /// Just inside the edge, and no further. Nothing happens when the
        /// target is on screen entire.
        case intoView
        /// In the middle of what is on screen.
        case centred
    }

    var task: TaskItem.ID
    var manner: Manner

    static func intoView(_ task: TaskItem.ID) -> BoardReveal {
        BoardReveal(task: task, manner: .intoView)
    }

    static func centred(_ task: TaskItem.ID) -> BoardReveal {
        BoardReveal(task: task, manner: .centred)
    }
}

/// A board card that the keyboard can reach: focusable, and carrying the keys
/// that move focus around the board and the card around the columns.
///
/// Wrapped around ``BoardTaskCard`` rather than folded into it because the flat
/// lists draw the same card with a smaller vocabulary — see ``ListCard`` — and
/// a preview draws it with none.
struct BoardCard: View {
    let task: TaskItem
    var metrics: BoardTaskCard.Metrics = .desk
    @FocusState.Binding var focus: TaskItem.ID?

    var body: some View {
        // `isFocused` is passed in rather than read inside the card: see
        // `BoardTaskCard.isFocused`. `@FocusState.Binding` here is a dynamic
        // property, so this both reads the live value and redraws on it.
        BoardTaskCard(task: task, metrics: metrics, isFocused: focus == task.id, focus: $focus)
            .modifier(CardKeyboard(
                task: task, commands: BoardKeyboard.boardCommands, surface: .board, focus: $focus
            ))
    }
}

/// The same card on a flat surface — the Inbox, a saved view, the Archive —
/// with the same keys less the four that need columns.
///
/// These surfaces had no keyboard at all: ⌘A, ⌘C, ⌘V, ⎋ and the arrows were
/// dead on three of the four places a card is drawn, while the shortcuts sheet
/// advertised every one of them without qualification.
struct ListCard: View {
    let task: TaskItem
    var showsColumn: Bool = true
    var metrics: BoardTaskCard.Metrics = .desk
    @FocusState.Binding var focus: TaskItem.ID?

    var body: some View {
        BoardTaskCard(
            task: task, metrics: metrics, showsColumn: showsColumn,
            isFocused: focus == task.id, focus: $focus
        )
        .modifier(CardKeyboard(
            task: task, commands: BoardKeyboard.flatCommands, surface: .flat, focus: $focus
        ))
    }
}

/// The keyboard's half of a card: focusable, the keys the surface answers to,
/// and the pasteboard.
///
/// One modifier for both surfaces so the board's cards and the flat lists' rows
/// cannot drift apart — the drift is what put ⌘C on the board and nowhere else.
private struct CardKeyboard: ViewModifier {
    /// Which surface the card is on, which is the whole of the difference
    /// between them: one has columns and the other has a single list of rows.
    enum Surface { case board, flat }

    @Environment(BoardStore.self) private var store
    @Environment(\.dayClock) private var dayClock
    /// Optional because not every surface has anything outside it to tell: a
    /// test harness, a preview and the iPad all stand this up without one.
    @Environment(BoardFocusRelay.self) private var relay: BoardFocusRelay?
    /// Whether this card is a row of the Inbox panel — the panel sets it, the
    /// same fact `BoardTaskCard` reads to pick its drag rule. The keyboard
    /// needs it because the panel is its own list: see `map`.
    @Environment(\.isInboxList) private var isInboxList

    let task: TaskItem
    let commands: [AppCommand]
    let surface: Surface
    @FocusState.Binding var focus: TaskItem.ID?

    private var hasFocus: Bool { focus == task.id }

    /// Which key presses reach the handler at all. Modifier-blind, so ⌘⏎ still
    /// arrives and is turned away by the matcher rather than never offered.
    /// The two vocabularies' sets are precomputed — see `boardKeys`.
    private var keys: Set<KeyEquivalent> {
        switch surface {
        case .board: BoardKeyboard.boardKeys
        case .flat: BoardKeyboard.flatKeys
        }
    }

    /// Rebuilt per press: the board changes under the keyboard, and a map held
    /// from the last press would move a card that is no longer there.
    ///
    /// **The Inbox panel's rows walk the panel and stop.** The flat
    /// every-visible-card order is right for ⌘A and wrong for an arrow: it
    /// stitches the panel to the board's columns, so ↓ on the last Inbox row
    /// walked focus into the board's first column — a card in another focus
    /// scope, which nothing there claims, while the relay stayed pointing at
    /// the row it had just left: the board scrolled to the new card and the
    /// menu bar's ⌘⌫ and ⌘⏎ kept acting on the old one. The end of the panel
    /// is the end of the walk, the way the end of a column is.
    private var map: BoardFocusMap {
        switch surface {
        case .board: BoardFocusMap(store)
        case .flat:
            isInboxList
                ? BoardFocusMap(flat: store.inboxTasks.map(\.id))
                : BoardFocusMap(flat: store.visibleTaskIDs(today: dayClock.today))
        }
    }

    func body(content: Content) -> some View {
        content
            .focusable()
            // The card draws its own ring, inset so it reads beside the
            // selection ring rather than instead of it.
            .focusEffectDisabled()
            .focused($focus, equals: task.id)
            .onKeyPress(keys: keys, phases: [.down, .repeat]) { press in
                guard let command = BoardKeyboard.command(for: press, among: commands)
                else { return .ignored }
                let outcome = BoardKeyboard.perform(
                    command, on: task, in: store, map: map, today: dayClock.today
                )
                focus = outcome.focus
                // The key moved it, so the card it landed on may be off the
                // bottom of its column or off the edge of the board.
                relay?.reveal = outcome.focus.map(BoardReveal.centred)
                // A refusal — ← at the leftmost column — is `ignored` rather
                // than handled, so the scroll view still gets the key.
                return outcome.isHandled ? .handled : .ignored
            }
            .modifier(CardPasteboard(task: task))
            // What the menu bar asks before it acts: ⌘⌫ and ⌘⏎ are its keys, so
            // it has to be able to see the card a press would otherwise have
            // been aimed at. Written by the card that takes focus rather than
            // by every card watching the relay — they all share it — and given
            // up again when that card leaves the tree, which is what a surface
            // change is.
            .onChange(of: hasFocus) { _, isMine in
                guard isMine else { return }
                relay?.focusedTaskID = task.id
                takeSelection()
            }
            // And back the other way, because the menu hands focus on as well
            // as reading it: ⌘⌫ names the neighbour of the card it deleted, and
            // the card it names has to take the keyboard or the surface is left
            // with none and the next arrow press goes nowhere.
            .onChange(of: relay?.focusedTaskID) { _, id in
                if id == task.id, !hasFocus {
                    focus = task.id
                    relay?.reveal = .centred(task.id)
                }
            }
            .onDisappear {
                if relay?.focusedTaskID == task.id { relay?.focusedTaskID = nil }
            }
    }

    /// The selection follows the keyboard onto this card — see
    /// ``BoardKeyboard/selectionFollows(focusOnto:selection:held:)``, which is
    /// where the rule and the reasons for it are.
    ///
    /// The modifier is read here, off `NSEvent`, because it is a fact about the
    /// moment focus arrived rather than about the card: the same read
    /// `BoardTaskCard.click()` makes, a beat later, to decide what the click
    /// itself meant.
    private func takeSelection() {
        guard BoardKeyboard.selectionFollows(
            focusOnto: task.id, selection: store.selection, held: CardClick.modifier
        ) else { return }
        store.select(task.id)
    }
}

/// ⌘C and ⌘V on a focused card.
///
/// Behind an availability check rather than a `#if`: `copyable` and
/// `pasteDestination` are macOS 13 but iOS **27**, and this app deploys to iOS
/// 26. An iPad running 26 keeps every other key on the card and goes without
/// these two; there is no earlier spelling of them that carries a `Transferable`
/// rather than a string.
private struct CardPasteboard: ViewModifier {
    @Environment(BoardStore.self) private var store

    let task: TaskItem

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        pasteboard(content)
        #else
        if #available(iOS 27.0, *) {
            pasteboard(content)
        } else {
            content
        }
        #endif
    }

    @available(iOS 27.0, macOS 13.0, *)
    private func pasteboard(_ content: Content) -> some View {
        content
            .copyable(BoardKeyboard.copyPayload(for: task, in: store))
            .pasteDestination(for: String.self) { BoardKeyboard.paste($0, onto: task, in: store) }
    }
}
