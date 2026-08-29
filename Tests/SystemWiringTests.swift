import Foundation
import Testing
@testable import Simple_Kanban

/// The joins between Phase F's machinery and the app that is meant to be using
/// it.
///
/// Every other suite in this phase drives `NotificationScheduler`,
/// `DeepLinkRouter` and `TaskIntentBridge` directly, which is what makes them
/// worth having — and also what makes them all pass on a build where nothing
/// ever calls any of them. A scheduler nobody reconciles schedules nothing; an
/// `onOpenURL` nobody attaches is never handed a URL; a bridge nobody adopts a
/// store into makes every Shortcut fail with "still starting up". This is
/// `UndoHandoverTests`' question asked of the other four handovers.
///
/// Read out of the source rather than off a running app, for the same reason
/// `MenuDeclarationTests` reads `BoardCommands.swift`: a SwiftUI scene has
/// nothing to enumerate at runtime, and a modifier commented out of a `body` is
/// invisible to everything else.
@Suite struct SystemWiringTests {
    /// Every Swift file in the app target, comments stripped — so a call named
    /// in prose is not mistaken for one the app makes.
    private static func sources() throws -> String {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()    // Tests/
            .deletingLastPathComponent()    // the source tree
            .appending(path: "Sources")
        let urls = FileManager.default
            .enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return try urls.reduce(into: "") { text, url in
            text += try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }
    }

    /// One file, comments stripped the same way.
    private static func source(named name: String) throws -> String {
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources")
        let url = try #require(
            FileManager.default
                .enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .first { $0.lastPathComponent == name },
            "no such file in Sources: \(name)"
        )
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func expectCalled(_ needle: String, _ why: Comment) throws {
        #expect(try Self.sources().contains(needle), why)
    }

    /// The three joins Phase F left open, now made. Each was wrapped in
    /// `withKnownIssue` while the machinery existed and nothing called it —
    /// `NotificationTests`, `DeepLinkTests` and `IntentTests` were a hundred
    /// green assertions about code the shipping app never ran. The wrappers
    /// came off in the run that wired them, which is what `withKnownIssue` is
    /// for: it fails a block that *stops* failing.
    @Test func theSchedulerIsReconciledFromTheBoard() throws {
        try expectCalled(
            ".reconcile(",
            "nothing reconciles the scheduler, so no due date ever schedules a reminder"
        )
        try expectCalled(
            "NotificationScheduler.reminders(",
            "the board's reminders are never derived, so the scheduler is never told what to want"
        )
    }

    @Test func theAppAttachesTheSystemEntryPoints() throws {
        try expectCalled(
            ".systemEntryPoints()",
            "no view attaches the entry points, so simplekanban:// URLs, tapped notifications, Handoff and Spotlight all reach nothing"
        )
    }

    @Test func theAppHandsItsStoreToTheIntentBridge() throws {
        try expectCalled(
            "TaskIntentBridge.adopt(",
            "no store is adopted, so every App Intent fails with \"still starting up\""
        )
    }

    /// The bridge is adopted from the app's `init()` and not from a view's
    /// `.onAppear`. An intent can perform in a process the user never brought
    /// to the front, before the first scene exists, and a store adopted on
    /// appear is not there yet when it does.
    @Test func theStoreIsAdoptedBeforeAnySceneExists() throws {
        let app = try Self.source(named: "SimpleKanbanApp.swift")
        let adopt = try #require(app.range(of: "TaskIntentBridge.adopt("))
        let initialiser = try #require(app.range(of: "init() {"))
        #expect(initialiser.lowerBound < adopt.lowerBound,
                "the intent bridge is adopted from somewhere other than the app's init()")
    }

    /// The share extension can only write into the App Group — see
    /// ``CaptureInbox`` — so this call is the *only* path a shared item takes
    /// onto the board. Without it a share sheet reports success and the card
    /// never appears, which is the worst kind of silent failure: the user
    /// watched it work.
    @Test func theAppDrainsWhatWasSharedIntoIt() throws {
        try expectCalled(
            "store.adoptPendingCaptures()",
            "nothing drains the App Group, so anything shared into the app is written and never read"
        )
    }

    /// Twice, and both are needed. `.onAppear` catches what was shared while
    /// the app was not running — a launch is not a foregrounding on either
    /// platform, so the scene comes up already active and `scenePhase` never
    /// changes. The `.active` branch catches everything after that.
    @Test func theDrainRunsAtLaunchAndOnComingForward() throws {
        let app = try Self.source(named: "SimpleKanbanApp.swift")
        let calls = app.components(separatedBy: "store.adoptPendingCaptures()").count - 1
        #expect(calls == 2,
                "the drain is called \(calls) times; it belongs on `.onAppear` and on `scenePhase == .active`")
    }

    /// Handoff and Spotlight publish the open task from whichever surface is
    /// showing one. Two surfaces show one, and a modifier on only the desk's
    /// leaves the phone handing off nothing.
    @Test func bothDetailSurfacesPublishTheirTask() throws {
        for file in ["TaskInspector.swift", "PhoneDetailSheet.swift"] {
            #expect(try Self.source(named: file).contains(".taskUserActivity("),
                    "\(file) shows a task and does not publish it for Handoff or Spotlight")
        }
    }

    /// The gate that keeps the suite off the machine it is running on.
    ///
    /// `scheduleSave()` reconciles the real Notification Centre and the real
    /// Spotlight index, and most suites here are file-backed — `TempBoard`
    /// hands out a throwaway `BoardFile`, not a `nil` one — so "an in-memory
    /// store is a test" is not the guard it sounds like. `BoardFile` already
    /// steps `.default` aside under a runner for the same reason; this asserts
    /// the detection still answers, because if it stops the next suite run
    /// quietly indexes `TestBoard` into the developer's Spotlight.
    @Test func theSuiteIsRecognisedAsATestRunner() {
        #expect(BoardFile.isRunningTests,
                "the test-runner check no longer fires, so the suite is publishing to this machine")
    }

    @Test func theSettingsSurfaceIsReachable() throws {
        try expectCalled(
            "SettingsView(",
            "the settings surface is built but nothing shows it"
        )
    }

    /// One store, said out loud. An intent, a notification and a window all
    /// write to the board, and a second store would give one of them a board of
    /// its own to overwrite the real one with.
    @Test func thereIsExactlyOneStoreOverTheRealFile() throws {
        let text = try Self.sources()
        #expect(text.components(separatedBy: "BoardStore.restored(").count - 1 == 1,
                "the app builds more than one store over the board file")
    }

    /// No presentation attached to the root reads the palette out of the
    /// environment.
    ///
    /// `RootView` publishes the palette *below* itself, so a `ViewModifier`
    /// applied to it sits above that in the tree and `@Environment(\.palette)`
    /// there resolves to the default light theme. Nothing about that is visible
    /// in light mode, and the surface it produces is cream-coloured over a dark
    /// board: it has already happened to the About panel, the first-run picker,
    /// the settings sheet and the save-failure banner. Each of them resolves the
    /// palette itself now, from the appearance override and the colour scheme,
    /// which is the only thing that works from that position.
    @Test func nothingPresentedFromTheRootReadsThePaletteFromTheEnvironment() throws {
        let text = try Self.source(named: "SimpleKanbanApp.swift")
        let parts = text.components(separatedBy: ": ViewModifier {")
        var offenders: [String] = []
        for index in 1..<max(parts.count, 1) {
            let name = parts[index - 1].components(separatedBy: "struct ").last ?? "?"
            // A top-level declaration closes on a `}` in the first column.
            let body = parts[index].components(separatedBy: "\n}").first ?? parts[index]
            if body.contains(#"Environment(\.palette)"#) { offenders.append(name) }
        }
        #expect(parts.count - 1 >= 4,
                "only \(parts.count - 1) view modifiers were found — the scan is not seeing the file")
        #expect(offenders.isEmpty, "these read the root's palette from above it: \(offenders)")
    }
}
