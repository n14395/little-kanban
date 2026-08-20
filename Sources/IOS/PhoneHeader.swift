#if os(iOS)

import SwiftUI

/// Board title, drawer button, and — depending on the tab — either the search
/// field or the column chips.
struct PhoneHeader: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 12) {
                Button { store.isNavDrawerOpen = true } label: {
                    hamburger
                }
                .buttonStyle(.bare)
                .accessibilityLabel("Show boards")

                Text("Northwind iOS 3.0")
                    .font(SimpleKanbanFont.serif(30))
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(palette.ink(0.5))
                    .frame(width: 34, height: 34)
                    .background(palette.ink(0.06), in: .circle)
            }

            if store.tab == .search {
                searchField
            } else if store.tab == .board {
                columnChips
            }
        }
        .padding(.horizontal, 20)
    }

    private var hamburger: some View {
        VStack(spacing: 4) {
            Capsule().frame(width: 14, height: 1.8)
            Capsule().frame(width: 14, height: 1.8)
            Capsule().frame(width: 9, height: 1.8).padding(.trailing, 5)
        }
        .foregroundStyle(palette.ink(0.55))
        .frame(width: 34, height: 34)
        .background(palette.ink(0.06), in: .circle)
        .padding(.bottom, 3)
    }

    private var searchField: some View {
        @Bindable var store = store

        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.ink(0.45))
            TextField("Search all tasks", text: $store.query)
                .textFieldStyle(.plain)
                .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                .foregroundStyle(palette.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(palette.ink(0.06), in: .rect(cornerRadius: 14))
    }

    private var columnChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(store.pagerColumns) { column in
                    let isCurrent = column.id == store.mobileColumnID
                    Button { store.mobileColumnID = column.id } label: {
                        HStack(spacing: 6) {
                            Text(column.name)
                                .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .footnote))
                            Text("\(store.visibleTasks(in: column.id).count)")
                                .font(SimpleKanbanFont.ui(10.5, .extraBold, relativeTo: .caption2))
                                .opacity(0.65)
                        }
                        .foregroundStyle(isCurrent ? .white : palette.ink(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isCurrent ? palette.accent : palette.ink(0.055), in: .capsule)
                    }
                    .buttonStyle(.bare)
                    .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }
}

/// Previous / dots / next, stepping through the workflow columns.
struct PhoneColumnPager: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            stepButton(systemName: "chevron.left", label: "Previous column") {
                store.stepMobileColumn(by: -1)
            }

            HStack(spacing: 7) {
                ForEach(store.pagerColumns) { column in
                    let isCurrent = column.id == store.mobileColumnID
                    Capsule()
                        .fill(isCurrent ? palette.accent : palette.ink(0.18))
                        .frame(width: isCurrent ? 22 : 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.snappy(duration: 0.2), value: store.mobileColumnID)

            stepButton(systemName: "chevron.right", label: "Next column") {
                store.stepMobileColumn(by: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func stepButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink(0.6))
                .frame(width: 30, height: 30)
                .background(palette.ink(0.06), in: .circle)
        }
        .buttonStyle(.bare)
        .accessibilityLabel(label)
    }
}

#endif
