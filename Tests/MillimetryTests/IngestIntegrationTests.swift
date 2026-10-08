import Foundation
import Testing
@testable import Millimetry

/// Sends real batches to a running Millimetry ingest server. Runs only when MILLIMETRY_INGEST_URL
/// and MILLIMETRY_APP_KEY are set, for example:
///
///     MILLIMETRY_INGEST_URL=http://127.0.0.1:8080 MILLIMETRY_APP_KEY=ak_… swift test
struct IngestIntegrationTests {
    static let ingestURL = ProcessInfo.processInfo.environment["MILLIMETRY_INGEST_URL"].flatMap(URL.init(string:))
    static let appKey = ProcessInfo.processInfo.environment["MILLIMETRY_APP_KEY"]

    @Test(.enabled(if: ingestURL != nil && appKey != nil, "set MILLIMETRY_INGEST_URL and MILLIMETRY_APP_KEY"))
    func theRealServerAcceptsTheSDKsBatches() async throws {
        let host = try #require(Self.ingestURL)
        let key = try #require(Self.appKey)
        let recorder = RecordingTransport(URLSessionTransport())
        var configuration = Configuration(appKey: key, host: host, options: Options(trackAppOpen: false, isDebug: true))
        configuration.limits.flushThreshold = 1_000
        let clock = SystemClock()
        let engine = try await Engine(configuration: configuration, dependencies: EngineDependencies(
            clock: clock,
            transport: recorder,
            backgroundTasks: RecordingBackgroundTasks(),
            queueDirectory: temporaryQueueDirectory(),
            systemInfo: { testSystem },
            jitter: { 0.5 }
        ))
        for index in 0..<120 {
            await engine.track("integration", ["index": .int(index), "screen": "home", "ok": true], at: clock.now())
        }
        await engine.flush()

        let responses = await recorder.responses
        #expect(responses.count == 2, "120 events are two batches")
        for response in responses {
            #expect(response.status == 200)
            let body = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
            #expect(body["dropped"] as? Int == 0)
        }
        let accepted = try responses.map { try #require((try JSONSerialization.jsonObject(with: $0.body) as? [String: Any])?["accepted"] as? Int) }
        #expect(accepted.reduce(0, +) == 120)
        #expect(await engine.queuedCount == 0)

        // A retry of a delivered batch is answered from the server's dedup record, not stored again.
        let replay = try #require(await recorder.requests.first)
        let again = try await URLSessionTransport().send(replay)
        #expect(again.status == 200)
        let replayed = try #require(try JSONSerialization.jsonObject(with: again.body) as? [String: Any])
        #expect(replayed["accepted"] as? Int == accepted.first)
    }
}

/// Passes requests to a real transport and keeps what went out and came back.
actor RecordingTransport: HTTPTransport {
    private let inner: any HTTPTransport
    private(set) var requests: [URLRequest] = []
    private(set) var responses: [HTTPResponse] = []

    init(_ inner: any HTTPTransport) {
        self.inner = inner
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        let response = try await inner.send(request)
        responses.append(response)
        return response
    }
}
