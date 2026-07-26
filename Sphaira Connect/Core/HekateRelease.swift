import Foundation

struct HekateRelease: Decodable, Identifiable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let size: Int
        let digest: String?
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let assets: [Asset]
    let draft: Bool?
    let prerelease: Bool?
    var id: String { tagName }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
        case draft
        case prerelease
    }

    var standardPayload: Asset? {
        assets.first { asset in
            let name = asset.name.lowercased()
            return name.hasPrefix("hekate_ctcaer_")
                && name.hasSuffix(".bin")
                && !name.contains("ram8gb")
                && URL(fileURLWithPath: asset.name).lastPathComponent == asset.name
        }
    }
}
