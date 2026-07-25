---
title: "Fortschrittsberechnung — Summenzählung statt Hochwassermarke"
created: 2026-07-26
updated: 2026-07-26
category: protocol
tags: [fortschritt, progresstracker, xci, durchsatz, drosselung, tests]
status: current
related:
  - protocol/install-session-flow
  - protocol/sph0-wire-protocol
  - architecture/system-overview
  - architecture/queue-and-file-scanning
  - ui/window-and-views
  - operations/testing-strategy
  - operations/troubleshooting
code_refs:
  - Sphaira Connect/Core/ProgressTracker.swift
  - Sphaira Connect/USB/InstallSession.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/ProgressTrackerTests.swift
---

# Fortschrittsberechnung

`CONTRACT.md` schrieb ursprünglich eine Hochwassermarke vor:
`max(bisher, offset + gelesen)`. Das klingt vernünftig und ist in freier Wildbahn sofort
gescheitert — bei XCI-Dateien stand der Balken nach dem ersten Block auf 100 %. Der Grund
liegt im Protokoll: **Die Switch liest wahlfrei, nicht sequenziell**, und beginnt bei XCI
gerne mit Kopf- und Partitionsdaten nahe dem Dateiende. Die Lösung ist ein eigener Typ,
`Core/ProgressTracker.swift`, der die angeforderte *Position* vollständig ignoriert und
stattdessen die **tatsächlich übertragenen Bytes summiert**.

## Der Fehler

Sphaira fordert Blöcke über `dataOffset`/`dataSize` an
([[protocol/sph0-wire-protocol]]). Bei einer 17,5-GB-XCI kann der allererste Block bei
Offset ~17,4 GB liegen und 64 KB groß sein. Mit einer Hochwassermarke ergäbe das:

```
max(0, 17_400_000_000 + 65_536) / 17_500_000_000 ≈ 99,4 %
```

— nach 64 übertragenen Kilobyte. Der Rest der Übertragung liefe dann eine gefühlte Ewigkeit
auf einem Balken, der bereits am Anschlag steht; Restzeit und Durchsatz wären ebenso
sinnlos. Der Test hält den Fall als Regressionsschutz fest:

```swift
/// Der Fehler, der in freier Wildbahn auftrat: Die Switch fragt bei einer XCI
/// früh Daten nahe dem Dateiende an. Eine Hochwassermarke über die höchste
/// Position stünde dadurch sofort bei 100 %.
@Test("Anfragen nahe dem Dateiende treiben den Fortschritt nicht hoch")
func lateOffsetDoesNotInflateProgress() {
    var tracker = ProgressTracker(totalBytes: 17_500_000_000, startNanos: 0)
    tracker.record(chunkSize: 65_536)
    #expect(tracker.fraction < 0.0001)
}
```

## Die Korrektur: summieren und klemmen

```swift
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
var clampedSent: Int64 { min(sentBytes, totalBytes) }

var fraction: Double {
    guard totalBytes > 0 else { return 0 }
    return min(1, Double(clampedSent) / Double(totalBytes))
}
```

Die Summenzählung hat eine Kehrseite, und die ist der Grund für `clampedSent`: Fordert
Sphaira einen Bereich zweimal an — was das Protokoll erlaubt —, zählt der Tracker ihn
zweimal. `sentBytes` misst damit *Busverkehr*, nicht *Dateiabdeckung*. Für die Anzeige wird
auf die Dateigröße geklemmt; `sentBytes` bleibt roh sichtbar und ist damit der ehrlichere
Wert für Diagnosezwecke. Der Test `duplicateReadsAreClamped` fixiert genau dieses Verhalten:
`record(80)` zweimal bei `totalBytes: 100` ergibt `sentBytes == 160`, `clampedSent == 100`.

Drei weitere Grenzfälle sind bewusst abgesichert:

| Fall | Verhalten |
|---|---|
| `chunkSize <= 0` | wird ignoriert (leere Antwort am Dateiende, siehe [[protocol/install-session-flow]]) |
| `totalBytes == 0` | `fraction == 0` statt Division durch null |
| `totalBytes < 0` | im `init` auf 0 gezogen (`max(0, totalBytes)`) |

## Drosselung — 100 ms Mindestabstand

Ein 64-KB-Block bei 20 MB/s heißt gut 300 Anfragen pro Sekunde. Jede davon in ein
`@Observable`-Feld zu schreiben, hieße 300 SwiftUI-Aktualisierungen pro Sekunde — der
Hauptthread würde mit dem Zeichnen von Fortschrittsbalken beschäftigt sein, während die
Übertragung darauf wartet. `tick(now:force:)` ist die Bremse:

```swift
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
```

`emitIntervalNanos = 100_000_000` deckelt die Oberflächenaktualisierungen auf zehn pro
Sekunde. Der Rückgabewert ist die einzige Steuerung: Nur wenn `tick` `true` liefert, baut
`InstallSession` überhaupt ein `TransferProgress` und schickt es durch den Ereigniskanal.

Beachtenswert ist `now &- lastEmitNanos` — Subtraktion mit Überlaufumbruch statt `-`.
`DispatchTime.now().uptimeNanoseconds` ist monoton, aber die `&-`-Variante macht die
Rechnung auch dann absturzsicher, wenn ein Aufrufer einen kleineren Zeitstempel hereinreicht,
als beim letzten Mal gesetzt wurde.

## Durchsatzglättung

Der Rohwert eines 100-ms-Fensters springt stark, weil Sphaira zwischen Blöcken selbst
schreibt und Prüfsummen rechnet. Ein exponentiell geglätteter Mittelwert mit
`rateSmoothing = 0.2` (20 % neuer Messwert, 80 % Historie) macht die Anzeige lesbar, ohne
träge zu werden.

Die Sonderbehandlung `bytesPerSecond == 0 ? sample : …` ist wichtig: Ohne sie startete jede
Datei bei 0 B/s und bräuchte etliche Fenster, um den echten Wert zu erreichen. So gilt der
erste Messwert voll, alle weiteren werden geglättet. Zwei Tests sichern beide Richtungen ab —
`rateReflectsThroughput` (1 MB in 100 ms ⇒ exakt 10 MB/s beim ersten Fenster) und
`rateIsSmoothed` (verdoppelter Durchsatz im zweiten Fenster darf nicht sofort auf den neuen
Wert springen).

Steht die Übertragung still, sinkt der Wert automatisch, weil `sample` dann 0 ist
(`rateDecaysWhenStalled`). Genau das braucht die Restzeit-Anzeige, damit sie bei einer
hängenden Verbindung nicht bei einem alten, optimistischen Wert einfriert.

## Warum der Zeitstempel hereingereicht wird

```swift
/// Bewusst ohne Zeit- und USB-Abhängigkeit: Der Zeitstempel wird hereingereicht,
/// damit sich das Verhalten deterministisch prüfen lässt.
init(totalBytes: Int64, startNanos: UInt64)
mutating func tick(now: UInt64, force: Bool = false) -> Bool
```

Würde der Tracker selbst `DispatchTime.now()` aufrufen, ließen sich Drosselung und
Durchsatzberechnung nur mit `sleep` im Test prüfen — langsam, und auf ausgelasteten
CI-Maschinen unzuverlässig. So schreibt der Test schlicht `tick(now: 100 * ms)` und erwartet
exakte Zahlen ([[operations/testing-strategy]]). Die einzige Stelle, an der echte Zeit ins Spiel kommt, liegt in
`InstallSession`:

```swift
var tracker = ProgressTracker(
    totalBytes: Int64(size),
    startNanos: DispatchTime.now().uptimeNanoseconds
)
```

`DispatchTime` und nicht `Date`: Eine Zeitumstellung oder eine NTP-Korrektur darf den
Durchsatz nicht ins Absurde ziehen.

## Einbettung in die Sitzung

Der Tracker ist **pro Datei** — er wird in `transferFile` erzeugt und lebt nur für diese
eine Übertragung. Der Gesamtfortschritt entsteht erst beim Bau des Ereignisses:

```swift
func emitProgress(force: Bool) {
    guard tracker.tick(now: DispatchTime.now().uptimeNanoseconds, force: force) else { return }
    let sent = tracker.clampedSent
    onProgress(TransferProgress(
        itemIndex: index,
        itemName: item.displayName,
        itemSent: sent,
        itemTotal: Int64(size),
        overallSent: completedBytes + sent,
        overallTotal: overallTotal,
        bytesPerSecond: tracker.bytesPerSecond
    ))
}
```

`completedBytes` sind die Bytes bereits **abgeschlossener** Dateien (nur erfolgreiche zählen,
siehe [[protocol/install-session-flow]]), `overallTotal` die Summe aller `byteCount` aus dem
Scan ([[architecture/queue-and-file-scanning]]). Am Dateiende steht ein
`emitProgress(force: true)`, das die Drosselung übergeht — sonst könnte die letzte Meldung
einer Datei verschluckt werden und der Balken kurz vor 100 % stehen bleiben.

Daraus rechnet `ProgressPanelView` ([[ui/window-and-views]]) weiter: zwei Balken (Gesamt und aktuelle Datei), beide auf
1 geklemmt und bei `isFinished` fest auf 1 gesetzt, sowie die Restzeit als
`(overallTotal − overallSent) / bytesPerSecond`. Ist der Durchsatz 0 oder die Übertragung
fertig, wird bewusst `.nan` in `ByteFormat.duration` gereicht und daraus ein Gedankenstrich —
siehe [[architecture/queue-and-file-scanning]].

## Ein bekannter Rest

`itemTotal` kommt aus `seekToEnd()` der geöffneten Datei, `overallTotal` dagegen aus den
beim Scan gemerkten `byteCount`. Ändert sich eine Datei zwischen Ablegen und Übertragung,
passt der Dateibalken weiterhin, der Gesamtbalken jedoch nicht exakt. Der Fall ist selten
und die Anzeige durch das Klemmen auf ≤ 100 % harmlos — bewusst nicht wegabstrahiert.
