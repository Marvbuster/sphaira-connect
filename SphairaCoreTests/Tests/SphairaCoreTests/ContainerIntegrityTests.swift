import CryptoKit
import Foundation
import Testing
@testable import SphairaCore

/// Builds tiny but structurally faithful NSP (PFS0) and XCI (HFS0) containers.
private enum Fixture {
    static func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
    static func le64(_ v: UInt64) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    /// Deterministic pseudo-random bytes — stands in for encrypted NCA content.
    static func noise(_ count: Int, seed: UInt8 = 1) -> Data {
        var state: UInt32 = 0x9E37_79B9 &+ UInt32(seed)
        var out = Data(capacity: count)
        for _ in 0..<count {
            state = state &* 1_664_525 &+ 1_013_904_223
            out.append(UInt8(truncatingIfNeeded: state >> 24))
        }
        return out
    }

    static func pfs0(_ files: [(String, Data)]) -> Data {
        var names = Data()
        var table = Data()
        var body = Data()
        for (name, content) in files {
            table += le64(UInt64(body.count)) + le64(UInt64(content.count)) + le32(UInt32(names.count)) + le32(0)
            names += Data(name.utf8) + [0]
            body += content
        }
        // Xcode's hactool-style tools pad the string table to 0x20; not required.
        return Data("PFS0".utf8) + le32(UInt32(files.count)) + le32(UInt32(names.count)) + le32(0) + table + names + body
    }

    /// HFS0 partition: every entry hashes its first `hashedSize` bytes.
    static func hfs0(_ files: [(String, Data)], hashedSize: (Data) -> Int = { _ in 0x200 }) -> Data {
        var names = Data()
        var table = Data()
        var body = Data()
        for (name, content) in files {
            let hashed = min(hashedSize(content), content.count)
            let digest = Data(SHA256.hash(data: content.prefix(hashed)))
            table += le64(UInt64(body.count)) + le64(UInt64(content.count)) + le32(UInt32(names.count))
                + le32(UInt32(hashed)) + le64(0) + digest
            names += Data(name.utf8) + [0]
            body += content
        }
        return Data("HFS0".utf8) + le32(UInt32(files.count)) + le32(UInt32(names.count)) + le32(0) + table + names + body
    }

    /// Gamecard image with a root HFS0 at 0xF000 holding the given partitions.
    static func xci(partitions: [(String, Data)]) -> Data {
        // The root entry hashes each partition's header (header + table + names),
        // not its content — exactly like a real gamecard.
        let root = hfs0(partitions, hashedSize: { partition in
            let count = Int(partition[4]) | Int(partition[5]) << 8
            let names = Int(partition[8]) | Int(partition[9]) << 8
            return 0x10 + count * 0x40 + names
        })
        let rootHeaderSize = 0x10 + partitions.count * 0x40 + partitions.reduce(0) { $0 + $1.0.utf8.count + 1 }
        var image = Data(count: 0xF000)
        image.replaceSubrange(0x100..<0x104, with: Data("HEAD".utf8))
        image.replaceSubrange(0x130..<0x138, with: le64(0xF000))
        image.replaceSubrange(0x138..<0x140, with: le64(UInt64(rootHeaderSize)))
        image += root
        return image
    }

    static func write(_ data: Data, name: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SphairaIntegrityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
}

@Suite("ContainerIntegrity")
struct ContainerIntegrityTests {
    private let program = Fixture.noise(0x3000, seed: 1)
    private let control = Fixture.noise(0x1000, seed: 2)
    private let cnmt = Fixture.noise(0xE00, seed: 3)

    // MARK: NSP

    @Test("healthy NSP is ok, all entries examined")
    func nspOK() throws {
        let url = try Fixture.write(Fixture.pfs0([
            ("aaa.nca", program), ("bbb.nca", control), ("ccc.cnmt.nca", cnmt),
            ("ccc.cnmt.xml", Data("<xml/>".utf8)), ("ddd.tik", Fixture.noise(0x2C0)),
        ]), name: "game.nsp")
        let report = ContainerIntegrity.check(url: url, deep: true)
        #expect(report.verdict == .ok)
        #expect(report.entriesChecked == 5)
    }

    @Test("NSP with a zeroed NCA head is corrupt (the Super Mario Wonder case, NSP flavour)")
    func nspZeroHead() throws {
        var damaged = cnmt
        damaged.replaceSubrange(0..<0x200, with: Data(count: 0x200))
        let url = try Fixture.write(Fixture.pfs0([("aaa.nca", program), ("ccc.cnmt.nca", damaged)]), name: "game.nsp")
        guard case .corrupt(let reason) = ContainerIntegrity.check(url: url, deep: false).verdict else {
            Issue.record("expected corrupt"); return
        }
        #expect(reason.contains("ccc.cnmt.nca"))
    }

    @Test("NSP truncated behind the directory is corrupt")
    func nspTruncated() throws {
        let full = Fixture.pfs0([("aaa.nca", program), ("bbb.nca", control)])
        let url = try Fixture.write(full.prefix(full.count - 0x800), name: "game.nsp")
        guard case .corrupt(let reason) = ContainerIntegrity.check(url: url, deep: false).verdict else {
            Issue.record("expected corrupt"); return
        }
        #expect(reason.contains("bbb.nca"))
    }

    @Test("deep pass: a long zero run inside an NCA is a warning, a short one is not")
    func nspZeroRun() throws {
        let threshold = Int(ContainerIntegrity.zeroRunThreshold)
        var holed = Fixture.noise(threshold * 3, seed: 4)
        holed.replaceSubrange(0x400..<(0x400 + threshold), with: Data(count: threshold))
        let url = try Fixture.write(Fixture.pfs0([("aaa.nca", holed)]), name: "game.nsp")
        guard case .warning(let reason) = ContainerIntegrity.check(url: url, deep: true).verdict else {
            Issue.record("expected warning"); return
        }
        #expect(reason.contains("aaa.nca"))
        // Without the deep pass the head looks fine and nothing is flagged.
        #expect(ContainerIntegrity.check(url: url, deep: false).verdict == .ok)

        var small = Fixture.noise(threshold * 3, seed: 5)
        small.replaceSubrange(0x400..<(0x400 + threshold / 2), with: Data(count: threshold / 2))
        let smallURL = try Fixture.write(Fixture.pfs0([("aaa.nca", small)]), name: "game.nsp")
        #expect(ContainerIntegrity.check(url: smallURL, deep: true).verdict == .ok)
    }

    @Test("deep pass reports progress and honours cancellation")
    func deepProgressAndCancel() throws {
        let url = try Fixture.write(Fixture.pfs0([("aaa.nca", Fixture.noise(0x20000, seed: 6))]), name: "game.nsp")
        var seen: [Double] = []
        let report = ContainerIntegrity.check(url: url, deep: true, progress: { seen.append($0) })
        #expect(report.verdict == .ok)
        #expect(seen.last == 1)

        let cancelled = ContainerIntegrity.check(url: url, deep: true, cancel: { true })
        guard case .notVerifiable = cancelled.verdict else { Issue.record("expected notVerifiable"); return }
    }

    // MARK: XCI

    private func secure(_ cnmtData: Data? = nil, control controlData: Data? = nil) -> Data {
        Fixture.hfs0([
            ("60a0.nca", program), ("c319.nca", controlData ?? control), ("4ac1.cnmt.nca", cnmtData ?? cnmt),
        ])
    }

    @Test("healthy XCI verifies every hash")
    func xciOK() throws {
        let image = Fixture.xci(partitions: [
            ("update", Fixture.hfs0([("u1.nca", Fixture.noise(0x800, seed: 7))])),
            ("normal", Fixture.hfs0([])),
            ("secure", secure()),
        ])
        let report = ContainerIntegrity.check(url: try Fixture.write(image, name: "game.xci"), deep: true)
        #expect(report.verdict == .ok)
        #expect(report.entriesChecked == 4)
    }

    @Test("XCI whose secure partition NCAs were zeroed is corrupt (the Super Mario Wonder dump)")
    func xciZeroedSecure() throws {
        // Hashes are computed over the healthy content, then the file is holed.
        let healthy = secure()
        let image = Fixture.xci(partitions: [("secure", healthy)])
        var holed = image
        let secureStart = image.count - healthy.count
        let cnmtStart = secureStart + healthy.count - cnmt.count
        holed.replaceSubrange(cnmtStart..<(cnmtStart + cnmt.count), with: Data(count: cnmt.count))
        guard case .corrupt(let reason) = ContainerIntegrity.check(url: try Fixture.write(holed, name: "game.xci"), deep: false).verdict else {
            Issue.record("expected corrupt"); return
        }
        #expect(reason.contains("secure/4ac1.cnmt.nca"))
    }

    @Test("hash damage in the update partition is only a warning")
    func xciDamagedUpdate() throws {
        let updateContent = Fixture.noise(0x800, seed: 8)
        let update = Fixture.hfs0([("u1.nca", updateContent)])
        let image = Fixture.xci(partitions: [("update", update), ("secure", secure())])
        var damaged = image
        // Flip a byte inside u1.nca's hashed head: it sits right after the update header.
        let updateStart = image.count - secure().count - update.count
        let u1Start = updateStart + (update.count - updateContent.count)
        damaged[u1Start + 5] ^= 0xFF
        guard case .warning(let reason) = ContainerIntegrity.check(url: try Fixture.write(damaged, name: "game.xci"), deep: true).verdict else {
            Issue.record("expected warning"); return
        }
        #expect(reason.contains("update/u1.nca"))
    }

    @Test("XCI with a prepended key area is reported as corrupt with a clear reason")
    func xciKeyArea() throws {
        let image = Data(count: 0x1000) + Fixture.xci(partitions: [("secure", secure())])
        guard case .corrupt(let reason) = ContainerIntegrity.check(url: try Fixture.write(image, name: "game.xci"), deep: false).verdict else {
            Issue.record("expected corrupt"); return
        }
        #expect(reason.contains("Key Area"))
    }

    // MARK: Misc

    @Test("unknown format and XCZ are not verifiable, never corrupt")
    func notVerifiable() throws {
        let junk = try Fixture.write(Fixture.noise(0x4000, seed: 9), name: "junk.nsp")
        guard case .notVerifiable = ContainerIntegrity.check(url: junk, deep: true).verdict else {
            Issue.record("expected notVerifiable"); return
        }
        let xcz = try Fixture.write(Fixture.noise(0x4000, seed: 9), name: "game.xcz")
        guard case .notVerifiable = ContainerIntegrity.check(url: xcz, deep: true).verdict else {
            Issue.record("expected notVerifiable"); return
        }
        let missing = URL(fileURLWithPath: "/nonexistent/game.nsp")
        guard case .notVerifiable = ContainerIntegrity.check(url: missing, deep: true).verdict else {
            Issue.record("expected notVerifiable"); return
        }
    }
}
