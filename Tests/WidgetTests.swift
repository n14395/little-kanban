import Foundation
import Testing
@testable import Simple_Kanban

/// What the app writes down for its widgets.
///
/// The extension draws a `WidgetDigest` and evaluates nothing — see the type's
/// own note — which makes this the whole of the contract between the two
/// targets. If a count here is wrong the widget is wrong, and there is no
/// second place the mistake could be corrected.
///
/// Nothing in this suite touches the App Group. `WidgetPublisher.digest(_:today:)`
/// is separate from the write for exactly that reason, and the file half is
/// asserted through ``WidgetDigestFile/decode(_:)`` on bytes made here.
@MainActor
@Suite struct WidgetDigestTests {
    private func digest(_ store: BoardStore, today: CalendarDay = TestBoard.dueDay) -> WidgetDigest {
        WidgetPublisher.digest(of: store, today: today)
    }

    // MARK: The Inbox

    @Test func theInboxCarriesWhatIsWaitingInIt() {
        let store = TestBoard.store()
        let inbox = digest(store).inbox

        #expect(inbox.count == store.inboxTasks.count)
        #expect(inbox.tasks.map(\.id) == store.inboxTasks.map(\.id))
        #expect(inbox.tasks.first?.title == store[TestBoard.widget]?.displayTitle)
        // The seeded Inbox view's identity, so a widget and the sidebar row
        // agree about which list they are showing.
        #expect(inbox.id == SavedView.id(of: .inbox))
    }

    /// "3 tasks in the Inbox" means three things left to do. A ticked-off
    /// capture stays in the panel and is not one of them, which is also what
    /// makes this list exactly the seeded Inbox view's membership.
    @Test func aTickedOffCaptureIsNotSomethingWaiting() {
        let store = TestBoard.store()
        let before = digest(store).inbox.count
        store.complete(TestBoard.widget)

        let after = digest(store).inbox
        #expect(after.count == before - 1)
        #expect(after.tasks.contains { $0.id == TestBoard.widget } == false)
    }

    /// An archived card is not in the Inbox either — but it is not in
    /// `inboxTasks` to begin with, so this is the claim that the filter above
    /// did not accidentally become the only one applied.
    @Test func anArchivedCaptureIsNotInTheInboxEither() {
        let store = TestBoard.store(tasks: TestBoard.tasks(archiving: [TestBoard.widget: 300]))
        #expect(digest(store).inbox.tasks.contains { $0.id == TestBoard.widget } == false)
    }

    // MARK: Boards and columns

    @Test func everyBoardComesAcrossWithItsOwnColumns() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: TestBoard.support),
                                    boards: TestBoard.boards)
        let published = digest(store)

        #expect(published.boards.map(\.id) == store.boards.map(\.id))
        for board in store.boards {
            let mirrored = try #require(published.board(id: board.id), "\(board.name) did not cross")
            #expect(mirrored.name == board.name)
            #expect(mirrored.columns.map(\.id) == board.columns.map(\.id))
            #expect(mirrored.columns.map(\.short) == board.columns.map(\.short))
        }
    }

    @Test func aColumnsCardsAreTheOnesTheBoardDraws() throws {
        let store = TestBoard.store()
        let published = digest(store)
        let backlog = try #require(published.column(id: BoardColumn.backlog.id))
        let onTheBoard = store.visibleTasks(in: BoardColumn.backlog.id)

        #expect(backlog.column.tasks.map(\.id) == onTheBoard.map(\.id))
        #expect(backlog.column.count == onTheBoard.count)
        #expect(backlog.board.id == SeedData.defaultBoard.id)
    }

    /// Done is the board's last column whatever it has been renamed to, and the
    /// board-overview widget leaves it off: it is the one column that only
    /// grows, so on any board older than a fortnight it is the largest number
    /// on the tile and the least interesting one. The rule is the board's own,
    /// read off position rather than off the word — a board whose Done column
    /// is called Published must lose *that* one.
    @Test func theColumnsAWidgetOffersAsWorkAreTheOnesBeforeDone() throws {
        let store = TestBoard.store(tasks: TestBoard.tasks(on: TestBoard.support),
                                    boards: TestBoard.boards)
        let published = digest(store)

        for board in store.boards {
            let mirrored = try #require(published.board(id: board.id))
            #expect(mirrored.doneColumn?.id == board.doneColumn?.id)
            #expect(mirrored.workingColumns.map(\.id) == board.workingColumns.map(\.id))
            #expect(mirrored.workingColumns.contains { $0.id == board.doneColumn?.id } == false,
                    "\(board.name) offers its Done column as somewhere to work")
        }
    }

    /// And the state that has to say something rather than draw an empty row: a
    /// board holding nothing but its Done column, which is what every freshly
    /// made board is.
    @Test func aBoardWithNothingButDoneOffersNoColumnsToWorkIn() throws {
        let bare = Board(name: "Bare", dot: .accent, columns: [BoardColumn.freshDone()],
                         codePrefix: "BR")
        let store = TestBoard.store(tasks: [], boards: [bare])
        let mirrored = try #require(digest(store).board(id: bare.id))

        #expect(mirrored.columns.count == 1)
        #expect(mirrored.workingColumns.isEmpty)
        #expect(mirrored.doneColumn != nil)
    }

    /// The count is the whole column and the rows are the first few of it. A
    /// widget's badge has to agree with the board's; its list cannot.
    @Test func theCountIsTheWholeColumnAndTheRowsAreTheFirstFew() throws {
        let store = ViewBoard.store(tasks: ViewBoard.deepTasks)
        let backlog = try #require(
            digest(store, today: ViewBoard.today).column(id: BoardColumn.backlog.id)?.column
        )

        #expect(backlog.count == 25)
        #expect(backlog.tasks.count == WidgetDigest.listLength)
        #expect(backlog.tasks.map(\.id) == store.visibleTasks(in: BoardColumn.backlog.id)
            .prefix(WidgetDigest.listLength).map(\.id))
    }

    // MARK: Saved views

    @Test func everyViewCarriesItsOwnCountAndItsOwnRows() throws {
        let store = ViewBoard.store()
        let published = digest(store, today: ViewBoard.today)

        #expect(published.views.map(\.id) == store.views.map(\.id))
        for view in store.views {
            let mirrored = try #require(published.view(id: view.id))
            #expect(mirrored.name == view.name)
            #expect(mirrored.symbol == view.symbol)
            #expect(mirrored.count == store.count(of: view, today: ViewBoard.today),
                    "\(view.name) reports \(mirrored.count)")
            #expect(mirrored.tasks.map(\.id)
                == store.tasks(in: view, today: ViewBoard.today)
                    .prefix(WidgetDigest.listLength).map(\.id))
        }
    }

    /// *Recently updated* is capped at twenty by the view itself and at eight by
    /// the digest, and the two caps mean different things: the pill says twenty,
    /// the widget shows eight. Taking `tasks.count` for the pill would have
    /// reported the digest's cap as the view's size.
    @Test func aViewsPillIsItsOwnLimitRatherThanTheDigestsCap() throws {
        let store = ViewBoard.store(tasks: ViewBoard.deepTasks)
        let recent = try #require(
            digest(store, today: ViewBoard.today).view(id: SavedView.id(of: .recentlyUpdated))
        )

        #expect(recent.count == 20)
        #expect(recent.tasks.count == WidgetDigest.listLength)
    }

    /// The extension has no `SavedView` and no table of the seeded ids, so the
    /// one thing it needs to recognise — Today, which is what a fresh saved-view
    /// widget starts on — comes across as a string. This is what holds that
    /// string to the enum it was copied from.
    @Test func todayIsRecognisableWithoutTheSavedViewEnum() throws {
        let store = ViewBoard.store()
        let published = digest(store, today: ViewBoard.today)
        let today = try #require(published.views.first { $0.preset == WidgetList.todayPreset })

        #expect(WidgetList.todayPreset == SavedView.Preset.today.rawValue)
        #expect(today.id == SavedView.id(of: .today))
    }

    // MARK: The two things that are not answers

    /// Whether a card is finished is a question about its board's last column,
    /// or about the Inbox's own completion. The extension cannot answer it and
    /// is not asked to.
    @Test func doneIsTheBoardsAnswerRatherThanAFieldOnTheCard() throws {
        let store = TestBoard.store()
        let published = digest(store)
        let done = try #require(published.column(id: BoardColumn.done.id)?.column)
        let backlog = try #require(published.column(id: BoardColumn.backlog.id)?.column)

        #expect(done.tasks.allSatisfy { $0.isDone }, "a card in Done did not read as done")
        #expect(backlog.tasks.allSatisfy { !$0.isDone })
    }

    @Test func theThemeTravelsSoTheWidgetWearsTheOneThatWasChosen() {
        let store = TestBoard.store()
        store.selectTheme(TestBoard.otherDarkTheme)

        let themes = digest(store).themes
        #expect(themes == store.themes)
        #expect(themes.theme(for: .dark).id == TestBoard.otherDarkTheme.id)
    }

    /// The appearance override decides which of the two slots a widget wears,
    /// and it is in `UserDefaults` rather than in the board — so it has to be
    /// read on the way past rather than found in the snapshot.
    @Test func theAppearanceOverrideTravelsWithIt() throws {
        // A suite of its own, because Swift Testing runs these in parallel and
        // `Preferences.defaults` is one global: a test that wrote the real
        // domain would be writing what every other suite is reading.
        let name = "widget-appearance-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: name))
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        suite.set(AppAppearance.dark.rawValue, forKey: AppAppearance.storageKey)

        let store = TestBoard.store()
        let published = Preferences.reading(suite) { digest(store) }
        #expect(published.appearance == .dark)
        // And what the widget does with it: an override wins over the scheme
        // the system handed the extension.
        #expect(published.appearance.slot(under: .light) == .dark)
        #expect(AppAppearance.system.slot(under: .light) == .light)
    }

    /// A due chip in a widget has to say what the same chip says on the board,
    /// so the day the lists were evaluated against travels with them rather
    /// than being read off the clock at render time.
    @Test func theDayTheListsWereBuiltAgainstTravelsWithThem() {
        #expect(digest(ViewBoard.store(), today: ViewBoard.today).today == ViewBoard.today)
    }

    // MARK: The file

    @Test func aDigestSurvivesAWriteAndARead() throws {
        let published = digest(TestBoard.store(tasks: TestBoard.tasks(on: TestBoard.support),
                                               boards: TestBoard.boards))
        let data = try #require(WidgetDigestFile.encoded(published))
        #expect(WidgetDigestFile.decode(data) == published)
    }

    /// What the change detection leans on: the same board twice is the same
    /// bytes twice. Without it every keystroke would wake every widget on the
    /// machine, because a dictionary that encoded in a different order each
    /// time is a digest that has always changed.
    @Test func theSameBoardEncodesToTheSameBytes() throws {
        let store = TestBoard.store()
        var first = digest(store)
        var second = digest(store)
        // The stamp is the one field that differs by construction, and is the
        // one field `publish` sets aside before comparing.
        let stamp = Date(timeIntervalSinceReferenceDate: 0)
        first.writtenAt = stamp
        second.writtenAt = stamp

        #expect(WidgetDigestFile.encoded(first) == WidgetDigestFile.encoded(second))
    }

    /// A digest from a build that meant something else by these fields is
    /// refused rather than migrated. The app rewrites it within half a second;
    /// a widget quietly showing another version's numbers would not be noticed
    /// at all.
    @Test func aDigestFromAnotherVersionIsRefused() throws {
        var published = digest(TestBoard.store())
        published.version = WidgetDigest.currentVersion + 1
        let data = try #require(WidgetDigestFile.encoded(published))

        #expect(WidgetDigestFile.decode(data) == nil)
        #expect(WidgetDigestFile.decode(Data("not a digest".utf8)) == nil)
    }
}

/// The URLs the widgets are wired with.
///
/// Written by one target and read by another, so a shape that drifted would be
/// a widget whose taps do nothing — reported, if at all, as "the widget is
/// broken". `DeepLinkTests` covers the task link, which is the one shape that
/// predates the widgets.
@Suite struct AppLinkTests {
    private static let destinations: [AppLink.Destination] = [
        .task(TestBoard.cafe), .board(SeedData.defaultBoard.id),
        .column(BoardColumn.backlog.id), .view(SavedView.id(of: .today)),
        .inbox, .newTask,
    ]

    @Test func everyDestinationRoundTripsThroughItsURL() {
        for destination in Self.destinations {
            let url = AppLink.url(destination)
            #expect(url.scheme == AppLink.scheme, "\(url)")
            #expect(AppLink.destination(of: url) == destination, "\(url) came back as something else")
        }
    }

    /// Every one of the six is a different URL, which is what stops a widget
    /// configured for one opening another.
    @Test func noTwoDestinationsShareAURL() {
        let urls = Self.destinations.map { AppLink.url($0).absoluteString }
        #expect(Set(urls).count == urls.count, "two destinations share a URL: \(urls)")
    }

    @Test func aURLThatIsNotOneOfOursNamesNothing() throws {
        let strangers = [
            "https://example.com/board/\(SeedData.defaultBoard.id.uuidString)",
            "otherapp://inbox",
            "simplekanban://board/not-a-uuid",
            "simplekanban://board",
            "simplekanban://elsewhere",
            // A host with something after it is not that host with something on
            // the end — it is a shape this build does not know.
            "simplekanban://inbox/\(UUID().uuidString)",
            "simplekanban://new/now",
        ]
        for text in strangers {
            let url = try #require(URL(string: text), Comment(rawValue: text))
            #expect(AppLink.destination(of: url) == nil, "\(text) was read as a destination")
        }
    }

    @Test func theSchemeAndHostAreMatchedWithoutRegardToCase() throws {
        let url = try #require(URL(string: "SimpleKanban://INBOX"))
        #expect(AppLink.destination(of: url) == .inbox)
    }
}

/// What happens when one of those URLs arrives.
///
/// The router is built here rather than reached through `TaskLink.router` for
/// `DeepLinkTests`' reason: the shared one is process-wide, and a suite whose
/// probes leaked a pending link into each other would pass or fail depending on
/// the order they ran in.
@MainActor
@Suite struct WidgetLinkRoutingTests {
    private func opened(_ destination: AppLink.Destination, in store: BoardStore) -> DeepLinkRouter {
        let router = DeepLinkRouter()
        router.open(AppLink.url(destination))
        router.resolve(in: store)
        return router
    }

    @Test func aBoardLinkGoesToThatBoard() {
        let store = TestBoard.store(boards: TestBoard.boards)
        #expect(store.activeBoardID == SeedData.defaultBoard.id)

        let router = opened(.board(TestBoard.support.id), in: store)
        #expect(router.failure == nil)
        #expect(store.activeBoardID == TestBoard.support.id)
    }

    /// A column is resolved to whichever board it is on *now*, because a column
    /// can be moved after the widget naming it was placed.
    @Test func aColumnLinkGoesToTheBoardTheColumnIsOn() {
        let store = TestBoard.store(boards: TestBoard.boards)
        let router = opened(.column(TestBoard.queue.id), in: store)

        #expect(router.failure == nil)
        #expect(store.activeBoardID == TestBoard.support.id)
        #expect(store.surface == .board)
    }

    @Test func aViewLinkOpensThatView() {
        let store = ViewBoard.store()
        let router = opened(.view(SavedView.id(of: .today)), in: store)

        #expect(router.failure == nil)
        #expect(store.surface == .view(SavedView.id(of: .today)))
    }

    /// The Inbox is a panel beside the board, so opening it means putting the
    /// board back as well as the panel out.
    @Test func anInboxLinkPutsThePanelOut() {
        let store = TestBoard.store()
        store.surface = .view(SavedView.id(of: .today))
        store.isInboxOpen = false

        let router = opened(.inbox, in: store)
        #expect(router.failure == nil)
        #expect(store.surface == .board)
        #expect(store.isInboxOpen)
    }

    /// The `+`. A card is made, it is put in front of the user, and its title
    /// field is asked for — a capture that arrived without one would be an
    /// untitled card the user has to go and find.
    @Test func aNewTaskLinkMakesACaptureWithItsTitleWaiting() throws {
        let store = TestBoard.store()
        let before = store.inboxTasks.count

        let router = opened(.newTask, in: store)
        #expect(router.failure == nil)

        let made = try #require(store.pendingTitleFocusID, "nothing asked for the title field")
        let task = try #require(store[made])
        #expect(task.placement == .inbox)
        #expect(task.title.isEmpty)
        #expect(store.inboxTasks.count == before + 1)
        #expect(store.isInboxOpen)
        #expect(store.surface == .board)
    }

    /// A widget goes on naming what it was set up with, and the four things it
    /// can name are all deletable. Each gets its own sentence: "that view no
    /// longer exists" tells somebody which widget to go and fix.
    @Test func aLinkToSomethingDeletedSaysWhichKindOfThingItWas() throws {
        let store = TestBoard.store()
        var titles: [String] = []

        for destination in [AppLink.Destination.board(UUID()), .column(UUID()), .view(UUID())] {
            let failure = try #require(opened(destination, in: store).failure,
                                       "\(destination) was swallowed")
            #expect(!failure.title.isEmpty)
            #expect(!failure.message.isEmpty)
            titles.append(failure.title)
        }
        #expect(Set(titles).count == titles.count, "two kinds share a sentence: \(titles)")
    }

    /// And the one that cannot be deleted still opens: there is always an Inbox
    /// and there is always somewhere to put a new card.
    @Test func theTwoDestinationsThatCannotGoAwayNeverFail() {
        let store = TestBoard.store()
        #expect(opened(.inbox, in: store).failure == nil)
        #expect(opened(.newTask, in: store).failure == nil)
    }
}

/// That the two bundles can actually reach each other.
///
/// Everything above would pass on a build whose entitlements name a group the
/// code does not, and the symptom would be a widget that draws its sample
/// forever while the app publishes into a container nothing else can see. This
/// reads the entitlement files off the disk the suite was compiled from — see
/// `SourceTree` — because there is no runtime value to inspect: the extension
/// is another process, and the app's own entitlements say nothing about it.
@MainActor
@Suite struct WidgetShareTests {
    private func groups(in file: String) throws -> [String] {
        let url = SourceTree.checkout.appending(path: "Resources/\(file)")
        let plist = try #require(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), format: nil
            ) as? [String: Any],
            "\(file) is not a property list"
        )
        return try #require(plist["com.apple.security.application-groups"] as? [String],
                            "\(file) joins no App Group")
    }

    /// The app's three entitlement files and the extension's two, each naming
    /// the group its platform's code expects. macOS insists the identifier
    /// begins with the team id and iOS insists it does not, so the pair is
    /// checked rather than one spelling.
    @Test func everyBundleJoinsTheGroupItsPlatformNames() throws {
        guard SourceTree.isReachable else { return }
        let mac = ["SimpleKanban-CloudKit.entitlements", "SimpleKanban.entitlements",
                   "SimpleKanbanWidgets.entitlements"]
        let ios = ["SimpleKanban-iOS-CloudKit.entitlements", "SimpleKanbanWidgets-iOS.entitlements"]

        for file in mac {
            #expect(try groups(in: file) == ["P52946XHRJ.group.com.n14395.SimpleKanban"],
                    "\(file) names another group")
        }
        for file in ios {
            #expect(try groups(in: file) == ["group.com.n14395.SimpleKanban"],
                    "\(file) names another group")
        }

        // And the constant the code actually calls `containerURL(for:)` with is
        // the one this platform's own files name — which is the half that would
        // still be wrong if the two lists above were merely internally
        // consistent with each other.
        #if os(macOS)
        #expect(try groups(in: mac[0]) == [WidgetShare.appGroup])
        #expect(try groups(in: "SimpleKanbanWidgets.entitlements") == [WidgetShare.appGroup])
        #else
        #expect(try groups(in: ios[0]) == [WidgetShare.appGroup])
        #expect(try groups(in: "SimpleKanbanWidgets-iOS.entitlements") == [WidgetShare.appGroup])
        #endif
    }

    /// Which sizes each widget offers.
    ///
    /// Read out of the source, because a `WidgetConfiguration` is not a value
    /// this process can enumerate — the extension is another target and the
    /// gallery is another process again. A family dropped from one of these
    /// lists is a size that quietly stops being offered, and the widgets
    /// somebody had at that size stop drawing.
    @Test func everyWidgetOffersTheSizesItIsDocumentedWith() throws {
        guard SourceTree.isReachable else { return }
        let expected = [
            "WidgetExtension/InboxWidget.swift": [".systemSmall", ".systemMedium", ".systemLarge"],
            "WidgetExtension/SavedViewWidget.swift": [".systemMedium", ".systemLarge"],
            // Both sizes, and the medium one is the same widget with fewer
            // rows rather than a layout of its own — see `ColumnWidget`.
            "WidgetExtension/ColumnWidget.swift": [".systemMedium", ".systemLarge"],
            "WidgetExtension/BoardOverviewWidget.swift": [".systemMedium"],
        ]
        for (path, families) in expected {
            let file = try #require(SourceTree.files().first { $0.path == path }, "\(path) is not there")
            let call = try #require(file.calls(headed: #"supportedFamilies\("#).first,
                                    "\(path) declares no supported families")
            for family in [".systemSmall", ".systemMedium", ".systemLarge"] {
                #expect(call.text.contains(family) == families.contains(family),
                        "\(path) offers \(call.text)")
            }
        }
    }

    /// That the board-overview widget draws the working columns rather than all
    /// of them, and the column widget still draws whichever one it was pointed
    /// at — a widget of what shipped this week is a perfectly good widget, so
    /// the filtering belongs at one point of use and not in the digest.
    ///
    /// Read out of the source for `everyWidgetOffersTheSizesItIsDocumentedWith`'s
    /// reason: the extension is another target, and `WidgetBoard.workingColumns`
    /// being right says nothing about which of the two the view calls.
    @Test func onlyTheBoardOverviewLeavesDoneOff() throws {
        guard SourceTree.isReachable else { return }
        let overview = try #require(
            SourceTree.files().first { $0.path == "WidgetExtension/BoardOverviewWidget.swift" }
        )
        #expect(overview.source.contains("board.workingColumns"),
                "the board overview draws every column, Done included")
        #expect(overview.source.contains("board.columns") == false,
                "the board overview still reaches for the unfiltered list")

        let column = try #require(
            SourceTree.files().first { $0.path == "WidgetExtension/ColumnWidget.swift" }
        )
        #expect(column.source.contains("workingColumns") == false,
                "the column widget refuses to show a Done column somebody chose")
    }

    /// The kinds the system stores against every widget somebody has placed.
    /// Renaming one orphans their widget silently, so they are named once and
    /// this is what says so.
    @Test func everyWidgetKindIsDistinct() {
        let kinds = WidgetShare.Kind.all
        #expect(kinds.count == 4)
        #expect(Set(kinds).count == kinds.count)
        #expect(kinds.allSatisfy { $0.hasPrefix("SimpleKanban") })
    }
}
