// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Synchronization
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The glyph a board wears, and the one thing every surface that draws one has
/// to agree about: **what to draw when the name is not a symbol here.**
///
/// A board's mark is an SF Symbol name, which is a string in a synced file —
/// and the set of symbol names is not the same on every system. A phone a year
/// ahead of the Mac beside it offers a year's worth of glyphs the Mac has never
/// heard of, and `Image(systemName:)` handed one of those draws *nothing*: not a
/// placeholder, not a question mark, an empty frame where the row's mark should
/// be. Which reads as a bug in the sidebar rather than as a symbol that has not
/// arrived yet.
///
/// So every call site asks here first. The answer is the name itself where the
/// system can draw it and ``boardFallback`` where it cannot, so the row is
/// marked either way and the file is left alone — the board goes on carrying
/// the name it was given, and the device that *does* have the glyph goes on
/// drawing it.
///
/// It lives beside the digest rather than in the model because the widget
/// extension draws board marks too and does not compile ``Board``.
enum SymbolMark {
    /// What a board wears when it has not been given a mark, and what stands in
    /// for one this system cannot draw.
    ///
    /// The app's own sign for *a board*: it is what the empty state under a
    /// board with no columns already draws, so the mark a new board arrives
    /// wearing is the one the surface behind it is using for the same idea.
    static let boardFallback = "rectangle.split.3x1"

    /// The saved-view counterpart — `SavedView.defaultSymbol`, spelled here
    /// for the reason the type gives about `Board`: the widget extension
    /// draws view glyphs too and does not compile ``SavedView``. A view's
    /// glyph is user-picked and synced, so it is exactly the string that can
    /// name a symbol this system has never heard of.
    static let viewFallback = "line.3.horizontal.decrease.circle"

    /// Whether the running system can draw each name asked about so far.
    ///
    /// The lookup is a bundle read — cheap, and cheap is not free when a
    /// sidebar of a dozen rows asks on every frame of a drag. Behind a lock
    /// rather than pinned to the main actor: nearly every caller is a view
    /// body, and a widget's timeline provider is not one.
    private static let drawable = Mutex<[String: Bool]>([:])

    /// The name to hand `Image(systemName:)`.
    static func resolved(_ name: String, fallback: String = boardFallback) -> String {
        guard !name.isEmpty else { return fallback }
        return exists(name) ? name : fallback
    }

    /// Whether the system has this symbol, remembered after the first ask.
    ///
    /// The image APIs are the only public answer — there is no
    /// `SFSymbol(named:)` — and they are what `Image(systemName:)` is going to
    /// ask anyway.
    static func exists(_ name: String) -> Bool {
        if let known = drawable.withLock({ $0[name] }) { return known }
        let known = systemHas(name)
        drawable.withLock { $0[name] = known }
        return known
    }

    private static func systemHas(_ name: String) -> Bool {
        #if canImport(UIKit)
        UIImage(systemName: name) != nil
        #elseif canImport(AppKit)
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
        true
        #endif
    }
}
