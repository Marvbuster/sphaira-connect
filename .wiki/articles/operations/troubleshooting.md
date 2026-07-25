---
title: "Fehlersuche — Praxisfunde und ihre Lösungen"
created: 2026-07-26
updated: 2026-07-26
category: operations
tags: [fehlersuche, praxis, libusb, fortschritt, nswindow, abbruch]
status: current
related:
  - usb/libusb-transport
  - protocol/progress-tracking
  - protocol/install-session-flow
  - architecture/concurrency-and-cancellation
  - operations/testing-strategy
  - operations/build-configuration
  - ui/window-and-views
code_refs:
  - Sphaira Connect/USB/USBTransport.swift
  - Sphaira Connect/Features/InstallerModel.swift
  - Sphaira Connect/Core/ProgressTracker.swift
  - Sphaira Connect/Shared/WindowStyleConfigurator.swift
  - SphairaCoreTests/Tests/SphairaCoreTests/ProgressTrackerTests.swift
---

# Fehlersuche

Diese Seite sammelt Fehler, die beim Bau von Sphaira Connect tatsächlich aufgetreten sind — nicht hypothetische. Jeder Fall steht als Symptom, Ursache, Lösung und Fundstelle im Code. Die Mehrzahl hat dieselbe Wurzel: Die Switch verhält sich anders als ein braves USB-Gerät, und zwei Zustandsmaschinen (Protokollablauf und Oberfläche) laufen auf verschiedenen Threads.

---

## 1. XCI springt sofort auf 100 %

**Symptom.** Beim Übertragen einer XCI zeigt der Fortschrittsbalken innerhalb der ersten Sekunde 100 % an und bleibt dann minutenlang dort stehen. Bei NSP-Dateien war es unauffällig oder deutlich schwächer ausgeprägt.

**Ursache.** Der Fortschritt wurde als **Hochwassermarke** über die von der Switch angeforderte Position gerechnet: `max(bisher, offset + gelesen)` — so steht es auch noch im ursprünglichen Ablauf in `CONTRACT.md`. Die Annahme dahinter ist, dass die Gegenstelle eine Datei von vorne nach hinten durchliest. Sphaira tut das nicht: Es liest Kopf- und Partitionsdaten quer über die Datei, bei einer XCI oft schon im ersten Zugriff nahe dem Dateiende. Ein einziger 64-KB-Block bei Offset 17,4 GB setzt die Hochwassermarke auf 17,4 GB von 17,5 GB.

**Lösung.** `ProgressTracker` zählt nur noch **tatsächlich übertragene Bytes** und ignoriert die Position vollständig:

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
```

Weil die Switch Bereiche auch **mehrfach** anfordern darf, kann die Summe die Dateigröße übersteigen. Deshalb gibt es `clampedSent` (`min(sentBytes, totalBytes)`) und einen ebenfalls geklemmten `fraction`. Die Anzeige läuft damit monoton bis 100 % und nie darüber.

**Abgesichert durch** `SphairaCoreTests/Tests/SphairaCoreTests/ProgressTrackerTests.swift`, Test `lateOffsetDoesNotInflateProgress` — mit dem echten Zahlenpaar aus dem Fehlerfall (17,5 GB Gesamtgröße, 64 KB übertragen, `fraction < 0.0001`).

**Merksatz.** Fortschritt ist, was durch die Leitung ging — nicht, wo die Gegenstelle gerade liest. Die vollständige Rechnung steht in [[protocol/progress-tracking]].

---

## 2. „Läuft" bleibt ewig stehen, obwohl alles übertragen ist

**Symptom.** Die letzte Datei ist durch, das Protokoll zeigt „Switch hat die Sitzung beendet.", aber die Oberfläche bleibt im Zustand „läuft": Abbrechen aktiv, Installieren gesperrt, Balken eingefroren. Sekunden später — oder gar nicht — kam die Abschlussmeldung.

**Ursache.** `InstallSession.run` räumt den Transport per `defer { transport.close() }` ab. `close()` rief synchron `libusb_release_interface`, `libusb_close` und `libusb_exit`. Hat die Switch die Verbindung ihrerseits bereits abgebaut — was am Sitzungsende genau der Fall ist —, können diese Aufrufe blockieren. Das `defer` läuft **vor** der Rückkehr aus `run`, also vor `continuation.yield(.finished(...))`. Ergebnis: Die fertige Übertragung meldet sich erst, wenn libusb sich losgerissen hat.

**Lösung.** `close()` löst die eigenen Verweise sofort und schiebt den libusb-Abbau auf eine Hintergrundschlange:

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

Das Nullen **vor** dem Absetzen des Blocks ist Teil der Lösung: Ein zweiter `close()`-Aufruf (etwa aus `deinit`) darf nichts doppelt freigeben. Weil jede Sitzung einen frischen `USBTransport` mit eigenem Kontext bekommt, stört der kurz überlebende Altkontext nicht. Details in [[usb/libusb-transport]].

---

## 3. Pakete werden plötzlich als `badMagic` oder `checksumMismatch` abgelehnt

**Symptom.** Mitten in einer laufenden Übertragung bricht die Sitzung mit einem Prüfsummen- oder Magic-Fehler ab, obwohl Kabel und Konsole in Ordnung sind. Ein erneuter Versuch scheitert an einer anderen Stelle.

**Ursache.** `libusb_bulk_transfer` schreibt die tatsächlich übertragene Menge auch dann nach `transferred`, wenn es `LIBUSB_ERROR_TIMEOUT` (-7) zurückgibt. Wird dieser Wert im Timeout-Zweig verworfen, hat der Puffer bereits Bytes bekommen, die niemand mitgezählt hat. Ab da ist der Bytestrom um genau diese Menge verschoben, und das nächste 24-Byte-Paket wird an der falschen Stelle dekodiert — mit falscher Magic oder falscher Prüfsumme.

**Lösung.** In beiden Richtungen wird `transferred` im Timeout-Zweig mitgezählt:

```swift
if code == 0 || code == Self.errorTimeout {
    // Bei Timeout können trotzdem Teilbytes angekommen sein.
    received += Int(transferred)
}
```

**Merksatz.** `LIBUSB_ERROR_TIMEOUT` heißt „noch nicht fertig", nicht „nichts passiert".

---

## 4. Zugriff verweigert statt nichtssagender Zahl

**Symptom.** Die Switch wird erkannt (die Statusanzeige zeigt „Switch verbunden"), aber beim Start der Übertragung kommt ein Fehler mit dem Code `-3`.

**Ursache.** `libusb_claim_interface` scheitert mit `LIBUSB_ERROR_ACCESS`. Die üblichen Gründe auf macOS: Die App-Sandbox ist wieder eingeschaltet, ein anderer Prozess hält das Interface (ein zweiter Installer, das alte `usb_install.py`), oder die Signatur passt nicht zu den erteilten Rechten.

**Lösung.** Der Code bekommt einen eigenen Fehlerfall statt einer nackten Zahl — an allen drei Stellen, an denen er auftreten kann (`claim_interface`, Lesen, Schreiben):

```swift
if claimResult == Self.errorAccess { throw InstallError.accessDenied }
```

`InstallError.accessDenied` trägt einen deutschen Klartext, der in der Fußnote der Aktionsleiste und im Protokoll landet. Zur Build-Seite des Problems siehe [[operations/build-configuration]].

---

## 5. Oberfläche bleibt hängen, wenn die Sitzung ohne Abschlussmeldung endet

**Symptom.** Sehr selten und schwer reproduzierbar: Der Übertragungsablauf endet, ohne dass eines der Abschlussereignisse (`finished`, `cancelled`, `failed`) bei der Oberfläche ankommt. Der Zustand bleibt auf „läuft".

**Ursache.** Alle Rückmeldungen laufen durch einen `AsyncStream`. Die Sitzung schreibt hinein, ein `Task { @MainActor }` liest heraus. Endet der Strom, ohne dass vorher ein Abschlussereignis geschrieben wurde, verlässt die `for await`-Schleife einfach ihren Rumpf — und niemand setzt die Phase zurück.

**Lösung.** Ein Rückfall hinter der Schleife:

```swift
eventTask = Task { @MainActor [weak self] in
    for await event in stream {
        self?.apply(event)
    }
    // Der Strom ist zu Ende, ohne dass ein Abschlussereignis kam.
    // Ohne diesen Rückfall bliebe die Oberfläche auf „läuft" stehen
    // und „Abbrechen" aktiv, obwohl nichts mehr passiert.
    guard let self, self.isBusy else { return }
    self.progress = nil
    self.phase = .idle
    self.appendLog("Sitzung ohne Abschlussmeldung beendet.")
}
```

Die `isBusy`-Prüfung sorgt dafür, dass der Rückfall im Normalfall nichts tut — dort ist die Phase bereits `.finished`, `.idle` oder `.failed`.

**Warum überhaupt ein Strom und nicht viele kleine Tasks?** Der Kommentar über `SessionEvent` sagt es: Einzelne unstrukturierte `Task { @MainActor }`-Aufrufe garantieren **keine Reihenfolge**. Fortschrittswerte und Protokollzeilen könnten vertauscht ankommen, und im schlimmsten Fall käme das Abschlussereignis vor dem letzten Fortschrittswert. Der Strom ist genau ein geordneter Kanal.

Aus demselben Grund zählt ein separater `DoneCounter` (mit `NSLock`) die fertigen Dateien **auf dem Sitzungs-Thread**, bevor das Ereignis abgeschickt wird — sonst hinge das Endergebnis „x Titel übertragen" von der Zustellreihenfolge ab.

---

## 6. „Nintendo Nintendo Switch" in der Verbindungsmeldung

**Symptom.** Das Protokoll meldete `Verbunden: Nintendo Nintendo Switch`.

**Ursache.** Die Meldung setzte Hersteller und Produkt zusammen. Der Produkt-String-Deskriptor der Konsole enthält den Herstellernamen aber bereits — und derselbe Effekt tritt auch bei den Rückfallwerten in `USBTransport.stringDescriptor` auf (`"Nintendo"` und `"Nintendo Switch"`).

**Lösung.** Nur noch `product` verwenden, mit Begründung im Code, damit es niemand „repariert":

```swift
case .device(let info):
    deviceSummary = "\(info.product) · \(info.serial)"
    phase = .transferring
    // info.product enthält bereits „Nintendo Switch" — den Hersteller
    // davorzusetzen ergäbe „Nintendo Nintendo Switch".
    appendLog("Verbunden: \(info.product) (Seriennummer \(info.serial))")
```

`DeviceInfo.manufacturer` wird weiterhin ermittelt, aber nicht angezeigt.

---

## 7. Fenster startet in der falschen Größe

**Symptom.** Beim Start ist das Fenster deutlich zu groß — mit viel Leerraum unter der leeren Ablagefläche. Die Größe entsprach dem Zustand beim letzten Beenden, typischerweise mit gefüllter Warteschlange und ausgeklapptem Protokoll.

**Ursache.** AppKit stellt den zuletzt gesicherten Fensterrahmen automatisch wieder her. Die Fenstergröße ist hier aber eine **Funktion des Inhalts** — beim Start ist der Inhalt immer der leere Zustand.

**Lösung.** Persistenz abschalten und einmal verzögert an den Inhalt anpassen:

```swift
// AppKit stellt beim Start den zuletzt gesicherten Rahmen wieder her —
// Persistenz abschalten und einmal an den Inhalt anpassen.
window.setFrameAutosaveName("")
window.isRestorable = false
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
    self?.fitWindowToContent()
}
```

Die Verzögerung ist nötig, weil SwiftUI zum Zeitpunkt von `viewDidMoveToWindow` noch keine belastbare Idealgröße gemessen hat. Zwei benachbarte Fallstricke aus derselben Datei sind in [[ui/window-and-views]] beschrieben: `fittingSize` kann bei `NSHostingView` kommentarlos Null liefern (deshalb zuerst `intrinsicContentSize`), und der Fensterursprung muss auf die obere linke Ecke umgerechnet werden, weil macOS-Koordinaten unten links beginnen.

---

## 8. Abbruch wirkt nicht sofort

**Symptom.** „Abbrechen" wird gedrückt, die Übertragung läuft aber noch kurz weiter.

**Erklärung, kein Fehler.** Der Abbruch ist ein Flag, das der USB-Thread abfragt — er wird nicht unterbrochen. Abgefragt wird an drei Stellen:

| Stelle | Takt |
|---|---|
| Warteschleife in `open` | alle 250 ms (`usleep(250_000)`) |
| Leseschleife | alle 500 ms (Lese-Timeout) |
| Schreibschleife | je Block, spätestens nach 5 s (Schreib-Timeout) |

Der schlechteste Fall ist also ein hängender Schreibblock. Genau deshalb ist das Schreib-Timeout **endlich**: Ohne es wäre die Sitzung unabbrechbar, sobald die Konsole mitten im Block stehen bleibt.

Das Flag selbst ist eine kleine Klasse mit `NSLock`, keine Modell-Eigenschaft:

```swift
/// Abbruch-Flag mit atomarem Zugriff. Wird aus dem cancel-Closure der Sitzung
/// gelesen — der darf niemals auf MainActor-Zustand warten, sonst blockiert
/// der USB-Thread gegen den Hauptthread.
fileprivate nonisolated final class CancelFlag: @unchecked Sendable
```

Ein Zugriff auf `@Observable`-Zustand aus dem `cancel`-Closure wäre die klassische Verklemmung: Der USB-Thread wartet auf den MainActor, der MainActor wartet auf die Oberfläche, die auf die Übertragung wartet. Siehe [[architecture/concurrency-and-cancellation]].

---

## 9. Gesamtfortschritt springt über eine gescheiterte Datei

**Symptom.** Ist eine Datei nicht lesbar, sprang der Gesamtbalken trotzdem um deren volle Größe weiter — die Anzeige lief der Wirklichkeit davon.

**Lösung.** `InstallSession.transferFile` liefert einen Wahrheitswert zurück, und nur ein `true` zählt:

```swift
// Nur tatsächlich übertragene Bytes zählen, sonst springt der
// Gesamtfortschritt über eine gescheiterte Datei hinweg.
if transferred {
    completedBytes += items[index].byteCount
}
```

Zum Verhalten bei einem Dateifehler gehört außerdem (siehe [[protocol/install-session-flow]]): Es geht ein Fehlerpaket an die Switch, die Datei wird als `.failed` markiert — und die Kommandoschleife läuft weiter. Sphaira bricht daraufhin die Installation ab, schickt aber noch den Quit-Befehl, der regulär beantwortet wird. Die Sitzung endet also geordnet statt mit einem abrupten USB-Abriss.

---

## Schnelldiagnose

| Beobachtung | Erster Blick |
|---|---|
| Fortschritt sofort bei 100 % | Fall 1 — `ProgressTracker.record` |
| „Läuft" nach dem Ende | Fall 2 — synchrones `close()` |
| `badMagic` / `checksumMismatch` mitten im Lauf | Fall 3 — Teilbytes bei Timeout |
| Fehlercode `-3` | Fall 4 — Sandbox oder zweiter Prozess |
| Oberfläche hängt ohne Meldung | Fall 5 — Rückfall im `eventTask` |
| Fenster zu groß beim Start | Fall 7 — Rahmenpersistenz |
| Abbruch reagiert träge | Fall 8 — Flag-Takt, kein Fehler |
| Balken läuft der Wirklichkeit davon | Fall 9 — gescheiterte Datei mitgezählt |
