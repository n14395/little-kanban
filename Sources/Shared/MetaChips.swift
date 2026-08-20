import SwiftUI

/// The coloured dot that encodes a task's priority.
struct PriorityDot: View {
    @Environment(\.palette) private var palette
    let priority: Priority
    var diameter: CGFloat = 6

    var body: some View {
        Circle()
            .fill(palette.priorityColor(priority))
            .frame(width: diameter, height: diameter)
            .accessibilityLabel("\(priority.displayName) priority")
    }
}

/// The due-date pill, tinted by urgency.
///
/// The day to measure from is passed in rather than read from the clock: the
/// caller takes it from `DayClock`, which is what re-renders the chip at
/// midnight instead of leaving it reading "Today" into the next morning.
struct DueChip: View {
    @Environment(\.palette) private var palette
    let due: CalendarDay
    let today: CalendarDay
    let columnID: BoardColumn.ID
    var font: CGFloat = 11
    var horizontalPadding: CGFloat = 6
    var radius: CGFloat = 6

    var body: some View {
        let tone = palette.dueTone(due: due, today: today, columnID: columnID)
        Text(DueDate.label(due, from: today))
            .font(SimpleKanbanFont.ui(font, .bold, relativeTo: .caption))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 2)
            .background(tone.background, in: .rect(cornerRadius: radius))
            // "Mon" alone is last Monday or next Monday, and the colour that
            // tells them apart is not something VoiceOver can read out.
            .accessibilityLabel(DueDate.accessibilityLabel(due, from: today))
    }
}

/// The small rounded count beside a column or view name.
struct CountPill: View {
    @Environment(\.palette) private var palette
    let count: Int
    var font: CGFloat = 11
    var horizontalPadding: CGFloat = 6

    var body: some View {
        Text("\(count)")
            .font(SimpleKanbanFont.ui(font, .bold, relativeTo: .caption2))
            .foregroundStyle(palette.ink(0.4))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 1)
            .background(palette.ink(0.06), in: .capsule)
    }
}

/// The sub-task-count marker on a macOS card: a tick glyph plus `2/3`.
struct SubtaskCountBadge: View {
    @Environment(\.palette) private var palette
    let text: String
    var font: CGFloat = 11
    var showsGlyph: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if showsGlyph {
                Image(systemName: "checklist")
                    .font(.system(size: font, weight: .semibold))
            }
            Text(text)
                .font(SimpleKanbanFont.ui(font, .bold, relativeTo: .caption))
        }
        .foregroundStyle(palette.ink(0.42))
    }
}

/// A flat progress meter — the checklist bar and the "This week" bar.
struct ProgressMeter: View {
    @Environment(\.palette) private var palette
    let fraction: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.ink(0.1))
                Capsule()
                    .fill(palette.accent)
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
