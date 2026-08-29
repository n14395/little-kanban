import Foundation

/// Something shared into the app from outside it, waiting to become an Inbox
/// card.
///
/// **Not a `TaskItem`.** The share extension is a separate process that must
/// never open `board.json` or the record store — see ``CaptureInbox`` — so what
/// crosses the App Group fence is the smallest possible description of what the
/// user shared, and the app mints the card from it on the way back in. That also
/// decides what happens when the two sides disagree about a format: a capture
/// the app cannot decode is set aside rather than deleted, because unlike the
/// widgets' digest this is not a cache. It is the only copy of something
/// somebody typed.
struct PendingCapture: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var note: String
    /// When it was shared, not when it is drained. The two can be days apart —
    /// an extension writes while the app is not running — and the order cards
    /// arrive in should be the order they were captured in.
    var createdAt: Date
}

/// What a share sheet's payload becomes.
///
/// A pure function of the two things a share carries, so the rules below are
/// testable without an extension, an `NSItemProvider` or a share sheet — none
/// of which any test in this suite can drive.
enum CaptureDraft {
    /// Longer than this and the title is cut, with the whole of the original
    /// line kept at the top of the note.
    ///
    /// A card's title has no limit in the model and the interface truncates
    /// whatever it is given, so this is not about storage: it is that sharing a
    /// paragraph should produce a card you can read in a column, and losing the
    /// rest of the paragraph to achieve that would be a strange trade. Nothing
    /// is dropped — it moves.
    static let titleLimit = 120

    /// The capture a share becomes.
    ///
    /// - The first non-empty line of the shared text is the title. It is what
    ///   Safari sends as the page's name, and it is what somebody selecting a
    ///   sentence and sharing it means by "this".
    /// - Everything else — the remaining lines, and the URL — is the note, in
    ///   that order.
    /// - With no text at all, a URL names itself: its host without `www.`,
    ///   which is short enough to read in a column and specific enough to
    ///   recognise. The full URL is still in the note.
    ///
    /// An empty result is possible — a share carrying neither — and is the
    /// caller's to refuse. Making a card called nothing out of nothing is not
    /// this function's decision.
    static func from(text: String?, url: URL?, now: Date = .now) -> PendingCapture {
        let lines = (text ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var noteParts: [String] = []
        var title = lines.first ?? url.map(readableName) ?? ""

        if title.count > titleLimit {
            // The cut goes at a word boundary where there is one within reach,
            // so a title does not end mid-word for the sake of four characters.
            let cut = String(title.prefix(titleLimit))
            let trimmed = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
            noteParts.append(title)
            title = trimmed.trimmingCharacters(in: .whitespaces) + "…"
        }

        noteParts.append(contentsOf: lines.dropFirst())
        if let url { noteParts.append(url.absoluteString) }

        return PendingCapture(
            title: title,
            note: noteParts.joined(separator: "\n\n"),
            createdAt: now
        )
    }

    /// A URL as a card title: `www.` dropped because it is four characters of
    /// nothing, and the whole URL when there is no host to name — a `file:` or
    /// a `mailto:` is still better identified by itself than by an empty title.
    static func readableName(of url: URL) -> String {
        guard let host = url.host(), !host.isEmpty else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
