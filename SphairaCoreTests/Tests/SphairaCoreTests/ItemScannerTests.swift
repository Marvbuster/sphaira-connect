import Foundation
import Testing
@testable import SphairaCore

@Suite("ItemScanner")
struct ItemScannerTests {
    /// Legt eine temporäre Ordnerstruktur an und räumt sie nach dem Testlauf ab.
    private func withFixture<T>(_ body: (URL) throws -> T) throws -> T {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SphairaScannerTests-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Verschachtelte Ordner, gemischte Endungen (auch groß), Nicht-Installierbares
        try fm.createDirectory(at: root.appendingPathComponent("sub/deep"), withIntermediateDirectories: true)
        let files: [(String, Int)] = [
            ("alpha.nsp", 100),
            ("Bravo.XCI", 200),              // Großschreibung der Endung
            ("sub/charlie.nsz", 300),
            ("sub/deep/delta.xcz", 400),
            ("sub/deep/echo.NSP", 500),      // Großschreibung, tief verschachtelt
            ("notes.txt", 10),               // nicht installierbar
            ("sub/README.md", 20),           // nicht installierbar
            ("sub/deep/archive.zip", 30),    // nicht installierbar
            ("noextension", 40),             // keine Endung
        ]
        for (path, size) in files {
            let data = Data(repeating: 0xAB, count: size)
            try data.write(to: root.appendingPathComponent(path))
        }
        return try body(root)
    }

    @Test("Rekursion, Endungsfilter und Groß-/Kleinschreibung")
    func recursionAndFilter() throws {
        try withFixture { root in
            let items = ItemScanner.scan([root])
            #expect(items.map(\.displayName) == [
                "alpha.nsp", "Bravo.XCI", "charlie.nsz", "delta.xcz", "echo.NSP",
            ])
        }
    }

    @Test("byteCount entspricht der tatsächlichen Dateigröße")
    func byteCounts() throws {
        try withFixture { root in
            let items = ItemScanner.scan([root])
            let sizes = Dictionary(uniqueKeysWithValues: items.map { ($0.displayName, $0.byteCount) })
            #expect(sizes["alpha.nsp"] == 100)
            #expect(sizes["Bravo.XCI"] == 200)
            #expect(sizes["charlie.nsz"] == 300)
            #expect(sizes["delta.xcz"] == 400)
            #expect(sizes["echo.NSP"] == 500)
        }
    }

    @Test("Duplikate (gleicher Pfad) entfallen")
    func duplicatesRemoved() throws {
        try withFixture { root in
            let file = root.appendingPathComponent("alpha.nsp")
            // Ordner + zweimal dieselbe Datei, einmal davon unnormalisiert
            let unnormalized = root.appendingPathComponent("sub/../alpha.nsp")
            let items = ItemScanner.scan([root, file, unnormalized, root])
            #expect(items.count == 5)
            #expect(items.filter { $0.displayName == "alpha.nsp" }.count == 1)
        }
    }

    @Test("Einzelne Datei-URLs funktionieren ohne Ordner")
    func directFileURLs() throws {
        try withFixture { root in
            let items = ItemScanner.scan([
                root.appendingPathComponent("sub/charlie.nsz"),
                root.appendingPathComponent("alpha.nsp"),
            ])
            // Stabil alphabetisch, unabhängig von der Übergabereihenfolge
            #expect(items.map(\.displayName) == ["alpha.nsp", "charlie.nsz"])
        }
    }

    @Test("Nicht installierbare Datei direkt übergeben wird ignoriert")
    func directNonInstallableIgnored() throws {
        try withFixture { root in
            #expect(ItemScanner.scan([root.appendingPathComponent("notes.txt")]).isEmpty)
        }
    }

    @Test("Nicht existierende URL ergibt leeres Ergebnis")
    func missingURL() {
        let ghost = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)/x.nsp")
        #expect(ItemScanner.scan([ghost]).isEmpty)
        #expect(ItemScanner.scan([]).isEmpty)
    }

    @Test("Unlesbare Datei wird übersprungen statt zu scheitern")
    func unreadableFileSkipped() throws {
        try withFixture { root in
            let locked = root.appendingPathComponent("locked.nsp")
            try Data(repeating: 0, count: 50).write(to: locked)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
            }
            let items = ItemScanner.scan([root])
            #expect(!items.contains { $0.displayName == "locked.nsp" })
            #expect(items.count == 5)
        }
    }

    @Test("Neue Items starten im Zustand queued mit displayName = Dateiname")
    func initialItemState() {
        let item = InstallItem(url: URL(fileURLWithPath: "/tmp/Homebrew Launcher.nsp"), byteCount: 123)
        #expect(item.state == .queued)
        #expect(item.displayName == "Homebrew Launcher.nsp")
        #expect(item.byteCount == 123)
    }

    @Test("Vertragskonstante installableExtensions")
    func extensionsConstant() {
        #expect(ItemScanner.installableExtensions == ["nsp", "xci", "nsz", "xcz"])
    }
}
