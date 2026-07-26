import Testing
@testable import SphairaCore

/// Independent bitwise reference implementation (no table), so the table-driven
/// production variant is checked against a second source.
private func referenceCRC32C(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (crc >> 1) ^ 0x82F6_3B78 : crc >> 1
        }
    }
    return ~crc
}

@Suite("CRC32C")
struct CRC32CTests {
    @Test("Empty input yields 0")
    func emptyInput() {
        #expect(CRC32C.checksum([]) == 0)
        #expect(CRC32C.checksum([UInt8]().prefix(0)) == 0)
    }

    @Test("Reference value from the contract: \"123456789\"")
    func contractReference() {
        #expect(CRC32C.checksum(Array("123456789".utf8)) == 0xE306_9283)
    }

    @Test("Known vectors from RFC 3720")
    func rfc3720Vectors() {
        #expect(CRC32C.checksum([UInt8](repeating: 0x00, count: 32)) == 0x8A91_36AA)
        #expect(CRC32C.checksum([UInt8](repeating: 0xFF, count: 32)) == 0x62A8_AB43)
        #expect(CRC32C.checksum((0..<32).map { UInt8($0) }) == 0x46DD_794E)
        #expect(CRC32C.checksum((0..<32).reversed().map { UInt8($0) }) == 0x113F_DB5C)
    }

    @Test("Every single-byte value matches the reference")
    func allSingleBytes() {
        for value in UInt8.min...UInt8.max {
            #expect(CRC32C.checksum([value]) == referenceCRC32C([value]))
        }
    }

    @Test("Short strings match the reference")
    func shortStrings() {
        for text in ["a", "abc", "message digest", "Sphaira Connect", "äöü ß €"] {
            let bytes = Array(text.utf8)
            #expect(CRC32C.checksum(bytes) == referenceCRC32C(bytes))
        }
    }

    @Test("Long buffer (1 MiB, deterministic pattern)")
    func longBuffer() {
        var bytes = [UInt8](repeating: 0, count: 1 << 20)
        var state: UInt32 = 0x1234_5678
        for index in bytes.indices {
            // Xorshift as a deterministic generator
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            bytes[index] = UInt8(truncatingIfNeeded: state)
        }
        #expect(CRC32C.checksum(bytes) == referenceCRC32C(bytes))
    }

    @Test("Random buffers of various lengths against the reference")
    func randomBuffers() {
        var generator = SystemRandomNumberGenerator()
        for length in [1, 2, 3, 7, 19, 20, 24, 255, 1024] {
            let bytes = (0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            #expect(CRC32C.checksum(bytes) == referenceCRC32C(bytes))
        }
    }

    @Test("Collection generics: ArraySlice yields the same as Array")
    func sliceEquality() {
        let bytes = Array("Hello Sphaira 123456789".utf8)
        #expect(CRC32C.checksum(bytes[...]) == CRC32C.checksum(bytes))
        #expect(CRC32C.checksum(bytes.prefix(9)) == CRC32C.checksum(Array(bytes.prefix(9))))
    }

    @Test("A single flipped bit changes the checksum")
    func bitFlipChangesChecksum() {
        let bytes = Array("123456789".utf8)
        let original = CRC32C.checksum(bytes)
        for index in bytes.indices {
            var mutated = bytes
            mutated[index] ^= 0x01
            #expect(CRC32C.checksum(mutated) != original)
        }
    }
}
