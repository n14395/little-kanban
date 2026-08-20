#if os(macOS)

import SwiftUI

/// The fixed 232pt source list: boards, saved views, and the weekly ship count.
///
/// The board and view rows are presentational — the design defines no board
/// switching or view filtering behaviour, so neither does this. See README.
struct MacSidebar: View {
    @Environment(\.palette) private var palette
    @Environment(BoardStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            trafficLightInset

            sectionHeader("Boards", topPadding: 0)
            VStack(spacing: 2) {
                boardRow(name: "Northwind iOS 3.0", dot: .accent, count: store.totalCount, isActive: true)
                boardRow(name: "Website refresh", dot: .hex(0x1F6F63), count: 9, isActive: false)
                boardRow(name: "Support triage", dot: .hex(0xC98A16), count: 4, isActive: false)
            }
            .padding(.horizontal, 8)

            sectionHeader("Views", topPadding: 22)
            VStack(spacing: 2) {
                viewRow("Today", count: store.todayCount)
                viewRow("Upcoming")
                viewRow("High priority")
                viewRow("Due this week")
                viewRow("Recently updated")
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
            weeklySummary
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 232)
        .background(palette.sidebar)
        .hairline(.trailing, color: palette.ink(0.07))
    }

    /// The window's own traffic lights sit here (the title bar is hidden), so
    /// the sidebar reserves the same 14pt band the design draws them in.
    private var trafficLightInset: some View {
        Color.clear
            .frame(height: 14)
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
    }

    private func sectionHeader(_ title: String, topPadding: CGFloat) -> some View {
        Text(title)
            .sectionLabelStyle()
            .padding(.horizontal, 12)
            .padding(.top, topPadding)
            .padding(.bottom, 6)
    }

    private func boardRow(name: String, dot: SwatchColor, count: Int, isActive: Bool) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(palette.resolve(dot))
                .frame(width: 7, height: 7)
            Text(name)
                .font(SimpleKanbanFont.ui(13, isActive ? .bold : .semibold, relativeTo: .subheadline))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count)")
                .font(SimpleKanbanFont.ui(11, .bold, relativeTo: .caption2))
                .opacity(isActive ? 0.7 : 0.5)
        }
        .foregroundStyle(isActive ? palette.accent : palette.ink(0.66))
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(isActive ? palette.accentSoft : .clear, in: .rect(cornerRadius: 9))
        .hoverBackground(isActive ? .clear : palette.ink(0.05), radius: 9)
    }

    private func viewRow(_ name: String, count: Int? = nil) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(SimpleKanbanFont.ui(13, .semibold, relativeTo: .subheadline))
                .foregroundStyle(palette.ink(0.66))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let count {
                CountPill(count: count)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .hoverBackground(palette.ink(0.05), radius: 9)
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This week")
                .sectionLabelStyle(tracking: 0.08, opacity: 0.4)
                .padding(.bottom, 8)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(store.doneCount)")
                    .font(SimpleKanbanFont.serif(30))
                Text("shipped")
                    .font(SimpleKanbanFont.ui(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(palette.ink(0.5))
            }

            ProgressMeter(fraction: store.doneFraction, height: 5)
                .padding(.top, 10)
        }
        .padding(12)
        .background(palette.ink(0.045), in: .rect(cornerRadius: 12))
        .padding(.horizontal, 12)
    }
}

#endif
