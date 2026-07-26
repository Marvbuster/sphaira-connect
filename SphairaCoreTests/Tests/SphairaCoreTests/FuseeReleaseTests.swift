import Foundation
import Testing
@testable import SphairaCore

@Suite("Fusée release selection")
struct FuseeReleaseTests {
    @Test("Selects the standalone fusee.bin asset")
    func selectsFuseePayload() throws {
        let release = try JSONDecoder().decode(FuseeRelease.self, from: Data(
            """
            {
              "tag_name": "1.11.2",
              "draft": false,
              "prerelease": false,
              "assets": [
                {
                  "name": "atmosphere.zip",
                  "size": 100,
                  "digest": "sha256:aaa",
                  "browser_download_url": "https://example.com/atmosphere.zip"
                },
                {
                  "name": "fusee.bin",
                  "size": 111840,
                  "digest": "sha256:bbb",
                  "browser_download_url": "https://example.com/fusee.bin"
                }
              ]
            }
            """.utf8
        ))

        #expect(release.tagName == "1.11.2")
        #expect(release.fuseePayload?.name == "fusee.bin")
    }

    @Test("Rejects similarly named assets")
    func rejectsInvalidAssets() throws {
        let release = try JSONDecoder().decode(FuseeRelease.self, from: Data(
            """
            {
              "tag_name": "1.0.0",
              "assets": [
                {
                  "name": "fusee-primary.bin",
                  "size": 12,
                  "digest": null,
                  "browser_download_url": "https://example.com/old.bin"
                }
              ]
            }
            """.utf8
        ))

        #expect(release.fuseePayload == nil)
    }
}
