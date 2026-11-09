//
//  ContainerIntegrity.swift
//  Sphaira Connect
//
//  Checks NSP/XCI containers for dump damage before anything goes over USB.
//

import CryptoKit
import Foundation

/// Integrity check for the container formats the Switch installs from.
///
/// The check needs no keys. It relies on what the containers themselves carry:
///
/// - **XCI (gamecard image)**: every HFS0 partition entry stores a SHA-256 over
///   the first `hashedSize` bytes of its file (normally 0x200 — the encrypted
///   NCA header), and the root partition stores a hash over each sub-partition
///   header. A dump gap that hits an NCA head is caught with certainty.
/// - **NSP (PFS0)**: carries no hashes. Instead the head of every NCA entry must
///   look like an encrypted header — 0x200 bytes of zeros or 0xFF are not.
///
/// The deep pass additionally streams through every NCA entry and looks for
/// long runs of zero bytes. NCA content is encrypted (AES-CTR/XTS); a run of
/// hundreds of kilobytes of zeros inside one cannot be genuine data. Because a
/// homebrew NCA could in theory carry plaintext sections, this is reported as a
/// warning rather than as damage.
///
/// Only the **secure** partition of an XCI matters for an install; damage in
/// the update/normal/logo partitions is reported as a warning.
nonisolated enum ContainerIntegrity {
    enum Verdict: Equatable, Sendable {
        /// Structure and all verifiable hashes are fine.
        case ok
        /// The file could not be examined (unknown or compressed-XCI format,
        /// unreadable). Nothing is known either way.
        case notVerifiable(String)
        /// Suspicious but not proven damaged.
        case warning(String)
        /// Proven damaged — an install will fail or produce a broken title.
        case corrupt(String)
    }

    struct Report: Equatable, Sendable {
        var verdict: Verdict
        /// Number of container entries that were examined.
        var entriesChecked: Int
    }

    /// A zero run at least this long inside an NCA entry is reported.
    static let zeroRunThreshold: Int64 = 256 * 1024
    /// Length of the NCA head examined by the quick check.
    static let ncaHeadLength = 0x200
    static let deepChunkSize = 4 * 1024 * 1024

    // MARK: - Entry point

    /// Runs the quick structural/hash check and, if `deep` is set, the zero-run
    /// scan over every NCA entry. `progress` receives 0…1 during the deep pass.
    /// Never throws — a file that cannot be read yields `.notVerifiable`.
    static func check(
        url: URL,
        deep: Bool,
        cancel: () -> Bool = { false },
        progress: (Double) -> Void = { _ in }
    ) -> Report {
        let ext = url.pathExtension.lowercased()
        if ext == "xcz" {
            return Report(verdict: .notVerifiable(String(localized: "XCZ ist komprimiert — Prüfsummen nicht prüfbar")), entriesChecked: 0)
        }
        guard let file = try? FileHandle(forReadingFrom: url),
              let fileSize = try? file.seekToEnd(), fileSize > 0 else {
            return Report(verdict: .notVerifiable(String(localized: "Datei nicht lesbar")), entriesChecked: 0)
        }
        defer { try? file.close() }
        let reader = Reader(file: file, size: Int64(fileSize))

        let layout: Layout
        do {
            layout = try parse(reader)
        } catch let failure as Failure {
            return Report(verdict: failure.verdict, entriesChecked: 0)
        } catch {
            return Report(verdict: .notVerifiable(error.localizedDescription), entriesChecked: 0)
        }

        var warnings: [String] = []
        if let issue = layout.structuralIssue {
            switch issue.severity {
            case .corrupt: return Report(verdict: .corrupt(issue.message), entriesChecked: layout.entries.count)
            case .warning: warnings.append(issue.message)
            }
        }

        if let hashFailure = verifyHashes(layout, reader: reader, cancel: cancel) {
            switch hashFailure.severity {
            case .corrupt: return Report(verdict: .corrupt(hashFailure.message), entriesChecked: layout.entries.count)
            case .warning: warnings.append(hashFailure.message)
            }
        }
        if cancel() { return Report(verdict: .notVerifiable(String(localized: "Prüfung abgebrochen")), entriesChecked: layout.entries.count) }

        if let headFailure = verifyNCAHeads(layout, reader: reader, cancel: cancel) {
            return Report(verdict: .corrupt(headFailure), entriesChecked: layout.entries.count)
        }
        if cancel() { return Report(verdict: .notVerifiable(String(localized: "Prüfung abgebrochen")), entriesChecked: layout.entries.count) }

        if deep, let zeroRun = scanZeroRuns(layout, reader: reader, cancel: cancel, progress: progress) {
            warnings.append(zeroRun)
        }
        if cancel() { return Report(verdict: .notVerifiable(String(localized: "Prüfung abgebrochen")), entriesChecked: layout.entries.count) }

        if let first = warnings.first {
            return Report(verdict: .warning(first), entriesChecked: layout.entries.count)
        }
        return Report(verdict: .ok, entriesChecked: layout.entries.count)
    }

    // MARK: - Layout

    enum Severity: Equatable { case warning, corrupt }

    struct Issue: Equatable {
        var severity: Severity
        var message: String
    }

    /// One file inside a container, with the region the container hashes.
    struct Entry: Equatable, Sendable {
        var name: String
        /// Partition name for XCI ("secure", "update", …); nil for NSP.
        var partition: String?
        var offset: Int64
        var size: Int64
        var hashedSize: Int64
        var expectedHash: Data?

        var isNCA: Bool {
            let lower = name.lowercased()
            return lower.hasSuffix(".nca") || lower.hasSuffix(".ncz")
        }
        /// Whether damage here breaks the install (as opposed to a cosmetic partition).
        var isInstallRelevant: Bool { partition == nil || partition == "secure" }
    }

    struct Layout: Equatable, Sendable {
        var kind: Kind
        var entries: [Entry]
        /// Sub-partition headers of an XCI that the root partition hashes.
        var partitionHeaders: [Entry]
        var structuralIssue: Issue?

        enum Kind: Equatable, Sendable { case nsp, xci }
    }

    struct Failure: Error {
        var verdict: Verdict
    }

    /// Detects the container type by magic and reads its directory.
    static func parse(_ reader: Reader) throws -> Layout {
        if reader.size >= 0x10, reader.read(at: 0, count: 4) == Data("PFS0".utf8) {
            return try parsePFS0(reader)
        }
        if reader.size >= 0x200, reader.read(at: 0x100, count: 4) == Data("HEAD".utf8) {
            return try parseXCI(reader)
        }
        if reader.size >= 0x1100, reader.read(at: 0x1100, count: 4) == Data("HEAD".utf8) {
            throw Failure(verdict: .corrupt(String(localized: "XCI mit vorangestellter Key Area (0x1000 Bytes) — Sphaira erwartet den Gamecard-Header bei 0x100")))
        }
        throw Failure(verdict: .notVerifiable(String(localized: "Unbekanntes Containerformat (weder PFS0 noch XCI)")))
    }

    private static func parsePFS0(_ reader: Reader) throws -> Layout {
        let header = reader.read(at: 0, count: 0x10)
        let count = Int(header.u32(at: 4))
        let stringTableSize = Int64(header.u32(at: 8))
        guard count > 0, count < 100_000 else {
            throw Failure(verdict: .corrupt(String(localized: "PFS0-Verzeichnis ungültig (\(count) Einträge)")))
        }
        let tableOffset: Int64 = 0x10
        let stringsOffset = tableOffset + Int64(count) * 0x18
        let dataStart = stringsOffset + stringTableSize
        guard dataStart <= reader.size else {
            throw Failure(verdict: .corrupt(String(localized: "PFS0-Verzeichnis reicht über das Dateiende hinaus")))
        }
        let table = reader.read(at: tableOffset, count: Int(count) * 0x18)
        let strings = reader.read(at: stringsOffset, count: Int(stringTableSize))

        var entries: [Entry] = []
        for index in 0..<count {
            let base = index * 0x18
            let offset = Int64(bitPattern: table.u64(at: base))
            let size = Int64(bitPattern: table.u64(at: base + 8))
            let nameOffset = Int(table.u32(at: base + 16))
            entries.append(Entry(
                name: strings.cString(at: nameOffset),
                partition: nil,
                offset: dataStart + offset,
                size: size,
                hashedSize: 0,
                expectedHash: nil
            ))
        }
        var layout = Layout(kind: .nsp, entries: entries, partitionHeaders: [], structuralIssue: nil)
        layout.structuralIssue = boundsIssue(entries, fileSize: reader.size)
        return layout
    }

    private static func parseXCI(_ reader: Reader) throws -> Layout {
        let header = reader.read(at: 0x100, count: 0x100)
        let rootOffset = Int64(bitPattern: header.u64(at: 0x30))
        let rootHeaderSize = Int64(bitPattern: header.u64(at: 0x38))
        guard rootOffset > 0, rootHeaderSize >= 0x10, rootOffset + rootHeaderSize <= reader.size else {
            throw Failure(verdict: .corrupt(String(localized: "Gamecard-Header verweist auf ein ungültiges Root-Verzeichnis")))
        }
        let root = try parseHFS0(reader, at: rootOffset, partition: nil)

        var entries: [Entry] = []
        var partitionHeaders: [Entry] = []
        var issue: Issue?
        for partition in root {
            partitionHeaders.append(partition)
            guard partition.offset + partition.hashedSize <= reader.size else {
                throw Failure(verdict: .corrupt(String(localized: "Partition „\(partition.name)“ liegt außerhalb der Datei")))
            }
            do {
                entries.append(contentsOf: try parseHFS0(reader, at: partition.offset, partition: partition.name))
            } catch let failure as Failure {
                if partition.name == "secure" { throw failure }
                if issue == nil, case .corrupt(let message) = failure.verdict {
                    issue = Issue(severity: .warning, message: message)
                }
            }
        }
        var layout = Layout(kind: .xci, entries: entries, partitionHeaders: partitionHeaders, structuralIssue: issue)
        if layout.structuralIssue == nil {
            layout.structuralIssue = boundsIssue(entries, fileSize: reader.size)
        }
        return layout
    }

    private static func parseHFS0(_ reader: Reader, at base: Int64, partition: String?) throws -> [Entry] {
        let label = partition ?? "root"
        guard base + 0x10 <= reader.size, reader.read(at: base, count: 4) == Data("HFS0".utf8) else {
            throw Failure(verdict: .corrupt(String(localized: "HFS0-Kennung der Partition „\(label)“ fehlt")))
        }
        let header = reader.read(at: base, count: 0x10)
        let count = Int(header.u32(at: 4))
        let stringTableSize = Int64(header.u32(at: 8))
        guard count < 100_000 else {
            throw Failure(verdict: .corrupt(String(localized: "HFS0-Verzeichnis der Partition „\(label)“ ungültig (\(count) Einträge)")))
        }
        let tableOffset = base + 0x10
        let stringsOffset = tableOffset + Int64(count) * 0x40
        let dataStart = stringsOffset + stringTableSize
        guard dataStart <= reader.size else {
            throw Failure(verdict: .corrupt(String(localized: "HFS0-Verzeichnis der Partition „\(label)“ reicht über das Dateiende hinaus")))
        }
        let table = reader.read(at: tableOffset, count: count * 0x40)
        let strings = reader.read(at: stringsOffset, count: Int(stringTableSize))

        var entries: [Entry] = []
        for index in 0..<count {
            let entryBase = index * 0x40
            entries.append(Entry(
                name: strings.cString(at: Int(table.u32(at: entryBase + 16))),
                partition: partition,
                offset: dataStart + Int64(bitPattern: table.u64(at: entryBase)),
                size: Int64(bitPattern: table.u64(at: entryBase + 8)),
                hashedSize: Int64(table.u32(at: entryBase + 20)),
                expectedHash: table.subdata(in: (entryBase + 32)..<(entryBase + 64))
            ))
        }
        return entries
    }

    private static func boundsIssue(_ entries: [Entry], fileSize: Int64) -> Issue? {
        for entry in entries where entry.offset < 0 || entry.size < 0 || entry.offset + entry.size > fileSize {
            let message = String(localized: "„\(entry.name)“ endet hinter dem Dateiende — Dump unvollständig")
            return Issue(severity: entry.isInstallRelevant ? .corrupt : .warning, message: message)
        }
        return nil
    }

    // MARK: - Checks

    /// XCI only: compares every stored SHA-256 with the data. Returns the first
    /// failure; damage in the secure partition (or a root entry) is corrupt,
    /// elsewhere a warning.
    static func verifyHashes(_ layout: Layout, reader: Reader, cancel: () -> Bool) -> Issue? {
        guard layout.kind == .xci else { return nil }
        var warning: Issue?
        // Root entries hash the sub-partition headers; only "secure" is fatal.
        let candidates: [(Entry, Bool)] =
            layout.partitionHeaders.map { ($0, $0.name == "secure") }
            + layout.entries.map { ($0, $0.isInstallRelevant) }
        for (entry, fatal) in candidates {
            if cancel() { return nil }
            guard let expected = entry.expectedHash, entry.hashedSize > 0 else { continue }
            let data = reader.read(at: entry.offset, count: Int(entry.hashedSize))
            guard Data(SHA256.hash(data: data)) != expected else { continue }
            let location = entry.partition.map { "\($0)/\(entry.name)" } ?? entry.name
            let message = String(localized: "Prüfsumme von „\(location)“ stimmt nicht — Dump beschädigt")
            if fatal { return Issue(severity: .corrupt, message: message) }
            if warning == nil { warning = Issue(severity: .warning, message: message) }
        }
        return warning
    }

    /// Every NCA head must look encrypted. A head of all zeros or all 0xFF is a
    /// dump gap — decisive for NSPs, which carry no hashes.
    static func verifyNCAHeads(_ layout: Layout, reader: Reader, cancel: () -> Bool) -> String? {
        for entry in layout.entries where entry.isNCA && entry.isInstallRelevant {
            if cancel() { return nil }
            let head = reader.read(at: entry.offset, count: Int(min(Int64(ncaHeadLength), entry.size)))
            guard !head.isEmpty else { continue }
            if head.allSatisfy({ $0 == 0 }) || head.allSatisfy({ $0 == 0xFF }) {
                return String(localized: "NCA-Header von „\(entry.name)“ ist leer — Dump beschädigt")
            }
        }
        return nil
    }

    /// Streams through every install-relevant NCA entry looking for long zero
    /// runs. Returns a description of the first one found.
    static func scanZeroRuns(
        _ layout: Layout,
        reader: Reader,
        cancel: () -> Bool,
        progress: (Double) -> Void
    ) -> String? {
        let targets = layout.entries.filter { $0.isNCA && $0.isInstallRelevant && $0.size > 0 }
        let total = targets.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return nil }
        var done: Int64 = 0
        var lastReported = -1.0

        for entry in targets {
            var position = entry.offset
            let end = entry.offset + entry.size
            var run: Int64 = 0
            while position < end {
                if cancel() { return nil }
                let count = Int(min(Int64(deepChunkSize), end - position))
                let chunk = reader.read(at: position, count: count)
                guard !chunk.isEmpty else { break }
                let hit = chunk.withUnsafeBytes { raw -> Bool in
                    let bytes = raw.bindMemory(to: UInt8.self)
                    var index = 0
                    let n = bytes.count
                    while index < n {
                        // Fast path: compare eight bytes at a time.
                        if index + 8 <= n, raw.loadUnaligned(fromByteOffset: index, as: UInt64.self) == 0 {
                            run += 8
                            index += 8
                        } else {
                            run = bytes[index] == 0 ? run + 1 : 0
                            index += 1
                        }
                        if run >= zeroRunThreshold { return true }
                    }
                    return false
                }
                if hit {
                    return String(localized: "Nullblock von mindestens \(ByteFormat.size(run)) in „\(entry.name)“ — mögliche Dump-Lücke")
                }
                position += Int64(chunk.count)
                done += Int64(chunk.count)
                let fraction = Double(done) / Double(total)
                if fraction - lastReported >= 0.01 {
                    lastReported = fraction
                    progress(fraction)
                }
            }
        }
        progress(1)
        return nil
    }

    // MARK: - Reader

    /// Positioned reads over a file handle; reads past the end return short data.
    final class Reader {
        let file: FileHandle
        let size: Int64

        init(file: FileHandle, size: Int64) {
            self.file = file
            self.size = size
        }

        func read(at offset: Int64, count: Int) -> Data {
            guard offset >= 0, offset < size, count > 0 else { return Data() }
            do {
                try file.seek(toOffset: UInt64(offset))
                return try file.read(upToCount: count) ?? Data()
            } catch {
                return Data()
            }
        }
    }
}

private extension Data {
    func u32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian
    }

    func u64(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }.littleEndian
    }

    func cString(at offset: Int) -> String {
        guard offset < count else { return "" }
        let slice = self[(startIndex + offset)...]
        let end = slice.firstIndex(of: 0) ?? slice.endIndex
        return String(decoding: slice[slice.startIndex..<end], as: UTF8.self)
    }
}
