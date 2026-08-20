#if os(macOS)

import SwiftUI

/// The 66pt board header: title, search, new-task button, inspector toggle.
struct MacToolbar: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var body: some View {
        @Bindable var store = store

        HStack(spacing: 14) {
            Text("Northwind iOS 3.0")
                .font(SimpleKanbanFont.serif(24))
                .lineLimit(1)

            Spacer(minLength: 0)

            searchField
            newTaskButton
            inspectorToggle
        }
        .padding(.horizontal, 20)
        .frame(height: 66)
        .hairline(.bottom, color: palette.ink(0.07))
    }

    private var searchField: some View {
        @Bindable var store = store

        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink(0.45))
            TextField("Search tasks", text: $store.query)
                .textFieldStyle(.plain)
                .font(SimpleKanbanFont.ui(13, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 12)
        .frame(width: 216, height: 34)
        .background(palette.ink(0.05), in: .rect(cornerRadius: 10))
    }

    private var newTaskButton: some View {
        Button {
            store.beginAdding(in: BoardColumn.inbox.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("New task")
                    .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .subheadline))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(palette.accent, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.bare)
        .keyboardShortcut("n", modifiers: .command)
    }

    private var inspectorToggle: some View {
        Button {
            store.isInspectorOpen.toggle()
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(store.isInspectorOpen ? palette.ink : palette.ink(0.45))
                .frame(width: 34, height: 34)
                .background(store.isInspectorOpen ? palette.ink(0.07) : .clear, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(palette.ink(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.bare)
        .help("Toggle details sidebar")
        .accessibilityLabel("Toggle details sidebar")
        .keyboardShortcut("i", modifiers: [.command, .option])
    }
}

/// The 34pt footer strip.
struct MacStatusBar: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            Text("\(store.totalCount) tasks")
            Text("·")
            Text("Drag a card to move it between columns")
            Spacer(minLength: 0)
            Text("Synced just now")
        }
        .font(SimpleKanbanFont.ui(11, .semibold, relativeTo: .caption2))
        .foregroundStyle(palette.ink(0.4))
        .padding(.horizontal, 18)
        .frame(height: 34)
        .hairline(.top, color: palette.ink(0.07))
    }
}

#endif
