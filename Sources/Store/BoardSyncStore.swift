import CoreData
import Foundation
import OSLog
import SwiftData

/// The board's SwiftData store, and the CloudKit sync that comes with it.
///
/// Sits where `BoardFile` sat: ``BoardStore`` hands it a `BoardSnapshot` and
/// asks for one back, and knows nothing about records. What it gains by the
/// swap is granularity — ``apply(_:)`` writes only the records that actually
/// changed, so a card edited on one device is one record for CloudKit to
/// reconcile rather than the whole board.
///
/// `board.json` does not go away. It keeps the roles SwiftData has no answer
/// for: rolling backups, export, import, and the recovery path when the store
/// itself cannot be opened. See ``BoardStore`` for how the two are ordered.
/// Whether the person wants their board on their other devices.
///
/// A preference rather than board data, so it lives in `@AppStorage` beside the
/// appearance and the sort order — a device that has been taken off sync should
/// stay off it, and that fact is this machine's, not the board's.
///
/// Read before the store is built, which is why it is a plain `UserDefaults`
/// read here and an `@AppStorage` binding in the settings screen. Defaults to
/// on: somebody signed in to iCloud who set the app up on two devices expects
/// the second one to show their board.
enum SyncPreference {
    static let storageKey = "CardstockSyncEnabled"

    /// Whether sync can work in this build at all, which is a fact about how
    /// the app was signed rather than anything the person chose. See
    /// ``CloudKitEntitlement``: asking for a container the build has no
    /// entitlement for is a crash, not a failure, so nothing may consult the
    /// preference without consulting this first.
    ///
    /// The settings screen reads it too, because a switch that cannot do
    /// anything should say so rather than sit there looking willing.
    static var isAvailable: Bool {
        CloudKitEntitlement.isSigned(for: SyncSchema.cloudContainerID)
    }

    static var isOn: Bool {
        // Tests get the same guard `BoardFile.default` has, and for the same
        // reason with more at stake: a suite that reached iCloud would edit the
        // developer's real board on every device they own.
        guard !BoardFile.isRunningTests else { return false }
        guard isAvailable else { return false }
        guard UserDefaults.standard.object(forKey: storageKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: storageKey)
    }
}

/// Which of the three lists a record set actually carries — see
/// ``BoardSyncStore/carriedLists()``.
///
/// Deliberately not `@MainActor`, unlike the protocol below: ``SharedList``
/// reads these from a `nonisolated` context.
struct SyncedLists: OptionSet, Sendable {
    let rawValue: Int
    static let themes = SyncedLists(rawValue: 1 << 0)
    static let views = SyncedLists(rawValue: 1 << 1)
    static let palette = SyncedLists(rawValue: 1 << 2)
}

/// What ``BoardStore`` asks of its record store, as a seam.
///
/// `BoardSyncStore` is the only conformer the app ships. The protocol exists
/// because one of the store's failure modes cannot be produced on purpose with
/// a real container — `load()` throwing — and the behaviour that failure must
/// provoke (withholding every push until a read succeeds; see
/// `BoardStore.isSyncReadBlocked`) is exactly the kind of never-executed
/// fallback this project has learned not to trust. `SyncStoreTests` conforms
/// a wrapper that fails on command.
/// The ids a snapshot spans, as bare sets — worn two ways by the deletion
/// licence.
///
/// ``BoardStore`` keeps one as its **baseline**: the ids it last agreed the
/// records hold, reset by every adoption and every push. The difference
/// between the baseline and the snapshot being pushed is the **tombstone
/// set** — the ids that left the board *on this device, by someone's hand* —
/// and ``SyncStoring/apply(_:deleting:)`` may delete those records and no
/// others. The base-names-it rule turned out not to be a licence at all: any
/// skew between the base and the snapshot — a launch race, a store holding a
/// board twice under different ids, a read taken mid-import — read as a
/// deletion nobody made, travelled to every device, and was the third data
/// loss in a week. Evidence of an actual deletion is the only licence left.
struct SyncIDs: Sendable, Equatable {
    var boards: Set<Board.ID> = []
    var columns: Set<BoardColumn.ID> = []
    var tasks: Set<TaskItem.ID> = []
    var labels: Set<String> = []

    static let none = SyncIDs()

    static func of(_ snapshot: BoardSnapshot) -> SyncIDs {
        SyncIDs(
            boards: Set(snapshot.boards.map(\.id)),
            columns: Set(snapshot.boards.flatMap(\.columns).map(\.id)),
            tasks: Set(snapshot.tasks.map(\.id)),
            labels: Set(snapshot.labels.map(\.key))
        )
    }

    /// What this set holds and `other` does not: the ids that left.
    func subtracting(_ other: SyncIDs) -> SyncIDs {
        SyncIDs(
            boards: boards.subtracting(other.boards),
            columns: columns.subtracting(other.columns),
            tasks: tasks.subtracting(other.tasks),
            labels: labels.subtracting(other.labels)
        )
    }

    var isEmpty: Bool {
        boards.isEmpty && columns.isEmpty && tasks.isEmpty && labels.isEmpty
    }
}

@MainActor
protocol SyncStoring: AnyObject {
    var isSyncing: Bool { get }
    func load() throws -> BoardSnapshot?
    func carriedLists() throws -> SyncedLists
    func hasStoredTaskOrder() throws -> Bool
    func backfillTaskPositions(from taskIDs: [TaskItem.ID]) throws
    func hasStoredBoardSymbols() throws -> Bool
    func backfillBoardSymbols(from boards: [Board]) throws
    func apply(_ snapshot: BoardSnapshot, deleting: SyncIDs) throws
    func reconnect()
}

extension SyncStoring {
    /// A write that deletes nothing — what every caller without a deletion to
    /// report means, and the only spelling most tests need.
    func apply(_ snapshot: BoardSnapshot) throws {
        try apply(snapshot, deleting: .none)
    }
}

@MainActor
final class BoardSyncStore: SyncStoring {
    private static let logger = Logger(subsystem: "com.n14395.Cardstock", category: "sync")

    private(set) var container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// How the container was opened, kept so ``reconnect()`` can open it the
    /// same way again. `nil` for a store handed a ready-made container — the
    /// in-memory ones every test uses — which therefore cannot reconnect.
    private var opening: (url: URL, cloudKit: ModelConfiguration.CloudKitDatabase)?

    /// When ``reconnect()`` last rebuilt the container, so a pull repeated in
    /// frustration does not churn out a mirror per tug.
    private var lastReconnectedAt: Date?

    /// What the last write left in the store, so the next one can tell which
    /// records actually changed without reading them all back.
    private var lastWritten: BoardSnapshot?

    /// Test hook: forces every JSON encode in this store to fail. The failure
    /// paths are unreachable with the real coders and the values the app
    /// writes, and a fallback that has never been executed is a comment —
    /// see `SyncStoreTests`, which runs both of them through this.
    var encodingFailsForTesting = false

    /// Whether this store is talking to iCloud. `false` for the in-memory
    /// container tests use, and for a store the user has turned sync off on.
    let isSyncing: Bool

    // MARK: Opening

    init(container: ModelContainer, isSyncing: Bool) {
        self.container = container
        self.isSyncing = isSyncing
    }

    /// The app's store, syncing if it can and local if it cannot.
    ///
    /// **The only place in the app that names a CloudKit container**, and the
    /// only place that may. Asking for one this build was not signed for does
    /// not fail at open time — it opens, and then CoreData traps on its own
    /// queue half a second later with nothing to catch. So the entitlement is
    /// checked here, before the ask, and a build without it opens the same
    /// store file locally. See ``CloudKitEntitlement``.
    ///
    /// Being signed for the container still does not mean iCloud will answer —
    /// nobody may be signed in — but that one *is* a thrown error, and it is
    /// not a reason to hand somebody an empty board either, so it falls back to
    /// the same local store. The records are the same either way, and turning
    /// sync on later just starts uploading them.
    ///
    /// Failing to open the store *at all* does throw. That one the caller
    /// has to hear about, because `board.json` is the answer to it and a store
    /// that could not be read must never look like a board with nothing on it.
    static func app(syncing: Bool, at url: URL) throws -> BoardSyncStore {
        // Before the store opens, while nothing else has the file: the pass
        // that keeps it a board rather than an archive of every board there
        // has been. See ``sweepHistory(at:olderThan:now:)``.
        sweepHistory(at: url)
        if let container = cloudContainer(syncing: syncing) {
            do {
                return try opened(at: url, cloudKit: .private(container), isSyncing: true)
            } catch {
                logger.notice("""
                    Sync is on but the iCloud container could not be opened, so the board is local \
                    for this session: \(error.localizedDescription)
                    """)
            }
        } else if syncing {
            logger.notice("""
                Sync is on, but this build is not signed for \(SyncSchema.cloudContainerID), so the \
                board is local. Point CODE_SIGN_ENTITLEMENTS at the -CloudKit files to change that.
                """)
        }
        return try opened(at: url, cloudKit: .none, isSyncing: false)
    }

    /// The container to ask for, or `nil` to stay local — **the whole decision,
    /// in one pure function**, because getting it wrong is a crash rather than
    /// a bug and a crash is not a thing a test can catch. `SyncEntitlementTests`
    /// calls this directly with each combination.
    ///
    /// Three ways to answer `nil`, and all three are load-bearing:
    ///
    /// - The person turned sync off.
    /// - **This build is not signed for the container.** Asking anyway opens
    ///   fine and then traps on CoreData's CloudKit queue about half a second
    ///   later. See ``CloudKitEntitlement``.
    /// - A test is running. `SyncPreference.isOn` guards that too, but this
    ///   function is reachable without it, and a suite that reached iCloud
    ///   would edit the developer's real board on every device they own.
    static func cloudContainer(
        syncing: Bool,
        isRunningTests: Bool = BoardFile.isRunningTests,
        signedContainers: [String] = CloudKitEntitlement.containers
    ) -> String? {
        guard syncing, !isRunningTests else { return nil }
        let wanted = SyncSchema.cloudContainerID
        return signedContainers.contains(wanted) ? wanted : nil
    }

    private static func opened(
        at url: URL, cloudKit: ModelConfiguration.CloudKitDatabase, isSyncing: Bool
    ) throws -> BoardSyncStore {
        let store = BoardSyncStore(container: try openedContainer(at: url, cloudKit: cloudKit),
                                   isSyncing: isSyncing)
        store.opening = (url, cloudKit)
        return store
    }

    private static func openedContainer(
        at url: URL, cloudKit: ModelConfiguration.CloudKitDatabase
    ) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(SyncSchema.models), url: url, cloudKitDatabase: cloudKit
        )
        return try ModelContainer(for: Schema(SyncSchema.models), configurations: configuration)
    }

    // MARK: Fetching, by the only lever there is

    /// Reopens the container, which is the one way to ask the mirror to fetch.
    ///
    /// The mirror schedules its own trips to CloudKit and takes no instruction
    /// about when one happens — with a single exception it does not know it
    /// offers: **opening the store runs its setup-and-import immediately.**
    /// That is why quitting and relaunching the app always "synced" when the
    /// Sync Now button did not: the button read a store the mirror had not
    /// refilled, while the relaunch made it fetch. So the button now does what
    /// the relaunch did. The rebuilt container holds the same records — the
    /// store file does not move — and the fresh mirror imports what the old
    /// one was waiting to be pushed about; each import lands as an ordinary
    /// remote-change notification and is merged the ordinary way.
    ///
    /// Throttled, because the gesture invites repetition: a pull tugged five
    /// times in frustration should not stand up five mirrors. Within the
    /// window the pull still pushes and re-reads; it just does not reopen.
    ///
    /// A store with no mirror has nothing to wake: local-only and in-memory
    /// stores keep their container, and a rebuild that fails keeps the old
    /// one too — a working stale mirror beats a broken fresh one.
    func reconnect() {
        guard isSyncing else { return }
        if let last = lastReconnectedAt, Date.now.timeIntervalSince(last) < Self.reconnectWindow {
            return
        }
        rebuild()
        lastReconnectedAt = .now
    }

    /// The rebuild itself, unthrottled and mirror-or-not — the seam
    /// `SyncMaintenanceTests` drives, since a test can hold no real mirror.
    func rebuild() {
        guard let opening else { return }
        do {
            container = try Self.openedContainer(at: opening.url, cloudKit: opening.cloudKit)
            // The diff base survives on purpose: it is what this device has
            // seen of the *records*, and the records did not move.
        } catch {
            Self.logger.error("The container could not be reopened; the old one stands: \(error.localizedDescription)")
        }
    }

    static let reconnectWindow: TimeInterval = 10

    /// Beside `board.json`, in the same Application Support folder, so a
    /// person looking for their data finds both halves in one place — and so
    /// deleting the container still resets everything.
    static var defaultURL: URL {
        BoardFile.default.url.deletingLastPathComponent().appending(path: "board.store")
    }

    /// A store that never touches the disk or the network, which is what every
    /// test and preview gets. The same guard `BoardFile.default` uses: a suite
    /// that reaches iCloud is a suite that edits somebody's real board.
    static func inMemory() throws -> BoardSyncStore {
        let configuration = ModelConfiguration(
            schema: Schema(SyncSchema.models),
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: Schema(SyncSchema.models), configurations: configuration)
        return BoardSyncStore(container: container, isSyncing: false)
    }

    // MARK: Maintenance

    /// Deletes the persistent history the mirror no longer needs, and gives
    /// the pages back.
    ///
    /// CloudKit sync runs on Core Data's persistent history — every save
    /// appends transactions, and the mirroring delegate reads them to know
    /// what to export. What nothing does, on any layer, is *delete* them:
    /// SwiftData has no knob for it, and the container keeps the log forever.
    /// Measured on a real device after a week of use (and one runaway write
    /// loop): 476,096 transactions, 2.3 million change rows, a 149 MB file
    /// for a 110 KB board. Unbounded by design is still unbounded.
    ///
    /// So the app prunes for itself, before the store opens each launch:
    /// history older than `olderThan` is deleted, and — when the file has
    /// grown past ``vacuumThreshold`` — the store is reopened once with
    /// `NSSQLiteManualVacuumOption` so SQLite returns the freed pages to the
    /// filesystem rather than keeping the file at its high-water mark.
    /// Measured against a copy of the 149 MB store: 143 MB on disk to 6.9 MB,
    /// the board unchanged. Below the threshold the vacuum is skipped, not
    /// because it would fail but because it copies the whole file to reclaim
    /// nothing a healthy store cannot simply reuse: freed pages feed later
    /// writes either way, so a small store merely plateaus.
    ///
    /// **The window is the safety.** The delegate has consumed anything a
    /// week old on any device that has been online at all, so pruning behind
    /// it costs nothing. The exception is a device offline for longer than
    /// the window *with unpushed edits*: deleting history its mirror has not
    /// exported makes the mirror re-baseline — drop the local records and
    /// re-import from the server. That used to be the disaster scenario; the
    /// deletion licence makes it additive (see ``apply(_:deleting:)``), and
    /// the board file still holds every local edit for the merge that
    /// follows, so the cost is bandwidth rather than work. A deliberate
    /// trade, and the reason the window is seven days rather than one.
    ///
    /// Failures here are logged and swallowed: a maintenance pass must never
    /// stand between the person and their board.
    static func sweepHistory(
        at url: URL, olderThan window: TimeInterval = 7 * 86_400, now: Date = .now
    ) {
        // Never on a store that does not exist — loading one creates the
        // file, and a first launch must keep meaning "the store is empty".
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            // Delete first, then reopen with the vacuum option, so the space
            // freed by this pass comes back this launch rather than next.
            let pruning = try maintenanceContainer(at: url, vacuuming: false)
            defer { close(pruning) }
            let context = pruning.newBackgroundContext()
            try context.performAndWait {
                let cutoff = now.addingTimeInterval(-window)
                try context.execute(NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff))
            }
        } catch {
            logger.error("The history sweep failed; the log stands until the next launch: \(error.localizedDescription)")
            return
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > Self.vacuumThreshold else { return }
        do {
            close(try maintenanceContainer(at: url, vacuuming: true))
        } catch {
            logger.error("The vacuum failed; the file keeps its high-water mark: \(error.localizedDescription)")
        }
    }

    /// Twice the biggest store a busy board has honestly earned, with its
    /// CloudKit bookkeeping — the healthy one measured 7 MB. Below this the
    /// file is left to reuse its own pages.
    static let vacuumThreshold = 32 * 1_048_576

    /// Whether any history transactions remain in the store — the test seam
    /// for ``sweepHistory(at:olderThan:now:)``, which has nothing else to
    /// observe: the whole point of the sweep is that the board it leaves
    /// behind is indistinguishable from the board it found.
    static func historyRemains(at url: URL) throws -> Bool {
        let container = try maintenanceContainer(at: url, vacuuming: false)
        defer { close(container) }
        let context = container.newBackgroundContext()
        return try context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: .distantPast)
            let result = try context.execute(request) as? NSPersistentHistoryResult
            let transactions = result?.result as? [NSPersistentHistoryTransaction]
            return transactions?.isEmpty == false
        }
    }

    /// A plain Core Data stack on the same file, for the requests SwiftData
    /// cannot make. History tracking stays on — the store was created with it
    /// and must never be opened without it — and the CloudKit options stay
    /// off: this stack maintains the store, it does not mirror it.
    private static func maintenanceContainer(
        at url: URL, vacuuming: Bool
    ) throws -> NSPersistentContainer {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: SyncSchema.models) else {
            throw CocoaError(.persistentStoreIncompatibleSchema)
        }
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        if vacuuming {
            description.setOption(true as NSNumber, forKey: NSSQLiteManualVacuumOption)
        }
        let container = NSPersistentContainer(name: "CardstockMaintenance", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        return container
    }

    /// Detaches the maintenance stack's store so the file is fully released
    /// before the real container opens it.
    private static func close(_ container: NSPersistentContainer) {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
    }

    // MARK: Reading

    /// The board as the store holds it, or `nil` when the store is empty — a
    /// first launch, which the caller answers by seeding or by importing
    /// `board.json`.
    ///
    /// Duplicates are settled here rather than prevented, because CloudKit
    /// cannot enforce uniqueness: two records under one id keep the one whose
    /// `updatedAt` is newer, which is last-writer-wins applied to the whole
    /// record. Sub-tasks and activity merge by id instead, per record, so an
    /// edit made on each of two devices keeps both.
    func load() throws -> BoardSnapshot? {
        let meta = try settled(context.fetch(FetchDescriptor<StoredMeta>()))
        let boards = try context.fetch(FetchDescriptor<StoredBoard>())
        let labels = try context.fetch(FetchDescriptor<StoredLabel>())
        let tasks = try context.fetch(FetchDescriptor<StoredTask>())
        guard meta != nil || !boards.isEmpty || !tasks.isEmpty else { return nil }

        let snapshot = BoardSnapshot(
            tasks: Self.ordered(Self.deduplicated(tasks, by: \.id, newest: \.updatedAt))
                .map(Self.value(of:)),
            boards: Self.deduplicated(boards, by: \.id, newest: \.createdAt)
                .sorted { $0.position < $1.position }
                .map(Self.value(of:)),
            labels: Self.deduplicated(labels, by: \.key, newest: { _ in Date.distantPast })
                .sorted { $0.position < $1.position }
                .map(Self.value(of:)),
            nextSerial: meta?.nextSerial ?? BoardSnapshot.baseSerial,
            activeBoardID: meta?.activeBoardID,
            // Each of the three falls back to what a board with none of them
            // means, and each is *also* reported as absent by ``carriedLists``
            // — because the caller has to tell "nobody has written one" from
            // "somebody wrote this one", and a fallback cannot say which it is.
            themes: Self.decoded(ThemeSettings.self, from: meta?.themesJSON) ?? .seed,
            viewsChangedAt: meta?.viewsChangedAt,
            paletteChangedAt: meta?.paletteChangedAt,
            themesChangedAt: meta?.themesChangedAt
        )
        var carried = snapshot
        carried.views = Self.decoded([SavedView].self, from: meta?.viewsJSON) ?? snapshot.views
        carried.palette = Self.decoded([PaletteSwatch].self, from: meta?.paletteJSON) ?? snapshot.palette
        // The dedup above settles the three record types that stand on their
        // own. This settles the three that hang off one — a board's columns, a
        // task's sub-tasks and its activity — which CloudKit can leave two of
        // just as easily and which nothing was settling at all. The base is set
        // to the settled snapshot, not the raw one, because the diff has to
        // describe what the caller was actually given.
        carried = carried.settlingDuplicates()
        // **Only a whole read becomes the diff base.** The base carries two
        // facts that are the same on every ordinary read and part company on
        // this one: what the records hold, which is what the diff needs, and
        // what this device has taken on, which is what licenses it to delete.
        // A read the caller then declines — see
        // ``BoardSnapshot/hasUnresolvedPlacements`` — advanced the first and
        // not the second, and the next save deleted the board it had read and
        // not adopted. Leaving the base where it was keeps the arriving records
        // unseen, which is exactly what protects them.
        if !carried.hasUnresolvedPlacements { lastWritten = carried }
        return carried
    }

    /// Which of the three shared lists the records actually hold, as opposed to
    /// which ones ``load()`` had to invent an answer for.
    ///
    /// The distinction is the whole of the upgrade guard. `load()` hands back a
    /// ``BoardSnapshot``, whose lists are not optional, so a record written
    /// before these attributes existed comes back wearing the seeded seven and
    /// the seed six — indistinguishable, from the outside, from another device
    /// saying "I have exactly the defaults". Reading the one as the other is
    /// how a view somebody made was lost on the launch after they made it.
    /// This is the question that separates them, and ``SharedList`` is what
    /// does the separating.
    ///
    /// Its own call rather than a field on the snapshot, for `hasStoredTaskOrder`'s
    /// reason: the snapshot is the *document* shape and is written to disk, and
    /// what one particular record set happens to carry is not a fact about the
    /// board.
    func carriedLists() throws -> SyncedLists {
        guard let meta = try settled(context.fetch(FetchDescriptor<StoredMeta>())) else { return [] }
        var carried: SyncedLists = []
        if meta.themesJSON != nil { carried.insert(.themes) }
        if meta.viewsJSON != nil { carried.insert(.views) }
        if meta.paletteJSON != nil { carried.insert(.palette) }
        return carried
    }

    private static func decoded<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// Whether every task record already carries its manual board-order rank.
    /// Records written before `StoredTask.position` was added are intentionally
    /// distinguishable from the first row, whose valid position is zero.
    func hasStoredTaskOrder() throws -> Bool {
        let records = try context.fetch(FetchDescriptor<StoredTask>())
        return Self.deduplicated(records, by: \.id, newest: \.updatedAt).allSatisfy { $0.position != nil }
    }

    /// Whether every board record already carries a mark. Records written
    /// before ``StoredBoard/symbol`` was added carry `nil`, which is a
    /// different answer from a board wearing ``SymbolMark/boardFallback``.
    func hasStoredBoardSymbols() throws -> Bool {
        let records = try context.fetch(FetchDescriptor<StoredBoard>())
        return Self.deduplicated(records, by: \.id, newest: \.createdAt).allSatisfy { $0.symbol != nil }
    }

    /// Gives pre-mark records the glyph from the local board file without
    /// touching anything else on them — which is the mark `migrate(v15:)` dealt
    /// that board, so a synced install upgrades to the same sidebar an
    /// unsynced one does. A board the file has never seen takes the fallback,
    /// the way it would if it had just been made.
    func backfillBoardSymbols(from boards: [Board]) throws {
        let marks = Dictionary(boards.map { ($0.id, $0.symbol) }, uniquingKeysWith: { first, _ in first })
        for record in try context.fetch(FetchDescriptor<StoredBoard>()) where record.symbol == nil {
            record.symbol = marks[record.id] ?? SymbolMark.boardFallback
        }
        try context.save()
    }

    /// Gives pre-position records the order from the local board file without
    /// touching their content. A remote-only card follows the known rows.
    func backfillTaskPositions(from taskIDs: [TaskItem.ID]) throws {
        let records = Self.deduplicated(
            try context.fetch(FetchDescriptor<StoredTask>()), by: \.id, newest: \.updatedAt
        )
        let positions = Dictionary(
            taskIDs.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        var next = taskIDs.count
        for record in records {
            if let position = positions[record.id] {
                record.position = position
            } else {
                record.position = next
                next += 1
            }
        }
        if context.hasChanges { try context.save() }
        lastWritten = nil
    }

    // MARK: Writing

    /// Writes only what changed.
    ///
    /// The diff is the reason this layer exists. Rewriting every record on
    /// every keystroke would hand CloudKit the whole board to reconcile and
    /// undo the granularity the schema was designed for, so each record is
    /// compared against what the last write left and touched only if it
    /// differs.
    ///
    /// **And the diff is evidence, not only economy.** `lastWritten` is
    /// everything this device has actually seen: what `load()` last read back,
    /// or what the last write left. A record in the store it does not name is
    /// not one the person deleted — on a device whose CloudKit import is still
    /// landing, which is every fresh install for its first minutes, it is
    /// somebody else's board arriving. So the writers below insert freely and
    /// overwrite **only what the diff base names** — with one exception, where
    /// there is a clock to argue with: an unseen task record older than the
    /// value in hand is one this device is genuinely ahead of, so it is
    /// written, the last-writer-wins ``deduplicated(_:by:newest:)`` already
    /// settles duplicate records with. An apply with no base at all adds and
    /// disturbs nothing.
    ///
    /// **Deleting takes more than the base.** "The base names it and the
    /// snapshot does not" turned out to be met by every kind of skew as well
    /// as by deletions — a launch race, a read taken mid-import, a store
    /// holding one board under two id-sets — and each false positive was a
    /// deletion replayed onto every device, then a fresh record minted for
    /// the reinsert, forever. So deletion now requires `deleting`: the
    /// ``SyncIDs`` the caller can attest actually left its board — see
    /// `BoardStore.syncBaseline` for how it knows. A tombstone lands even on
    /// a record the base never named, because a deletion made here must not
    /// resurface; everything else absent-but-untombstoned survives to be read
    /// back, which is the recoverable direction. `FreshDeviceTests` holds the
    /// fresh-install sequence and `DeletionLicenseTests` the licence itself.
    func apply(_ snapshot: BoardSnapshot, deleting: SyncIDs) throws {
        let previous = lastWritten
        try applyMeta(snapshot, changedFrom: previous)
        try applyLabels(snapshot, changedFrom: previous, deleting: deleting.labels)
        try applyBoards(snapshot, changedFrom: previous, deleting: deleting)
        try applyTasks(snapshot, changedFrom: previous, deleting: deleting.tasks)
        if context.hasChanges { try context.save() }
        lastWritten = snapshot
    }

    /// Forgets what the last write left, so the next `apply` reconsiders every
    /// record instead of trusting the diff. It does not make that write
    /// authoritative: with no base there is nothing this device has seen, so
    /// the apply may add and must not sweep — see the rule on ``apply(_:)``.
    func invalidateDiff() { lastWritten = nil }

    private func applyMeta(_ snapshot: BoardSnapshot, changedFrom previous: BoardSnapshot?) throws {
        let unchanged = previous.map {
            $0.nextSerial == snapshot.nextSerial
                && $0.themes == snapshot.themes
                && $0.views == snapshot.views
                && $0.palette == snapshot.palette
                && $0.viewsChangedAt == snapshot.viewsChangedAt
                && $0.paletteChangedAt == snapshot.paletteChangedAt
                && $0.themesChangedAt == snapshot.themesChangedAt
                && $0.activeBoardID == snapshot.activeBoardID
        } ?? false
        guard !unchanged else { return }

        let stored = try settled(context.fetch(FetchDescriptor<StoredMeta>()))
        // The one record with a fixed id, so a device that has never read the
        // records still lands on the one they hold. With no diff base to argue
        // from, the themes and the active board are left exactly as they are —
        // the next read adopts them — and only `nextSerial` moves, to whichever
        // side is further on: two devices handing out one task code is the one
        // disagreement no later merge can undo.
        if previous == nil, let stored {
            guard snapshot.nextSerial > stored.nextSerial else { return }
            stored.nextSerial = snapshot.nextSerial
            stored.updatedAt = .now
            return
        }
        let meta = stored ?? {
            let fresh = StoredMeta()
            context.insert(fresh)
            return fresh
        }()
        meta.nextSerial = snapshot.nextSerial
        // On an encode failure the previous value stands. `nil` is what a
        // record written before these attributes existed says, and what the
        // reader is required to treat as "ask the other device" — so writing
        // it on error would hand another device's work back to it as a
        // question. Stale-until-the-list-next-changes is the accepted cost;
        // the log line is what keeps it from being a silent one.
        write(encoded(snapshot.themes), to: \.themesJSON, on: meta, called: "themes")
        write(encoded(snapshot.views), to: \.viewsJSON, on: meta, called: "saved views")
        write(encoded(snapshot.palette), to: \.paletteJSON, on: meta, called: "palette")
        // The stamps ride with them, `nil` included: an undated list stays
        // undated on the way through, so the device that reads it merges rather
        // than replaces. Writing `.now` here instead would have every push
        // claim an edit nobody made — see ``SharedList``.
        meta.themesChangedAt = snapshot.themesChangedAt
        meta.viewsChangedAt = snapshot.viewsChangedAt
        meta.paletteChangedAt = snapshot.paletteChangedAt
        meta.activeBoardID = snapshot.activeBoardID
        meta.updatedAt = .now
    }

    private func applyLabels(_ snapshot: BoardSnapshot, changedFrom previous: BoardSnapshot?,
                             deleting: Set<String>) throws {
        guard previous?.labels != snapshot.labels || !deleting.isEmpty else { return }
        var existing = Dictionary(
            Self.deduplicated(try context.fetch(FetchDescriptor<StoredLabel>()), by: \.key,
                              newest: { _ in Date.distantPast }).map { ($0.key, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let seen = Set((previous?.labels ?? []).map(\.key))
        for (index, label) in snapshot.labels.enumerated() {
            let found = existing.removeValue(forKey: label.key)
            // A record under a key the diff base never carried is one this
            // device has not seen. See ``apply(_:)``.
            if found != nil, !seen.contains(label.key) { continue }
            let record = found ?? {
                let fresh = StoredLabel(key: label.key)
                context.insert(fresh)
                return fresh
            }()
            record.name = label.name
            record.light = Self.encoded(label.light)
            record.dark = Self.encoded(label.dark)
            record.position = index
        }
        // The licence, not the base: a leftover the tombstones do not name is
        // one nobody here deleted, whatever the base believes — it stays, and
        // the next read brings it back to the screen it vanished from.
        for (key, orphan) in existing where deleting.contains(key) { context.delete(orphan) }
    }

    private func applyBoards(_ snapshot: BoardSnapshot, changedFrom previous: BoardSnapshot?,
                             deleting: SyncIDs) throws {
        guard previous?.boards != snapshot.boards || !deleting.boards.isEmpty else { return }
        var existing = Dictionary(
            Self.deduplicated(try context.fetch(FetchDescriptor<StoredBoard>()), by: \.id,
                              newest: \.createdAt).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let seen = Dictionary((previous?.boards ?? []).map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })
        for (index, board) in snapshot.boards.enumerated() {
            let found = existing.removeValue(forKey: board.id)
            // A board record the diff base never carried is one this device has
            // not seen, and a board has no timestamp to argue with. See
            // ``apply(_:)``.
            if found != nil, seen[board.id] == nil { continue }
            let record = found ?? {
                let fresh = StoredBoard(id: board.id)
                context.insert(fresh)
                return fresh
            }()
            record.name = board.name
            record.symbol = board.symbol
            record.createdAt = board.createdAt
            record.codePrefix = board.codePrefix
            record.position = index
            applyColumns(board.columns, to: record,
                         seen: Set((seen[board.id]?.columns ?? []).map(\.id)),
                         deleting: deleting.columns)
        }
        // Deletion by tombstone alone — see `applyLabels`. The cascade takes a
        // deleted board's columns and, on the way out, nothing else.
        for (id, orphan) in existing where deleting.boards.contains(id) { context.delete(orphan) }
    }

    /// `seen` is the columns the diff base gave this board — the ones this
    /// device may speak for. See ``apply(_:)``.
    private func applyColumns(_ columns: [BoardColumn], to board: StoredBoard,
                              seen: Set<BoardColumn.ID>, deleting: Set<BoardColumn.ID>) {
        var existing = Dictionary(
            (board.columns ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        // An id written once in this pass is not written again. `existing` is
        // keyed by id, so a snapshot carrying the same column twice found
        // nothing the second time and inserted a *second* record for it — and
        // the read that followed carried both, so every save doubled the board
        // again. See ``BoardSnapshot/settlingDuplicates()``, which is why a
        // snapshot no longer arrives here in that state, and this, which is why
        // it would not matter if one did.
        var written: Set<BoardColumn.ID> = []
        for (index, column) in columns.enumerated() {
            guard written.insert(column.id).inserted else { continue }
            let found = existing.removeValue(forKey: column.id)
            if found != nil, !seen.contains(column.id) { continue }
            let record = found ?? {
                let fresh = StoredColumn(id: column.id)
                context.insert(fresh)
                fresh.board = board
                return fresh
            }()
            record.name = column.name
            record.short = column.short
            record.dot = Self.encoded(column.dot)
            // Written for older builds only — see `StoredColumn.roleKey`. The
            // last column is the Done one, which is the whole of v9's rule
            // spelled in v8's vocabulary.
            record.roleKey = index == columns.count - 1 ? "done" : "backlog"
            record.position = index
            record.limit = column.limit
        }
        for (id, orphan) in existing where deleting.contains(id) { context.delete(orphan) }
    }

    private func applyTasks(_ snapshot: BoardSnapshot, changedFrom previous: BoardSnapshot?,
                            deleting: Set<TaskItem.ID>) throws {
        // The one hot path: a keystroke changes one card, and comparing against
        // the last write is what stops the other four hundred being rewritten.
        let before = Dictionary(
            (previous?.tasks ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let changed = snapshot.tasks.filter { before[$0.id] != $0 }
        let previousPositions = Dictionary(
            (previous?.tasks ?? []).enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        let repositioned = snapshot.tasks.enumerated().compactMap { offset, task in
            previousPositions[task.id] == offset ? nil : task.id
        }
        let positions = Dictionary(
            snapshot.tasks.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        let changedIDs = Set(changed.map(\.id)).union(repositioned)
        guard !changedIDs.isEmpty || !deleting.isEmpty || previous == nil else { return }

        // Only the records this apply will touch are fetched. A diffed apply
        // can trust that: an id it did not write is one the last write left
        // alone, and the paths that make that untrue — a first write, a remote
        // merge — arrive with no `previous` and take the whole table below,
        // which is also the pass that reconciles strays.
        let fetched: [StoredTask]
        if previous == nil {
            fetched = try context.fetch(FetchDescriptor<StoredTask>())
        } else {
            // The tombstoned ids ride along whether or not the base names
            // them: a deletion made here is licensed to reach a record this
            // device never read.
            let wanted = changedIDs.union(deleting)
            fetched = try context.fetch(FetchDescriptor<StoredTask>(
                predicate: #Predicate { wanted.contains($0.id) }
            ))
        }
        var existing = Dictionary(
            Self.deduplicated(fetched, by: \.id, newest: \.updatedAt).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // A first write, or one after a remote merge, has no diff to trust.
        let seen = Set((previous?.tasks ?? []).map(\.id))
        let writing = previous == nil ? snapshot.tasks : snapshot.tasks.filter { changedIDs.contains($0.id) }
        for task in writing {
            guard let position = positions[task.id] else { continue }
            let record: StoredTask
            if let found = existing[task.id] {
                // An unseen record is another device's — but a task carries the
                // clock a board and a label do not, so one older than the value
                // in hand is one this device is ahead of. See ``apply(_:)``.
                guard seen.contains(task.id) || task.updatedAt >= found.updatedAt else { continue }
                record = found
            } else {
                let fresh = StoredTask(id: task.id)
                context.insert(fresh)
                existing[task.id] = fresh
                record = fresh
            }
            Self.write(task, at: position, into: record, context: context,
                       encodingFails: encodingFailsForTesting)
        }
        // The tombstones and not "everything the snapshot no longer names",
        // nor even everything the base names and the snapshot does not: an id
        // nobody here deleted is not this device's to delete, whatever the
        // base believes. What the tombstones miss survives and resurfaces on
        // the next read, which is the recoverable direction.
        for id in deleting {
            guard positions[id] == nil, let record = existing[id] else { continue }
            context.delete(record)
        }
    }

    // MARK: Value ⇄ record

    private static func write(
        _ task: TaskItem, at position: Int, into record: StoredTask, context: ModelContext,
        encodingFails: Bool = false
    ) {
        record.code = task.code
        record.boardID = task.boardID
        record.columnID = task.columnID
        record.title = task.title
        record.note = task.note
        record.labelKeys = task.labelKeys
        record.dueDay = task.due?.description
        record.priorityKey = task.priority.rawValue
        record.createdAt = task.createdAt
        record.updatedAt = task.updatedAt
        record.position = position
        record.inboxCompletedAt = task.inboxCompletedAt
        record.archivedAt = task.archivedAt

        var subtasks = Dictionary(
            (record.subtasks ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        var writtenSubtasks: Set<SubTask.ID> = []
        for (index, subtask) in task.subtasks.enumerated() {
            guard writtenSubtasks.insert(subtask.id).inserted else { continue }
            let row = subtasks.removeValue(forKey: subtask.id) ?? {
                let fresh = StoredSubtask(id: subtask.id)
                context.insert(fresh)
                fresh.task = record
                return fresh
            }()
            row.text = subtask.text
            row.done = subtask.done
            row.position = index
        }
        for orphan in subtasks.values { context.delete(orphan) }

        var entries = Dictionary(
            (record.activity ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        for entry in task.activity {
            // An id names one immutable entry — they are made once and never
            // edited — so an existing row is already right. Rewriting it
            // re-encoded the kind and dirtied the context for every entry of
            // every changed task, a cost that grew for the life of the card.
            if entries.removeValue(forKey: entry.id) != nil { continue }
            // A kind that will not encode is not inserted at all. An empty
            // row would satisfy the skip above on every later pass and never
            // be repaired, then be dropped by `value(of:)` on every other
            // device — a silent, permanent loss. A missing row is written the
            // next time the task changes, and logged so the wait is at least
            // a visible one.
            guard let kind = encodedKind(entry.kind, failing: encodingFails) else {
                Self.logger.error("An activity entry's kind failed to encode; its record was not written.")
                continue
            }
            let fresh = StoredActivity(id: entry.id)
            context.insert(fresh)
            fresh.task = record
            fresh.kind = kind
            fresh.when = entry.when
        }
        // Activity is append-only, so an entry the snapshot no longer carries
        // was undone rather than forgotten, and the record goes with it. Only
        // rows this build can read are candidates: a row whose kind does not
        // decode was never in the value — `value(of:)` leaves it out — so its
        // absence from the snapshot is not an undo, and deleting it would take
        // a newer build's entry with it.
        for orphan in entries.values {
            guard (try? Self.kindDecoder.decode(ActivityEntry.Kind.self, from: orphan.kind)) != nil
            else { continue }
            context.delete(orphan)
        }
    }

    private static func encodedKind(_ kind: ActivityEntry.Kind, failing: Bool) -> Data? {
        guard !failing else { return nil }
        return try? kindEncoder.encode(kind)
    }

    /// Puts an encoded list on the record, or leaves what is there and says so.
    private func write(
        _ encoded: Data?, to field: ReferenceWritableKeyPath<StoredMeta, Data?>,
        on meta: StoredMeta, called name: String
    ) {
        guard let encoded else {
            Self.logger.error("The \(name, privacy: .public) failed to encode; the previously synced copy stands.")
            return
        }
        meta[keyPath: field] = encoded
    }

    private func encoded(_ value: some Encodable) -> Data? {
        guard !encodingFailsForTesting else { return nil }
        return try? JSONEncoder().encode(value)
    }

    /// One coder each way rather than one per activity row: a fresh
    /// `JSONEncoder` per entry made loading a long-lived board allocate
    /// thousands of them.
    private static let kindEncoder = JSONEncoder()
    private static let kindDecoder = JSONDecoder()

    private static func value(of record: StoredTask) -> TaskItem {
        var task = TaskItem(id: record.id, code: record.code, title: record.title)
        // Through `placement` rather than the two fields, so a record carrying
        // one id and not the other cannot reach the board as an illegal pair.
        task.placement = placement(boardID: record.boardID, columnID: record.columnID)
        task.note = record.note
        task.labelKeys = record.labelKeys
        task.due = record.dueDay.flatMap(CalendarDay.init(exactly:))
        task.priority = Priority(rawValue: record.priorityKey) ?? .medium
        task.createdAt = record.createdAt
        task.updatedAt = record.updatedAt
        task.inboxCompletedAt = record.inboxCompletedAt
        task.archivedAt = record.archivedAt
        task.subtasks = (record.subtasks ?? [])
            .sorted { ($0.position, $0.text) < ($1.position, $1.text) }
            .map { SubTask(id: $0.id, text: $0.text, done: $0.done) }
        // Newest first, the order the feed reads in.
        task.activity = (record.activity ?? [])
            .sorted { $0.when > $1.when }
            .compactMap { row in
                guard let kind = try? Self.kindDecoder.decode(ActivityEntry.Kind.self, from: row.kind)
                else {
                    // Most likely a kind written by a newer build. Left out of
                    // the value, kept in the store — see the orphan rule in
                    // `applyTask` — so the build that understands it still has
                    // it.
                    Self.logger.notice("An activity entry's kind failed to decode and was left out.")
                    return nil
                }
                return ActivityEntry(id: row.id, kind, when: row.when)
            }
        return task
    }

    /// Fetch descriptors do not guarantee order. Rows with no rank are legacy
    /// records waiting for `backfillTaskPositions(from:)`; their id is merely a
    /// deterministic fallback until the local board file can supply the order.
    private static func ordered(_ records: [StoredTask]) -> [StoredTask] {
        records.sorted { lhs, rhs in
            switch (lhs.position, rhs.position) {
            case let (left?, right?) where left != right:
                return left < right
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            default:
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    /// The placement invariant, rebuilt on the way out. A record carrying one
    /// id and not the other is a half-written pair — CloudKit does not apply
    /// relationship changes atomically — and an unfiled card is the one reading
    /// of it that cannot put a card somewhere nobody can find.
    private static func placement(boardID: UUID?, columnID: UUID?) -> TaskPlacement {
        guard let boardID, let columnID else { return .inbox }
        return .column(board: boardID, column: columnID)
    }

    private static func value(of record: StoredBoard) -> Board {
        Board(
            id: record.id,
            name: record.name,
            symbol: Board.symbol(record.symbol ?? ""),
            createdAt: record.createdAt,
            // Ordered totally rather than by position alone: two records under
            // one id are settled by keeping the first, so every device has to
            // sort them into the same order or they would each keep a different
            // one and never agree on the column's name again.
            columns: (record.columns ?? [])
                .sorted { ($0.position, $0.name, $0.short) < ($1.position, $1.name, $1.short) }
                .map(value(of:)),
            codePrefix: record.codePrefix
        )
    }

    private static func value(of record: StoredColumn) -> BoardColumn {
        BoardColumn(
            id: record.id,
            name: record.name,
            short: record.short,
            dot: Self.decoded(record.dot) ?? .accent,
            limit: record.limit
        )
    }

    private static func value(of record: StoredLabel) -> LabelDef {
        LabelDef(
            key: record.key,
            name: record.name,
            light: Self.decoded(record.light) ?? LabelDef.seed[0].light,
            dark: Self.decoded(record.dark) ?? LabelDef.seed[0].dark
        )
    }

    /// A `Codable` value as a record attribute.
    ///
    /// `SwatchColor` and `LabelTone` are enums with associated values, which
    /// SwiftData has no attribute layout for — see `StoredTask.dueDay` for what
    /// that failure looks like, and when. JSON is the shape that always works.
    static func encoded<Value: Encodable>(_ value: Value?) -> Data? {
        value.flatMap { try? JSONEncoder().encode($0) }
    }

    static func decoded<Value: Decodable>(_ data: Data?) -> Value? {
        data.flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    // MARK: Duplicates

    /// Keeps one record per key, the newest by `newest`.
    ///
    /// CloudKit cannot enforce uniqueness, so two devices that both create the
    /// board — or that both replay an import — leave two records under one id.
    /// This is last-writer-wins applied to a whole record, which is the policy
    /// for everything except sub-tasks and activity: those merge by id, inside
    /// the record that owns them.
    static func deduplicated<Model, Key: Hashable>(
        _ records: [Model],
        by key: KeyPath<Model, Key>,
        newest: (Model) -> Date
    ) -> [Model] {
        var kept: [Key: Model] = [:]
        var order: [Key] = []
        for record in records {
            let id = record[keyPath: key]
            guard let rival = kept[id] else {
                kept[id] = record
                order.append(id)
                continue
            }
            if newest(record) > newest(rival) { kept[id] = record }
        }
        return order.compactMap { kept[$0] }
    }

    static func deduplicated<Model, Key: Hashable>(
        _ records: [Model], by key: KeyPath<Model, Key>, newest: KeyPath<Model, Date>
    ) -> [Model] {
        deduplicated(records, by: key, newest: { $0[keyPath: newest] })
    }

    /// The single settings record, or the newest of however many exist.
    private func settled(_ records: [StoredMeta]) throws -> StoredMeta? {
        let kept = Self.deduplicated(records, by: \.id, newest: \.updatedAt)
        // The losers are deleted rather than left: a duplicate that survives is
        // one the next device has to settle again, forever.
        for record in records where !kept.contains(where: { $0.persistentModelID == record.persistentModelID }) {
            context.delete(record)
        }
        return kept.first
    }
}
