import Foundation

nonisolated enum SphairaCommand: UInt32 { case quit = 0, open = 1 }
nonisolated enum SphairaResult: UInt32 { case ok = 0, error = 1 }

nonisolated enum TransferFlags {
    static let none: UInt32 = 0
    static let stream: UInt32 = 1 << 0
}

/// Drahtformat: sechs UInt32 little-endian — magic, arg2, arg3, arg4, arg5, crc32c.
/// Die CRC32C läuft über die ersten 20 Bytes.
nonisolated struct Packet: Equatable, Sendable {
    static let magic: UInt32 = 0x5350_4830
    static let byteCount: Int = 24

    var arg2: UInt32
    var arg3: UInt32
    var arg4: UInt32
    var arg5: UInt32

    init(arg2: UInt32 = 0, arg3: UInt32 = 0, arg4: UInt32 = 0, arg5: UInt32 = 0) {
        self.arg2 = arg2
        self.arg3 = arg3
        self.arg4 = arg4
        self.arg5 = arg5
    }

    func encoded() -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(Self.byteCount)
        for word in [Self.magic, arg2, arg3, arg4, arg5] {
            bytes.append(contentsOf: Self.littleEndianBytes(word))
        }
        bytes.append(contentsOf: Self.littleEndianBytes(CRC32C.checksum(bytes)))
        return bytes
    }

    static func decode(_ bytes: [UInt8]) throws -> Packet {
        // Prüfreihenfolge laut Vertrag: erst Länge, dann Magic, dann CRC.
        guard bytes.count == byteCount else {
            throw InstallError.shortPacket(expected: byteCount, got: bytes.count)
        }
        let words = (0..<6).map { readWord(bytes, at: $0 * 4) }
        guard words[0] == magic else { throw InstallError.badMagic }
        guard CRC32C.checksum(bytes.prefix(20)) == words[5] else {
            throw InstallError.checksumMismatch
        }
        return Packet(arg2: words[1], arg3: words[2], arg4: words[3], arg5: words[4])
    }

    var command: UInt32 { arg2 }
    var dataOffset: UInt64 { UInt64(arg2) << 32 | UInt64(arg3) }
    var dataSize: UInt32 { arg4 }

    private static func littleEndianBytes(_ word: UInt32) -> [UInt8] {
        [UInt8(word & 0xFF), UInt8((word >> 8) & 0xFF),
         UInt8((word >> 16) & 0xFF), UInt8((word >> 24) & 0xFF)]
    }

    private static func readWord(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
