import Foundation

struct FuseeRelease: Decodable, Identifiable, Sendable {
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

    var fuseePayload: Asset? {
        assets.first { asset in
            asset.name.lowercased() == "fusee.bin"
                && URL(fileURLWithPath: asset.name).lastPathComponent == asset.name
        }
    }
}
