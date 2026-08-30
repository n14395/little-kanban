import Foundation
import SwiftUI
import Testing
@testable import Simple_Kanban

/// The theme engine: the twenty the app ships with, the shape a theme is, the
/// arithmetic under it, and the file it travels in.
///
/// **Why any of this is asked at all.** A theme is data that decides what every
/// surface in the app looks like, and almost none of it can be checked by
/// looking: a gradient at 160° and one at 200° are both plausible pictures, a
/// hex that lost a digit on the way through HSB is still a colour, and a theme
/// file that silently dropped its label-chip rule still opens. The screenshot
/// proves the wiring; this proves the values.
@Suite struct ThemeTests {
    // MARK: The twenty

    /// The document's own order, which is not the order they were designed in:
    /// round two is the first section of the page. The user counts them off the
    /// page, so `1a` has to be the eleventh here too.
    @Test func thePresetsAreInTheDocumentsOrder() {
        #expect(ThemePresets.all.count == 20)
        #expect(ThemePresets.all.prefix(10).map(\.id) == ["2a", "2b", "2c", "2d", "2e", "2f", "2g", "2h", "2i", "2j"])
        #expect(ThemePresets.all.dropFirst(10).map(\.id) == ["1a", "1b", "1c", "1d", "1e", "1f", "1g", "1h", "1i", "1j"])
        #expect(ThemePresets.all[10].id == ThemePresets.emberID, "Ember is not the eleventh theme")
        #expect(ThemePresets.all[10].name == "Ember")
    }

    @Test func everyPresetIsDistinctAndFindable() {
        #expect(Set(ThemePresets.all.map(\.id)).count == 20)
        #expect(Set(ThemePresets.all.map(\.name)).count == 20)
        for theme in ThemePresets.all {
            #expect(ThemePresets.theme(theme.id) == theme)
            #expect(theme.isPreset)
        }
        #expect(ThemePresets.theme("nope") == nil)
        #expect(ThemePresets.isPresetID(UUID().uuidString) == false)
    }

    /// Eleven dark and nine light, which is what the document has — round one
    /// leaned dark and round two evened it up without quite getting there. What
    /// matters is that neither slot is left with nothing to offer.
    @Test func bothSlotsHaveSomethingToOffer() {
        let dark = ThemePresets.all.filter { $0.appearance == .dark }
        #expect(dark.count == 11)
        #expect(ThemePresets.all.count - dark.count == 9)
        #expect(ThemePresets.fallback(for: .dark).id == ThemePresets.auroraID)
        #expect(ThemePresets.fallback(for: .light).id == ThemePresets.porcelainID)
        #expect(ThemePresets.fallback(for: .light).appearance == .light)
    }

    /// **The transcription, spot-checked against the document.** Ember is the
    /// one to check because it is the reference point — the shipping theme,
    /// tuned — and every other preset was transcribed by the same script from
    /// the same page.
    @Test func emberIsTheDocumentsEmber() throws {
        let ember = try #require(ThemePresets.theme("1a"))
        #expect(ember.appearance == .dark)
        #expect(ember.displayFont.family == "Instrument Serif")
        #expect(ember.uiFont.family == "Manrope")
        #expect(ember.windowBackground.angle == 160)
        #expect(ember.windowBackground.stops.map(\.color.hex) == [0x2A1E15, 0x17110D, 0x0D0A08])
        #expect(ember.windowBackground.stops.map(\.location) == [0, 0.55, 1])
        #expect(ember.panelOverlay == ThemeColor(0x000000, opacity: 0.32))
        #expect(ember.card.fill == ThemeColor(0x28211A))
        #expect(ember.card.border == ThemeColor(0xF3EDE4, opacity: 0.08))
        #expect(ember.card.radius == 11)
        #expect(ember.ink.base == ThemeColor(0xF3EDE4))
        #expect(ember.ink.muted == 0.62)
        #expect(ember.ink.faint == 0.4)
        #expect(ember.wash == ThemeColor(0xF3EDE4, opacity: 0.09))
        #expect(ember.highlight.accent == ThemeColor(0xE8703F))
        #expect(ember.highlight.soft == ThemeColor(0xE8703F, opacity: 0.16))
        #expect(ember.highlight.onAccent == ThemeColor(0xFFF7F2))
        #expect(ember.status.done == ThemeColor(0x58B896))
        #expect(ember.status.medium == ThemeColor(0xE2B33C))
        #expect(ember.dueChips.hot.background == ThemeColor(0xF05A5A, opacity: 0.22))
        #expect(ember.dueChips.warm.foreground == ThemeColor(0xF0B7BE))
    }

    /// The two the document sets in italic, and the one whose gradient has four
    /// stops rather than three — the shapes a transcription is most likely to
    /// flatten.
    @Test func theAwkwardPresetsSurvivedTranscription() throws {
        #expect(try #require(ThemePresets.theme("1j")).displayFont.isItalic, "Midnight Gold is not italic")
        #expect(try #require(ThemePresets.theme("2h")).displayFont.isItalic, "Porcelain is not italic")
        #expect(ThemePresets.all.filter(\.displayFont.isItalic).count == 2)

        let neon = try #require(ThemePresets.theme("2g"))
        #expect(neon.windowBackground.stops.count == 4)
        #expect(neon.windowBackground.stops.map(\.location) == [0, 0.45, 0.78, 1])

        // Eclipse's ground is the only one that runs upwards, and its last stop
        // is at 62% rather than 100 — a gradient that stops short.
        let eclipse = try #require(ThemePresets.theme("2j"))
        #expect(eclipse.windowBackground.angle == 0)
        #expect(eclipse.windowBackground.stops.last?.location == 0.62)
    }

    /// A preset naming a face nobody has would fall back to a system font, which
    /// is a theme that does not look like the theme.
    @Test func everyPresetsFacesAreBundled() {
        for theme in ThemePresets.all {
            #expect(FontCatalog.isBundled(theme.displayFont.family),
                    "\(theme.name)'s display face \(theme.displayFont.family) is not bundled")
            #expect(FontCatalog.isBundled(theme.uiFont.family),
                    "\(theme.name)'s UI face \(theme.uiFont.family) is not bundled")
        }
    }

    /// Every family, at every weight the app asks for, resolves to a real face.
    /// Fifteen of the seventeen are variable fonts whose per-weight names
    /// CoreText fabricates — `WorkSansRoman-ExtraBold`, `DMSans-9ptRegular_Bold`
    /// — and a family that failed to register comes back `nil` here rather than
    /// looking slightly wrong on screen.
    @Test func everyBundledFaceResolvesAtEveryWeight() {
        for family in FontCatalog.bundledFamilies {
            for weight in [400, 500, 600, 700, 800] {
                #expect(FontCatalog.postScriptName(family: family, weight: weight, italic: false) != nil,
                        "\(family) has no face at \(weight)")
            }
        }
        #expect(FontCatalog.postScriptName(family: "Not A Font", weight: 400, italic: false) == nil)
        // The two the presets need a real italic of.
        #expect(FontCatalog.hasItalic("Instrument Serif"))
        #expect(FontCatalog.hasItalic("Newsreader"))
    }

    // MARK: Colours

    @Test func aColourIsWrittenAsAHexAndReadBack() throws {
        #expect(ThemeColor(0x2A1E15).cssString == "#2A1E15")
        #expect(ThemeColor(0x000000, opacity: 0.32).cssString == "#00000052")

        for text in ["#2A1E15", "2a1e15", " #2A1E15 "] {
            #expect(ThemeColor(css: text) == ThemeColor(0x2A1E15), "\(text) did not read")
        }
        // The spelling the document is written in.
        #expect(ThemeColor(css: "rgba(243,237,228,0.08)") == ThemeColor(0xF3EDE4, opacity: 0.08))
        #expect(ThemeColor(css: "rgb(0, 0, 0)") == ThemeColor(0x000000))
        #expect(ThemeColor(css: "#C53") == ThemeColor(0xCC5533))
    }

    /// Refused rather than salvaged, for ``ColorMathTests``' reason: a theme file
    /// with a typo in it should say so at the point of import.
    @Test func nonsenseIsNotAColour() {
        for junk in ["", "#", "#12345", "rgba(300,0,0,1)", "rgba(0,0,0)x", "rebeccapurple", "#GG0000"] {
            #expect(ThemeColor(css: junk) == nil, "\(junk) read as a colour")
        }
    }

    @Test func opacityRoundTripsThroughEightDigits() {
        for opacity in [0.0, 0.08, 0.32, 0.5, 0.88, 1.0] {
            let written = ThemeColor(0x123456, opacity: opacity).cssString
            let read = ThemeColor(css: written)
            #expect(read?.hex == 0x123456)
            #expect(abs((read?.opacity ?? -1) - opacity) < 0.005, "\(written) came back at \(read?.opacity ?? -1)")
        }
    }

    @Test func aTranslucentColourFlattensOntoWhatIsBehindIt() {
        // Half of white over black is mid-grey, both ways round.
        #expect(ThemeColor(0xFFFFFF, opacity: 0.5).composited(over: ThemeColor(0x000000)) == ThemeColor(0x808080))
        #expect(ThemeColor(0x000000, opacity: 0).composited(over: ThemeColor(0x123456)) == ThemeColor(0x123456))
        // Opaque already: nothing behind it shows, and the alpha is spent.
        #expect(ThemeColor(0xABCDEF).composited(over: ThemeColor(0x000000)) == ThemeColor(0xABCDEF))
    }

    // MARK: The gradient

    /// CSS measures its angle from *up*, turning clockwise. SwiftUI wants two
    /// points. The four on the axes are exact and are what the conversion is
    /// pinned to; a sign error anywhere here turns every theme upside down.
    @Test func theGradientAngleIsTheOneCssMeans() {
        func ends(_ angle: Double) -> (UnitPoint, UnitPoint) {
            let gradient = ThemeGradient(angle, (ThemeColor(0), 0), (ThemeColor(0xFFFFFF), 1))
            return (gradient.startPoint, gradient.endPoint)
        }
        func near(_ point: UnitPoint, _ x: Double, _ y: Double) -> Bool {
            abs(point.x - x) < 0.001 && abs(point.y - y) < 0.001
        }
        // 0° runs upwards: it starts at the bottom.
        #expect(near(ends(0).0, 0.5, 1) && near(ends(0).1, 0.5, 0))
        #expect(near(ends(90).0, 0, 0.5) && near(ends(90).1, 1, 0.5))
        #expect(near(ends(180).0, 0.5, 0) && near(ends(180).1, 0.5, 1))
        #expect(near(ends(270).0, 1, 0.5) && near(ends(270).1, 0, 0.5))
        // 135° points down and to the right, and on a square it lands exactly on
        // that corner — CSS's own answer, since the gradient line is as long as
        // the projection of the corners onto it.
        #expect(near(ends(135).1, 1, 1))
        #expect(near(ends(135).0, 0, 0))
        // Off the diagonal it reaches *past* the frame, for the same reason —
        // Ember's 160° ground runs from above the top edge to below the bottom.
        #expect(ends(160).1.y > 1)
    }

    /// A flat ground is a gradient with one stop, so there is no second case to
    /// hold — but `Gradient` needs two ends to interpolate between.
    @Test func oneStopIsAFlatGround() {
        let flat = ThemeGradient.flat(ThemeColor(0x123456))
        #expect(flat.stops.count == 1)
        #expect(flat.gradient.stops.count == 2)
        #expect(flat.representative == ThemeColor(0x123456))
        // And a gradient can never be emptied down to no colour at all.
        #expect(ThemeGradient(angle: 90, stops: []).stops.count == 1)
    }

    /// The one colour that stands for the window where a gradient cannot be
    /// drawn: the stop nearest the middle of the run, because that is what most
    /// of the window is wearing.
    @Test func theRepresentativeStopIsTheMiddleOne() throws {
        let ember = try #require(ThemePresets.theme("1a"))
        #expect(ember.windowBackground.representative == ThemeColor(0x17110D))
    }

    // MARK: The two slots

    @Test func aThemeGoesInTheSlotItsOwnKindNames() throws {
        var settings = ThemeSettings.seed
        let ember = try #require(ThemePresets.theme("1a"))    // dark, not the seed's
        let daybreak = try #require(ThemePresets.theme("1c")) // light

        settings.select(ember)
        #expect(settings.darkID == "1a")
        #expect(settings.lightID == ThemePresets.porcelainID, "a dark theme moved the light slot")

        settings.select(daybreak)
        #expect(settings.lightID == "1c")
        #expect(settings.darkID == "1a")
        #expect(settings.theme(for: .dark) == ember)
        #expect(settings.theme(for: .light) == daybreak)
    }

    /// A slot naming a theme this machine has never seen — a board file copied
    /// from one that had a custom theme — resolves to the preset rather than
    /// leaving the app with no colours at all.
    @Test func aSlotNamingNothingFallsBack() {
        var settings = ThemeSettings(lightID: "gone", darkID: "also-gone")
        #expect(settings.theme(for: .light).id == ThemePresets.porcelainID)
        #expect(settings.theme(for: .dark).id == ThemePresets.auroraID)

        // And a slot naming a theme that has since been flipped to the other
        // kind, which is the same hole reached from inside.
        var flipped = ThemePresets.fallback(for: .dark).duplicated(named: "Mine")
        settings.select(flipped)
        flipped.appearance = .light
        settings.save(flipped)
        #expect(settings.theme(for: .dark).id == ThemePresets.auroraID)
    }

    /// A reference point that can be overwritten is not one.
    @Test func aPresetCannotBeSavedOverOrDeleted() throws {
        var settings = ThemeSettings.seed
        var aurora = try #require(ThemePresets.theme("1b"))
        aurora.name = "Not Aurora"
        #expect(settings.save(aurora) == false)
        #expect(settings.custom.isEmpty)
        #expect(settings.theme(for: .dark).name == "Aurora")
        #expect(settings.delete("1b") == false)
    }

    @Test func savingTwiceReplacesRatherThanDuplicates() {
        var settings = ThemeSettings.seed
        var mine = ThemePresets.fallback(for: .dark).duplicated(named: "Mine")
        settings.save(mine)
        mine.name = "Mine, edited"
        settings.save(mine)
        #expect(settings.custom.count == 1)
        #expect(settings.custom.first?.name == "Mine, edited")
    }

    @Test func aDuplicateGetsAnIdentityAndANameOfItsOwn() throws {
        var settings = ThemeSettings.seed
        let ember = try #require(ThemePresets.theme("1a"))
        let copy = ember.duplicated(named: settings.unusedName(basedOn: ember.name))
        #expect(copy.id != ember.id)
        #expect(copy.name == "Ember 2")
        #expect(copy.isPreset == false)
        // Everything else about it is Ember.
        #expect(copy.windowBackground == ember.windowBackground)

        settings.save(copy)
        #expect(settings.unusedName(basedOn: "Ember") == "Ember 3")
        #expect(settings.unusedName(basedOn: "Unheard Of") == "Unheard Of")
    }

    // MARK: What a theme paints

    /// The accent *swatch* is pinned: a board dot painted "Accent" is the same
    /// colour on every theme, while the themes' own accents — the app's chrome —
    /// still differ underneath it.
    @Test func theAccentSwatchIsPinned() throws {
        let ember = Palette(theme: try #require(ThemePresets.theme("1a")))
        let aurora = Palette(theme: try #require(ThemePresets.theme("1b")))
        #expect(ember.accentValue == 0xE8703F)
        #expect(aurora.accentValue == 0x4FE3C1)
        #expect(ember.resolve(.accent) == aurora.resolve(.accent))
        #expect(ember.resolve(.accent) == Color(hex: SwatchColor.accentHex))
        #expect(aurora.resolve(.ink(opacity: 0.35)) == Color(hex: SwatchColor.inkHex, opacity: 0.35))
    }

    /// Max priority takes the overdue chip's own hue rather than a fifth tone of
    /// the accent — the app has one alarm colour and it is said once.
    @Test func maxPriorityIsTheOverdueHue() throws {
        for theme in ThemePresets.all {
            let palette = Palette(theme: theme)
            #expect(palette.priorityColor(.max) == theme.dueChips.hot.background.solid.color,
                    "\(theme.name)'s max priority is not its overdue hue")
            #expect(palette.priorityColor(.high) == palette.accent)
            #expect(palette.priorityColor(.medium) == theme.status.medium.color)
        }
    }

    /// Anything further out than soon takes "wash / muted", which is the
    /// document's own line — and a *finished* task takes the done hue through
    /// the label chip rule rather than through two more literals.
    @Test func theDueChipsAreTheThemes() throws {
        let theme = try #require(ThemePresets.theme("1a"))
        let palette = Palette(theme: theme)
        #expect(palette.dueTone(urgency: .overdue, isDone: false).background == theme.dueChips.hot.background.color)
        #expect(palette.dueTone(urgency: .today, isDone: false).foreground == theme.dueChips.hot.foreground.color)
        #expect(palette.dueTone(urgency: .soon, isDone: false).background == theme.dueChips.warm.background.color)
        #expect(palette.dueTone(urgency: .later, isDone: false).background == palette.wash)
        #expect(palette.dueTone(urgency: .overdue, isDone: true).background
                == palette.chipTone(for: .hex(theme.status.done.hex)).background)
    }

    /// **The theme carries the recipe, not the colours.** Two themes with the
    /// same label in front of them draw two different chips, and both are the
    /// label's own colour.
    @Test func aLabelsChipIsItsOwnColourThroughTheThemesRule() throws {
        let dark = Palette(theme: try #require(ThemePresets.theme("1a")))
        let light = Palette(theme: try #require(ThemePresets.theme("2h")))
        let colour: SwatchColor = .hex(0x1F6F63)

        #expect(dark.chipTone(for: colour).background != light.chipTone(for: colour).background)
        // The dark ground is lifted before it is tinted, so it is lighter than
        // the colour it came from — a 19% wash of a deep green over a near-black
        // card is very nearly the card.
        #expect(ColorMath.luminance(of: ColorMath.shade(0x1F6F63, by: dark.theme.labelChips.backgroundLift))
                > ColorMath.luminance(of: 0x1F6F63))
        #expect(light.theme.labelChips.backgroundLift == 0)

        // The grey label goes through the same rule as any other colour, from
        // the pinned grey rather than the theme's ink.
        #expect(dark.chipTone(for: .ink(opacity: 0.35)).background
                == dark.chipTone(for: .hex(SwatchColor.inkHex)).background)
    }

    /// A theme cannot make text unreadable, however low it sets its ink tiers.
    /// The tiers are still used exactly as written for what is *not* text.
    @Test func theContrastFloorIsNotATheme() throws {
        var theme = try #require(ThemePresets.theme("1a"))
        theme.ink.muted = 0.1
        theme.ink.faint = 0.05
        let palette = Palette(theme: theme)
        #expect(palette.inkText(theme.ink.muted) == palette.ink(Palette.readableInk))
        #expect(palette.inkMuted == palette.ink(0.1), "a rule is not text and takes the theme's own number")
        #expect(palette.inkFaint == palette.ink(0.05))
    }

    // MARK: The file

    @Test func aThemeSurvivesTheRoundTripThroughItsFile() throws {
        for theme in ThemePresets.all {
            let data = try ThemeDocument([theme]).encoded()
            #expect(try ThemeDocument.decode(data) == [theme], "\(theme.name) did not come back whole")
        }
    }

    /// Three shapes read, one written: what this app writes, a bare array, and a
    /// bare object — the last two being what somebody who wrote a theme by hand
    /// is likely to hand it.
    @Test func aHandWrittenThemeFileIsAccepted() throws {
        let theme = try #require(ThemePresets.theme("2b"))
        let encoder = JSONEncoder()
        #expect(try ThemeDocument.decode(try encoder.encode(theme)) == [theme])
        #expect(try ThemeDocument.decode(try encoder.encode([theme, theme])).count == 2)
    }

    @Test func aBrokenThemeFileSaysWhatIsWrongWithIt() throws {
        #expect(throws: ThemeFileError.self) {
            try ThemeDocument.decode(Data("not json at all".utf8))
        }
        #expect(throws: ThemeFileError.empty) {
            try ThemeDocument.decode(Data(#"{"format":"com.n14395.SimpleKanban.theme","version":1,"themes":[]}"#.utf8))
        }
        // A colour with a typo in it names the field it is in rather than
        // throwing a Swift type name at somebody editing a hex.
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(try #require(ThemePresets.theme("1a")))
        ) as? [String: Any] ?? [:]
        json["wash"] = "#not-a-colour"
        let broken = try JSONSerialization.data(withJSONObject: json)
        do {
            _ = try ThemeDocument.decode(broken)
            Issue.record("a theme with a broken colour in it was accepted")
        } catch let error as ThemeFileError {
            #expect(error.errorDescription?.contains("wash") == true,
                    "the complaint does not name the field: \(error.errorDescription ?? "")")
        }
    }

    /// The export is meant to be opened in a text editor, so it is
    /// pretty-printed, its keys are in order, and its colours are hexes rather
    /// than three fields each.
    @Test func theExportIsSomethingAPersonCanEdit() throws {
        let text = String(decoding: try ThemeDocument([try #require(ThemePresets.theme("1a"))]).encoded(), as: UTF8.self)
        #expect(text.contains("\n"), "the export is one line")
        #expect(text.contains("\"#E8703F\""), "a colour is not written as a hex")
        #expect(text.contains("\"format\" : \"com.n14395.SimpleKanban.theme\""))
    }
}
