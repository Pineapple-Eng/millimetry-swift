import Foundation
@testable import Millimetry

/// A clock the test moves by hand. Thread-safe through its lock.
final class ManualClock: SDKClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_791_000_000)) {
        current = start
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }

    func sleep(seconds: TimeInterval) async throws {}
}

/// One request as the server would see it: headers and the decoded body.
struct ReceivedBatch: Sendable {
    var batchID: String
    var appKey: String
    var contentType: String
    var contentEncoding: String
    var uncompressedSize: Int
    /// The decompressed JSON body.
    var json: Data

    var body: [String: Any] { (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:] }
    var events: [[String: Any]] { body["events"] as? [[String: Any]] ?? [] }
    var eventNames: [String] { events.compactMap { $0["name"] as? String } }
    var system: [String: Any] { body["system"] as? [String: Any] ?? [:] }
}

/// A scriptable server: each request gets whatever `respond` says, and every request is recorded.
actor MockServer: HTTPTransport {
    enum Reply: Sendable {
        case status(Int, headers: [String: String] = [:], body: String = "{}")
        case offline
    }

    private var respond: @Sendable (ReceivedBatch) -> Reply
    private(set) var received: [ReceivedBatch] = []
    /// Called while a request is being answered (to check the caller's state at that moment).
    private var onRequest: (@Sendable () async -> Void)?

    init(_ respond: @escaping @Sendable (ReceivedBatch) -> Reply = { _ in .status(200) }) {
        self.respond = respond
    }

    func setResponder(_ respond: @escaping @Sendable (ReceivedBatch) -> Reply) {
        self.respond = respond
    }

    func setOnRequest(_ hook: @escaping @Sendable () async -> Void) {
        onRequest = hook
    }

    nonisolated func send(_ request: URLRequest) async throws -> HTTPResponse {
        let batch = try ReceivedBatch(request)
        let reply = await record(batch)
        switch reply {
        case .offline:
            throw URLError(.notConnectedToInternet)
        case .status(let status, let headers, let body):
            return HTTPResponse(status: status, headers: headers, body: Data(body.utf8))
        }
    }

    private func record(_ batch: ReceivedBatch) async -> Reply {
        received.append(batch)
        await onRequest?()
        return respond(batch)
    }

}

extension ReceivedBatch {
    init(_ request: URLRequest) throws {
        guard let gzip = request.httpBody else { throw GunzipForTests.Corrupt() }
        batchID = request.value(forHTTPHeaderField: "X-Batch-Id") ?? ""
        appKey = request.value(forHTTPHeaderField: "X-App-Key") ?? ""
        contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
        contentEncoding = request.value(forHTTPHeaderField: "Content-Encoding") ?? ""
        json = try GunzipForTests.decode(gzip)
        uncompressedSize = json.count
    }
}

/// Reverses ``Gzip/compress(_:)`` for assertions: strips the 10-byte header and 8-byte trailer,
/// inflates the raw DEFLATE stream, and checks the trailer's CRC-32 and length.
enum GunzipForTests {
    struct Corrupt: Error {}

    static func decode(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 0x08 else { throw Corrupt() }
        let deflate = Data(bytes[10..<(bytes.count - 8)])
        let inflated = try (deflate as NSData).decompressed(using: .zlib) as Data
        let trailer = Array(bytes.suffix(8))
        let crc = trailer[0..<4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        let size = trailer[4..<8].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        guard crc == CRC32.checksum(inflated), size == UInt32(truncatingIfNeeded: inflated.count) else { throw Corrupt() }
        return inflated
    }
}

/// Records whether work is running inside a background assertion.
actor RecordingBackgroundTasks: BackgroundTaskRunner {
    private(set) var started = 0
    private(set) var finished = 0
    private(set) var isActive = false

    nonisolated func run(name: String, _ work: @escaping @Sendable () async -> Void) async {
        await begin()
        await work()
        await end()
    }

    private func begin() {
        started += 1
        isActive = true
    }

    private func end() {
        finished += 1
        isActive = false
    }
}

/// A fresh, empty queue directory per test.
func temporaryQueueDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("millimetry-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("queue", isDirectory: true)
}

let testSystem = SystemInfo(
    osName: "iOS", osVersion: "26.0.1", deviceModel: "iPhone17,1", locale: "en-CA",
    appVersion: "1.5.0", appBuild: "42", isDebug: false
)

/// The pieces of an engine under test.
struct EngineHarness {
    let engine: Engine
    let clock: ManualClock
    let server: MockServer
    let background: RecordingBackgroundTasks
    let directory: URL

    static func make(
        directory: URL = temporaryQueueDirectory(),
        clock: ManualClock = ManualClock(),
        server: MockServer = MockServer(),
        trackAppOpen: Bool = false,
        limits: Limits = Limits(),
        system: SystemInfo = testSystem,
        systemProvider: (@Sendable () async -> SystemInfo)? = nil
    ) async throws -> EngineHarness {
        let background = RecordingBackgroundTasks()
        var configuration = Configuration(
            appKey: "ak_0123456789abcdefghijklmnopqrstuv",
            host: URL(string: "https://e.example.test")!,
            options: Options(trackAppOpen: trackAppOpen, isDebug: false),
            limits: limits
        )
        configuration.limits = limits
        let dependencies = EngineDependencies(
            clock: clock,
            transport: server,
            backgroundTasks: background,
            queueDirectory: directory,
            systemInfo: systemProvider ?? { system },
            jitter: { 0.5 }
        )
        let engine = try await Engine(configuration: configuration, dependencies: dependencies)
        return EngineHarness(engine: engine, clock: clock, server: server, background: background, directory: directory)
    }
}
