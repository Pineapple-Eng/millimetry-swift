import Foundation

/// Privacy-first analytics for your app.
///
/// Configure once at launch, then track events from anywhere:
///
/// ```swift
/// Millimetry.configure(appKey: "ak_…", host: URL(string: "https://e.millimetry.app")!)
/// Millimetry.track("purchase", ["price": 4.99, "plan": "pro", "trial": false])
/// ```
///
/// The SDK stores no identifiers on the device. Events wait in a small on-disk queue until they
/// are delivered, and are sent in compressed batches.
public enum Millimetry {
    /// Starts the SDK. Call it once, as early as possible in the app's launch. Later calls are
    /// ignored.
    ///
    /// - Parameters:
    ///   - appKey: The public `ak_…` key for your app, from the dashboard.
    ///   - host: The ingest host, for example `https://e.millimetry.app`.
    ///   - options: Automatic events, flush cadence and the debug flag.
    public static func configure(appKey: String, host: URL, options: Options = Options()) {
        Runtime.shared.send(.configure(Configuration(appKey: appKey, host: host, options: options)))
    }

    /// Records an event. Safe to call from any thread, before or after ``configure(appKey:host:options:)``.
    ///
    /// - Parameters:
    ///   - name: 1 to 64 characters; names starting with `$` are reserved.
    ///   - properties: Up to 25 values. Never send personal data: the server drops properties that
    ///     look like email addresses, phone numbers or identifiers, but the responsibility is yours.
    public static func track(_ name: String, _ properties: [String: PropValue] = [:]) {
        Runtime.shared.send(.track(name: name, properties: properties, at: Date()))
    }

    /// Sends everything queued so far and returns when the attempt is over. Events that could not
    /// be delivered stay queued and are retried later.
    public static func flush() async {
        await withCheckedContinuation { continuation in
            Runtime.shared.send(.flush(continuation))
        }
    }

    /// Turns tracking on or off. Turning it off deletes every queued event and ignores events
    /// until it is turned on again. The setting is not stored: apply your own user preference on
    /// every launch, before ``configure(appKey:host:options:)``.
    public static func setEnabled(_ enabled: Bool) {
        Runtime.shared.send(.setEnabled(enabled))
    }
}
