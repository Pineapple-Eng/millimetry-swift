import Foundation
import Testing
@testable import Millimetry

/// Flush triggers, the background flush, sessions, opt-out and the request format.
struct EngineBehaviorTests {
    @Test func theBackgroundFlushRunsInsideABackgroundTask() async throws {
        let background = RecordingBackgroundTasksProbe()
        let server = MockServer()
        let harness = try await EngineHarness.make(server: server)
        await server.setOnRequest { await background.sawRequest(during: harness.background) }
        await harness.engine.track("a", [:], at: harness.clock.now())

        await harness.engine.didEnterBackground()

        #expect(await harness.background.started == 1)
        #expect(await harness.background.finished == 1)
        #expect(await harness.background.isActive == false, "the assertion was ended")
        #expect(await background.requestsInsideAssertion == 1, "the upload happened while the assertion was held")
        #expect(await harness.engine.queuedCount == 0)
    }

    @Test func fiftyQueuedEventsTriggerAFlushWithoutTheTimer() async throws {
        let harness = try await EngineHarness.make()
        for index in 0..<49 { await harness.engine.track("e\(index)", [:], at: harness.clock.now()) }
        await harness.engine.waitForIdle()
        #expect(await harness.server.received.isEmpty)
        await harness.engine.track("e49", [:], at: harness.clock.now())
        await harness.engine.waitForIdle()
        #expect(await harness.server.received.flatMap(\.eventNames).count == 50)
    }

    @Test func theTimerFlushesOnlyInTheForeground() async throws {
        let harness = try await EngineHarness.make()
        await harness.engine.track("a", [:], at: harness.clock.now())
        // Leaving for the background flushes; the next event waits there until the app is back.
        await harness.engine.didEnterBackground()
        await harness.engine.track("b", [:], at: harness.clock.now())
        await harness.engine.tick()
        #expect(await harness.server.received.flatMap(\.eventNames) == ["a"])
        await harness.engine.willEnterForeground()
        await harness.engine.tick()
        #expect(await harness.server.received.flatMap(\.eventNames) == ["a", "b"])
    }

    @Test func theFlushIntervalIsThirtySecondsInReleaseAndTwoInDebug() {
        let host = URL(string: "https://e.example.test")!
        #expect(Configuration(appKey: "k", host: host, options: Options(isDebug: false)).flushInterval == 30)
        #expect(Configuration(appKey: "k", host: host, options: Options(isDebug: true)).flushInterval == 2)
        #expect(Configuration(appKey: "k", host: host, options: Options(flushInterval: 10, isDebug: false)).flushInterval == 10)
    }

    @Test func appOpenIsSentAtLaunchAndOnReturningToTheForeground() async throws {
        let harness = try await EngineHarness.make(trackAppOpen: true)
        await harness.engine.start()
        await harness.engine.didEnterBackground()
        await harness.engine.willEnterForeground()
        await harness.engine.flush()
        #expect(await harness.server.received.flatMap(\.eventNames) == ["app_open", "app_open"])
    }

    @Test func eventsThirtyMinutesApartBelongToDifferentSessions() async throws {
        let harness = try await EngineHarness.make()
        await harness.engine.track("a", [:], at: harness.clock.now())
        await harness.engine.track("b", [:], at: harness.clock.now() + 60)
        await harness.engine.track("c", [:], at: harness.clock.now() + 60 + 1_800)
        await harness.engine.flush()
        let sessions = await harness.server.received.flatMap(\.events).compactMap { $0["session_id"] as? String }
        #expect(sessions.count == 3)
        #expect(sessions[0] == sessions[1])
        #expect(sessions[1] != sessions[2])
    }

    @Test func aLongStayInTheBackgroundStartsANewSession() async throws {
        let harness = try await EngineHarness.make()
        await harness.engine.track("before", [:], at: harness.clock.now())
        let first = try #require(await harness.engine.currentSessionID)
        await harness.engine.didEnterBackground()
        harness.clock.advance(by: 1_800)
        await harness.engine.willEnterForeground()
        await harness.engine.track("after", [:], at: harness.clock.now())
        #expect(await harness.engine.currentSessionID != first)
    }

    @Test func turningTrackingOffDeletesTheQueueAndIgnoresEvents() async throws {
        let harness = try await EngineHarness.make()
        await harness.engine.track("a", [:], at: harness.clock.now())
        await harness.engine.setEnabled(false)
        #expect(await harness.engine.queuedCount == 0)
        await harness.engine.track("b", [:], at: harness.clock.now())
        await harness.engine.flush()
        #expect(await harness.server.received.isEmpty)
        await harness.engine.setEnabled(true)
        await harness.engine.track("c", [:], at: harness.clock.now())
        await harness.engine.flush()
        #expect(await harness.server.received.flatMap(\.eventNames) == ["c"])
    }

    @Test func anOSUpdateWhileAwaySplitsTheBatch() async throws {
        let versions = VersionBox("26.0.1")
        let harness = try await EngineHarness.make(systemProvider: {
            var system = testSystem
            system.osVersion = versions.value
            return system
        })
        await harness.engine.track("old", [:], at: harness.clock.now())
        await harness.engine.didEnterBackground()
        await harness.engine.track("old2", [:], at: harness.clock.now())
        versions.value = "26.1"
        await harness.engine.willEnterForeground()
        await harness.engine.track("new", [:], at: harness.clock.now())
        await harness.engine.flush()
        let batches = await harness.server.received
        #expect(batches.map { $0.system["os_version"] as? String } == ["26.0.1", "26.0.1", "26.1"])
        #expect(batches.map(\.eventNames) == [["old"], ["old2"], ["new"]])
    }

    @Test func invalidNamesAreDroppedOnTheDevice() async throws {
        let harness = try await EngineHarness.make()
        await harness.engine.track("", [:], at: harness.clock.now())
        await harness.engine.track("$reserved", [:], at: harness.clock.now())
        await harness.engine.track(String(repeating: "n", count: 65), [:], at: harness.clock.now())
        await harness.engine.track("ok", [:], at: harness.clock.now())
        #expect(await harness.engine.queuedCount == 1)
    }

    @Test func requestsFollowTheWireFormat() async throws {
        let harness = try await EngineHarness.make()
        await harness.engine.track("purchase", ["price": 4.99, "plan": "pro", "trial": false, "items": 3], at: harness.clock.now())
        await harness.engine.flush()
        let request = try #require(await harness.server.received.first)
        #expect(request.appKey == "ak_0123456789abcdefghijklmnopqrstuv")
        #expect(request.contentType == "application/json")
        #expect(request.contentEncoding == "gzip")
        #expect(UUID(uuidString: request.batchID) != nil)

        let body = request.body
        #expect(body["sdk"] as? String == DeviceInfo.sdkVersion)
        let system = try #require(body["system"] as? [String: Any])
        #expect(Set(system.keys) == ["os_name", "os_version", "device_model", "locale", "app_version", "app_build", "is_debug"])
        let event = try #require(request.events.first)
        #expect(Set(event.keys) == ["name", "ts", "session_id", "props"])
        #expect(event["name"] as? String == "purchase")
        let ts = try #require(event["ts"] as? String)
        #expect(ts.hasSuffix("Z"))
        #expect(ts.contains("."), "milliseconds are included")
        let props = try #require(event["props"] as? [String: Any])
        #expect(props["price"] as? Double == 4.99)
        #expect(props["plan"] as? String == "pro")
        #expect(props["trial"] as? Bool == false)
        #expect(props["items"] as? Int == 3)
    }
}

/// Counts requests that arrive while the background assertion is held.
actor RecordingBackgroundTasksProbe {
    private(set) var requestsInsideAssertion = 0

    func sawRequest(during tasks: RecordingBackgroundTasks) async {
        if await tasks.isActive { requestsInsideAssertion += 1 }
    }
}

/// A value the test changes while the engine reads it. Thread-safe through its lock.
final class VersionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String

    init(_ value: String) { current = value }

    var value: String {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }
}
