import Testing
@testable import SphairaCore

@Suite("TransferCompletion")
struct TransferCompletionTests {
    private let mb: Int64 = 1_000_000

    @Test("exact size and over-delivery (ranges requested twice) count as complete")
    func exactAndOver() {
        #expect(TransferCompletion.isComplete(sentBytes: 10 * mb, totalBytes: 10 * mb))
        #expect(TransferCompletion.isComplete(sentBytes: 11 * mb, totalBytes: 10 * mb))
        #expect(TransferCompletion.isComplete(sentBytes: 0, totalBytes: 0))
    }

    @Test("container padding of a few hundred bytes is not a skip (v1.1 build 2 case)")
    func padding() {
        #expect(TransferCompletion.isComplete(sentBytes: 10 * mb - 512, totalBytes: 10 * mb))
    }

    @Test("unread metadata entries of ~100 KB in a 994 MB update NSP are not a skip (BotW v786432)")
    func metadataShortfall() {
        // The field case: 993.8 MB of 993.9 MB requested, install succeeded on the console.
        #expect(TransferCompletion.isComplete(sentBytes: 993_800_000, totalBytes: 993_900_000))
    }

    @Test("a shortfall right at the tolerance passes, one byte more does not")
    func toleranceEdge() {
        let total: Int64 = 2_000 * mb
        let tolerance = TransferCompletion.shortfallTolerance
        #expect(TransferCompletion.isComplete(sentBytes: total - tolerance, totalBytes: total))
        #expect(!TransferCompletion.isComplete(sentBytes: total - tolerance - 1, totalBytes: total))
    }

    @Test("a genuine skip after the header is reported for large files")
    func skipLargeFile() {
        // XCI of 17.5 GB, Switch read a single 64 KB block and closed the file.
        #expect(!TransferCompletion.isComplete(sentBytes: 65_536, totalBytes: 17_500 * mb))
        // Aborted at 95 % of a 20 GB file.
        #expect(!TransferCompletion.isComplete(sentBytes: 19_000 * mb, totalBytes: 20_000 * mb))
    }

    @Test("a small file skipped after its header is not waved through by the absolute tolerance")
    func skipSmallFile() {
        // 1 MB DLC NSP, only 8 KB requested: shortfall is far below the absolute
        // tolerance, but the relative floor still catches it.
        #expect(!TransferCompletion.isComplete(sentBytes: 8_192, totalBytes: 1 * mb))
        // Just below half is still a skip, half is complete.
        #expect(!TransferCompletion.isComplete(sentBytes: 499_999, totalBytes: 1 * mb))
        #expect(TransferCompletion.isComplete(sentBytes: 500_000, totalBytes: 1 * mb))
    }

    @Test("a small NSP whose metadata entries make up a noticeable share still completes")
    func smallFileWithMetadata() {
        // 2 MB NSP with 60 KB of XML metadata never requested.
        #expect(TransferCompletion.isComplete(sentBytes: 2 * mb - 60_000, totalBytes: 2 * mb))
    }
}
