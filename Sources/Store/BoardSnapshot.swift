import Foundation
import OSLog
import Synchronization

/// What survives a relaunch.
///
/// Session state — selection, drafts, the search query, which tab is showing,
/// drag state — is deliberately absent. It belongs to a sitting, not to the
/// board, and restoring it would be more surprising than helpful.
struct BoardSnapshot: Codable, Sendable {
    /// Bumped when the shape changes so an older file can be migrated rather
    /// than silently mis-decoded. See `BoardMigration.swift`.
    var version: Int = BoardSnapshot.currentVersion
    var tasks: [TaskItem]
    /// The boards, in sidebar order, each carrying its own columns. Since v5 —
    /// v4 kept one flat `columns` array here, from before there was more than
    /// one board to hang columns on.
    var boards: [Board] = SeedData.boards
    var labels: [LabelDef]
    /// Kept so task codes keep climbing across launches. Without it a new
    /// session restarts at NW-140 and collides with tasks an earlier one made.
    /// One counter for the whole file, not one per board: the prefix is what
    /// distinguishes a board's codes, and a per-board counter would hand two
    /// boards the same number and make the prefix load-bearing.
    var nextSerial: Int
    var accentTheme: AccentTheme
    /// The board last looked at. This one *is* saved, unlike the saved view —
    /// which board you are on is where your work is, not where you happened to
    /// glance. Optional so a file whose boards have been hand-edited still
    /// reads; the store falls back to the first board.
    var activeBoardID: Board.ID?

    static let currentVersion = 6

    /// The serial a fresh board starts minting from.
    static let baseSerial = 100

    /// The human code a serial mints, under the destination's prefix. Kept here
    /// rather than inline in `addTask` because the v1 migration has to agree
    /// with it: a board whose serial has fallen behind its codes would mint one
    /// it already contains.
    static func code(prefix: String = Board.defaultCodePrefix, forSerial serial: Int) -> String {
        "\(prefix)-\(140 + serial - baseSerial)"
    }

    /// The serial a code was minted from, whatever prefix it carries, or `nil`
    /// for one this did not mint. Reading the number rather than rebuilding the
    /// whole code is what lets `discardIfUntouched` hand a serial back without
    /// knowing which board — or the Inbox — minted it.
    static func serial(ofCode code: String) -> Int? {
        guard let dash = code.lastIndex(of: "-"),
              let number = Int(code[code.index(after: dash)...])
        else { return nil }
        return baseSerial + number - 140
    }
}

/// Why a saved board could not be used, and where it was put for safe keeping.
///
/// `quarantinedAt` is `nil` when the file could not even be moved aside. That
/// is the one case where the store must stop saving: the only copy of the
/// user's work is still sitting at `url`, and a write would land on top of it.
enum BoardLoadFailure: Equatable, Sendable {
    case unreadable(quarantinedAt: URL?)
    case newerVersion(Int, quarantinedAt: URL?)
}

/// What became of a board file that could not be read, when the user chose to
/// carry on and the app had one last chance to get it out of the way.
enum BoardRescue: Equatable, Sendable {
    /// Nothing is at the board's URL any more, so there is nothing to protect.
    case nothingToRescue
    /// The bytes now live here, and the board's URL is free to be written.
    case preserved(URL)
    /// The file is still at the board's URL and could not be copied anywhere.
    /// Writing would destroy the only copy of the user's work.
    case failed
}

/// The outcome of a load: a board, a reason there is none, or neither — a
/// first launch has no file and no failure, and the caller seeds.
struct BoardLoadResult: Sendable {
    var snapshot: BoardSnapshot? = nil
    var failure: BoardLoadFailure? = nil
    /// Set when the file on disk was older than `currentVersion` and was
    /// migrated forward on the way in.
    var migratedFromVersion: Int? = nil
}

/// One file in `backups/`, and when it was taken.
///
/// The stamp is read out of the name rather than off the file, so a backup
/// copied to another machine still says when it was made.
struct BoardBackup: Identifiable, Hashable, Sendable {
    var url: URL
    var takenAt: Date?

    var id: URL { url }
}

/// A board file that cannot be turned into a snapshot. `load()` converts these
/// into a `BoardLoadFailure`; `restore(from:)` throws them, because a restore
/// the user asked for should fail loudly.
enum BoardFileError: LocalizedError, Equatable, Sendable {
    case unreadable
    case newerVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "The board file could not be read.",
                   comment: "Error shown when a saved board is corrupt or not a board file")
        case .newerVersion(let version):
            String(localized: "The board file was saved by a newer version of Simple Kanban (format \(version)).",
                   comment: "Error shown when a saved board is too new for this build to read")
        }
    }
}

/// The board's JSON file.
///
/// A small document rather than a database: `BoardStore` holds plain value
/// types, so the whole board encodes in one pass and the port of the spec's
/// logic stays untouched. If sync ever matters this is the layer to replace.
///
/// Every method here is free of actor isolation on purpose — the debounced
/// save encodes and writes off the main actor.
struct BoardFile: Sendable {
    var url: URL

    private static let logger = Logger(subsystem: "com.n14395.SimpleKanban", category: "persistence")

    /// `~/Library/Application Support/SimpleKanban/board.json` on both platforms.
    static let `default`: BoardFile = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        // `xcodebuild test` launches this app as the test host under its real
        // bundle identifier, so an unguarded `.default` puts the suite on the
        // developer's own board — reading it, migrating it, and quarantining it
        // when the tree is briefly on an older schema. A test may only ever be
        // handed a throwaway file, so the app's own file steps aside first.
        guard !isRunningTests else {
            return BoardFile(url: URL.temporaryDirectory
                .appending(path: "SimpleKanbanTestHost-\(UUID().uuidString)/board.json"))
        }
        return BoardFile(url: base.appending(path: "SimpleKanban/board.json"))
    }()

    /// True when this process was launched by a test runner rather than by a
    /// person. Both spellings are checked because Swift Testing and XCTest
    /// announce themselves differently.
    ///
    /// Not private: `BoardStore.scheduleSave` asks it the same question about
    /// the two *other* pieces of machine-wide state the app owns — see there.
    static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    // MARK: Loading

    /// Reads the board, migrating an older file forward.
    ///
    /// Anything that cannot be turned into a board is **moved aside first**, so
    /// the seeded board the caller falls back to cannot be written over the top
    /// of it. A file that is simply absent is not a failure and leaves nothing
    /// behind.
    func load() -> BoardLoadResult {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return BoardLoadResult()
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try Self.decode(data)
            if let from = decoded.migratedFrom {
                preserveBeforeMigration(from: from)
            }
            return BoardLoadResult(snapshot: decoded.snapshot, migratedFromVersion: decoded.migratedFrom)
        } catch BoardFileError.newerVersion(let version) {
            Self.logger.error("Board file is version \(version), newer than this build reads")
            return BoardLoadResult(failure: .newerVersion(version, quarantinedAt: quarantine("from-newer-version-\(version)")))
        } catch {
            Self.logger.error("Could not read the board file: \(error.localizedDescription)")
            return BoardLoadResult(failure: .unreadable(quarantinedAt: quarantine("corrupt")))
        }
    }

    /// Decodes board bytes of any shipped version.
    ///
    /// The `version` is read out of the raw JSON *before* anything is decoded,
    /// because synthesised `Codable` throws `keyNotFound` for a field the older
    /// shape never wrote — a default does not save you. Routing on the version
    /// first is what keeps a v1 file out of the current decoder.
    ///
    /// Each older version is decoded by the shape that wrote it and then walked
    /// forward one step at a time, so a v1 file passes through exactly the same
    /// v4 → v5 code a v4 file does. Widening an old decoder to reach the current
    /// shape instead would make every future field silently rewrite the past.
    static func decode(_ data: Data) throws -> (snapshot: BoardSnapshot, migratedFrom: Int?) {
        let decoder = JSONDecoder()
        switch try version(of: data) {
        case BoardSnapshot.currentVersion:
            return (try decoder.decode(BoardSnapshot.self, from: data), nil)
        case 5:
            // v5 and v6 are the same shape. What changed is how `Priority`
            // spells itself on disk, which `Priority.init(stored:)` absorbs, so
            // the current decoder reads a v5 file — but the bump still has to
            // happen, because the reverse is not true and a v5 build must
            // refuse this file rather than lose every priority in it.
            return (BoardSnapshot.migrate(v5: try decoder.decode(BoardSnapshot.self, from: data)), 5)
        case 4:
            let v4 = try decoder.decode(BoardSnapshotV4.self, from: data)
            return (BoardSnapshot.migrate(v5: BoardSnapshot.migrate(v4: v4)), 4)
        case 3:
            let v3 = try decoder.decode(BoardSnapshotV3.self, from: data)
            return (BoardSnapshot.migrate(v5: BoardSnapshot.migrate(v4: BoardSnapshot.migrate(v3: v3))), 3)
        case 2:
            let v2 = try decoder.decode(BoardSnapshotV2.self, from: data)
            return (
                BoardSnapshot.migrate(
                    v5: BoardSnapshot.migrate(v4: BoardSnapshot.migrate(v3: BoardSnapshot.migrate(v2: v2)))
                ),
                2
            )
        case 1:
            let v1 = try decoder.decode(BoardSnapshotV1.self, from: data)
            return (
                BoardSnapshot.migrate(
                    v5: BoardSnapshot.migrate(
                        v4: BoardSnapshot.migrate(v3: BoardSnapshot.migrate(v2: BoardSnapshot.migrate(v1: v1)))
                    )
                ),
                1
            )
        case let version where version > BoardSnapshot.currentVersion:
            throw BoardFileError.newerVersion(version)
        default:
            throw BoardFileError.unreadable
        }
    }

    /// A file with no `version` at all predates versioning, which makes it a
    /// v1 board — the same assumption `BoardSnapshotV1` decodes on. A `version`
    /// that is present but not a number is a file this is not.
    private static func version(of data: Data) throws -> Int {
        let root = try? JSONSerialization.jsonObject(with: data)
        guard let object = root as? [String: Any] else { throw BoardFileError.unreadable }
        guard let version = object["version"] else { return 1 }
        guard let number = version as? Int else { throw BoardFileError.unreadable }
        return number
    }

    // MARK: Writing

    /// The one encoder the board is written with. Exported bytes go through it
    /// too, so a file the user exports and the file on disk are the same
    /// document rather than two spellings of one.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    /// Which generation of which file has reached the disk.
    ///
    /// Write ordering belongs to the *file*, not to whoever is writing it. Two
    /// stores can share one path — a restore, a window replaced while its
    /// debounced write is still in flight — and a counter kept per store would
    /// start both of them at zero, so a stale write would look current and land
    /// on top of a newer save.
    private struct WriteOrder: Sendable {
        var issued: UInt64 = 0
        var written: UInt64 = 0
    }

    private static let writeOrder = Mutex<[URL: WriteOrder]>([:])

    private var orderKey: URL { url.standardizedFileURL }

    #if DEBUG
    /// How many times bytes have actually landed on each path.
    ///
    /// Only the tests read it, and only because there is no other way to tell
    /// one write from two: both leave the same file, and a modification date
    /// has one-second resolution where the thing under test is a 500ms
    /// debounce. Keyed like `writeOrder`, because what is worth counting is
    /// writes to a *file* rather than calls on one `BoardFile` value.
    private static let writeCounts = Mutex<[URL: Int]>([:])

    /// Writes to this file that have reached the disk since the process began.
    var writeCount: Int { Self.writeCounts.withLock { $0[orderKey] ?? 0 } }
    #endif

    /// Claims the generation for a save. Called when the save is *queued*, so a
    /// write overtaken while it waited out a debounce can tell.
    func nextWriteGeneration() -> UInt64 {
        Self.writeOrder.withLock { table in
            var order = table[orderKey] ?? WriteOrder()
            order.issued &+= 1
            table[orderKey] = order
            return order.issued
        }
    }

    /// Writes the board unless a later save has already landed, returning
    /// whether the bytes actually reached the disk — an overtaken write is
    /// dropped rather than undoing the newer one, and its caller must not go on
    /// to claim the board was saved.
    ///
    /// Throws so a failed save can reach the user. `OSLog` is not a user
    /// interface, and an app that has silently stopped saving looks identical
    /// to one that is working.
    ///
    /// Encoding happens outside the lock: it is the half that grows with the
    /// board, and `saveNow()` runs on the main actor, where waiting on a
    /// background encode is exactly the stall this is meant to avoid.
    @discardableResult
    func write(_ snapshot: BoardSnapshot, generation: UInt64) throws -> Bool {
        let data = try Self.encoder().encode(snapshot)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return try Self.writeOrder.withLock { table in
            var order = table[orderKey] ?? WriteOrder()
            guard generation > order.written else { return false }
            // Older generations are retired before the attempt, not after it.
            // Their content is stale whether or not these bytes land, and a
            // write that throws must not leave the door open for one of them.
            order.written = generation
            table[orderKey] = order
            // Atomic: a crash mid-write leaves the previous board intact.
            try data.write(to: url, options: .atomic)
            #if DEBUG
            Self.writeCounts.withLock { $0[orderKey, default: 0] += 1 }
            #endif
            return true
        }
    }

    // MARK: Backups

    var backupsDirectory: URL { url.deletingLastPathComponent().appending(path: "backups") }

    /// Copies the live file into `backups/` when the newest backup has aged
    /// past `interval`, then prunes to the `limit` newest.
    ///
    /// This is the answer to a board the app reads perfectly and whose contents
    /// are wrong — quarantine only rescues a file that fails to decode.
    func backupIfDue(interval: TimeInterval = 15 * 60, keeping limit: Int = 10) {
        let manager = FileManager.default
        // A board that has never been written has nothing worth keeping.
        guard manager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        if let newest = backups().first, let taken = Self.date(ofBackup: newest),
           Date.now.timeIntervalSince(taken) < interval {
            return
        }
        let destination = backupsDirectory.appending(path: "board-\(Self.stamp(.now)).json")
        // A second backup within the same second would collide; one a second is
        // already far more history than this is for.
        if !manager.fileExists(atPath: destination.path(percentEncoded: false)) {
            do {
                try manager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
                try manager.copyItem(at: url, to: destination)
            } catch {
                Self.logger.error("Could not take a board backup: \(error.localizedDescription)")
                return
            }
        }
        prune(keeping: limit)
    }

    /// Copies the live file into `backups/` whatever the age of the last one,
    /// then prunes. Returns where it went, or `nil` if it could not be kept.
    ///
    /// `backupIfDue` deliberately does neither of those things — it is the
    /// rolling backup, and one a second is far more history than it is for. A
    /// restore or a reset is the one moment the board about to be replaced has
    /// no other copy anywhere, and "there was already one this second" is not an
    /// answer to that.
    @discardableResult
    func backupNow(keeping limit: Int = 10) -> URL? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        var moment = Date.now
        var destination = backupsDirectory.appending(path: "board-\(Self.stamp(moment)).json")
        while manager.fileExists(atPath: destination.path(percentEncoded: false)) {
            // The stamp is second-resolution and it is also what orders the
            // list, so a clash takes the next second rather than a decorated
            // name — which would sort as the *older* of the two.
            moment.addTimeInterval(1)
            destination = backupsDirectory.appending(path: "board-\(Self.stamp(moment)).json")
        }
        do {
            try manager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            try manager.copyItem(at: url, to: destination)
        } catch {
            Self.logger.error("Could not keep the board before replacing it: \(error.localizedDescription)")
            return nil
        }
        prune(keeping: limit)
        return destination
    }

    /// Newest first. The stamp in the name sorts chronologically, which is the
    /// reason it is zero-padded UTC rather than anything friendlier.
    func backups() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("board-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// The same list with the moment each was taken, which is the only thing
    /// that tells one apart from another in the restore list.
    func recentBackups() -> [BoardBackup] {
        backups().map { BoardBackup(url: $0, takenAt: Self.date(ofBackup: $0)) }
    }

    /// Reads a backup into a snapshot, migrating it forward if it predates the
    /// current version. The caller adopts the result and saves it — restoring
    /// is an edit to the board, not a file move, so it can be undone.
    func restore(from backupURL: URL) throws -> BoardSnapshot {
        try Self.decode(try Data(contentsOf: backupURL)).snapshot
    }

    private func prune(keeping limit: Int) {
        for stale in backups().dropFirst(max(0, limit)) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    // MARK: Moving files aside

    /// Moves the unusable file to a sibling named for what was wrong with it.
    ///
    /// Returns `nil` when even that failed, which the caller must treat as
    /// "do not write" rather than "carry on" — see `BoardLoadFailure`.
    private func quarantine(_ reason: String) -> URL? {
        let manager = FileManager.default
        let destination = siblingURL(reason)
        do {
            try manager.moveItem(at: url, to: destination)
            return destination
        } catch {
            // A move can fail on permissions or across volumes; a copy still
            // preserves the bytes even when the original cannot be cleared.
            do {
                try manager.copyItem(at: url, to: destination)
                try? manager.removeItem(at: url)
                return destination
            } catch {
                Self.logger.error("Could not set the unreadable board aside: \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// A last attempt to get an unreadable board out of the way, made when the
    /// user says to carry on with the fresh one.
    ///
    /// Launch is not the only moment worth trying: whatever stopped the move —
    /// a directory that was briefly read-only, a file open elsewhere — may be
    /// over by now. Failing that the bytes are forced into `backups/`, which is
    /// a different directory and may still be writable. Only when both fail is
    /// the file genuinely unprotectable, and then nothing may be written.
    func rescueUnreadable(reason: String) -> BoardRescue {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path(percentEncoded: false)) else { return .nothingToRescue }
        if let moved = quarantine(reason) { return .preserved(moved) }
        do {
            try manager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            // Not named `board-…`, so `backups()` does not offer an unreadable
            // file as something to restore and `prune` cannot reclaim it.
            let destination = backupsDirectory.appending(path: "\(reason)-\(Self.stamp(.now)).json")
            if !manager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try manager.copyItem(at: url, to: destination)
            }
            return .preserved(destination)
        } catch {
            Self.logger.error("Could not preserve the unreadable board: \(error.localizedDescription)")
            return .failed
        }
    }

    /// Keeps the pre-migration bytes beside the board. A migration is the one
    /// moment the old shape stops existing anywhere, and this copy is outside
    /// `backups/` so pruning cannot reclaim it.
    private func preserveBeforeMigration(from version: Int) {
        let destination = siblingURL("v\(version)")
        guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            Self.logger.error("Could not keep the pre-migration board: \(error.localizedDescription)")
        }
    }

    /// `board.<reason>-<stamp>.json`, uniqued if one already exists.
    private func siblingURL(_ reason: String) -> URL {
        let directory = url.deletingLastPathComponent()
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        let stamp = Self.stamp(.now)
        var candidate = directory.appending(path: "\(name).\(reason)-\(stamp).\(ext)")
        var attempt = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = directory.appending(path: "\(name).\(reason)-\(stamp)-\(attempt).\(ext)")
            attempt += 1
        }
        return candidate
    }

    // MARK: Timestamps in file names

    /// ISO 8601 with the punctuation taken out: colons are legal in a file name
    /// and miserable everywhere else, and the compact form still sorts.
    private static func stampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }

    static func stamp(_ date: Date) -> String { stampFormatter().string(from: date) }

    /// When a backup was taken, from its name — falling back to the file's own
    /// modification date if someone has renamed it.
    static func date(ofBackup backupURL: URL) -> Date? {
        let name = backupURL.deletingPathExtension().lastPathComponent
        let prefix = "board-"
        if name.hasPrefix(prefix), let date = stampFormatter().date(from: String(name.dropFirst(prefix.count))) {
            return date
        }
        return try? backupURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

// MARK: - Export and import

/// What an import did. Every number here is something that was *added*: an
/// import never renames, recolours, moves or removes anything already on the
/// board, so there is no "replaced" to count.
struct BoardImportSummary: Equatable, Sendable {
    var boardsAdded = 0
    /// Columns folded into a board that was already here.
    var columnsAdded = 0
    var tasksAdded = 0
    /// Tasks that arrived under an id this board already uses. Neither side
    /// wins: the arriving one is kept beside the one already here.
    var tasksCopied = 0
    var labelsAdded = 0
    /// Tasks that were already here, identical — what re-importing the same
    /// file is made of.
    var tasksUnchanged = 0

    var changedAnything: Bool {
        boardsAdded + columnsAdded + tasksAdded + tasksCopied + labelsAdded > 0
    }
}

extension BoardSnapshot {
    /// The bytes an export writes.
    func encoded() throws -> Data { try BoardFile.encoder().encode(self) }

    /// Reads exported bytes of any shipped version, migrating an older file
    /// forward on the way in.
    ///
    /// Throws rather than returning a `BoardLoadResult`: a file the user picked
    /// and asked to import has to fail loudly, and there is nothing to
    /// quarantine — the file is theirs and stays where it is.
    static func decoding(_ data: Data) throws -> BoardSnapshot {
        try BoardFile.decode(data).snapshot
    }

    /// Folds an imported board into this one.
    ///
    /// **Merge, never replace.** Nothing already here is renamed, recoloured,
    /// moved or removed, and the two fields that are not the file's to change —
    /// the accent, and which board is being looked at — stay as they are.
    ///
    /// Tasks are matched on `id`, which is why 3.7 made them UUIDs. A task that
    /// is already here byte for byte is skipped, so re-importing the same file
    /// is a no-op; a task arriving under an id that names a *different* task
    /// here is kept **as well as**, under a fresh id, rather than one of the two
    /// being picked as the winner. Codes are re-minted only where they would
    /// collide: a code is a label a person may have pasted into a commit
    /// message, so it is left alone wherever it can be.
    ///
    /// Boards are matched on `id` too. One that is already here keeps its name,
    /// dot and prefix and gains only the columns it is missing — a board is a
    /// place the user has arranged, and an import that re-ordered or renamed
    /// its columns would be overwriting exactly what the merge is there to
    /// protect. Column ids are unique across boards, because the store resolves
    /// a card's board from its column, so a column arriving with an id already
    /// in use on a *new* board is re-minted.
    func merging(_ incoming: BoardSnapshot) -> (snapshot: BoardSnapshot, summary: BoardImportSummary) {
        var merged = self
        var summary = BoardImportSummary()
        // Above both files' counters, so nothing re-minted here can collide
        // with a code either side has already issued.
        var serial = Swift.max(nextSerial, incoming.nextSerial)

        var boardOfColumn = Dictionary(
            merged.boards.flatMap { board in board.columns.map { ($0.id, board.id) } },
            uniquingKeysWith: { first, _ in first }
        )
        // Where each incoming column ended up here.
        var columnMap: [BoardColumn.ID: BoardColumn.ID] = [:]

        for incomingBoard in incoming.boards {
            if let index = merged.boards.firstIndex(where: { $0.id == incomingBoard.id }) {
                for column in incomingBoard.columns {
                    columnMap[column.id] = column.id
                    guard boardOfColumn[column.id] == nil else { continue }
                    merged.boards[index].columns.append(column)
                    boardOfColumn[column.id] = incomingBoard.id
                    summary.columnsAdded += 1
                }
                continue
            }
            var board = incomingBoard
            board.columns = []
            for original in incomingBoard.columns {
                var column = original
                if boardOfColumn[column.id] != nil { column.id = UUID() }
                columnMap[original.id] = column.id
                boardOfColumn[column.id] = board.id
                board.columns.append(column)
            }
            merged.boards.append(board)
            summary.boardsAdded += 1
        }

        let prefixes = Dictionary(
            merged.boards.map { ($0.id, $0.codePrefix) }, uniquingKeysWith: { first, _ in first }
        )
        var here = Dictionary(merged.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var contents = Set(merged.tasks.map(Self.contentKey))
        var codes = Set(merged.tasks.map(\.code))

        for incomingTask in incoming.tasks {
            var task = incomingTask
            if let columnID = incomingTask.columnID, let mapped = columnMap[columnID],
               let boardID = boardOfColumn[mapped] {
                task.placement = .column(board: boardID, column: mapped)
            } else {
                // A card whose column did not come with the file is still the
                // user's, and the Inbox is where it can be found again — the
                // same answer `BoardStore.placed` gives.
                task.placement = .inbox
            }
            if let mine = here[incomingTask.id] {
                guard mine != task else {
                    summary.tasksUnchanged += 1
                    continue
                }
                // A copy of this card may already be here from an earlier
                // import of the same file: the copy took a fresh id, so it no
                // longer answers to the id that arrived, and matching on the id
                // alone would add another one on every re-import.
                guard !contents.contains(Self.contentKey(task)) else {
                    summary.tasksUnchanged += 1
                    continue
                }
                task.id = UUID()
                summary.tasksCopied += 1
            } else {
                summary.tasksAdded += 1
            }
            while codes.contains(task.code) {
                task.code = BoardSnapshot.code(
                    prefix: task.boardID.flatMap { prefixes[$0] } ?? Board.inboxCodePrefix,
                    forSerial: serial
                )
                serial += 1
            }
            codes.insert(task.code)
            contents.insert(Self.contentKey(task))
            here[task.id] = task
            merged.tasks.append(task)
        }

        var keys = Set(merged.labels.map(\.key))
        for label in incoming.labels where !keys.contains(label.key) {
            merged.labels.append(label)
            keys.insert(label.key)
            summary.labelsAdded += 1
        }

        merged.nextSerial = Swift.max(serial, Swift.max(nextSerial, incoming.nextSerial))
        merged.version = BoardSnapshot.currentVersion
        return (merged, summary)
    }

    /// A card stripped of the two things about it that are labels rather than
    /// content — its id and its code — so "this card is already here under
    /// another number" is one lookup rather than a scan.
    ///
    /// Both are set aside because both are exactly what an earlier import may
    /// have changed: a colliding card is kept under a fresh id, and a card whose
    /// code was already taken is re-minted. Everything else about a card —
    /// including its `createdAt`, its `updatedAt` and the ids of its activity
    /// entries — travels with the file unchanged, which is what makes this
    /// specific enough to key on.
    private static func contentKey(_ task: TaskItem) -> TaskItem {
        var probe = task
        probe.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        probe.code = ""
        return probe
    }
}
