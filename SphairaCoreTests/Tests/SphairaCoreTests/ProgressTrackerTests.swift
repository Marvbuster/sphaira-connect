import Testing
@testable import SphairaCore

@Suite("ProgressTracker")
struct ProgressTrackerTests {

    private static let ms: UInt64 = 1_000_000

    /// Der Fehler, der in freier Wildbahn auftrat: Die Switch fragt bei einer XCI
    /// früh Daten nahe dem Dateiende an. Eine Hochwassermarke über die höchste
    /// Position stünde dadurch sofort bei 100 %.
    @Test("Anfragen nahe dem Dateiende treiben den Fortschritt nicht hoch")
    func lateOffsetDoesNotInflateProgress() {
        var tracker = ProgressTracker(totalBytes: 17_500_000_000, startNanos: 0)

        // Erster Block liegt bei Offset ~17,4 GB — nur 64 KB tatsächlich übertragen.
        tracker.record(chunkSize: 65_536)

        #expect(tracker.sentBytes == 65_536)
        #expect(tracker.clampedSent == 65_536)
        #expect(tracker.fraction < 0.0001)
    }

    @Test("Fortschritt ist die Summe der Blöcke, unabhängig von der Reihenfolge")
    func progressSumsChunks() {
        var tracker = ProgressTracker(totalBytes: 1000, startNanos: 0)
        for _ in 0..<10 {
            tracker.record(chunkSize: 50)
        }
        #expect(tracker.sentBytes == 500)
        #expect(tracker.fraction == 0.5)
    }

    @Test("Doppelt angeforderte Bereiche werden auf die Dateigröße geklemmt")
    func duplicateReadsAreClamped() {
        var tracker = ProgressTracker(totalBytes: 100, startNanos: 0)
        tracker.record(chunkSize: 80)
        tracker.record(chunkSize: 80)

        #expect(tracker.sentBytes == 160)
        #expect(tracker.clampedSent == 100)
        #expect(tracker.fraction == 1.0)
    }

    @Test("Leere und negative Blöcke ändern nichts")
    func emptyChunksAreIgnored() {
        var tracker = ProgressTracker(totalBytes: 100, startNanos: 0)
        tracker.record(chunkSize: 0)
        tracker.record(chunkSize: -5)
        #expect(tracker.sentBytes == 0)
    }

    @Test("Leere Datei ergibt Anteil 0 statt Division durch null")
    func zeroSizeIsSafe() {
        var tracker = ProgressTracker(totalBytes: 0, startNanos: 0)
        tracker.record(chunkSize: 10)
        #expect(tracker.fraction == 0)
        #expect(tracker.clampedSent == 0)
    }

    @Test("Negative Gesamtgröße wird auf null gezogen")
    func negativeTotalIsClamped() {
        let tracker = ProgressTracker(totalBytes: -42, startNanos: 0)
        #expect(tracker.totalBytes == 0)
    }

    @Test("Vor Ablauf des Mindestabstands wird nicht gemeldet")
    func throttlesEmits() {
        var tracker = ProgressTracker(totalBytes: 1000, startNanos: 0)
        tracker.record(chunkSize: 100)

        #expect(tracker.tick(now: 50 * Self.ms) == false)
        #expect(tracker.tick(now: 99 * Self.ms) == false)
        #expect(tracker.tick(now: 100 * Self.ms) == true)
    }

    @Test("force meldet auch innerhalb des Mindestabstands")
    func forceBypassesThrottle() {
        var tracker = ProgressTracker(totalBytes: 1000, startNanos: 0)
        #expect(tracker.tick(now: Self.ms, force: true) == true)
    }

    @Test("Durchsatz wird aus Bytes je Zeitfenster berechnet")
    func rateReflectsThroughput() {
        var tracker = ProgressTracker(totalBytes: 10_000_000, startNanos: 0)

        // 1 MB in 100 ms entspricht 10 MB/s.
        tracker.record(chunkSize: 1_000_000)
        _ = tracker.tick(now: 100 * Self.ms)

        #expect(tracker.bytesPerSecond == 10_000_000)
    }

    @Test("Durchsatz wird geglättet statt zu springen")
    func rateIsSmoothed() {
        var tracker = ProgressTracker(totalBytes: 100_000_000, startNanos: 0)

        tracker.record(chunkSize: 1_000_000)
        _ = tracker.tick(now: 100 * Self.ms)
        let first = tracker.bytesPerSecond

        // Zweites Fenster mit doppeltem Durchsatz — die Anzeige darf nicht
        // sofort auf den neuen Wert springen.
        tracker.record(chunkSize: 2_000_000)
        _ = tracker.tick(now: 200 * Self.ms)
        let second = tracker.bytesPerSecond

        #expect(second > first)
        #expect(second < 20_000_000)
    }

    @Test("Ohne Fortschritt fällt der geschätzte Durchsatz")
    func rateDecaysWhenStalled() {
        var tracker = ProgressTracker(totalBytes: 10_000_000, startNanos: 0)
        tracker.record(chunkSize: 1_000_000)
        _ = tracker.tick(now: 100 * Self.ms)
        let moving = tracker.bytesPerSecond

        _ = tracker.tick(now: 200 * Self.ms)
        #expect(tracker.bytesPerSecond < moving)
    }
}
