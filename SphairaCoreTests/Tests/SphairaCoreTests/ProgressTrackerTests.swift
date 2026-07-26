import Testing
@testable import SphairaCore

@Suite("ProgressTracker")
struct ProgressTrackerTests {

    private static let ms: UInt64 = 1_000_000

    /// The bug that showed up in the wild: for an XCI the Switch requests data
    /// near the end of the file early on. A high-water mark over the highest
    /// offset would therefore jump straight to 100 %.
    @Test("Requests near the end of the file do not inflate progress")
    func lateOffsetDoesNotInflateProgress() {
        var tracker = ProgressTracker(totalBytes: 17_500_000_000, startNanos: 0)

        // First chunk sits at offset ~17.4 GB — only 64 KB actually transferred.
        tracker.record(chunkSize: 65_536)

        #expect(tracker.sentBytes == 65_536)
        #expect(tracker.clampedSent == 65_536)
        #expect(tracker.fraction < 0.0001)
    }

    @Test("Progress is the sum of the chunks, regardless of their order")
    func progressSumsChunks() {
        var tracker = ProgressTracker(totalBytes: 1000, startNanos: 0)
        for _ in 0..<10 {
            tracker.record(chunkSize: 50)
        }
        #expect(tracker.sentBytes == 500)
        #expect(tracker.fraction == 0.5)
    }

    @Test("Ranges requested twice are clamped to the file size")
    func duplicateReadsAreClamped() {
        var tracker = ProgressTracker(totalBytes: 100, startNanos: 0)
        tracker.record(chunkSize: 80)
        tracker.record(chunkSize: 80)

        #expect(tracker.sentBytes == 160)
        #expect(tracker.clampedSent == 100)
        #expect(tracker.fraction == 1.0)
    }

    @Test("Empty and negative chunks change nothing")
    func emptyChunksAreIgnored() {
        var tracker = ProgressTracker(totalBytes: 100, startNanos: 0)
        tracker.record(chunkSize: 0)
        tracker.record(chunkSize: -5)
        #expect(tracker.sentBytes == 0)
    }

    @Test("An empty file yields fraction 0 instead of a division by zero")
    func zeroSizeIsSafe() {
        var tracker = ProgressTracker(totalBytes: 0, startNanos: 0)
        tracker.record(chunkSize: 10)
        #expect(tracker.fraction == 0)
        #expect(tracker.clampedSent == 0)
    }

    @Test("A negative total size is clamped to zero")
    func negativeTotalIsClamped() {
        let tracker = ProgressTracker(totalBytes: -42, startNanos: 0)
        #expect(tracker.totalBytes == 0)
    }

    @Test("Nothing is emitted before the minimum interval has elapsed")
    func throttlesEmits() {
        var tracker = ProgressTracker(totalBytes: 1000, startNanos: 0)
        tracker.record(chunkSize: 100)

        #expect(tracker.tick(now: 50 * Self.ms) == false)
        #expect(tracker.tick(now: 99 * Self.ms) == false)
        #expect(tracker.tick(now: 100 * Self.ms) == true)
    }

    @Test("force emits even within the minimum interval")
    func forceBypassesThrottle() {
        var tracker = ProgressTracker(totalBytes: 1000, startNanos: 0)
        #expect(tracker.tick(now: Self.ms, force: true) == true)
    }

    @Test("Throughput is computed from bytes per time window")
    func rateReflectsThroughput() {
        var tracker = ProgressTracker(totalBytes: 10_000_000, startNanos: 0)

        // 1 MB in 100 ms equals 10 MB/s.
        tracker.record(chunkSize: 1_000_000)
        _ = tracker.tick(now: 100 * Self.ms)

        #expect(tracker.bytesPerSecond == 10_000_000)
    }

    @Test("Throughput is smoothed instead of jumping")
    func rateIsSmoothed() {
        var tracker = ProgressTracker(totalBytes: 100_000_000, startNanos: 0)

        tracker.record(chunkSize: 1_000_000)
        _ = tracker.tick(now: 100 * Self.ms)
        let first = tracker.bytesPerSecond

        // Second window with double the throughput — the display must not jump
        // straight to the new value.
        tracker.record(chunkSize: 2_000_000)
        _ = tracker.tick(now: 200 * Self.ms)
        let second = tracker.bytesPerSecond

        #expect(second > first)
        #expect(second < 20_000_000)
    }

    @Test("Without progress the estimated throughput decays")
    func rateDecaysWhenStalled() {
        var tracker = ProgressTracker(totalBytes: 10_000_000, startNanos: 0)
        tracker.record(chunkSize: 1_000_000)
        _ = tracker.tick(now: 100 * Self.ms)
        let moving = tracker.bytesPerSecond

        _ = tracker.tick(now: 200 * Self.ms)
        #expect(tracker.bytesPerSecond < moving)
    }
}
