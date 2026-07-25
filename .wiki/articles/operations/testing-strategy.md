---
title: "Teststrategie — SwiftPM-Paket mit Symlink auf Core"
created: 2026-07-26
updated: 2026-07-26
category: operations
tags: [tests, swift-testing, swiftpm, symlink, ci]
status: current
related:
  - operations/build-configuration
  - operations/troubleshooting
  - protocol/sph0-wire-protocol
  - protocol/progress-tracking
  - architecture/queue-and-file-scanning
code_refs:
  - SphairaCoreTests/Package.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/CRC32CTests.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/PacketTests.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/ItemScannerTests.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/ByteFormatTests.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/ProgressTrackerTests.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/InstallErrorTests.swift
---

# Teststrategie

Getestet wird ausschließlich `Sphaira Connect/Core/` — Prüfsumme, Drahtformat, Dateisuche, Zahlenformatierung, Fortschrittsrechnung, Fehlertexte. Das passiert nicht in einem Xcode-Testziel, sondern in einem eigenständigen SwiftPM-Paket daneben, dessen Quellordner ein **Symlink** auf die Core-Dateien des Xcode-Projekts ist. Damit gibt es keine zweite Kopie der Dateien, kein Xcode wird zum Testen gebraucht, und ein `swift test` läuft in wenigen Sekunden durch.

## Aufbau

```
SphairaCoreTests/
├── Package.swift
├── Sources/
│   └── SphairaCore -> ../../Sphaira Connect/Core   (Symlink)
└── Tests/
    └── SphairaCoreTests/
        ├── ByteFormatTests.swift
        ├── CRC32CTests.swift
        ├── InstallErrorTests.swift
        ├── ItemScannerTests.swift
        ├── PacketTests.swift
        └── ProgressTrackerTests.swift
```

```swift
// swift-tools-version: 6.0
import PackageDescription

// Eigenständiges Testpaket: bindet die Core-Quellen des Xcode-Projekts
// per Symlink ein, damit es keine zweite Kopie der Dateien gibt.
let package = Package(
    name: "SphairaCoreTests",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "SphairaCore",
            path: "Sources/SphairaCore"
        ),
        .testTarget(
            name: "SphairaCoreTests",
            dependencies: ["SphairaCore"],
            path: "Tests/SphairaCoreTests"
        ),
    ]
)
```

Ausgeführt wird mit:

```bash
cd "<project>/SphairaCoreTests" && swift test
```

## Warum ein Symlink und kein Xcode-Testziel

Vier Gründe, in dieser Reihenfolge:

1. **Keine zweite Dateikopie.** Eine kopierte `CRC32C.swift` im Testpaket würde beim nächsten Fehler in der App-Version stillschweigend auseinanderlaufen — die Tests wären dann grün gegen Code, den niemand ausführt.
2. **Die Projektdatei bleibt unangetastet.** Ein Xcode-Testziel bräuchte einen Eintrag in `project.pbxproj`; genau das verbietet die dateisystem-synchronisierte Gruppe (siehe [[operations/build-configuration]]).
3. **Kein Xcode nötig.** `swift test` braucht nur die Toolchain, keine `.xcodeproj`, keine Simulatoren, kein Schema. Damit ist der Testlauf skript- und CI-tauglich.
4. **Kein libusb.** Das Paket linkt nichts, weil `Core/` per Vertrag weder SwiftUI noch USB kennen darf. Genau diese Beschränkung macht die Konstruktion überhaupt erst möglich — sie ist Architekturvorgabe und Testvoraussetzung in einem.

Zwei Unterschiede zur App-Umgebung sind bewusst in Kauf genommen:

- **Plattformangabe `.macOS(.v14)`** statt 26.5. Core benutzt nur `Foundation`, das Paket läuft also auch auf älteren Systemen und mit älteren Toolchains.
- **Kein `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** In der App ist jeder Typ standardmäßig an den Hauptthread gebunden, im Paket nicht. Dass die Tests trotzdem dasselbe Verhalten prüfen wie die App, liegt daran, dass die Core-Typen fast alle ausdrücklich `nonisolated` deklariert sind — `nonisolated enum CRC32C`, `nonisolated struct Packet`, `nonisolated enum ItemScanner`, `nonisolated enum ByteFormat`, `nonisolated enum InstallError`. Einzige Ausnahme ist `struct ProgressTracker` (ohne `nonisolated`); es ist in der App damit MainActor-isoliert, was im Swift-5-Sprachmodus beim Aufruf aus der Sitzung nur eine Warnung erzeugt ([[architecture/concurrency-and-cancellation]]). Die Annotationen sind also nicht nur für den USB-Thread da, sie halten auch die beiden Übersetzungsumgebungen deckungsgleich.

Der Preis des Symlinks: Er muss im Repository erhalten bleiben. Wer den Ordner kopiert statt klont oder das Archiv über ein Werkzeug entpackt, das Symlinks auflöst, bekommt eine stille Kopie zurück — mit genau dem Problem, das Punkt 1 vermeiden sollte.

## Werkzeug

Swift Testing statt XCTest: `import Testing`, `@Suite("…")`, `@Test("…")`, `#expect(…)`. Für Fehlerfälle `#expect(throws: InstallError.badMagic) { … }`, was die Gleichheit des geworfenen Wertes prüft — möglich, weil `InstallError: Equatable` ist. Die Testnamen sind deutsche Sätze, damit die Ausgabe eines fehlgeschlagenen Laufs ohne Blick in den Quelltext verständlich ist.

## Die sechs Suiten

| Suite | Schwerpunkt |
|---|---|
| `CRC32C` | Referenzwerte, Vergleich gegen eine zweite Implementierung |
| `Packet` | Drahtformat byteweise, Hin- und Rückumwandlung, Fehlerfälle |
| `ItemScanner` | Echte Ordnerstruktur im temporären Verzeichnis |
| `ByteFormat` | Grenzwerte und deutsche Formatierung |
| `ProgressTracker` | Fortschrittsrechnung samt Regressionsfall |
| `InstallError` | Vollständigkeit und Inhalt der Klartexte |

### CRC32C

Der Kern ist eine **unabhängige zweite Implementierung** im Testcode:

```swift
/// Unabhängige bitweise Referenzimplementierung (ohne Tabelle), damit die
/// tabellenbasierte Produktivvariante gegen eine zweite Quelle geprüft wird.
private func referenceCRC32C(_ bytes: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (crc >> 1) ^ 0x82F6_3B78 : crc >> 1
        }
    }
    return ~crc
}
```

Damit wird nicht nur gegen feste Erwartungswerte geprüft, sondern gegen eine zweite Ableitung derselben Spezifikation — alle 256 Einzelbytes, mehrere Zeichenketten, ein 1-MiB-Puffer mit deterministischem Xorshift-Muster und Zufallspuffer verschiedener Längen. Dazu die Vertragsvorgabe (`checksum([])` = 0, `checksum("123456789")` = `0xE3069283`) und vier Vektoren aus RFC 3720.

Zwei weitere Fälle sichern Eigenschaften ab, die leicht verlorengehen: Ein `ArraySlice` muss dasselbe liefern wie ein `Array` (die Signatur ist über `Collection` generisch), und jedes einzeln gekippte Bit muss die Prüfsumme verändern.

### Packet

Die Byteanordnung wird nicht über einen Roundtrip geprüft — der wäre auch bei durchgängig falscher Bytereihenfolge grün —, sondern **einzeln nachgerechnet**:

```swift
// magic 0x53504830 → LE: 30 48 50 53
#expect(Array(bytes[0..<4]) == [0x30, 0x48, 0x50, 0x53])
// arg2 0x01020304 → LE: 04 03 02 01
#expect(Array(bytes[4..<8]) == [0x04, 0x03, 0x02, 0x01])
```

Was dabei geprüft wird, ist in [[protocol/sph0-wire-protocol]] beschrieben. Darüber hinaus: 200 Zufallspakete im Roundtrip, Grenzwerte (`0`, `1`, `0x7FFFFFFF`, `0x80000000`, `.max`), `dataOffset` jenseits der 4-GB-Grenze (das ist der Fall, der bei jeder XCI eintritt), jedes einzeln gekippte Byte muss werfen — und zwar in den ersten vier Bytes `badMagic`, danach `checksumMismatch`.

Zwei Feinheiten verdienen Erwähnung, weil sie echte Verwechslungsgefahren abdecken:

- **Falsche Magic mit passend nachgerechneter CRC** muss trotzdem `badMagic` liefern. Sonst würde die Magic-Prüfung faktisch von der CRC-Prüfung erschlagen.
- **Länge wird vor Magic geprüft.** `Packet.decode([0xFF, 0xFF, 0xFF, 0xFF])` ist zu kurz *und* hat die falsche Magic; erwartet wird `shortPacket(expected: 24, got: 4)`. Ohne diesen Test wäre die Reihenfolge Zufall — und eine `shortPacket`-Meldung ist bei der Fehlersuche deutlich hilfreicher.

### ItemScanner

Der einzige Test mit echtem Dateisystem. `withFixture` legt unter `NSTemporaryDirectory()` einen Baum mit verschachtelten Ordnern an und räumt ihn per `defer` wieder ab. Enthalten sind Endungen in Groß- und Kleinschreibung (`Bravo.XCI`, `echo.NSP`), nicht installierbare Dateien (`.txt`, `.md`, `.zip`) und eine Datei ganz ohne Endung.

Die Regeln, gegen die geprüft wird, stehen in [[architecture/queue-and-file-scanning]]. Geprüft werden Rekursion, Endungsfilter, stabile alphabetische Reihenfolge unabhängig von der Übergabereihenfolge, korrekte `byteCount`-Werte und die Entdopplung — auch bei unnormalisierten Pfaden:

```swift
let unnormalized = root.appendingPathComponent("sub/../alpha.nsp")
let items = ItemScanner.scan([root, file, unnormalized, root])
#expect(items.count == 5)
```

Der interessanteste Fall ist der unlesbare Eintrag: Eine Datei bekommt `posixPermissions: 0o000` und muss **übersprungen** werden, statt den ganzen Suchlauf scheitern zu lassen. Das ist wichtiger, als es klingt — ein einziger unlesbarer Titel in einem großen Ordner würde sonst das Hinzufügen komplett verhindern. `defer` setzt die Rechte zurück, damit das Aufräumen gelingt.

### ByteFormat

Reine Tabellenprüfung, aber mit zwei Aussagen: Die Skalierung ist **dezimal** (1000 Byte = „1,0 kB", 1024 Byte ebenfalls „1,0 kB") und die Formatierung deutsch (Komma als Dezimaltrenner). `Int64.max` muss auf „PB" enden statt zu überlaufen. Ungültige Eingaben — negativ, `.nan`, `±.infinity` — ergeben durchgängig den Gedankenstrich `–` und nie einen Absturz. Das ist die Vertragsvorgabe, und die Oberfläche verlässt sich darauf: `ProgressPanelView` reicht bei abgeschlossener Übertragung absichtlich `.nan` hinein, um „–" anzuzeigen.

### ProgressTracker

Diese Suite trägt einen echten Praxisfund als Regressionstest — mit Begründung direkt im Testcode:

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

Die ganze Geschichte steht in [[operations/troubleshooting]], die Rechnung dahinter in [[protocol/progress-tracking]]. Weitere Fälle: Summierung unabhängig von der Reihenfolge, Klemmung bei mehrfach angeforderten Bereichen (`sentBytes == 160`, aber `clampedSent == 100`), leere und negative Blöcke ohne Wirkung, leere Datei ohne Division durch null, negative Gesamtgröße auf null gezogen.

Der Zeitanteil ist testbar, weil `ProgressTracker` seine Zeit **hereingereicht** bekommt statt sie selbst zu holen — der Doku-Kommentar nennt das ausdrücklich als Entwurfsziel. Damit lässt sich die Drosselung exakt prüfen (`tick(now: 99 ms) == false`, `tick(now: 100 ms) == true`), ebenso `force`, der Durchsatz (1 MB in 100 ms ergibt exakt 10 MB/s), die Glättung (zweiter Wert steigt, springt aber nicht auf den neuen Messwert) und der Abfall bei Stillstand.

### InstallError

Prüft, dass **jeder** der neun Fälle einen nicht leeren deutschen Klartext liefert, dass assoziierte Werte darin auftauchen (Operationsname, Fehlercode, erwartete und erhaltene Länge, Kommandonummer, Dateipfad) und dass `Equatable` sowohl Fälle als auch assoziierte Werte unterscheidet. Der letzte Punkt ist keine Formalie: Die `#expect(throws:)`-Prüfungen der Packet-Suite hängen daran.

## Was nicht getestet wird

Bewusste Lücken, damit niemand sie für Versehen hält:

| Bereich | Grund |
|---|---|
| `USB/USBTransport.swift` | Braucht echte Hardware; libusb lässt sich nicht sinnvoll attrappieren |
| `USB/InstallSession.swift` | Hängt am Transport; der Ablauf wird gegen die echte Switch geprüft |
| `Features/` und `Features/Views/` | Ansichten und Ansichtsmodell, MainActor-gebunden, außerhalb des Pakets |

Die Konsequenz: Alles, was am Protokollablauf oder an der USB-Schicht geändert wird, muss an echter Hardware nachgestellt werden. Die Fälle, die dabei schon aufgetreten sind, sammelt [[operations/troubleshooting]].
