import Foundation

/// A batch formed from queued events and saved before its first upload, so a retry, even after
/// the app was killed and relaunched, reuses the same `batchID`, so the server stores it once.
struct StoredBatch: Sendable, Equatable, Codable {
    var batchID: UUID
    var system: SystemInfo
    var events: [QueuedEvent]
    /// The sealing file the batch was cut from; crash recovery uses it to discard a half-written
    /// set of batches and cut them again.
    var source: String

    enum CodingKeys: String, CodingKey {
        case batchID = "id"
        case system
        case events
        case source
    }
}
