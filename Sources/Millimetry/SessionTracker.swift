import Foundation

/// The session: a UUIDv7 made in memory on the first event after launch, replaced
/// after 30 minutes in the background or 30 minutes without events. It is never written to disk
/// and never survives a relaunch.
struct SessionTracker: Sendable {
    let timeout: TimeInterval
    private(set) var current: UUID?
    private var lastEventAt: Date?
    private var backgroundedAt: Date?

    init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    /// The session an event at `now` belongs to, starting a new one when the old one has ended.
    mutating func sessionID(at now: Date) -> UUID {
        if let current, let lastEventAt, now.timeIntervalSince(lastEventAt) < timeout {
            self.lastEventAt = now
            return current
        }
        let fresh = UUIDv7.make(at: now)
        current = fresh
        lastEventAt = now
        return fresh
    }

    mutating func enterBackground(at now: Date) {
        backgroundedAt = now
    }

    /// Ends the session if the app was in the background for the whole timeout.
    mutating func enterForeground(at now: Date) {
        if let backgroundedAt, now.timeIntervalSince(backgroundedAt) >= timeout {
            current = nil
            lastEventAt = nil
        }
        backgroundedAt = nil
    }
}
