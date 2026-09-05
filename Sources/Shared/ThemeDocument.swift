import SwiftUI
import UniformTypeIdentifiers

/// A theme as a file, for `.fileExporter` and `.fileImporter`.
///
/// **Plain `.json`, and no type of its own.** A board is a document this app
/// owns and declares; a theme is a paragraph of settings somebody should be able
/// to paste into a message, put in a gist, or open in a text editor and change
/// one hex in. Giving it a bespoke extension would buy an icon and cost all of
/// that.
///
/// Written pretty-printed with sorted keys for the same reason — the file is
/// meant to be read. It is about sixty lines.
struct ThemeDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    /// An array even when there is one, so that exporting a single theme and
    /// exporting a whole library are one format rather than two.
    var themes: [Theme]

    init(_ themes: [Theme]) {
        self.themes = themes
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw ThemeFileError.unreadable
        }
        themes = try Self.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try encoded())
    }

    // MARK: The format

    private struct Envelope: Codable {
        var format: String
        var version: Int
        var themes: [Theme]

        static let marker = "com.n14395.Cardstock.theme"
        static let currentVersion = 1
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(
            Envelope(format: Envelope.marker, version: Envelope.currentVersion, themes: themes)
        )
    }

    /// **Three shapes read, one written.** The envelope is what this app writes.
    /// A bare array and a bare object are what somebody who wrote a theme by
    /// hand — or pulled one out of a longer file — is likely to hand it, and
    /// refusing those would be pedantry: the theme is all the way there in
    /// either case.
    static func decode(_ data: Data) throws -> [Theme] {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            guard !envelope.themes.isEmpty else { throw ThemeFileError.empty }
            return envelope.themes
        }
        if let list = try? decoder.decode([Theme].self, from: data) {
            guard !list.isEmpty else { throw ThemeFileError.empty }
            return list
        }
        do {
            return [try decoder.decode(Theme.self, from: data)]
        } catch let error as DecodingError {
            throw ThemeFileError.malformed(Self.explain(error))
        }
    }

    /// The complaint a person can act on: which field, and what was wrong with
    /// it. `DecodingError`'s own description names a Swift type and a coding
    /// path in the same breath, and neither means anything to somebody editing
    /// a hex by hand.
    private static func explain(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: " → ")
        }
        switch error {
        case .keyNotFound(let key, let context):
            let inside = path(context)
            return inside.isEmpty
                ? String(localized: "“\(key.stringValue)” is missing.",
                         comment: "Theme import error: a required field is absent")
                : String(localized: "“\(key.stringValue)” is missing from \(inside).",
                         comment: "Theme import error: a required field is absent from a section")
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return String(localized: "\(path(context)) is not the right kind of value.",
                          comment: "Theme import error: a field holds the wrong kind of value")
        case .dataCorrupted(let context):
            let inside = path(context)
            return inside.isEmpty
                ? context.debugDescription
                : String(localized: "\(inside): \(context.debugDescription)",
                         comment: "Theme import error: a field's value could not be read")
        @unknown default:
            return String(localized: "It is not a theme file.",
                          comment: "Theme import error: the file is not a theme")
        }
    }

    /// `Ember.json`. Named after the theme rather than dated, unlike a board
    /// export: a theme is a *thing* and two exports of one are the same file,
    /// where two exports of a board are two moments.
    static func filename(for theme: Theme) -> String { theme.name }
}

enum ThemeFileError: LocalizedError, Equatable {
    case unreadable
    case empty
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "That file could not be opened.",
                   comment: "Theme import error: the file could not be read at all")
        case .empty:
            String(localized: "That file has no themes in it.",
                   comment: "Theme import error: valid JSON with an empty theme list")
        case .malformed(let detail):
            detail
        }
    }
}
