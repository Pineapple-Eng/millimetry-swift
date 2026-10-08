import Foundation
import Testing
@testable import Millimetry

struct UUIDv7Tests {
    @Test func carriesVersionSevenAndTheRFCVariant() {
        let uuid = UUIDv7.make(at: Date())
        let bytes = uuid.uuid
        #expect(bytes.6 >> 4 == 0x7)
        #expect(bytes.8 >> 6 == 0b10)
        #expect(uuid.uuidString.dropFirst(14).first == "7")
    }

    @Test(arguments: [0.0, 1_791_000_000.123, 2_000_000_000.999])
    func embedsTheUnixMilliseconds(seconds: TimeInterval) {
        let uuid = UUIDv7.make(at: Date(timeIntervalSince1970: seconds))
        #expect(UUIDv7.milliseconds(of: uuid) == UInt64(seconds * 1_000))
    }

    @Test func laterIdsSortAfterEarlierOnes() {
        let earlier = UUIDv7.make(at: Date(timeIntervalSince1970: 1_791_000_000))
        let later = UUIDv7.make(at: Date(timeIntervalSince1970: 1_791_000_001))
        #expect(earlier.uuidString < later.uuidString)
    }
}
