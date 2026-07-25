import Foundation
import Testing
@testable import SphairaCore

@Suite("InstallError")
struct InstallErrorTests {
    private static let allCases: [InstallError] = [
        .switchNotFound,
        .accessDenied,
        .usb(operation: "bulk_transfer", code: -7),
        .shortPacket(expected: 24, got: 3),
        .badMagic,
        .checksumMismatch,
        .unexpectedCommand(99),
        .fileUnreadable(path: "/tmp/x.nsp", reason: "kein Zugriff"),
        .cancelled,
    ]

    @Test("Jeder Fall liefert einen nicht leeren deutschen Klartext")
    func descriptionsPresent() {
        for error in Self.allCases {
            let text = error.errorDescription
            #expect(text != nil)
            #expect(text?.isEmpty == false)
        }
    }

    @Test("Assoziierte Werte erscheinen im Klartext")
    func associatedValuesInText() {
        #expect(InstallError.usb(operation: "claim", code: -3).errorDescription?.contains("claim") == true)
        #expect(InstallError.usb(operation: "claim", code: -3).errorDescription?.contains("-3") == true)
        #expect(InstallError.shortPacket(expected: 24, got: 7).errorDescription?.contains("24") == true)
        #expect(InstallError.shortPacket(expected: 24, got: 7).errorDescription?.contains("7") == true)
        #expect(InstallError.unexpectedCommand(42).errorDescription?.contains("42") == true)
        #expect(InstallError.fileUnreadable(path: "/a/b.nsp", reason: "weg").errorDescription?.contains("/a/b.nsp") == true)
    }

    @Test("Equatable unterscheidet Fälle und assoziierte Werte")
    func equatable() {
        #expect(InstallError.badMagic == InstallError.badMagic)
        #expect(InstallError.badMagic != InstallError.checksumMismatch)
        #expect(InstallError.usb(operation: "a", code: 1) != InstallError.usb(operation: "a", code: 2))
        #expect(InstallError.shortPacket(expected: 24, got: 23) != InstallError.shortPacket(expected: 24, got: 25))
    }
}
