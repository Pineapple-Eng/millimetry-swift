import Foundation

/// Time-ordered UUIDs (RFC 9562 version 7): 48 bits of Unix milliseconds, then random bits.
/// Session ids use them, so the server can tell roughly when a session started from its id alone.
enum UUIDv7 {
    static func make(at date: Date) -> UUID {
        var generator = SystemRandomNumberGenerator()
        return make(at: date, using: &generator)
    }

    static func make<G: RandomNumberGenerator>(at date: Date, using generator: inout G) -> UUID {
        let milliseconds = UInt64(max(0, date.timeIntervalSince1970 * 1_000))
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<6 {
            bytes[index] = UInt8(truncatingIfNeeded: milliseconds >> (8 * (5 - index)))
        }
        for index in 6..<16 {
            bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70  // version 7
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // RFC 9562 variant
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// The Unix-millisecond timestamp a version 7 UUID carries.
    static func milliseconds(of uuid: UUID) -> UInt64 {
        let bytes = uuid.uuid
        let leading = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5]
        return leading.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
