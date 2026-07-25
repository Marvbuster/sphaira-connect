import Testing
@testable import SphairaCore

@Suite("Packet")
struct PacketTests {
    @Test("Konstanten laut Vertrag")
    func constants() {
        #expect(Packet.magic == 0x5350_4830)
        #expect(Packet.byteCount == 24)
        #expect(SphairaCommand.quit.rawValue == 0)
        #expect(SphairaCommand.open.rawValue == 1)
        #expect(SphairaResult.ok.rawValue == 0)
        #expect(SphairaResult.error.rawValue == 1)
        #expect(TransferFlags.none == 0)
        #expect(TransferFlags.stream == 1)
    }

    @Test("encoded() liefert genau 24 Bytes")
    func encodedLength() {
        #expect(Packet().encoded().count == 24)
        #expect(Packet(arg2: .max, arg3: .max, arg4: .max, arg5: .max).encoded().count == 24)
    }

    @Test("Byteanordnung: sechs UInt32 little-endian, einzeln nachgerechnet")
    func wireLayoutLittleEndian() {
        let packet = Packet(arg2: 0x0102_0304, arg3: 0xAABB_CCDD, arg4: 0x0000_0001, arg5: 0xFF00_00FF)
        let bytes = packet.encoded()

        // magic 0x53504830 → LE: 30 48 50 53
        #expect(Array(bytes[0..<4]) == [0x30, 0x48, 0x50, 0x53])
        // arg2 0x01020304 → LE: 04 03 02 01
        #expect(Array(bytes[4..<8]) == [0x04, 0x03, 0x02, 0x01])
        // arg3 0xAABBCCDD → LE: DD CC BB AA
        #expect(Array(bytes[8..<12]) == [0xDD, 0xCC, 0xBB, 0xAA])
        // arg4 0x00000001 → LE: 01 00 00 00
        #expect(Array(bytes[12..<16]) == [0x01, 0x00, 0x00, 0x00])
        // arg5 0xFF0000FF → LE: FF 00 00 FF
        #expect(Array(bytes[16..<20]) == [0xFF, 0x00, 0x00, 0xFF])

        // CRC32C über die ersten 20 Bytes, ebenfalls little-endian
        let crc = CRC32C.checksum(bytes.prefix(20))
        #expect(bytes[20] == UInt8(crc & 0xFF))
        #expect(bytes[21] == UInt8((crc >> 8) & 0xFF))
        #expect(bytes[22] == UInt8((crc >> 16) & 0xFF))
        #expect(bytes[23] == UInt8((crc >> 24) & 0xFF))
    }

    @Test("Hin- und Rückumwandlung für Zufallswerte")
    func roundTripRandom() throws {
        for _ in 0..<200 {
            let original = Packet(
                arg2: .random(in: .min ... .max),
                arg3: .random(in: .min ... .max),
                arg4: .random(in: .min ... .max),
                arg5: .random(in: .min ... .max)
            )
            let decoded = try Packet.decode(original.encoded())
            #expect(decoded == original)
        }
    }

    @Test("Hin- und Rückumwandlung für Grenzwerte")
    func roundTripEdges() throws {
        for value: UInt32 in [0, 1, 0x7FFF_FFFF, 0x8000_0000, .max] {
            let packet = Packet(arg2: value, arg3: value, arg4: value, arg5: value)
            #expect(try Packet.decode(packet.encoded()) == packet)
        }
    }

    @Test("Abgeleitete Felder: command, dataSize, dataOffset")
    func derivedFields() {
        let packet = Packet(arg2: 7, arg3: 9, arg4: 42, arg5: 0)
        #expect(packet.command == 7)
        #expect(packet.dataSize == 42)
        #expect(packet.dataOffset == (UInt64(7) << 32 | 9))
    }

    @Test("dataOffset jenseits der 4-GB-Grenze")
    func dataOffsetBeyond4GB() {
        #expect(Packet(arg2: 1, arg3: 0).dataOffset == 4_294_967_296)
        #expect(Packet(arg2: 1, arg3: 1).dataOffset == 4_294_967_297)
        #expect(Packet(arg2: .max, arg3: .max).dataOffset == UInt64.max)
        #expect(Packet(arg2: 0, arg3: .max).dataOffset == 4_294_967_295)
    }

    @Test("Jedes einzelne gekippte Byte lässt decode werfen")
    func everyFlippedByteThrows() {
        let bytes = Packet(arg2: 0xDEAD_BEEF, arg3: 0x0102_0304, arg4: 55, arg5: 0xCAFE_F00D).encoded()
        for index in 0..<Packet.byteCount {
            var mutated = bytes
            mutated[index] ^= 0xFF
            #expect(throws: InstallError.self, "Byte \(index) gekippt") {
                _ = try Packet.decode(mutated)
            }
        }
    }

    @Test("Gekippte Magic-Bytes ergeben badMagic, Nutzdaten-Bytes checksumMismatch")
    func flipErrorKinds() {
        let bytes = Packet(arg2: 1, arg3: 2, arg4: 3, arg5: 4).encoded()
        for index in 0..<4 {
            var mutated = bytes
            mutated[index] ^= 0xFF
            #expect(throws: InstallError.badMagic) { _ = try Packet.decode(mutated) }
        }
        for index in 4..<Packet.byteCount {
            var mutated = bytes
            mutated[index] ^= 0xFF
            #expect(throws: InstallError.checksumMismatch) { _ = try Packet.decode(mutated) }
        }
    }

    @Test("Falsche Magic ergibt badMagic — auch mit passend nachgerechneter CRC")
    func wrongMagicWithValidCRC() {
        var bytes = Packet(arg2: 1).encoded()
        bytes[3] = 0x54 // Magic verändern …
        let crc = CRC32C.checksum(bytes.prefix(20))
        bytes[20] = UInt8(crc & 0xFF) // … und die CRC dazu passend machen
        bytes[21] = UInt8((crc >> 8) & 0xFF)
        bytes[22] = UInt8((crc >> 16) & 0xFF)
        bytes[23] = UInt8((crc >> 24) & 0xFF)
        #expect(throws: InstallError.badMagic) { _ = try Packet.decode(bytes) }
    }

    @Test("23 und 25 Bytes ergeben shortPacket")
    func wrongLengthThrowsShortPacket() {
        let valid = Packet(arg2: 9).encoded()
        #expect(throws: InstallError.shortPacket(expected: 24, got: 23)) {
            _ = try Packet.decode(Array(valid.prefix(23)))
        }
        #expect(throws: InstallError.shortPacket(expected: 24, got: 25)) {
            _ = try Packet.decode(valid + [0x00])
        }
        #expect(throws: InstallError.shortPacket(expected: 24, got: 0)) {
            _ = try Packet.decode([])
        }
    }

    @Test("Prüfreihenfolge: Länge vor Magic")
    func lengthCheckedBeforeMagic() {
        // Zu kurz UND falsche Magic → die Länge muss zuerst gemeldet werden.
        #expect(throws: InstallError.shortPacket(expected: 24, got: 4)) {
            _ = try Packet.decode([0xFF, 0xFF, 0xFF, 0xFF])
        }
    }
}
