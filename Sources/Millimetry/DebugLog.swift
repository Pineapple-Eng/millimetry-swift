import Foundation
import os

/// Logging for debug builds only: drops and rejections are logged in debug builds, nothing in release.
/// Nothing the SDK logs identifies a person; event properties are never logged.
struct DebugLog: Sendable {
    let enabled: Bool
    private let logger = Logger(subsystem: "app.millimetry", category: "sdk")

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func notice(_ message: String) {
        guard enabled else { return }
        logger.notice("\(message, privacy: .public)")
    }
}
