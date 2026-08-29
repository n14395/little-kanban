import Foundation

/// The App Group, and the digest the app and its widgets both hold.
///
/// It is no longer the only thing in the container: `CaptureInbox` puts a
/// `Captures/` folder beside `Widgets/` for the share extension to write into,
/// which is exactly what ``digestURL`` left room for below.
///
/// **Not `board.json`.** The board file lives in the app's own container, it is
/// versioned, it is migrated on the way in, and it is the only copy of the
/// user's work — three good reasons not to hand a read of it to a process that
/// runs on the system's schedule rather than the user's. What crosses the fence
/// instead is a *digest*: a small, flat, capped rendering of exactly what the
/// widgets draw, written by the app and only ever read by them. See
/// ``WidgetDigest``.
///
/// That also decides what happens when the two sides disagree about a format.
/// A digest the extension cannot decode is a widget drawing its placeholder for
/// as long as it takes the app to write the next one — where a board file the
/// extension could not decode would be a board file the extension might
/// *quarantine*.
enum WidgetShare {
    /// The App Group both bundles are entitled to.
    ///
    /// **Spelled differently on each platform, and it has to be.** A sandboxed
    /// macOS app may only join a group whose identifier begins with its team
    /// identifier; iOS wants the conventional `group.` prefix and rejects the
    /// team-prefixed spelling in provisioning. One constant per platform is the
    /// only arrangement that signs on both.
    #if os(macOS)
    static let appGroup = "P52946XHRJ.group.com.n14395.SimpleKanban"
    #else
    static let appGroup = "group.com.n14395.SimpleKanban"
    #endif

    /// The group's container, or `nil` when this build is not entitled to it —
    /// which is what a developer build signed without the group looks like, and
    /// is not a crash. The app then publishes nothing and the widgets draw
    /// their placeholder, which is a great deal better than a trap on a queue
    /// nobody owns.
    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    /// Where the digest is written. In a folder of its own rather than at the
    /// root of the container, so that anything else that ever needs to cross
    /// the fence has somewhere to go that is not beside this.
    static var digestURL: URL? {
        container?.appending(path: "Widgets/digest.json")
    }

    /// The kinds the widget bundle registers, named once so that the app can
    /// reload a single one and the extension cannot drift from it.
    ///
    /// These strings are stored by the system against every widget the user has
    /// placed, so they are *identifiers*: renaming one silently orphans
    /// everybody's existing widgets. They stay as written.
    enum Kind {
        static let inbox = "SimpleKanbanInbox"
        static let boardOverview = "SimpleKanbanBoardOverview"
        static let column = "SimpleKanbanColumn"
        static let savedView = "SimpleKanbanSavedView"

        static let all = [inbox, boardOverview, column, savedView]
    }
}
