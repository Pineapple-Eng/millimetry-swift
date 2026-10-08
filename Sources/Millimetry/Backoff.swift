import Foundation

/// When the next upload may be tried: after a network error or 5xx, an exponential
/// delay with jitter, 2 s doubling to a 5-minute cap; after a 429, the server's `Retry-After`.
struct Backoff: Sendable {
    let base: TimeInterval
    let cap: TimeInterval
    private(set) var failures = 0
    private(set) var nextAttemptAt: Date?

    init(base: TimeInterval, cap: TimeInterval) {
        self.base = base
        self.cap = cap
    }

    /// The delay for the `failures`-th consecutive failure, before jitter.
    func delay(afterFailures failures: Int) -> TimeInterval {
        let exponent = Double(max(0, failures - 1))
        return min(cap, base * pow(2, exponent))
    }

    /// Records a failure at `now`. `jitter` is a number in 0...1; the delay is scaled into
    /// 80–120 % of the nominal value, then capped.
    mutating func recordFailure(at now: Date, jitter: Double) {
        failures += 1
        let nominal = delay(afterFailures: failures)
        let scaled = min(cap, nominal * (0.8 + 0.4 * min(1, max(0, jitter))))
        nextAttemptAt = now.addingTimeInterval(scaled)
    }

    /// Records a 429: wait exactly as long as the server asked (at least one second).
    mutating func recordRetryAfter(_ seconds: TimeInterval, at now: Date) {
        nextAttemptAt = now.addingTimeInterval(max(1, seconds))
    }

    mutating func recordSuccess() {
        failures = 0
        nextAttemptAt = nil
    }

    func mayAttempt(at now: Date) -> Bool {
        guard let nextAttemptAt else { return true }
        return now >= nextAttemptAt
    }
}
