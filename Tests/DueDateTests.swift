// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import LittleKanban

/// Every band edge of the due chip, against a fixed today.
///
/// `today` is Thursday 20 August 2026 throughout. The labels are localised and
/// the weekday ones are formatted by the locale the tests happen to run in, so
/// what is asserted is the *behaviour* of each band — which side of an edge a
/// day falls on, and whether the wording depends on today — rather than the
/// English strings.
@Suite struct DueDateTests {
    let today = CalendarDay(year: 2026, month: 8, day: 20)

    private func day(_ offset: Int) -> CalendarDay { today.adding(days: offset) }
    private func label(_ offset: Int) -> String { DueDate.label(day(offset), from: today) }
    private func urgency(_ offset: Int) -> DueUrgency { DueDate.urgency(day(offset), from: today) }

    // MARK: Distance

    @Test func daysAwayIsSignedAndWhole() {
        for offset in [-15, -14, -13, -8, -7, -6, -2, -1, 0, 1, 6, 7, 13, 14, 15] {
            #expect(DueDate.daysAway(day(offset), from: today) == offset)
        }
    }

    // MARK: Urgency bands

    @Test func urgencyChangesOnlyAtItsThreeEdges() {
        #expect(urgency(-15) == .overdue)
        #expect(urgency(-1) == .overdue)
        #expect(urgency(0) == .today)
        #expect(urgency(1) == .soon)
        #expect(urgency(2) == .soon)
        #expect(urgency(3) == .later)
        #expect(urgency(15) == .later)
    }

    // MARK: Label bands

    @Test func theFourFixedPhrasesSitExactlyOnTheirEdges() {
        let lastWeek = label(-7)
        #expect(label(-13) == lastWeek)
        #expect(label(-8) == lastWeek)
        #expect(label(-14) != lastWeek)          // beyond a fortnight it is a date
        #expect(label(-6) != lastWeek)           // inside a week it is a weekday

        let nextWeek = label(7)
        #expect(label(13) == nextWeek)
        #expect(label(14) != nextWeek)
        #expect(label(6) != nextWeek)

        let yesterday = label(-1)
        #expect(yesterday != label(-2))
        #expect(yesterday != label(0))

        let todayLabel = label(0)
        #expect(todayLabel != label(1))
        #expect(todayLabel != label(-1))
        #expect(todayLabel == DueDate.Preset.today.label)
    }

    @Test func lastWeekAndNextWeekAreDifferentPhrases() {
        #expect(label(-7) != label(7))
    }

    @Test func theWeekdayBandsNameTheWeekdayAndNothingElse() {
        // Two days five apart land in the two weekday bands — one behind today,
        // one ahead — and are the same weekday, so the compact chip reads the
        // same on both. That ambiguity is the whole reason the spoken form
        // exists, so it is asserted rather than tolerated.
        #expect(label(-2) == label(5))
        #expect(label(-6) == label(1))
        // …and different weekdays inside one band do not collide.
        #expect(label(1) != label(2))
        #expect(label(-2) != label(-3))
        // A weekday label never borrows one of the fixed phrases.
        for offset in [-6, -5, -4, -3, -2, 1, 2, 3, 4, 5, 6] {
            #expect(label(offset) != label(0), "offset \(offset) collided with Today")
            #expect(label(offset) != label(-1), "offset \(offset) collided with Yesterday")
            #expect(label(offset) != label(-7), "offset \(offset) collided with Last week")
            #expect(label(offset) != label(7), "offset \(offset) collided with Next week")
        }
    }

    @Test func beyondAFortnightTheLabelStopsDependingOnToday() {
        // An absolute date is the same string whoever asks; a relative one is not.
        let christmas = CalendarDay(year: 2026, month: 12, day: 25)
        let fromAugust = DueDate.label(christmas, from: today)
        let fromJanuary = DueDate.label(christmas, from: CalendarDay(year: 2026, month: 1, day: 1))
        #expect(fromAugust == fromJanuary)
        #expect(DueDate.daysAway(christmas, from: today) >= 14)

        let relative = DueDate.label(day(7), from: today)
        #expect(DueDate.label(day(7), from: today.adding(days: 7)) != relative)
    }

    // MARK: Spoken form

    @Test func theSpokenFormSaysWhichSideOfTodayADayFallsOn() {
        // Same chip text, opposite meanings — VoiceOver cannot see the colour
        // that separates them, so the words have to.
        #expect(label(-2) == label(5))
        #expect(DueDate.accessibilityLabel(day(-2), from: today) != DueDate.accessibilityLabel(day(5), from: today))
        #expect(DueDate.accessibilityLabel(day(0), from: today) != DueDate.accessibilityLabel(day(1), from: today))
        // It spells the day out rather than abbreviating it, so it is never the
        // compact label.
        for offset in [-2, 0, 5] {
            #expect(DueDate.accessibilityLabel(day(offset), from: today) != label(offset))
        }
    }

    // MARK: Presets and offsets

    @Test func presetsResolveAgainstTheDayPassedIn() {
        #expect(DueDate.Preset.today.day(from: today) == today)
        #expect(DueDate.Preset.tomorrow.day(from: today) == CalendarDay(year: 2026, month: 8, day: 21))
        #expect(DueDate.Preset.nextWeek.day(from: today) == CalendarDay(year: 2026, month: 8, day: 27))
        #expect(DueDate.Preset.allCases.map(\.id) == ["today", "tomorrow", "nextWeek"])
    }

    @Test func offsetWalksInBothDirections() {
        #expect(DueDate.offset(0, from: today) == today)
        #expect(DueDate.offset(-14, from: today) == CalendarDay(year: 2026, month: 8, day: 6))
        #expect(DueDate.offset(14, from: today) == CalendarDay(year: 2026, month: 9, day: 3))
    }
}
