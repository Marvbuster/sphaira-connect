//
//  DeviceSerial.swift
//  Sphaira Connect
//
//  Normalises the USB serial string descriptor reported by the Switch.
//

import Foundation

/// The homebrew USB stack on the Switch (libnx `usbComms`) defaults its string
/// descriptors to manufacturer "Nintendo", product "Nintendo Switch" and —
/// literally — serial "SerialNumber". Sphaira overrides the serial with the
/// console's real one (`XAJ4…`); apps that keep the default (Awoo, Tinfoil, …)
/// present the placeholder. Shown as if it were a value ("Seriennummer
/// SerialNumber") it reads like a broken format string, so it is filtered out
/// here — and its presence doubles as a hint that Sphaira is not the app
/// currently holding the USB interface.
nonisolated enum DeviceSerial {
    /// The literal placeholder libnx reports instead of a serial number.
    static let placeholder = "SerialNumber"

    /// Whether the descriptor is the libnx default. Sphaira reports the real
    /// serial; seeing the placeholder is a strong hint that a different app
    /// (Awoo, Tinfoil, …) is running on the console.
    static func isPlaceholder(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(placeholder) == .orderedSame
    }

    /// Returns the serial for display, or `nil` if the descriptor is missing,
    /// empty or the libnx placeholder.
    static func display(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.caseInsensitiveCompare(placeholder) != .orderedSame else { return nil }
        return trimmed
    }
}
