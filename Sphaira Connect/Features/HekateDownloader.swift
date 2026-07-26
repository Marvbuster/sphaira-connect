import CryptoKit
import Foundation

enum HekateDownloadError: LocalizedError {
    case invalidResponse
    case missingPayload
    case invalidPayload
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "GitHub hat keine gültige Hekate-Release geliefert.")
        case .missingPayload:
            String(localized: "Die neueste Hekate-Release enthält keine Standard-Payload.")
        case .invalidPayload:
            String(localized: "Die geladene Hekate-Payload ist ungültig.")
        case .checksumMismatch:
            String(localized: "Die Prüfsumme der Hekate-Payload stimmt nicht.")
        }
    }
}

struct HekateDownloader: Sendable {
    private static let releasesURL = URL(
        string: "https://api.github.com/repos/CTCaer/hekate/releases?per_page=10"
    )!
    private static let maximumPayloadSize = 2 * 1_024 * 1_024

    func availableReleases() async throws -> [HekateRelease] {
        var releaseRequest = URLRequest(url: Self.releasesURL)
        releaseRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        releaseRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        releaseRequest.setValue("Sphaira-Connect", forHTTPHeaderField: "User-Agent")

        let (releaseData, releaseResponse) = try await URLSession.shared.data(for: releaseRequest)
        guard let response = releaseResponse as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw HekateDownloadError.invalidResponse
        }

        return try JSONDecoder().decode([HekateRelease].self, from: releaseData)
            .filter {
                $0.draft != true
                    && $0.prerelease != true
                    && $0.standardPayload != nil
            }
            .prefix(5)
            .map(\.self)
    }

    func download(_ release: HekateRelease) async throws -> URL {
        guard let asset = release.standardPayload else {
            throw HekateDownloadError.missingPayload
        }
        guard asset.size > 0, asset.size <= Self.maximumPayloadSize else {
            throw HekateDownloadError.invalidPayload
        }

        var payloadRequest = URLRequest(url: asset.browserDownloadURL)
        payloadRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        payloadRequest.setValue("Sphaira-Connect", forHTTPHeaderField: "User-Agent")
        let (payload, payloadResponse) = try await URLSession.shared.data(for: payloadRequest)
        guard let response = payloadResponse as? HTTPURLResponse,
              response.statusCode == 200,
              payload.count == asset.size,
              payload.count <= Self.maximumPayloadSize else {
            throw HekateDownloadError.invalidPayload
        }

        if let digest = asset.digest, digest.hasPrefix("sha256:") {
            let expected = String(digest.dropFirst("sha256:".count)).lowercased()
            let actual = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                throw HekateDownloadError.checksumMismatch
            }
        }

        let directory = try payloadDirectory()
        let destination = directory.appendingPathComponent(asset.name, isDirectory: false)
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
