import Foundation
import OSLog
import Synchronization

/// What survives a relaunch.
///
/// Session state — selection, drafts, the search query, which tab is showing,
/// drag state — is deliberately absent. It belongs to a sitting, not to the
/// board, and restoring it would be more surprising than helpful.
struct BoardSnapshot: Codable, Sendable, Equatable {
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
    /// Which theme fills the light slot and which fills the dark one, plus the
    /// themes the user made. Since v12, when the accent — four fixed choices —
    /// became one parameter of a whole theme. See ``ThemeSettings``.
    var themes: ThemeSettings = .seed
    /// The board last looked at. This one *is* saved, unlike the saved view —
    /// which board you are on is where your work is, not where you happened to
    /// glance. Optional so a file whose boards have been hand-edited still
    /// reads; the store falls back to the first board.
    var activeBoardID: Board.ID?
    /// What the user has thrown away and can still get back — see
    /// ``TrashedItem``. Since v7, and defaulted so a hand-written or
    /// half-migrated file still reads.
    ///
    /// Kept in the file rather than worked out from the board, because it is
    /// precisely the things that are *not* on the board any more.
    var trash: [TrashedItem] = []
    /// The colours every picker in the app offers — see ``PaletteSwatch``.
    /// Since v10, and defaulted to the six the app ships with: a file written
    /// before there was a palette was written by a build whose pickers offered
    /// exactly those.
    var palette: [PaletteSwatch] = PaletteSwatch.seed

    /// The saved views, in sidebar order.
    ///
    /// Since v11, when the seven stopped being an enum and became editable rows
    /// — see ``SavedView``. Defaulted to the seeded seven, which is what a file
    /// written before them means: a build whose sidebar offered exactly those.
    var views: [SavedView] = SavedView.seededAll

    /// When the user last changed the saved views, the palette and the themes —
    /// **not** when the file was last written.
    ///
    /// These three are the lists two devices can both hold an opinion about and
    /// that CloudKit cannot merge for them: each is one blob in one record, so
    /// without a clock the winner is whichever device saved last, which need
    /// not be the device that did the editing. A laptop that has not touched
    /// its views since March could overwrite this morning's iPad edit just by
    /// saving something unrelated.
    ///
    /// `nil` means **undated**, which is a real answer rather than a missing
    /// one: every file written before v15, and every list nobody has touched
    /// since. An undated list is never overwritten by a dated one — it is
    /// merged with it, see ``SharedList/resolve(local:changedAt:remote:changedAt:)``
    /// — because the alternative is deciding that work nobody can date is work
    /// nobody did.
    ///
    /// Since v15. The tasks need none of this: a card carries its own
    /// `updatedAt` and CloudKit merges two devices card by card.
    var viewsChangedAt: Date?
    var paletteChangedAt: Date?
    var themesChangedAt: Date?

    static let currentVersion = 16

    enum CodingKeys: String, CodingKey {
        case version, tasks, boards, labels, nextSerial, activeBoardID, trash, palette, views, themes
        case viewsChangedAt, paletteChangedAt, themesChangedAt
    }

    /// Written out rather than synthesised, for one field.
    ///
    /// A synthesised `init(from:)` throws `keyNotFound` for a key the file does
    /// not carry, **and a property default does not save you** — which is fine
    /// for the fields every version wrote and wrong for `trash`, which v6 and
    /// everything before it had never heard of. Without this the v5 and v6
    /// branches of `decode(_:)` would route a perfectly good file into the
    /// current decoder and get a `keyNotFound` back, and the user's board would
    /// be quarantined as corrupt by a feature they have not used yet.
    ///
    /// Only `trash` is lenient. Everything else stays strict on purpose: a board
    /// file with no `tasks` key is not a board file with no tasks, it is not a
    /// board file, and reading it as an empty board would write that emptiness
    /// straight back over the user's work.
    ///
    /// This is the same shape `BoardSnapshotV4` uses for the same reason, and
    /// the price of it is the same: a field added here has to be added below.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        tasks = try container.decode([TaskItem].self, forKey: .tasks)
        boards = try container.decode([Board].self, forKey: .boards)
        labels = try container.decode([LabelDef].self, forKey: .labels)
        nextSerial = try container.decode(Int.self, forKey: .nextSerial)
        activeBoardID = try container.decodeIfPresent(Board.ID.self, forKey: .activeBoardID)
        trash = try container.decodeIfPresent([TrashedItem].self, forKey: .trash) ?? []
        // Lenient for `trash`'s reason, and one of its own: a palette decoded
        // as empty is a picker with nothing in it, so the absence of the key
        // has to mean the six rather than none.
        palette = try container.decodeIfPresent([PaletteSwatch].self, forKey: .palette) ?? PaletteSwatch.seed
        // Lenient again, and the *absent* case is the seven rather than none:
        // every file written before v11 had them, and reading their absence as
        // an empty sidebar would take Today away from everyone who upgraded.
        //
        // An empty array that is genuinely *there* is respected — that is
        // somebody who deleted all seven, and handing them back would make the
        // deletion un-stick on every launch.
        views = try container.decodeIfPresent([SavedView].self, forKey: .views) ?? SavedView.seededAll
        // Lenient once more, and the absence means the two defaults: a file
        // written before v12 chose an accent rather than a theme, and what its
        // accent becomes is `BoardMigration.migrate(v11:accent:)`'s answer
        // rather than this decoder's — it needs the bytes, which are gone by
        // the time this runs.
        themes = try container.decodeIfPresent(ThemeSettings.self, forKey: .themes) ?? .seed
        // Lenient a fourth time, and here the absence *is* the value: a file
        // written before v15 carries three lists nobody could date, which is
        // exactly what `nil` says. See the properties.
        viewsChangedAt = try container.decodeIfPresent(Date.self, forKey: .viewsChangedAt)
        paletteChangedAt = try container.decodeIfPresent(Date.self, forKey: .paletteChangedAt)
        themesChangedAt = try container.decodeIfPresent(Date.self, forKey: .themesChangedAt)
    }

    init(
        version: Int = BoardSnapshot.currentVersion,
        tasks: [TaskItem],
        boards: [Board] = SeedData.boards,
        labels: [LabelDef],
        nextSerial: Int,
        activeBoardID: Board.ID? = nil,
        trash: [TrashedItem] = [],
        views: [SavedView] = SavedView.seededAll,
        palette: [PaletteSwatch] = PaletteSwatch.seed,
        themes: ThemeSettings = .seed,
        viewsChangedAt: Date? = nil,
        paletteChangedAt: Date? = nil,
        themesChangedAt: Date? = nil
    ) {
        self.version = version
        self.tasks = tasks
        self.boards = boards
        self.labels = labels
        self.nextSerial = nextSerial
        self.activeBoardID = activeBoardID
        self.trash = trash
        self.views = views
        self.palette = palette
        self.themes = themes
        self.viewsChangedAt = viewsChangedAt
        self.paletteChangedAt = paletteChangedAt
        self.themesChangedAt = themesChangedAt
    }

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
    /// whole code is what lets `discardIfBlank` hand a serial back without
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
            String(localized: "The board file was saved by a newer version of Cardstock (format \(version)).",
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

    private static let logger = Logger(subsystem: "com.n14395.Cardstock", category: "persistence")

    /// `~/Library/Application Support/Cardstock/board.json` on both platforms.
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
                .appending(path: "CardstockTestHost-\(UUID().uuidString)/board.json"))
        }
        return BoardFile(url: base.appending(path: "Cardstock/board.json"))
    }()

    /// True when this process was launched by a test runner rather than by a
    /// person. Both spellings are checked because Swift Testing and XCTest
    /// announce themselves differently.
    ///
    /// Not private: `BoardStore.scheduleSave` asks it the same question about
    /// the two *other* pieces of machine-wide state the app owns — see there.
    ///
    /// Cached: the runner sets these variables when it spawns the process, so
    /// the answer cannot change, and `ProcessInfo.environment` rebuilds the
    /// whole dictionary on every read — too dear for a question `scheduleSave`
    /// asks on every mutation.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
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
    /// because a decoder throws `keyNotFound` for a field the older shape never
    /// wrote — and a property default does not save you. Routing on the version
    /// first is what keeps a v1 file out of the current decoder.
    ///
    /// The three versions that *do* come through the current decoder — v5, v6
    /// and v7, which share this shape — get there because `init(from:)` above is
    /// written rather than synthesised, and reads `trash` leniently. That is the
    /// only leniency there is; every other absent key is still a refusal.
    ///
    /// Each older version is decoded by the shape that wrote it and then walked
    /// forward one step at a time, so a v1 file passes through exactly the same
    /// v4 → v5 code a v4 file does. Widening an old decoder to reach the current
    /// shape instead would make every future field silently rewrite the past.
    static func decode(_ data: Data) throws -> (snapshot: BoardSnapshot, migratedFrom: Int?) {
        let (snapshot, migratedFrom) = try decodeToV8(data)
        guard let migratedFrom else { return (snapshot.settlingDuplicates(), nil) }
        // The v8 step is applied once at the end of whichever chain ran, because
        // it is the only one that needs something the *bytes* still have and the
        // decoded value no longer does — see `migrate(v8:legacyDoneColumns:)`.
        // A v9 file is already past it and must not be walked through it again.
        let atV9 = migratedFrom < 9
            ? BoardSnapshot.migrate(v8: snapshot, legacyDoneColumns: legacyDoneColumns(in: data))
            : snapshot
        let atV10 = migratedFrom < 10 ? BoardSnapshot.migrate(v9: atV9) : atV9
        let atV11 = migratedFrom < 11 ? BoardSnapshot.migrate(v10: atV10) : atV10
        // The accent comes out of the bytes for `legacyDoneColumns`' reason:
        // v12 removed the field, so the decoded value no longer has it.
        let atV12 = migratedFrom < 12
            ? BoardSnapshot.migrate(v11: atV11, accent: legacyAccent(in: data))
            : atV11
        let atV13 = migratedFrom < 13 ? BoardSnapshot.migrate(v12: atV12) : atV12
        let atV14 = migratedFrom < 14 ? BoardSnapshot.migrate(v13: atV13) : atV13
        let atV15 = migratedFrom < 15 ? BoardSnapshot.migrate(v14: atV14) : atV14
        let current = migratedFrom < 16 ? BoardSnapshot.migrate(v15: atV15) : atV15
        return (current.settlingDuplicates(), migratedFrom)
    }

    /// Every version up to and including v8, decoded and walked forward to the
    /// v8 shape. `nil` for a file that is already current and needs no step.
    private static func decodeToV8(_ data: Data) throws -> (BoardSnapshot, Int?) {
        let decoder = JSONDecoder()
        switch try version(of: data) {
        case BoardSnapshot.currentVersion:
            return (try decoder.decode(BoardSnapshot.self, from: data), nil)
        case 15:
            // v15 and v16 are the same shape in the one direction that matters
            // here: v16 *removes* a board's `dot` and *adds* its `symbol`, and
            // an unknown key is not a decoding failure while `Board.init(from:)`
            // is lenient about the new one — so a v15 file reads whole and every
            // board lands on the fallback mark. What it is dealt instead is
            // `migrate(v15:)`'s answer. The bump is for the other direction, as
            // ever.
            return (try decoder.decode(BoardSnapshot.self, from: data), 15)
        case 14:
            // v14 and v15 are the same shape: v15 only *adds* the three dates,
            // and `init(from:)` reads each of them leniently — an absent one is
            // an undated list, which is the truth about every file written
            // before there was anywhere to write a date. The bump is for the
            // other direction, as ever — see `migrate(v14:)`.
            return (try decoder.decode(BoardSnapshot.self, from: data), 14)
        case 13:
            // v13 and v14 are the same shape: v14 only *adds*
            // `BoardColumn.limit`, and a synthesised decoder reads an absent
            // `Optional` as `nil`, which is what a column written before there
            // were WIP limits means. The bump is for the other direction, as
            // ever — see `migrate(v13:)`.
            return (try decoder.decode(BoardSnapshot.self, from: data), 13)
        case 12:
            // The new Inbox-completion timestamp is optional on `TaskItem`, so
            // v12 bytes already decode as the v13 shape without inventing state.
            return (try decoder.decode(BoardSnapshot.self, from: data), 12)
        case 11:
            // v11 and v12 are the same shape in the one direction that matters
            // here: v12 *removes* `accentTheme` and *adds* `themes`, both of
            // which the current decoder is lenient about, so a v11 file reads
            // whole and its accent is picked up separately — see
            // `migrate(v11:accent:)`. The bump is for the other direction, as
            // ever: a v11 build handed a v12 file finds no accent, throws, and
            // quarantines a board it could otherwise have shown.
            return (try decoder.decode(BoardSnapshot.self, from: data), 11)
        case 10:
            // v10 and v11 are the same shape: v11 only *adds* the saved views,
            // and the field is defaulted, so the current decoder reads a v10
            // file whole and gets the seeded seven — which is exactly the seven
            // a v10 build's sidebar drew, because they were an enum in the
            // source rather than rows in the file. The bump is for the other
            // direction: a v10 build handed a v11 file drops every view the user
            // made and writes the loss straight back.
            return (try decoder.decode(BoardSnapshot.self, from: data), 10)
        case 9:
            // v9 and v10 are the same shape: v10 only *adds* the palette, and
            // the field is defaulted, so the current decoder reads a v9 file
            // whole and gets the six colours it was offering anyway. The bump is
            // for what a *v9* build does with a v10 file — it would drop the
            // palette on the way in and write the loss back out, taking every
            // colour the user had mixed with it.
            return (try decoder.decode(BoardSnapshot.self, from: data), 9)
        case 8:
            // v8 and v9 are the same shape: v9 *removes* `ColumnRole` from each
            // column, and an unknown key is not a decoding failure, so the
            // current decoder reads a v8 file whole. What it cannot read is the
            // roles — which is exactly what the step below needs, and why it
            // takes them from the bytes instead.
            return (try decoder.decode(BoardSnapshot.self, from: data), 8)
        case 7:
            // v7 and v8 are the same shape as well: v8 adds a priority above
            // High and moves what a new card starts on, neither of which is a
            // field. The bump is for what a *v7* build does with a v8 file —
            // see `migrate(v7:)`, which is the one step here whose absence
            // would cost somebody their board rather than a field of it.
            return (BoardSnapshot.migrate(v7: try decoder.decode(BoardSnapshot.self, from: data)), 7)
        case 6:
            // v6 and v7 are the same shape: v7 only *adds* the trash, and the
            // field is defaulted, so the current decoder reads a v6 file whole
            // and gets an empty trash — which is the truth about it. The bump
            // still has to happen; see `migrate(v6:)` for what a v6 build would
            // otherwise do to a v7 file.
            return (
                BoardSnapshot.migrate(v7: BoardSnapshot.migrate(v6: try decoder.decode(BoardSnapshot.self, from: data))),
                6
            )
        case 5:
            // v5 and v6 are the same shape too. What changed is how `Priority`
            // spells itself on disk, which `Priority.init(stored:)` absorbs, so
            // the current decoder reads a v5 file — but the bump still has to
            // happen, because the reverse is not true and a v5 build must
            // refuse this file rather than lose every priority in it.
            return (
                BoardSnapshot.migrate(
                    v7: BoardSnapshot.migrate(v6: BoardSnapshot.migrate(v5: try decoder.decode(BoardSnapshot.self, from: data)))
                ),
                5
            )
        case 4:
            let v4 = try decoder.decode(BoardSnapshotV4.self, from: data)
            return (
                BoardSnapshot.migrate(
                    v7: BoardSnapshot.migrate(v6: BoardSnapshot.migrate(v5: BoardSnapshot.migrate(v4: v4)))
                ),
                4
            )
        case 3:
            let v3 = try decoder.decode(BoardSnapshotV3.self, from: data)
            return (
                BoardSnapshot.migrate(
                    v7: BoardSnapshot.migrate(
                        v6: BoardSnapshot.migrate(v5: BoardSnapshot.migrate(v4: BoardSnapshot.migrate(v3: v3)))
                    )
                ),
                3
            )
        case 2:
            let v2 = try decoder.decode(BoardSnapshotV2.self, from: data)
            return (
                BoardSnapshot.migrate(
                    v7: BoardSnapshot.migrate(
                        v6: BoardSnapshot.migrate(
                            v5: BoardSnapshot.migrate(v4: BoardSnapshot.migrate(v3: BoardSnapshot.migrate(v2: v2)))
                        )
                    )
                ),
                2
            )
        case 1:
            let v1 = try decoder.decode(BoardSnapshotV1.self, from: data)
            return (
                BoardSnapshot.migrate(
                    v7: BoardSnapshot.migrate(
                        v6: BoardSnapshot.migrate(
                            v5: BoardSnapshot.migrate(
                                v4: BoardSnapshot.migrate(v3: BoardSnapshot.migrate(v2: BoardSnapshot.migrate(v1: v1)))
                            )
                        )
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

    /// The column each board would have sent a tick to under v8: the **first**
    /// one whose `ColumnRole` said `done`.
    ///
    /// Read straight out of the bytes rather than off the decoded snapshot,
    /// because v9 removed the field and the decoder therefore throws it away —
    /// see `BoardMigration.migrate(v8:legacyDoneColumns:)`, which is the only
    /// caller. A tiny shape rather than a frozen copy of the whole v8 snapshot:
    /// one key of one array is all the step needs, and a full `BoardSnapshotV8`
    /// would be several hundred lines that exist to answer a yes/no question.
    ///
    /// Silent about failure on purpose. A v1–v4 file has no `boards` key at all
    /// and yields nothing, which is the right answer — those are rebuilt out of
    /// `BoardColumn.workflow` on the way through and already end in Done.
    static func legacyDoneColumns(in data: Data) -> [BoardColumn.ID] {
        struct Roles: Decodable {
            struct Board: Decodable { var columns: [Column] }
            struct Column: Decodable { var id: UUID; var role: String }
            var boards: [Board]
        }
        guard let roles = try? JSONDecoder().decode(Roles.self, from: data) else { return [] }
        return roles.boards.compactMap { board in
            board.columns.first { $0.role == "done" }?.id
        }
    }

    /// The accent a v11 file chose, as a literal.
    ///
    /// Out of the bytes rather than off the decoded snapshot, exactly as
    /// ``legacyDoneColumns(in:)`` is and for the same reason: v12 removed the
    /// field, so the decoder throws it away. `nil` for a file that never had one
    /// and for `ink`, which is not a hex — it was the theme's own text colour,
    /// and there is no theme parameter that can mean that.
    static func legacyAccent(in data: Data) -> UInt32? {
        struct Accent: Decodable { var accentTheme: String }
        guard let found = try? JSONDecoder().decode(Accent.self, from: data) else { return nil }
        switch found.accentTheme {
        case "ember": return 0xC2532F
        case "pine": return 0x1F6F63
        case "indigo": return 0x3B5BA9
        default: return nil
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

    /// Whether this snapshot is still arriving: a task naming a column that no
    /// board here has.
    ///
    /// CloudKit applies records and relationships independently, so a board and
    /// the columns it is made of do not land together. A card pointing at a
    /// column nothing has yet is not a card in the Inbox — it is a card whose
    /// board is halfway here — and the two readings are the difference between
    /// waiting a moment and rewriting somebody's board.
    ///
    /// Asked in two places, which is why it is here rather than on either of
    /// them. ``BoardStore`` asks it to decide whether to *adopt* a read.
    /// ``BoardSyncStore/load()`` asks it to decide whether that read may become
    /// the **diff base** — and that second question was not being asked at all.
    /// The base advanced on every read, adopted or not, so a declined read left
    /// this device believing the records held a board its own board list had
    /// never heard of. The next save read the difference as a deletion, and
    /// deleted a board somebody had just made on another device, along with
    /// the cards on it. See `NewBoardTests`.
    var hasUnresolvedPlacements: Bool {
        let columns = Set(boards.flatMap(\.columns).map(\.id))
        return tasks.contains { task in
            task.columnID.map { !columns.contains($0) } ?? false
        }
    }

    /// One of each, where the records cannot promise it.
    ///
    /// CloudKit enforces no uniqueness, so two devices that each create the
    /// same logical row leave **two records under one id** — the case
    /// ``BoardSyncStore/deduplicated(_:by:newest:)`` exists for. It settles the
    /// three record types that stand on their own: tasks, boards and labels.
    /// The three that hang off a parent record were settled by nothing at all:
    /// a board's columns, and a task's sub-tasks and activity.
    ///
    /// The symptom was a column drawn twice, and it did not stay still. The
    /// board that was read carried both, the save that followed wrote the board
    /// that was read, and the write found no record for the second copy of an
    /// id it had already written — so it made one. Every save doubled the board
    /// again. Sub-tasks and activity had the same hole and the same shape.
    ///
    /// Applied at the two doors board data comes in through — ``decode(_:)``
    /// for the file, an import and a backup, and `BoardSyncStore.load()` for
    /// the records — because in-memory the app cannot make one: every verb that
    /// adds a column, a sub-task or an entry mints a fresh id for it.
    ///
    /// The first of each id wins, which is not arbitrary: both readers order
    /// their rows totally before calling this, so two devices settling the same
    /// pair keep the same one.
    func settlingDuplicates() -> BoardSnapshot {
        var settled = self
        settled.boards = boards.map { board in
            var board = board
            board.columns = Self.oneOfEach(board.columns, by: \.id)
            return board
        }
        settled.tasks = tasks.map { task in
            var task = task
            task.subtasks = Self.oneOfEach(task.subtasks, by: \.id)
            task.activity = Self.oneOfEach(task.activity, by: \.id)
            return task
        }
        return settled
    }

    /// The first element under each key, in the order they were given.
    private static func oneOfEach<Element, Key: Hashable>(
        _ elements: [Element], by key: KeyPath<Element, Key>
    ) -> [Element] {
        var seen: Set<Key> = []
        return elements.filter { seen.insert($0[keyPath: key]).inserted }
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


/// Which of two answers about a shared list stands, when two devices both have
/// one and CloudKit cannot merge them.
///
/// The saved views, the palette and a theme collection are each stored as one
/// blob in one record — see ``SyncSchema`` — so there is nothing for CloudKit
/// to reconcile element by element the way it does cards. Somebody has to
/// choose, and this is the whole of the choosing:
///
/// | this device | the records | what stands |
/// | --- | --- | --- |
/// | anything | never written | this device's |
/// | dated | dated | the newer of the two |
/// | undated | anything, or the reverse | **both**, merged by id |
///
/// **The last row is the one that matters**, and it is why the dates were added
/// at all. An undated list is one nobody could date — a board file from before
/// v15, or a list nobody has touched since — and the honest thing to do with two
/// of those is to keep everything in either. It costs one oddity: a view deleted
/// before any of this existed can come back the first time two devices meet.
/// That is the safe direction, it happens once, and any edit afterwards dates
/// the list and settles it for good.
///
/// Order is this device's first, then whatever the other side has that this one
/// has not — so a merge never reshuffles a sidebar somebody has arranged.
enum SharedList {
    /// `remote` is `nil` where the records carry no such list at all, which is
    /// not the same fact as an empty one: it is what every record written
    /// before the field existed says, and what it means is "ask this device".
    static func resolve<Element: Identifiable>(
        local: [Element], changedAt localStamp: Date?,
        remote: [Element]?, changedAt remoteStamp: Date?
    ) -> (list: [Element], changedAt: Date?) {
        guard let remote else { return (local, localStamp) }
        if let localStamp, let remoteStamp {
            return remoteStamp > localStamp ? (remote, remoteStamp) : (local, localStamp)
        }
        let known = Set(local.map(\.id))
        return (local + remote.filter { !known.contains($0.id) }, localStamp ?? remoteStamp)
    }

    /// The same question asked of a whole ``ThemeSettings``.
    ///
    /// The custom themes are a list and merge as one. **The two slots do not**:
    /// which theme is showing in light and which in dark is a scalar, and a
    /// merge of two scalars is just a choice — so an undated pair keeps this
    /// machine's, on the same principle that puts the light/dark override in
    /// `UserDefaults`. What the app looks like belongs to the machine you are
    /// looking at; the themes themselves are work and travel.
    static func resolve(
        local: ThemeSettings, changedAt localStamp: Date?,
        remote: ThemeSettings?, changedAt remoteStamp: Date?
    ) -> (themes: ThemeSettings, changedAt: Date?) {
        guard let remote else { return (local, localStamp) }
        let merged = resolve(
            local: local.custom, changedAt: localStamp,
            remote: remote.custom, changedAt: remoteStamp
        )
        let slots: ThemeSettings = {
            guard let localStamp, let remoteStamp, remoteStamp > localStamp else { return local }
            return remote
        }()
        return (
            ThemeSettings(lightID: slots.lightID, darkID: slots.darkID, custom: merged.list),
            merged.changedAt
        )
    }
}

extension SharedList {
    /// The three lists after this device's answer and the records' have been
    /// put to the rule above — the one place both the launch and a pull ask,
    /// so the two cannot come to different conclusions.
    struct Outcome: Equatable, Sendable {
        var views: [SavedView]
        var viewsChangedAt: Date?
        var palette: [PaletteSwatch]
        var paletteChangedAt: Date?
        var themes: ThemeSettings
        var themesChangedAt: Date?
    }

    /// `local` is `nil` on a device with no board file at all — a fresh
    /// install, where there is nothing to defend and the records are simply
    /// the answer.
    ///
    /// `carried` is what the record set actually holds, as opposed to what
    /// ``BoardSyncStore/load()`` had to fill in: a list it does not carry is
    /// passed down as `nil`, which is what stops "nobody has written one" from
    /// being read as "somebody wrote the defaults".
    static func resolve(
        local: BoardSnapshot?, remote: BoardSnapshot, carried: SyncedLists
    ) -> Outcome {
        let remoteViews = carried.contains(.views) ? remote.views : nil
        let remotePalette = carried.contains(.palette) ? remote.palette : nil
        let remoteThemes = carried.contains(.themes) ? remote.themes : nil
        guard let local else {
            return Outcome(
                views: remoteViews ?? SavedView.seededAll,
                viewsChangedAt: remoteViews == nil ? nil : remote.viewsChangedAt,
                palette: remotePalette ?? PaletteSwatch.seed,
                paletteChangedAt: remotePalette == nil ? nil : remote.paletteChangedAt,
                themes: remoteThemes ?? .seed,
                themesChangedAt: remoteThemes == nil ? nil : remote.themesChangedAt
            )
        }
        let views = resolve(
            local: local.views, changedAt: local.viewsChangedAt,
            remote: remoteViews, changedAt: remote.viewsChangedAt
        )
        let palette = resolve(
            local: local.palette, changedAt: local.paletteChangedAt,
            remote: remotePalette, changedAt: remote.paletteChangedAt
        )
        let themes = resolve(
            local: local.themes, changedAt: local.themesChangedAt,
            remote: remoteThemes, changedAt: remote.themesChangedAt
        )
        return Outcome(
            views: views.list, viewsChangedAt: views.changedAt,
            palette: palette.list, paletteChangedAt: palette.changedAt,
            themes: themes.themes, themesChangedAt: themes.changedAt
        )
    }
}
