# Privacy

What the SDK sends, what it stores, and what to put in your App Store privacy label.

## What is sent

Each batch carries the device and app description once (OS name and version, hardware model,
locale, app version and build, whether it is a debug build) and the events: name, time, session id
and properties. The SDK sends no identifiers: no advertising identifier (IDFA), no vendor
identifier (IDFV), no install id, nothing from the Keychain or `UserDefaults`.

The server sees the connection's IP address. It uses it, with the device description and a random
value that changes every day, to compute a daily-rotating user hash, and to look up the country and
region. The IP address itself is never stored or logged.

## What is stored on the device

Only the outbound queue: events waiting to be sent, under `Application Support/Millimetry/queue/`.
The folder is excluded from backups, and its files are protected until the device is first
unlocked. Events leave the queue when they are delivered, after 7 days, or when the queue passes
1,000 events (the oldest go first). The session id is kept in memory only.

## Privacy manifest

The package ships a `PrivacyInfo.xcprivacy` declaring no tracking and one collected data type:
**Product Interaction**, not linked to the user, not used for tracking, for **Analytics**. The SDK
uses none of Apple's required-reason APIs.

## Your App Store privacy label

Declare **Product Interaction**, used for **Analytics**, **not linked** to the user's identity and
**not used for tracking**. Country and region are derived on the server from the IP address; whether
that also needs **Coarse Location** on the label is still being confirmed, and this page will say
so when it is.
