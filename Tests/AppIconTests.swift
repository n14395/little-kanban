// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import LittleKanban

/// The icon the app wears, and the two switches that choose it.
///
/// The drawing itself is not tested here — it is a `Canvas` and a rasteriser,
/// and the guard on *that* is that `Tools/make-app-icons` reproduces the
/// shipping `AppIcon.appiconset` byte for byte from these same numbers. What is
/// tested is the arithmetic under it: which icon a pair of switches resolves
/// to, what it is called in the bundle, and that the mark is still the nine
/// rectangles the design document draws.
@MainActor
@Suite struct AppIconTests {
    // MARK: The ten

    /// The document's fourth round is ten grounds with ids `4a`…`4j`, and the
    /// app ships wearing one of them.
    @Test func theTenAreTheDocumentsTenAndTheDefaultIsAmongThem() {
        #expect(AppIcon.all.count == 10)
        #expect(AppIcon.all.map(\.id) == ["4a", "4b", "4c", "4d", "4e", "4f", "4g", "4h", "4i", "4j"])
        #expect(AppIcon.gradient(AppIcon.defaultID)?.name == "Teal → chartreuse")
        #expect(AppIcon.fallback.id == AppIcon.defaultID)
    }

    /// Every ground is three stops at nought, a half and one — the round's own
    /// rule — and every mark is one colour, which is what "no stepped opacity"
    /// meant when the round dropped it.
    @Test func everyGroundIsThreeStopsAndEveryMarkIsOneColour() {
        for icon in AppIcon.all {
            #expect(icon.art.ground.stops.map(\.location) == [0, 0.5, 1], "\(icon.id)")
            #expect(icon.art.cap == icon.art.card, "\(icon.id) draws its caps and cards apart")
            #expect(icon.art.ground.stops.allSatisfy { $0.color.opacity == 1 }, "\(icon.id)")
        }
    }

    /// An id from a build that had other grounds — or from nothing at all —
    /// falls back rather than leaves the app faceless, the same way a slot
    /// naming an uninstalled theme does.
    @Test func anUnknownGroundFallsBackToTheOneTheAppShipsWith() {
        let resolved = AppIcon.resolve(
            AppIconSelection(gradientID: "9z", followsTheme: false),
            themes: .seed, appearance: .dark
        )
        #expect(resolved.name == AppIcon.fallback.name)
        #expect(resolved.assetName == nil)
    }

    // MARK: Icons from themes

    /// **The design's rule, not a transcription of its output**: the window
    /// gradient is the ground, the highlight is the caps, the ink is the cards.
    @Test func aThemesIconIsItsWindowItsHighlightAndItsInk() {
        let theme = ThemePresets.theme(ThemePresets.emberID)!
        let art = AppIcon.art(matching: theme)
        #expect(art.ground.stops.map(\.color.hex) == theme.windowBackground.stops.map(\.color.hex))
        #expect(art.ground.angle == theme.windowBackground.angle)
        #expect(art.cap.hex == theme.highlight.accent.hex)
        #expect(art.card.hex == theme.ink.base.hex)
    }

    /// An icon has nothing behind it, so a stop with an alpha would be a hole
    /// rather than a tint. The twenty are opaque already; a theme somebody
    /// builds in the editor need not be.
    @Test func aThemeWithATranslucentInkStillDrawsAnOpaqueIcon() {
        var theme = ThemePresets.theme(ThemePresets.emberID)!.duplicated(named: "Mine")
        theme.ink.base = ThemeColor(0xFFFFFF, opacity: 0.4)
        theme.windowBackground = ThemeGradient(
            160, (ThemeColor(0x101010, opacity: 0.2), 0), (ThemeColor(0x000000), 1)
        )
        let art = AppIcon.art(matching: theme)
        #expect(art.card.opacity == 1)
        #expect(art.ground.stops.allSatisfy { $0.color.opacity == 1 })
    }

    // MARK: Which one is worn

    /// With the switch on, the icon is the theme in the slot the *appearance*
    /// names — not the dark one, and not whichever was chosen last.
    @Test func followingTheThemeTracksTheSlotTheAppearanceNames() {
        let themes = ThemeSettings(lightID: "2b", darkID: "1d")
        let selection = AppIconSelection(gradientID: "4a", followsTheme: true)

        let dark = AppIcon.resolve(selection, themes: themes, appearance: .dark)
        #expect(dark.name == "Ultraviolet")
        #expect(dark.assetName == "AppIcon-theme-1d")

        let light = AppIcon.resolve(selection, themes: themes, appearance: .light)
        #expect(light.name == "Glacier")
        #expect(light.assetName == "AppIcon-theme-2b")
    }

    /// And with it off the ten are back, whatever the theme is.
    @Test func theChosenGroundIsWornWhateverTheThemeIs() {
        let themes = ThemeSettings(lightID: "2b", darkID: "1d")
        let resolved = AppIcon.resolve(
            AppIconSelection(gradientID: "4c", followsTheme: false),
            themes: themes, appearance: .dark
        )
        #expect(resolved.name == "Sunrise")
        #expect(resolved.assetName == "AppIcon-4c")
    }

    /// **The one thing the phone cannot do.** A theme the user made has no icon
    /// compiled into the bundle, so iOS is asked for `nil` — the icon the app
    /// shipped with. The *art* is still right, which is what the desk draws and
    /// what the picker shows either way.
    @Test func aThemeTheUserMadeHasNoIconInTheBundle() {
        let mine = ThemePresets.theme(ThemePresets.emberID)!.duplicated(named: "Mine")
        let themes = ThemeSettings(lightID: "2h", darkID: mine.id, custom: [mine])
        let resolved = AppIcon.resolve(
            AppIconSelection(gradientID: "4a", followsTheme: true),
            themes: themes, appearance: .dark
        )
        #expect(resolved.name == "Mine")
        #expect(resolved.assetName == nil, "a name nothing in the bundle answers to")
        #expect(resolved.art.cap.hex == mine.highlight.accent.hex)
    }

    // MARK: The asset catalogue

    /// Thirty sets, not thirty-one: the built-in `AppIcon` *is* `4g`, so the ten
    /// contribute nine alternates. Every name is unique, because two sets of the
    /// same name is a catalogue that does not build.
    @Test func theCatalogueIsTheBuiltInOneAndTwentyNineAlternates() {
        let catalogue = AppIcon.catalogue
        #expect(catalogue.count == 30)
        #expect(catalogue.filter(\.isDefault).map(\.assetName) == ["AppIcon"])
        #expect(Set(catalogue.map(\.assetName)).count == catalogue.count)
        #expect(catalogue.first?.art == AppIcon.fallback.art, "the built-in set is not 4g")
        // One per preset, none for anything else.
        let themed = catalogue.filter { $0.assetName.hasPrefix("AppIcon-theme-") }
        #expect(themed.count == ThemePresets.all.count)
        #expect(!catalogue.contains { $0.assetName == "AppIcon-\(AppIcon.defaultID)" })
    }

    /// What `setAlternateIconName(_:)` is handed has to be a name the catalogue
    /// holds, or the call fails and the icon silently stays as it was.
    @Test func everyNameAnIconResolvesToIsOneTheCatalogueHolds() {
        let names = Set(AppIcon.catalogue.map(\.assetName))
        let themes = ThemeSettings.seed
        for icon in AppIcon.all {
            for appearance in ThemeAppearance.allCases {
                let resolved = AppIcon.resolve(
                    AppIconSelection(gradientID: icon.id, followsTheme: false),
                    themes: themes, appearance: appearance
                )
                #expect(resolved.assetName.map(names.contains) ?? true, "\(icon.id)")
            }
        }
        for theme in ThemePresets.all {
            var themes = ThemeSettings.seed
            themes.select(theme)
            let resolved = AppIcon.resolve(
                AppIconSelection(gradientID: AppIcon.defaultID, followsTheme: true),
                themes: themes, appearance: theme.appearance
            )
            #expect(resolved.assetName.map(names.contains) ?? false, "\(theme.id)")
        }
    }

    // MARK: The mark

    /// The nine rectangles of `little-kanban-icon-4f.svg`, which the tool
    /// rasterises and the picker draws. Derived in `AppIconArtwork` rather than
    /// transcribed, so this is the transcription — and the place a change to
    /// the drawing has to be argued for.
    @Test func theMarkIsStillTheNineRectanglesTheDesignDraws() {
        #expect(AppIconArtwork.headers.count == 3)
        #expect(AppIconArtwork.cards.count == 6)
        #expect(AppIconArtwork.cardCounts == [2, 3, 1], "a board is not a staircase")

        #expect(AppIconArtwork.headers.map(\.x) == [20, 41, 62])
        #expect(AppIconArtwork.headers.allSatisfy { $0.y == 24 && $0.height == 5 })
        #expect(AppIconArtwork.cards.map(\.x) == [20, 20, 41, 41, 41, 62])
        #expect(AppIconArtwork.cards.map(\.y) == [35, 51, 35, 51, 67, 35])
        #expect(AppIconArtwork.cards.allSatisfy { $0.width == 18 && $0.height == 13 })

        // The simplified mark is the same silhouette with the detail taken out:
        // one capsule per column, from the first card's top to the last one's
        // bottom.
        #expect(AppIconArtwork.stacks.map(\.height) == [29, 45, 13])
        #expect(AppIconArtwork.stacks.allSatisfy { $0.y == 35 })
    }

    /// **The picker draws what the bundle holds.** `AppIconMark` is a `Canvas`
    /// and `Tools/make-app-icon.swift` is Core Graphics; they share the numbers
    /// but not a line of drawing code, and a tile that disagreed with the icon
    /// it installs would make the whole picker a lie.
    ///
    /// Sampled rather than compared whole: the two rasterisers antialias
    /// differently, and an exact image match would fail on the edge of every
    /// rounded corner. These four points are nowhere near one.
    @Test func theDrawnMarkIsTheGroundInTheCornersAndTheMarkOnTheCards() throws {
        let art = AppIcon.fallback.art
        let renderer = ImageRenderer(content: AppIconMark(art: art).frame(width: 100, height: 100))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 100 && image.height == 100)

        // Corner to corner, which is where 4g's three stops are anchored — so
        // the first and last are sampled at the actual corner pixels rather
        // than a few in. An inset sample is not the stop, it is a point a few
        // per cent short of it along the ramp, and how far short that lands in
        // colour depends on how steep that particular ground is: 4g climbs
        // 195 levels of red across its second half, so three pixels in from the
        // corner is 9 levels off the stop — a real miss that the tolerance for
        // *rasteriser* differences should never have been absorbing. `AppIconMark`
        // is full bleed and unclipped, so the corner pixel is the ground.
        expect(image, at: (0, 0), isNear: 0x00696E, "the ground does not start at the teal")
        expect(image, at: (50, 50), isNear: 0x00B39A, "the ground's middle stop is not the jade")
        expect(image, at: (99, 99), isNear: 0xC3F53C, "the ground does not end at the chartreuse")
        // The middle of the first column's first card (x 20…38, y 35…48), and a
        // gap between two cards, which has to be ground and not mark.
        expect(image, at: (29, 41), isNear: 0x04231F, "the cards are not being drawn")
        // And the 3-unit gap between two cards is ground rather than mark. Its
        // exact colour is a point part-way along a gradient interpolated in a
        // space this test has no business restating, so what is asserted is the
        // thing that matters: it is nowhere near the card.
        expect(image, at: (29, 49), isFarFrom: 0x04231F, "the gap between two cards is filled in")
    }

    /// A pixel, nowhere near a colour — for the places whose exact value is not
    /// worth stating but whose *identity* is.
    private func expect(
        _ image: CGImage, at point: (x: Int, y: Int), isFarFrom hex: UInt32, _ note: String
    ) {
        guard let channels = pixel(image, at: point) else { return }
        let want = (r: Int((hex >> 16) & 0xFF), g: Int((hex >> 8) & 0xFF), b: Int(hex & 0xFF))
        let off = max(
            abs(channels.r - want.r), max(abs(channels.g - want.g), abs(channels.b - want.b))
        )
        #expect(off > 40, "\(note) — at \(point) it is very nearly #\(String(hex, radix: 16))")
    }

    /// A pixel, within a step or two — a gradient rasterised twice does not
    /// land on the same byte, and neither does one read through a colour space.
    private func expect(
        _ image: CGImage, at point: (x: Int, y: Int), isNear hex: UInt32, _ note: String,
        tolerance: Int = 6
    ) {
        guard let channels = pixel(image, at: point) else { return }
        let (red, green, blue) = (channels.r, channels.g, channels.b)
        let want = (r: Int((hex >> 16) & 0xFF), g: Int((hex >> 8) & 0xFF), b: Int(hex & 0xFF))
        let off = max(abs(red - want.r), max(abs(green - want.g), abs(blue - want.b)))
        let got = String(format: "#%02X%02X%02X", red, green, blue)
        #expect(off <= tolerance, "\(note) — at \(point) wanted #\(String(hex, radix: 16)), got \(got)")
    }

    /// RGBA, in that order: `ImageRenderer` hands back a straight `CGImage` and
    /// the `Canvas` is opaque, so alpha is 255 throughout and the three channels
    /// are read as they lie. Measured — reading them the other way round turns
    /// 4f's peach corner into a pale blue one.
    private func pixel(
        _ image: CGImage, at point: (x: Int, y: Int)
    ) -> (r: Int, g: Int, b: Int)? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            Issue.record("no pixels in the rendered icon")
            return nil
        }
        let offset = point.y * image.bytesPerRow + point.x * (image.bitsPerPixel / 8)
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }
}
