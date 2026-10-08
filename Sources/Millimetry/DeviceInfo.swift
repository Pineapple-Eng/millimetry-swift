import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif
#if os(watchOS)
import WatchKit
#endif

/// Reads what ``SystemInfo`` describes from the running device. Nothing here identifies the
/// device: no IDFA, no IDFV, no install id. The OS name needs UIKit, so it is read on
/// the main actor.
enum DeviceInfo {
    /// The version string the SDK reports as `sdk`.
    static let sdkVersion = "swift@0.1.0"

    @MainActor
    static func current(isDebug: Bool, bundle: Bundle = .main) -> SystemInfo {
        SystemInfo(
            osName: osName(),
            osVersion: osVersion(),
            deviceModel: deviceModel(),
            locale: localeIdentifier(Locale.current),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            isDebug: isDebug
        )
    }

    @MainActor
    static func osName() -> String {
        #if os(macOS)
        return "macOS"
        #elseif os(visionOS)
        return "visionOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(iOS)
        // iPadOS is reported separately from iOS; an iPhone app on an iPad is still iPadOS.
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #else
        return "unknown"
        #endif
    }

    static func osVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// The hardware model, e.g. `iPhone17,1` or `Mac15,3`; on a simulator, the simulated model.
    static func deviceModel() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        #if os(macOS)
        return sysctlString("hw.model") ?? "Mac"
        #else
        return sysctlString("hw.machine") ?? "unknown"
        #endif
    }

    /// `en_CA` becomes `en-CA`; calendar and other extensions (`@calendar=…`) are dropped.
    static func localeIdentifier(_ locale: Locale) -> String {
        let base = locale.identifier.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
        return base.replacingOccurrences(of: "_", with: "-")
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
