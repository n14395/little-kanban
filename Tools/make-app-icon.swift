// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

//
// Draws every app icon Little Kanban ships with and writes the asset catalogue
// that names them.
//
//     Tools/make-app-icons                 # writes into Resources/Assets.xcassets
//     Tools/make-app-icons --out DIR       # somewhere else, to eyeball a change
//
// **It compiles the app's own theme sources**, which is why there is a shell
// script beside it rather than a `swift Tools/make-app-icon.swift` shebang. The
// ten grounds are `AppIcon.all`, the twenty theme-matched icons are derived from
// `ThemePresets` by `AppIcon.art(matching:)`, and the nine rectangles are
// `AppIconArtwork`. Nothing about the drawing is restated here: a number
// transcribed into this file is a number that can disagree with the picker, and
// the whole point of the picker is that the tile is what you get.
//
// What *is* here is rasterisation, which the app never does — the two platforms
// want different artwork from the same drawing. macOS icons sit in a squircle
// inset from the canvas and cast their own shadow, because the Dock draws them
// beside other icons that do; the iOS artwork is full-bleed and opaque, because
// the system masks and shadows it for you.
//
// The alternates are **iOS only**. macOS has no `setAlternateIconName`: the desk
// renders its Dock icon at run time from the same `AppIconArt` (see
// `AppIconInstaller`), so a macOS slot in an alternate set would be an icon
// nothing can ever ask for.

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Colour

/// **sRGB, named, everywhere** — the colours, the bitmap and the gradient alike.
///
/// `CGColor(red:green:blue:alpha:)` makes a colour in the *generic* RGB space,
/// and drawing one into a `DeviceRGB` bitmap converts it. Measured against the
/// first render of this drawing, every stop came out visibly lighter than the
/// design: #FFB48A arrived as #FEC09B, #E0559B as #E970AC, and #7B2CD9 —
/// the one that carries the icon — as #904BE0, a full step off. A hex in the
/// design has to be the hex in the file, so nothing here is left to convert.
let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

func cgColor(_ colour: ThemeColor) -> CGColor {
    CGColor(
        colorSpace: sRGB,
        components: [
            CGFloat((colour.hex >> 16) & 0xFF) / 255,
            CGFloat((colour.hex >> 8) & 0xFF) / 255,
            CGFloat(colour.hex & 0xFF) / 255,
            CGFloat(colour.opacity),
        ]
    ) ?? CGColor(gray: 0, alpha: 1)
}

func capsulePath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

// MARK: - The mark

/// Draws the mark over `tile`, in a coordinate space where y grows down.
///
/// `tile` is the ground itself rather than an inset box: the design carries its
/// own margins — the columns run from 20 to 80 of the 100 — so insetting again
/// here would shrink the mark inside a border the drawing already has.
func drawMark(in context: CGContext, tile: CGRect, art: AppIconArt, simplified: Bool) {
    let scale = tile.width / AppIconArtwork.unit
    context.saveGState()
    context.translateBy(x: tile.minX, y: tile.minY)
    context.scaleBy(x: scale, y: scale)
    let runs: [(bars: [AppIconArtwork.Bar], colour: ThemeColor)] = simplified
        ? [(AppIconArtwork.stacks, art.card)]
        : [(AppIconArtwork.headers, art.cap), (AppIconArtwork.cards, art.card)]
    for run in runs {
        context.setFillColor(cgColor(run.colour))
        for bar in run.bars {
            context.addPath(capsulePath(
                CGRect(x: bar.x, y: bar.y, width: bar.width, height: bar.height),
                radius: bar.radius
            ))
            context.fillPath()
        }
    }
    context.restoreGState()
}

// MARK: - Rendering one slot

enum Platform { case mac, ios }

func render(_ art: AppIconArt, pixels: Int, platform: Platform) -> CGImage {
    let size = CGFloat(pixels)
    // The iOS marketing icon must have no alpha channel at all — Xcode rejects
    // one that does — so its bitmap is RGBX and ImageIO writes three channels.
    let info: CGImageAlphaInfo = platform == .ios ? .noneSkipLast : .premultipliedLast
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: info.rawValue
    ) else { fatalError("could not make a \(pixels)pt bitmap") }

    // Top-left origin, so the geometry reads the way the design writes it.
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)

    // Apple's macOS grid: the artwork occupies 824 of a 1024 canvas, and the
    // space around it is where the shadow goes. iOS fills the square and lets
    // the system mask it.
    let inset = platform == .mac ? size * (100.0 / 1024.0) : 0
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = platform == .mac
        ? AppIconArtwork.squircle(in: plate)
        : CGPath(rect: plate, transform: nil)

    if platform == .mac {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -size * 0.015),
            blur: size * 0.035, color: CGColor(gray: 0, alpha: 0.30)
        )
        context.addPath(shape)
        // Only ever seen as the shadow's caster and as the pixel under the
        // gradient's own antialiased edge, so it is the stop nearest the middle
        // of the run: whichever corner the edge is on, that is the nearer tone.
        context.setFillColor(cgColor(art.ground.representative.solid))
        context.fillPath()
        context.restoreGState()
    }

    context.saveGState()
    context.addPath(shape)
    context.clip()
    drawGround(art.ground, in: context, over: plate)
    drawMark(
        in: context, tile: plate, art: art,
        simplified: pixels < AppIconArtwork.simplifiedBelow
    )
    context.restoreGState()

    guard let image = context.makeImage() else { fatalError("could not make a \(pixels)pt image") }
    return image
}

/// The ground, at the angle the theme states it in.
///
/// The two ends come from ``ThemeGradient/points``, which is the same pair the
/// app's `Canvas` draws with — so the tile in the picker and the icon in the
/// bundle are lit from the same corner.
///
/// **Both extend options, always.** A `UnitPoint` outside 0…1 is ordinary here:
/// the CSS angles the twenty themes are written in put the ends of the gradient
/// line off the box on anything but the axes and the diagonals. Without these
/// Core Graphics leaves everything past the last stop unpainted, which on
/// Oxblood's 155° is a bare wedge in two corners.
func drawGround(_ ground: ThemeGradient, in context: CGContext, over plate: CGRect) {
    let colours = ground.stops.map { cgColor($0.color) } as CFArray
    let locations = ground.stops.map { CGFloat($0.location) }
    guard let gradient = CGGradient(colorsSpace: sRGB, colors: colours, locations: locations) else {
        context.setFillColor(cgColor(ground.representative.solid))
        context.fill(plate)
        return
    }
    let (start, end) = ground.points
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.minX + start.x * plate.width, y: plate.minY + start.y * plate.height),
        end: CGPoint(x: plate.minX + end.x * plate.width, y: plate.minY + end.y * plate.height),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("could not open \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

// MARK: - Slots

/// One entry of a set's `Contents.json`, and the pixel size it needs.
struct Slot {
    var idiom: String
    var platform: String?
    var size: String
    var scale: String?
    var suffix: String
    var pixels: Int
    var target: Platform
}

func macSlot(_ points: Int, _ scale: Int) -> Slot {
    Slot(
        idiom: "mac", platform: nil, size: "\(points)x\(points)", scale: "\(scale)x",
        suffix: "mac-\(points)x\(points)\(scale == 1 ? "" : "@\(scale)x")",
        pixels: points * scale, target: .mac
    )
}

func phoneSlot(_ scale: Int) -> Slot {
    Slot(idiom: "iphone", platform: nil, size: "60x60", scale: "\(scale)x",
         suffix: "iphone-60x60@\(scale)x", pixels: 60 * scale, target: .ios)
}

/// What the built-in icon needs: every macOS size the Dock and Finder ask for,
/// and the single 1024 iOS artwork the modern catalogue takes.
let defaultSlots: [Slot] = [
    Slot(idiom: "universal", platform: "ios", size: "1024x1024", scale: nil,
         suffix: "ios-1024", pixels: 1024, target: .ios),
    macSlot(16, 1), macSlot(16, 2),
    macSlot(32, 1), macSlot(32, 2),
    macSlot(128, 1), macSlot(128, 2),
    macSlot(256, 1), macSlot(256, 2),
    macSlot(512, 1), macSlot(512, 2),
]

/// What an alternate needs, which is much less.
///
/// **The classic per-idiom sizes rather than one 1024.** An alternate icon is
/// never shown in the App Store and never rendered above the Home Screen's own
/// size, so the 1024 would be four hundred kilobytes of nothing — measured, a
/// full set of these is around a twentieth of one 1024 slot, and there are
/// twenty-nine of them. macOS gets nothing here for the reason at the top of
/// this file.
let alternateSlots: [Slot] = [
    phoneSlot(2), phoneSlot(3),
    Slot(idiom: "ipad", platform: nil, size: "76x76", scale: "2x",
         suffix: "ipad-76x76@2x", pixels: 152, target: .ios),
    Slot(idiom: "ipad", platform: nil, size: "83.5x83.5", scale: "2x",
         suffix: "ipad-83.5x83.5@2x", pixels: 167, target: .ios),
]

func contentsJSON(_ slots: [Slot], filename: (Slot) -> String) -> String {
    var entries: [String] = []
    for slot in slots {
        var fields = ["\"filename\" : \"\(filename(slot))\"", "\"idiom\" : \"\(slot.idiom)\""]
        if let platform = slot.platform { fields.append("\"platform\" : \"\(platform)\"") }
        if let scale = slot.scale { fields.append("\"scale\" : \"\(scale)\"") }
        fields.append("\"size\" : \"\(slot.size)\"")
        entries.append("    { " + fields.joined(separator: ", ") + " }")
    }
    return """
    {
      "images" : [
    \(entries.joined(separator: ",\n"))
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """
}

// MARK: - Main

/// `@main` rather than top-level code, because Swift only allows statements at
/// the top level in a file called `main.swift` — and this one is compiled
/// alongside the app's theme sources, which is the whole arrangement. See
/// `Tools/make-app-icons`.
@main
enum MakeAppIcon {
    static func main() throws {
        var catalogueDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Assets.xcassets")
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let index = arguments.firstIndex(of: "--out"), index + 1 < arguments.count {
            catalogueDirectory = URL(fileURLWithPath: arguments[index + 1])
        }

        let fileManager = FileManager.default
        var written = 0

        for asset in AppIcon.catalogue {
            let slots = asset.isDefault ? defaultSlots : alternateSlots
            let directory = catalogueDirectory.appending(path: "\(asset.assetName).appiconset")
            // Emptied rather than merged: a slot dropped from the lists above
            // would otherwise stay on disk for ever, and Xcode warns about an
            // image that no entry names.
            try? fileManager.removeItem(at: directory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            // The filenames carry the set's name, so that thirty sets in one
            // Finder window are still telling you which is which.
            let name = { (slot: Slot) in "\(asset.assetName)-\(slot.suffix).png" }
            for slot in slots {
                write(
                    render(asset.art, pixels: slot.pixels, platform: slot.target),
                    to: directory.appending(path: name(slot))
                )
                written += 1
            }
            // Written here rather than by hand: a slot added above with no entry
            // is an image Xcode never sees, and an entry with no image is a
            // validation warning.
            try contentsJSON(slots, filename: name).write(
                to: directory.appending(path: "Contents.json"), atomically: true, encoding: .utf8
            )
            print("  \(asset.assetName).appiconset  \(slots.count) images")
        }

        print("\(AppIcon.catalogue.count) icon sets, \(written) images")
    }
}
