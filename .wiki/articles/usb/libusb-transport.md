---
title: "libusb-Anbindung — Transport, Geräteerkennung und Fallstricke"
created: 2026-07-26
updated: 2026-07-26
category: usb
tags: [libusb, usb, transport, endpunkte, timeout, abbruch, nonisolated]
status: current
related:
  - protocol/install-session-flow
  - protocol/sph0-wire-protocol
  - architecture/concurrency-and-cancellation
  - operations/build-configuration
  - operations/troubleshooting
code_refs:
  - Sphaira Connect/USB/USBTransport.swift
  - Sphaira Connect/USB/LibUSBProbe.swift
  - Sphaira Connect/USB/SphairaConnect-Bridging-Header.h
  - Sphaira Connect/Features/InstallerModel.swift
---

# libusb-Anbindung

`USBTransport` ist die einzige Stelle im Projekt, an der C-Funktionen von libusb aufgerufen werden. Alles darüber (Sitzungsablauf, Ansichtsmodell, Oberfläche) sieht nur noch `Packet`, `InstallError` und ein `cancel`-Closure. Die Schicht ist klein, aber sie enthält die meisten Fallstricke des ganzen Projekts: Timeouts sind hier keine Fehler sondern Abbruch-Gelegenheiten, Teilbytes können auch bei einem Timeout schon übertragen sein, und der Verbindungsabbau darf nicht synchron passieren, weil libusb nach einem Abriss der Gegenstelle blockieren kann.

## Einordnung

```
InstallerModel  (MainActor)
      │  Task.detached
InstallSession  (nonisolated, blockierend)
      │
USBTransport    (nonisolated, blockierend)  ←  hier
      │
libusb (statisch gelinkt, über Bridging-Header sichtbar)
```

`libusb_*` ist ohne `import` global sichtbar, weil `Sphaira Connect/USB/SphairaConnect-Bridging-Header.h` genau eine Zeile enthält:

```c
#import <libusb.h>
```

Wie die Bibliothek gefunden und statisch gelinkt wird, steht in [[operations/build-configuration]].

Die Klasse ist `final class USBTransport: @unchecked Sendable` und jede Methode explizit `nonisolated`. Das ist keine Kosmetik: Im Projekt gilt `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, jeder Typ wäre also standardmäßig an den Hauptthread gebunden. Ein blockierender `libusb_bulk_transfer` auf dem MainActor würde die Oberfläche für die gesamte Übertragung einfrieren — das Gesamtbild dazu steht in [[architecture/concurrency-and-cancellation]].

Wer die Schicht **darüber** sucht — Reihenfolge der Pakete, Kommandos, Dateiübertragung —, findet sie in [[protocol/install-session-flow]]; das Drahtformat selbst in [[protocol/sph0-wire-protocol]].

## Geräteerkennung

Gesucht wird ein Gerät mit fester Kennung:

| Konstante | Wert |
|---|---|
| `vendorID` | `0x057E` (Nintendo) |
| `productID` | `0x3000` (Sphaira im USB-Installationsmodus) |

Es gibt zwei Implementierungen derselben Suche. `LibUSBProbe.isSwitchAttached()` ist der ursprüngliche Rauchtest der Anbindung (zusammen mit `LibUSBProbe.version()`, das `libusb_get_version()` als `major.minor.micro` formatiert); `USBTransport.isSwitchAttached()` ist die Kopie, die das Ansichtsmodell tatsächlich pollt. Laut `CONTRACT.md` bleibt `LibUSBProbe.swift` unverändert — die Doppelung ist bewusst in Kauf genommen, nicht übersehen.

Beide gehen gleich vor: eigener `libusb_init`-Kontext, `libusb_get_device_list`, für jedes Gerät `libusb_get_device_descriptor`, Vergleich von `idVendor`/`idProduct`, danach `libusb_free_device_list(list, 1)` und `libusb_exit` per `defer`. Es wird also **kein** Gerät geöffnet — die Abfrage braucht keine Zugriffsrechte und ist billig genug für den 2-Sekunden-Takt aus `InstallerModel.startMonitoring()`. Trotzdem läuft sie dort in einem `Task.detached(priority: .utility)`, weil das Aufbauen der Geräteliste kurz blockiert.

## Verbindungsaufbau

`open(cancel:)` ist bewusst als Warteschleife gebaut — der Benutzer startet die Übertragung, bevor er Sphaira auf der Konsole öffnet:

```swift
var deviceHandle: OpaquePointer?
while deviceHandle == nil {
    if cancel() {
        close()
        throw InstallError.cancelled
    }
    deviceHandle = libusb_open_device_with_vid_pid(newContext, Self.vendorID, Self.productID)
    if deviceHandle == nil {
        usleep(250_000)
    }
}
```

Das `cancel()`-Closure wird zwischen den Versuchen abgefragt, also spätestens alle 250 ms. Deshalb kann die Oberfläche „Abbrechen" anbieten, obwohl der Thread eigentlich wartet.

Danach passieren vier Dinge, in dieser Reihenfolge:

1. `libusb_set_auto_detach_kernel_driver(deviceHandle, 1)` — Rückgabewert bewusst mit `_ =` verworfen. Auf macOS liefert das üblicherweise `NOT_SUPPORTED`; es gibt dort keinen abzuhängenden Kernel-Treiber im Linux-Sinn. Ein `guard` an dieser Stelle würde die App auf jedem Mac scheitern lassen.
2. `resolveEndpoints(deviceHandle:)` (siehe unten).
3. `libusb_claim_interface(deviceHandle, 0)`. Schlägt das mit `-3` fehl, wird `InstallError.accessDenied` geworfen statt eines nichtssagenden numerischen Fehlers; jeder andere Code wird als `InstallError.usb(operation: "libusb_claim_interface", code:)` weitergereicht. In beiden Fällen wird vorher `close()` gerufen.
4. `libusb_get_device_descriptor` und drei String-Deskriptoren für `DeviceInfo`.

`stringDescriptor(index:fallback:)` liest über `libusb_get_string_descriptor_ascii` in einen 256-Byte-Puffer und fällt auf einen Vorgabewert zurück, wenn der Index `0` ist, die Länge `<= 0` oder der getrimmte Text leer. Die Vorgaben sind `"Nintendo"`, `"Nintendo Switch"` und `"unbekannt"` — daraus folgt eine Eigenheit der Verbindungsmeldung, siehe [[operations/troubleshooting]].

## Endpunkte

Die Endpunktadressen werden nicht geraten, sondern aus der aktiven Konfiguration gelesen:

```swift
for interfaceIndex in 0..<Int(config.pointee.bNumInterfaces) {
    let interface = config.pointee.interface[interfaceIndex]
    for altIndex in 0..<Int(interface.num_altsetting) {
        let altsetting = interface.altsetting[altIndex]
        for endpointIndex in 0..<Int(altsetting.bNumEndpoints) {
            let address = altsetting.endpoint[endpointIndex].bEndpointAddress
            if address & 0x80 != 0 {
                if foundIn == nil { foundIn = address }
            } else if foundOut == nil {
                foundOut = address
            }
        }
    }
}
```

Bit 7 der Adresse unterscheidet Richtung IN (gesetzt) von OUT. Der jeweils **erste** Treffer gewinnt. Findet die Schleife nichts — oder scheitert schon `libusb_get_active_config_descriptor` —, bleiben die Vorbelegungen `endpointIn = 0x81` und `endpointOut = 0x01` stehen. Das sind die Werte, die auch das Python-Skript fest verdrahtet hat; der Rückfall ist also der bisherige Zustand, nicht ein Ratespiel.

`libusb_free_config_descriptor` läuft per `defer`.

## Fehlercodes numerisch statt als C-Enum

```swift
private nonisolated static let errorTimeout: Int32 = -7  // LIBUSB_ERROR_TIMEOUT
private nonisolated static let errorAccess: Int32 = -3   // LIBUSB_ERROR_ACCESS
private nonisolated static let errorNoDevice: Int32 = -4 // LIBUSB_ERROR_NO_DEVICE
```

Der Kommentar im Code nennt den Grund: Die importierten C-Enum-Konstanten sind je nach Import nicht direkt mit `Int32` vergleichbar. `libusb_bulk_transfer` liefert aber ein blankes `Int32`. Ein Vergleich gegen `LIBUSB_ERROR_TIMEOUT` würde entweder nicht übersetzen oder einen `rawValue`-Umweg brauchen. Die drei Konstanten sind Teil der stabilen libusb-ABI und ändern sich nicht.

## Lesen — Timeout ist kein Fehler

```swift
let code = libusb_bulk_transfer(
    handle, endpointIn,
    pointer.baseAddress! + received, Int32(count - received),
    &transferred, Self.readTimeoutMS
)
if code == 0 || code == Self.errorTimeout {
    // Bei Timeout können trotzdem Teilbytes angekommen sein.
    received += Int(transferred)
} else if code == Self.errorAccess {
    throw InstallError.accessDenied
} else {
    throw InstallError.usb(operation: "libusb_bulk_transfer(in)", code: code)
}
```

Zwei Entscheidungen stecken darin:

**Das Timeout von 500 ms ist die Taktung des Abbruchs.** Gelesen wird immer, bis exakt `count` Bytes da sind. Ohne Timeout wäre `read` bei einer stillen Switch unabbrechbar; mit 500 ms kommt die Schleife regelmäßig an `if cancel() { throw InstallError.cancelled }` vorbei. Die Kehrseite: Der Protokollablauf verbringt zwischen zwei Anforderungen der Switch die meiste Zeit in genau dieser Schleife, was völlig normal ist.

**`transferred` wird auch im Timeout-Fall verrechnet.** libusb schreibt in `transferred` die tatsächlich übertragene Menge — die kann bei `LIBUSB_ERROR_TIMEOUT` größer als null sein. Würde man den Wert verwerfen, liefe der Puffer aus dem Tritt und ein Paket würde ab dem nächsten Byte falsch dekodiert (Ergebnis: `badMagic` oder `checksumMismatch`, obwohl die Leitung in Ordnung ist).

## Schreiben — endliches Timeout mit Absicht

Der Schreibpfad ist symmetrisch, hat aber `writeTimeoutMS = 5_000`. Der Kommentar im Code begründet beide Zahlen:

> Großzügiger als beim Lesen — ein Block ist unterwegs, soll aber nicht unbegrenzt hängen können, sonst wäre der Abbruch wirkungslos.

Beim Lesen wartet man auf eine Entscheidung der Switch (kann dauern), beim Schreiben ist ein bereits angekündigter Block unterwegs (sollte zügig gehen). Ein unbegrenztes Timeout wäre der bequeme Weg, macht die Sitzung aber unabbrechbar, sobald die Konsole mitten im Block stehen bleibt. Auch hier gilt: `sent += Int(transferred)` läuft ebenfalls im Timeout-Zweig.

`Int32(clamping: pointer.count - sent)` schützt die Umwandlung der Restlänge — die Namensliste und die Datenblöcke sind zwar klein, aber `clamping` kostet nichts.

## Protokoll-Hilfen

`readPacket`, `send` und `sendFileInfo` sind dünne Aufsätze auf `read`/`write`. Interessant ist nur die Bitpackung der Dateigröße:

```swift
nonisolated func sendFileInfo(size: UInt64, flags: UInt32, cancel: () -> Bool) throws {
    let lsb = UInt32(truncatingIfNeeded: size)
    let msb = UInt32((size >> 32) & 0xFFFF) | (flags << 16)
    try send(.ok, arg3: msb, arg4: lsb, cancel: cancel)
}
```

`arg4` trägt die unteren 32 Bit der Größe, `arg3` in den unteren 16 Bit die oberen 16 Bit der Größe und in den oberen 16 Bit die Übertragungsflags. Daraus folgt die praktische Obergrenze von 48 Bit für eine Dateigröße — 256 TB, weit jenseits jeder XCI. Die Feldbelegung der Pakete beschreibt [[protocol/sph0-wire-protocol]].

## Verbindungsabbau im Hintergrund

`close()` ist der überraschendste Teil der Datei. Es räumt die eigenen Verweise sofort auf und schiebt die eigentliche libusb-Arbeit auf eine Hintergrundschlange:

```swift
handle = nil
context = nil
interfaceClaimed = false

guard openHandle != nil || openContext != nil else { return }

DispatchQueue.global(qos: .utility).async {
    if let openHandle {
        if wasClaimed {
            _ = libusb_release_interface(openHandle, 0)
        }
        libusb_close(openHandle)
    }
    if let openContext {
        libusb_exit(openContext)
    }
}
```

Der Grund steht im Doku-Kommentar darüber: Hat die Switch die Verbindung ihrerseits schon abgebaut, können `libusb_close` und `libusb_exit` blockieren. `close()` läuft aus einem `defer` am Ende von `InstallSession.run` — die Abschlussmeldung an die Oberfläche käme dann erst nach dem Blockieren, die Übertragung sähe ewig „läuft" aus. Der ganze Fall ist in [[operations/troubleshooting]] beschrieben.

Zwei Feinheiten sichern das ab:

- Die Verweise werden **vor** dem Absetzen des Blocks genullt, damit ein zweiter `close()`-Aufruf nichts doppelt freigibt.
- `deinit` ruft `close()`, das ist also auch der Aufräumpfad, wenn niemand mehr eine Referenz hält.

Preis der Lösung: Der Kontext lebt kurz über das Sitzungsende hinaus. Da für jede Sitzung ein frischer `USBTransport` samt eigenem Kontext gebaut wird (`InstallSession(items:transport: USBTransport())` in `InstallerModel.start()`), stört das nicht.

## Fallstricke auf einen Blick

| Fallstrick | Umgang im Code |
|---|---|
| `LIBUSB_ERROR_TIMEOUT` als Fehler behandeln | Timeout ist Normalfall und Abbruch-Gelegenheit |
| `transferred` bei Timeout verwerfen | Wird in beiden Richtungen mitgezählt |
| Unbegrenztes Schreib-Timeout | 5 s, sonst ist der Abbruch wirkungslos |
| Vergleich gegen C-Enum-Konstanten | Numerische `Int32`-Konstanten (`-7`, `-3`, `-4`) |
| `auto_detach_kernel_driver` prüfen | Rückgabewert bewusst ignoriert (macOS) |
| Feste Endpunkte annehmen | Aus der aktiven Konfiguration lesen, Rückfall `0x81`/`0x01` |
| `libusb_close`/`libusb_exit` synchron | Abbau auf einer Hintergrundschlange |
| Transport auf dem MainActor | Alles `nonisolated`, Sitzung per `Task.detached` |
