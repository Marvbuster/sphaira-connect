//
//  LibUSBProbe.swift
//  Sphaira Connect
//
//  Rauchtest der libusb-Anbindung: prüft, ob die Bibliothek gelinkt ist und
//  ob eine Switch am Bus hängt. Wird von der Statusanzeige benutzt.
//

import Foundation

enum LibUSBProbe {
    static let vendorID: UInt16 = 0x057E
    static let productID: UInt16 = 0x3000

    static func version() -> String {
        guard let info = libusb_get_version() else { return "unbekannt" }
        let v = info.pointee
        return "\(v.major).\(v.minor).\(v.micro)"
    }

    static func isSwitchAttached() -> Bool {
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
}
