import Foundation
import SwiftData
import Testing
@testable import LittleKanban

/// Pull a list of cards past its top and the board checks iCloud.
///
/// Two halves, tested from two ends. What the pull *does* is
/// ``BoardStore/syncNow(settling:)``, which is a value the suite can drive —
/// every store here is `BoardSyncStore.inMemory()`, which reaches no iCloud
/// account, for `SyncStoreTests`' reason. Where the pull is *offered* is a fact
/// about the source: `refreshable` is a modifier, and a surface that stopped
/// carrying it looks exactly like one that never did.
@MainActor
@Suite struct PullToSyncTests {
    private func board(_ sync: BoardSyncStore, on temp: TempBoard) -> BoardStore {
        let store = BoardStore.restored(file: temp.file, sync: sync)
        store.saveNow()
        return store
    }

    // MARK: What the pull does

    /// The half that is genuinely this device's: whatever came down while
    /// nobody was looking is adopted on the pull rather than on the next
    /// notification.
    @Test func aPullAdoptsWhatAnotherDeviceHasSent() async throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        store.addTask(to: .inbox, title: "Mine")
        store.saveNow()

        // Through a second store over the same container, the way an import
        // arrives — this device's diff base must not hear about it.
        var theirs = try #require(try sync.load())
        theirs.tasks = theirs.tasks.map { task in
            var edited = task
            if edited.title == "Mine" { edited.title = "Theirs" }
            return edited
        }
        try BoardSyncStore(container: sync.container, isSyncing: false).apply(theirs)

        let arrived = await store.syncNow(settling: .zero)
        #expect(arrived, "the pull found the other device's edit and said it had not")
        #expect(store.tasks.contains { $0.title == "Theirs" })
        #expect(store.lastSyncedAt != nil)
    }

    /// The other half, which the debounce owns: a card ticked a moment ago is
    /// still waiting here when the finger pulls, and the pull sends it before
    /// it reads — `mergeRemoteChanges`' flush, reached through the same door.
    @Test func aPullSendsWhatTheDebounceHasNotPushedYet() async throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)

        let made = try #require(store.createBoard(named: "Fresh"))
        await store.syncNow(settling: .zero)

        #expect(try #require(try sync.load()).boards.contains { $0.id == made },
                "the pull read the records without flushing the pending board into them")
    }

    /// **A read is not news.** The stamp beside the adoption is the sentence
    /// Settings prints as "last change from another device", and a pull is the
    /// user asking at a moment of their own choosing — so a board that had
    /// nothing to say would have been saying it in the present tense, once per
    /// pull, for as long as somebody kept pulling.
    @Test func aPullThatFindsNothingNewClaimsNothing() async throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        store.addTask(to: .inbox, title: "Mine")
        store.saveNow()

        let arrived = await store.syncNow(settling: .zero)
        #expect(arrived == false, "the records held exactly what this board holds")
        #expect(store.lastSyncedAt == nil, "an empty read stamped a change nobody made")
        #expect(store.tasks.contains { $0.title == "Mine" }, "the empty read cost a card")
    }

    /// Sync off, or a build with no records at all. Nothing to ask, and the
    /// modifier hangs nothing on the list either — see `theCardSurfacesOffer`.
    @Test func aBoardWithNoRecordsHasNothingToPull() async throws {
        let temp = TempBoard()
        let store = BoardStore.restored(file: temp.file)
        let arrived = await store.syncNow(settling: .zero)
        #expect(arrived == false)
        #expect(store.lastSyncedAt == nil)
    }

    /// **A check that finished says so**, because a pull that found nothing
    /// looks exactly like a pull that did not happen: the spinner leaves either
    /// way. The two answers are different sentences — see
    /// ``Announcement/synced(adopted:)`` — and the card is raised after the
    /// settle, so it lands as the spinner goes rather than under it.
    @Test func aPullLeavesACardSayingWhichAnswerItGot() async throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        store.addTask(to: .inbox, title: "Mine")
        store.saveNow()

        await store.syncNow(settling: .zero)
        #expect(store.announcement?.text == "Up to date",
                "a pull that found nothing said nothing")

        var theirs = try #require(try sync.load())
        theirs.tasks = theirs.tasks.map { task in
            var edited = task
            if edited.title == "Mine" { edited.title = "Theirs" }
            return edited
        }
        try BoardSyncStore(container: sync.container, isSyncing: false).apply(theirs)

        await store.syncNow(settling: .zero)
        #expect(store.announcement?.text == "Board updated",
                "a pull that brought a card down said nothing happened")
    }

    /// **A merge nobody asked for stays quiet.** The notification fires whenever
    /// another device pushes, several times an hour on a board two people are
    /// working; a card each time would be a notification nobody asked for, and
    /// the board changing under them is the message.
    @Test func anUnaskedMergeRaisesNoCard() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        store.addTask(to: .inbox, title: "Mine")
        store.saveNow()

        var theirs = try #require(try sync.load())
        theirs.tasks = theirs.tasks.map { task in
            var edited = task
            if edited.title == "Mine" { edited.title = "Theirs" }
            return edited
        }
        try BoardSyncStore(container: sync.container, isSyncing: false).apply(theirs)

        store.mergeRemoteChanges()
        #expect(store.tasks.contains { $0.title == "Theirs" }, "the merge did not land")
        #expect(store.announcement == nil, "an unasked merge announced itself")
    }

    /// **Scenario 17 of the two-device checklist.** A theme made on the other
    /// device arrives on a pull — not at the next launch, which is where the
    /// old rule held the whole of `ThemeSettings` back and what read from the
    /// outside as "themes don't sync". Only the *list* travels live: which
    /// theme this machine is showing is its own until the next launch, because
    /// the slots are the half that repaints the window mid-sentence.
    @Test func aThemeMadeOnTheOtherDeviceArrivesOnAPull() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        store.addTask(to: .inbox, title: "Mine")
        store.saveNow()
        let wearing = (light: store.themes.lightID, dark: store.themes.darkID)

        var theirs = try #require(try sync.load())
        // Two applies, deliberately: a writer with no diff base leaves the
        // meta blobs exactly as they are — the fresh-device rule in
        // `applyMeta` — so the first call is the other device establishing its
        // base, and the second is the edit. One apply from a fresh instance
        // never writes a theme, which is the rule working, not the harness.
        let writer = BoardSyncStore(container: sync.container, isSyncing: false)
        try writer.apply(theirs)
        var made = ThemePresets.fallback(for: .light)
        made.id = "made-on-the-other-device"
        made.name = "Theirs"
        made.changedAt = .now
        theirs.themes.custom.append(made)
        // And they put it straight in a slot, which is exactly what somebody
        // who has just made a theme does — the half that must not travel.
        theirs.themes.lightID = made.id
        theirs.themesChangedAt = .now
        try writer.apply(theirs)

        store.mergeRemoteChanges()
        #expect(store.themes.custom.contains { $0.id == made.id },
                "a theme made on the other device waited for a relaunch")
        #expect(store.themes.lightID == wearing.light && store.themes.darkID == wearing.dark,
                "another device's slot choice repainted this window")
        // And the arrival is news — the pull's announcement rests on this.
        #expect(store.lastSyncedAt != nil, "a theme arriving did not count as news")
    }

    /// A merge that changed the board drops the undo stack — the steps on it
    /// restore boards from before it, which the push would read back as
    /// deletions (see `DeletionLicenseTests`). A theme is the exemption:
    /// themes live outside `BoardMutation`, so a merge that only brought one
    /// moved nothing a ⌘Z can see, and every step still restores exactly what
    /// it says.
    @Test func aMergeThatOnlyBroughtAThemeKeepsTheUndoStack() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        let undo = RecordingUndoManager()
        undo.groupsByEvent = false
        store.undoManager = undo
        step(undo) { store.addTask(to: .inbox, title: "Mine") }
        store.saveNow()

        let theirs = try #require(try sync.load())
        // The double apply, for `aThemeMadeOnTheOtherDeviceArrivesOnAPull`'s
        // reason: the first establishes the writer's base, the second is the edit.
        let writer = BoardSyncStore(container: sync.container, isSyncing: false)
        try writer.apply(theirs)
        var edited = theirs
        var made = ThemePresets.fallback(for: .light)
        made.id = "made-on-the-other-device"
        made.name = "Theirs"
        made.changedAt = .now
        edited.themes.custom.append(made)
        edited.themesChangedAt = .now
        try writer.apply(edited)

        store.mergeRemoteChanges()
        #expect(store.themes.custom.contains { $0.id == made.id }, "the theme never arrived")
        #expect(undo.canUndo, "a theme crossing cost the user their undo history")
    }

    /// **Scenario 17's second way of failing.** A theme made on the other
    /// device is still crossing — CloudKit pushes take what they take — while
    /// this device merges something unrelated. The unrelated merge used to
    /// stamp all three watermarks at the wall clock, so the theme landed
    /// wearing a `changedAt` *behind* the watermark, which is the shape of a
    /// deletion: the rule dropped it, and the next push taught the device
    /// that made it to drop it too. The watermark now stands at the stamp the
    /// merge consumed, which anything still crossing is always ahead of.
    @Test func aThemeStillCrossingSurvivesAnUnrelatedMergeInBetween() throws {
        let temp = TempBoard()
        let sync = try BoardSyncStore.inMemory()
        let store = board(sync, on: temp)
        store.addTask(to: .inbox, title: "Mine")
        // This device has a dated theme list of its own: the arrival has to
        // come through the two-dated-lists merge, where the watermark is the
        // whole of the decision.
        var early = ThemePresets.fallback(for: .light)
        early.id = "made-here-first"
        early.name = "Here, first"
        store.saveTheme(early)
        store.saveNow()

        // The other device makes a theme. Its push does not land yet.
        let theirDevice = BoardSyncStore(container: sync.container, isSyncing: false)
        var theirs = try #require(try theirDevice.load())
        var made = ThemePresets.fallback(for: .light)
        made.id = "made-on-the-other-device"
        made.name = "Theirs, crossing"
        made.changedAt = .now
        theirs.themes.custom.append(made)
        theirs.themesChangedAt = made.changedAt

        // Meanwhile a card edit arrives from elsewhere and this device merges
        // it — the unrelated merge that used to move the theme watermark.
        let bystander = BoardSyncStore(container: sync.container, isSyncing: false)
        var edited = try #require(try bystander.load())
        edited.tasks = edited.tasks.map { task in
            var retitled = task
            if retitled.title == "Mine" { retitled.title = "Theirs" }
            return retitled
        }
        try bystander.apply(edited)
        store.mergeRemoteChanges()
        #expect(store.tasks.contains { $0.title == "Theirs" },
                "the unrelated merge did not land, so the scenario never started")

        // This device then edits its own themes, dating its list *after* the
        // crossing theme was made…
        var later = ThemePresets.fallback(for: .light)
        later.id = "made-here-second"
        later.name = "Here, second"
        store.saveTheme(later)
        store.saveNow()

        // …and the crossing push finally lands.
        try theirDevice.apply(theirs)

        store.mergeRemoteChanges()
        #expect(store.themes.custom.contains { $0.id == made.id },
                "a theme that crossed an unrelated merge was read as deleted")
        #expect(store.themes.custom.contains { $0.id == later.id },
                "this device's own newer theme was lost to the arrival")
        #expect(store.themes.custom.contains { $0.id == early.id })
    }

    // MARK: Where the pull is offered

    /// Every surface that holds cards and scrolls downward carries it, and the
    /// one that scrolls sideways cannot: the iPad's saved view is
    /// `TaskColumnsView`'s down-then-across flow, a horizontal scroll view with
    /// no top to pull past.
    ///
    /// `PullToSync` is read too, because the whole of the promise is in it: the
    /// gesture is attached only where there is something to ask, and it takes
    /// the vertical bounce back while it is attached — a column whose cards do
    /// not fill it asks for `.basedOnSize`, and a list that cannot be pulled
    /// past a top it is already at cannot be pulled to refresh.
    ///
    /// **What the source cannot say is whether the pull fires**, and that was
    /// driven by hand rather than left to a claim: on a build with the gesture
    /// forced on and a marker card minted inside `syncNow`, a pull on a phone
    /// column and a pull on an iPad column both produced the card. The same
    /// drag on the flat list produced nothing, three ways round — which is as
    /// likely to be XCUITest's inability to drive a `UIRefreshControl` as
    /// anything about the app, since `List` with `refreshable` is the pairing
    /// Apple documents. Recorded rather than asserted; see **Pull to sync** in
    /// the README.
    @Test func theCardSurfacesOfferThePull() {
        guard SourceTree.isReachable else { return }
        // The scroll surfaces, what each hands the modifier as its resting
        // bounce, and how many `scrollBounceBehavior` lines are left over: none,
        // because a surface that pulls hands its bounce over rather than stating
        // it twice — except `TaskColumnsView`, whose *other* flow is the
        // sideways one that cannot pull and still asks for its own.
        let carries = [
            // The desk's and the iPad's columns
            "Shared/BoardColumnView.swift": ("pullToSync(bounce: .basedOnSize)", 0),
            // The iPad's Inbox
            "Shared/InboxPanel.swift": ("pullToSync(bounce: .basedOnSize)", 0),
            // A saved view on a phone held sideways
            "Shared/TaskColumnsView.swift": ("pullToSync(bounce: .basedOnSize)", 1),
            // The phone's columns and its Inbox sheet
            "IOS/PhoneCardStack.swift": ("pullToSync(bounce: .basedOnSize, enabled: pullsToSync)", 0),
            // A saved view, Search and the Inbox tab — a `List`, which bounces
            // of its own accord and asks for nothing here
            "Shared/TaskListView.swift": ("pullToSync()", 0),
        ]
        var seen: Set<String> = []
        for file in SourceTree.files() {
            let code = String(file.code)
            if let (spelling, leftOver) = carries[file.path] {
                #expect(code.contains(spelling), "\(file.path) stopped offering the pull")
                #expect(code.components(separatedBy: "scrollBounceBehavior").count - 1 == leftOver,
                        "\(file.path) states a bounce the pull was handed")
                seen.insert(file.path)
            }
            guard file.path == "Shared/PullToSync.swift" else { continue }
            #expect(code.contains("store.isSyncing"),
                    "the spinner promises a check, and is hung on a board that cannot make one")
            #expect(code.contains("refreshable"))
            #expect(code.contains("scrollBounceBehavior(.always"),
                    "a column that does not bounce cannot be pulled past its top")
            seen.insert(file.path)
        }
        #expect(seen.count == carries.count + 1, "a card surface moved file: found \(seen)")
    }

    /// **The phone's Inbox opts out**, and is the only surface that does.
    ///
    /// The sheet's own dismissal is a downward drag, so a pull past the top of
    /// its cards was one finger asking for two things a few points apart —
    /// which of them happened depended on where the thumb landed. The board's
    /// columns keep the gesture, and so does the iPad's Inbox, which is a panel
    /// standing in the window rather than a sheet with somewhere to go.
    ///
    /// Read out of the source because the claim is about a modifier that is not
    /// there: a stack drawn without the pull looks exactly like one drawn with
    /// it until a finger arrives.
    @Test func thePhonesInboxDoesNotOfferThePull() {
        guard SourceTree.isReachable else { return }
        var seen: Set<String> = []
        for file in SourceTree.files() {
            let code = String(file.code)
            switch file.path {
            case "IOS/PhoneInboxSheet.swift":
                #expect(code.contains("pullsToSync: false"),
                        "the phone's Inbox sheet pulls again, against its own dismissal")
                seen.insert(file.path)
            case "IOS/PhoneCardStack.swift":
                // The switch has to reach the modifier, or passing `false`
                // reads as a fix and does nothing.
                #expect(code.contains("enabled: pullsToSync"))
                seen.insert(file.path)
            case "Shared/InboxPanel.swift":
                #expect(code.contains("pullToSync("),
                        "the iPad's Inbox lost the pull with the phone's")
                seen.insert(file.path)
            default:
                break
            }
        }
        #expect(seen.count == 3, "an Inbox surface moved file: found \(seen)")
    }

    /// **The desk asks with a button**, because a window that is already in
    /// front of you has no pull to borrow — it sits at the end of the status
    /// bar, after the sentence about the last save. Read out of the source for
    /// the same reason as the pull: whether a control is *there* is not a value
    /// the store can be asked for.
    ///
    /// Two guards are the whole of its honesty, and both are asserted. A build
    /// with no entitlement can never reach a container, so it draws no button at
    /// all — Settings explains that state, and a control that could never work
    /// is worse than none. Sync merely off, or iCloud away this launch, keeps
    /// the button and greys it, which is the desk's version of what the touch
    /// platforms do by attaching no gesture.
    @Test func theDeskAsksWithAButton() {
        guard SourceTree.isReachable else { return }
        var seen = false
        for file in SourceTree.files() where file.path == "Mac/MacStatusBar.swift" {
            let code = String(file.code)
            #expect(code.contains("store.syncNow()"),
                    "the status bar's button no longer asks for a sync")
            #expect(code.contains("SyncPreference.isAvailable"),
                    "a build that cannot reach a container draws a button that could never work")
            #expect(code.contains("disabled(!store.isSyncing"),
                    "the button is pressable while the board is not syncing")
            seen = true
        }
        #expect(seen, "MacStatusBar moved file")
    }
}
