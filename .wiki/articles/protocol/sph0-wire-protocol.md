---
title: "Das SPH0-USB-Protokoll — Paketformat, CRC32C, Kommandos"
created: 2026-07-26
updated: 2026-07-26
category: protocol
tags: [protokoll, sph0, crc32c, paketformat, libusb, little-endian]
status: current
related:
  - protocol/install-session-flow
  - protocol/progress-tracking
  - architecture/system-overview
  - architecture/concurrency-and-cancellation
  - usb/libusb-transport
  - operations/testing-strategy
code_refs:
  - Sphaira Connect/Core/SphairaProtocol.swift
  - Sphaira Connect/Core/CRC32C.swift
  - Sphaira Connect/Core/InstallError.swift
  - Sphaira Connect/USB/USBTransport.swift
---

# Das SPH0-Drahtformat

Sphaira und Sphaira Connect tauschen ausschließlich **24-Byte-Pakete fester Größe** aus:
sechs `UInt32` little-endian — `magic, arg2, arg3, arg4, arg5, crc32c` — gefolgt (bei
Bedarf) von rohen Nutzdaten außerhalb des Pakets. Die vier `arg`-Felder haben **keine feste
Bedeutung**; sie werden je nach Richtung und Zustand des Zustandsautomaten anders gelesen.
Genau das ist die häufigste Fehlerquelle beim Lesen des Codes und der Grund, warum `Packet`
neben den Rohfeldern drei benannte Sichten (`command`, `dataOffset`, `dataSize`) anbietet.

## Byteanordnung

| Offset | Länge | Feld | Inhalt |
|---|---|---|---|
| 0 | 4 | `magic` | `0x53504830`, konstant |
| 4 | 4 | `arg2` | Kommando (Switch → Host) bzw. Ergebniscode (Host → Switch) |
| 8 | 4 | `arg3` | kontextabhängig |
| 12 | 4 | `arg4` | kontextabhängig |
| 16 | 4 | `arg5` | ungenutzt, immer 0 |
| 20 | 4 | `crc32c` | CRC-32C über die **ersten 20 Bytes** |

`0x53504830` ist ASCII `"SPH0"` — allerdings little-endian geschrieben, das heißt auf dem Bus
stehen die Bytes `30 48 50 53`. Wer den Verkehr mitschneidet, sieht am Paketanfang also
`"0HPS"`. Der Test `wireLayoutLittleEndian` in `PacketTests.swift` rechnet jede einzelne
Byteposition nach.

`arg5` wird vom Code nie belegt (`init` hat den Standardwert 0, und keine Sendestelle setzt
ihn); die Hin- und Rückumwandlung überträgt ihn dennoch verlustfrei, damit ein künftiger
Protokollschritt ihn nutzen kann, ohne das Format zu brechen.

## CRC32C (Castagnoli)

```swift
nonisolated enum CRC32C {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var crc = UInt32(index)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0x82F6_3B78 : crc >> 1
            }
            return crc
        }
    }()

    static func checksum<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)] }
        return ~crc
    }
}
```

Parameter: gespiegeltes Polynom `0x82F63B78`, Startwert `0xFFFFFFFF`, Endnegation, keine
Reflexion des Ergebnisses (die steckt bereits in der gespiegelten Form). Das ist derselbe
CRC-32C wie in RFC 3720 (iSCSI) und in der `crc32c`-Hardwareinstruktion moderner CPUs — die
Gegenseite auf der Switch rechnet mit derselben Variante.

Referenzwerte, die im Vertrag stehen und in `CRC32CTests.swift` geprüft werden:

| Eingabe | Ergebnis |
|---|---|
| `[]` | `0` |
| `"123456789"` (UTF-8) | `0xE3069283` |
| 32 × `0x00` | `0x8A9136AA` |
| 32 × `0xFF` | `0x62A8AB43` |

Die Signatur ist generisch über `Collection`, nicht über `[UInt8]`. Das ist kein Selbstzweck:
`Packet.decode` prüft mit `CRC32C.checksum(bytes.prefix(20))`, also über eine
`ArraySlice` — ohne Generik müsste an dieser heißen Stelle jedes Paket einmal kopiert werden.

**Wichtig für das Verständnis der Sitzung:** Die Paket-CRC schützt nur den 20-Byte-Kopf. Die
eigentlichen Nutzdaten (Namensliste, Dateiblöcke) laufen ungeschützt daneben über den Bus —
für sie schickt der Host die CRC32C des Blocks in `arg4` des zugehörigen OK-Pakets
([[protocol/install-session-flow]]).

## Kodieren und Dekodieren

```swift
func encoded() -> [UInt8] {
    var bytes = [UInt8]()
    bytes.reserveCapacity(Self.byteCount)
    for word in [Self.magic, arg2, arg3, arg4, arg5] {
        bytes.append(contentsOf: Self.littleEndianBytes(word))
    }
    bytes.append(contentsOf: Self.littleEndianBytes(CRC32C.checksum(bytes)))
    return bytes
}
```

Die CRC wird über den bereits gefüllten Puffer gerechnet — dadurch kann Kopfaufbau und
Prüfsumme nicht auseinanderlaufen.

Beim Dekodieren ist die **Prüfreihenfolge festgeschrieben: Länge → Magic → CRC.**

```swift
static func decode(_ bytes: [UInt8]) throws -> Packet {
    // Prüfreihenfolge laut Vertrag: erst Länge, dann Magic, dann CRC.
    guard bytes.count == byteCount else {
        throw InstallError.shortPacket(expected: byteCount, got: bytes.count)
    }
    let words = (0..<6).map { readWord(bytes, at: $0 * 4) }
    guard words[0] == magic else { throw InstallError.badMagic }
    guard CRC32C.checksum(bytes.prefix(20)) == words[5] else {
        throw InstallError.checksumMismatch
    }
    return Packet(arg2: words[1], arg3: words[2], arg4: words[3], arg5: words[4])
}
```

Warum diese Reihenfolge und nicht irgendeine:

- **Länge zuerst**, weil `readWord` sonst über das Pufferende hinausliest und der Prozess
  abstürzt statt einen Fehler zu melden. Der Test `lengthCheckedBeforeMagic` sichert das ab.
- **Magic vor CRC**, weil die beiden Fehler verschiedene Ursachen benennen. `badMagic` heißt
  „die Antwort kommt gar nicht von Sphaira" (falsches Gerät, falscher Endpunkt, Bus außer
  Tritt); `checksumMismatch` heißt „richtiges Gegenüber, kaputte Leitung". Die deutschen
  Fehlertexte in `InstallError` sagen genau das: *„Ungültige Paketkennung — Antwort stammt
  nicht von Sphaira."* gegenüber *„Prüfsummenfehler im empfangenen Paket."* Ein Paket mit
  fremder Magic und passend nachgerechneter CRC wird deshalb als `badMagic` gemeldet, nicht
  als gültig akzeptiert.

Der Aufrufer bekommt beides nie einzeln zu sehen: `USBTransport.readPacket` liest exakt
`Packet.byteCount` Bytes und reicht sie direkt in `decode`.

## Kommandos und Ergebniscodes

```swift
nonisolated enum SphairaCommand: UInt32 { case quit = 0, open = 1 }
nonisolated enum SphairaResult: UInt32 { case ok = 0, error = 1 }
```

`arg2` trägt in **Switch → Host**-Paketen das Kommando, in **Host → Switch**-Paketen den
Ergebniscode. Beide Aufzählungen belegen die Werte 0 und 1 — ein `0` ist je nach Richtung
also `quit` oder `ok`. Deshalb ist die Sicht `packet.command` (== `arg2`) nur in der
Kommandoschleife sinnvoll und `send(_ result:…)` nur in der Gegenrichtung.

Alles außer `quit` und `open` beantwortet die Sitzung mit `send(.error, 0, 0)` und wirft
`InstallError.unexpectedCommand(command)` — kein stilles Ignorieren, weil ein unbekanntes
Kommando bedeutet, dass beide Seiten den Zustandsautomaten unterschiedlich sehen.

## `dataOffset` — 64 Bit aus zwei Wörtern

```swift
var command: UInt32 { arg2 }
var dataOffset: UInt64 { UInt64(arg2) << 32 | UInt64(arg3) }
var dataSize: UInt32 { arg4 }
```

Während einer Dateiübertragung fragt die Switch Bereiche an; die Position ist ein
64-Bit-Wert, aufgeteilt auf `arg2` (obere 32 Bit) und `arg3` (untere 32 Bit). Das ist keine
Vorsichtsmaßnahme, sondern Alltag: Eine XCI kann 32 GB groß sein, die 4-GB-Grenze
(`0x1_0000_0000`) wird bei jedem größeren Titel überschritten. `PacketTests` prüft die
Grenze ausdrücklich — `Packet(arg2: 1, arg3: 0).dataOffset == 4_294_967_296`.

Man beachte die Überlappung: Dasselbe `arg2`, das in der Kommandoschleife das Kommando
trägt, ist innerhalb der Dateischleife das obere Offset-Wort. Ein Offset ≥ 4 GB sieht auf
Feldebene aus wie „Kommando 1, 2, 3 …". Die beiden Bedeutungen kollidieren nicht, weil sie in
verschiedenen Zuständen des Automaten gelesen werden — wer die Zustände vermischt, baut
genau hier einen unauffindbaren Fehler ein.

## `sendFileInfo` — Größe und Flags in einem Paket

Die Antwort auf ein `open` muss Dateigröße *und* Übertragungsflags transportieren, hat dafür
aber nur `arg3` und `arg4` frei — `arg2` ist in dieser Richtung durch den Ergebniscode
belegt:

```swift
nonisolated func sendFileInfo(size: UInt64, flags: UInt32, cancel: () -> Bool) throws {
    let lsb = UInt32(truncatingIfNeeded: size)
    let msb = UInt32((size >> 32) & 0xFFFF) | (flags << 16)
    try send(.ok, arg3: msb, arg4: lsb, cancel: cancel)
}
```

- `arg4` = untere 32 Bit der Größe
- `arg3`, untere 16 Bit = Bits 32…47 der Größe → maximal darstellbare Dateigröße 2^48 − 1
  Bytes (256 TiB), für Switch-Titel weit ausreichend
- `arg3`, obere 16 Bit = Flags

Die Größe ist hier also gegenüber `dataOffset` **um ein Wort verschoben** (dort `arg2`/`arg3`,
hier `arg3`/`arg4`). Wer die beiden Kodierungen verwechselt, meldet der Switch eine um den
Faktor 2^32 falsche Dateigröße — sichtbar erst daran, dass Sphaira Blöcke jenseits des
Dateiendes anfordert.

```swift
nonisolated enum TransferFlags {
    static let none: UInt32 = 0
    static let stream: UInt32 = 1 << 0
}
```

`TransferFlags.stream` ist definiert, wird aber im gesamten Projekt nirgends gesendet:
`InstallSession` ruft `sendFileInfo(size:flags: TransferFlags.none)` auf. Das Flag ist als
Platzhalter für einen künftigen Streaming-Modus (Daten, die nicht aus einer Datei stammen)
reserviert.

## Transportschicht

`USBTransport` kapselt libusb und liefert nur zwei Rohoperationen: „lies genau *n* Bytes" und
„schreibe diesen Puffer vollständig". Beide Schleifen behandeln `LIBUSB_ERROR_TIMEOUT` (−7)
als Teilfortschritt statt als Fehler und werten `LIBUSB_ERROR_ACCESS` (−3) zu
`InstallError.accessDenied` auf; Einzelheiten dazu in
[[architecture/concurrency-and-cancellation]]. Die Endpunkte holt `resolveEndpoints` aus der
aktiven Konfigurationsbeschreibung (erster IN-, erster OUT-Endpunkt); ohne Treffer bleibt es
beim Rückfall `0x81` / `0x01`. Die vollständige libusb-Anbindung beschreibt
[[usb/libusb-transport]].
