import Foundation

nonisolated struct InstallItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case queued
        case transferring
        case done
        /// The Switch closed the file after a few bytes. Whether it skipped the
        /// title (already installed) or rejected it (e.g. an invalid header) is
        /// NOT distinguishable from the protocol — both cases look identical on
        /// the wire. Hence a dedicated, neutral state instead of an error.
        case skipped(String)
        case failed(String)
    }

    let id: UUID
    let url: URL
    let displayName: String     // File name including extension — sent to the Switch as is
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

    /// Directories are resolved recursively, duplicates (same path) are dropped,
    /// and non-installable extensions are ignored. Order: stable alphabetical.
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

        // sort(by:) is stable — equal names keep the order they were found in.
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

        // errorHandler returns true: skip unreadable subdirectories instead of aborting.
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
