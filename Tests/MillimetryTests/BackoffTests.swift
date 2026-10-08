import Foundation
import Testing
@testable import Millimetry

struct BackoffTests {
    let now = Date(timeIntervalSince1970: 1_791_000_000)

    @Test func theDelayDoublesFromTwoSecondsToAFiveMinuteCap() {
        let backoff = Backoff(base: 2, cap: 300)
        let delays = (1...10).map { backoff.delay(afterFailures: $0) }
        #expect(delays == [2, 4, 8, 16, 32, 64, 128, 256, 300, 300])
    }

    @Test(arguments: [(0.0, 1.6), (0.5, 2.0), (1.0, 2.4)])
    func jitterScalesTheDelayBetweenEightyAndOneHundredTwentyPercent(jitter: Double, expected: TimeInterval) throws {
        var backoff = Backoff(base: 2, cap: 300)
        backoff.recordFailure(at: now, jitter: jitter)
        let next = try #require(backoff.nextAttemptAt)
        #expect(abs(next.timeIntervalSince(now) - expected) < 0.000_1)
    }

    @Test func jitterNeverPushesPastTheCap() throws {
        var backoff = Backoff(base: 2, cap: 300)
        for _ in 0..<12 { backoff.recordFailure(at: now, jitter: 1) }
        let next = try #require(backoff.nextAttemptAt)
        #expect(next.timeIntervalSince(now) <= 300)
    }

    @Test func attemptsWaitForTheDelayAndSuccessResets() {
        var backoff = Backoff(base: 2, cap: 300)
        #expect(backoff.mayAttempt(at: now))
        backoff.recordFailure(at: now, jitter: 0.5)
        #expect(backoff.mayAttempt(at: now + 1) == false)
        #expect(backoff.mayAttempt(at: now + 2))
        backoff.recordSuccess()
        #expect(backoff.failures == 0)
        #expect(backoff.nextAttemptAt == nil)
    }

    @Test func retryAfterIsHonouredExactly() throws {
        var backoff = Backoff(base: 2, cap: 300)
        backoff.recordRetryAfter(42, at: now)
        #expect(try #require(backoff.nextAttemptAt) == now + 42)
        backoff.recordRetryAfter(0, at: now)
        #expect(try #require(backoff.nextAttemptAt) == now + 1, "never sooner than a second")
    }
}
