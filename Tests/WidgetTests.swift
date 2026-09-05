import Foundation
import Testing
@testable import LittleKanban

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
        let bare = Board(name: "Bare", columns: [BoardColumn.freshDone()],
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

    /// The limit crosses the fence so the widget can draw the `4/3` the board
    /// is drawing. A column shown as a plain `4` on the home screen while the
    /// app shows it over its limit would be the digest quietly disagreeing with
    /// the board, which is the one thing this file exists to prevent.
    @Test func aColumnsWipLimitTravelsWithItsCount() throws {
        let store = ViewBoard.store(tasks: ViewBoard.deepTasks)
        store.setColumnLimit(5, on: BoardColumn.backlog.id)

        let published = digest(store, today: ViewBoard.today)
        let backlog = try #require(published.column(id: BoardColumn.backlog.id)?.column)
        #expect(backlog.limit == 5)
        #expect(ColumnLoad(count: backlog.count, limit: backlog.limit) == .over)

        // Every other column arrives unlimited rather than defaulted to
        // something, so a widget on a board with no limits draws what it always
        // drew.
        let others = try #require(published.boards.first).columns.filter { $0.id != BoardColumn.backlog.id }
        #expect(others.isEmpty == false)
        #expect(others.allSatisfy { $0.limit == nil })
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

    /// *Recently updated* is capped at twenty by the view itself and at sixteen
    /// by the digest, and the two caps mean different things: the pill says
    /// twenty, the widget shows what fits. Taking `tasks.count` for the pill
    /// would have
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
            "littlekanban://board/not-a-uuid",
            "littlekanban://board",
            "littlekanban://elsewhere",
            // A host with something after it is not that host with something on
            // the end — it is a shape this build does not know.
            "littlekanban://inbox/\(UUID().uuidString)",
            "littlekanban://new/now",
        ]
        for text in strangers {
            let url = try #require(URL(string: text), Comment(rawValue: text))
            #expect(AppLink.destination(of: url) == nil, "\(text) was read as a destination")
        }
    }

    @Test func theSchemeAndHostAreMatchedWithoutRegardToCase() throws {
        let url = try #require(URL(string: "LittleKanban://INBOX"))
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

    /// The `+`, which is **the app's own `+`** — a different control on each
    /// platform, and both of them a field with the keyboard in it.
    ///
    /// Where the Inbox is a panel, that is the panel's one-line composer: the
    /// card is not made until something is typed into it. On the phone there is
    /// no panel to put a composer in, so it is the card's whole editor in a
    /// sheet, which is what `quickCapture()` has always done for the button
    /// floating over the tab bar.
    @Test func aNewTaskLinkOpensWhicheverCaptureThisPlatformHas() throws {
        let store = TestBoard.store()
        let before = store.tasks.count

        let router = opened(.newTask, in: store)
        #expect(router.failure == nil)
        #expect(store.surface == .board)

        if BoardStore.inboxOpensBesideTheBoard {
            #expect(store.isInboxOpen, "the panel that draws the composer is not out")
            #expect(store.addingPlacement == .inbox, "no composer is open on the Inbox")
            #expect(store.draft.isEmpty)
            // Nothing is written down until something is typed, which is the
            // whole difference between a composer and an editor — and why this
            // route leaves no untitled card behind if it is opened and ignored.
            #expect(store.tasks.count == before)
        } else {
            let made = try #require(store.pendingTitleFocusID, "nothing asked for the title field")
            let task = try #require(store[made])
            #expect(task.placement == .inbox)
            #expect(task.title.isEmpty)
            #expect(store.sheetID == made, "the sheet that carries the field is not up")
            #expect(store.tasks.count == before + 1)
        }
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
        let mac = ["LittleKanban-CloudKit.entitlements", "LittleKanban.entitlements",
                   "LittleKanbanWidgets.entitlements", "LittleKanbanShare.entitlements"]
        let ios = ["LittleKanban-iOS-CloudKit.entitlements", "LittleKanbanWidgets-iOS.entitlements",
                   "LittleKanbanShare-iOS.entitlements"]

        for file in mac {
            #expect(try groups(in: file) == ["P52946XHRJ.group.com.n14395.LittleKanban"],
                    "\(file) names another group")
        }
        for file in ios {
            #expect(try groups(in: file) == ["group.com.n14395.LittleKanban"],
                    "\(file) names another group")
        }

        // And the constant the code actually calls `containerURL(for:)` with is
        // the one this platform's own files name — which is the half that would
        // still be wrong if the two lists above were merely internally
        // consistent with each other.
        #if os(macOS)
        #expect(try groups(in: mac[0]) == [WidgetShare.appGroup])
        #expect(try groups(in: "LittleKanbanWidgets.entitlements") == [WidgetShare.appGroup])
        #expect(try groups(in: "LittleKanbanShare.entitlements") == [WidgetShare.appGroup])
        #else
        #expect(try groups(in: ios[0]) == [WidgetShare.appGroup])
        #expect(try groups(in: "LittleKanbanWidgets-iOS.entitlements") == [WidgetShare.appGroup])
        #expect(try groups(in: "LittleKanbanShare-iOS.entitlements") == [WidgetShare.appGroup])
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

    /// **Every tile is filled by the rows it has room for.**
    ///
    /// `WidgetRowCount` works its answer out from the tile rather than from the
    /// family — the type itself shows why — so what is left worth pinning is
    /// the arithmetic and its two ends: that a medium tile on a current phone
    /// holds five headed rows and six bullets rather than the four of each it
    /// drew when one constant had to serve every phone, that the smallest phone
    /// still gets a count it can draw without overrunning its margin, and that
    /// no tile can ask for more rows than the digest carries.
    ///
    /// The row sizes are read out of the extension's source, which is another
    /// target — `everyWidgetOffersTheSizesItIsDocumentedWith`'s reason — and the
    /// counts are worked out here by stacking rows one at a time, which is a
    /// different sum from the division the source does. An off-by-one in the
    /// gap, which is the whole bug class here, shows up as the two disagreeing.
    @Test func everyTileIsFilledByTheRowsItHasRoomFor() throws {
        guard SourceTree.isReachable else { return }
        let file = try #require(
            SourceTree.files().first { $0.path == "WidgetExtension/WidgetChrome.swift" }
        )
        func metric(_ name: String) throws -> (task: Double, bullet: Double) {
            let pattern = try Regex(
                #"var \#(name): CGFloat \{\s*switch self \{\s*case \.task: (\d+)\s*case \.bullet: (\d+)"#
            )
            let found = try #require(file.source.firstMatch(of: pattern),
                                     "no \(name) on WidgetRowCount.Shape")
            return (Double(found.output[1].substring!)!, Double(found.output[2].substring!)!)
        }
        let height = try metric("height")
        let gap = try metric("gap")
        #expect(file.source.contains("static let ceiling = WidgetDigest.listLength"),
                "the row count is not clamped to what the digest carries")

        /// Rows stacked into `room` one at a time, which is the question the
        /// tile actually asks.
        func fits(_ room: Double, row: Double, gap: Double) -> Int {
            var count = 0
            var used = 0.0
            while used + (count == 0 ? row : gap + row) <= room {
                used += count == 0 ? row : gap + row
                count += 1
            }
            return min(WidgetDigest.listLength, max(1, count))
        }

        // A tile's content is its family size less the system's 16pt margins on
        // each side; a headed list is that less the heading and its gap.
        let heading = 16.0
        for (tile, headed, bullets) in [
            // The smallest phone still supported: 321×148 and 321×324.
            (116.0, 4, 5),
            // 6.1": 338×158 and 338×354.
            (126.0, 5, 6),
            // 6.7" and the desk: 364×170, 360×170.
            (138.0, 5, 6),
        ] {
            #expect(fits(tile - heading - 6, row: height.task, gap: gap.task) == headed,
                    "a \(tile)pt medium tile draws the wrong number of headed rows")
            #expect(fits(tile, row: height.bullet, gap: gap.bullet) == bullets,
                    "a \(tile)pt medium tile draws the wrong number of bullets")
        }
        // And the large family, whose heading sits on an 8pt gap. Fifteen is
        // what a 6.7" phone holds, which is why the digest carries sixteen.
        for (tile, rows) in [(292.0, 13), (322.0, 14), (350.0, 15)] {
            #expect(fits(tile - heading - 8, row: height.task, gap: gap.task) == rows,
                    "a \(tile)pt large tile draws the wrong number of rows")
        }
        #expect(fits(350 - heading - 8, row: height.task, gap: gap.task) < WidgetDigest.listLength,
                "the digest carries no spare row over what the tallest tile draws")
    }

    /// That every list takes its length from the space it is in, and that the
    /// saved view's medium is the one that takes it in bullets.
    ///
    /// The two shapes are different heights on different gaps, and one shape for
    /// both is what drew four bullets in a box with room for six. A literal
    /// `prefix(4)` left behind anywhere would be the older bug returning: a list
    /// that draws the same length whatever tile it is on.
    @Test func everyListTakesItsLengthFromTheSpaceItIsIn() throws {
        guard SourceTree.isReachable else { return }
        func source(_ path: String) throws -> String {
            try #require(SourceTree.files().first { $0.path == path }, "\(path) is not there").source
        }
        let lists = [
            "WidgetExtension/InboxWidget.swift",
            "WidgetExtension/ColumnWidget.swift",
            "WidgetExtension/SavedViewWidget.swift",
        ]
        for path in lists {
            let text = try source(path)
            #expect(text.contains("WidgetRowSpace"),
                    "\(path) draws a list without measuring the room for it")
            #expect(text.contains(/prefix\(\d/) == false,
                    "\(path) still cuts a list at a fixed length")
        }
        #expect(try source("WidgetExtension/SavedViewWidget.swift").contains("shape: .bullet"),
                "the saved-view medium is not measured in bullets")
        for path in lists.dropLast() {
            #expect(try source(path).contains("shape: .bullet") == false,
                    "\(path) draws a heading over rows and took the bullet shape")
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
        #expect(kinds.allSatisfy { $0.hasPrefix("LittleKanban") })
    }
}
