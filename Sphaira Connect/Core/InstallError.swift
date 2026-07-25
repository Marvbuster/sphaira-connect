import Foundation

nonisolated enum InstallError: LocalizedError, Equatable {
    case switchNotFound
    case accessDenied
    case usb(operation: String, code: Int32)
    case shortPacket(expected: Int, got: Int)
    case badMagic
    case checksumMismatch
    case unexpectedCommand(UInt32)
    case fileUnreadable(path: String, reason: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .switchNotFound:
            return "Keine Switch gefunden. Ist Sphaira im USB-Modus gestartet?"
        case .accessDenied:
            return "Zugriff auf das USB-Gerät verweigert. Bitte Berechtigungen prüfen."
        case let .usb(operation, code):
            return "USB-Fehler bei „\(operation)“ (Code \(code))."
        case let .shortPacket(expected, got):
            return "Paket zu kurz: \(expected) Bytes erwartet, \(got) erhalten."
        case .badMagic:
            return "Ungültige Paketkennung — Antwort stammt nicht von Sphaira."
        case .checksumMismatch:
            return "Prüfsummenfehler im empfangenen Paket."
        case let .unexpectedCommand(command):
            return "Unerwarteter Befehl von der Switch: \(command)."
        case let .fileUnreadable(path, reason):
            return "Datei nicht lesbar: \(path) (\(reason))."
        case .cancelled:
            return "Übertragung abgebrochen."
        }
    }
}
