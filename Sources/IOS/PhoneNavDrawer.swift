#if os(iOS)

import SwiftUI

/// The slide-over board list. The design specifies a drawer at 84% width with a
/// scrim, so this stays a custom overlay rather than a navigation split view.
struct PhoneNavDrawer: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var body: some View {
        ZStack(alignment: .leading) {
            palette.ink(0.3)
                .ignoresSafeArea()
                .onTapGesture { store.isNavDrawerOpen = false }
                .transition(.opacity)

            panel
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.84 }
                .transition(.move(edge: .leading))
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Simple Kanban").font(SimpleKanbanFont.serif(26))
                Spacer(minLength: 0)
                Button { store.isNavDrawerOpen = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.ink(0.55))
                        .frame(width: 30, height: 30)
                        .background(palette.ink(0.07), in: .circle)
                }
                .buttonStyle(.bare)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            sectionHeader("Boards", topPadding: 0)
            VStack(spacing: 2) {
                boardRow(name: "Northwind iOS 3.0", dot: .accent, count: store.totalCount, isActive: true)
                boardRow(name: "Website refresh", dot: .hex(0x1F6F63), count: 9, isActive: false)
                boardRow(name: "Support triage", dot: .hex(0xC98A16), count: 4, isActive: false)
            }
            .padding(.horizontal, 12)

            sectionHeader("Views", topPadding: 24)
            VStack(spacing: 2) {
                viewRow("Today", count: store.todayCount)
                viewRow("Upcoming")
                viewRow("High priority")
                viewRow("Due this week")
                viewRow("Recently updated")
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
            weeklySummary
        }
        .padding(.top, 20)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(palette.sidebar)
                .shadow(color: palette.shadow(0.24), radius: 20, x: 8)
                .ignoresSafeArea()
        }
    }

    private func sectionHeader(_ title: String, topPadding: CGFloat) -> some View {
        Text(title)
            .sectionLabelStyle()
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .padding(.bottom, 8)
    }

    private func boardRow(name: String, dot: SwatchColor, count: Int, isActive: Bool) -> some View {
        HStack(spacing: 11) {
            Circle()
                .fill(palette.resolve(dot))
                .frame(width: 8, height: 8)
            Text(name)
                .font(SimpleKanbanFont.ui(15, isActive ? .bold : .semibold, relativeTo: .body))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count)")
                .font(SimpleKanbanFont.ui(12.5, .bold, relativeTo: .caption))
                .opacity(isActive ? 0.7 : 0.5)
        }
        .foregroundStyle(isActive ? palette.accent : palette.ink(0.66))
        .padding(12)
        .background(isActive ? palette.accentSoft : .clear, in: .rect(cornerRadius: 12))
    }

    private func viewRow(_ name: String, count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(SimpleKanbanFont.ui(15, .semibold, relativeTo: .body))
                .foregroundStyle(palette.ink(0.66))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let count {
                CountPill(count: count, font: 12.5, horizontalPadding: 8)
            }
        }
        .padding(12)
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This week")
                .sectionLabelStyle(tracking: 0.08, opacity: 0.4)
                .padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(store.doneCount)").font(SimpleKanbanFont.serif(34))
                Text("shipped")
                    .font(SimpleKanbanFont.ui(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(palette.ink(0.5))
            }
            ProgressMeter(fraction: store.doneFraction, height: 6)
                .padding(.top, 11)
        }
        .padding(16)
        .background(palette.ink(0.045), in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}

#endif
