import Foundation

/// The `/v1/app/batch` request body: the system once, then the events.
struct WirePayload: Encodable {
    struct Event: Encodable {
        var name: String
        var ts: String
        var sessionID: UUID
        var props: [String: PropValue]

        enum CodingKeys: String, CodingKey {
            case name
            case ts
            case sessionID = "session_id"
            case props
        }
    }

    var sdk: String
    var system: SystemInfo
    var events: [Event]

    init(batch: StoredBatch, sdk: String = DeviceInfo.sdkVersion) {
        self.sdk = sdk
        self.system = batch.system
        self.events = batch.events.map { event in
            Event(
                name: event.name,
                ts: WirePayload.timestamp(milliseconds: event.timestamp),
                sessionID: event.sessionID,
                props: event.properties
            )
        }
    }

    /// ISO 8601 in UTC with milliseconds, e.g. `2026-10-05T17:03:12.345Z`.
    static func timestamp(milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        return Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// The encoded size of one event, used to keep a batch under the byte limit.
    static func encodedSize(of event: QueuedEvent) -> Int {
        let wire = Event(name: event.name, ts: timestamp(milliseconds: event.timestamp), sessionID: event.sessionID, props: event.properties)
        return (try? JSONEncoder().encode(wire).count) ?? 0
    }
}
