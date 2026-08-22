import Foundation

/// How urgent a task is.
///
/// The raw values are tokens, not words. They are what the board file carries,
/// and a file whose stored values *are* its UI text cannot be translated
/// without rewriting everybody's boards — which is what the spellings below
/// replaced in snapshot v6. `displayName` is the only thing here that speaks a
/// language.
enum Priority: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case high, medium, low

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .high: String(localized: "High", comment: "Task priority")
        case .medium: String(localized: "Medium", comment: "Task priority")
        case .low: String(localized: "Low", comment: "Task priority")
        }
    }

    /// How files up to v5 spelled these — the display strings of the day.
    /// Written out rather than derived with `capitalized`, so the mapping stays
    /// exact in a locale where case folding is not the identity it looks like.
    private static let storedBeforeV6: [String: Priority] = [
        "High": .high, "Medium": .medium, "Low": .low,
    ]

    /// A priority as any shipped board file spells it: the v6 token, or the
    /// pre-v6 display string. `nil` for neither.
    ///
    /// This is where the v5 → v6 migration actually happens. The step itself
    /// has nothing else to do — the shape either side of it is identical — but
    /// the version still has to be bumped, because a v5 build handed a file of
    /// tokens would decode none of them.
    init?(stored raw: String) {
        guard let value = Priority(rawValue: raw) ?? Self.storedBeforeV6[raw] else { return nil }
        self = value
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = Priority(stored: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\(raw) is not a priority this build knows"
            )
        }
        self = value
    }
}
