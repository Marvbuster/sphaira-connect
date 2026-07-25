//
//  ProgressTracker.swift
//  Sphaira Connect
//
//  Buchführung über den Fortschritt einer Dateiübertragung.
//

import Foundation

/// Zählt übertragene Bytes und schätzt den Durchsatz.
///
/// Bewusst ohne Zeit- und USB-Abhängigkeit: Der Zeitstempel wird hereingereicht,
/// damit sich das Verhalten deterministisch prüfen lässt.
struct ProgressTracker {
    /// Mindestabstand zwischen zwei Aktualisierungen der Oberfläche.
    static let emitIntervalNanos: UInt64 = 100_000_000
    /// Gewicht des neuen Messwerts bei der Durchsatzglättung (0…1).
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

    /// Zählt einen übertragenen Block.
    ///
    /// Die von der Switch angeforderte Position geht bewusst NICHT ein: Sie liest
    /// Kopf- und Partitionsdaten quer über die Datei, oft früh nahe dem Ende. Eine
    /// Hochwassermarke über die höchste Position stünde dadurch sofort bei 100 %.
    mutating func record(chunkSize: Int) {
        guard chunkSize > 0 else { return }
        sentBytes += Int64(chunkSize)
    }

    /// Übertragene Bytes, auf die Dateigröße geklemmt — die Switch darf einen
    /// Bereich auch mehrfach anfordern.
    var clampedSent: Int64 {
        min(sentBytes, totalBytes)
    }

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(clampedSent) / Double(totalBytes))
    }

    /// Meldet, ob eine Aktualisierung fällig ist, und schreibt dabei den
    /// geglätteten Durchsatz fort. `force` erzwingt sie (Dateiende).
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
