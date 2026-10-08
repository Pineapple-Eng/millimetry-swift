/// The app moving between foreground and background, as the platform reports it.
enum LifecycleEvent: Sendable {
    case didEnterBackground
    case willEnterForeground
    /// The app is losing focus without being suspended (macOS): a good moment to flush.
    case willResignActive
}
