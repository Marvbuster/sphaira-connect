//
//  ProgressTracker.swift
//  Sphaira Connect
//
//  Bookkeeping for the progress of a file transfer.
//

import Foundation

/// Counts transferred bytes and estimates throughput.
///
/// Deliberately free of any clock or USB dependency: the timestamp is passed in
/// so the behaviour can be tested deterministically.
nonisolated struct ProgressTracker {
    /// Minimum interval between two UI updates.
    static let emitIntervalNanos: UInt64 = 100_000_000
    /// Weight of the new sample in the throughput smoothing (0…1).
    static let rateSmoothing: Double = 0.2

    let totalBytes: Int64

    private(set) var sentBytes: Int64 = 0
    private(set) var bytesPerSecond: Double = 0

    private var lastEmitNanos: UInt64
    private var lastEmitBytes: Int64 = 0

    init(totalBytes: Int64, startNanos: UInt64) {
        self.totalBytes = max(0, totalBytes)
        self.lastEmitNanos = startNanos
    }

    /// Counts one transferred chunk.
    ///
    /// The offset requested by the Switch is deliberately NOT taken into account:
    /// it reads header and partition data all over the file, often near the end
    /// early on. A high-water mark over the highest offset would therefore jump
    /// straight to 100 %.
    mutating func record(chunkSize: Int) {
        guard chunkSize > 0 else { return }
        sentBytes += Int64(chunkSize)
    }

    /// Transferred bytes, clamped to the file size — the Switch is allowed to
    /// request the same range more than once.
    var clampedSent: Int64 {
        min(sentBytes, totalBytes)
    }

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(clampedSent) / Double(totalBytes))
    }

    /// Reports whether an update is due, advancing the smoothed throughput in
    /// the process. `force` demands one (end of file).
    mutating func tick(now: UInt64, force: Bool = false) -> Bool {
        let elapsedNanos = now &- lastEmitNanos
        guard force || elapsedNanos >= Self.emitIntervalNanos else { return false }

        if elapsedNanos > 0 {
            let sample = Double(sentBytes - lastEmitBytes) / (Double(elapsedNanos) / 1e9)
            bytesPerSecond = bytesPerSecond == 0
                ? sample
                : bytesPerSecond * (1 - Self.rateSmoothing) + sample * Self.rateSmoothing
        }

        lastEmitNanos = now
        lastEmitBytes = sentBytes
        return true
    }
}
