import SwiftUI

/// The keyboard reference, from Help ▸ Keyboard Shortcuts (⌘/).
///
/// Every row is read out of ``AppCommand``, which is also what the menu bar
/// declares its items from and what the board matches key presses against. A
/// sheet that claims a shortcut the app does not have is worse than no sheet at
/// all, and this one cannot: there is one list, and this draws it.
///
/// Seed task `t12`, sitting in the Done column, is "Keyboard shortcuts sheet" —
/// the sample data has claimed this shipped since the first commit.
struct ShortcutsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    /// The groups with something to teach. `Set Due Date…` and its like have no
    /// key of their own and are named in the footer instead.
    private var groups: [AppCommandGroup] {
        AppCommand.groups.filter { !commands(in: $0).isEmpty }
    }

    /// This machine's rows, which is not the whole vocabulary: two commands
    /// exist on one platform only — see ``AppCommand/platforms`` — and a
    /// reference card that taught an iPad the desk's ⌘, or taught the desk a
    /// theme browser it opens some other way would be a card claiming a key the
    /// app in front of you does not have.
    private func commands(in group: AppCommandGroup) -> [AppCommand] {
        AppCommand.commands(in: group, on: .current).filter { !$0.shortcuts.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(groups) { section($0) }
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 560, minHeight: 620)
        .background(palette.windowFill)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Keyboard Shortcuts", comment: "Title of the macOS shortcuts reference")
                .font(palette.display(24))
                .foregroundStyle(palette.ink)

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Text("Done", comment: "Button that closes the shortcuts reference")
                    .font(palette.ui(12.5, .bold, relativeTo: .subheadline))
                    .foregroundStyle(palette.ink(0.65))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
            }
            .bareButton()
            .hoverBackground(palette.ink(0.06), radius: 9)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .frame(minHeight: 62)
        .hairline(.bottom, color: palette.ink(0.07))
    }

    private func section(_ group: AppCommandGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title).sectionLabelStyle(opacity: Palette.readableInk)
            VStack(spacing: 0) {
                ForEach(commands(in: group)) { row($0) }
            }
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.card)
                    .shadow(color: palette.shadow(0.05), radius: 1, y: 1)
            }
        }
    }

    private func row(_ command: AppCommand) -> some View {
        HStack(spacing: 12) {
            Text(command.title)
                .font(palette.ui(13, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)

            Spacer(minLength: 0)

            // Only completion has two — ⌘⏎ from the menu, Space on a card that
            // has the keyboard.
            HStack(spacing: 6) {
                ForEach(Array(command.shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    if index > 0 {
                        Text("or", comment: "Between two keys that do the same thing")
                            .font(palette.ui(11, .medium, relativeTo: .caption2))
                            .foregroundStyle(palette.inkText(0.4))
                    }
                    keycap(shortcut.display)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        // Every row but the last, so the group reads as one block.
        .hairline(.bottom, color: command == commands(in: command.group).last ? .clear : palette.ink(0.06))
        .accessibilityElement(children: .combine)
    }

    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(palette.ui(12, .bold, relativeTo: .footnote))
            .foregroundStyle(palette.ink(0.75))
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 24)
            .background(palette.ink(0.06), in: .rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(palette.ink(0.08), lineWidth: 1)
            }
    }

    /// What has no key. Read off the same list rather than written out, so a
    /// command that gains a shortcut leaves this sentence on its own.
    @ViewBuilder
    private var footer: some View {
        let here = AppCommand.allCases.filter { $0.platforms.contains(.current) }
        let menuOnly = here.filter { $0.shortcuts.isEmpty && $0.source == .app }
        let unbuilt = here.filter { $0.source == .unbuilt }
        // The four keys that need columns. The Inbox, the saved views and the
        // Archive draw the same cards and answer to the same keys less these,
        // and a reference that does not say so has promised ⌥← everywhere.
        let boardOnly = AppCommand.allCases
            .filter { BoardKeyboard.columnCommands.contains($0) }
            .compactMap { $0.shortcuts.first?.display }

        VStack(alignment: .leading, spacing: 6) {
            if !boardOnly.isEmpty {
                Text("On the board only, where there are columns: \(boardOnly.formatted(.list(type: .and)))",
                     comment: "Shortcuts sheet footer naming the keys the flat lists do not answer to")
            }
            if !menuOnly.isEmpty {
                Text("In the menus, without a key: \(list(menuOnly))",
                     comment: "Shortcuts sheet footer naming the commands that have no shortcut")
            }
            if !unbuilt.isEmpty {
                Text("Not built yet: \(list(unbuilt))",
                     comment: "Shortcuts sheet footer naming the menu items that are drawn disabled")
            }
        }
        .font(palette.ui(11.5, .medium, relativeTo: .caption))
        .foregroundStyle(palette.inkText(0.45))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func list(_ commands: [AppCommand]) -> String {
        commands.map(\.title).formatted(.list(type: .and))
    }
}
