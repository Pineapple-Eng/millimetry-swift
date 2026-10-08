import Foundation

/// Time, injected so tests can move it by hand instead of sleeping.
protocol SDKClock: Sendable {
    func now() -> Date
    func sleep(seconds: TimeInterval) async throws
}

struct SystemClock: SDKClock {
    func now() -> Date { Date() }

    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}
