import Foundation

/// How the SDK behaves. The defaults suit almost every app.
public struct Options: Sendable, Equatable {
    /// Sends `app_open` at launch and whenever the app returns to the foreground.
    public var trackAppOpen: Bool
    /// Seconds between automatic flushes while the app is in the foreground. `nil` means 30 s in
    /// release builds and 2 s in debug builds.
    public var flushInterval: TimeInterval?
    /// Marks events as debug data, which the dashboard keeps apart and deletes after 30 days.
    /// `nil` means "debug when the app is built with the Debug configuration".
    public var isDebug: Bool?

    public init(trackAppOpen: Bool = true, flushInterval: TimeInterval? = nil, isDebug: Bool? = nil) {
        self.trackAppOpen = trackAppOpen
        self.flushInterval = flushInterval
        self.isDebug = isDebug
    }
}
