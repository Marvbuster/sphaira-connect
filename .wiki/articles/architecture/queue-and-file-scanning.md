---
title: "Warteschlange und Dateiscan — InstallItem, ItemScanner, ByteFormat"
created: 2026-07-26
updated: 2026-07-26
category: architecture
tags: [warteschlange, dateiscan, filemanager, sortierung, formatierung, core]
status: current
related:
  - architecture/system-overview
  - architecture/concurrency-and-cancellation
  - protocol/install-session-flow
  - protocol/progress-tracking
  - ui/window-and-views
  - operations/testing-strategy
code_refs:
  - Sphaira Connect/Core/InstallItem.swift
  - Sphaira Connect/Core/ByteFormat.swift
  - Sphaira Connect/Features/InstallerModel.swift
---

# Warteschlange und Dateiscan

Zwischen „Ordner auf die App ziehen" und „Liste, die an die Switch geht" liegt genau eine
Funktion: `ItemScanner.scan([URL]) -> [InstallItem]`. Sie löst Ordner rekursiv auf, filtert
auf vier Endungen, wirft Duplikate weg, überspringt alles Unlesbare **ohne zu scheitern** und
sortiert natürlichsprachlich stabil. Gefüttert wird sie von `DropZoneView`
([[ui/window-and-views]]). Das Ergebnis ist die Reihenfolge, in der Sphaira die
Titel auf der Switch anzeigt — der Scanner bestimmt damit nicht nur, *was* übertragen wird,
sondern auch, *wie es heißt* und *in welcher Reihenfolge es dasteht*.

## `InstallItem` — der Eintrag

```swift
nonisolated struct InstallItem: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case queued
        case transferring
        case done
        case failed(String)
    }

    let id: UUID
    let url: URL
    let displayName: String     // Dateiname inkl. Endung — geht so an die Switch
    let byteCount: Int64
    var state: State
}
```

Vier Details, die man kennen sollte:

- **`displayName` ist `url.lastPathComponent`, ungefiltert.** Genau dieser String landet in
  der Namensliste, die die Switch bekommt ([[protocol/install-session-flow]]). Umbenennen der
  Datei auf der Platte heißt also: anderer Name in Sphaira. Es gibt keine Bereinigung von
  Sonderzeichen — die Liste geht als UTF-8 auf den Bus.
- **`id` ist eine frische `UUID` je Scan.** Zwei Scans derselben Datei ergeben zwei
  verschiedene `id`s; Identität für SwiftUI-Listen ja, Identität über Läufe hinweg nein. Die
  Duplikaterkennung arbeitet deshalb über Pfade, nicht über `id`.
- **`state` ist das einzige veränderliche Feld.** Alles andere ist `let`; Zustandsübergänge
  kommen ausschließlich aus `onItemState` der Sitzung.
- **`byteCount` stammt vom Dateisystem zum Scan-Zeitpunkt**, nicht vom Transfer. Die Größe,
  die tatsächlich an die Switch gemeldet wird, ermittelt die Sitzung selbst per
  `file.seekToEnd()`. Ändert sich eine Datei zwischen Ablegen und Start, stimmt der
  *Gesamtfortschritt* nicht mehr exakt — der Dateifortschritt schon.

## `ItemScanner.scan` — die Pipeline

Die Reihenfolge der Schritte ist bewusst und in `scan` direkt ablesbar:

```swift
for url in urls {
    for fileURL in resolve(url) {
        guard installableExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
        let path = fileURL.standardizedFileURL.path
        guard !seenPaths.contains(path) else { continue }
        guard let byteCount = readableFileSize(of: fileURL) else { continue }
        seenPaths.insert(path)
        items.append(InstallItem(url: fileURL, byteCount: byteCount))
    }
}
```

**1. Auflösen.** `resolve(_:)` prüft mit `fileExists(atPath:isDirectory:)`. Ist es keine
Datei und kein Ordner, kommt eine leere Liste zurück — nicht existierende URLs sind kein
Fehler. Ordner werden mit `FileManager.enumerator` durchlaufen, und zwar mit einem
Fehlerbehandler, der bewusst weiterlaufen lässt:

```swift
// errorHandler liefert true: unlesbare Unterordner überspringen statt abbrechen.
errorHandler: { _, _ in true }
```

Ohne dieses `true` würde ein einziger Unterordner ohne Leserecht — etwa in einer
Netzwerkfreigabe oder einem Time-Machine-Verzeichnis — die gesamte Aufzählung abbrechen und
still eine halbe Liste liefern. Nur reguläre Dateien (`isRegularFileKey`) landen im
Ergebnis; Symlinks auf Ordner und Bündel werden dadurch nicht mitgeschleppt.

**2. Endungsfilter.** `installableExtensions` ist `["nsp", "xci", "nsz", "xcz"]`, verglichen
wird `pathExtension.lowercased()`. `Bravo.XCI` und `echo.NSP` werden also erkannt — im
Testfixture ausdrücklich abgedeckt. Eine direkt übergebene `notes.txt` fällt genauso raus wie
eine gefundene.

**3. Duplikate.** Schlüssel ist `standardizedFileURL.path`. Das ist mehr als
Zeichenkettenvergleich: `…/sub/../alpha.nsp` und `…/alpha.nsp` werden auf denselben Pfad
normalisiert. Wer denselben Ordner zweimal ablegt oder Ordner *und* enthaltene Datei
gleichzeitig, bekommt jeden Titel trotzdem einmal.

**4. Lesbarkeit und Größe.** `readableFileSize` prüft `isReadableFile(atPath:)` und liest
`fileSizeKey`. Schlägt eines fehl, wird der Eintrag übersprungen — und zwar **bevor** der
Pfad in `seenPaths` landet. Eine unlesbare Datei blockiert damit nicht die Chance, dieselbe
Datei später über einen anderen Weg doch noch aufzunehmen.

**5. Sortierung.**

```swift
// sort(by:) ist stabil — gleiche Namen behalten ihre Fundreihenfolge.
return items.sorted {
    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
}
```

`localizedStandardCompare` ist der Vergleich, den auch der Finder benutzt: Groß- und
Kleinschreibung wird ignoriert, Ziffernfolgen werden numerisch verglichen — „Teil 2" steht
vor „Teil 10", nicht dahinter. Zusammen mit der Stabilität von `sorted` ist die Ausgabe
deterministisch, egal in welcher Reihenfolge das Dateisystem die Ordner aufzählt. Für die
Anzeige auf der Switch ist das der Unterschied zwischen einer sortierten Liste und Zufall.

Sämtliche Schritte sind in `ItemScannerTests.swift` gegen ein temporäres Ordnerfixture
abgesichert — verschachtelte Ordner, Endungen in Großschreibung, unnormalisierte Pfade und
eine per `chmod 000` unlesbar gemachte Datei ([[operations/testing-strategy]]).

## Zusammenspiel mit `InstallerModel`

`scan` entfernt Duplikate nur **innerhalb eines Aufrufs**. Das Ansichtsmodell filtert
deshalb ein zweites Mal, diesmal gegen die bereits vorhandene Warteschlange:

```swift
func add(urls: [URL]) {
    let existing = Set(items.map { $0.url.standardizedFileURL.path })
    let fresh = ItemScanner.scan(urls).filter {
        !existing.contains($0.url.standardizedFileURL.path)
    }
    guard !fresh.isEmpty else { return }
    items.append(contentsOf: fresh)
    appendLog("\(fresh.count) Datei(en) zur Warteschlange hinzugefügt.")
}
```

Wichtig: **Nachträglich hinzugefügte Einträge werden ans Ende gehängt, nicht neu
einsortiert.** Die Gesamtliste ist also nur dann durchgehend alphabetisch, wenn sie in einem
Rutsch abgelegt wurde. Das ist Absicht — eine Neusortierung würde Einträge unter dem Cursor
wegspringen lassen.

`remove(_:)` und `clearAll()` sind durch `guard !isBusy` geschützt: Während einer laufenden
Übertragung darf die Liste sich nicht ändern, weil die Sitzung mit einer Kopie arbeitet und
Indizes (`packet.arg3`, `onItemState(index:)`) sonst ins Leere zeigen würden. `add` ist
bewusst *nicht* gesperrt — neue Dateien landen dann in der Liste, gehören aber nicht zur
laufenden Sitzung.

## `ByteFormat` — Formatierung ohne Absturz und ohne Formatter

Alle Größen-, Raten- und Zeitangaben der Oberfläche gehen durch drei Funktionen, deren
oberste Regel lautet: **niemals abstürzen, im Zweifel ein Gedankenstrich.**

```swift
static func rate(_ bytesPerSecond: Double) -> String {
    guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return dash }
    return scaled(bytesPerSecond) + "/s"
}
```

`.nan`, `.infinity` und negative Werte ergeben `"–"`. Das ist kein theoretischer Fall:
`ProgressPanelView` reicht bei fertiger Übertragung ausdrücklich `.nan` hinein
(`ByteFormat.rate(isFinished ? .nan : progress.bytesPerSecond)`), um die Geschwindigkeit
verschwinden zu lassen, und `remainingText` tut dasselbe für die Restzeit, solange kein
Durchsatz bekannt ist. Der Gedankenstrich ist also eine *benutzte* Schnittstelle, kein
Notausgang.

Skaliert wird **dezimal** (1000er-Schritte, `B, kB, MB, GB, TB, PB`) — dieselbe Zählweise,
die macOS im Finder verwendet, damit eine 17,5-GB-XCI auch in der App 17,5 GB heißt. Die
Formatierung geschieht von Hand:

```swift
// Deutsches Zahlenformat mit genau einer Nachkommastelle, ohne NumberFormatter
// (der ist nicht threadsicher und die Aufrufer sind nonisolated).
let tenths = Int((value * 10).rounded())
return "\(tenths / 10),\(tenths % 10) \(units[unitIndex])"
```

Der Grund steht im Kommentar und hängt direkt an
[[architecture/concurrency-and-cancellation]]: `ByteFormat` liegt in `Core/` und wird aus
`nonisolated`-Kontexten aufgerufen; ein geteilter `NumberFormatter` wäre dort ein
Datenrennen. Unterhalb von 1000 Bytes wird ganzzahlig ausgegeben (`"512 B"`), darüber immer
mit genau einer Nachkommastelle und Komma als Trennzeichen.

`duration` liefert `m:ss` und ab einer Stunde `h:mm:ss`; auch hier gilt der Gedankenstrich
für `.nan`/`.infinity`/negativ. Gespeist wird sie in `ProgressPanelView` aus
`(overallTotal − overallSent) / bytesPerSecond`, also aus dem geglätteten Durchsatz des
[[protocol/progress-tracking]].
