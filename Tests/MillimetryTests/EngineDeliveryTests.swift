import Foundation
import Testing
@testable import Millimetry

/// Delivery across relaunches, outages and oversize batches.
struct EngineDeliveryTests {
    @Test func eventsSurviveKillingAndRelaunchingTheApp() async throws {
        let directory = temporaryQueueDirectory()
        let first = try await EngineHarness.make(directory: directory)
        await first.engine.track("a", [:], at: first.clock.now())
        await first.engine.track("b", ["n": 1], at: first.clock.now())
        await first.engine.track("c", [:], at: first.clock.now())
        // The process dies here: no flush, no background, nothing but what is on disk.

        let relaunched = try await EngineHarness.make(directory: directory)
        #expect(await relaunched.engine.queuedCount == 3)
        await relaunched.engine.flush()
        let received = await relaunched.server.received
        #expect(received.flatMap(\.eventNames) == ["a", "b", "c"])
        #expect(await relaunched.engine.queuedCount == 0)
    }

    @Test func aFormedBatchKeepsItsIdAcrossARelaunch() async throws {
        let directory = temporaryQueueDirectory()
        let failing = MockServer { _ in .status(503) }
        let first = try await EngineHarness.make(directory: directory, server: failing)
        await first.engine.track("a", [:], at: first.clock.now())
        await first.engine.flush()
        let firstID = try #require(await failing.received.first?.batchID)

        let relaunched = try await EngineHarness.make(directory: directory)
        await relaunched.engine.flush()
        let retried = try #require(await relaunched.server.received.first)
        #expect(retried.batchID == firstID, "the server deduplicates on this id")
        #expect(retried.eventNames == ["a"])
    }

    @Test func anHourOfflineThenOnlineDeliversEveryEventOnce() async throws {
        let online = OnlineSwitch()
        let server = MockServer { _ in online.isOnline ? .status(200) : .offline }
        let harness = try await EngineHarness.make(server: server)
        let engine = harness.engine

        // An hour offline: an event every 20 s, the timer ticking every 30 s, every attempt failing.
        var tracked: [String] = []
        for second in stride(from: 0, to: 3_600, by: 10) {
            if second % 20 == 0 {
                let name = "e\(second)"
                await engine.track(name, [:], at: harness.clock.now())
                tracked.append(name)
            }
            if second % 30 == 0 { await engine.tick() }
            harness.clock.advance(by: 10)
        }
        #expect(await server.received.isEmpty == false, "it kept trying while offline")
        #expect(await engine.queuedCount == tracked.count)

        online.isOnline = true
        harness.clock.advance(by: 301)   // past the longest backoff
        await engine.tick()
        await engine.waitForIdle()

        // What the server stored, keyed by batch id: retries of one batch carry the same id and
        // the same events, so the server deduplicates them; no event may sit in two batches.
        var stored: [String: [String]] = [:]
        for attempt in await server.received {
            stored[attempt.batchID] = attempt.eventNames
        }
        let deliveredNames = stored.values.flatMap { $0 }
        #expect(deliveredNames.sorted() == tracked.sorted(), "every event, exactly once across batch ids")
        #expect(Set(deliveredNames).count == deliveredNames.count)
        #expect(await engine.queuedCount == 0)
    }

    @Test func retriesReuseTheBatchIdSoTheServerCanDeduplicate() async throws {
        let replies = ReplyScript([.status(503), .offline, .status(200)])
        let server = MockServer { _ in replies.next() }
        let harness = try await EngineHarness.make(server: server)
        await harness.engine.track("a", [:], at: harness.clock.now())
        for _ in 0..<3 {
            await harness.engine.flush()
            harness.clock.advance(by: 301)
        }
        let ids = await server.received.map(\.batchID)
        #expect(ids.count == 3)
        #expect(Set(ids).count == 1)
    }

    @Test func aThreeHundredKilobyteBatchIsSplitOn413AndDelivered() async throws {
        // A server that refuses bodies over 150 KB, and a batch limit raised so a 300 KB batch forms.
        let server = MockServer { batch in batch.uncompressedSize > 150 * 1_024 ? .status(413) : .status(200) }
        var limits = Limits()
        limits.maxBatchBytes = 400 * 1_024
        let harness = try await EngineHarness.make(server: server, limits: limits)
        for index in 0..<30 {
            await harness.engine.track("big\(index)", ["blob": .string(String(repeating: "x", count: 10_000))], at: harness.clock.now())
        }
        await harness.engine.flush()

        let received = await server.received
        let first = try #require(received.first)
        #expect(first.uncompressedSize > 290 * 1_024, "the first attempt was the whole ~300 KB batch")
        #expect(received.filter { $0.uncompressedSize > 150 * 1_024 }.count >= 1)
        let deliveredNames = received.filter { $0.uncompressedSize <= 150 * 1_024 }.flatMap(\.eventNames)
        #expect(deliveredNames == (0..<30).map { "big\($0)" }, "every event, once, in order")
        #expect(await harness.engine.queuedCount == 0)
    }

    @Test func aSingleEventTooLargeForTheServerIsDropped() async throws {
        let server = MockServer { _ in .status(413) }
        let harness = try await EngineHarness.make(server: server)
        await harness.engine.track("huge", [:], at: harness.clock.now())
        await harness.engine.flush()
        #expect(await server.received.count == 1)
        #expect(await harness.engine.queuedCount == 0)
    }

    @Test(arguments: [400, 401, 403, 422])
    func aClientErrorDeletesTheBatch(status: Int) async throws {
        let server = MockServer { _ in .status(status) }
        let harness = try await EngineHarness.make(server: server)
        await harness.engine.track("a", [:], at: harness.clock.now())
        await harness.engine.flush()
        #expect(await harness.engine.queuedCount == 0)
        #expect(await harness.engine.nextAttemptAt == nil, "a 4xx is not retried")
    }

    @Test func overQuotaDeletesTheBatchWithoutBackingOff() async throws {
        let server = MockServer { _ in .status(200, body: #"{"accepted":0,"dropped":1,"reason":"over_quota"}"#) }
        let harness = try await EngineHarness.make(server: server)
        await harness.engine.track("a", [:], at: harness.clock.now())
        await harness.engine.flush()
        #expect(await harness.engine.queuedCount == 0)
        #expect(await harness.engine.nextAttemptAt == nil)
    }

    @Test func aRateLimitKeepsTheBatchUntilRetryAfter() async throws {
        let replies = ReplyScript([.status(429, headers: ["retry-after": "20"]), .status(200)])
        let server = MockServer { _ in replies.next() }
        let harness = try await EngineHarness.make(server: server)
        await harness.engine.track("a", [:], at: harness.clock.now())
        await harness.engine.flush()
        #expect(await harness.engine.queuedCount == 1)
        #expect(await harness.engine.nextAttemptAt == harness.clock.now() + 20)

        harness.clock.advance(by: 19)
        await harness.engine.tick()
        #expect(await server.received.count == 1, "nothing is sent before Retry-After")

        harness.clock.advance(by: 1)
        await harness.engine.tick()
        #expect(await server.received.count == 2)
        #expect(await harness.engine.queuedCount == 0)
    }

    @Test func serverErrorsBackOffExponentially() async throws {
        let server = MockServer { _ in .status(503) }
        let harness = try await EngineHarness.make(server: server)
        await harness.engine.track("a", [:], at: harness.clock.now())
        var delays: [TimeInterval] = []
        for _ in 0..<5 {
            await harness.engine.flush()
            let next = try #require(await harness.engine.nextAttemptAt)
            delays.append(next.timeIntervalSince(harness.clock.now()))
            harness.clock.advance(by: next.timeIntervalSince(harness.clock.now()))
        }
        // jitter 0.5 → exactly the nominal delay
        #expect(delays == [2, 4, 8, 16, 32])
        #expect(await harness.engine.nextWakeDelay() <= 32)
    }
}

/// A flag the test flips while the mock server reads it. Thread-safe through its lock.
final class OnlineSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var online = false

    var isOnline: Bool {
        get { lock.lock(); defer { lock.unlock() }; return online }
        set { lock.lock(); online = newValue; lock.unlock() }
    }
}

/// Hands out scripted replies in order, then 200 forever. Thread-safe through its lock.
final class ReplyScript: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [MockServer.Reply]

    init(_ replies: [MockServer.Reply]) {
        self.replies = replies
    }

    func next() -> MockServer.Reply {
        lock.lock()
        defer { lock.unlock() }
        return replies.isEmpty ? .status(200) : replies.removeFirst()
    }
}
