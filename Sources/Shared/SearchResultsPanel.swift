// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The search results, hanging under the field they were typed into.
///
/// **A place to go, not a filter over the board.** The field used to narrow the
/// columns behind it, which answers "which of the cards on this board match"
/// and cannot answer the question people actually type into a search field:
/// *where is that card*. The card is usually on another board, and a filter
/// over the board you are already looking at is the one shape of answer that
/// can never say so. So the query no longer touches the board — see
/// ``BoardStore/searchResults`` — and this panel lists every task in the app,
/// best match first, with the board and column each one lives on.
///
/// **One panel, both pointer platforms.** macOS and iPadOS present it
/// identically because it is the same act on both; the phone's Search tab is
/// the same list drawn full-screen, and all three go through the one matcher in
/// ``TaskSearch``.
///
/// **An overlay rather than `.popover`.** A real popover is its own window on
/// macOS and its own presentation on iPadOS, and both take first responder as
/// they open — which drops the keyboard out of the field the user is still
/// typing into, one character in. Measured, both platforms. What is drawn here
/// is a panel with a popover's shadow and radius, laid over the board by the
/// toolbar that owns the field.
struct SearchResultsPanel: View {
    struct Metrics {
        /// How wide the panel is, floored against the field it hangs under —
        /// see ``SearchResultsPanel/width(under:)``.
        var minWidth: CGFloat
        var maxHeight: CGFloat
        var rowSpacing: CGFloat
        var titleSize: CGFloat
        /// The one line of the description under the title.
        var noteSize: CGFloat
        var placeSize: CGFloat
        var radius: CGFloat
        /// The least a row may be, which on touch is the 44pt minimum and on
        /// the desk is only what the two lines of text need.
        var rowHeight: CGFloat

        // Wider than the field they hang under: a row is three lines now — the
        // title, a line of the description, and where the card lives — and the
        // last of those is a board, a column, a priority and however many labels
        // the card carries.
        static let desk = Metrics(
            minWidth: 400, maxHeight: 440, rowSpacing: 2, titleSize: 13,
            noteSize: 11.5, placeSize: 10.5, radius: 12, rowHeight: 34
        )
        static let pad = Metrics(
            minWidth: 440, maxHeight: 480, rowSpacing: 4, titleSize: 15,
            noteSize: 13, placeSize: 11.5, radius: 14, rowHeight: 44
        )
    }

    @Environment(\.palette) private var palette
    @Environment(\.dayClock) private var dayClock
    @Environment(BoardStore.self) private var store

    let results: [TaskItem]
    /// Which row Return would take. Owned by the toolbar, because the keys that
    /// move it are pressed in the *field* — the panel never holds focus, and a
    /// list that cannot be reached by keyboard is one a search field cannot use.
    @Binding var highlighted: TaskItem.ID?
    var metrics: Metrics = .desk
    let choose: (TaskItem.ID) -> Void

    private var chrome = ChromeScale()

    init(
        results: [TaskItem],
        highlighted: Binding<TaskItem.ID?>,
        metrics: Metrics = .desk,
        choose: @escaping (TaskItem.ID) -> Void
    ) {
        self.results = results
        _highlighted = highlighted
        self.metrics = metrics
        self.choose = choose
    }

    var body: some View {
        Group {
            if results.isEmpty {
                nothingMatched
            } else {
                rows
            }
        }
        .background(palette.panelSolid, in: .rect(cornerRadius: metrics.radius))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.radius)
                .strokeBorder(palette.ink(0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        // One element per result and nothing announcing the container, so a
        // reader arrives on the first match rather than on a group wrapper.
        .accessibilityLabel("Search results")
    }

    /// Scrolled rather than capped. A cap would make the panel a *sample* of
    /// what matched, and the one thing a reader cannot do with a sample is
    /// conclude that the card is not there.
    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: metrics.rowSpacing) {
                    ForEach(results) { task in
                        row(task)
                            .id(task.id)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: chrome(metrics.maxHeight, cap: 1.35))
            // The keys are pressed in the field, so the row they move to has to
            // be scrolled to from here — the panel is what knows where it is.
            .onChange(of: highlighted) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: nil)
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        let isHighlighted = highlighted == task.id
        return Button { choose(task.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.displayTitle)
                        .font(palette.ui(metrics.titleSize, .bold, relativeTo: .subheadline))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // One line of the description, which is often the only thing
                    // that tells two cards with similar titles apart — and the
                    // first line is where people put the sentence that does it.
                    if let note = Self.firstLine(of: task.note) {
                        // Tinted and not underlined, as the card's preview is:
                        // the row is a button that opens the task, and the link
                        // is live once you are there. See ``TaskLinks``.
                        Text(TaskLinks.highlighted(note, tint: palette.accent))
                            .font(palette.ui(metrics.noteSize, .medium, relativeTo: .caption))
                            .foregroundStyle(palette.inkText(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    place(of: task)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Beside the title rather than centred on a row that is now
                // three lines tall.
                if let due = task.due {
                    DueChip(due: due, today: dayClock.today, isDone: store.isDone(task))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minHeight: chrome(metrics.rowHeight))
            .contentShape(.rect)
        }
        .bareButton()
        .background(
            isHighlighted ? palette.ink(0.07) : .clear,
            in: .rect(cornerRadius: metrics.radius - 4)
        )
        // Only where nothing is driving it from the keyboard: a pointer moving
        // over the list while the user arrows through it would fight for the
        // same highlight, and the arrow keys are the ones that decide what
        // Return does.
        .hoverBackground(isHighlighted ? .clear : palette.ink(0.05), radius: metrics.radius - 4)
        // The row says the title; the line under it says where the card is, and
        // a reader needs both in one breath.
        .accessibilityElement(children: .combine)
    }

    /// Where the card is and what it is like: **board, column, priority**, in
    /// that order.
    ///
    /// The order is the funnel a reader follows — which board, then which column
    /// of it, and only then what the card is like — so the two that say *where*
    /// come first and stay together. The board and column are the half of a
    /// result the board itself could never show, and the reason this list spans
    /// every board.
    ///
    /// **No labels.** They were here for one build and came straight out: a card
    /// may carry any number of them, they are the widest thing a line like this
    /// can be asked to hold, and none of them is what tells one result from
    /// another — the title and the description above have already done that. The
    /// card itself is two lines further on for anyone who wants the rest.
    private func place(of task: TaskItem) -> some View {
        HStack(spacing: 6) {
            if let board = store.board(id: task.boardID) {
                Text(board.name)
                    .font(palette.ui(metrics.placeSize, .bold, relativeTo: .caption2))
                    .foregroundStyle(palette.inkText(0.42))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            ColumnChip(column: store.column(for: task), size: .compact)
                // The chip sizes itself to its name and stops. Without this it
                // takes the row's whole width — it is built to fill the space a
                // card's flow layout gives it — and a result reads as one long
                // grey bar with a column name at the front of it.
                .fixedSize()
            PriorityDot(priority: task.priority, namesPriority: true)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    /// The first line of a description that has one — the first line with
    /// anything on it, so a note that starts with a blank line still shows its
    /// sentence rather than an empty row.
    static func firstLine(of note: String) -> String? {
        note.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    private var nothingMatched: some View {
        Text("No tasks match “\(store.query)”", comment: "Search results panel with no matches")
            .font(palette.ui(metrics.titleSize, .semibold, relativeTo: .subheadline))
            .foregroundStyle(palette.inkText(0.5))
            .lineLimit(2)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: chrome(52), alignment: .leading)
    }
}

extension SearchResultsPanel {
    /// How wide to draw it under a field of `fieldWidth`.
    ///
    /// Never narrower than the field it hangs from — a panel that stopped short
    /// of the control it belongs to reads as something else on screen — and
    /// never so wide it leaves the window, which is what the caller's own width
    /// is for.
    static func width(under fieldWidth: CGFloat, in containerWidth: CGFloat, metrics: Metrics) -> CGFloat {
        let wanted = max(fieldWidth, metrics.minWidth)
        guard containerWidth > 0 else { return wanted }
        return min(wanted, containerWidth)
    }

    /// Where the panel's leading edge goes: under the field, pulled back inside
    /// the window when the field is near the trailing edge and the panel is
    /// wider than it.
    static func offset(under field: CGRect, width: CGFloat, in containerWidth: CGFloat) -> CGFloat {
        guard containerWidth > 0 else { return field.minX }
        return max(0, min(field.minX, containerWidth - width))
    }
}
