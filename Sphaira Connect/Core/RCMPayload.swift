import Foundation

/// Errors raised while turning a user-selected payload into the image expected
/// by the Tegra recovery boot ROM.
nonisolated enum RCMPayloadError: LocalizedError, Equatable {
    case empty
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .empty:
            return String(localized: "Die Payload-Datei ist leer.")
        case .tooLarge:
            return String(localized: "Die Payload-Datei ist zu groß.")
        }
    }
}

/// Builds the Fusée Gelée RCM image without touching USB.
///
/// Keeping this transformation in Core makes every byte of the layout testable
/// without a connected console. The small intermezzo relocator is the standard
/// permissively licensed implementation used by fusee-launcher and ironfoil.
nonisolated enum RCMPayloadBuilder {
    static let packetSize = 0x1000

    private static let intermezzo: [UInt8] = [
        0x44, 0x00, 0x9f, 0xe5, 0x01, 0x11, 0xa0, 0xe3, 0x40, 0x20, 0x9f, 0xe5, 0x00, 0x20, 0x42, 0xe0,
        0x08, 0x00, 0x00, 0xeb, 0x01, 0x01, 0xa0, 0xe3, 0x10, 0xff, 0x2f, 0xe1, 0x00, 0x00, 0xa0, 0xe1,
        0x2c, 0x00, 0x9f, 0xe5, 0x2c, 0x10, 0x9f, 0xe5, 0x02, 0x28, 0xa0, 0xe3, 0x01, 0x00, 0x00, 0xeb,
        0x20, 0x00, 0x9f, 0xe5, 0x10, 0xff, 0x2f, 0xe1, 0x04, 0x30, 0x90, 0xe4, 0x04, 0x30, 0x81, 0xe4,
        0x04, 0x20, 0x52, 0xe2, 0xfb, 0xff, 0xff, 0x1a, 0x1e, 0xff, 0x2f, 0xe1, 0x20, 0xf0, 0x01, 0x40,
        0x5c, 0xf0, 0x01, 0x40, 0x00, 0x00, 0x02, 0x40, 0x00, 0x00, 0x01, 0x40,
    ]

    private static let rcmLength: UInt32 = 0x30298
    private static let payloadAddress: UInt32 = 0x4001_0000
    private static let intermezzoLocation: UInt32 = 0x4001_F000
    private static let addressTableOffset = 0x2A8
    private static let addressRepeatCount =
        Int((intermezzoLocation - payloadAddress) / UInt32(MemoryLayout<UInt32>.size))

    static let userPayloadOffset = addressTableOffset
        + addressRepeatCount * MemoryLayout<UInt32>.size
        + packetSize

    static func build(userPayload: [UInt8]) throws -> [UInt8] {
        guard !userPayload.isEmpty else { throw RCMPayloadError.empty }
        guard userPayload.count <= Int.max - userPayloadOffset - (packetSize - 1) else {
            throw RCMPayloadError.tooLarge
        }

        let unalignedSize = userPayloadOffset + userPayload.count
        let imageSize = ((unalignedSize + packetSize - 1) / packetSize) * packetSize
        var image = [UInt8](repeating: 0, count: imageSize)

        writeLittleEndian(rcmLength, into: &image, at: 0)
        for index in 0..<addressRepeatCount {
            writeLittleEndian(
                intermezzoLocation,
                into: &image,
                at: addressTableOffset + index * MemoryLayout<UInt32>.size
            )
        }

        let intermezzoOffset = addressTableOffset + addressRepeatCount * MemoryLayout<UInt32>.size
        image.replaceSubrange(intermezzoOffset..<(intermezzoOffset + intermezzo.count), with: intermezzo)
        image.replaceSubrange(
            userPayloadOffset..<(userPayloadOffset + userPayload.count),
            with: userPayload
        )
        return image
    }

    static func requiresParityPadding(imageByteCount: Int) -> Bool {
        let packetCount = imageByteCount / packetSize
        return packetCount.isMultiple(of: 2)
    }

    static func transmittedByteCount(imageByteCount: Int) -> Int {
        imageByteCount + (requiresParityPadding(imageByteCount: imageByteCount) ? packetSize : 0)
    }

    private static func writeLittleEndian(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}
