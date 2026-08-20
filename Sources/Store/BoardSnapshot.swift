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
    var labels: [LabelDef]
    /// Kept so task codes keep climbing across launches. Without it a new
    /// session restarts at NW-140 and collides with tasks an earlier one made.
    var nextSerial: Int
    var accentTheme: AccentTheme

    static let currentVersion = 2

    /// The serial a fresh board starts minting from.
    static let baseSerial = 100

    /// The human code a serial mints. Kept here rather than inline in
    /// `addTask` because the v1 migration has to agree with it: a board whose
    /// serial has fallen behind its codes would mint one it already contains.
    static func code(forSerial serial: Int) -> String { "NW-\(140 + serial - baseSerial)" }
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

    private static let logger = Logger(subsystem: "com.simplekanban.SimpleKanban", category: "persistence")

    /// `~/Library/Application Support/SimpleKanban/board.json` on both platforms.
    static let `default`: BoardFile = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        return BoardFile(url: base.appending(path: "SimpleKanban/board.json"))
    }()

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
    static func decode(_ data: Data) throws -> (snapshot: BoardSnapshot, migratedFrom: Int?) {
        let decoder = JSONDecoder()
        switch try version(of: data) {
        case BoardSnapshot.currentVersion:
            return (try decoder.decode(BoardSnapshot.self, from: data), nil)
        case 1:
            return (BoardSnapshot.migrate(v1: try decoder.decode(BoardSnapshotV1.self, from: data)), 1)
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
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
    private static func date(ofBackup backupURL: URL) -> Date? {
        let name = backupURL.deletingPathExtension().lastPathComponent
        let prefix = "board-"
        if name.hasPrefix(prefix), let date = stampFormatter().date(from: String(name.dropFirst(prefix.count))) {
            return date
        }
        return try? backupURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
