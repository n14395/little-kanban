#!/usr/bin/env swift
//
// Draws Simple Kanban's app icon and writes every slot the asset catalogue
// declares, plus the `Contents.json` that names them.
//
//     swift Tools/make-app-icon.swift            # writes into Resources/…/AppIcon.appiconset
//     swift Tools/make-app-icon.swift --out DIR  # somewhere else, e.g. to eyeball a change
//
// There is no design tool in this repository, so the icon is a program: the
// mark below is the board's own column-dot motif — a header dot over a stack of
// cards, three columns, the stacks shortening left to right the way work does —
// drawn in the palette from `Sources/Theme/Palette.swift` on the ember accent.
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

/// `Palette.accent` for `.ember`, and the two shades either side of it that
/// give the ground its light. `LabelDef.seed` uses the same darker ember.
let emberLight = 0xD2653C
let emberDeep = 0x9E3E1F
/// `Palette.sheet`, light — the warm cream every card in the app is drawn on.
let cardCream = 0xFBF9F5
/// The board's column dots, in board order: Backlog, Up Next, Done.
/// `BoardColumn.backlog/.upNext/.done`. In Progress is ember and would vanish
/// into the ground, so the three that read are the three that are used.
let dotStone = 0xA8A29A
let dotAmber = 0xC98A16
let dotPine = 0x1F6F63

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
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

/// One column of the mark: a header dot with a stack of cards under it.
struct Column {
    var dot: Int
    var cards: Int
}

/// Laid out in a 1000×1000 box and scaled to whatever the slot needs, so every
/// size is the same drawing rather than a set of hand-tuned ones.
let columns = [Column(dot: dotStone, cards: 3), Column(dot: dotAmber, cards: 2), Column(dot: dotPine, cards: 1)]

/// How much of the mark survives at this size.
///
/// A 16pt icon is about nine points of artwork: the header dots land under a
/// pixel each and the gaps between cards close up, so the full drawing turns
/// into a smudge. The small sizes get the same silhouette with the detail taken
/// out — three descending bars, no dots — which is what Apple's own icons do
/// with hand-drawn small artwork.
enum Detail { case full, simplified }
let markUnit: CGFloat = 1000
let columnWidth: CGFloat = 150
let columnGap: CGFloat = 95
let cardHeight: CGFloat = 140
let cardGap: CGFloat = 42
let dotRadius: CGFloat = 44
/// Between the dot's baseline and the first card. The dot is a column *header*,
/// so it has to read as a separate thing from the stack.
let dotToCards: CGFloat = 66

/// Draws the mark centred in `box`, in a coordinate space where y grows down.
func drawMark(in context: CGContext, box: CGRect, detail: Detail) {
    let scale = box.width / markUnit
    let width = CGFloat(columns.count) * columnWidth + CGFloat(columns.count - 1) * columnGap
    let tallest = columns.map(\.cards).max() ?? 1
    let stackHeight = CGFloat(tallest) * cardHeight + CGFloat(tallest - 1) * cardGap
    let header = detail == .full ? dotRadius * 2 + dotToCards : 0
    let height = header + stackHeight

    let originX = (markUnit - width) / 2
    let originY = (markUnit - height) / 2

    context.saveGState()
    context.translateBy(x: box.minX, y: box.minY)
    context.scaleBy(x: scale, y: scale)

    for (index, column) in columns.enumerated() {
        let x = originX + CGFloat(index) * (columnWidth + columnGap)
        // The stack recedes: the card at the top of a column is the one being
        // looked at, and the ones under it are further away.
        let opacity: CGFloat = [1.0, 0.88, 0.76][min(index, 2)]
        context.setFillColor(rgb(cardCream, opacity))

        if detail == .simplified {
            let bar = CGFloat(column.cards) * cardHeight + CGFloat(column.cards - 1) * cardGap
            context.addPath(capsulePath(
                CGRect(x: x, y: originY, width: columnWidth, height: bar), radius: columnWidth / 2
            ))
            context.fillPath()
            continue
        }

        context.setFillColor(rgb(column.dot))
        context.fillEllipse(in: CGRect(
            x: x + columnWidth / 2 - dotRadius, y: originY, width: dotRadius * 2, height: dotRadius * 2
        ))

        context.setFillColor(rgb(cardCream, opacity))
        var y = originY + header
        for _ in 0..<column.cards {
            context.addPath(capsulePath(
                CGRect(x: x, y: y, width: columnWidth, height: cardHeight), radius: 46
            ))
            context.fillPath()
            y += cardHeight + cardGap
        }
    }
    context.restoreGState()
}

// MARK: - Rendering one slot

enum Platform { case mac, ios }

func render(pixels: Int, platform: Platform) -> CGImage {
    let size = CGFloat(pixels)
    let space = CGColorSpaceCreateDeviceRGB()
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
        context.setFillColor(rgb(emberDeep))
        context.fillPath()
        context.restoreGState()
    }

    context.saveGState()
    context.addPath(shape)
    context.clip()
    // The ground is the ember accent lit from the top-left, which is where the
    // system's own icons take their light from.
    if let gradient = CGGradient(
        colorsSpace: space, colors: [rgb(emberLight), rgb(emberDeep)] as CFArray, locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient, start: CGPoint(x: plate.minX, y: plate.minY),
            end: CGPoint(x: plate.maxX, y: plate.maxY), options: []
        )
    }
    // The mark is smaller inside the plate than the plate is inside the canvas:
    // an icon whose artwork runs to its own edge reads as a photograph.
    let detail: Detail = pixels <= 32 ? .simplified : .full
    // The simplified mark is allowed to run wider, because the pixel it gains
    // is the difference between three bars and a smudge.
    let margin: CGFloat = detail == .full ? 0.15 : 0.12
    drawMark(in: context, box: plate.insetBy(dx: plate.width * margin, dy: plate.height * margin), detail: detail)
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
