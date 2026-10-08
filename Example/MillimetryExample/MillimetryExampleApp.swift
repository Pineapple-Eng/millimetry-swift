import Millimetry
import SwiftUI

/// A small app that exercises the SDK: screen views, a purchase, opting out, and sending now.
@main
struct MillimetryExampleApp: App {
    init() {
        let settings = ExampleSettings.fromEnvironment()
        Millimetry.configure(appKey: settings.appKey, host: settings.host)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
