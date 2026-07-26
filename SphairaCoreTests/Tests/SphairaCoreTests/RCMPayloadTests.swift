import Testing
@testable import SphairaCore

@Suite("RCM payload builder")
struct RCMPayloadTests {
    @Test("An empty user payload is rejected")
    func rejectsEmptyPayload() {
        #expect(throws: RCMPayloadError.empty) {
            try RCMPayloadBuilder.build(userPayload: [])
        }
    }

    @Test("Image contains header, address table, intermezzo and user bytes")
    func buildsExpectedLayout() throws {
        let userPayload: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE]
        let image = try RCMPayloadBuilder.build(userPayload: userPayload)

        #expect(Array(image[0..<4]) == [0x98, 0x02, 0x03, 0x00])
        #expect(Array(image[0x2A8..<0x2AC]) == [0x00, 0xF0, 0x01, 0x40])
        #expect(Array(image[0xF2A8..<0xF2AC]) == [0x44, 0x00, 0x9F, 0xE5])
        let userStart = RCMPayloadBuilder.userPayloadOffset
        let userEnd = userStart + userPayload.count
        #expect(Array(image[userStart..<userEnd]) == userPayload)
        #expect(image.count.isMultiple(of: RCMPayloadBuilder.packetSize))
    }

    @Test("Transfer size adds one packet only for an even packet count")
    func parityPadding() {
        let packet = RCMPayloadBuilder.packetSize

        #expect(RCMPayloadBuilder.requiresParityPadding(imageByteCount: packet * 2))
        #expect(RCMPayloadBuilder.transmittedByteCount(imageByteCount: packet * 2) == packet * 3)
        #expect(!RCMPayloadBuilder.requiresParityPadding(imageByteCount: packet * 3))
        #expect(RCMPayloadBuilder.transmittedByteCount(imageByteCount: packet * 3) == packet * 3)
    }
}
