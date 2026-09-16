import SwiftUI

/// The mark that encodes a task's priority.
///
/// It was a coloured dot and nothing else, which is the whole of what 7.1 calls
/// colour carrying meaning alone: the tints are traffic lights — green, amber,
/// red, and red again for Max — and to anyone who cannot tell those apart a
/// card said nothing about its priority at all. So the marks differ in
/// **shape** as well — a filled disc, a filled square, a ring — which is a
/// difference that survives a greyscale screenshot, and which nobody has to
/// turn a setting on to get. For Max against High the shape is not a fallback
/// but the whole message: both wear the red, and the triangle is what says
/// *more*.
///
/// Turning the setting on adds the word. `differentiateWithoutColor` is the
/// reader saying they do not want to infer anything from a hue, and on a card
/// the mark is the only thing that names the priority at all; in the picker the
/// word is already the row beside it, so only the cards ask for it.
///
/// The mark scales with Dynamic Type. It carries meaning, so it is type rather
/// than decoration, and a 6pt disc beside 30pt text is a fleck.
struct PriorityDot: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let priority: Priority
    var diameter: CGFloat = 6
    /// Whether this mark may say the priority in words. See above.
    var namesPriority: Bool = false

    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 100

    private var size: CGFloat { diameter * min(max(1, scale / 100), 2) }

    var body: some View {
        HStack(spacing: size * 0.55) {
            mark
                .frame(width: size, height: size)
                .foregroundStyle(palette.priorityColor(priority))
            if namesPriority, differentiateWithoutColor {
                Text(priority.displayName)
                    .font(palette.ui(10.5, .extraBold, relativeTo: .caption2))
                    .textCase(.uppercase)
                    .foregroundStyle(palette.inkText(0.55))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "\(priority.displayName) priority",
                   comment: "Accessibility label for the priority mark on a card")
        )
    }

    /// Point, filled disc, filled square, ring — heaviest to lightest, so the
    /// shapes rank the way the priorities do.
    ///
    /// Max is the triangle for the reason `SavedView.highPriority` is drawn
    /// with `exclamationmark.triangle`: it is the shape that means *look at
    /// this* rather than one more rounded thing, and at 6pt it is the only one
    /// of the four that could not be mistaken for another at a glance.
    @ViewBuilder
    private var mark: some View {
        switch Self.mark(for: priority) {
        case .triangle: Triangle()
        case .disc: Circle()
        case .square: RoundedRectangle(cornerRadius: size * 0.22)
        case .ring: Circle().strokeBorder(lineWidth: max(1, size * 0.3))
        }
    }

    /// Which of the four the mark is. Named rather than switched inline
    /// because a shape drawn in a body is invisible to the suite, and the whole
    /// claim being made here is that the four differ.
    enum Mark: Hashable { case triangle, disc, square, ring }

    static func mark(for priority: Priority) -> Mark {
        switch priority {
        case .max: .triangle
        case .high: .disc
        case .medium: .square
        case .low: .ring
        }
    }
}

/// The one shape SwiftUI does not ship. Point up, sitting on its own base, and
/// drawn to whatever square it is given — see ``PriorityDot``, which is the
/// only thing that asks for it.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The due-date pill, tinted by urgency.
///
/// The day to measure from is passed in rather than read from the clock: the
/// caller takes it from `DayClock`, which is what re-renders the chip at
/// midnight instead of leaving it reading "Today" into the next morning.
struct DueChip: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    let due: CalendarDay
    let today: CalendarDay
    /// The role of the column the task is in, which is the only thing the tint
    /// asks about it: completed work reads green whatever the date says.
    let isDone: Bool
    var font: CGFloat = 11
    var horizontalPadding: CGFloat = 6
    var radius: CGFloat = 6

    var body: some View {
        let tone = palette.dueTone(due: due, today: today, isDone: isDone)
        HStack(spacing: 3) {
            if let symbol = urgencySymbol, differentiateWithoutColor {
                Image(systemName: symbol)
                    .symbolSize(font - 1.5, weight: .bold, relativeTo: .caption)
                    .accessibilityHidden(true)
            }
            Text(DueDate.label(due, from: today))
                .font(palette.ui(font, .bold, relativeTo: .caption))
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 2)
        .background(tone.background, in: .rect(cornerRadius: radius))
        // "Mon" alone is last Monday or next Monday, and the colour that
        // tells them apart is not something VoiceOver can read out.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DueDate.accessibilityLabel(due, from: today))
    }

    /// What the tint says, said again in a shape, for a reader who has asked
    /// not to be told anything by colour alone. Four tints, four states: done,
    /// urgent, close, and a date far enough out that the chip is only a date —
    /// which is the one that earns no mark, because a mark on every chip is a
    /// mark that distinguishes nothing.
    private var urgencySymbol: String? {
        Self.urgencySymbol(urgency: DueDate.urgency(due, from: today), isDone: isDone)
    }

    /// A `static` for the same reason ``PriorityDot/mark(for:)`` is one.
    static func urgencySymbol(urgency: DueUrgency, isDone: Bool) -> String? {
        if isDone { return "checkmark" }
        switch urgency {
        case .overdue, .today: return "exclamationmark"
        case .soon: return "clock"
        case .later: return nil
        }
    }
}

/// Where a task sits, for a card drawn away from it — a saved view, the phone's
/// Search tab, the Inbox. Two results with the same title, one in Backlog and
/// one in Done, are otherwise told apart only by a strikethrough.
///
/// The geometry is `LabelChip`'s, borrowed rather than re-declared so the two
/// sit level when a card carries both. The fill is not: a second coloured pill
/// would read as another label, and a column is where a task *is* rather than
/// something the user put on it. The colour is spent on the dot instead, which
/// is how the column header already names itself.
struct ColumnChip: View {
    @Environment(\.palette) private var palette

    /// The task's column, or `nil` for a card in the Inbox — which the chip
    /// **names** rather than skipping. `nil` cannot mean "an id no column
    /// answers to" any more: the store puts every task it adopts back through
    /// `TaskPlacement`, and deleting a column relocates its cards, so a
    /// non-`nil` `columnID` always resolves. Drawing nothing would leave the
    /// reader inferring "unfiled" from an absence, in the one list where cards
    /// from the Inbox and from a board sit side by side.
    let column: BoardColumn?
    var size: LabelChip.Size = .compact
    /// Use the abbreviated name ("Doing"), where a row has less room than the
    /// flat lists do.
    var usesShortName: Bool = false

    var body: some View {
        HStack(spacing: dotSpacing) {
            Circle()
                .fill(palette.resolve(column?.dot ?? Board.inboxDot))
                .frame(width: dotDiameter, height: dotDiameter)
            Text(usesShortName ? (column?.short ?? Board.inboxName) : name)
                .font(palette.ui(size.font, .extraBold, relativeTo: .caption2))
                // See `LabelChip`: tracking would clip the last letter.
                .kerning(size.font * 0.04)
                .textCase(.uppercase)
                .lineLimit(size.nameLineLimit)
                .truncationMode(size.nameTruncation)
                .frame(maxWidth: size.maxNameWidth, alignment: .leading)
        }
        .foregroundStyle(palette.inkText(0.55))
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(palette.ink(0.06), in: .rect(cornerRadius: size.radius))
        // "BACKLOG" read out mid-card says nothing about what it is, and a
        // sentence built around the name reads as whatever the name
        // happens to be — "In In Progress" today, and worse now that people
        // name their own columns. A field and its value do not care what the
        // value says. The Inbox is not a column, so it gets the sentence a
        // place can carry instead of a field it would have to lie about.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var name: String { column?.name ?? Board.inboxName }

    private var accessibilityLabel: String {
        column == nil
            ? String(localized: "In the Inbox",
                     comment: "Accessibility label for the place chip on an unfiled card")
            : String(localized: "Column: \(name)",
                     comment: "Accessibility label for the column chip on a card shown outside its column")
    }

    /// Both track the type rather than being constants, so the chip stays
    /// balanced at either size.
    private var dotDiameter: CGFloat { size == .compact ? 5 : 6 }
    private var dotSpacing: CGFloat { size == .compact ? 5 : 6 }
}

/// The small rounded count beside a column or view name.
struct CountPill: View {
    @Environment(\.palette) private var palette
    let count: Int
    /// The column's WIP limit, when it has one — see ``BoardColumn/limit``.
    /// `nil` draws the pill exactly as it always has: a bare number in the
    /// wash, saying nothing about how full anything is.
    var limit: Int?
    var font: CGFloat = 11
    var horizontalPadding: CGFloat = 6

    private var load: ColumnLoad { ColumnLoad(count: count, limit: limit) }

    var body: some View {
        // The tone is `nil` under the limit and without one, which is the same
        // pill this has always been. See `Palette.loadTone(_:)`.
        let tone = palette.loadTone(load)
        label
            .font(palette.ui(font, .bold, relativeTo: .caption2))
            .foregroundStyle(tone?.foreground ?? palette.inkText(0.4))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 1)
            .background(tone?.background ?? palette.ink(0.06), in: .capsule)
            .accessibilityLabel(spokenLabel)
    }

    @ViewBuilder private var label: some View {
        if let limit {
            // Localised rather than assembled from a String, so a locale that
            // wants a different separator between the pair has somewhere to say
            // so — and so the numbers themselves are formatted for it.
            Text("\(count)/\(limit)", comment: "A column's card count against its WIP limit, as in 4/3")
        } else {
            Text("\(count)")
        }
    }

    /// Silent about a column with no limit, which leaves VoiceOver reading the
    /// number itself — what it has always read, and all there is to say. A pill
    /// carrying a limit reads as two numbers otherwise ("4 slash 3"), which
    /// says nothing about whether that is good news.
    private var spokenLabel: Text {
        guard let limit else { return Text("\(count)") }
        return switch load {
        case .over:
            Text("\(count) of \(limit), over the column limit",
                 comment: "VoiceOver label for a column count pill past its WIP limit")
        case .at:
            Text("\(count) of \(limit), at the column limit",
                 comment: "VoiceOver label for a column count pill exactly at its WIP limit")
        case .under, .unlimited:
            Text("\(count) of \(limit)",
                 comment: "VoiceOver label for a column count pill below its WIP limit")
        }
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
                    .symbolSize(font, weight: .semibold, relativeTo: .caption)
            }
            Text(text)
                .font(palette.ui(font, .bold, relativeTo: .caption))
        }
        .foregroundStyle(palette.inkText(0.42))
    }
}

/// A flat progress meter — the checklist bar, the "This week" bar, and the line
/// along the foot of a card that has a checklist.
struct ProgressMeter: View {
    @Environment(\.palette) private var palette
    /// The bar shares a row with a heading and a count, and at an accessibility
    /// size those two fill the row on their own — the inspector's "CHECKLIST"
    /// broke across two lines and the meter sat on top of the second. It is
    /// decoration the reader is already hidden from, and the count beside it
    /// says the same thing in words, so it steps out rather than squeezing the
    /// two things that carry the meaning.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let fraction: Double
    var height: CGFloat = 4
    /// Whether the meter's own ends are shaped.
    ///
    /// Rounded where it floats in a row with air either side of it — the
    /// inspector's checklist, the week meter. Square where something else's
    /// corners are already doing the shaping, which is the card's bottom edge:
    /// a capsule there leaves a sliver of card showing at each end, under a
    /// clip that was going to round the corners anyway.
    var isFlush: Bool = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                track.fill(palette.ink(0.1))
                track
                    .fill(palette.accent)
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .frame(height: height)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 0 : nil)
        .opacity(dynamicTypeSize.isAccessibilitySize ? 0 : 1)
        .accessibilityHidden(true)
    }

    private var track: AnyShape { isFlush ? AnyShape(Rectangle()) : AnyShape(Capsule()) }
}
