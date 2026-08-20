#if os(macOS)

import SwiftUI

/// One 272pt board column: header, inline composer, and its cards.
struct MacColumnView: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store
    @FocusState private var isComposerFocused: Bool

    let column: BoardColumn
    /// Inbox is fenced off from the workflow columns by a vertical rule.
    var showsLeadingRule: Bool = false

    private var tasks: [TaskItem] { store.visibleTasks(in: column.id) }
    private var isDropTarget: Bool { store.dropTargetColumnID == column.id && store.draggingID != nil }
    private var isComposing: Bool { store.addingColumnID == column.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            cards
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(width: 272)
        .background(
            isDropTarget ? palette.accent.opacity(0.07) : palette.ink(0.035),
            in: .rect(cornerRadius: 16)
        )
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(palette.accent, lineWidth: 2)
            }
        }
        .overlay(alignment: .leading) {
            if showsLeadingRule {
                Rectangle()
                    .fill(palette.ink(0.14))
                    .frame(width: 1)
                    .padding(.vertical, 2)
                    .offset(x: -14)
            }
        }
        .padding(.leading, showsLeadingRule ? 14 : 0)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first, store[dragged] != nil else { return false }
            store.move(dragged, to: column.id)
            return true
        } isTargeted: { targeted in
            if targeted {
                store.dropTargetColumnID = column.id
            } else if store.dropTargetColumnID == column.id {
                store.dropTargetColumnID = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(palette.resolve(column.dot))
                .frame(width: 8, height: 8)

            Text(column.name)
                .font(SimpleKanbanFont.ui(12.5, .extraBold, relativeTo: .footnote))
                .tracking(12.5 * 0.02)
                .foregroundStyle(palette.ink)

            CountPill(count: tasks.count)

            Spacer(minLength: 0)

            Button {
                store.beginAdding(in: column.id)
                isComposerFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.ink(0.45))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bare)
            .hoverBackground(palette.ink(0.08), radius: 7)
            .accessibilityLabel("Add task to \(column.name)")
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private var cards: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if isComposing { composer }
                ForEach(tasks) { task in
                    MacTaskCard(task: task)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minHeight: 40)
    }

    private var composer: some View {
        @Bindable var store = store

        return TextField("Task title, then ⏎", text: $store.draft)
            .textFieldStyle(.plain)
            .font(SimpleKanbanFont.ui(13.5, .bold, relativeTo: .subheadline))
            .foregroundStyle(palette.ink)
            .focused($isComposerFocused)
            .onSubmit { store.commitDraft() }
            .onKeyPress(.escape) {
                store.cancelDraft()
                return .handled
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.card)
                    .shadow(color: palette.shadow(0.1), radius: 1, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(palette.accent.opacity(0.35), lineWidth: 2)
            }
            .onAppear { isComposerFocused = true }
    }
}

/// The horizontally scrolling column strip.
struct MacBoardView: View {
    @Environment(BoardStore.self) private var store

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(BoardColumn.all.enumerated()), id: \.element.id) { index, column in
                    MacColumnView(column: column, showsLeadingRule: index == 1)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#endif
