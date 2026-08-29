import Foundation
import OSLog

/// The hand-off between the share extension and the app: a folder in the App
/// Group holding whatever has been shared and not yet drained.
///
/// **One file per capture, not one file appended to.** Two share sheets in
/// quick succession are two processes, and a read-modify-write of a shared list
/// across two processes loses one of them — there is no lock either side could
/// take that the other is guaranteed to respect. A file each has no race at all:
/// the writer creates a name nothing else will choose, and the reader takes
/// whatever it finds.
///
/// **The extension writes here and nowhere else.** It never opens `board.json`
/// and never opens the SwiftData store. The board file is versioned, migrated on
/// the way in, quarantined when it cannot be read, and is the only copy of the
/// user's work — none of which is safe to hand to a process the system starts
/// and kills around a share sheet. `WidgetShare` makes the same argument for the
/// widgets from the read side; this is the write side of the same fence.
///
/// **A capture is not a cache.** The digest is refused when it cannot be
/// decoded, because the app rewrites it within half a second. This is the only
/// copy of something the user typed, so a capture that cannot be decoded is set
/// aside — see ``reject(_:)`` — rather than deleted or retried forever.
enum CaptureInbox {
    private static let logger = Logger(subsystem: "com.n14395.SimpleKanban", category: "capture")

    /// Beside the widgets' folder rather than at the root of the container,
    /// which is what `WidgetShare.digestURL` left room for.
    static var directory: URL? {
        override ?? WidgetShare.container?.appending(path: "Captures")
    }

    /// A directory swapped in for the length of one test.
    ///
    /// **A simulator build is never entitled to the App Group** — Xcode strips
    /// the entitlements dict, the same fact `project.yml` records about
    /// CloudKit — so `WidgetShare.container` is `nil` on the iOS test host, and
    /// a suite that merely guarded on it would assert nothing at all on that
    /// platform. `Preferences.defaults` makes the same bargain for the same
    /// reason.
    nonisolated(unsafe) private static var override: URL?

    /// Reads and writes captures in `directory` for the length of `body`.
    ///
    /// `@MainActor` and nothing else, exactly as `Preferences.reading(_:_:)`
    /// argues: everything that touches a capture — the extension's write, the
    /// app's drain — does so on the main actor, so a main-actor function cannot
    /// be interleaved with one, and Swift Testing's parallel suites cannot read
    /// this mid-swap.
    @MainActor
    static func using<Result>(_ directory: URL, _ body: () throws -> Result) rethrows -> Result {
        let previous = override
        override = directory
        defer { override = previous }
        return try body()
    }

    private static let fileExtension = "json"
    /// What a capture the app could not read is renamed to. Out of the way of
    /// the enumerator below, and still on disk.
    private static let rejectedExtension = "rejected"

    /// Why a capture could not be written, in the one sentence the share sheet
    /// shows. There is no recovery here and no retry: the user is looking at a
    /// sheet, and the honest thing is to say it did not work while their text is
    /// still in front of them.
    enum WriteError: Swift.Error {
        /// This build is not entitled to the App Group, which is what a
        /// developer build signed without it looks like. Not a crash, and not
        /// something the user can act on — but it must not look like success.
        case noContainer
        case failed(any Swift.Error)
    }

    static func write(_ capture: PendingCapture) throws(WriteError) {
        guard let directory else { throw WriteError.noContainer }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(capture)
            // Atomic, because the reader is another process that may wake at
            // any moment: a half-written capture is one the app would set aside
            // as unreadable, and the user would have to share it again.
            try data.write(to: url(for: capture.id), options: .atomic)
            return
        } catch {
            logger.error("Could not write a shared capture: \(error.localizedDescription)")
            throw WriteError.failed(error)
        }
    }

    /// Everything waiting, oldest first — the order they were shared in, which
    /// is the order they should reach the Inbox.
    ///
    /// A file that will not decode is **not** returned and **not** deleted: it
    /// is left for ``reject(_:)``, which ``BoardStore/adoptPendingCaptures()``
    /// calls. Silence here would mean a broken capture retried on every launch
    /// forever.
    static func pending() -> (captures: [PendingCapture], unreadable: [URL]) {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              )
        else { return ([], []) }

        var captures: [PendingCapture] = []
        var unreadable: [URL] = []
        for file in names where file.pathExtension == fileExtension {
            guard let data = try? Data(contentsOf: file),
                  let capture = try? JSONDecoder().decode(PendingCapture.self, from: data)
            else {
                unreadable.append(file)
                continue
            }
            captures.append(capture)
        }
        return (captures.sorted { $0.createdAt < $1.createdAt }, unreadable)
    }

    /// Takes one capture off the queue. Called only once its card exists — see
    /// ``BoardStore/adoptPendingCaptures()`` — so a crash between the two costs
    /// a duplicate card rather than a lost one, which is the right way round.
    static func remove(_ id: PendingCapture.ID) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: url(for: id, in: directory))
    }

    /// Renames a capture this build cannot read, so it stops being offered and
    /// is still there for anybody who goes looking.
    ///
    /// The same shape as a quarantined board file, and for the same reason:
    /// deleting it would be silent loss, and leaving it would mean failing over
    /// it on every launch for the rest of the install's life.
    static func reject(_ file: URL) {
        let destination = file.deletingPathExtension().appendingPathExtension(rejectedExtension)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: file, to: destination)
            logger.error("A shared capture could not be read; kept as \(destination.lastPathComponent)")
        } catch {
            logger.error("A shared capture could not be read or set aside: \(error.localizedDescription)")
        }
    }

    private static func url(for id: PendingCapture.ID) -> URL {
        // Force-unwrapped nowhere: every caller has already established the
        // directory. The private overload below is the one that takes it.
        url(for: id, in: directory ?? FileManager.default.temporaryDirectory)
    }

    private static func url(for id: PendingCapture.ID, in directory: URL) -> URL {
        directory.appending(path: "\(id.uuidString).\(fileExtension)")
    }
}
