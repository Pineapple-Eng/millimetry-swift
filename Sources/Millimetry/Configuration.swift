import Foundation

/// Everything the engine needs to know, resolved from the public options.
struct Configuration: Sendable, Equatable {
    var appKey: String
    var host: URL
    var trackAppOpen: Bool
    var flushInterval: TimeInterval
    var isDebug: Bool
    var limits: Limits

    init(appKey: String, host: URL, options: Options, limits: Limits = Limits()) {
        let isDebug = options.isDebug ?? Configuration.builtForDebug
        self.appKey = appKey
        self.host = host
        self.trackAppOpen = options.trackAppOpen
        self.flushInterval = options.flushInterval ?? (isDebug ? 2 : 30)
        self.isDebug = isDebug
        self.limits = limits
    }

    /// The configuration the SDK was compiled with, which follows the app's build configuration.
    static var builtForDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// `/v1/app/batch` on the configured host.
    var batchEndpoint: URL {
        host.appendingPathComponent("v1").appendingPathComponent("app").appendingPathComponent("batch")
    }
}
