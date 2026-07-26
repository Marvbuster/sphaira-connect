//
//  USBTransport.swift
//  Sphaira Connect
//
//  Raw libusb binding to the Switch (Sphaira USB installer).
//  Everything here runs blocking on a background thread, hence
//  nonisolated throughout.
//

import Foundation

final class USBTransport: @unchecked Sendable {
    struct DeviceInfo: Sendable {
        let manufacturer: String
        let product: String
        let serial: String
    }

    nonisolated static let vendorID: UInt16 = 0x057E
    nonisolated static let productID: UInt16 = 0x3000

    // libusb error codes spelled out numerically, because depending on how the
    // C enum is imported its constants are not directly comparable to Int32.
    private nonisolated static let errorTimeout: Int32 = -7  // LIBUSB_ERROR_TIMEOUT
    private nonisolated static let errorAccess: Int32 = -3   // LIBUSB_ERROR_ACCESS
    private nonisolated static let errorNoDevice: Int32 = -4 // LIBUSB_ERROR_NO_DEVICE

    private nonisolated static let readTimeoutMS: UInt32 = 500
    /// More generous than for reads — a chunk is in flight, but it must not be
    /// able to hang forever, otherwise cancellation would have no effect.
    private nonisolated static let writeTimeoutMS: UInt32 = 5_000

    nonisolated(unsafe) private var context: OpaquePointer?
    nonisolated(unsafe) private var handle: OpaquePointer?
    nonisolated(unsafe) private var endpointIn: UInt8 = 0x81
    nonisolated(unsafe) private var endpointOut: UInt8 = 0x01
    nonisolated(unsafe) private var interfaceClaimed = false

    nonisolated init() {}

    deinit {
        close()
    }

    // MARK: - Device detection

    nonisolated static func isSwitchAttached() -> Bool {
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

    // MARK: - Connection

    nonisolated func open(cancel: () -> Bool) throws -> DeviceInfo {
        close()

        var newContext: OpaquePointer?
        let initResult = libusb_init(&newContext)
        guard initResult == 0 else {
            throw InstallError.usb(operation: "libusb_init", code: initResult)
        }
        context = newContext

        // Wait for the Switch; cancellation is checked between attempts.
        var deviceHandle: OpaquePointer?
        while deviceHandle == nil {
            if cancel() {
                close()
                throw InstallError.cancelled
            }
            deviceHandle = libusb_open_device_with_vid_pid(newContext, Self.vendorID, Self.productID)
            if deviceHandle == nil {
                usleep(250_000)
            }
        }
        handle = deviceHandle

        // Usually NOT_SUPPORTED on macOS — return value deliberately ignored.
        _ = libusb_set_auto_detach_kernel_driver(deviceHandle, 1)

        resolveEndpoints(deviceHandle: deviceHandle)

        let claimResult = libusb_claim_interface(deviceHandle, 0)
        guard claimResult == 0 else {
            close()
            if claimResult == Self.errorAccess { throw InstallError.accessDenied }
            throw InstallError.usb(operation: "libusb_claim_interface", code: claimResult)
        }
        interfaceClaimed = true

        var descriptor = libusb_device_descriptor()
        _ = libusb_get_device_descriptor(libusb_get_device(deviceHandle), &descriptor)
        return DeviceInfo(
            manufacturer: stringDescriptor(index: descriptor.iManufacturer, fallback: "Nintendo"),
            product: stringDescriptor(index: descriptor.iProduct, fallback: "Nintendo Switch"),
            serial: stringDescriptor(index: descriptor.iSerialNumber, fallback: String(localized: "unbekannt"))
        )
    }

    /// Releases the connection and returns immediately.
    ///
    /// The actual libusb teardown runs in the background: if the Switch has
    /// already torn the connection down on its side, `libusb_close` and
    /// `libusb_exit` can block. Since `close()` runs from a `defer` at the end of
    /// the session, that would hold back the completion message to the UI — the
    /// transfer would look "in progress" forever even though it has finished.
    nonisolated func close() {
        let openHandle = handle
        let openContext = context
        let wasClaimed = interfaceClaimed

        // Clear our own references first so a second call cannot free
        // anything twice.
        handle = nil
        context = nil
        interfaceClaimed = false

        guard openHandle != nil || openContext != nil else { return }

        DispatchQueue.global(qos: .utility).async {
            if let openHandle {
                if wasClaimed {
                    _ = libusb_release_interface(openHandle, 0)
                }
                libusb_close(openHandle)
            }
            if let openContext {
                libusb_exit(openContext)
            }
        }
    }

    // MARK: - Protocol

    nonisolated func readPacket(cancel: () -> Bool) throws -> Packet {
        let bytes = try read(count: Packet.byteCount, cancel: cancel)
        return try Packet.decode(bytes)
    }

    nonisolated func send(_ result: SphairaResult, arg3: UInt32, arg4: UInt32, cancel: () -> Bool) throws {
        let packet = Packet(arg2: result.rawValue, arg3: arg3, arg4: arg4)
        try write(packet.encoded(), cancel: cancel)
    }

    nonisolated func sendFileInfo(size: UInt64, flags: UInt32, cancel: () -> Bool) throws {
        let lsb = UInt32(truncatingIfNeeded: size)
        let msb = UInt32((size >> 32) & 0xFFFF) | (flags << 16)
        try send(.ok, arg3: msb, arg4: lsb, cancel: cancel)
    }

    // MARK: - Raw transfers

    nonisolated func write(_ bytes: [UInt8], cancel: () -> Bool) throws {
        guard let handle else {
            throw InstallError.usb(operation: "libusb_bulk_transfer(out)", code: Self.errorNoDevice)
        }
        var data = bytes
        var sent = 0
        try data.withUnsafeMutableBufferPointer { pointer in
            while sent < pointer.count {
                if cancel() { throw InstallError.cancelled }
                var transferred: Int32 = 0
                let remaining = Int32(clamping: pointer.count - sent)
                let code = libusb_bulk_transfer(
                    handle, endpointOut,
                    pointer.baseAddress! + sent, remaining,
                    &transferred, Self.writeTimeoutMS
                )
                // Finite timeout instead of waiting indefinitely: if the Switch
                // stalls mid-chunk, the session would otherwise be impossible to
                // cancel. Bytes may already have gone out even on a timeout.
                if code == 0 || code == Self.errorTimeout {
                    sent += Int(transferred)
                } else if code == Self.errorAccess {
                    throw InstallError.accessDenied
                } else {
                    throw InstallError.usb(operation: "libusb_bulk_transfer(out)", code: code)
                }
            }
        }
    }

    /// Reads exactly `count` bytes; a timeout is not an error, just an
    /// opportunity to check `cancel`.
    private nonisolated func read(count: Int, cancel: () -> Bool) throws -> [UInt8] {
        guard let handle else {
            throw InstallError.usb(operation: "libusb_bulk_transfer(in)", code: Self.errorNoDevice)
        }
        var buffer = [UInt8](repeating: 0, count: count)
        var received = 0
        try buffer.withUnsafeMutableBufferPointer { pointer in
            while received < count {
                if cancel() { throw InstallError.cancelled }
                var transferred: Int32 = 0
                let code = libusb_bulk_transfer(
                    handle, endpointIn,
                    pointer.baseAddress! + received, Int32(count - received),
                    &transferred, Self.readTimeoutMS
                )
                if code == 0 || code == Self.errorTimeout {
                    // Some bytes may have arrived even on a timeout.
                    received += Int(transferred)
                } else if code == Self.errorAccess {
                    throw InstallError.accessDenied
                } else {
                    throw InstallError.usb(operation: "libusb_bulk_transfer(in)", code: code)
                }
            }
        }
        return buffer
    }

    // MARK: - Helpers

    /// Endpoints taken from the active configuration; the first IN and the first
    /// OUT endpoint win. With no match the fallback stays 0x81/0x01.
    private nonisolated func resolveEndpoints(deviceHandle: OpaquePointer?) {
        var config: UnsafeMutablePointer<libusb_config_descriptor>?
        guard libusb_get_active_config_descriptor(libusb_get_device(deviceHandle), &config) == 0,
              let config else { return }
        defer { libusb_free_config_descriptor(config) }

        var foundIn: UInt8?
        var foundOut: UInt8?
        for interfaceIndex in 0..<Int(config.pointee.bNumInterfaces) {
            let interface = config.pointee.interface[interfaceIndex]
            for altIndex in 0..<Int(interface.num_altsetting) {
                let altsetting = interface.altsetting[altIndex]
                for endpointIndex in 0..<Int(altsetting.bNumEndpoints) {
                    let address = altsetting.endpoint[endpointIndex].bEndpointAddress
                    if address & 0x80 != 0 {
                        if foundIn == nil { foundIn = address }
                    } else if foundOut == nil {
                        foundOut = address
                    }
                }
            }
        }
        if let foundIn { endpointIn = foundIn }
        if let foundOut { endpointOut = foundOut }
    }

    private nonisolated func stringDescriptor(index: UInt8, fallback: String) -> String {
        guard index != 0, let handle else { return fallback }
        var buffer = [UInt8](repeating: 0, count: 256)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            libusb_get_string_descriptor_ascii(handle, index, pointer.baseAddress, Int32(pointer.count))
        }
        guard length > 0 else { return fallback }
        let text = String(decoding: buffer[0..<Int(length)], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }
}
