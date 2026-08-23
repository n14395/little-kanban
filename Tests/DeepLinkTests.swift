import Foundation
import Testing
@testable import Simple_Kanban

/// `simplekanban://task/<uuid>` — the one vocabulary every way into the app from
/// outside it speaks: a pasted link, a tapped notification, a Handoff, a
/// Spotlight result.
///
/// The router is built here rather than reached through `TaskLink.router`: the
/// shared one is process-wide, and a suite whose probes leaked a pending link
/// into each other would pass or fail depending on the order they ran in.
@MainActor
@Suite struct DeepLinkTests {
    private func opened(_ url: URL, in store: BoardStore) -> DeepLinkRouter {
        let router = DeepLinkRouter()
        router.open(url)
        router.resolve(in: store)
        return router
    }

    // MARK: The URL itself

    @Test func aLinkRoundTripsThroughTheIdItNames() {
        for id in [TestBoard.cafe, TestBoard.widget, UUID()] {
            let url = TaskLink.url(for: id)
            #expect(url.scheme == TaskLink.scheme)
            #expect(url.host() == TaskLink.host)
            #expect(TaskLink.taskID(in: url) == id)
        }
    }

    /// A URL typed by a person, or normalised by whatever passed it along.
    @Test func theSchemeAndHostAreMatchedWithoutRegardToCase() throws {
        let id = TestBoard.cafe
        let shouty = try #require(URL(string: "SimpleKanban://TASK/\(id.uuidString.uppercased())"))
        #expect(TaskLink.taskID(in: shouty) == id)
    }

    @Test func aURLThatIsNotOneOfOursNamesNothing() throws {
        let strangers = [
            "https://example.com/task/\(TestBoard.cafe.uuidString)",
            "simplekanban://board/\(TestBoard.cafe.uuidString)",
            "simplekanban://task/not-a-uuid",
            "simplekanban://task/",
            "simplekanban://task/NW-122",
            "otherapp://task/\(TestBoard.cafe.uuidString)",
        ]
        for text in strangers {
            let url = try #require(URL(string: text), Comment(rawValue: text))
            #expect(TaskLink.taskID(in: url) == nil, "\(text) was read as a task link")
        }
    }

    /// The code is not the key. It is minted per board, it is not unique across
    /// installs, and two boards can both hold an NW-122 — which is the whole
    /// reason 3.7 moved ids to UUIDs before anything could link to one.
    @Test func aLinkNamesTheIdRatherThanTheCode() {
        let url = TaskLink.url(for: TestBoard.cafe)
        #expect(!url.absoluteString.contains("NW-122"))
        #expect(url.absoluteString.contains(TestBoard.cafe.uuidString.lowercased()))
    }

    // MARK: Opening one

    @Test func aLinkToARealTaskSelectsIt() {
        let store = TestBoard.store()
        let router = opened(TaskLink.url(for: TestBoard.cafe), in: store)

        #expect(router.failure == nil)
        #expect(store.selectedID == TestBoard.cafe)
        // Every detail surface the app has, not the one this platform was
        // assumed to have. The panel was raised on macOS alone, so on an iPad
        // — which has a panel and no sheet — a link selected the task and
        // showed nothing at all whenever the inspector was closed.
        #expect(store.isInspectorOpen)
        #if os(iOS)
        #expect(store.sheetID == TestBoard.cafe)
        #expect(store.mobileColumnID == BoardColumn.backlog.id)
        #expect(store.isNavDrawerOpen == false)
        #expect(store.tab == .board)
        #endif
    }

    /// The iPad's half of the same claim, said where a regression would show:
    /// with the panel closed, a link has to open it again. Closing it is one
    /// tap on the toolbar and it stays closed across launches of the surface,
    /// so "the inspector happens to be open" is not something a link may rely
    /// on.
    @Test func aLinkOpensTheInspectorWhenItHasBeenClosed() {
        let store = TestBoard.store()
        store.isInspectorOpen = false

        let router = opened(TaskLink.url(for: TestBoard.cafe), in: store)

        #expect(router.failure == nil)
        #expect(store.isInspectorOpen, "the task was selected behind a closed panel")
        #expect(store.selectedID == TestBoard.cafe)
    }

    /// And an archived task, which is the one that reaches a surface with no
    /// board under it at all.
    @Test func aLinkToAnArchivedTaskOpensTheInspectorToo() {
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.cafe: 300]))
        store.isInspectorOpen = false

        _ = opened(TaskLink.url(for: TestBoard.cafe), in: store)

        #expect(store.activeView == .archive)
        #expect(store.isInspectorOpen)
    }

    @Test func aLinkToAnUnfiledTaskOpensTheInbox() {
        let store = TestBoard.store()
        let router = opened(TaskLink.url(for: TestBoard.widget), in: store)

        #expect(router.failure == nil)
        #expect(store.selectedID == TestBoard.widget)
        // The Inbox is a panel beside the board, so opening it means putting
        // the board back *and* the panel out.
        #expect(store.surface == .board)
        #expect(store.isInboxShowing)
        // The Inbox stopped being a tab when it became a panel, so there is no
        // tab left to check: `isInboxShowing` is the whole of the claim, and
        // `.board` above says what is under it.
    }

    @Test func aLinkToATaskOnAnotherBoardGoesToThatBoard() {
        var elsewhere = TestBoard.tasks[2]
        elsewhere.placement = .column(board: TestBoard.support.id, column: TestBoard.queue.id)
        let store = TestBoard.store(
            tasks: [TestBoard.tasks[1], elsewhere], boards: TestBoard.boards
        )
        #expect(store.activeBoardID == SeedData.defaultBoard.id)

        let router = opened(TaskLink.url(for: TestBoard.cafe), in: store)
        #expect(router.failure == nil)
        #expect(store.activeBoardID == TestBoard.support.id)
        #expect(store.selectedID == TestBoard.cafe)
    }

    @Test func aLinkToAFiledAwayTaskOpensTheArchive() {
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.cafe: 300]))
        let router = opened(TaskLink.url(for: TestBoard.cafe), in: store)

        #expect(router.failure == nil)
        #expect(store.activeView == .archive)
        #expect(store.selectedID == TestBoard.cafe)
    }

    /// A link that lands on a board filtered to something the task does not
    /// match opens onto an empty column, which reads as the link having failed.
    @Test func openingALinkClearsAQueryThatWouldHideIt() {
        let store = TestBoard.store()
        store.query = "sync"
        #expect(store.searchResults.contains { $0.id == TestBoard.cafe } == false)

        let router = opened(TaskLink.url(for: TestBoard.cafe), in: store)
        #expect(router.failure == nil)
        #expect(store.query.isEmpty)
        #expect(store.searchResults.contains { $0.id == TestBoard.cafe })
    }

    // MARK: Saying so when it cannot

    /// Doing nothing is the worst available answer: from the outside it is
    /// indistinguishable from the app having failed to launch, and the user is
    /// left re-clicking the link.
    @Test func aLinkToATaskThatDoesNotExistSaysSoRatherThanFailingSilently() throws {
        let store = TestBoard.store()
        store.select(TestBoard.sync)
        let router = opened(TaskLink.url(for: UUID()), in: store)

        let failure = try #require(router.failure, "a link to nothing was swallowed")
        #expect(failure.title.isEmpty == false)
        #expect(failure.message.isEmpty == false)
        #expect(failure.title != failure.message)
        // Nothing moved: a link that could not be opened must not also disturb
        // where the user was.
        #expect(store.selectedID == TestBoard.sync)
    }

    @Test func aMalformedLinkIsRejectedAndSaysSomethingElse() throws {
        let store = TestBoard.store()
        let wasOn = store.selectedID
        let malformed = try #require(URL(string: "https://example.com/task/\(TestBoard.cafe.uuidString)"))
        let router = opened(malformed, in: store)

        let failure = try #require(router.failure, "a URL that is not ours was swallowed")
        // The two failures are different sentences on purpose: "this is not a
        // task link" and "that task has gone" are different problems with
        // different answers.
        let missing = opened(TaskLink.url(for: UUID()), in: store)
        #expect(failure.title != missing.failure?.title)
        #expect(store.selectedID == wasOn, "the selection the store started with is untouched")
    }

    @Test func aFailureIsDismissible() {
        let store = TestBoard.store()
        let router = opened(TaskLink.url(for: UUID()), in: store)
        #expect(router.failure != nil)
        router.dismissFailure()
        #expect(router.failure == nil)
    }

    // MARK: Arriving before there is anywhere to put it

    /// A notification tapped from the lock screen launches the app, and the
    /// delegate runs while the window is still being built.
    @Test func aLinkThatArrivesBeforeTheSceneIsHeldUntilThereIsABoard() {
        let router = DeepLinkRouter()
        router.open(TaskLink.url(for: TestBoard.cafe))
        #expect(router.arrivals == 1)

        let store = TestBoard.store()
        router.resolve(in: store)
        #expect(store.selectedID == TestBoard.cafe)
        #expect(router.failure == nil)
    }

    @Test func resolvingWithNothingWaitingDoesNothing() {
        let store = TestBoard.store()
        store.select(TestBoard.sync)
        let router = DeepLinkRouter()
        router.resolve(in: store)
        router.resolve(in: store)

        #expect(router.failure == nil)
        #expect(store.selectedID == TestBoard.sync)
    }

    /// `arrivals` is what the view watches, so the same link twice has to read
    /// as two openings rather than as one value that did not change.
    @Test func theSameLinkTwiceIsTwoArrivals() {
        let store = TestBoard.store()
        let router = DeepLinkRouter()
        let url = TaskLink.url(for: TestBoard.cafe)

        router.open(url)
        router.resolve(in: store)
        store.select(TestBoard.sync)

        router.open(url)
        #expect(router.arrivals == 2)
        router.resolve(in: store)
        #expect(store.selectedID == TestBoard.cafe)
    }

    /// A link is consumed by the resolve that reads it, so the view calling
    /// `resolve` on appear as well as on arrival cannot open it twice.
    @Test func aLinkIsConsumedByTheResolveThatReadsIt() {
        let store = TestBoard.store()
        let router = DeepLinkRouter()
        router.open(TaskLink.url(for: TestBoard.cafe))
        router.resolve(in: store)

        store.select(TestBoard.sync)
        router.resolve(in: store)
        #expect(store.selectedID == TestBoard.sync)
    }

    // MARK: What the bundle has to declare

    /// The scheme is registered by the Info.plist, not by the code that parses
    /// it. Without the declaration nothing is ever handed to `onOpenURL` and
    /// every probe above still passes.
    @Test func theURLSchemeIsDeclaredInTheBundle() throws {
        let declared = try #require(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
            "the test host declares no URL types, so simplekanban:// reaches nothing"
        )
        let schemes = declared.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
        #expect(schemes.contains(TaskLink.scheme),
                "\(TaskLink.scheme) is parsed in code but not declared in project.yml")
    }

    // MARK: Opened files

    /// The bundle claims `.simplekanban` as its own document type, so the
    /// Finder and Files both hand one to `onOpenURL`. Before this branch the
    /// user's own board file arrived at the link parser and was told it was not
    /// a task link, which is the worst answer available.
    @Test func openingABoardFileImportsItRatherThanRejectingIt() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let before = store.tasks.count
        let url = try Self.writingAFile(named: "shared.simplekanban",
                                        bytes: ForeignBoard.snapshot().encoded())
        defer { try? FileManager.default.removeItem(at: url) }

        let router = opened(url, in: store)
        #expect(router.failure == nil, "a board file was read as a broken link")
        #expect(store.tasks.count > before, "the opened file was not merged")
        #expect(store.tasks.contains { $0.id == ForeignBoard.brief })
        #expect(router.notice?.title == "Board imported.")
    }

    /// The same act as Settings ▸ Import, so the same one ⌘Z takes it back.
    @Test func anOpenedFileIsUndoableAsOneStep() throws {
        let (store, undo) = TestBoard.undoing(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let before = store.tasks.map(\.id)
        let url = try Self.writingAFile(named: "shared.simplekanban",
                                        bytes: ForeignBoard.snapshot().encoded())
        defer { try? FileManager.default.removeItem(at: url) }

        // Grouped by hand: `TestBoard.undoing` turns `groupsByEvent` off so a
        // step is what a test says it is rather than what the run loop decides.
        undo.beginUndoGrouping()
        _ = opened(url, in: store)
        undo.endUndoGrouping()
        #expect(store.tasks.map(\.id) != before)
        #expect(undo.undoActionName == "Import Board")
        undo.undo()
        #expect(store.tasks.map(\.id) == before)
    }

    /// A file that is not a board says so, and says the board was left alone —
    /// the reassurance is the half that matters.
    @Test func openingSomethingThatIsNotABoardSaysSoAndChangesNothing() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let before = store.tasks.map(\.id)
        let url = try Self.writingAFile(named: "notes.simplekanban",
                                        bytes: Data("this is not a board".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let router = opened(url, in: store)
        #expect(router.notice?.title == "That file could not be imported.")
        #expect(router.notice?.message.contains("Your board has not been changed.") == true)
        #expect(store.tasks.map(\.id) == before)
        #expect(router.failure == nil, "a file failure was reported through the link channel")
    }

    @Test func anOpenedFileNoticeIsDismissible() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: SeedData.defaultBoard))
        let url = try Self.writingAFile(named: "notes.simplekanban", bytes: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        let router = opened(url, in: store)
        #expect(router.notice != nil)
        router.dismissNotice()
        #expect(router.notice == nil)
    }

    private static func writingAFile(named name: String, bytes: Data) throws -> URL {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "\(UUID().uuidString)-\(name)")
        try bytes.write(to: url)
        return url
    }

    /// Handoff and Spotlight both continue this activity type, and the system
    /// hands one over only if the bundle claims it.
    @Test func theActivityTypeIsDeclaredInTheBundle() throws {
        let declared = try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String],
            "the test host declares no user activity types, so Handoff never arrives"
        )
        #expect(declared.contains(TaskLink.activityType))
    }
}
