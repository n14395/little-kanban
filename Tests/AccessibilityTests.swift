import SwiftUI
import Testing
@testable import Simple_Kanban

/// 7.1's claims, held as numbers.
///
/// Every one of these is something the Accessibility Inspector's audit reported
/// and a human then had to re-check by eye. The audit is not in the suite —
/// it needs a running app — so what is here is the arithmetic underneath each
/// finding: the opacity a secondary tone resolves to, the ratio it carries, the
/// shape a priority draws, the glyph a due chip wears when colour is off the
/// table, and what an animation becomes when the reader has asked for less.
@Suite struct AccessibilityContrastTests {
    /// WCAG relative luminance, from the linear components `Color.Resolved`
    /// already hands back.
    private func luminance(_ color: Color.Resolved) -> Double {
        0.2126 * Double(color.linearRed)
            + 0.7152 * Double(color.linearGreen)
            + 0.0722 * Double(color.linearBlue)
    }

    /// `over` composited under `color`, in the space a blend actually happens
    /// in. `Color.Resolved` keeps opacity beside the channels rather than
    /// premultiplied into them, so this is the blend written out.
    private func composite(_ color: Color, over ground: Color) -> Color.Resolved {
        let top = color.resolve(in: EnvironmentValues())
        let bottom = ground.resolve(in: EnvironmentValues())
        let a = top.opacity
        return Color.Resolved(
            red: bottom.red + a * (top.red - bottom.red),
            green: bottom.green + a * (top.green - bottom.green),
            blue: bottom.blue + a * (top.blue - bottom.blue)
        )
    }

    private func contrast(_ a: Color.Resolved, _ b: Color.Resolved) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    private func surfaces(_ palette: Palette) -> [(String, Color)] {
        [
            ("card", palette.card), ("panel", palette.panel), ("sheet", palette.sheet),
            ("sidebar", palette.sidebar), ("window", palette.window),
            ("app", palette.appBackground),
        ]
    }

    /// The design's secondary tones run from 0.38 to 0.55 of ink, and at those
    /// opacities a count pill reads at 2.6:1 and a card's note at 3.5:1 — under
    /// the 4.5:1 WCAG asks of text that size, and 26 separate findings on one
    /// iPad screen. Every one of them now goes through ``Palette/inkText(_:)``,
    /// and this is the claim that makes.
    @Test func everySecondaryToneIsReadableOnEverySurfaceItIsDrawnOn() {
        for scheme in [ColorScheme.light, .dark] {
            let palette = Palette(colorScheme: scheme)
            for requested in [0.38, 0.4, 0.42, 0.45, 0.5, 0.55, 0.6] {
                for (name, surface) in surfaces(palette) {
                    let ink = composite(palette.inkText(requested), over: surface)
                    let ratio = contrast(ink, surface.resolve(in: EnvironmentValues()))
                    #expect(
                        ratio >= 4.5,
                        "inkText(\(requested)) on \(name) in \(scheme) is \(ratio):1"
                    )
                }
            }
        }
    }

    /// A tone the design already drew darker than the floor is left exactly as
    /// it was: the floor is a floor, not a flattening.
    @Test func aToneAlreadyDarkEnoughIsUntouched() {
        let palette = Palette(colorScheme: .light)
        #expect(palette.inkText(0.8) == palette.ink(0.8))
        #expect(palette.inkText(0.4) == palette.ink(Palette.readableInk))
    }

    /// The due chip's four tints are the one place a colour pair is chosen by
    /// hand rather than derived from ink, and the neutral one — a date far
    /// enough out to be only a date — was the one that failed, at 3.95:1.
    @Test func theDueChipIsReadableAtEveryUrgencyInEitherScheme() {
        for scheme in [ColorScheme.light, .dark] {
            let palette = Palette(colorScheme: scheme)
            for role in [ColumnRole.backlog, .done] {
                for urgency in [DueUrgency.overdue, .today, .soon, .later] {
                    let tone = palette.dueTone(urgency: urgency, role: role)
                    let ground = composite(tone.background, over: palette.card)
                    let text = composite(
                        tone.foreground,
                        over: Color(
                            .sRGB, red: Double(ground.red), green: Double(ground.green),
                            blue: Double(ground.blue), opacity: 1
                        )
                    )
                    let ratio = contrast(text, ground)
                    #expect(ratio >= 4.5, "\(urgency)/\(role) in \(scheme) is \(ratio):1")
                }
            }
        }
    }
}

/// What a reader gets when the hue is not available to them, and what they get
/// when they have asked for less movement.
@MainActor @Suite struct AccessibilityAdaptationTests {
    /// Priority was a coloured dot and nothing else. Three tints, one shape:
    /// in greyscale a card said nothing about how urgent it was.
    @Test func thePriorityMarksAreThreeDifferentShapes() {
        let marks = Priority.allCases.map { PriorityDot.mark(for: $0) }
        #expect(Set(marks).count == Priority.allCases.count)
        #expect(PriorityDot.mark(for: .high) == .disc)
        #expect(PriorityDot.mark(for: .medium) == .square)
        #expect(PriorityDot.mark(for: .low) == .ring)
    }

    /// The due chip's meaning was entirely in its tint. With
    /// `differentiateWithoutColor` on it wears a glyph as well — one per state
    /// the tint distinguishes, and none for the neutral one, because a mark on
    /// every chip distinguishes nothing.
    @Test func theDueChipMarksEachUrgencyItTints() {
        #expect(DueChip.urgencySymbol(urgency: .later, role: .done) == "checkmark")
        #expect(DueChip.urgencySymbol(urgency: .overdue, role: .done) == "checkmark")
        #expect(DueChip.urgencySymbol(urgency: .overdue, role: .backlog) == "exclamationmark")
        #expect(DueChip.urgencySymbol(urgency: .today, role: .backlog) == "exclamationmark")
        #expect(DueChip.urgencySymbol(urgency: .soon, role: .backlog) == "clock")
        #expect(DueChip.urgencySymbol(urgency: .later, role: .backlog) == nil)
    }

    /// A tint the chip draws and a glyph it does not are the same failure over
    /// again, so the two are held together: every tint the palette tells apart
    /// has a mark that tells the same states apart.
    @Test func everyDistinctTintHasItsOwnMark() {
        let palette = Palette(colorScheme: .light)
        var byTint: [String: Set<String?>] = [:]
        for role in [ColumnRole.backlog, .done] {
            for urgency in [DueUrgency.overdue, .today, .soon, .later] {
                let tone = palette.dueTone(urgency: urgency, role: role)
                let key = "\(tone.background)|\(tone.foreground)"
                byTint[key, default: []].insert(DueChip.urgencySymbol(urgency: urgency, role: role))
            }
        }
        for (tint, marks) in byTint {
            #expect(marks.count == 1, "one tint, \(marks.count) marks: \(tint)")
        }
        #expect(Set(byTint.values.map { $0.first ?? nil }).count == byTint.count)
    }

    /// Reduce Motion is not a preference about taste. A `nil` animation is what
    /// SwiftUI reads as "at once", which is the point: the change still
    /// happens, it just does not travel.
    @Test func reduceMotionTakesTheAnimationAndNotTheChange() {
        #expect(Motion.animation(.easeOut(duration: 0.16), reduceMotion: true) == nil)
        #expect(Motion.animation(.easeOut(duration: 0.16), reduceMotion: false)
            == .easeOut(duration: 0.16))
        #expect(Motion.animation(nil, reduceMotion: false) == nil)
    }

    /// Differentiate Without Colour only ever *adds*.
    ///
    /// The setting is a reader saying they cannot take meaning from a hue, so
    /// every use of it in the tree is a condition on showing something more —
    /// the word beside the priority mark, the glyph in front of the due date.
    /// Negate one and the app does the exact opposite of what was asked, in a
    /// state nobody who is not using the setting will ever see; the mark and the
    /// glyph are pure functions and tested above, but which way round the flag
    /// is read is in a view body, and this is the only thing that reads it.
    @Test func theDifferentiateWithoutColorFlagIsNeverReadBackwards() {
        guard SourceTree.isReachable else { return }
        let name = Array("differentiateWithoutColor")
        var negated: [String] = []
        var read = 0
        for file in SourceTree.files() {
            // Comments are already blanked in `code`, so the prose above each
            // use is not one of these.
            let code = file.code
            guard code.count >= name.count else { continue }
            for offset in 0...(code.count - name.count) where Array(code[offset..<offset + name.count]) == name {
                read += 1
                if code[..<offset].last(where: { !$0.isWhitespace }) == "!" {
                    negated.append("\(file.path):\(file.line(of: offset))")
                }
            }
        }
        #expect(read >= 4, "\(read) reads of the flag were found — the scan is not seeing the code")
        #expect(negated.isEmpty, "Differentiate Without Colour is read negated at \(negated)")
    }

    /// The chrome's own scale never shrinks anything: the design's sizes are
    /// already the floor, and the touch minimums are stated in them.
    @Test func theChromeScaleOnlyEverGrows() {
        let chrome = ChromeScale()
        #expect(chrome(66) >= 66)
        #expect(chrome(272) >= 272)
        #expect(chrome.scaling(nil) == nil)
        #expect(chrome.scaling(336) ?? 0 >= 336)
    }
}
