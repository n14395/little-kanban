import Foundation

enum Priority: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }
    var displayName: String { rawValue }
}
