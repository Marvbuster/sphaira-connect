import Foundation
import Testing
@testable import SphairaCore

@Suite("Hekate release selection")
struct HekateReleaseTests {
    @Test("Selects the standard payload instead of the 8 GB variant")
    func selectsStandardPayload() throws {
        let release = try JSONDecoder().decode(HekateRelease.self, from: Data(
            """
            {
              "tag_name": "v6.5.3",
              "assets": [
                {
                  "name": "hekate_ctcaer_6.5.3__ram8GB.bin",
                  "size": 110028,
                  "digest": "sha256:aaa",
                  "browser_download_url": "https://example.com/8gb.bin"
                },
                {
                  "name": "hekate_ctcaer_6.5.3.bin",
                  "size": 110028,
                  "digest": "sha256:bbb",
                  "browser_download_url": "https://example.com/standard.bin"
                }
              ]
            }
            """.utf8
        ))

        #expect(release.tagName == "v6.5.3")
        #expect(release.standardPayload?.name == "hekate_ctcaer_6.5.3.bin")
    }

    @Test("Rejects unrelated and path-traversing assets")
    func rejectsInvalidAssets() throws {
        let release = try JSONDecoder().decode(HekateRelease.self, from: Data(
            """
            {
              "tag_name": "v1",
              "assets": [
                {
                  "name": "../hekate_ctcaer_v1.bin",
                  "size": 12,
                  "digest": null,
                  "browser_download_url": "https://example.com/bad.bin"
                },
                {
                  "name": "hekate_ctcaer_v1.zip",
                  "size": 12,
                  "digest": null,
                  "browser_download_url": "https://example.com/bad.zip"
                }
              ]
            }
            """.utf8
        ))

        #expect(release.standardPayload == nil)
    }
}
