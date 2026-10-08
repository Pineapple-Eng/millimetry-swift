import Foundation

/// One tracked event as it waits on disk: what the wire needs, plus the batch-forming facts
/// (when it happened, which system it belongs to).
struct QueuedEvent: Sendable, Equatable, Codable {
    var name: String
    /// Unix milliseconds, for the age limit and ordering.
    var timestamp: Int64
    var sessionID: UUID
    var properties: [String: PropValue]
    var system: SystemInfo

    enum CodingKeys: String, CodingKey {
        case name = "n"
        case timestamp = "t"
        case sessionID = "s"
        case properties = "p"
        case system = "y"
    }

    var date: Date { Date(timeIntervalSince1970: Double(timestamp) / 1_000) }
}
