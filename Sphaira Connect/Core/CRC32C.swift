import Foundation

// CRC-32C (Castagnoli), reflected polynomial 0x82F63B78.
// nonisolated so the USB code can call it off the MainActor.
nonisolated enum CRC32C {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var crc = UInt32(index)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0x82F6_3B78 : crc >> 1
            }
            return crc
        }
    }()

    static func checksum<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return ~crc
    }
}
