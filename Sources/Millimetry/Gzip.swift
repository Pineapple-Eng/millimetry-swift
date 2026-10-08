import Foundation

/// gzip (RFC 1952) around Foundation's raw DEFLATE, so the SDK needs no zlib wrapper of its own.
/// `NSData.compressed(using: .zlib)` produces a raw DEFLATE stream; gzip adds a fixed 10-byte
/// header and an 8-byte trailer holding the CRC-32 and length of the original bytes.
enum Gzip {
    enum Failure: Error {
        case compression
    }

    static func compress(_ data: Data) throws -> Data {
        let deflated: Data
        do {
            deflated = try (data as NSData).compressed(using: .zlib) as Data
        } catch {
            throw Failure.compression
        }
        var out = Data(capacity: deflated.count + 18)
        // ID1 ID2, CM = deflate, FLG = none, MTIME = 0, XFL = 0, OS = unknown (255)
        out.append(contentsOf: [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        out.append(deflated)
        appendLittleEndian(CRC32.checksum(data), to: &out)
        appendLittleEndian(UInt32(truncatingIfNeeded: data.count), to: &out)
        return out
    }

    private static func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, to: 32, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }
}
