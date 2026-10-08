# Getting Started

Add the package, configure it at launch, and track your first event.

## Add the package

In Xcode, choose **File › Add Package Dependencies…** and add the Millimetry package, or add it to
your `Package.swift`:

```swift
.package(url: "https://github.com/Pineapple-Eng/millimetry-swift", from: "0.1.0")
```

The package has no dependencies of its own.

## Configure at launch

Call ``Millimetry/configure(appKey:host:options:)`` once, as early as possible: in your `App`'s
initializer or your app delegate's `application(_:didFinishLaunchingWithOptions:)`. The app key is
public: it identifies your app, so it is fine to ship it in your binary.

```swift
Millimetry.configure(
    appKey: "ak_…",
    host: URL(string: "https://e.millimetry.app")!,
    options: .init(trackAppOpen: true)
)
```

With `trackAppOpen`, the SDK sends `app_open` at launch and whenever the app returns to the
foreground. Nothing else is tracked automatically.

## Track events

```swift
Millimetry.track("screen_view", ["screen": "settings"])
Millimetry.track("purchase", ["price": 4.99, "plan": "pro"])
```

Event names are 1 to 64 characters; names that start with `$` are reserved. An event carries up to
25 properties, each a string, a whole number, a decimal number or a Boolean, written as plain
literals. Strings longer than 256 characters are cut.

Never put personal data in properties: no names, email addresses, phone numbers or account ids. The
server drops properties that look like these, but that is a safety net, not a guarantee.

## When events are sent

Events are written to a small queue on disk and sent in batches:

- every 30 seconds while the app is in the foreground (every 2 seconds in debug builds);
- as soon as 50 events are waiting;
- when the app moves to the background, inside a background task so the upload can finish;
- whenever you call ``Millimetry/flush()``.

If the device is offline or the server is unavailable, the batch stays queued and is retried with a
growing delay, up to five minutes. A batch keeps its id across retries and relaunches, so the
server stores it once however many times it arrives. The queue holds at most 1,000 events and drops
events older than 7 days.

## Debug data

Builds made with the Debug configuration mark their events as debug data, which the dashboard keeps
apart from production and deletes after 30 days. Override it with `Options(isDebug:)`.

## Letting people opt out

``Millimetry/setEnabled(_:)`` with `false` stops tracking and deletes everything queued. The SDK
does not remember the choice, because remembering it would mean storing something on the device:
keep your own setting and apply it on every launch, before configuring.

```swift
Millimetry.setEnabled(UserPreferences.analyticsAllowed)
Millimetry.configure(appKey: "ak_…", host: host)
```
