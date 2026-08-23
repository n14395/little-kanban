#!/usr/bin/env swift
//
// Draws Simple Kanban's app icon and writes every slot the asset catalogue
// declares, plus the `Contents.json` that names them.
//
//     swift Tools/make-app-icon.swift            # writes into Resources/…/AppIcon.appiconset
//     swift Tools/make-app-icon.swift --out DIR  # somewhere else, e.g. to eyeball a change
//
// The mark is a **transcription of the design**, not an invention of this file:
// `simple-kanban-icon-4f.svg` — three columns of cards under their header rules,
// in white on a peach-to-violet diagonal. It is a program rather than a
// rasteriser because a rasteriser is a dependency and the drawing is nine
// rounded rectangles and a gradient; every number below is the SVG's own, in the
// SVG's own 100-unit box, so the two can be read side by side.
//
// The two platforms want different artwork from the same drawing. macOS icons
// sit in a squircle inset from the canvas and cast their own shadow, because
// the Dock draws them beside other icons that do; the iOS 1024 is full-bleed
// and opaque, because the system masks and shadows it for you.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette

/// The ground's three stops, top-left to bottom-right — the SVG's `ground`
/// gradient, offsets 0, 0.5 and 1.
let groundPeach = 0xFFB48A
let groundRose = 0xE0559B
let groundViolet = 0x7B2CD9
/// The cards and their header rules. White, and only white: the design gets its
/// depth from the ground, so a second tone in the mark would be a third idea on
/// an icon that has two.
let markWhite = 0xFFFFFF

/// **sRGB, named, everywhere** — the colours, the bitmap and the gradient alike.
///
/// `CGColor(red:green:blue:alpha:)` makes a colour in the *generic* RGB space,
/// and drawing one into a `DeviceRGB` bitmap converts it. Measured against the
/// first render of this drawing, every stop came out visibly lighter than the
/// design: #FFB48A arrived as #FEC09B, #E0559B as #E970AC, and #7B2CD9 —
/// the one that carries the icon — as #904BE0, a full step off. A hex in the
/// design has to be the hex in the file, so nothing here is left to convert.
let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: sRGB,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ]
    ) ?? CGColor(gray: 0, alpha: alpha)
}

// MARK: - Geometry

/// A superellipse, which is what an Apple icon's corners actually are — a
/// rounded rect with circular corners reads visibly tighter beside them.
/// `n = 5` is the exponent that matches the system's continuous curvature
/// closely enough that the two sit together in the Dock.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let steps = 720
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func capsulePath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

// MARK: - The mark

/// One white rectangle of the design, in the SVG's 100-unit box.
struct Bar {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
}

/// The nine rectangles, straight off `simple-kanban-icon-4f.svg`: three columns
/// at x = 20, 41 and 62, each 18 wide, each led by a 5-tall header rule at
/// y = 24, with 13-tall cards under it at y = 35, 51 and 67.
///
/// The stacks are **2, 3, 1** rather than a tidy descent, which is the whole
/// point of the drawing: a board is not a staircase, it is work piled unevenly
/// across the middle of it.
let bars: [Bar] = [
    Bar(x: 20, y: 24, width: 18, height: 5, radius: 2.5),
    Bar(x: 20, y: 35, width: 18, height: 13, radius: 3.6),
    Bar(x: 20, y: 51, width: 18, height: 13, radius: 3.6),

    Bar(x: 41, y: 24, width: 18, height: 5, radius: 2.5),
    Bar(x: 41, y: 35, width: 18, height: 13, radius: 3.6),
    Bar(x: 41, y: 51, width: 18, height: 13, radius: 3.6),
    Bar(x: 41, y: 67, width: 18, height: 13, radius: 3.6),

    Bar(x: 62, y: 24, width: 18, height: 5, radius: 2.5),
    Bar(x: 62, y: 35, width: 18, height: 13, radius: 3.6),
]

/// The three stacks as single capsules, for the sizes the cards cannot survive.
///
/// A 16pt icon is about nine points of artwork: a 13-unit card is a pixel and a
/// bit, the 3-unit gaps between cards close up entirely, and the 5-unit header
/// rule lands under half a pixel. What is left of the full drawing at that size
/// is a smudge in three vertical bands — so the small sizes are drawn *as* three
/// vertical bands, which is the same silhouette with the detail taken out and is
/// what Apple's own icons do with hand-drawn small artwork. The header rules go
/// with the gaps: at that size they are a grey haze over the top of the mark.
let stacks: [Bar] = [
    Bar(x: 20, y: 35, width: 18, height: 29, radius: 9),
    Bar(x: 41, y: 35, width: 18, height: 45, radius: 9),
    Bar(x: 62, y: 35, width: 18, height: 13, radius: 9),
]

/// How much of the mark survives at this size.
enum Detail { case full, simplified }

/// The SVG's box, which every number in `bars` is measured in.
let markUnit: CGFloat = 100

/// Draws the mark over `tile`, in a coordinate space where y grows down.
///
/// `tile` is the ground itself rather than an inset box: the design carries its
/// own margins — the columns run from 20 to 80 of the 100 — so insetting again
/// here would shrink the mark inside a border the drawing already has.
func drawMark(in context: CGContext, tile: CGRect, detail: Detail) {
    let scale = tile.width / markUnit
    context.saveGState()
    context.translateBy(x: tile.minX, y: tile.minY)
    context.scaleBy(x: scale, y: scale)
    context.setFillColor(rgb(markWhite))
    for bar in (detail == .full ? bars : stacks) {
        context.addPath(capsulePath(
            CGRect(x: bar.x, y: bar.y, width: bar.width, height: bar.height), radius: bar.radius
        ))
        context.fillPath()
    }
    context.restoreGState()
}

// MARK: - Rendering one slot

enum Platform { case mac, ios }

func render(pixels: Int, platform: Platform) -> CGImage {
    let size = CGFloat(pixels)
    let space = sRGB
    // The iOS marketing icon must have no alpha channel at all — Xcode rejects
    // one that does — so its bitmap is RGBX and ImageIO writes three channels.
    let info: CGImageAlphaInfo = platform == .ios ? .noneSkipLast : .premultipliedLast
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: info.rawValue
    ) else { fatalError("could not make a \(pixels)pt bitmap") }

    // Top-left origin, so the geometry above reads the way it is written.
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)

    // Apple's macOS grid: the artwork occupies 824 of a 1024 canvas, and the
    // space around it is where the shadow goes. iOS fills the square and lets
    // the system mask it.
    let inset = platform == .mac ? size * (100.0 / 1024.0) : 0
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = platform == .mac ? squircle(in: plate) : CGPath(rect: plate, transform: nil)

    if platform == .mac {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -size * 0.015),
            blur: size * 0.035, color: rgb(0x000000, 0.30)
        )
        context.addPath(shape)
        // Only ever seen as the shadow's caster and as the pixel under the
        // gradient's own antialiased edge, so it is the middle stop rather than
        // either end: whichever corner the edge is on, it is the nearer tone.
        context.setFillColor(rgb(groundRose))
        context.fillPath()
        context.restoreGState()
    }

    context.saveGState()
    context.addPath(shape)
    context.clip()
    // The ground, corner to corner: peach at the top left through rose at the
    // middle to violet at the bottom right, which is the SVG's `ground` and is
    // also where the system's own icons take their light from.
    if let gradient = CGGradient(
        colorsSpace: space,
        colors: [rgb(groundPeach), rgb(groundRose), rgb(groundViolet)] as CFArray,
        locations: [0, 0.5, 1]
    ) {
        context.drawLinearGradient(
            gradient, start: CGPoint(x: plate.minX, y: plate.minY),
            end: CGPoint(x: plate.maxX, y: plate.maxY), options: []
        )
    }
    drawMark(in: context, tile: plate, detail: pixels <= 32 ? .simplified : .full)
    context.restoreGState()

    guard let image = context.makeImage() else { fatalError("could not make a \(pixels)pt image") }
    return image
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else { fatalError("could not open \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

// MARK: - Slots

/// One entry of `Contents.json`, and the pixel size it needs.
struct Slot {
    var idiom: String
    var platform: String?
    var size: String
    var scale: String?
    var filename: String
    var pixels: Int
    var target: Platform
}

func macSlot(_ points: Int, _ scale: Int) -> Slot {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    return Slot(
        idiom: "mac", platform: nil, size: "\(points)x\(points)", scale: "\(scale)x",
        filename: "icon-mac-\(points)x\(points)\(suffix).png", pixels: points * scale, target: .mac
    )
}

let slots: [Slot] = [
    Slot(idiom: "universal", platform: "ios", size: "1024x1024", scale: nil,
         filename: "icon-ios-1024.png", pixels: 1024, target: .ios),
    macSlot(16, 1), macSlot(16, 2),
    macSlot(32, 1), macSlot(32, 2),
    macSlot(128, 1), macSlot(128, 2),
    macSlot(256, 1), macSlot(256, 2),
    macSlot(512, 1), macSlot(512, 2),
]

// MARK: - Main

var outputDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "Resources/Assets.xcassets/AppIcon.appiconset")
var arguments = Array(CommandLine.arguments.dropFirst())
if let index = arguments.firstIndex(of: "--out"), index + 1 < arguments.count {
    outputDirectory = URL(fileURLWithPath: arguments[index + 1])
}
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for slot in slots {
    write(render(pixels: slot.pixels, platform: slot.target), to: outputDirectory.appending(path: slot.filename))
    print("  \(slot.filename)  \(slot.pixels)px")
}

// Written here rather than by hand: a slot added above with no entry is an
// image Xcode never sees, and an entry with no image is a validation warning.
var entries: [String] = []
for slot in slots {
    var fields = ["\"filename\" : \"\(slot.filename)\"", "\"idiom\" : \"\(slot.idiom)\""]
    if let platform = slot.platform { fields.append("\"platform\" : \"\(platform)\"") }
    if let scale = slot.scale { fields.append("\"scale\" : \"\(scale)\"") }
    fields.append("\"size\" : \"\(slot.size)\"")
    entries.append("    { " + fields.joined(separator: ", ") + " }")
}
let json = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try json.write(to: outputDirectory.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("  Contents.json")
