import Foundation
import Testing
@testable import SphairaCore

@Suite("ItemScanner")
struct ItemScannerTests {
    /// Creates a temporary directory tree and tears it down after the test run.
    private func withFixture<T>(_ body: (URL) throws -> T) throws -> T {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SphairaScannerTests-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Nested directories, mixed extensions (including uppercase), non-installable files
        try fm.createDirectory(at: root.appendingPathComponent("sub/deep"), withIntermediateDirectories: true)
        let files: [(String, Int)] = [
            ("alpha.nsp", 100),
            ("Bravo.XCI", 200),              // uppercase extension
            ("sub/charlie.nsz", 300),
            ("sub/deep/delta.xcz", 400),
            ("sub/deep/echo.NSP", 500),      // uppercase, deeply nested
            ("notes.txt", 10),               // not installable
            ("sub/README.md", 20),           // not installable
            ("sub/deep/archive.zip", 30),    // not installable
            ("noextension", 40),             // no extension
        ]
        for (path, size) in files {
            let data = Data(repeating: 0xAB, count: size)
            try data.write(to: root.appendingPathComponent(path))
        }
        return try body(root)
    }

    @Test("Recursion, extension filter and case insensitivity")
    func recursionAndFilter() throws {
        try withFixture { root in
            let items = ItemScanner.scan([root])
            #expect(items.map(\.displayName) == [
                "alpha.nsp", "Bravo.XCI", "charlie.nsz", "delta.xcz", "echo.NSP",
            ])
        }
    }

    @Test("byteCount matches the actual file size")
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

    @Test("Duplicates (same path) are dropped")
    func duplicatesRemoved() throws {
        try withFixture { root in
            let file = root.appendingPathComponent("alpha.nsp")
            // Directory + the same file twice, one of them unnormalized
            let unnormalized = root.appendingPathComponent("sub/../alpha.nsp")
            let items = ItemScanner.scan([root, file, unnormalized, root])
            #expect(items.count == 5)
            #expect(items.filter { $0.displayName == "alpha.nsp" }.count == 1)
        }
    }

    @Test("Individual file URLs work without a directory")
    func directFileURLs() throws {
        try withFixture { root in
            let items = ItemScanner.scan([
                root.appendingPathComponent("sub/charlie.nsz"),
                root.appendingPathComponent("alpha.nsp"),
            ])
            // Stable alphabetical order, regardless of the order passed in
            #expect(items.map(\.displayName) == ["alpha.nsp", "charlie.nsz"])
        }
    }

    @Test("A non-installable file passed in directly is ignored")
    func directNonInstallableIgnored() throws {
        try withFixture { root in
            #expect(ItemScanner.scan([root.appendingPathComponent("notes.txt")]).isEmpty)
        }
    }

    @Test("A non-existent URL yields an empty result")
    func missingURL() {
        let ghost = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)/x.nsp")
        #expect(ItemScanner.scan([ghost]).isEmpty)
        #expect(ItemScanner.scan([]).isEmpty)
    }

    @Test("An unreadable file is skipped instead of failing")
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

    @Test("New items start in the queued state with displayName = file name")
    func initialItemState() {
        let item = InstallItem(url: URL(fileURLWithPath: "/tmp/Homebrew Launcher.nsp"), byteCount: 123)
        #expect(item.state == .queued)
        #expect(item.displayName == "Homebrew Launcher.nsp")
        #expect(item.byteCount == 123)
    }

    @Test("Contract constant installableExtensions")
    func extensionsConstant() {
        #expect(ItemScanner.installableExtensions == ["nsp", "xci", "nsz", "xcz"])
    }
}
