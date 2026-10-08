import Foundation

/// The device and app description sent once per batch. A batch never mixes two
/// of these: when anything changes (an app update, an OS update) the next events start a new batch.
struct SystemInfo: Sendable, Hashable, Codable {
    var osName: String
    var osVersion: String
    var deviceModel: String
    var locale: String
    var appVersion: String
    var appBuild: String
    var isDebug: Bool

    enum CodingKeys: String, CodingKey {
        case osName = "os_name"
        case osVersion = "os_version"
        case deviceModel = "device_model"
        case locale
        case appVersion = "app_version"
        case appBuild = "app_build"
        case isDebug = "is_debug"
    }
}
