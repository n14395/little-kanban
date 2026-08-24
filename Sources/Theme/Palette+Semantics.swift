import SwiftUI

extension Palette {
    /// What is drawn *on* ``accent``: a filled button's label, the tick inside a
    /// completed checkbox, the current chip in a row of chips.
    ///
    /// The theme states it rather than the app deducing it. Seven views once
    /// wrote it as a literal `.white`, which was wrong for the one accent of the
    /// four that was near-white itself: the capture button, the completion tick,
    /// the pager chips and the due-date presets all read as blank. It is a
    /// parameter now because a theme picking its own highlight has to be able to
    /// say what survives on top of it — Ultraviolet's gold takes near-black,
    /// Aurora's mint takes a deep green, and neither is a rule anything could
    /// have worked out.
    var onAccent: Color { theme.highlight.onAccent.color }

    /// The wash over whatever a panel is covering: the iPhone's navigation
    /// drawer, which is the one thing in this app that covers a surface of its
    /// own accord rather than sitting beside it. The Inbox's slide-over is
    /// covered too, by the system's own dimming — it is a real sheet, and a
    /// sheet dims what it is presented over without being asked.
    ///
    /// **Not the theme's panel overlay, and not ink.** A scrim is a *shadow* —
    /// the absence of what is behind it — which is why it goes through
    /// ``shadow(_:)`` and not ``ink(_:)``. Ink is the text colour and in a dark
    /// theme it is near-white, so a scrim written as ink laid a pale veil over
    /// the board: opening either panel lit the screen up instead of dimming it,
    /// which is the one thing a scrim exists not to do.
    ///
    /// Heavier in the dark, because the board is near-black to begin with and
    /// black at 0.3 over that is not a wash anybody can see. `fraction` is for a
    /// panel being dragged in, whose scrim arrives with it.
    func scrim(_ fraction: Double = 1) -> Color {
        shadow((isDark ? 0.5 : 0.3) * fraction)
    }

    /// Ink for text and for the glyphs read as text, with a floor under the
    /// opacity that is asked for.
    ///
    /// The design's secondary tones — 0.38 on a section label, 0.4 on a count
    /// pill, 0.42 on the sub-task badge, 0.5 on a card's note — carry 2.4:1 to
    /// 3.5:1 against the surfaces they are drawn on. WCAG asks 4.5:1 of text
    /// that size and the Accessibility Inspector's audit reported every one of
    /// them: 26 contrast failures on a single iPad screen.
    ///
    /// 0.68 is where Apple puts its own `secondaryLabel`, and it clears 5.8:1 on
    /// the worst pairing the app draws. 0.62 did not: the count pill's 11pt
    /// digit sits on a second wash of ink and computes to 4.76:1 — flat-colour
    /// arithmetic that anti-aliased type this small does not deliver.
    ///
    /// **A theme cannot lower it.** ``ThemeInk/muted`` and ``ThemeInk/faint``
    /// are the theme's own numbers and are used exactly as written for the
    /// things that are not text — a hairline, a dot, an empty meter track — but
    /// text that cannot be read is not a style choice. The theme editor says so
    /// where the two fields are.
    func inkText(_ opacity: Double) -> Color { ink(max(opacity, Self.readableInk)) }

    /// The floor ``inkText(_:)`` applies. One number, so the whole app's
    /// secondary tone moves together.
    static let readableInk: Double = 0.68

    /// The dot beside a card's metadata row.
    ///
    /// **Max is the one that does not take the accent.** High *is* the accent,
    /// so it is Ember's rust on one theme and Aurora's mint on another — a mark
    /// that says *this one* against the cards around it. Max has to say it
    /// against High as well, and a fifth tone of the accent would not; it takes
    /// the theme's overdue hue, which is the app's one alarm colour and is said
    /// once rather than twice. See ``ThemeStatus``.
    func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .max: theme.dueChips.hot.background.solid.color
        case .high: accent
        case .medium: theme.status.medium.color
        case .low: inkFaint
        }
    }

    /// A label's chip, worked out from the one colour the label carries.
    ///
    /// **The theme owns the recipe, not the colours.** A label is not one of a
    /// fixed four — you make labels and give each one a colour from the same
    /// picker a board and a column are coloured from — so what a theme can say
    /// about label chips is how a colour becomes a ground and a text. See
    /// ``ThemeChipRule``.
    ///
    /// A colourless label — the palette's grey, which is the theme's own ink and
    /// has no hue to derive from — gets ink at the two weights the `API` seed
    /// label wears.
    func chipTone(for base: SwatchColor) -> (background: Color, foreground: Color) {
        let value: UInt32
        switch base {
        case .rgb(let hex, _): value = hex
        case .accent: value = accentValue
        case .ink: return (ink(isDark ? 0.10 : 0.08), inkText(isDark ? 0.65 : 0.6))
        }
        let rule = theme.labelChips
        return (
            Color(hex: ColorMath.shade(value, by: rule.backgroundLift), opacity: rule.backgroundOpacity),
            Color(hex: ColorMath.shade(value, by: rule.foregroundShade))
        )
    }

    func chipTone(for label: LabelDef) -> (background: Color, foreground: Color) {
        chipTone(for: label.baseColor)
    }

    /// The due chip's colours. Completed work reads as the theme's done hue
    /// regardless of date; otherwise anything due today or already past is
    /// urgent, the next couple of days are warm, and everything further out is
    /// the wash with muted ink on it — which is the design's own line, "other
    /// dates use wash / muted".
    ///
    /// It takes *whether the card is done* rather than a column id: a board
    /// whose owner renamed their Done column to Shipped would otherwise go on
    /// colouring shipped work as overdue. Which column that is, is
    /// ``Board/doneColumn``'s answer and reaches here through
    /// `BoardStore.isDone(_:)`.
    func dueTone(urgency: DueUrgency, isDone: Bool) -> (background: Color, foreground: Color) {
        if isDone {
            // Through the chip rule rather than as a fifth and sixth literal:
            // the done chip and a green label chip are the same shape wearing
            // the same colour, and two recipes for that is one of them drifting.
            return chipTone(for: .hex(theme.status.done.hex))
        }
        switch urgency {
        case .overdue, .today:
            return (theme.dueChips.hot.background.color, theme.dueChips.hot.foreground.color)
        case .soon:
            return (theme.dueChips.warm.background.color, theme.dueChips.warm.foreground.color)
        case .later:
            return (wash, inkText(theme.ink.muted))
        }
    }

    /// Convenience for a task's own due date. `today` is passed rather than
    /// read from the clock so the tint follows the day rolling over.
    func dueTone(
        due: CalendarDay, today: CalendarDay, isDone: Bool
    ) -> (background: Color, foreground: Color) {
        dueTone(urgency: DueDate.urgency(due, from: today), isDone: isDone)
    }
}
