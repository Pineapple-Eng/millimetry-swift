# Millimetry for Swift

Privacy-first product analytics for apps on Apple platforms. Track what people do in your app without learning who they are: the SDK sends no device identifiers, stores no user ID on the device, and the server never keeps IP addresses.

- iOS and iPadOS 15, macOS 12, tvOS 15, watchOS 8, visionOS 1 or later
- No dependencies. Swift 6 with strict concurrency; every call is safe from any thread.
- Events are queued on disk, sent in compressed batches, retried with backoff, and stored exactly once.

Documentation: [docs.millimetry.app](https://docs.millimetry.app/start/apps/)

## Install

In Xcode, choose **File › Add Package Dependencies…** and enter:

```
https://github.com/Pineapple-Eng/millimetry-swift
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/Pineapple-Eng/millimetry-swift", from: "0.1.0")
```

## Use

Create an app at [millimetry.app](https://millimetry.app) and copy its key (`ak_…`). The key identifies your app and is safe to ship in your binary.

```swift
import Millimetry

@main
struct MyApp: App {
    init() {
        Millimetry.configure(
            appKey: "ak_…",
            host: URL(string: "https://e.millimetry.app")!
        )
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

```swift
Millimetry.track("screen_view", ["screen": "settings"])
Millimetry.track("purchase", ["plan": "pro", "price": 4.99, "trial": false])
```

- `app_open` is sent at launch and when the app returns to the foreground. Turn it off with `options: .init(trackAppOpen: false)`.
- Event names are 1 to 64 characters. Up to 25 properties per event: strings, numbers or Booleans.
- Never put personal data in properties. The server drops properties that look like an email address, a phone number or an ID, but that is a safety net, not a guarantee.
- `await Millimetry.flush()` sends whatever is queued.
- `Millimetry.setEnabled(false)` stops tracking and deletes everything queued. The SDK does not remember the choice, because remembering it would mean storing something on the device. Keep your own setting and apply it on every launch, before `configure`.

Builds with the Debug configuration mark their events as debug data, which the dashboard keeps apart and deletes after 30 days. Override with `Options(isDebug:)`.

## Privacy

What is sent with each batch: the OS name and version, the device model (such as `iPhone17,1`), the locale, the app version and build, and whether it is a debug build. Each event carries its name, time, session ID and your properties.

What is never collected: the advertising identifier (IDFA), the vendor identifier (IDFV), an install ID, or anything from the Keychain or `UserDefaults`. The session ID lives in memory only.

On the device, the SDK keeps one thing: the queue of events waiting to be sent, in `Application Support/Millimetry/queue/`. It is excluded from backups, holds at most 1,000 events, and drops events older than 7 days.

The package ships a privacy manifest (`PrivacyInfo.xcprivacy`) that declares no tracking and one collected data type, Product Interaction, not linked to the user, for analytics. It uses none of Apple's required-reason APIs; a test fails the build if one appears.

For your App Store privacy label, see [the guide](https://docs.millimetry.app/guides/app-store-label/).

## Example app

`Example/MillimetryExample.xcodeproj` is a small SwiftUI app that uses the package from this folder. Set `MILLIMETRY_APP_KEY` in its scheme (Product › Scheme › Edit Scheme › Run › Arguments) and run it.

## Development

```sh
swift test
```

Tests use Swift Testing, with an injected clock and network, so queue limits, batching, backoff and session rotation are tested without waiting. One integration test talks to a real ingest server and runs only when `MILLIMETRY_INGEST_URL` and `MILLIMETRY_APP_KEY` are set.

## License

[MIT](LICENSE)
