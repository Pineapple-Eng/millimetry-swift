import Foundation
import Testing
@testable import Millimetry

/// The privacy manifest is present and declares exactly what the SDK does.
struct PrivacyManifestTests {
    private func manifest() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func declaresNoTracking() throws {
        let plist = try manifest()
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
    }

    @Test func declaresProductInteractionForAnalyticsNotLinked() throws {
        let types = try #require(try manifest()["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        #expect(types.count == 1)
        let type = try #require(types.first)
        #expect(type["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeProductInteraction")
        #expect(type["NSPrivacyCollectedDataTypeLinked"] as? Bool == false)
        #expect(type["NSPrivacyCollectedDataTypeTracking"] as? Bool == false)
        #expect(type["NSPrivacyCollectedDataTypePurposes"] as? [String] == ["NSPrivacyCollectedDataTypePurposeAnalytics"])
    }

    /// The manifest declares no required-reason APIs, so the sources must not use any. If one of
    /// these appears, declare it in the manifest with its reason code and update this list.
    @Test func theSourcesUseNoRequiredReasonAPIs() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Millimetry")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 10)
        let requiredReason = [
            "creationDate", "modificationDate", "contentModificationDate", "attributesOfItem",
            "systemUptime", "mach_absolute_time", "UserDefaults", "volumeAvailableCapacity",
            "systemFreeSize", "statfs", "activeInputModes",
        ]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for symbol in requiredReason {
                #expect(text.contains(symbol) == false, "\(file.lastPathComponent) uses \(symbol)")
            }
        }
    }

    @Test func theSDKSendsNoAdvertisingOrVendorIdentifiers() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Millimetry")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for symbol in ["advertisingIdentifier", "identifierForVendor", "ASIdentifierManager", "Keychain", "SecItem"] {
                #expect(text.contains(symbol) == false, "\(file.lastPathComponent) uses \(symbol)")
            }
        }
    }
}
