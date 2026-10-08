import Foundation

/// Where the example sends its events. Set `MILLIMETRY_APP_KEY` to your app's key in the scheme's
/// environment (Product › Scheme › Edit Scheme › Run › Arguments), or prefix it with `SIMCTL_CHILD_`
/// when launching with `xcrun simctl launch`. `MILLIMETRY_HOST` overrides the server.
struct ExampleSettings {
    var appKey: String
    var host: URL

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> ExampleSettings {
        ExampleSettings(
            appKey: environment["MILLIMETRY_APP_KEY"] ?? "ak_set_MILLIMETRY_APP_KEY_in_the_scheme",
            host: environment["MILLIMETRY_HOST"].flatMap(URL.init(string:)) ?? URL(string: "https://e.millimetry.app")!
        )
    }
}
