import SwiftUI

extension Palette {
    private var isDarkScheme: Bool { colorScheme == .dark }

    /// What is drawn *on* ``accent``: a filled button's label, the tick inside a
    /// completed checkbox, the current chip in a row of chips.
    ///
    /// Seven views wrote this as a literal `.white`, which is a C2 violation and
    /// also wrong. Three of the four accents are dark, saturated colours in
    /// either scheme and white is right on them — but `.ink` *is* the ink
    /// colour, and ink in dark mode is 0xEEEAE2. A white label on the ink accent
    /// in dark mode is white on near-white: the toolbar's New task button, the
    /// completion tick, the pager chips and the due-date presets all read as
    /// blank. On-accent is the colour the accent is not, so it follows the
    /// scheme the other way round.
    var onAccent: Color {
        switch accentTheme {
        case .ember, .pine, .indigo: Color(hex: 0xFFFFFF)
        case .ink: Color(hex: isDarkScheme ? 0x171310 : 0xFCFBF9)
        }
    }

    /// The wash over whatever a panel is covering: the iPhone's navigation
    /// drawer and its Inbox slide-over, which are the two things in this app
    /// that cover a surface rather than sitting beside it.
    ///
    /// **Not `ink(0.3)`, which is what both of them used to be** — the same
    /// trap ``onAccent`` documents from the other end. Ink is the *text* colour
    /// and in dark mode it is 0xEEEAE2, so a scrim written as ink laid a
    /// near-white veil over the board: opening either panel lit the screen up
    /// instead of dimming it, which is the one thing a scrim exists not to do.
    ///
    /// A scrim is a **shadow** rather than an ink — it is the absence of what
    /// is behind it — and `shadow(_:)` is already the colour that goes to pure
    /// black in dark mode, for this exact reason. Light mode is unchanged to
    /// the byte: shadow and ink are the same 0x171310 there, which is why this
    /// went unnoticed.
    ///
    /// Heavier in the dark, because the board is 0x131110 to begin with and
    /// black at 0.3 over near-black is not a wash anybody can see. `fraction`
    /// is for a panel being dragged in, whose scrim arrives with it.
    func scrim(_ fraction: Double = 1) -> Color {
        shadow((isDarkScheme ? 0.5 : 0.3) * fraction)
    }

    /// Ink for text and for the glyphs read as text, with a floor under the
    /// opacity the design asks for.
    ///
    /// The design's secondary tones — 0.38 on a section label, 0.4 on a count
    /// pill, 0.42 on the sub-task badge, 0.45 on a glyph, 0.5 on a card's
    /// note — carry 2.4:1 to 3.5:1 against the surfaces they are drawn on.
    /// WCAG asks 4.5:1 of text that size and the Accessibility Inspector's
    /// audit reports every one of them: 26 contrast failures on a single iPad
    /// screen, which is the largest single category 7.1 had to answer for.
    ///
    /// 0.62 is the lowest opacity that clears 4.5:1 on the worst pairing the
    /// app draws, on paper. It was not enough: at 0.62 the audit went on
    /// reporting the count pill, whose 11pt digit sits on a second wash of ink
    /// and computes to 4.76:1 — flat-colour arithmetic that anti-aliased type
    /// this small does not actually deliver. 0.68 carries 5.8:1 there and 6.3
    /// on a card, and is where Apple puts its own `secondaryLabel`.
    ///
    /// The call site still passes the design's own number, so the hierarchy it
    /// wanted is still written down and comes back on its own if the palette is
    /// ever re-toned darker.
    func inkText(_ opacity: Double) -> Color { ink(max(opacity, Self.readableInk)) }

    /// The floor ``inkText(_:)`` applies. One number, so the whole app's
    /// secondary tone moves together.
    static let readableInk: Double = 0.68

    /// The dot beside a card's metadata row.
    func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .high: accent
        case .medium: isDarkScheme ? Color(hex: 0xE0A83A) : Color(hex: 0xC98A16)
        case .low: isDarkScheme ? ink(0.38) : Color(hex: 0xB4AEA4)
        }
    }

    /// The due chip's colours. Completed work reads green regardless of date;
    /// otherwise anything due today or already past is urgent, the next couple
    /// of days are warm, and everything further out is neutral ink.
    ///
    /// It takes the column's *role* rather than its id: a board whose owner
    /// made their own Done column would otherwise go on colouring shipped work
    /// as overdue.
    func dueTone(urgency: DueUrgency, role: ColumnRole) -> (background: Color, foreground: Color) {
        if role == .done {
            return isDarkScheme
                ? (Color(hex: 0x50BEAA, opacity: 0.16), Color(hex: 0x8FD9C8))
                : (Color(hex: 0x1F6F63, opacity: 0.12), Color(hex: 0x175A50))
        }
        switch urgency {
        case .overdue, .today:
            return isDarkScheme
                ? (Color(hex: 0xF05A5A, opacity: 0.18), Color(hex: 0xF3A3A3))
                : (Color(hex: 0xBE2828, opacity: 0.12), Color(hex: 0xA32222))
        case .soon:
            return isDarkScheme
                ? (Color(hex: 0xE6AF3C, opacity: 0.18), Color(hex: 0xEFCB84))
                : (Color(hex: 0xC98A16, opacity: 0.16), Color(hex: 0x8A5D06))
        case .later:
            // The one tone of the four that failed: 0.55 of ink on 0.06 of ink
            // over a card is 3.95:1, and the other three clear 4.9. See
            // ``inkText(_:)`` for where 0.62 comes from.
            return (ink(0.06), inkText(0.55))
        }
    }

    /// Convenience for a task's own due date. `today` is passed rather than
    /// read from the clock so the tint follows the day rolling over.
    func dueTone(
        due: CalendarDay, today: CalendarDay, role: ColumnRole
    ) -> (background: Color, foreground: Color) {
        dueTone(urgency: DueDate.urgency(due, from: today), role: role)
    }
}
