import Foundation

/// The process-wide home of the engine behind the static ``Millimetry`` API. Commands arrive on
/// one ordered stream, so `track` stays synchronous and cheap from any thread while events keep
/// the order they were tracked in. Before `configure` arrives, events wait in memory (at most a
/// queue's worth).
final class Runtime: Sendable {
    static let shared = Runtime()

    private let continuation: AsyncStream<Command>.Continuation

    private init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Command.self)
        self.continuation = continuation
        // A plain task: this initializer is nonisolated, so nothing is inherited that needs shedding.
        Task(priority: .utility) {
            await Runtime.consume(stream)
        }
    }

    func send(_ command: Command) {
        continuation.yield(command)
    }

    private static func consume(_ commands: AsyncStream<Command>) async {
        var engine: Engine?
        var early: [(String, [String: PropValue], Date)] = []
        var enabled = true
        // Kept alive for the life of the process.
        var observers: [any NSObjectProtocol] = []

        for await command in commands {
            switch command {
            case .configure(let configuration):
                guard engine == nil else { continue }
                do {
                    let dependencies = try EngineDependencies.live(configuration: configuration)
                    let started = try await Engine(configuration: configuration, dependencies: dependencies)
                    await started.setEnabled(enabled)
                    for (name, properties, date) in early {
                        await started.track(name, properties, at: date)
                    }
                    early.removeAll()
                    await started.start()
                    observers = startLifecycle(started)
                    startTimer(started, clock: dependencies.clock)
                    engine = started
                } catch {
                    DebugLog(enabled: configuration.isDebug).notice("could not start: \(error.localizedDescription)")
                }
            case .track(let name, let properties, let date):
                if let engine {
                    await engine.track(name, properties, at: date)
                } else if enabled, early.count < Limits().maxQueuedEvents {
                    early.append((name, properties, date))
                }
            case .flush(let continuation):
                if let engine {
                    // Not awaited here: tracking keeps flowing while the request is out.
                    Task {
                        await engine.flush()
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
            case .setEnabled(let value):
                enabled = value
                if value == false { early.removeAll() }
                await engine?.setEnabled(value)
            }
        }
        _ = observers
    }

    private static func startLifecycle(_ engine: Engine) -> [any NSObjectProtocol] {
        let (events, continuation) = AsyncStream.makeStream(of: LifecycleEvent.self)
        Task {
            for await event in events {
                switch event {
                case .didEnterBackground: await engine.didEnterBackground()
                case .willEnterForeground: await engine.willEnterForeground()
                case .willResignActive: await engine.flush()
                }
            }
        }
        return LifecycleObserver.observe(continuation)
    }

    private static func startTimer(_ engine: Engine, clock: any SDKClock) {
        Task(priority: .utility) {
            while !Task.isCancelled {
                let delay = await engine.nextWakeDelay()
                try? await clock.sleep(seconds: delay)
                await engine.tick()
            }
        }
    }
}
