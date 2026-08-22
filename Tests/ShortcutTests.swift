import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

/// The one shortcut vocabulary, read the way the three surfaces that consume it
/// read it: the menu bar declares items from it, the board matches key presses
/// against it, and the shortcuts sheet prints it.
///
/// Nothing here can be checked by looking at the app — a shortcut that two
/// commands claim simply never fires for one of them, silently, and only on the
/// build where AppKit happens to resolve it the other way. That is exactly the
/// kind of drift a single vocabulary exists to prevent and a test is the only
/// thing that notices.
@Suite struct ShortcutVocabularyTests {
    /// What AppKit actually dispatches on: the character SwiftUI is handed and
    /// the modifier mask beside it. Deliberately not `AppShortcut`'s own
    /// `Hashable` — two differently spelled `AppKey`s can reach the same key,
    /// and it is the key that collides, not the spelling.
    ///
    /// The character is folded to lower case for the same reason: ⇧N and ⇧n are
    /// one press, so declaring both would be declaring one twice.
    private struct Press: Hashable {
        var character: String
        var modifiers: Int

        init(_ shortcut: AppShortcut) {
            let resolved = shortcut.keyboardShortcut
            character = String(resolved.key.character).lowercased()
            modifiers = resolved.modifiers.rawValue
        }
    }

    @Test func noTwoCommandsClaimThePressTheSystemWillDispatch() {
        var owner: [Press: AppCommand] = [:]
        for command in AppCommand.allCases {
            for shortcut in command.shortcuts {
                let press = Press(shortcut)
                #expect(owner[press] == nil,
                        "\(command.rawValue) and \(owner[press]?.rawValue ?? "—") both claim \(shortcut.display)")
                owner[press] = command
            }
        }
    }

    /// Every command names itself, in title case, in words rather than in the
    /// enum's spelling — these strings go straight onto the menu bar.
    @Test func everyCommandHasATitleOfItsOwn() {
        var seen: Set<String> = []
        for command in AppCommand.allCases {
            let title = command.title
            #expect(!title.isEmpty, "\(command.rawValue) has no title")
            #expect(title != command.rawValue, "\(command.rawValue) is showing its raw value")
            #expect(title.first?.isUppercase == true, "\(command.rawValue) is not title case")
            // Two items reading the same in one menu is a defect wherever it
            // lands, so the whole vocabulary is checked rather than each menu.
            #expect(!seen.contains(title), "two commands are both called “\(title)”")
            seen.insert(title)
        }
    }

    /// The commands with no key of their own, named — so adding one is a
    /// decision rather than an omission. Two open submenus, one opens a picker,
    /// one is a Task-menu item nobody has claimed a key for, and Import… and
    /// Export… open panels the user then has to answer anyway.
    @Test func theCommandsWithoutAKeyAreTheOnesWeChose() {
        let keyless = Set(AppCommand.allCases.filter(\.shortcuts.isEmpty))
        #expect(keyless == [.moveToColumn, .setPriority, .setDueDate, .archiveTask,
                            .importBoard, .exportBoard])
        // And everything else has a key that SwiftUI can be handed.
        for command in AppCommand.allCases where !keyless.contains(command) {
            #expect(command.keyboardShortcut != nil, "\(command.rawValue) has no key equivalent")
            #expect(command.keyboardShortcut?.key.character == command.shortcuts.first?.key.keyEquivalent.character)
        }
    }

    /// A command that does not work yet must not hold a key hostage: the press
    /// would land on a disabled item and do nothing, and the key could not then
    /// be given to anything that does work.
    ///
    /// Vacuous while nothing is unbuilt — Import… and Export… were the last two
    /// and are wired — and kept for the next one rather than deleted, which is
    /// what `theSheetsThreeListsCoverTheWholeVocabularyBetweenThem` pins.
    @Test func anUnbuiltCommandClaimsNoKey() {
        for command in AppCommand.allCases where command.source == .unbuilt {
            #expect(command.shortcuts.isEmpty, "\(command.rawValue) claims a key it cannot honour")
            // Still a menu item, drawn disabled — the gap is meant to be visible.
            #expect(command.isMenuItem)
        }
    }

    /// Item 1.9, settled: ⌘N used to sit on a toolbar button while SwiftUI's own
    /// File menu went on advertising ⌘N as New Window, so the menu and the key
    /// disagreed about what the app did.
    @Test func theNewKeysAreTheOnesTheFileMenuAdvertises() {
        #expect(AppCommand.newTask.shortcuts == [AppShortcut("n", .command)])
        #expect(AppCommand.newBoard.shortcuts == [AppShortcut("n", [.command, .shift])])
        #expect(AppCommand.newTask.shortcuts.first?.display == "⌘N")
        #expect(AppCommand.newBoard.shortcuts.first?.display == "⇧⌘N")

        // And nothing else answers to either press.
        #expect(AppCommand.allCases.filter { $0.shortcuts.contains(AppShortcut("n", .command)) } == [.newTask])
        #expect(AppCommand.allCases.filter { $0.shortcuts.contains(AppShortcut("n", [.command, .shift])) } == [.newBoard])

        // Both on the File menu, and both declared by the app: `.newItem` is
        // replaced, so if these two were not menu items the menu would have
        // nothing where New Window used to be.
        #expect(Array(AppCommand.commands(in: .file).prefix(2)) == [.newTask, .newBoard])
        #expect(AppCommand.newTask.isMenuItem)
        #expect(AppCommand.newBoard.isMenuItem)
    }

    /// `UndoManager` puts Undo and Redo on the Edit menu itself. Declaring them
    /// again would put two of each there — and the app's copy would be the one
    /// that did nothing.
    @Test func theSystemsOwnItemsAreListedButNotDeclared() {
        let system = AppCommand.allCases.filter { $0.source == .system }
        #expect(Set(system) == [.undo, .redo])
        for command in system {
            #expect(command.isMenuItem == false, "\(command.rawValue) would be declared twice")
            // Listed, because a user pressing ⌘Z expects to find it in the sheet.
            #expect(AppCommand.commands(in: command.group).contains(command))
            #expect(command.shortcuts.isEmpty == false)
        }
    }

    /// ⌘C, ⌘V and ⌘A on the Edit menu take those keys away from every text
    /// field in the app — a menu item wins over the responder chain. They are
    /// handled where the board has focus and taught by the sheet instead.
    @Test func theBoardsOwnKeysGetNoMenuItem() {
        #expect(AppCommandGroup.board.hasMenu == false)
        for command in AppCommand.commands(in: .board) {
            #expect(command.isMenuItem == false, "\(command.rawValue) would shadow a text field")
        }
        #expect(AppCommand.commands(in: .board).contains(.copyTask))
        #expect(AppCommand.commands(in: .board).contains(.selectAll))
        // Every group that does have a menu declares at least one item into it,
        // or the menu bar would draw an empty menu.
        for group in AppCommandGroup.allCases where group.hasMenu {
            let declared = AppCommand.commands(in: group).filter(\.isMenuItem)
            #expect(!declared.isEmpty, "\(group.rawValue) would draw an empty menu")
        }
    }

    /// A menu item that acts on a task disables with nothing selected rather
    /// than no-opping: from the outside a command that does nothing is a broken
    /// one.
    @Test func everyCommandThatActsOnATaskSaysItNeedsOne() {
        #expect(Set(AppCommand.allCases.filter(\.needsSelection))
                == [.deleteTask, .completeTask, .moveToColumn, .setPriority, .setDueDate,
                    .archiveTask, .copyTask, .deselect, .openTask, .moveCardLeft, .moveCardRight])

        // Acting on the whole selection without needing one is incoherent.
        for command in AppCommand.allCases where command.actsOnWholeSelection {
            #expect(command.needsSelection, "\(command.rawValue) acts on a selection it does not require")
        }
        // And the commands that make something new, or that only move focus
        // about, must stay live on an empty board.
        for command in [AppCommand.newTask, .newBoard, .pasteTask, .selectAll, .find,
                        .toggleInspector, .toggleSidebar, .shortcuts,
                        .focusPreviousColumn, .focusNextColumn, .focusCardAbove, .focusCardBelow] {
            #expect(command.needsSelection == false, "\(command.rawValue) would disable with nothing selected")
        }
    }

    /// A menu item aimed at three cards has to say so, rather than promising to
    /// delete one and taking all three.
    @Test func aBulkCommandSaysHowManyCardsItIsAimedAt() {
        #expect(AppCommand.deleteTask.title(selectionCount: 0) == "Delete Task")
        #expect(AppCommand.deleteTask.title(selectionCount: 1) == "Delete Task")
        #expect(AppCommand.deleteTask.title(selectionCount: 3) == "Delete 3 Tasks")
        #expect(AppCommand.completeTask.title(selectionCount: 2) == "Complete 2 Tasks")
        #expect(AppCommand.archiveTask.title(selectionCount: 2) == "Archive 2 Tasks")
        #expect(AppCommand.copyTask.title(selectionCount: 2) == "Copy 2 Tasks")

        // A submenu and a picker read the same whatever they are aimed at, and
        // a command that never acts on more than one ignores the count.
        for command in AppCommand.allCases where !command.actsOnWholeSelection {
            #expect(command.title(selectionCount: 4) == command.title, "\(command.rawValue) grew a plural")
        }
    }

    /// What `AppKey` exists for. `KeyEquivalent.leftArrow` is U+F702, a
    /// private-use code point: printed straight into a sheet it renders as
    /// nothing at all, and the row reads "⌥" with a blank beside it.
    @Test func noShortcutPrintsAGlyphThatRendersAsNothing() {
        for command in AppCommand.allCases {
            for shortcut in command.shortcuts {
                #expect(!shortcut.display.isEmpty, "\(command.rawValue) prints nothing")
                let privateUse = shortcut.display.unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) }
                #expect(!privateUse, "\(command.rawValue) prints a private-use glyph for \(command.title)")
            }
        }
        #expect(AppCommand.moveCardLeft.shortcuts.first?.display == "⌥←")
        #expect(AppCommand.focusCardBelow.shortcuts.first?.display == "↓")
        #expect(AppCommand.deselect.shortcuts.first?.display == "⎋")
        #expect(AppCommand.deleteTask.shortcuts.first?.display == "⌘⌫")
    }

    /// Completion is the one command with two presses — ⌘⏎ from the menu, and
    /// Space on a card that has focus. The menu shows the first; a key handler
    /// matches either.
    @Test func aCommandMayCarryMorePressesThanTheMenuShows() {
        #expect(AppCommand.completeTask.shortcuts == [AppShortcut(.return, .command), AppShortcut(.space)])
        #expect(AppCommand.completeTask.keyboardShortcut?.key.character == KeyEquivalent.return.character)
        #expect(AppCommand.completeTask.keyboardShortcut?.modifiers == .command)
        // Space is a board key, so nothing on a menu claims it on its own.
        #expect(AppCommand.allCases.filter { $0.shortcuts.contains(AppShortcut(.space)) } == [.completeTask])
    }

    @Test func modifiersPrintInTheOrderTheSystemWritesThem() {
        #expect(AppShortcut("i", [.command, .option]).display == "⌥⌘I")
        #expect(AppShortcut("s", [.command, .control]).display == "⌃⌘S")
        #expect(AppShortcut("z", [.command, .shift]).display == "⇧⌘Z")
        #expect(AppShortcut(.return, [.control, .option, .shift, .command]).display == "⌃⌥⇧⌘↩")
        #expect(AppModifiers([.command, .option]).eventModifiers == [.command, .option])
    }
}

/// The sheet and the menu bar cannot drift apart, because there is only one
/// list and both walk it.
///
/// Seed task `t12`, sitting in Done, is "Keyboard shortcuts sheet" — the sample
/// data has been claiming this shipped since the first commit. What makes it
/// worth shipping is that it is *true*: a reference card that lists a key the
/// menu does not have is worse than no reference card at all.
@Suite struct ShortcutReferenceTests {
    /// One row as either surface renders it: what it is called, and what it
    /// says the keys are.
    private struct Row: Hashable {
        var command: AppCommand
        var group: AppCommandGroup
        var title: String
        var keys: [String]

        init(_ command: AppCommand) {
            self.command = command
            group = command.group
            title = command.title
            keys = command.shortcuts.map(\.display)
        }
    }

    /// Every row the sheet prints: each group in order, and every command in it
    /// — including the ones the system declares and the ones only the board
    /// handles, which is the entire reason the sheet exists.
    private var sheet: [Row] { AppCommand.groups.flatMap { AppCommand.commands(in: $0).map(Row.init) } }

    /// Every row the menu bar declares: the groups that get a menu, and the
    /// commands in them the app declares itself.
    private var menu: [Row] {
        AppCommandGroup.allCases
            .filter(\.hasMenu)
            .flatMap { AppCommand.commands(in: $0).filter(\.isMenuItem).map(Row.init) }
    }

    /// The sheet lists the whole vocabulary, once each. A command that reached
    /// the enum — and so could reach a menu — cannot fail to reach the sheet.
    @Test func theSheetListsEveryCommandExactlyOnce() {
        #expect(Set(sheet.map(\.command)) == Set(AppCommand.allCases))
        #expect(sheet.count == AppCommand.allCases.count)
        #expect(AppCommand.groups == AppCommandGroup.allCases)
    }

    /// Every menu item is in the sheet, with the same name and the same keys —
    /// they are the same rows, built from the same properties.
    @Test func everyMenuItemIsInTheSheetSayingTheSameThing() {
        for row in menu {
            #expect(sheet.contains(row), "\(row.command.rawValue) reads differently on the menu and in the sheet")
        }
        #expect(Set(menu).isSubset(of: Set(sheet)))
    }

    /// And the difference between the two is exactly the three kinds of command
    /// that are listed but not declared: the board's own keys, and Undo/Redo,
    /// which the system puts on the Edit menu itself.
    @Test func theOnlyThingsInTheSheetButNotTheMenuAreTheOnesWeNamed() {
        let listedOnly = Set(sheet.map(\.command)).subtracting(menu.map(\.command))
        #expect(listedOnly == Set(AppCommand.commands(in: .board)).union([.undo, .redo]))
        for command in listedOnly {
            #expect(command.group == .board || command.source == .system)
        }
    }

    /// The inventory, pinned in menu order.
    ///
    /// `commands(in:)` filters `allCases`, so the order a menu draws is the
    /// order the cases are declared in — which makes reordering the enum a
    /// change to the menu bar, and one worth noticing. It also means a command
    /// added to the vocabulary has to be added here, which is the moment to ask
    /// which menu it belongs on and whether anything already owns its key.
    @Test func theVocabularyIsWhatWeThinkItIs() {
        #expect(AppCommand.commands(in: .file) == [.newTask, .newBoard, .importBoard, .exportBoard])
        #expect(AppCommand.commands(in: .edit) == [.undo, .redo, .deleteTask, .find])
        #expect(AppCommand.commands(in: .view) == [.toggleInspector, .toggleSidebar])
        #expect(AppCommand.commands(in: .task)
                == [.completeTask, .moveToColumn, .setPriority, .setDueDate, .archiveTask])
        #expect(AppCommand.commands(in: .board)
                == [.copyTask, .pasteTask, .selectAll, .deselect, .openTask,
                    .focusPreviousColumn, .focusNextColumn, .focusCardAbove, .focusCardBelow,
                    .moveCardLeft, .moveCardRight])
        #expect(AppCommand.commands(in: .help) == [.shortcuts])
    }

    /// The sheet draws a row per command that has a key and names the rest in a
    /// footnote: the menu-only items, and the two that are not built yet. Those
    /// three lists have to cover the vocabulary between them — a command that
    /// belongs to none of them is one the sheet silently leaves out, which is
    /// the drift in the direction a reader cannot see.
    ///
    /// Written as the sheet's own three predicates rather than by asking the
    /// view, which a test cannot render.
    @Test func theSheetsThreeListsCoverTheWholeVocabularyBetweenThem() {
        let rows = AppCommand.allCases.filter { !$0.shortcuts.isEmpty }
        let menuOnly = AppCommand.allCases.filter { $0.shortcuts.isEmpty && $0.source == .app }
        let unbuilt = AppCommand.allCases.filter { $0.source == .unbuilt }

        #expect(Set(rows).union(menuOnly).union(unbuilt) == Set(AppCommand.allCases))
        #expect(rows.count + menuOnly.count + unbuilt.count == AppCommand.allCases.count)
        #expect(Set(menuOnly) == [.moveToColumn, .setPriority, .setDueDate, .archiveTask,
                                  .importBoard, .exportBoard])
        #expect(unbuilt.isEmpty, "an unbuilt command is drawn disabled — say which, and why")
    }

    /// Each group heads a section of the sheet and names a menu, so each needs
    /// a name of its own.
    @Test func everyGroupNamesItself() {
        var seen: Set<String> = []
        for group in AppCommandGroup.allCases {
            #expect(!group.title.isEmpty)
            #expect(group.title != group.rawValue)
            #expect(!seen.contains(group.title))
            seen.insert(group.title)
        }
    }

    /// The submenus are anchors, not contents: the columns, priorities, saved
    /// views and boards under them come off the store and change as the user
    /// works. A vocabulary that named today's columns would be wrong the moment
    /// somebody renamed one.
    @Test func aSubmenuAnchorOpensRatherThanDoes() {
        #expect(Set(AppCommand.allCases.filter(\.opensSubmenu)) == [.moveToColumn, .setPriority])
        for command in AppCommand.allCases where command.opensSubmenu {
            #expect(command.shortcuts.isEmpty, "\(command.rawValue) opens a submenu and cannot take a key")
            #expect(command.isMenuItem)
        }
    }
}

#if os(macOS)

/// The menu bar itself, as against a model of it.
///
/// Everything above asks `AppCommand` what the menu *ought* to hold, which is
/// exactly the question `BoardCommands` can quietly stop answering: drop a block
/// out of the `.commands` body and ⌘F leaves the app without a single test
/// noticing. A vocabulary only prevents drift between the surfaces that read it,
/// and until now nothing was reading the menu.
///
/// Two halves. The vocabulary's own half — that every menu item is declared into
/// exactly one section — is asked of the enum. The other half is asked of
/// `BoardCommands.swift` as text, because a `Commands` body is a result builder
/// over opaque values with nothing to enumerate at runtime, there is no `NSMenu`
/// outside a running app and a test bundle cannot host one. `#filePath` finds
/// the file, so the check follows the tests into a scratch copy of the tree.
@Suite struct MenuDeclarationTests {
    /// Where each block of the menu bar is hung, which is the one thing not in
    /// `AppCommand` and cannot be: `.pasteboard` is a place on the Edit menu and
    /// `.sidebar` a place on View. The Task menu draws two blocks with a divider
    /// between them — filing a card away is not editing it.
    private static let placements: [(anchor: String, sections: [AppMenuSection])] = [
        ("CommandGroup(replacing: .newItem)", [.new]),
        ("CommandGroup(replacing: .importExport)", [.importExport]),
        ("CommandGroup(after: .pasteboard)", [.edit]),
        ("CommandGroup(after: .sidebar)", [.view]),
        ("CommandMenu(AppCommandGroup.task.title)", [.task, .filing]),
        ("CommandGroup(replacing: .help)", [.help]),
    ]

    /// The `.commands` body, comments stripped so a section named in prose is
    /// not mistaken for one the menu draws, and cut at the first `// MARK:` so
    /// the private helpers below it are not read as declarations.
    private static func body() throws -> String {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()    // Tests/
            .deletingLastPathComponent()    // the source tree
        let text = try String(
            contentsOf: root.appending(path: "Sources/App/BoardCommands.swift"), encoding: .utf8
        )
        let start = try #require(text.range(of: "var body: some Commands {"))
        let end = text.range(of: "// MARK:", range: start.upperBound..<text.endIndex)
        return text[start.upperBound..<(end?.lowerBound ?? text.endIndex)]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Every item the menu bar draws is declared into exactly one block of it,
    /// and every command that must stay off the menu bar declares no block at
    /// all — `UndoManager` puts Undo and Redo on the Edit menu itself, and an
    /// item for ⌘C, ⌘V or ⌘A takes that key from every text field in the app.
    @Test func everyMenuItemIsDeclaredIntoExactlyOneBlock() {
        let declared = AppMenuSection.allCases.flatMap(AppCommand.menuItems(in:))
        #expect(Set(declared) == Set(AppCommand.allCases.filter(\.isMenuItem)))
        #expect(declared.count == AppCommand.allCases.count(where: \.isMenuItem),
                "a command is drawn into two blocks of the menu bar")

        for command in AppCommand.allCases {
            #expect((command.menuSection != nil) == command.isMenuItem,
                    "\(command.rawValue) disagrees with itself about being a menu item")
        }
    }

    /// A block belongs to one menu, and the blocks of a menu hold that menu's
    /// items in the order the vocabulary lists them.
    @Test func theBlocksOfAMenuCoverThatMenusItemsInOrder() {
        for section in AppMenuSection.allCases {
            let items = AppCommand.menuItems(in: section)
            #expect(!items.isEmpty, "the \(section.rawValue) block would draw nothing")
            #expect(Set(items.map(\.group)).count == 1,
                    "the \(section.rawValue) block spans two menus")
        }

        for group in AppCommandGroup.allCases where group.hasMenu {
            let drawn = AppMenuSection.allCases
                .flatMap(AppCommand.menuItems(in:))
                .filter { $0.group == group }
            #expect(drawn == AppCommand.commands(in: group).filter(\.isMenuItem),
                    "the \(group.rawValue) menu and the vocabulary disagree about what is on it")
        }
    }

    /// And the body draws every block, once each, under the right anchor.
    /// Commenting one out — or hanging Edit's block off the View menu — fails
    /// here and nowhere else.
    @Test func theBodyDrawsEveryBlockOnceUnderTheAnchorItBelongsTo() throws {
        let body = try Self.body()
        #expect(Set(Self.placements.flatMap(\.sections)) == Set(AppMenuSection.allCases),
                "a block of the menu bar is hung nowhere")

        var cuts: [(index: String.Index, anchor: String, sections: [AppMenuSection])] = []
        for placement in Self.placements {
            #expect(body.components(separatedBy: placement.anchor).count == 2,
                    "\(placement.anchor) is not opened exactly once")
            if let range = body.range(of: placement.anchor) {
                cuts.append((range.upperBound, placement.anchor, placement.sections))
            }
        }
        cuts.sort { $0.index < $1.index }

        for (offset, cut) in cuts.enumerated() {
            let end = offset + 1 < cuts.count ? cuts[offset + 1].index : body.endIndex
            let block = body[cut.index..<end]
            let drawn = AppMenuSection.allCases.filter { block.contains("items(.\($0.rawValue))") }
            #expect(drawn == cut.sections,
                    "\(cut.anchor) draws \(drawn.map(\.rawValue)) rather than \(cut.sections.map(\.rawValue))")
        }

        // Once each across the whole body, so a block cannot be drawn twice
        // under two anchors and satisfy both.
        for section in AppMenuSection.allCases {
            #expect(body.components(separatedBy: "items(.\(section.rawValue))").count == 2,
                    "the \(section.rawValue) block is not drawn exactly once")
        }
    }
}

#endif
