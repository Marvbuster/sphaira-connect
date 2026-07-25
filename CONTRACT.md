# Sphaira Connect — verbindlicher Schnittstellenvertrag

Alle Module werden gegen **exakt** diese Signaturen gebaut. Keine Abweichung, keine
Umbenennung, keine zusätzlichen Pflichtparameter. Wer etwas vermisst, ergänzt es
**additiv** (neue Methode), ohne Bestehendes zu ändern.

## Rahmenbedingungen (nicht verhandelbar)

- Ziel: **macOS 26.5**, Swift 5 Sprachmodus, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  → Jeder Typ ist standardmäßig `@MainActor`. Alles, was USB macht oder blockiert,
  **muss** explizit `nonisolated` sein bzw. `final class ... : @unchecked Sendable`.
- App-Sandbox ist **aus**, Hardened Runtime an. libusb ist statisch gelinkt,
  Bridging-Header vorhanden — `libusb_*` ist ohne `import` global sichtbar.
- Dateien liegen unter `Sphaira Connect/` und werden per
  `PBXFileSystemSynchronizedRootGroup` automatisch kompiliert. **Projektdatei nicht anfassen.**
- Kommentare und Oberflächentexte auf **Deutsch**, Bezeichner auf Englisch.
- Keine Datei über 400 Zeilen.

## Ordnerzuordnung

| Ordner | Inhalt |
|---|---|
| `Sphaira Connect/Core/` | Reine Logik, keine SwiftUI-, keine USB-Abhängigkeit |
| `Sphaira Connect/USB/` | libusb-Anbindung und Protokoll-Zustandsautomat |
| `Sphaira Connect/Shared/` | Designsystem |
| `Sphaira Connect/Features/` | Ansichtsmodell |
| `Sphaira Connect/Features/Views/` | SwiftUI-Ansichten |

---

## 1. Core — `Sphaira Connect/Core/`

### CRC32C.swift
```swift
enum CRC32C {
    static func checksum<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8
}
```
Castagnoli, gespiegeltes Polynom `0x82F63B78`, Start `0xFFFFFFFF`, Endnegation.
Referenzwerte für Tests: `checksum([])` = `0`, `checksum("123456789".utf8)` = `0xE3069283`.

### SphairaProtocol.swift
```swift
enum SphairaCommand: UInt32 { case quit = 0, open = 1 }
enum SphairaResult: UInt32 { case ok = 0, error = 1 }

enum TransferFlags {
    static let none: UInt32 = 0
    static let stream: UInt32 = 1 << 0
}

struct Packet: Equatable, Sendable {
    static let magic: UInt32 = 0x5350_4830
    static let byteCount: Int = 24

    var arg2: UInt32
    var arg3: UInt32
    var arg4: UInt32
    var arg5: UInt32

    init(arg2: UInt32 = 0, arg3: UInt32 = 0, arg4: UInt32 = 0, arg5: UInt32 = 0)

    func encoded() -> [UInt8]
    static func decode(_ bytes: [UInt8]) throws -> Packet

    var command: UInt32 { get }      // == arg2
    var dataOffset: UInt64 { get }   // UInt64(arg2) << 32 | UInt64(arg3)
    var dataSize: UInt32 { get }     // == arg4
}
```
Drahtformat: sechs `UInt32` little-endian — `magic, arg2, arg3, arg4, arg5, crc32c`.
Die CRC32C läuft über die **ersten 20 Bytes**. `decode` wirft bei falscher Magic
(`InstallError.badMagic`), falscher Länge (`.shortPacket`) und CRC-Fehler (`.checksumMismatch`).

### InstallError.swift
```swift
enum InstallError: LocalizedError, Equatable {
    case switchNotFound
    case accessDenied
    case usb(operation: String, code: Int32)
    case shortPacket(expected: Int, got: Int)
    case badMagic
    case checksumMismatch
    case unexpectedCommand(UInt32)
    case fileUnreadable(path: String, reason: String)
    case cancelled

    var errorDescription: String? { get }   // deutscher Klartext
}
```

### InstallItem.swift
```swift
struct InstallItem: Identifiable, Equatable, Sendable {
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

    init(url: URL, byteCount: Int64)
}

enum ItemScanner {
    static let installableExtensions: Set<String>   // ["nsp", "xci", "nsz", "xcz"]

    /// Ordner werden rekursiv aufgelöst, Duplikate (gleicher Pfad) entfallen,
    /// nicht installierbare Endungen werden ignoriert. Reihenfolge: stabil alphabetisch.
    static func scan(_ urls: [URL]) -> [InstallItem]
}
```

### ByteFormat.swift
```swift
enum ByteFormat {
    static func size(_ bytes: Int64) -> String            // "1,4 GB"
    static func rate(_ bytesPerSecond: Double) -> String  // "23,1 MB/s"
    static func duration(_ seconds: Double) -> String     // "2:05" bzw. "–"
}
```
Nicht-endliche oder negative Eingaben ergeben `"–"`, nie einen Absturz.

---

## 2. USB — `Sphaira Connect/USB/`

`LibUSBProbe.swift` existiert bereits und bleibt unverändert.

### USBTransport.swift
```swift
final class USBTransport: @unchecked Sendable {
    struct DeviceInfo: Sendable {
        let manufacturer: String
        let product: String
        let serial: String
    }

    nonisolated init()

    nonisolated static func isSwitchAttached() -> Bool

    /// Blockiert, bis die Switch da ist. `cancel` wird regelmäßig abgefragt.
    nonisolated func open(cancel: () -> Bool) throws -> DeviceInfo
    nonisolated func close()

    nonisolated func readPacket(cancel: () -> Bool) throws -> Packet
    nonisolated func send(_ result: SphairaResult, arg3: UInt32, arg4: UInt32, cancel: () -> Bool) throws
    nonisolated func sendFileInfo(size: UInt64, flags: UInt32, cancel: () -> Bool) throws
    nonisolated func write(_ bytes: [UInt8], cancel: () -> Bool) throws
}
```
Lesen läuft mit 500 ms Timeout in einer Schleife, damit `cancel` greift;
`LIBUSB_ERROR_TIMEOUT` ist kein Fehler. `LIBUSB_ERROR_ACCESS` (-3) wirft
`.accessDenied`. Endpunkte werden aus der aktiven Konfiguration ermittelt,
Rückfall auf `0x81` (IN) und `0x01` (OUT).

### InstallSession.swift
```swift
struct TransferProgress: Equatable, Sendable {
    var itemIndex: Int
    var itemName: String
    var itemSent: Int64
    var itemTotal: Int64
    var overallSent: Int64
    var overallTotal: Int64
    var bytesPerSecond: Double
}

final class InstallSession: @unchecked Sendable {
    nonisolated init(items: [InstallItem], transport: USBTransport)

    nonisolated func run(
        onLog: @Sendable @escaping (String) -> Void,
        onDevice: @Sendable @escaping (USBTransport.DeviceInfo) -> Void,
        onProgress: @Sendable @escaping (TransferProgress) -> Void,
        onItemState: @Sendable @escaping (Int, InstallItem.State) -> Void,
        cancel: @Sendable @escaping () -> Bool
    ) throws
}
```

**Ablauf — exakt so, sonst hängt die Switch:**
1. `transport.open` → `onDevice`
2. Namensliste bauen: für jeden Eintrag `displayName` + `"\n"`, UTF-8
3. **Ein** Paket lesen (`readPacket`) — Inhalt wird verworfen, nur die Magic zählt
4. `send(.ok, arg3: UInt32(tableBytes.count), arg4: 0)`, danach `write(tableBytes)`
5. Schleife: `readPacket`
   - `command == 0` (quit) → `send(.ok, 0, 0)`, Schleife verlassen, fertig
   - `command == 1` (open) → Datei mit Index `packet.arg3` übertragen
   - sonst → `send(.error, 0, 0)` und `InstallError.unexpectedCommand` werfen
6. Datei übertragen:
   - Datei öffnen, Größe bestimmen, `sendFileInfo(size:flags: TransferFlags.none)`
   - Schleife: `readPacket` → `dataOffset`/`dataSize`
     - beide `0` → `send(.ok, 0, 0)`, Datei fertig
     - sonst: an Offset springen, `dataSize` Bytes lesen,
       `send(.ok, arg3: UInt32(gelesen), arg4: CRC32C.checksum(gelesen))`,
       danach `write(daten)`
   - Fortschritt: Hochwassermarke `max(bisher, offset + gelesen)`,
     `onProgress` höchstens alle 100 ms

`onItemState` meldet `.transferring` beim Start und `.done` am Ende einer Datei.
Abbruch wirft `InstallError.cancelled`. `close()` gehört in ein `defer`.

---

## 3. Designsystem — `Sphaira Connect/Shared/`

Stilvorlage ist NovaTimePuncher unter `<reference-project>/NovaTimePuncher/Shared/`.
Übernommen wird die Machart, **nicht** die Fachlichkeit.

### DesignTokens.swift
```swift
enum Spacing { static let xs, sm, md, lg, xl, xxl: CGFloat }   // 4, 8, 12, 16, 24, 32
enum Fonts { static let title, subtitle, mono, helper, badge: Font }
enum Colors {
    static let backgroundTint: Color        // ruhiges Blau, Grundzustand
    static let backgroundTintActive: Color  // grünlich, während der Übertragung
    static let backgroundTintError: Color   // rötlich, bei Fehlern
    static let accent, success, warning, danger: Color
}
extension Color { init(hex: UInt32, alpha: Double = 1.0) }
```

### GlassEffectTheme.swift
```swift
struct GlassBackground: View { var cornerRadius: CGFloat; var tint: Color }
struct VisualEffectBlur: NSViewRepresentable    // .behindWindow, .underWindowBackground, .active
extension View { func connectCard(radius: CGFloat = 14, tint: Color = Colors.backgroundTint) -> some View }
```
**Wichtig:** Glas darf nicht in Glas geschachtelt werden. `connectCard` ist die
Gruppierung ohne Glaseffekt für Bereiche, die selbst Glaselemente enthalten.

### GlassInteractive.swift
```swift
extension View { func glassInteractive(radius: CGFloat = 14) -> some View }
```

### GlassButton.swift
```swift
enum GlassButtonKind { case clear, green, red, orange }
enum GlassButtonSize { case compact, standard }

struct GlassButton: View {
    init(_ title: String,
         systemImage: String? = nil,
         kind: GlassButtonKind = .clear,
         cornerRadius: CGFloat = 14,
         size: GlassButtonSize = .compact,
         isEnabled: Bool = true,
         action: @escaping () -> Void)
}
```
Umsetzung über `.glassEffect(Glass.regular.tint(...).interactive(), in: .rect(cornerRadius:))`.

### WindowStyleConfigurator.swift
```swift
struct WindowStyleConfigurator: NSViewRepresentable { var sizeKey: AnyHashable }
```
Transparente Titelleiste, `fullSizeContentView`, per Hintergrund verschiebbar,
Fenster passt sich animiert dem Inhalt an. Ampelknöpfe bleiben sichtbar.

---

## 4. Ansichtsmodell — `Sphaira Connect/Features/InstallerModel.swift`

```swift
@Observable
final class InstallerModel {
    enum Phase: Equatable {
        case idle
        case waitingForSwitch
        case transferring
        case finished(transferred: Int)
        case failed(String)
    }

    struct LogLine: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let text: String
    }

    var items: [InstallItem]
    var phase: Phase
    var progress: TransferProgress?
    var log: [LogLine]
    var switchAttached: Bool
    var deviceSummary: String?
    var isLogExpanded: Bool

    var totalBytes: Int64 { get }
    var canStart: Bool { get }        // Einträge vorhanden und nicht am Übertragen
    var isBusy: Bool { get }

    func add(urls: [URL])
    func remove(_ item: InstallItem)
    func clearAll()
    func start()
    func cancel()
    func startMonitoring()            // pollt alle 2 s `USBTransport.isSwitchAttached()`
    func stopMonitoring()
}
```
`start()` startet die Sitzung über `Task.detached`, damit der Hauptthread frei
bleibt; alle Rückmeldungen laufen über `Task { @MainActor in ... }` zurück.
`cancel()` setzt ein Abbruch-Flag, das die Sitzung abfragt.
Das Protokoll darf **nicht** auf dem MainActor laufen.

---

## 5. Ansichten — `Sphaira Connect/Features/Views/`

- `RootView.swift` — `ZStack`: `VisualEffectBlur`, Zustandsfarbe, Inhalt,
  `WindowStyleConfigurator`. Kopfzeile mit Titel und Statusanzeige,
  darunter Ablagefläche beziehungsweise Warteschlange, unten Fortschritt und Aktionen.
- `StatusPill.swift` — Verbindungsanzeige, Punkt plus Text, animierter Farbwechsel.
- `DropZoneView.swift` — `.onDrop` für Dateien und Ordner, Klick öffnet `NSOpenPanel`
  (mehrfach, Ordner erlaubt). Deutliche optische Rückmeldung beim Überfahren.
- `QueueListView.swift` — Liste der Einträge mit Name, Größe, Zustandssymbol,
  Entfernen-Knopf. Der gerade laufende Eintrag ist hervorgehoben.
- `ProgressPanelView.swift` — Gesamtfortschritt und aktuelle Datei, Geschwindigkeit,
  Restzeit, übertragene von Gesamtgröße.
- `LogConsoleView.swift` — aufklappbar, monospaced, automatisch nach unten gescrollt.

`ContentView.swift` wird zu einer dünnen Hülle, die `RootView` zeigt.
`Sphaira_ConnectApp.swift` bleibt schlank (`WindowGroup`, `.hiddenTitleBar`, `.contentSize`).

---

## 6. Tests — `SphairaCoreTests/` (eigenes SwiftPM-Paket neben dem Xcode-Projekt)

Getestet wird die reine Logik aus `Core/`, eingebunden per Symlink. Swift Testing
(`import Testing`, `@Test`, `#expect`). Pflichtfälle:

- CRC32C gegen die Referenzwerte, leere Eingabe, inkrementelle Gleichheit
- `Packet` Hin- und Rückumwandlung, Feldanordnung little-endian,
  `dataOffset` über die 4-GB-Grenze, verfälschtes Byte ⇒ `checksumMismatch`,
  falsche Magic ⇒ `badMagic`, zu kurz ⇒ `shortPacket`
- `ItemScanner`: Ordnerrekursion, Endungsfilter, Duplikate, stabile Reihenfolge,
  Groß- und Kleinschreibung der Endung
- `ByteFormat`: Grenzwerte, negativ, `.infinity`, `.nan`
