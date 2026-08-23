import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The whole board as one document. Declared here *and* in the app's
    /// Info.plist (`project.yml` → `UTExportedTypeDeclarations` and
    /// `CFBundleDocumentTypes`) for the reason `simpleKanbanTask` gives: the
    /// plist is what the system reads, and the code declaration is what keeps
    /// the type meaning something inside a bundle that has not been registered.
    ///
    /// Conforms to `public.json` rather than `public.data`, unlike the two drag
    /// payloads: a `.simplekanban` file genuinely is JSON, and saying so is what
    /// lets somebody open one in a text editor without the system arguing.
    static let simpleKanbanBoard = UTType(
        exportedAs: "com.n14395.SimpleKanban.board", conformingTo: .json
    )

    /// Markdown, which this app does not own — hence *imported*, and declared in
    /// the Info.plist under `UTImportedTypeDeclarations`. Without the
    /// declaration the save panel has no extension to offer and names the
    /// Markdown export `.txt`.
    static let markdown = UTType(
        importedAs: "net.daringfireball.markdown", conformingTo: .plainText
    )
}

/// The board as a file, for `.fileExporter` and `.fileImporter`.
///
/// The bytes are exactly what `BoardFile` writes, through the same encoder, so
/// an exported document and `board.json` are one format rather than two — which
/// is also what lets a board file copied off another machine be imported
/// directly, and what makes `board.json` itself something worth handing to
/// somebody.
struct BoardTransferDocument: FileDocument {
    /// `.json` is readable too, so the file the user drags in off another Mac —
    /// which is `board.json`, with no `.simplekanban` extension — can be picked.
    static var readableContentTypes: [UTType] { [.simpleKanbanBoard, .json] }
    static var writableContentTypes: [UTType] { [.simpleKanbanBoard] }

    var snapshot: BoardSnapshot

    init(_ snapshot: BoardSnapshot) {
        self.snapshot = snapshot
    }

    /// Migrates an older file forward and throws on one this build cannot read,
    /// so an import either lands a whole board or lands nothing.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw BoardFileError.unreadable
        }
        snapshot = try BoardSnapshot.decoding(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try snapshot.encoded())
    }

    /// `Simple Kanban 2026-08-21`. Dated rather than named after the board,
    /// because an export is a moment rather than a thing — two exports of one
    /// board on different days are different files and should not collide.
    static func filename(on day: CalendarDay) -> String { "Simple Kanban \(day)" }
}

/// The same board as Markdown, which is the form most people actually want:
/// something to paste into a note, an issue or a message.
///
/// Export only. There is no importer for it and there should not be — Markdown
/// is lossy here (ids, timestamps and activity all go), and a round trip
/// through it would quietly discard the history the JSON document keeps.
struct BoardMarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [] }
    static var writableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(_ text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Renders a board as Markdown.
///
/// A pure function of the snapshot so it says the same thing wherever it is
/// called from, and grouped exactly the way the app is — the Inbox, then each
/// board by column, then the archive — so the file reads as the board looks
/// rather than as the file is stored.
enum BoardMarkdown {
    static func render(_ snapshot: BoardSnapshot, today: CalendarDay = .today()) -> String {
        var lines: [String] = ["# Simple Kanban", "", "_Exported \(today.description)_"]
        let names = Dictionary(
            snapshot.labels.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        let live = snapshot.tasks.filter { !$0.isArchived }

        let inbox = live.filter(\.isUnfiled)
        if !inbox.isEmpty {
            lines += section(Board.inboxName, tasks: inbox, done: false, labels: names)
        }

        for board in snapshot.boards {
            let onBoard = live.filter { $0.boardID == board.id }
            // A board with nothing on it is still a board the user made, and an
            // export that silently dropped it would read as data loss.
            lines += ["", "## \(board.name)"]
            for column in board.columns {
                let cards = onBoard.filter { $0.columnID == column.id }
                guard !cards.isEmpty else { continue }
                lines += section(column.name, tasks: cards, done: column.id == board.doneColumn?.id,
                                 labels: names, level: 3)
            }
        }

        let archived = snapshot.tasks.filter(\.isArchived)
        if !archived.isEmpty {
            lines += section(String(localized: "Archive", comment: "Markdown export heading for filed-away tasks"),
                             tasks: archived, done: true, labels: names)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func section(
        _ heading: String, tasks: [TaskItem], done: Bool,
        labels: [String: String], level: Int = 2
    ) -> [String] {
        var lines = ["", String(repeating: "#", count: level) + " \(heading)", ""]
        for task in tasks {
            lines.append("- [\(done ? "x" : " ")] `\(task.code)` \(task.displayTitle)\(trailer(task, labels: labels))")
            for subtask in task.subtasks {
                lines.append("  - [\(subtask.done ? "x" : " ")] \(subtask.text)")
            }
            let note = task.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                // Each line prefixed, so a multi-line description stays one
                // block quote rather than becoming a quote and some loose text.
                lines += note.split(separator: "\n", omittingEmptySubsequences: false).map { "  > \($0)" }
            }
        }
        return lines
    }

    /// The metadata that fits on the card's own line, in the order a card shows
    /// it. Omitted entirely where there is none, rather than left as an empty
    /// pair of brackets.
    private static func trailer(_ task: TaskItem, labels: [String: String]) -> String {
        var parts: [String] = []
        if let due = task.due { parts.append("due \(due.description)") }
        if task.priority != .default { parts.append(task.priority.displayName.lowercased()) }
        parts += task.labelKeys.map { labels[$0] ?? $0 }
        return parts.isEmpty ? "" : " — _\(parts.joined(separator: ", "))_"
    }
}


/// Reads a board file the user pointed at.
///
/// Three doors hand the app one — the import panel, a `.simplekanban` opened
/// from the Finder, and the same from Files — and every one of them arrives
/// security-scoped. Reading without claiming the scope is the sandbox failure
/// that only shows up in a signed build, so it is claimed in one place.
enum BoardImportFile {
    static func read(_ url: URL) throws -> BoardSnapshot {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try BoardSnapshot.decoding(try Data(contentsOf: url))
    }
}

/// Something the user has to be told after an import, an export or a restore.
struct SettingsNotice: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var message: String
}

extension SettingsNotice {
    /// What the import did, spelled out. An import that changed nothing says so
    /// rather than closing silently, which is indistinguishable from a bug.
    static func summarising(_ summary: BoardImportSummary) -> SettingsNotice {
        guard summary.changedAnything else {
            return SettingsNotice(
                title: String(localized: "Nothing to import.",
                              comment: "Alert title when an imported file held nothing new"),
                message: String(localized: "Everything in that file is already on this board.",
                                comment: "Alert body when an imported file held nothing new")
            )
        }
        var parts: [String] = []
        if summary.boardsAdded > 0 {
            parts.append(String(localized: "\(summary.boardsAdded) boards added",
                                comment: "Import summary line"))
        }
        if summary.columnsAdded > 0 {
            parts.append(String(localized: "\(summary.columnsAdded) columns added",
                                comment: "Import summary line"))
        }
        if summary.tasksAdded > 0 {
            parts.append(String(localized: "\(summary.tasksAdded) tasks added",
                                comment: "Import summary line"))
        }
        if summary.tasksCopied > 0 {
            parts.append(String(localized: "\(summary.tasksCopied) tasks kept alongside ones already here",
                                comment: "Import summary line for id collisions"))
        }
        if summary.labelsAdded > 0 {
            parts.append(String(localized: "\(summary.labelsAdded) labels added",
                                comment: "Import summary line"))
        }
        if summary.tasksUnchanged > 0 {
            parts.append(String(localized: "\(summary.tasksUnchanged) tasks already here, unchanged",
                                comment: "Import summary line"))
        }
        return SettingsNotice(
            title: String(localized: "Board imported.", comment: "Alert title after a successful import"),
            message: parts.joined(separator: "\n") + "\n\n" + String(
                localized: "⌘Z takes the whole import back.",
                comment: "Alert footer reminding the user an import is undoable"
            )
        )
    }

    /// Reads a chosen file and merges it, reporting either way.
    ///
    /// One function because three doors do this — the import panel, a file
    /// opened from the Finder, and the same from Files — and a door that
    /// reported nothing would be indistinguishable from a broken one.
    @MainActor static func importing(_ url: URL, into store: BoardStore) -> SettingsNotice {
        do {
            return .summarising(store.importBoard(try BoardImportFile.read(url)))
        } catch {
            return .importFailed(error)
        }
    }

    /// Why a file could not be imported, and the sentence that matters more
    /// than the reason: nothing was touched.
    static func importFailed(_ error: Error) -> SettingsNotice {
        SettingsNotice(
            title: String(localized: "That file could not be imported.",
                          comment: "Alert title when an imported file could not be read"),
            message: [error.localizedDescription,
                      String(localized: "Your board has not been changed.",
                             comment: "Reassurance after a failed import")]
                .joined(separator: "\n\n")
        )
    }
}

/// The three file panels, kept off `SettingsView.body` because each of them
/// wants a document built at presentation time and the three together are
/// longer than the surface they hang on.
///
/// Attached by whichever surface *raised* a panel rather than once at the root:
/// on iOS the settings sheet is already presented over the root, and a
/// `fileImporter` on the view underneath it has nowhere to appear. macOS
/// attaches a second copy in `MacRootView` for File ▸ Import… / Export…, bound
/// to the store's flags instead of the pane's — the menu bar belongs to the
/// window, and its save panel should sheet onto the window.
struct BoardTransfer: ViewModifier {
    @Binding var isExportingBoard: Bool
    /// Markdown is offered by the settings pane only, so the menu's copy leaves
    /// it alone.
    var isExportingMarkdown: Binding<Bool> = .constant(false)
    @Binding var isImporting: Bool

    let snapshot: BoardSnapshot
    let today: CalendarDay
    let onImport: (URL) -> Void
    let onFailure: (String) -> Void

    func body(content: Content) -> some View {
        content
            .fileExporter(
                isPresented: $isExportingBoard,
                document: BoardTransferDocument(snapshot),
                contentType: .simpleKanbanBoard,
                defaultFilename: BoardTransferDocument.filename(on: today)
            ) { report($0) }
            .fileExporter(
                isPresented: isExportingMarkdown,
                document: BoardMarkdownDocument(BoardMarkdown.render(snapshot, today: today)),
                contentType: .markdown,
                defaultFilename: BoardTransferDocument.filename(on: today)
            ) { report($0) }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.simpleKanbanBoard, .json]
            ) { result in
                switch result {
                case .success(let url): onImport(url)
                case .failure(let error): onFailure(error.localizedDescription)
                }
            }
    }

    /// A cancelled panel is not a failure; anything else is, and has to say so.
    private func report(_ result: Result<URL, Error>) {
        if case .failure(let error) = result { onFailure(error.localizedDescription) }
    }
}
