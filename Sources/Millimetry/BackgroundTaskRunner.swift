import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Keeps the app running while `work` finishes after it enters the background: the background
/// flush runs inside a background-task assertion. Injected so tests can observe it.
protocol BackgroundTaskRunner: Sendable {
    func run(name: String, _ work: @escaping @Sendable () async -> Void) async
}

/// UIKit's `beginBackgroundTask` where it exists; on watchOS, `performExpiringActivity`; on
/// macOS, nothing is needed because apps are not suspended on leaving the foreground.
struct SystemBackgroundTaskRunner: BackgroundTaskRunner {
    func run(name: String, _ work: @escaping @Sendable () async -> Void) async {
        #if canImport(UIKit) && !os(watchOS)
        let assertion = await UIKitAssertion.begin(name: name)
        await work()
        await assertion.end()
        #elseif os(watchOS)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // The system may call the block a second time with `expired` while the work still
            // runs, so the continuation is resumed by whichever call gets there first.
            let once = ResumeOnce(continuation)
            ProcessInfo.processInfo.performExpiringActivity(withReason: name) { expired in
                if expired {
                    once.resume()
                    return
                }
                // The activity lasts as long as this block: hold it until the work is done.
                let done = DispatchSemaphore(value: 0)
                Task {
                    await work()
                    done.signal()
                }
                done.wait()
                once.resume()
            }
        }
        #else
        await work()
        #endif
    }
}

#if canImport(UIKit) && !os(watchOS)
/// One `beginBackgroundTask` assertion, ended exactly once: by the work finishing or by the
/// system's expiration handler, whichever comes first.
@MainActor
final class UIKitAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    static func begin(name: String) -> UIKitAssertion {
        let assertion = UIKitAssertion()
        assertion.identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            MainActor.assumeIsolated { assertion.end() }
        }
        return assertion
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif
