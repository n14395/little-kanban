#if os(macOS)

import AppKit
import SwiftUI

/// Seed task `t8` — "Menu bar quick-add on macOS — ⌃⌘N from anywhere drops a
/// task into Up Next" — as far as it is worth taking it.
///
/// **There is no system-wide hotkey, deliberately.** ⌃⌘N from *anywhere* needs
/// either a Carbon `RegisterEventHotKey` — a C callback, a global mutable
/// registration and an API Apple has been winding down for a decade — or the
/// Accessibility permission, which is a far larger thing to ask for than a text
/// field deserves and which a sandboxed, notarized build has to justify. What
/// ships instead is this extra, which is one click away from any app; ⌘N inside
/// the app, which already exists; and the `AddTaskIntent` in
/// `Sources/Model/TaskIntents.swift`, which the Shortcuts app *will* bind to a
/// system-wide key press for anyone who wants ⌃⌘N specifically. That last one is
/// the supported route to exactly the feature `t8` describes, and it costs no
/// permission at all.
struct MenuBarQuickAdd: Scene {
    let store: BoardStore

    /// Whether the status item is in the menu bar at all. On by default,
    /// because it is this app's one route in from another app; a setting
    /// because a menu bar is finite and not everybody spends theirs here.
    @AppStorage(Preferences.menuBarExtraKey) private var isShowing = true

    var body: some Scene {
        MenuBarExtra("Simple Kanban", systemImage: "checklist", isInserted: $isShowing) {
            MenuBarQuickAddView()
                .environment(store)
        }
        // A field needs a window; the default `.menu` style would draw the
        // whole thing as menu items and swallow the keystrokes.
        .menuBarExtraStyle(.window)
    }
}

/// The panel itself: one field, one destination, and the two lines of feedback
/// that make it usable without opening the app.
private struct MenuBarQuickAddView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BoardStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    /// Where a capture goes, remembered across launches. The Inbox by default:
    /// `t8` named Up Next, but the global Inbox did not exist when it was
    /// written, and a capture made from another app is exactly the case the
    /// Inbox is for — deciding which board it belongs on is the thing the user
    /// is deferring by capturing at all. Anyone who wants Up Next picks it once.
    @AppStorage("SimpleKanbanQuickAddDestination") private var destinationID = ""
    @State private var draft = ""
    /// What the last capture made, so the panel can say the capture landed. It
    /// stays up rather than dismissing: capture is usually plural.
    @State private var lastAdded: String?
    @FocusState private var isFieldFocused: Bool

    private var palette: Palette {
        Palette(theme: store.theme(for: colorScheme.themeAppearance))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Add")
                .sectionLabelStyle(opacity: Palette.readableInk)

            TextField(text: $draft) {
                Text("Task title, then ⏎")
            }
            .textFieldStyle(.plain)
            .font(palette.ui(14, .medium, relativeTo: .body))
            .focused($isFieldFocused)
            .onSubmit(commit)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(palette.ink(0.05))
                    .strokeBorder(palette.ink(0.09))
            }

            HStack(spacing: 8) {
                destinationPicker
                Spacer(minLength: 0)
                Button("Add", action: commit)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedDraft.isEmpty)
            }

            Divider().overlay(palette.ink(0.08))

            HStack(spacing: 8) {
                Text(lastAdded ?? String(localized: "Captured tasks go to the board unopened.",
                                         comment: "Resting caption under the menu bar quick-add field"))
                    .font(palette.ui(11.5, .medium, relativeTo: .caption))
                    .foregroundStyle(palette.ink(lastAdded == nil ? 0.4 : 0.62))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    NSApp.activate()
                    openWindow(id: "board")
                } label: {
                    Text("Open Board")
                        .font(palette.ui(11.5, .semibold, relativeTo: .caption))
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bare)
                .hoverBackground(palette.ink(0.05), radius: 6)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(palette.panelSolid)
        .environment(\.palette, palette)
        .tint(palette.accent)
        .foregroundStyle(palette.ink)
        .focusWhenReady($isFieldFocused)
    }

    /// The Inbox and every column of every board, because the extra outlives
    /// whichever board the window happens to be showing.
    private var destinationPicker: some View {
        Picker(selection: $destinationID) {
            Text(Board.inboxName).tag("")
            ForEach(store.boards) { board in
                Section(board.name) {
                    ForEach(board.columns) { column in
                        Text(column.name).tag(column.id.uuidString)
                    }
                }
            }
        } label: {
            Text("Add to")
        }
        .labelsHidden()
        .font(palette.ui(12, .medium, relativeTo: .caption))
        .fixedSize()
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `.captured` rather than `.created`, so the activity feed says where the
    /// card came from — which is the entry that string was written for.
    private func commit() {
        let title = trimmedDraft
        guard !title.isEmpty else { return }
        let id = store.addTask(to: destination, title: title, log: .captured)
        draft = ""
        lastAdded = store[id].map { task in
            String(localized: "Added \(task.code) to \(placeName)",
                   comment: "Menu bar quick-add confirmation: a task code and where it went")
        }
        isFieldFocused = true
    }

    /// A remembered column that has since been deleted is not an error: the
    /// capture falls back to the Inbox, which is where a card with nowhere to be
    /// belongs anyway.
    private var destination: TaskPlacement {
        guard let id = UUID(uuidString: destinationID),
              let board = store.board(ofColumn: id)
        else { return .inbox }
        return .column(board: board.id, column: id)
    }

    private var placeName: String {
        guard let id = UUID(uuidString: destinationID),
              let column = store.column(id: id)
        else { return Board.inboxName }
        return column.name
    }
}

#endif

