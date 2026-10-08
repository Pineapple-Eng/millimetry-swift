import Foundation

/// What the public API asks of the runtime, in the order it was asked.
enum Command: Sendable {
    case configure(Configuration)
    case track(name: String, properties: [String: PropValue], at: Date)
    case flush(CheckedContinuation<Void, Never>)
    case setEnabled(Bool)
}
