import Foundation

nonisolated enum RCMTransportError: LocalizedError {
    case deviceNotFound
    case accessDenied
    case usb(operation: String, code: Int32)
    case shortTransfer(operation: String, expected: Int, got: Int)
    case exploitNotTriggered(received: Int32)

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return String(localized: "Keine Switch im RCM-Modus gefunden.")
        case .accessDenied:
            return String(localized: "Zugriff auf die RCM-Switch verweigert. Wird sie von einer anderen App verwendet?")
        case let .usb(operation, code):
            return String(localized: "RCM-USB-Fehler bei „\(operation)“ (Code \(code)).")
        case let .shortTransfer(operation, expected, got):
            return String(localized: "Unvollständige RCM-Übertragung bei „\(operation)“: \(got) von \(expected) Bytes.")
        case let .exploitNotTriggered(received):
            return String(localized: "Die Switch antwortete auf den Exploit-Request (\(received) Bytes). Das Gerät ist möglicherweise gepatcht.")
        }
    }
}

/// Blocking libusb transport for a Nintendo Switch in Tegra recovery mode.
final class RCMTransport: @unchecked Sendable {
    nonisolated static let vendorID: UInt16 = 0x0955
    nonisolated static let productID: UInt16 = 0x7321

    private nonisolated static let endpointOut: UInt8 = 0x01
    private nonisolated static let endpointIn: UInt8 = 0x81
    private nonisolated static let interfaceNumber: Int32 = 0
    private nonisolated static let timeoutMS: UInt32 = 5_000
    private nonisolated static let errorAccess: Int32 = -3
    private nonisolated static let errorNoDevice: Int32 = -4

    nonisolated init() {}

    nonisolated static func isRCMAttached() -> Bool {
        var context: OpaquePointer?
        guard libusb_init(&context) == 0 else { return false }
        defer { libusb_exit(context) }

        var list: UnsafeMutablePointer<OpaquePointer?>?
        let count = libusb_get_device_list(context, &list)
        guard count > 0, let list else { return false }
        defer { libusb_free_device_list(list, 1) }

        for index in 0..<Int(count) {
            guard let device = list[index] else { continue }
            var descriptor = libusb_device_descriptor()
            guard libusb_get_device_descriptor(device, &descriptor) == 0 else { continue }
            if descriptor.idVendor == vendorID, descriptor.idProduct == productID {
                return true
            }
        }
        return false
    }

    /// Sends an already prepared RCM image and manually triggers Fusée Gelée.
    ///
    /// A disconnect while handling the final control transfer is the expected
    /// success signal: the boot ROM has left USB recovery and started the image.
    nonisolated func inject(
        image: [UInt8],
        onDeviceID: (String) -> Void,
        onProgress: (Int, Int) -> Void
    ) throws {
        var context: OpaquePointer?
        let initResult = libusb_init(&context)
        guard initResult == 0 else {
            throw RCMTransportError.usb(operation: "libusb_init", code: initResult)
        }
        defer { libusb_exit(context) }

        guard let handle = libusb_open_device_with_vid_pid(
            context, Self.vendorID, Self.productID
        ) else {
            throw RCMTransportError.deviceNotFound
        }
        defer { libusb_close(handle) }

        _ = libusb_set_auto_detach_kernel_driver(handle, 1)
        let claimResult = libusb_claim_interface(handle, Self.interfaceNumber)
        guard claimResult == 0 else {
            if claimResult == Self.errorAccess { throw RCMTransportError.accessDenied }
            throw RCMTransportError.usb(operation: "libusb_claim_interface", code: claimResult)
        }
        defer { _ = libusb_release_interface(handle, Self.interfaceNumber) }

        let deviceID = try readExactly(16, from: handle)
        onDeviceID(deviceID.map { String(format: "%02x", $0) }.joined())

        let total = RCMPayloadBuilder.transmittedByteCount(imageByteCount: image.count)
        var sent = 0
        for chunkStart in stride(from: 0, to: image.count, by: RCMPayloadBuilder.packetSize) {
            let chunkEnd = min(chunkStart + RCMPayloadBuilder.packetSize, image.count)
            try writeExactly(Array(image[chunkStart..<chunkEnd]), to: handle)
            sent += chunkEnd - chunkStart
            onProgress(sent, total)
        }

        if RCMPayloadBuilder.requiresParityPadding(imageByteCount: image.count) {
            try writeExactly([UInt8](repeating: 0, count: RCMPayloadBuilder.packetSize), to: handle)
            sent += RCMPayloadBuilder.packetSize
            onProgress(sent, total)
        }

        var triggerBuffer = [UInt8](repeating: 0, count: 0x7000)
        let result = triggerBuffer.withUnsafeMutableBufferPointer { buffer in
            libusb_control_transfer(
                handle,
                0x81, // device-to-host, standard, interface
                0,
                0,
                0,
                buffer.baseAddress,
                UInt16(buffer.count),
                1_000
            )
        }

        // A normal response means a patched boot ROM (or a request that never
        // reached the vulnerable path). Timeout/disconnect-style errors mean
        // the vulnerable boot ROM vanished while starting the payload.
        switch RCMTriggerOutcome.classify(result) {
        case .payloadStarted:
            return
        case let .deviceResponded(received):
            throw RCMTransportError.exploitNotTriggered(received: received)
        case let .usbFailure(code):
            throw RCMTransportError.usb(
                operation: String(localized: "Exploit auslösen"),
                code: code
            )
        }
    }

    private nonisolated func readExactly(_ count: Int, from handle: OpaquePointer?) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        var received = 0
        let operation = String(localized: "Geräte-ID lesen")
        try bytes.withUnsafeMutableBufferPointer { buffer in
            while received < count {
                var transferred: Int32 = 0
                let result = libusb_bulk_transfer(
                    handle,
                    Self.endpointIn,
                    buffer.baseAddress! + received,
                    Int32(count - received),
                    &transferred,
                    Self.timeoutMS
                )
                if result != 0 {
                    throw usbError(result, operation: operation)
                }
                guard transferred > 0 else {
                    throw RCMTransportError.shortTransfer(
                        operation: operation, expected: count, got: received
                    )
                }
                received += Int(transferred)
            }
        }
        return bytes
    }

    private nonisolated func writeExactly(_ bytes: [UInt8], to handle: OpaquePointer?) throws {
        var mutableBytes = bytes
        var written = 0
        let operation = String(localized: "Payload senden")
        try mutableBytes.withUnsafeMutableBufferPointer { buffer in
            while written < buffer.count {
                var transferred: Int32 = 0
                let result = libusb_bulk_transfer(
                    handle,
                    Self.endpointOut,
                    buffer.baseAddress! + written,
                    Int32(buffer.count - written),
                    &transferred,
                    Self.timeoutMS
                )
                if result != 0 {
                    throw usbError(result, operation: operation)
                }
                guard transferred > 0 else {
                    throw RCMTransportError.shortTransfer(
                        operation: operation, expected: buffer.count, got: written
                    )
                }
                written += Int(transferred)
            }
        }
    }

    private nonisolated func usbError(_ code: Int32, operation: String) -> RCMTransportError {
        if code == Self.errorAccess { return .accessDenied }
        if code == Self.errorNoDevice { return .deviceNotFound }
        return .usb(operation: operation, code: code)
    }
}
