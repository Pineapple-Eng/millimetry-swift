import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif
#if os(watchOS)
import WatchKit
#endif

/// Turns the platform's lifecycle notifications into a stream of ``LifecycleEvent``s.
enum LifecycleObserver {
    /// Starts observing. The returned tokens must be kept alive for as long as observation should
    /// continue; the runtime keeps them for the life of the process.
    static func observe(_ continuation: AsyncStream<LifecycleEvent>.Continuation) -> [any NSObjectProtocol] {
        let center = NotificationCenter.default
        var pairs: [(Notification.Name, LifecycleEvent)] = []
        #if canImport(UIKit) && !os(watchOS)
        pairs = [
            (UIApplication.didEnterBackgroundNotification, .didEnterBackground),
            (UIApplication.willEnterForegroundNotification, .willEnterForeground),
        ]
        #elseif os(watchOS)
        pairs = [
            (WKApplication.didEnterBackgroundNotification, .didEnterBackground),
            (WKApplication.willEnterForegroundNotification, .willEnterForeground),
        ]
        #elseif canImport(AppKit)
        pairs = [
            (NSApplication.didHideNotification, .didEnterBackground),
            (NSApplication.didUnhideNotification, .willEnterForeground),
            (NSApplication.willResignActiveNotification, .willResignActive),
            (NSApplication.willTerminateNotification, .didEnterBackground),
        ]
        #endif
        return pairs.map { name, event in
            center.addObserver(forName: name, object: nil, queue: nil) { _ in
                continuation.yield(event)
            }
        }
    }
}
