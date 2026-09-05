import Foundation

/// Every place outside the app that can name a place inside it.
///
/// The app has answered `cardstock://task/<uuid>` since links existed — see
/// ``TaskLink`` — and a widget needs four more: the board it is showing, the
/// column it is showing, the saved view it is showing, and the two things the
/// Inbox widget's `+` and header do. They are one vocabulary rather than five
/// call sites building strings, because the extension writes these URLs and the
/// app reads them, and the two are in different targets: a shape that drifted
/// would be a widget whose taps do nothing, reported as "the widget is broken".
///
/// **Widgets link rather than act.** Every destination here opens the app.
/// WidgetKit will run an `AppIntent` in the background from a button, and for
/// "add a task" that is exactly the wrong thing — a task added from a widget
/// with no title and no way to type one is litter the user then has to find and
/// delete. ``newTask`` opens the app on a fresh Inbox capture with its title
/// field focused, which is what the app's own `+` does.
enum AppLink {
    static let scheme = "cardstock"

    /// What a link names. Cases carry ids and nothing else: a link is written
    /// by one process and read by another, possibly after the thing it names
    /// has been renamed, moved or deleted, so anything else it carried would be
    /// a copy that could be wrong by the time it arrived.
    enum Destination: Hashable, Sendable {
        case task(UUID)
        case board(UUID)
        /// The column's own id, without its board's. A column resolves to
        /// exactly one board — the store answers `board(ofColumn:)` — so
        /// carrying the pair would only create the possibility of a link whose
        /// two halves disagree.
        case column(UUID)
        case view(UUID)
        case inbox
        case newTask
    }

    /// The host each destination is spelled with. Stored by the system inside
    /// every widget the user has placed, so these are identifiers and stay as
    /// written.
    private enum Host {
        static let task = "task"
        static let board = "board"
        static let column = "column"
        static let view = "view"
        static let inbox = "inbox"
        static let newTask = "new"
    }

    static func url(_ destination: Destination) -> URL {
        let text = switch destination {
        case .task(let id): "\(scheme)://\(Host.task)/\(Self.text(id))"
        case .board(let id): "\(scheme)://\(Host.board)/\(Self.text(id))"
        case .column(let id): "\(scheme)://\(Host.column)/\(Self.text(id))"
        case .view(let id): "\(scheme)://\(Host.view)/\(Self.text(id))"
        case .inbox: "\(scheme)://\(Host.inbox)"
        case .newTask: "\(scheme)://\(Host.newTask)"
        }
        // Every string above is built from a fixed host and a UUID, so the only
        // way this fails is a change to the shapes — which the tests would have
        // caught first. The fallback keeps the signature non-optional so that
        // no call site has to have an opinion about a case that cannot arise.
        return URL(string: text) ?? URL(filePath: "/")
    }

    /// What a URL names, or `nil` when it names nothing this app can open.
    ///
    /// Strict about the shape, which is ``TaskLink/taskID(in:)``'s rule and its
    /// reason: a link that is not one of ours must not be read as a link to
    /// something that has gone away, because those two get different sentences
    /// from the router.
    static func destination(of url: URL) -> Destination? {
        guard url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame,
              let host = url.host()?.lowercased()
        else { return nil }
        switch host {
        case Host.inbox: return isBare(url) ? .inbox : nil
        case Host.newTask: return isBare(url) ? .newTask : nil
        case Host.task: return identified(url, as: Destination.task)
        case Host.board: return identified(url, as: Destination.board)
        case Host.column: return identified(url, as: Destination.column)
        case Host.view: return identified(url, as: Destination.view)
        default: return nil
        }
    }

    /// A host with nothing after it. `cardstock://inbox/anything` is not the
    /// Inbox with something on the end — it is a link whose shape this build
    /// does not know, and reading it as the Inbox would silently swallow a
    /// destination a later version might mean by it.
    private static func isBare(_ url: URL) -> Bool {
        let path = url.path()
        return path.isEmpty || path == "/"
    }

    private static func identified(
        _ url: URL, as make: (UUID) -> Destination
    ) -> Destination? {
        UUID(uuidString: url.lastPathComponent).map(make)
    }

    /// Lower-cased, because that is how the app has always written a task link
    /// and a URL somebody copied out of one has to read back the same.
    private static func text(_ id: UUID) -> String { id.uuidString.lowercased() }
}
