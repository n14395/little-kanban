// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

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
    /// **Traffic lights, not the theme.** Low is green, Medium is amber, High
    /// is red, and Max is the same red on the triangle — the shape is what
    /// says *more than High*, see `PriorityDot`. A priority is a scale, and a
    /// scale whose rungs changed hue with the theme was not one: High wore
    /// Ember's rust on one board and Aurora's mint on the next, and which of
    /// two marks was the louder depended on which theme they were read under.
    /// Green–amber–red is the one ranking nobody has to learn.
    ///
    /// Two literals per rung rather than one, because the marks sit on
    /// whatever card the theme draws: the darker set holds against a pale
    /// card, the brighter against a near-black one. The *hue* is fixed either
    /// way — a theme no longer gets a say in what a priority means.
    func priorityColor(_ priority: Priority) -> Color {
        switch priority {
        case .max, .high: Color(hex: isDark ? 0xFF5A4E : 0xD62B2B)
        case .medium: Color(hex: isDark ? 0xFFC93D : 0xC98A00)
        case .low: Color(hex: isDark ? 0x3ECF6E : 0x1E9E44)
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
    /// Every base is a literal now — `.accent` and `.ink` are pinned on
    /// ``SwatchColor`` — so the grey label goes through the same recipe as any
    /// other colour rather than borrowing the theme's ink, and no chip changes
    /// hue when the theme does.
    func chipTone(for base: SwatchColor) -> (background: Color, foreground: Color) {
        let value = base.literalValue
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

    /// The count pill's tint when a column is at or over its WIP limit.
    ///
    /// **The two due-chip recipes rather than two new theme parameters.** "This
    /// is getting tight" and "this is past it" are precisely what warm and hot
    /// already mean everywhere else in the app, all twenty presets have tuned
    /// them against their own ground, and a `ThemeWip` pair would have made a
    /// WIP limit a *theme* schema change — twenty presets and everybody's saved
    /// themes rewritten — for two colours every theme already carries.
    ///
    /// `nil` for a column with no limit, and for one under it: the pill draws
    /// its plain self, which is what it has always drawn. Colouring the normal
    /// case would spend the reader's attention on the columns that are fine.
    func loadTone(_ load: ColumnLoad) -> (background: Color, foreground: Color)? {
        switch load {
        case .unlimited, .under:
            nil
        case .at:
            (theme.dueChips.warm.background.color, theme.dueChips.warm.foreground.color)
        case .over:
            (theme.dueChips.hot.background.color, theme.dueChips.hot.foreground.color)
        }
    }
}
