import Foundation
import Testing
@testable import Millimetry

struct GzipTests {
    @Test func crc32MatchesTheStandardCheckValue() {
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum([UInt8]()) == 0)
    }

    @Test func writesAGzipHeaderAndRoundTrips() throws {
        let original = Data(String(repeating: #"{"name":"screen_view","props":{"screen":"home"}}"#, count: 200).utf8)
        let compressed = try Gzip.compress(original)
        #expect(Array(compressed.prefix(3)) == [0x1F, 0x8B, 0x08])
        #expect(compressed.count < original.count / 4, "repetitive JSON compresses well")
        #expect(try GunzipForTests.decode(compressed) == original)
    }

    @Test func compressesAnEmptyBody() throws {
        let compressed = try Gzip.compress(Data())
        #expect(try GunzipForTests.decode(compressed).isEmpty)
    }
}
