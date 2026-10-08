import Foundation

/// The queue, batch, session and retry limits. Tests shrink some of them.
struct Limits: Sendable, Equatable {
    /// Events kept on disk at most; the oldest are dropped beyond this.
    var maxQueuedEvents = 1_000
    /// Events older than this are dropped before sending (the server refuses them anyway).
    var maxEventAge: TimeInterval = 7 * 24 * 60 * 60
    /// Events per request.
    var maxBatchEvents = 100
    /// JSON bytes per request, before compression.
    var maxBatchBytes = 200 * 1_024
    /// Queued events that trigger a flush without waiting for the timer.
    var flushThreshold = 50
    /// A session ends after this long in the background or without events.
    var sessionTimeout: TimeInterval = 30 * 60
    /// The first retry delay after a failure; it doubles up to `backoffCap`.
    var backoffBase: TimeInterval = 2
    var backoffCap: TimeInterval = 5 * 60
}
