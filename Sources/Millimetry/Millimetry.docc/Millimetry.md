# ``Millimetry``

Privacy-first product analytics for Apple platforms.

## Overview

Millimetry counts what happens in your app without identifying the people using it. The SDK stores
no identifiers on the device: no advertising identifier, no vendor identifier, no install id. A
session id lives in memory only and is replaced after 30 minutes away. The server derives a user
count from a hash that rotates every day, so it can tell you how many people used the app today,
but never who they were or what one person did last week.

Events are queued on disk until they are delivered, so they survive the app being killed or the
device going offline, and are sent in small compressed batches.

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

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

Then track events from anywhere:

```swift
Millimetry.track("purchase", ["price": 4.99, "plan": "pro", "trial": false])
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``Millimetry/configure(appKey:host:options:)``
- ``Millimetry/track(_:_:)``

### Delivery and opting out

- ``Millimetry/flush()``
- ``Millimetry/setEnabled(_:)``

### Configuration

- ``Options``
- ``PropValue``

### Privacy

- <doc:Privacy>
