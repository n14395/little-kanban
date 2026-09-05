import Foundation
import Testing
@testable import Cardstock

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The list Settings is divided into, on both surfaces.
///
/// `SettingsTab` exists because the two surfaces had drifted: **System** was in
/// the macOS `TabView` with no `.tabItem` attached, so its pane was reachable
/// only by clicking the unlabelled gap where its name should have been. One
/// `CaseIterable` read by the desk's tabs and the sheet's strip alike makes that
/// particular defect unwritable — a case with no name will not compile — and
/// what is left to check is the part the compiler cannot see: that there are few
/// enough of them, that the names are distinct, and that each glyph is a symbol
/// the system actually has.
@Suite struct SettingsTabTests {

    /// **Four, and no more.** There were eight — Trash, Appearance, Board,
    /// Notifications, Sync, System, Labels and Data — and half of them held a
    /// single row. A subject that holds one switch is not a subject; it is a row
    /// that has been given a tab of its own, and the cost is paid by everybody
    /// who has to read past it. It is paid hardest on the phone, where the strip
    /// shows about three chips at a time and the other five are off the side of
    /// the screen.
    ///
    /// A number rather than a list of the four, because the claim is the ceiling:
    /// the next single-switch subject is the one this is here to stop.
    @Test func thereAreAtMostFourSubjects() {
        #expect(SettingsTab.allCases.count <= 4,
                "Settings has grown to \(SettingsTab.allCases.count) subjects: \(SettingsTab.allCases.map(\.title))")
    }

    /// **The Trash is not one of them.** It is the user's own work waiting out a
    /// thirty-day countdown, not a preference about how the app behaves, and it
    /// has doors of its own now — see `TrashSurfaceTests`, which is where the
    /// other half of this claim lives.
    @Test func theTrashIsNotASubjectOfSettings() {
        #expect(SettingsTab(rawValue: "trash") == nil, "the Trash is a settings tab again")
        let titles = SettingsTab.allCases.map(\.title)
        #expect(!titles.contains("Trash"), "a settings subject is called Trash: \(titles)")
    }

    /// A `Label` whose `systemImage` does not resolve draws nothing at all and
    /// reports no error, which on the desk is a toolbar item that is a word with
    /// a hole above it and on the sheet is a chip with the icon missing. Only a
    /// run can tell — the name is a string until something asks the system for
    /// it, and that is what this does.
    @Test func everySubjectsGlyphIsASymbolTheSystemHas() {
        for tab in SettingsTab.allCases {
            #if os(macOS)
            let resolved = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil) != nil
            #else
            let resolved = UIImage(systemName: tab.symbol) != nil
            #endif
            #expect(resolved, "\(tab.rawValue) asks for a symbol named \(tab.symbol), which does not exist")
        }
    }

    /// Two subjects under one word is a strip where choosing has no visible
    /// effect, and `UITests/SettingsTabsTests` matches its chips by identifier
    /// precisely so it cannot notice.
    @Test func noTwoSubjectsShareAName() {
        let titles = SettingsTab.allCases.map(\.title)
        #expect(Set(titles).count == titles.count, "two subjects are drawn under the same name: \(titles)")
        #expect(titles.allSatisfy { !$0.isEmpty }, "a subject has no name at all")
    }

    /// **General leads**, and the sheet opens on whatever is first here — so the
    /// order is a decision and not an accident of where the case was typed. It
    /// leads because it is the pane holding the two things somebody opening
    /// Settings for the first time is most likely to be after: the accent and
    /// light-or-dark.
    @Test func generalIsTheSubjectBothSurfacesOpenOn() {
        #expect(SettingsTab.allCases.first == .general)
    }

    /// **The same four on both platforms.** The desk's two extra switches —
    /// open at login, and the menu bar item — are rows inside **General** now
    /// rather than a **System** case compiled out on iOS, so `allCases` is the
    /// whole truth about what each surface draws and neither has to filter it.
    @Test func bothPlatformsDrawTheSameSubjects() {
        let expected: [SettingsTab] = [.general, .board, .notifications, .data]
        #expect(SettingsTab.allCases == expected,
                "the subjects have changed: \(SettingsTab.allCases.map(\.rawValue))")
    }
}
