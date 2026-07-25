import Testing
@testable import SphairaCore

/// Unabhängige bitweise Referenzimplementierung (ohne Tabelle), damit die
/// tabellenbasierte Produktivvariante gegen eine zweite Quelle geprüft wird.
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
    @Test("Leere Eingabe ergibt 0")
    func emptyInput() {
        #expect(CRC32C.checksum([]) == 0)
        #expect(CRC32C.checksum([UInt8]().prefix(0)) == 0)
    }

    @Test("Referenzwert der Vertragsvorgabe: \"123456789\"")
    func contractReference() {
        #expect(CRC32C.checksum(Array("123456789".utf8)) == 0xE306_9283)
    }

    @Test("Bekannte Vektoren aus RFC 3720")
    func rfc3720Vectors() {
        #expect(CRC32C.checksum([UInt8](repeating: 0x00, count: 32)) == 0x8A91_36AA)
        #expect(CRC32C.checksum([UInt8](repeating: 0xFF, count: 32)) == 0x62A8_AB43)
        #expect(CRC32C.checksum((0..<32).map { UInt8($0) }) == 0x46DD_794E)
        #expect(CRC32C.checksum((0..<32).reversed().map { UInt8($0) }) == 0x113F_DB5C)
    }

    @Test("Jeder Einzelbyte-Wert stimmt mit der Referenz überein")
    func allSingleBytes() {
        for value in UInt8.min...UInt8.max {
            #expect(CRC32C.checksum([value]) == referenceCRC32C([value]))
        }
    }

    @Test("Kurzstrings stimmen mit der Referenz überein")
    func shortStrings() {
        for text in ["a", "abc", "message digest", "Sphaira Connect", "äöü ß €"] {
            let bytes = Array(text.utf8)
            #expect(CRC32C.checksum(bytes) == referenceCRC32C(bytes))
        }
    }

    @Test("Langer Puffer (1 MiB, deterministisches Muster)")
    func longBuffer() {
        var bytes = [UInt8](repeating: 0, count: 1 << 20)
        var state: UInt32 = 0x1234_5678
        for index in bytes.indices {
            // Xorshift als deterministischer Generator
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            bytes[index] = UInt8(truncatingIfNeeded: state)
        }
        #expect(CRC32C.checksum(bytes) == referenceCRC32C(bytes))
    }

    @Test("Zufallspuffer verschiedener Längen gegen die Referenz")
    func randomBuffers() {
        var generator = SystemRandomNumberGenerator()
        for length in [1, 2, 3, 7, 19, 20, 24, 255, 1024] {
            let bytes = (0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            #expect(CRC32C.checksum(bytes) == referenceCRC32C(bytes))
        }
    }

    @Test("Collection-Generik: ArraySlice liefert dasselbe wie Array")
    func sliceEquality() {
        let bytes = Array("Hallo Sphaira 123456789".utf8)
        #expect(CRC32C.checksum(bytes[...]) == CRC32C.checksum(bytes))
        #expect(CRC32C.checksum(bytes.prefix(9)) == CRC32C.checksum(Array(bytes.prefix(9))))
    }

    @Test("Ein gekipptes Bit ändert die Prüfsumme")
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
