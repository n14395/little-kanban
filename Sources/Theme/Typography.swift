// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The two faces a theme is set in, and the five weights the app asks of them.
///
/// Sizes are the design's pixel values used directly as points, and stay Dynamic
/// Type responsive by being declared relative to a text style.
///
/// **Nothing here knows which theme is in force.** The faces arrive as
/// arguments, from ``Palette/ui(_:_:relativeTo:)`` and
/// ``Palette/display(_:relativeTo:)``, because the palette is the one value that
/// travels down the environment and a font that came from a global would go on
/// drawing in the old face for a frame after the theme changed.
enum LittleKanbanFont {
    /// The weights the app asks for, as CSS numbers so that they add to a
    /// theme's baseline without a table in between. See ``ThemeFont/weight``.
    enum Weight: Int, CaseIterable, Sendable {
        case regular = 400
        case medium = 500
        case semibold = 600
        case bold = 700
        case extraBold = 800

        var systemEquivalent: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .extraBold: .heavy
            }
        }

        /// The same weight as AppKit and UIKit spell it, for the one control
        /// that takes a ``LittleKanbanFont/Platform`` rather than a `Font`.
        var platformEquivalent: Platform.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .extraBold: .heavy
            }
        }
    }

    /// The font type the two text systems take. `NSFont` and `UIFont` differ in
    /// name and in nothing this app asks of them, so the one place that needs a
    /// platform font — ``DescriptionEditor``, which is a text view rather than a
    /// SwiftUI control — says it once and reads the same on both.
    #if os(macOS)
    typealias Platform = NSFont
    #else
    typealias Platform = UIFont
    #endif

    /// `face` at `size`, `step` heavier or lighter than the face's own baseline.
    ///
    /// The step is *added* to the face's weight rather than replacing it: a
    /// theme that sets its UI font at 500 because the face reads thin gets every
    /// one of the app's two hundred call sites lifted by the same amount, and a
    /// theme that leaves it at 400 — which is all twenty of the presets — gets
    /// exactly the weights the call sites were written with.
    static func font(
        _ face: ThemeFont, size: CGFloat, step: Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        let weight = min(max(face.weight + step.rawValue - Weight.regular.rawValue, 100), 900)
        guard let name = FontCatalog.postScriptName(
            family: face.family, weight: weight, italic: face.isItalic
        ) else {
            return fallback(face, size: size, weight: weight)
        }
        let font = Font.custom(name, size: size, relativeTo: textStyle)
        // A family with no slanted face gets a sheared upright rather than
        // nothing. Worse than a drawn italic and better than a theme that asks
        // for italic Sora and silently gets roman.
        return face.isItalic && !FontCatalog.hasItalic(face.family) ? font.italic() : font
    }

    /// What a face nobody has resolves to. The design is guessed from the
    /// family — see ``FontCatalog/isSerif(_:)`` — because a theme built on a
    /// font the user bought should still read as the *kind* of face it was set
    /// in when it is opened on a machine that does not have it.
    private static func fallback(_ face: ThemeFont, size: CGFloat, weight: Int) -> Font {
        let system = Font.system(
            size: size,
            weight: Weight(rawValue: weight)?.systemEquivalent ?? .regular,
            design: FontCatalog.isSerif(face.family) ? .serif : .default
        )
        return face.isItalic ? system.italic() : system
    }
}


extension LittleKanbanFont.Platform {
    /// This face with a slant put on it, or `nil` where the descriptor will not
    /// make one — the platform's version of the shear
    /// ``ResolvedThemeFace/font(_:_:relativeTo:)`` asks SwiftUI for when a family
    /// ships no italic of its own.
    ///
    /// AppKit and UIKit disagree twice in three lines: the trait is `.italic` on
    /// one and `.traitItalic` on the other, and building a font from a descriptor
    /// can fail on one and not the other. Both differences are spent here rather
    /// than at the call site.
    var obliqued: LittleKanbanFont.Platform? {
        #if os(macOS)
        return LittleKanbanFont.Platform(
            descriptor: fontDescriptor.withSymbolicTraits(.italic), size: 0
        )
        #else
        guard let slanted = fontDescriptor.withSymbolicTraits(.traitItalic) else { return nil }
        return LittleKanbanFont.Platform(descriptor: slanted, size: 0)
        #endif
    }

    /// This face redrawn as a serif, for the stand-in a missing family gets.
    var serifed: LittleKanbanFont.Platform? {
        guard let serif = fontDescriptor.withDesign(.serif) else { return nil }
        return LittleKanbanFont.Platform(descriptor: serif, size: 0)
    }
}

/// A theme face resolved against this machine, once.
///
/// ``LittleKanbanFont/font(_:size:step:relativeTo:)`` answers the same
/// question, but it answers it through ``FontCatalog`` — a lock and a
/// string-keyed hash — on **every** `.font(...)` in the app, on every body
/// evaluation, which on a scrolling board is hundreds of round-trips per
/// frame. A face can only be asked for at five weights, so the five names are
/// resolved when the palette is built and every later ask is a plain array
/// read. See ``Palette/ui(_:_:relativeTo:)``.
struct ResolvedThemeFace: Equatable, Sendable {
    private let face: ThemeFont
    /// One slot per ``LittleKanbanFont/Weight``, in `allCases` order; `nil`
    /// where this machine has no such family and the system face stands in.
    private let names: [String?]
    /// The slant will be sheared onto an upright — the family has no italic.
    private let shearsItalic: Bool
    /// What the fallback is drawn in, decided from the family name once.
    private let fallbackDesign: Font.Design

    init(_ face: ThemeFont) {
        self.face = face
        self.names = LittleKanbanFont.Weight.allCases.map { step in
            FontCatalog.postScriptName(
                family: face.family, weight: Self.clamped(face.weight, step: step),
                italic: face.isItalic
            )
        }
        self.shearsItalic = face.isItalic && !FontCatalog.hasItalic(face.family)
        self.fallbackDesign = FontCatalog.isSerif(face.family) ? .serif : .default
    }

    func font(
        _ size: CGFloat, _ step: LittleKanbanFont.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        let index = LittleKanbanFont.Weight.allCases.firstIndex(of: step) ?? 0
        guard let name = names[index] else { return fallback(size: size, step: step) }
        let font = Font.custom(name, size: size, relativeTo: textStyle)
        return shearsItalic ? font.italic() : font
    }

    /// The same face as a platform font, for ``DescriptionEditor`` — the app's
    /// one control that is a text view rather than a SwiftUI view, and so takes
    /// an `NSFont`/`UIFont` where everything else takes a `Font`.
    ///
    /// **`size` arrives already grown.** A `Font` carries the text style it was
    /// declared `relativeTo` and follows the reader's text size on its own; a
    /// platform font is a fixed number of points and does not. So the growing
    /// happens at the call site, through the `ScaledMetric` the rest of the
    /// app's fixed sizes go through, and what reaches here is the answer.
    func platformFont(_ size: CGFloat, _ step: LittleKanbanFont.Weight = .regular)
        -> LittleKanbanFont.Platform {
        let index = LittleKanbanFont.Weight.allCases.firstIndex(of: step) ?? 0
        guard let name = names[index], let font = LittleKanbanFont.Platform(name: name, size: size)
        else { return platformFallback(size: size, step: step) }
        // A family with no slanted face gets a synthesised oblique, which is the
        // platform's version of the shear `font(_:_:relativeTo:)` asks SwiftUI
        // for. If the descriptor cannot make one, upright is the honest answer.
        guard shearsItalic else { return font }
        return font.obliqued ?? font
    }

    /// ``platformFont(_:_:)``'s stand-in, from the same precomputed design the
    /// SwiftUI fallback uses — a theme built on a font this machine does not
    /// have still reads as the *kind* of face it was set in.
    private func platformFallback(size: CGFloat, step: LittleKanbanFont.Weight)
        -> LittleKanbanFont.Platform {
        let weight = Self.clamped(face.weight, step: step)
        let system = LittleKanbanFont.Platform.systemFont(
            ofSize: size,
            weight: LittleKanbanFont.Weight(rawValue: weight)?.platformEquivalent ?? .regular
        )
        guard fallbackDesign == .serif else { return system }
        return system.serifed ?? system
    }

    /// ``LittleKanbanFont/fallback(_:size:weight:)``, from the precomputed design.
    private func fallback(size: CGFloat, step: LittleKanbanFont.Weight) -> Font {
        let weight = Self.clamped(face.weight, step: step)
        let system = Font.system(
            size: size,
            weight: LittleKanbanFont.Weight(rawValue: weight)?.systemEquivalent ?? .regular,
            design: fallbackDesign
        )
        return face.isItalic ? system.italic() : system
    }

    /// The face's baseline plus the step, held to the axis — the same sum
    /// ``LittleKanbanFont/font(_:size:step:relativeTo:)`` makes.
    private static func clamped(_ base: Int, step: LittleKanbanFont.Weight) -> Int {
        min(max(base + step.rawValue - LittleKanbanFont.Weight.regular.rawValue, 100), 900)
    }
}

extension FontCatalog {
    /// Whether a family is a serif, for the one case where it matters: choosing
    /// a system face to stand in for one that is not installed.
    ///
    /// The seventeen the app ships with are named, because they are known. Every
    /// other family is guessed from its name, which is right often enough for a
    /// fallback and wrong in no way anybody can be hurt by.
    static func isSerif(_ family: String) -> Bool {
        if bundledSerifs.contains(family) { return true }
        if bundledFamilies.contains(family) { return false }
        let name = family.lowercased()
        return ["serif", "times", "georgia", "caslon", "garamond", "baskerville", "roman"]
            .contains { name.contains($0) }
    }

    private static let bundledSerifs: Set<String> = [
        "Instrument Serif", "Newsreader", "IBM Plex Serif", "Spectral",
        "Crimson Pro", "Libre Caslon Text",
    ]
}

extension View {
    /// Applies the design's uppercase micro-label treatment:
    /// `11px / 800 / 0.1em tracking / uppercase`.
    ///
    /// The default opacity is the readable floor rather than the design's 0.38.
    /// 0.38 of ink under 11pt uppercase type is the single most common finding
    /// the accessibility audit made — it resolves to about 2.4:1 — and every one
    /// of the twenty-six call sites had to pass the floor by hand to get out of
    /// it. A default that has to be overridden everywhere is not a default; this
    /// is the same number said once.
    func sectionLabelStyle(
        size: CGFloat = 11, tracking: CGFloat = 0.1, opacity: Double = Palette.readableInk
    ) -> some View {
        modifier(SectionLabelStyle(size: size, tracking: tracking, opacity: opacity))
    }
}

private struct SectionLabelStyle: ViewModifier {
    @Environment(\.palette) private var palette
    let size: CGFloat
    let tracking: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .font(palette.ui(size, .extraBold, relativeTo: .caption2))
            .tracking(size * tracking)
            .textCase(.uppercase)
            // `inkText` rather than `ink`: the floor belongs to the tone, so a
            // call site that passes the design's own lighter number still gets
            // text that can be read.
            .foregroundStyle(palette.inkText(opacity))
    }
}
