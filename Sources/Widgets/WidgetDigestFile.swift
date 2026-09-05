import Foundation
import OSLog

/// Reads and writes the digest, from either side of the fence.
///
/// Both ends are deliberately silent about failure. The app cannot do anything
/// useful about a container it is not entitled to, and the extension cannot do
/// anything useful about a digest that is missing or from another version — it
/// draws its placeholder and waits for the next write, which the app makes
/// within half a second of the next edit. Nothing here is on a path the user is
/// watching, so nothing here has anything to report.
enum WidgetDigestFile {
    private static let logger = Logger(subsystem: "com.n14395.LittleKanban", category: "widgets")

    /// Sorted keys and no pretty-printing: the app compares the bytes it is
    /// about to write against the bytes it wrote last to decide whether the
    /// widgets need waking, and a dictionary that encoded in a different order
    /// each time would wake them on every keystroke.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    /// The bytes for a digest, or `nil` when it cannot be encoded at all —
    /// which nothing in the shape can cause and is therefore not worth an error
    /// path anybody would ever read.
    static func encoded(_ digest: WidgetDigest) -> Data? {
        try? encoder.encode(digest)
    }

    /// Writes bytes already encoded by ``encoded(_:)``.
    ///
    /// Split from the encoding because the caller has to compare the bytes
    /// before deciding to write them at all, and encoding twice to do that
    /// would be the one expensive part of this done for nothing.
    @discardableResult
    static func write(_ data: Data) -> Bool {
        guard let url = WidgetShare.digestURL else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // Atomic, because the reader is another process on the system's own
            // schedule: a widget rendered halfway through a write would decode
            // nothing, and the digest has no second copy to fall back to.
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            logger.error("Could not publish the widget digest: \(error.localizedDescription)")
            return false
        }
    }

    /// The digest, or `nil` when there is none this build can read.
    static func read() -> WidgetDigest? {
        guard let url = WidgetShare.digestURL, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    /// **A version that is not this one is refused rather than migrated.** A
    /// board file gets a migration chain because it is the only copy of the
    /// user's work; a digest is a cache the app rewrites within half a second
    /// of the next edit, and the cost of refusing one is a widget that draws
    /// its sample for that half-second. The cost of *reading* one written by a
    /// build that meant something else by these fields is a widget quietly
    /// showing the wrong numbers, which is worse and much harder to notice.
    ///
    /// Split from ``read()`` so the refusal can be asserted about without a
    /// container to write into.
    static func decode(_ data: Data) -> WidgetDigest? {
        guard let digest = try? JSONDecoder().decode(WidgetDigest.self, from: data),
              digest.version == WidgetDigest.currentVersion
        else { return nil }
        return digest
    }
}
