import CryptoKit
import Foundation

enum FuseeDownloadError: LocalizedError {
    case invalidResponse
    case missingPayload
    case invalidPayload
    case checksumMismatch
    case invalidVersion

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "GitHub hat keine gültige Atmosphère-Release geliefert.")
        case .missingPayload:
            String(localized: "Die Atmosphère-Release enthält keine Fusée-Payload.")
        case .invalidPayload:
            String(localized: "Die geladene Fusée-Payload ist ungültig.")
        case .checksumMismatch:
            String(localized: "Die Prüfsumme der Fusée-Payload stimmt nicht.")
        case .invalidVersion:
            String(localized: "Die Atmosphère-Version ist ungültig.")
        }
    }
}

struct FuseeDownloader: Sendable {
    private static let releasesURL = URL(
        string: "https://api.github.com/repos/Atmosphere-NX/Atmosphere/releases?per_page=10"
    )!
    private static let maximumPayloadSize = 2 * 1_024 * 1_024

    func availableReleases() async throws -> [FuseeRelease] {
        var request = URLRequest(url: Self.releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Sphaira-Connect", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw FuseeDownloadError.invalidResponse
        }

        return try JSONDecoder().decode([FuseeRelease].self, from: data)
            .filter {
                $0.draft != true
                    && $0.prerelease != true
                    && $0.fuseePayload != nil
            }
            .prefix(5)
            .map(\.self)
    }

    func download(_ release: FuseeRelease) async throws -> URL {
        guard let asset = release.fuseePayload else {
            throw FuseeDownloadError.missingPayload
        }
        guard asset.size > 0, asset.size <= Self.maximumPayloadSize else {
            throw FuseeDownloadError.invalidPayload
        }
        guard !release.tagName.isEmpty,
              URL(fileURLWithPath: release.tagName).lastPathComponent == release.tagName else {
            throw FuseeDownloadError.invalidVersion
        }

        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Sphaira-Connect", forHTTPHeaderField: "User-Agent")
        let (payload, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              payload.count == asset.size,
              payload.count <= Self.maximumPayloadSize else {
            throw FuseeDownloadError.invalidPayload
        }

        if let digest = asset.digest, digest.hasPrefix("sha256:") {
            let expected = String(digest.dropFirst("sha256:".count)).lowercased()
            let actual = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                throw FuseeDownloadError.checksumMismatch
            }
        }

        let directory = try payloadDirectory()
        let destination = directory.appendingPathComponent(
            "fusee-\(release.tagName).bin",
            isDirectory: false
        )
        try payload.write(to: destination, options: .atomic)
        return destination
    }

    private func payloadDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("Sphaira Connect", isDirectory: true)
            .appendingPathComponent("Payloads", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
