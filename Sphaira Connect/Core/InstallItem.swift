import Foundation

nonisolated struct InstallItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case queued
        case transferring
        case done
        /// Die Switch hat die Datei nach wenigen Bytes geschlossen. Ob sie den
        /// Titel übersprungen hat (bereits installiert) oder verworfen (etwa
        /// wegen ungültigem Kopfsatz), geht aus dem Protokoll NICHT hervor —
        /// beide Fälle sehen auf dem Draht identisch aus. Deshalb ein eigener,
        /// neutraler Zustand statt eines Fehlers.
        case skipped(String)
        case failed(String)
    }

    let id: UUID
    let url: URL
    let displayName: String     // Dateiname inkl. Endung — geht so an die Switch
    let byteCount: Int64
    var state: State

    init(url: URL, byteCount: Int64) {
        self.id = UUID()
        self.url = url
        self.displayName = url.lastPathComponent
        self.byteCount = byteCount
        self.state = .queued
    }
}

nonisolated enum ItemScanner {
    static let installableExtensions: Set<String> = ["nsp", "xci", "nsz", "xcz"]

    /// Ordner werden rekursiv aufgelöst, Duplikate (gleicher Pfad) entfallen,
    /// nicht installierbare Endungen werden ignoriert. Reihenfolge: stabil alphabetisch.
    static func scan(_ urls: [URL]) -> [InstallItem] {
        var seenPaths = Set<String>()
        var items: [InstallItem] = []

        for url in urls {
            for fileURL in resolve(url) {
                guard installableExtensions.contains(fileURL.pathExtension.lowercased()) else {
                    continue
                }
                let path = fileURL.standardizedFileURL.path
                guard !seenPaths.contains(path) else { continue }
                guard let byteCount = readableFileSize(of: fileURL) else { continue }
                seenPaths.insert(path)
                items.append(InstallItem(url: fileURL, byteCount: byteCount))
            }
        }

        // sort(by:) ist stabil — gleiche Namen behalten ihre Fundreihenfolge.
        return items.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func resolve(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else { return [url] }

        // errorHandler liefert true: unlesbare Unterordner überspringen statt abbrechen.
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var files: [URL] = []
        for case let child as URL in enumerator {
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(child)
            }
        }
        return files
    }

    private static func readableFileSize(of url: URL) -> Int64? {
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else { return nil }
        return Int64(size)
    }
}
