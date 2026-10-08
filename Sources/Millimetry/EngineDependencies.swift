import Foundation

/// Everything the engine touches outside itself, so tests can replace each piece.
struct EngineDependencies: Sendable {
    var clock: any SDKClock
    var transport: any HTTPTransport
    var backgroundTasks: any BackgroundTaskRunner
    /// Where the queue lives.
    var queueDirectory: URL
    /// The current device and app description; read when the engine starts and whenever the app
    /// returns to the foreground, since an OS update can happen in between.
    var systemInfo: @Sendable () async -> SystemInfo
    /// A number in 0...1 for backoff jitter.
    var jitter: @Sendable () -> Double

    static func live(configuration: Configuration) throws -> EngineDependencies {
        let isDebug = configuration.isDebug
        return EngineDependencies(
            clock: SystemClock(),
            transport: URLSessionTransport(),
            backgroundTasks: SystemBackgroundTaskRunner(),
            queueDirectory: try DiskQueue.defaultDirectory(),
            systemInfo: { await DeviceInfo.current(isDebug: isDebug) },
            jitter: { Double.random(in: 0...1) }
        )
    }
}
