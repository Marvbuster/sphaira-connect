---
title: "Nebenläufigkeit und Abbruch — MainActor-Default, Ereigniskanal, CancelFlag"
created: 2026-07-26
updated: 2026-07-26
category: architecture
tags: [nebenlaeufigkeit, mainactor, asyncstream, abbruch, sendable, threading]
status: current
related:
  - architecture/system-overview
  - protocol/install-session-flow
  - protocol/progress-tracking
  - usb/libusb-transport
  - operations/troubleshooting
code_refs:
  - Sphaira Connect/Features/InstallerModel.swift
  - Sphaira Connect/USB/InstallSession.swift
  - Sphaira Connect/USB/USBTransport.swift
---

# Nebenläufigkeit und Abbruch

Das Projekt baut mit `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: **jeder Typ ist
standardmäßig `@MainActor`**, wenn nichts anderes dasteht. Für eine App, deren Kernaufgabe
stundenlang blockierende `libusb_bulk_transfer`-Aufrufe sind, ist das genau die falsche
Voreinstellung — deshalb tragen `Core/` und `USB/` fast durchgehend `nonisolated`
(einzige Ausnahme: `ProgressTracker`, siehe Fallstricke), die Sitzung
läuft in einem `Task.detached`, und **jede** Rückmeldung kommt über genau einen geordneten
`AsyncStream` zurück. Der Abbruch läuft nicht über `Task.cancel()`, sondern über ein
`NSLock`-gesichertes Flag, das die blockierenden Schleifen zwischen zwei USB-Timeouts
abfragen.

## Der MainActor-Default und seine Folgen

Weil der Default umgedreht ist, steht das Schlüsselwort an Stellen, an denen man es sonst
nie sieht — an Enums, Structs und Konstanten:

```swift
nonisolated enum CRC32C { … }
nonisolated struct Packet: Equatable, Sendable { … }
nonisolated struct TransferProgress: Equatable, Sendable { … }
```

Ohne das `nonisolated` wäre `CRC32C.checksum` ein MainActor-Aufruf und in `InstallSession`
schlicht nicht erreichbar. Für die beiden Klassen in `USB/` reicht `nonisolated` allein
nicht, weil sie veränderlichen Zustand halten:

```swift
final class USBTransport: @unchecked Sendable {
    nonisolated(unsafe) private var context: OpaquePointer?
    nonisolated(unsafe) private var handle: OpaquePointer?
```

`@unchecked Sendable` ist hier eine Zusage an den Compiler, die der Aufrufer einhalten muss:
**eine `USBTransport`-Instanz gehört genau einem Thread.** Im Projekt ist das gegeben — die
Instanz wird in `InstallerModel.start()` erzeugt, sofort an die Sitzung übergeben und nur
noch aus deren detached Task benutzt. `isSwitchAttached()` ist `static` und öffnet einen
eigenen libusb-Kontext, teilt also nichts.

## Sitzungsstart: `Task.detached`, keine Modellreferenz

```swift
Task.detached(priority: .userInitiated) {
    defer { continuation.finish() }
    do {
        try session.run(
            onLog: { continuation.yield(.log($0)) },
            …
            cancel: { flag.isSet() }
        )
        continuation.yield(.finished(transferred: doneCounter.value()))
    } catch InstallError.cancelled {
        continuation.yield(.cancelled)
    } catch { … }
}
```

`Task.detached` — nicht `Task { }` — weil ein normales `Task` in einem `@MainActor`-Kontext
die Isolation erbt und der Hauptthread dann für die gesamte Übertragung stünde. Ebenso
wichtig: **die Sitzung hält keine Referenz auf `InstallerModel`.** Sie schreibt nur in die
Continuation. Damit gibt es weder einen Referenzzyklus noch die Versuchung, aus dem
USB-Thread MainActor-Zustand zu lesen.

## Ein Kanal statt vieler Tasks

Naheliegend wäre gewesen, jeden Callback als `Task { @MainActor in … }` zurückzuschicken.
Das ist falsch, und der Kommentar im Code sagt auch warum:

```swift
/// Rückmeldungen der Sitzung. Sie laufen durch genau einen geordneten Kanal,
/// damit Fortschritt und Protokollzeilen nicht vertauscht ankommen — einzelne
/// unstrukturierte Tasks garantieren keine Reihenfolge.
fileprivate enum SessionEvent: Sendable { … }
```

Unstrukturierte Tasks werden nicht in Erzeugungsreihenfolge abgearbeitet. In der Praxis
hieße das: „Datei X fertig" erscheint vor „Übertrage X …", oder ein alter
Fortschrittsschnappschuss überschreibt einen neueren. Der `AsyncStream` mit
`bufferingPolicy: .unbounded` löst beides — Reihenfolge garantiert, und der USB-Thread
blockiert nie an einem vollen Puffer (`yield` auf einen unbegrenzten Strom kehrt sofort
zurück). Die Konsumentenseite ist eine einzige Schleife:

```swift
eventTask = Task { @MainActor [weak self] in
    for await event in stream {
        self?.apply(event)
    }
    // Der Strom ist zu Ende, ohne dass ein Abschlussereignis kam.
    guard let self, self.isBusy else { return }
    self.progress = nil
    self.phase = .idle
    self.appendLog("Sitzung ohne Abschlussmeldung beendet.")
}
```

Der Rückfall nach der Schleife ist kein Zierrat: `continuation.finish()` steht im `defer` des
detached Tasks und feuert damit **immer**, auch auf Pfaden, die kein Abschlussereignis
geliefert haben. Ohne diesen Zweig bliebe die Oberfläche auf „läuft" stehen und „Abbrechen"
aktiv, obwohl nichts mehr passiert.

## `CancelFlag` und `DoneCounter` — warum zwei Mini-Klassen mit `NSLock`

```swift
fileprivate nonisolated final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    func isSet() -> Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
```

Das `cancel`-Closure wird **synchron aus dem USB-Thread** aufgerufen, mitten in einer
blockierenden Schleife. Es darf deshalb weder `await` enthalten noch MainActor-Zustand
lesen — sonst würde der USB-Thread auf den Hauptthread warten, während dieser womöglich
gerade auf USB-Ergebnisse wartet. Ein Boolean hinter einem `NSLock` ist die kleinste
Konstruktion, die das erfüllt.

`DoneCounter` löst ein verwandtes Problem: Die Zahl fertiger Dateien wird **auf dem
Sitzungs-Thread** hochgezählt, direkt im `onItemState`-Callback, bevor das Ereignis in den
Strom geht:

```swift
onItemState: { index, state in
    if state == .done { doneCounter.increment() }
    continuation.yield(.itemState(index: index, state: state))
},
```

Damit steht der Wert bereits fest, wenn `.finished(transferred:)` erzeugt wird — die
Abschlussmeldung hängt nicht davon ab, ob die MainActor-Seite die vorherigen Ereignisse
schon verarbeitet hat.

## Der Abbruchpfad

Abbruch ist kein `Task.cancel()`, weil die Sitzung nicht in `await`-Punkten hängt, sondern in
C-Aufrufen. Stattdessen prüft jede blockierende Schleife das Flag zwischen zwei Timeouts:

| Ort | Timeout | Verhalten |
|---|---|---|
| `USBTransport.open` | 250 ms `usleep` zwischen Öffnungsversuchen | `cancel()` → `close()` + `InstallError.cancelled` |
| `USBTransport.read` (private) | `readTimeoutMS = 500` | `LIBUSB_ERROR_TIMEOUT` (−7) ist **kein Fehler**, nur die Gelegenheit, `cancel` zu prüfen |
| `USBTransport.write` | `writeTimeoutMS = 5_000` | ebenso; großzügiger, weil ein Block unterwegs ist |

```swift
if code == 0 || code == Self.errorTimeout {
    // Bei Timeout können trotzdem Teilbytes angekommen sein.
    received += Int(transferred)
}
```

Die Zeile ist der eigentliche Trick: Ein Timeout wird als Teilfortschritt verbucht, nicht als
Abbruch. `read(count:)` liest deshalb so lange weiter, bis die geforderten Bytes vollständig
da sind — ein Paket, das über eine Timeout-Grenze hinweg eintrudelt, geht nicht verloren.
Praktische Folge für die Bedienung: Ein Abbruch greift beim Lesen binnen ~500 ms, beim
Schreiben im schlimmsten Fall erst nach ~5 s. Die libusb-Seite dazu steht in
[[usb/libusb-transport]].

Geworfen wird immer `InstallError.cancelled`; `InstallerModel` fängt das gesondert ab und
meldet `.cancelled` statt `.failed`, damit ein bewusster Abbruch nicht wie ein Fehler
aussieht.

## `close()` kehrt sofort zurück

```swift
DispatchQueue.global(qos: .utility).async {
    if let openHandle {
        if wasClaimed { _ = libusb_release_interface(openHandle, 0) }
        libusb_close(openHandle)
    }
    if let openContext { libusb_exit(openContext) }
}
```

`close()` steht im `defer` von `InstallSession.run` — es läuft also unmittelbar vor der
Abschlussmeldung. Hat die Switch die Verbindung ihrerseits schon abgebaut, können
`libusb_close` und `libusb_exit` blockieren; die Übertragung sähe dann ewig „läuft" aus,
obwohl sie fertig ist. Deshalb löst `close()` zuerst die eigenen Verweise (`handle = nil`,
`context = nil`, damit ein zweiter Aufruf nichts doppelt freigibt) und schiebt den
eigentlichen Abbau auf eine Hintergrundqueue.

## Geräteüberwachung

`startMonitoring()` pollt alle zwei Sekunden, ob eine Switch am Bus hängt. Die Schleife lebt
auf dem MainActor (sie schreibt `switchAttached`), der blockierende Teil nicht:

```swift
let attached = await Task.detached(priority: .utility) {
    USBTransport.isSwitchAttached()
}.value
```

`isSwitchAttached()` baut jedes Mal einen eigenen libusb-Kontext auf und wieder ab und
läuft dadurch kurz, aber eben blockierend. Ein `Task.isCancelled`-Check vor dem Schreiben
und ein `catch break` um den `Task.sleep` sorgen dafür, dass `stopMonitoring()` (aufgerufen
aus `RootView.onDisappear`) sauber greift.

## Fallstricke

- **Neuer Code in `Core/` ohne `nonisolated`** ist automatisch MainActor-isoliert. Im
  Swift-5-Sprachmodus des Projekts ist der Aufruf aus `nonisolated`-Kontext nur eine
  **Warnung**, kein Fehler — `struct ProgressTracker` (ohne `nonisolated` deklariert) wird
  genau so aus `InstallSession.transferFile` benutzt und übersetzt trotzdem. Ab dem
  Swift-6-Sprachmodus würde daraus ein Compilerfehler; neue Core-Typen deshalb ausdrücklich
  `nonisolated` markieren.
- **`NumberFormatter` und Freunde meiden.** `ByteFormat` formatiert von Hand, weil die
  Aufrufer `nonisolated` sind; siehe [[architecture/queue-and-file-scanning]].
- **Kein `await` im `cancel`-Closure.** Es ist ein synchrones `() -> Bool` und wird tief im
  USB-Thread aufgerufen.
- **`USBTransport` nicht zwischen Tasks teilen.** `@unchecked Sendable` schaltet die
  Compiler-Prüfung ab; die Einthread-Zusage ist reine Disziplin.
